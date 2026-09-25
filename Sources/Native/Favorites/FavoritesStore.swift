import SwiftUI

/**
 ИЗБРАННОЕ — ЭТАП 5 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 🔴 ХРАНИТСЯ НА ТЕЛЕФОНЕ, А НЕ НА САЙТЕ. API избранного на сайте приложению неизвестно (исходников сайта под рукой
 нет), а угаданный адрес — это запись наугад в чужую таблицу. Поэтому сердечко здесь своё: с избранным сайта не
 сходится и на другой телефон не переезжает. Станет известен API — этот список превратится в кэш серверного.

 Listing только разбирается из ответа API (Decodable), поэтому на диск кладём свою маленькую запись — то, что видно
 в сетке: цена, название, обложка, город, метки. Полную карточку ListingDetailView дотянет сама по ?id=, а открытая
 карточка освежает запись: цена в избранном — последняя увиденная.

 Не больше 500 записей, новые сверху. Стирается при выходе из аккаунта (WebContainer, bye=1) вместе с лентой на диске.
 */
@MainActor
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    /// Потолок списка: старые уходят снизу. Файл при этом — пара сотен килобайт.
    static let предел = 500

    /// Номера сохранённых — сердечко на карточке спрашивает здесь.
    @Published private(set) var номера: Set<String> = []
    /// Сохранённые объявления, новые сверху, — сетка вкладки «Избранное».
    @Published private(set) var товары: [Listing] = []

    private var записи: [ИзбранноеЗапись] = []

    private init() {
        var виденные = Set<String>()
        let прочитанные = ИзбранноеФайл.прочитать()
            .sorted { $0.savedAt > $1.savedAt }
            .filter { виденные.insert($0.id).inserted }
        показать(Array(прочитанные.prefix(Self.предел)))
    }

    func есть(_ id: String) -> Bool { номера.contains(id) }

    func переключить(_ товар: Listing) {
        if номера.contains(товар.id) { убрать(товар.id) } else { добавить(товар) }
    }

    func добавить(_ товар: Listing) {
        var новые = записи.filter { $0.id != товар.id }
        новые.insert(ИзбранноеЗапись(товар), at: 0)
        if новые.count > Self.предел { новые.removeLast(новые.count - Self.предел) }
        применить(новые)
    }

    func убрать(_ id: String) {
        guard номера.contains(id) else { return }
        применить(записи.filter { $0.id != id })
    }

    /// Открыли полную карточку сохранённого — переписать цену и прочее свежими, место в списке не меняя. Пустое в
    /// ответе (нет названия, обложки) прежнее не затирает: хуже старой цены только пустая карточка.
    func освежить(_ товар: Listing) {
        guard let место = записи.firstIndex(where: { $0.id == товар.id }) else { return }
        let было = записи[место]
        var стало = ИзбранноеЗапись(товар, когда: было.savedAt)
        if стало.title.isEmpty { стало.title = было.title }
        if стало.thumb == nil { стало.thumb = было.thumb }
        if стало.city.isEmpty { стало.city = было.city }
        guard стало != было else { return }
        var новые = записи
        новые[место] = стало
        применить(новые)
    }

    /// Выход из аккаунта: избранное ушедшего следующему не показываем.
    func стереть() {
        показать([])
        ИзбранноеФайл.стереть()
    }

    private func показать(_ новые: [ИзбранноеЗапись]) {
        записи = новые
        номера = Set(новые.map(\.id))
        товары = новые.map { Listing(избранное: $0) }
    }

    private func применить(_ новые: [ИзбранноеЗапись]) {
        показать(новые)
        ИзбранноеФайл.записать(новые)
    }
}

/// Запись избранного на диске: поля строки ленты и когда сохранили. Новые поля — только необязательные (Optional),
/// иначе файл прежней версии не разберётся.
struct ИзбранноеЗапись: Codable, Equatable {
    let id: String
    var title: String
    var price: Double?
    var oldPrice: Double?
    var negotiable: Bool
    var forRent: Bool
    var rentPriceDay: Double?
    var thumb: String?
    var city: String
    var isTop: Bool
    var isNew: Bool
    var savedAt: Date

    init(_ т: Listing, когда: Date = Date()) {
        id = т.id
        title = т.title
        price = т.price
        oldPrice = т.oldPrice
        negotiable = т.negotiable
        forRent = т.forRent
        rentPriceDay = т.rentPriceDay
        thumb = т.thumb
        city = т.city
        isTop = т.isTop
        isNew = т.isNew
        savedAt = когда
    }
}

extension Listing {
    /// Объявление из записи избранного — как строка ленты: полную карточку ListingDetailView дотянет по ?id=.
    init(избранное з: ИзбранноеЗапись) {
        id = з.id
        title = з.title
        price = з.price
        oldPrice = з.oldPrice
        negotiable = з.negotiable
        forRent = з.forRent
        rentPriceDay = з.rentPriceDay
        thumb = з.thumb
        city = з.city
        isTop = з.isTop
        isNew = з.isNew
    }
}

/**
 ФАЙЛ ИЗБРАННОГО: один JSON в Application Support, вне резервной копии — как лента на диске (ListingsCache).

 Пишем не на главном потоке, но по порядку: одна последовательная очередь, иначе два быстрых нажатия могли бы лечь
 на диск наоборот, а стирание при выходе — обогнать последнюю запись и оставить файл.
 */
enum ИзбранноеФайл {
    private static let очередь = DispatchQueue(label: "kz.kliko.favorites", qos: .utility)

    private static var адрес: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-favorites.json")
    }

    /// Запись, которая не разобралась, пропускаем, а не теряем весь список.
    private struct Любая: Decodable {
        let запись: ИзбранноеЗапись?
        init(from decoder: Decoder) throws { запись = try? ИзбранноеЗапись(from: decoder) }
    }

    static func прочитать() -> [ИзбранноеЗапись] {
        guard let файл = адрес,
              let данные = try? Data(contentsOf: файл),
              let список = try? JSONDecoder().decode([Любая].self, from: данные) else { return [] }
        return список.compactMap(\.запись)
    }

    static func записать(_ список: [ИзбранноеЗапись]) {
        guard let файл = адрес, let данные = try? JSONEncoder().encode(список) else { return }
        очередь.async {
            do {
                try данные.write(to: файл, options: .atomic)
                var значения = URLResourceValues()
                значения.isExcludedFromBackup = true
                var изменяемый = файл
                try? изменяемый.setResourceValues(значения)
            } catch {
                // Диск полон — на экране избранное есть до конца запуска; следующее нажатие попробует снова.
            }
        }
    }

    static func стереть() {
        guard let файл = адрес else { return }
        очередь.async { try? FileManager.default.removeItem(at: файл) }
    }
}
