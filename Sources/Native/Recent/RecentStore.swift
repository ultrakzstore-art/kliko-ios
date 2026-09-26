import Foundation

/**
 НЕДАВНИЕ — ЭТАП 6 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»): «Вы смотрели» над лентой и
 история поиска подсказками под полем.

 🔴 ХРАНИТСЯ НА ТЕЛЕФОНЕ, как избранное (этап 5): истории просмотров и поиска у API сайта приложению неизвестно, а
 угаданный адрес хуже никакого. С сайтом не сходится и на другой телефон не переезжает.

 Просмотренное кладём той же записью, что избранное (ИзбранноеЗапись): поля строки ленты и когда видели. Полную
 карточку ListingDetailView дотянет по ?id=, а дотянувшись — освежит запись. Не больше 30 объявлений и 10 запросов,
 новые сверху, повторы поднимаются наверх, а не дублируются. Стирается при выходе из аккаунта (WebContainer, bye=1).
 */
@MainActor
final class RecentStore: ObservableObject {
    static let shared = RecentStore()

    static let пределПросмотров = 30
    static let пределЗапросов = 10
    /// Длиннее — не запрос, а вставленный текст: в подсказке он всё равно не поместится.
    static let длинаЗапроса = 100

    /// Просмотренные объявления, свежие сверху, — полоса «Вы смотрели».
    @Published private(set) var товары: [Listing] = []
    /// Отправленные запросы поиска, свежие сверху, без повторов с точностью до регистра.
    @Published private(set) var запросы: [String] = []

    private var записи: [ИзбранноеЗапись] = []

    private init() {
        guard let сохранённое = НедавниеФайл.прочитать() else { return }
        var виденные = Set<String>()
        let просмотры = сохранённое.просмотры
            .sorted { $0.savedAt > $1.savedAt }
            .filter { виденные.insert($0.id).inserted }
        записи = Array(просмотры.prefix(Self.пределПросмотров))
        товары = записи.map { Listing(избранное: $0) }

        var чистые: [String] = []
        for строка in сохранённое.запросы {
            let чистая = строка.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !чистая.isEmpty,
                  !чистые.contains(where: { $0.caseInsensitiveCompare(чистая) == .orderedSame }) else { continue }
            чистые.append(чистая)
        }
        запросы = Array(чистые.prefix(Self.пределЗапросов))
    }

    // MARK: - Просмотренные

    /// Открыли карточку — наверх полосы. Уже наверху и ничего не поменялось (вернулись в карточку из чата) — файл
    /// не переписываем.
    func запомнить(_ товар: Listing) {
        let прежняя = записи.first(where: { $0.id == товар.id })
        if let прежняя, записи.first?.id == прежняя.id,
           Self.слить(товар, с: прежняя, когда: прежняя.savedAt) == прежняя { return }
        var новые = записи.filter { $0.id != товар.id }
        новые.insert(Self.слить(товар, с: прежняя, когда: Date()), at: 0)
        if новые.count > Self.пределПросмотров { новые.removeLast(новые.count - Self.пределПросмотров) }
        применить(просмотры: новые)
    }

    /// Дотянулась полная карточка — свежая цена и обложка, место в полосе прежнее. Записи нет (полосу очистили, пока
    /// карточка грузилась) — не возвращаем: человек её только что убрал.
    func освежить(_ товар: Listing) {
        guard let место = записи.firstIndex(where: { $0.id == товар.id }) else { return }
        let было = записи[место]
        let стало = Self.слить(товар, с: было, когда: было.savedAt)
        guard стало != было else { return }
        var новые = записи
        новые[место] = стало
        применить(просмотры: новые)
    }

    /// Очистили «Вы смотрели» — и из поиска iPhone (этап 10): там те же просмотры, и вычищенная история не должна
    /// всплывать в поиске телефона.
    func очиститьПросмотры() {
        ПоискТелефона.стереть()
        guard !записи.isEmpty else { return }
        применить(просмотры: [])
    }

    // MARK: - История поиска

    /// Отправили поиск — запрос наверх истории. Тот же запрос в другом регистре заменяется новым написанием.
    func запомнитьЗапрос(_ текст: String) {
        let чистый = String(текст.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.длинаЗапроса))
        guard !чистый.isEmpty else { return }
        var новые = запросы.filter { $0.caseInsensitiveCompare(чистый) != .orderedSame }
        новые.insert(чистый, at: 0)
        if новые.count > Self.пределЗапросов { новые.removeLast(новые.count - Self.пределЗапросов) }
        guard новые != запросы else { return }
        запросы = новые
        сохранить()
    }

    /// «×» у строки «Вы искали» поиска как на сайте (mkSovRmRecent): один запрос, без учёта регистра.
    func забытьЗапрос(_ текст: String) {
        let новые = запросы.filter { $0.caseInsensitiveCompare(текст) != .orderedSame }
        guard новые != запросы else { return }
        запросы = новые
        сохранить()
    }

    func очиститьЗапросы() {
        guard !запросы.isEmpty else { return }
        запросы = []
        сохранить()
    }

    // MARK: - Выход

    /// Выход из аккаунта: что смотрел и искал ушедший, следующему не показываем.
    func стереть() {
        записи = []
        товары = []
        запросы = []
        НедавниеФайл.стереть()
    }

    // MARK: - Внутреннее

    /// Свежая запись поверх прежней: пустое в ответе (нет названия, обложки, города) прежнее не затирает — как в
    /// избранном.
    private static func слить(_ товар: Listing, с прежняя: ИзбранноеЗапись?, когда: Date) -> ИзбранноеЗапись {
        var стало = ИзбранноеЗапись(товар, когда: когда)
        if let прежняя {
            if стало.title.isEmpty { стало.title = прежняя.title }
            if стало.thumb == nil { стало.thumb = прежняя.thumb }
            if стало.city.isEmpty { стало.city = прежняя.city }
        }
        return стало
    }

    private func применить(просмотры новые: [ИзбранноеЗапись]) {
        записи = новые
        товары = новые.map { Listing(избранное: $0) }
        сохранить()
    }

    private func сохранить() {
        НедавниеФайл.записать(НедавниеСодержимое(просмотры: записи, запросы: запросы))
    }
}

/// Файл недавнего целиком: просмотренное и запросы. Новые поля — только необязательные, иначе файл прежней версии
/// не разберётся.
struct НедавниеСодержимое: Codable {
    var просмотры: [ИзбранноеЗапись]
    var запросы: [String]

    enum CodingKeys: String, CodingKey {
        case просмотры = "viewed"
        case запросы = "queries"
    }

    init(просмотры: [ИзбранноеЗапись], запросы: [String]) {
        self.просмотры = просмотры
        self.запросы = запросы
    }

    /// Запись, которая не разобралась, пропускаем, а не теряем всю полосу.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        просмотры = ((try? c.decode([ЛюбаяНедавняя].self, forKey: .просмотры)) ?? []).compactMap(\.запись)
        запросы = (try? c.decode([String].self, forKey: .запросы)) ?? []
    }
}

private struct ЛюбаяНедавняя: Decodable {
    let запись: ИзбранноеЗапись?
    init(from decoder: Decoder) throws { запись = try? ИзбранноеЗапись(from: decoder) }
}

/**
 ФАЙЛ НЕДАВНЕГО: один JSON в Application Support, вне резервной копии — как избранное (ИзбранноеФайл).

 Пишем не на главном потоке, но по порядку: одна последовательная очередь, чтобы стирание при выходе не обогнало
 последнюю запись и не оставило файл.
 */
enum НедавниеФайл {
    private static let очередь = DispatchQueue(label: "kz.kliko.recent", qos: .utility)

    private static var адрес: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-recent.json")
    }

    static func прочитать() -> НедавниеСодержимое? {
        guard let файл = адрес, let данные = try? Data(contentsOf: файл) else { return nil }
        return try? JSONDecoder().decode(НедавниеСодержимое.self, from: данные)
    }

    static func записать(_ содержимое: НедавниеСодержимое) {
        guard let файл = адрес, let данные = try? JSONEncoder().encode(содержимое) else { return }
        очередь.async {
            do {
                try данные.write(to: файл, options: .atomic)
                var значения = URLResourceValues()
                значения.isExcludedFromBackup = true
                var изменяемый = файл
                try? изменяемый.setResourceValues(значения)
            } catch {
                // Диск полон — полоса есть до конца запуска; следующий просмотр попробует снова.
            }
        }
    }

    static func стереть() {
        guard let файл = адрес else { return }
        очередь.async { try? FileManager.default.removeItem(at: файл) }
    }
}
