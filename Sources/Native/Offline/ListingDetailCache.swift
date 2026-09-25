import Foundation
import Combine

/**
 ОБЪЯВЛЕНИЯ БЕЗ СЕТИ — ЭТАП 13 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующие этапы»).

 Сохранённое в избранном (этап 5) и недавно открытое (этап 6) открывается полной карточкой и без связи: ответ
 GET /api/listings.php?id= ({ok, item}) целиком лежит на телефоне, и ListingDetailView, не дотянувшись до сайта,
 показывает его с пометкой «Сохранённая копия · когда». Сеть есть — всегда свежий ответ, копия только освежается.

 Храним сырой ответ, а не свою запись: его разбирает тот же ListingEnvelope, что живой ответ, — новое поле карточки
 появится и в копии, без второго формата на диске.

 🔴 КОПИЯ — ТОЛЬКО ВМЕСТО ТИШИНЫ. Нет связи или сайт лёг (5xx) — показываем копию. Сайт ответил по существу (404 —
 сняли с продажи, 403, не тот ответ) — копией не подменяем: старая копия спорила бы с сайтом.

 🔴 ТОЛЬКО ИЗБРАННОЕ И «ВЫ СМОТРЕЛИ». Копия живёт, пока номер есть в одном из них: сняли сердечко, очистили «Вы
 смотрели» — файл уходит с диска при ближайшей подрезке (через 2 с). Не больше 60 файлов, лишние — самые давние.
 Стирается при выходе из аккаунта (WebContainer, bye=1). Сервера это не касается: тот же ?id=, что у карточки.
 */
enum ListingDetailCache {
    /// Потолок файлов. Карточка — несколько килобайт текста (фото в ней — адресами), шестьдесят — меньше мегабайта.
    static let предел = 60
    /// Больше — уже не карточка, а что-то не то (страница ошибки, лента): не храним.
    static let размер = 512 * 1024

    /// Копия с диска и когда она легла.
    struct Копия {
        let товар: Listing
        let когда: Date
    }

    /// Запись, подрезка и стирание — по порядку, одной очередью: стирание при выходе не обгонит последнюю запись.
    private static let очередь = DispatchQueue(label: "kz.kliko.listing-details", qos: .utility)
    private static let замок = NSLock()
    /// Поколение копий: выход из аккаунта его меняет. Только под замком.
    private static var счётчик = 0
    /// Что можно в имени файла. Номер приходит от сайта: «../» в нём не должен вывести запись из папки.
    private static let допустимые: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    /// Одна папка в Application Support, вне резервной копии, файл на объявление: <номер>.json.
    private static var папка: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-listing-details", isDirectory: true)
    }

    /// Поколение сейчас. Его берут ДО запроса и отдают в записать(): ответ, опоздавший за выходом из аккаунта, на
    /// диск уже не ляжет.
    static var поколение: Int {
        замок.lock()
        defer { замок.unlock() }
        return счётчик
    }

    private static func имяФайла(_ id: String) -> String? {
        guard !id.isEmpty, id.count <= 64, id.allSatisfy({ допустимые.contains($0) }) else { return nil }
        return id + ".json"
    }

    /// Есть ли копия. Без очереди: запись, которая ещё в пути, в худшем случае обернётся одним лишним запросом.
    static func есть(_ id: String) -> Bool {
        guard let имя = имяФайла(id), let корень = папка else { return false }
        return FileManager.default.fileExists(atPath: корень.appendingPathComponent(имя).path)
    }

    static func записать(_ данные: Data, id: String, поколение взятое: Int) {
        guard данные.count <= размер, let имя = имяФайла(id), let корень = папка else { return }
        очередь.async {
            guard взятое == ListingDetailCache.поколение else { return }
            do {
                try FileManager.default.createDirectory(at: корень, withIntermediateDirectories: true)
                var значения = URLResourceValues()
                значения.isExcludedFromBackup = true
                var изменяемая = корень
                try? изменяемая.setResourceValues(значения)
                try данные.write(to: корень.appendingPathComponent(имя), options: .atomic)
            } catch {
                // Диск полон — копия удобство, а не обязанность: со связью карточка откроется и так.
            }
        }
    }

    /// Копия объявления или nil. Читаем на той же очереди — после записей, поставленных раньше.
    static func прочитать(_ id: String) async -> Копия? {
        guard let имя = имяФайла(id), let корень = папка else { return nil }
        let файл = корень.appendingPathComponent(имя)
        return await withCheckedContinuation { (готово: CheckedContinuation<Копия?, Never>) in
            очередь.async {
                guard let данные = try? Data(contentsOf: файл),
                      let конверт = try? JSONDecoder().decode(ListingEnvelope.self, from: данные) else {
                    готово.resume(returning: nil)
                    return
                }
                let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey])
                готово.resume(returning: Копия(товар: конверт.item, когда: свойства?.contentModificationDate ?? Date()))
            }
        }
    }

    /// Оставить копии только этих номеров и не больше предела — лишние самые давние (по времени записи).
    static func оставить(_ нужные: Set<String>) {
        guard let корень = папка else { return }
        очередь.async {
            let диск = FileManager.default
            guard let файлы = try? диск.contentsOfDirectory(at: корень,
                                                           includingPropertiesForKeys: [.contentModificationDateKey],
                                                           options: [.skipsHiddenFiles]) else { return }
            var живые: [(файл: URL, когда: Date)] = []
            for файл in файлы {
                let номер = файл.deletingPathExtension().lastPathComponent
                guard файл.pathExtension == "json", нужные.contains(номер) else {
                    try? диск.removeItem(at: файл)
                    continue
                }
                let свойства = try? файл.resourceValues(forKeys: [.contentModificationDateKey])
                живые.append((файл: файл, когда: свойства?.contentModificationDate ?? .distantPast))
            }
            guard живые.count > ListingDetailCache.предел else { return }
            let давние = живые.sorted { $0.когда > $1.когда }.dropFirst(ListingDetailCache.предел)
            for давний in давние { try? диск.removeItem(at: давний.файл) }
        }
    }

    /// Выход из аккаунта или выключенный рубильник: все копии долой, а ответы, что ещё в пути, — мимо диска.
    static func стереть() {
        замок.lock()
        счётчик += 1
        замок.unlock()
        guard let корень = папка else { return }
        очередь.async { try? FileManager.default.removeItem(at: корень) }
    }

    /// Показывать ли копию вместо «не удалось»: нет связи или сайт лёг (5xx) — да; ответ сайта по существу — нет.
    static func подходитКопия(после ошибка: Error) -> Bool {
        guard let своя = ошибка as? ListingsAPI.Ошибка else { return false }
        switch своя {
        case .сеть:              return true
        case .статус(let код):   return код >= 500
        case .разбор:            return false
        }
    }
}

/**
 КТО КЛАДЁТ И УБИРАЕТ КОПИИ (этап 13). Следит за избранным и «Вы смотрели» (Combine, как Передача за лентой):

   · любое их изменение — подрезка копий через 2 с после последнего (пачка изменений — одна подрезка);
   · новое сердечко на объявлении без копии — один фоновый запрос ?id=. По одному за раз, в порядке сердечек, и
     без повторов: не вышло (нет связи) — копии нет до открытия карточки или следующего сердечка. Десять сердечек
     подряд — десять запросов друг за другом, а не буря.

 Карточка кладёт копию сама (ListingDetailView → запомнить), когда дотянулась полная.
 */
@MainActor
final class КарточкиБезСети {
    static let shared = КарточкиБезСети()

    private var подписки: Set<AnyCancellable> = []
    /// Номера избранного при прошлом изменении: новые сердечки — разница с ними. nil — ещё ничего не приходило: первое
    /// значение Combine отдаёт при подписке, и это «так было», а не «добавили».
    private var прежниеИзбранные: Set<String>?
    /// Ждут фоновой загрузки, по порядку сердечек.
    private var ждут: [String] = []
    /// Качается сейчас; nil — ничего.
    private var качается: String?
    /// Очередь ждущих уже разбирается — второй разборщик не нужен.
    private var разбираем = false
    private var подрезка: Task<Void, Never>?

    private init() {}

    /// Запуск приложения (SceneDelegate). Рубильник выключен — копии прежних запусков стираем, а не ждём выхода.
    func запустить() {
        guard Config.карточкиБезСети else {
            ListingDetailCache.стереть()
            return
        }
        guard подписки.isEmpty else { return }
        FavoritesStore.shared.$номера
            .sink { [weak self] номера in self?.избранноеСтало(номера) }
            .store(in: &подписки)
        RecentStore.shared.$товары
            .map { (товары: [Listing]) -> [String] in товары.map { $0.id } }
            .removeDuplicates()
            .sink { [weak self] _ in self?.подрезатьПозже() }
            .store(in: &подписки)
    }

    /// Ответ ?id= на диск, если копия ещё нужна: номер в избранном или в «Вы смотрели». `открыта` — ответ пришёл
    /// открытой карточке: при недавних она сама ляжет в «Вы смотрели» (ListingDetailView), даже если ещё не легла —
    /// открытое по ссылке попадает туда только с полной карточкой. `поколение` — взятое до запроса.
    func запомнить(_ сырое: Data, id: String, поколение: Int, открыта: Bool = false) {
        guard Config.карточкиБезСети, (открыта && Config.недавние) || нужные().contains(id) else { return }
        ListingDetailCache.записать(сырое, id: id, поколение: поколение)
        подрезатьПозже()
    }

    /// Подрезать копии по избранному и недавним — через 2 с после последнего изменения. К этому времени открытая
    /// по ссылке карточка уже в «Вы смотрели», и её свежая копия не уйдёт.
    func подрезатьПозже() {
        подрезка?.cancel()
        подрезка = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            ListingDetailCache.оставить(self.нужные())
        }
    }

    // MARK: - Внутреннее

    /// Чьи копии держим: избранное и «Вы смотрели» — только включённые рубильниками.
    private func нужные() -> Set<String> {
        var номера = Set<String>()
        if Config.избранное { номера.formUnion(FavoritesStore.shared.номера) }
        if Config.недавние { номера.formUnion(RecentStore.shared.товары.map { $0.id }) }
        return номера
    }

    /// Избранное изменилось. Combine присылает новое значение до того, как оно легло в хранилище (willSet), поэтому
    /// разницу считаем с присланным, а само хранилище читаем позже — в подрезке и перед запросом.
    private func избранноеСтало(_ номера: Set<String>) {
        defer { прежниеИзбранные = номера }
        подрезатьПозже()
        guard Config.избранное, let были = прежниеИзбранные else { return }
        for номер in номера.subtracting(были) { скачатьПотом(номер) }
    }

    private func скачатьПотом(_ id: String) {
        guard качается != id, !ждут.contains(id), !ListingDetailCache.есть(id) else { return }
        ждут.append(id)
        guard !разбираем else { return }
        разбираем = true
        Task(priority: .utility) { await self.разобратьОчередь() }
    }

    private func разобратьОчередь() async {
        while !ждут.isEmpty {
            let id = ждут.removeFirst()
            /* Сердечко успели снять или карточку успели открыть, пока номер ждал, — не качаем. */
            guard FavoritesStore.shared.есть(id), !ListingDetailCache.есть(id) else { continue }
            качается = id
            let взятое = ListingDetailCache.поколение
            if let ответ = try? await ListingsAPI.объявлениеСОтветом(id), ответ.товар.id == id {
                запомнить(ответ.сырое, id: id, поколение: взятое)
            }
            качается = nil
        }
        разбираем = false
    }
}
