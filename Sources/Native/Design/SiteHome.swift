import SwiftUI
import UIKit

/**
 ГЛАВНАЯ КАК НА САЙТЕ — ЭТАП 26 (владелец 25.09.2026: «приложение должно быть почти 100% похоже на сайт»).

 Образец — секция #mk-home главной kliko.kz на телефоне (css/marketplace-home.min.css, js/marketplace-home.min.js):
 под шапкой сетка .mh-hub — баннер Kliko на две строки слева и цветные плитки разделов («Авто», «6 предложений»,
 картинка в углу), ниже «Рекомендуем» и по ряду на раздел: «• Электроника 26  Все ›» и карточки, листающиеся вбок.
 Нажатие на плитку или «Все» — та же лента с разделом (FeedModel.выбратьРаздел), что полоса разделов этапа 1.

 🔴 ДАННЫЕ. Сайт берёт ряды одним запросом api/listings.php?home=1 (verts[k].n и items), но этот ответ приложению не
 проверен. Проверенный — тот же запрос ленты с cat=<раздел>&per=10 (этап 7 «Похожие» ходит так же): по запросу на
 раздел, параллельно и с куками веб-сессии, число на плитке и в ряду — поле total ответа. Раздел без объявлений —
 без ряда; запрос не прошёл — ряда нет, остальное на месте.
 Этап 34 (владелец 25.09.2026): теперь — тем самым одним запросом home=1, разобранным терпимо (Native/Home/HomeAPI.swift),
 с VIP и копией на диске; запросы по разделам остались запасным путём и для выключенного Config.главнаяОдинЗапрос.

 Этап 49 (владелец 26.09.2026: «всё одно и то же, просто код разный»): как у сайта сейчас —
   · разделов семь, вместе с «Работой» (MK_HOME_V): сервер тасует их и рисует первые шесть, скрипт тасует шесть ещё раз
     при каждом входе на главную (_mhHubShuffle) — поэтому здесь шесть случайных из семи в случайном порядке, заново при
     каждом возвращении на главную; первые две после баннера — сплошные;
   · число на плитке — только n ответа (_mhTiles): у «Работы» — jobs.n и «вакансий»; ноль — у сплошной подпись раздела
     («Вакансии и резюме»), у светлой пусто; пока ответа нет — мерцающая полоска;
   · слайдов баннера четыре (перенос, продажа, торг, «Деньги ждут у нас»), порядок тасуется раз за загрузку, нажатие
     открывает лист со сведениями (hpOpen) — кнопки листа ведут на страницы сайта, денег нигде нет;
   · ряд «Работа» — вакансии jobs.items (mhCardJob), их открывает сайт: своего экрана вакансий у приложения нет;
   · порядок рядов тасуется при каждой загрузке (mkHomeRender), ширина карточки — (W − 32 − 20) / 2,2, как .mh-rs.
 */
struct РазделГлавной: Identifiable, Hashable {
    /// Ключ раздела — cat= у api/listings.php и k в снимке главной (FeedSnapshot).
    let ключ: String
    /// Краска раздела — --vc плитки, «#DC2626».
    let краска: UInt32

    var id: String { ключ }

    /// Картинка плитки с сайта — MK_CATPIC: /img/cat-<раздел>.webp, 320 px. Малая (-s, 200 px) на экране 3× мылится.
    var картинка: URL? { Config.url("/img/cat-\(ключ).webp?v=1789893153") }

    /// «Работа»: её объявления — вакансии (api/jobs.php у сайта), нативного экрана для них нет — открывает сайт.
    var вакансии: Bool { ключ == "jobs" }

    /// Значок раздела в полосе разделов под шапкой (.mk-vchip-ic) — ближайший SF Symbol к SVG сайта.
    var значок: String {
        switch ключ {
        case "transport": return "car"
        case "realty": return "building.2"
        case "services": return "wrench.and.screwdriver"
        case "electronics": return "desktopcomputer"
        case "goods": return "bag"
        case "animals": return "pawprint"
        case "jobs": return "briefcase"
        default: return "square.grid.2x2"
        }
    }

    /// MK_HOME_V сайта целиком, в порядке MH_ORDER (порядок рядов до тасовки): семь разделов вместе с «Работой».
    static let все: [РазделГлавной] = [
        РазделГлавной(ключ: "transport", краска: 0xDC2626),
        РазделГлавной(ключ: "realty", краска: 0x059669),
        РазделГлавной(ключ: "electronics", краска: 0x2563EB),
        РазделГлавной(ключ: "jobs", краска: 0x4F46E5),
        РазделГлавной(ключ: "services", краска: 0x0D9488),
        РазделГлавной(ключ: "goods", краска: 0xD97706),
        РазделГлавной(ключ: "animals", краска: 0x7C3AED)
    ]

    /// Порядок полосы разделов под шапкой (#mk-vrail): Авто, Недвижимость, Услуги, Электроника, Товары, Животные, Работа.
    static let полоса: [РазделГлавной] = ["transport", "realty", "services", "electronics", "goods", "animals", "jobs"]
        .compactMap { ключ in все.first { $0.ключ == ключ } }

    static func с(ключом ключ: String) -> РазделГлавной? {
        все.first { $0.ключ == ключ }
    }
}

/// Ряды «Рекомендуем» и числа на плитках. Живут, пока жива лента: вернулись со страницы сайта — те же ряды.
///
/// Этап 34: при Config.главнаяОдинЗапрос — одним запросом home=1, как у сайта (ГлавнаяAPI, Native/Home/HomeAPI.swift),
/// с VIP, total и копией на диске; ответ не того вида или выбран район — по запросу на раздел, как на этапе 26.
@MainActor
final class ПодборкиГлавной: ObservableObject {
    struct Ряд: Identifiable {
        let раздел: РазделГлавной
        let товары: [Listing]
        /// Этап 49: ряд «Работа» — вакансии вместо объявлений.
        let вакансии: [ВакансияГлавной]
        /// Всего объявлений в разделе (total, с этапа 34 — verts[раздел].n); nil — сайт не прислал.
        let всего: Int?
        var id: String { раздел.ключ }
    }

    @Published private(set) var ряды: [Ряд] = []
    /// «N предложений» на плитках — только больше нуля.
    @Published private(set) var счёт: [String: Int] = [:]
    /// Этап 49: ответ уже был (или не придёт): до него у плиток вместо числа — мерцающая полоска (.mh-tile-n:empty).
    @Published private(set) var числаГотовы = false
    @Published private(set) var грузим = false
    /// Ни один запрос не прошёл, а показать нечего — строка «Не удалось загрузить подборки» с «Повторить».
    @Published private(set) var неудача = false
    /// Этап 34: vip[] ответа home=1 — блок «VIP-объявления» среди рядов. Пусто — блока нет.
    @Published private(set) var вип: [Listing] = []
    /// Этап 34: total ответа home=1 — число на «Показать все объявления». nil — не пришло.
    @Published private(set) var всегоОбъявлений: Int?
    /// Этап 34: на экране главная не для нынешнего запроса — копия с диска или прежнего места, а свежая не пришла:
    /// «Показано, как было в последний раз» с «Повторить» (.mh-stale сайта).
    @Published private(set) var устарело = false
    /// Этап 49: шесть плиток из семи в случайном порядке (MK_HOME_V сервера и _mhHubShuffle сайта).
    @Published private(set) var плитки: [РазделГлавной] = ПодборкиГлавной.новыеПлитки()
    /// Этап 49: названия подразделов у карточек техники (_mxKind: mkCatName раздела) — со страницы сайта, на её языке.
    @Published private(set) var подразделы: [String: String] = [:]
    /// Этап 49: слайды баннера в случайном порядке — mhBannerInit тасует их раз за загрузку страницы.
    let слайды: [БаннерГлавной.Слайд] = БаннерГлавной.слайды.shuffled()

    /// Этап 32: пока ряды грузились, их попросили снова (сменили город) — по окончании загрузить ещё раз, уже для него.
    private var ещёРаз = false

    /// Этап 34: чья главная на экране — ключ запроса home=1 (ГлавнаяAPI.ключ); nil — ряды по разделам или ничего.
    private var показанныйКлюч: String?
    /// Этап 34: на экране копия с диска, свежая ещё не приходила.
    private var показаноСДиска = false
    /// Этап 34: home=1 в этот запуск ответил не тем видом — дальше по разделам (этап 26), не спрашивая его снова.
    private var одинЗапросНеПонят = false
    /// Порядок рядов — MH_ORDER, перемешанный: mkHomeRender тасует его при каждой отрисовке. Этап 49: заново при каждой
    /// загрузке; копия с диска и свежий ответ одной загрузки идут в одном порядке — ряды не прыгают под пальцем дважды.
    private var порядок: [РазделГлавной] = РазделГлавной.все.shuffled()
    /// Где среди рядов VIP — у сайта после 1 + floor(random · рядов) рядов; случайная доля — тоже на загрузку.
    private var доляВИП = Double.random(in: 0..<1)
    /// Больше карточек в ряду не берём — сайт показывает все, что прислано, это страховка от неожиданно длинного ответа.
    private static let вРяду = 30

    init() {
        /* Этап 34 выключен — копия главной прежних запусков больше не нужна. */
        if !Config.главнаяОдинЗапрос { КэшГлавной.стереть() }
    }

    /// Шесть из семи в случайном порядке.
    private static func новыеПлитки() -> [РазделГлавной] {
        Array(РазделГлавной.все.shuffled().prefix(6))
    }

    /// После скольких рядов стоит VIP (1…число рядов; у сайта d ≥ рядов — в конец). Рядов нет — 0: VIP сам по себе.
    var местоВИП: Int {
        guard !ряды.isEmpty else { return 0 }
        return min(ряды.count, 1 + Int(доляВИП * Double(ряды.count)))
    }

    /// .mh-busy сайта: главная обновляется поверх уже показанной — ряды и VIP притушены.
    var обновляем: Bool { грузим && (!ряды.isEmpty || !вип.isEmpty) }

    /// Этап 49: снова на главной — плитки в новом случайном порядке (_mhHubShuffle при входе на главную). Ряды сайт при
    /// этом не перерисовывает — они того же места и уже на экране.
    func перетасовать() {
        плитки = Self.новыеПлитки()
    }

    /// Первый показ: ряды уже есть — второй раз не просим. Этап 34: на экране копия с диска, а свежую так и не спросили
    /// до конца (лента ушла с экрана посреди запроса, и .task его отменил), — спросить; не пришла по-настоящему
    /// («Показано, как было в последний раз») — не спрашиваем сами, для этого «Повторить».
    func начать() async {
        let пусто = ряды.isEmpty && вип.isEmpty
        guard пусто || (показаноСДиска && !устарело), !грузим else { return }
        await загрузить()
    }

    /// Все разделы разом, с первой страницы. Не пришло ничего — прежние ряды остаются на экране.
    func загрузить() async {
        guard !грузим else {
            ещёРаз = true
            return
        }
        грузим = true
        defer { грузим = false }
        repeat {
            ещёРаз = false
            порядок = РазделГлавной.все.shuffled()
            доляВИП = Double.random(in: 0..<1)
            await загрузитьРаз()
        } while ещёРаз && !Task.isCancelled
    }

    /// Один проход — для города, выбранного на его начало (этап 32): числа на плитках и ряды — его. Этап 34: одним
    /// запросом home=1, если можно; ответ не того вида — тут же по разделам.
    private func загрузитьРаз() async {
        let где = ГдеИскать.сохранённое()
        if ГлавнаяAPI.годится(где) && !одинЗапросНеПонят {
            if await загрузитьОднимЗапросом(где) { return }
        }
        await загрузитьПоРазделам(где)
    }

    // MARK: - Одним запросом (этап 34)

    /// Главная ответом home=1 — mkHomeLoad сайта. false — ответ не того вида: пусть грузит по разделам.
    private func загрузитьОднимЗапросом(_ где: ГдеИскать) async -> Bool {
        let ключ = ГлавнаяAPI.ключ(где)
        /* Как _mhCacheGet: на экране не эта главная — сначала копия с диска для того же места, если свежая. */
        if показанныйКлюч != ключ, let сохранённый = await КэшГлавной.прочитатьВФоне(ключ) {
            guard !Task.isCancelled else { return true }
            показать(сохранённый, ключ: ключ, сДиска: true)
        }
        let куки = await SiteSession.куки()
        let ответ: ОтветГлавной
        let сырое: Data
        do {
            (ответ, сырое) = try await ГлавнаяAPI.загрузить(где, куки: куки)
        } catch ListingsAPI.Ошибка.разбор {
            одинЗапросНеПонят = true
            return false
        } catch {
            if !Task.isCancelled { неПришло(ключ) }
            return true
        }
        guard !Task.isCancelled else { return true }
        guard ответ.ok else {
            неПришло(ключ)
            return true
        }
        показать(ответ, ключ: ключ, сДиска: false)
        await КэшГлавной.сохранитьВФоне(сырое, ключ: ключ)
        return true
    }

    /// Ответ home=1 — на экран (mkHomeRender): ряды в перемешанном порядке, пустых разделов нет, ТОП в начале ряда
    /// вперемешку. Этап 49: числа плиток и рядов — только n ответа (_mhTiles, _mhRow): у сайта других нет; у «Работы» —
    /// jobs{items, n}.
    private func показать(_ ответ: ОтветГлавной, ключ: String, сДиска: Bool) {
        var новые: [Ряд] = []
        var счётПлиток: [String: Int] = [:]
        for раздел in порядок {
            if раздел.вакансии {
                if let всего = ответ.вакансийВсего, всего > 0 { счётПлиток[раздел.ключ] = всего }
                if !ответ.вакансии.isEmpty {
                    новые.append(Ряд(раздел: раздел, товары: [], вакансии: Self.вакансииБезПовторов(ответ.вакансии),
                                     всего: ответ.вакансийВсего))
                }
                continue
            }
            let сРаздела = ответ.разделы[раздел.ключ]
            let всегоВРазделе = сРаздела?.всего
            if let всегоВРазделе, всегоВРазделе > 0 { счётПлиток[раздел.ключ] = всегоВРазделе }
            if let сРаздела, !сРаздела.товары.isEmpty {
                let товары = Self.топВперемешку(Self.безПовторов(Array(сРаздела.товары.prefix(Self.вРяду))))
                новые.append(Ряд(раздел: раздел, товары: товары, вакансии: [], всего: всегоВРазделе))
            }
        }
        ряды = новые
        счёт = счётПлиток
        числаГотовы = true
        вип = Self.безПовторов(ответ.вип)
        всегоОбъявлений = ответ.всего
        показанныйКлюч = ключ
        показаноСДиска = сДиска
        неудача = false
        устарело = false
        спроситьПодразделы()
    }

    /// Свежая главная не пришла (_mhFail): показать нечего — «Не удалось загрузить подборки»; на экране копия с диска или
    /// главная прежнего места — «Показано, как было в последний раз»; свежая этого же места — ничего, как у сайта.
    private func неПришло(_ ключ: String) {
        if ряды.isEmpty && вип.isEmpty {
            неудача = true
            устарело = false
            числаГотовы = true              // _mhTiles(null): у плиток подписи вместо мерцания
        } else {
            устарело = показаноСДиска || показанныйКлюч != ключ
        }
    }

    /// _mhShuffleTops сайта: ТОП-объявления, идущие подряд с начала ряда, — в случайном порядке, если их хотя бы два.
    private static func топВперемешку(_ товары: [Listing]) -> [Listing] {
        var сколько = 0
        while сколько < товары.count && товары[сколько].isTop { сколько += 1 }
        guard сколько >= 2 else { return товары }
        return Array(товары[..<сколько]).shuffled() + Array(товары[сколько...])
    }

    /// Одно объявление дважды в ряду — два одинаковых id в ForEach, сломанная прокрутка; оставляем первое.
    private static func безПовторов(_ товары: [Listing]) -> [Listing] {
        var были = Set<String>()
        return товары.filter { товар in были.insert(товар.id).inserted }
    }

    private static func вакансииБезПовторов(_ вакансии: [ВакансияГлавной]) -> [ВакансияГлавной] {
        var были = Set<String>()
        return Array(вакансии.filter { были.insert($0.id).inserted }.prefix(вРяду))
    }

    /// Этап 49: подпись подраздела у карточек техники (_mxKind — mkCatName раздела объявления) — у загруженной страницы
    /// сайта, на её языке. Страница ещё не загружена — спросим, когда догрузится (NativeFeedView зовёт снова).
    func спроситьПодразделы() {
        var нужны = Set<String>()
        for ряд in ряды where ряд.раздел.ключ == "electronics" {
            for товар in ряд.товары {
                if let раздел = товар.категория, подразделы[раздел] == nil { нужны.insert(раздел) }
            }
        }
        for товар in вип where ВидКарточкиГлавной(товара: товар) == .техника {
            if let раздел = товар.категория, подразделы[раздел] == nil { нужны.insert(раздел) }
        }
        guard !нужны.isEmpty else { return }
        let список = Array(нужны)
        Task { @MainActor [weak self] in
            let имена = await SiteSession.названияРазделов(список)
            guard let self, !имена.isEmpty else { return }
            /* Имя, совпадающее с ключом, сайт не показывает (r !== n в _mxKind). */
            var годные: [String: String] = [:]
            for (раздел, имя) in имена where имя != раздел { годные[раздел] = имя }
            self.подразделы.merge(годные) { _, новое in новое }
        }
    }

    // MARK: - По разделам (этап 26)

    /// Ряды запросами по разделам — как на этапе 26: без рубильника этапа 34 и когда home=1 не понят. Вакансий так не
    /// взять — у них другой ответ (jobs), ряда «Работа» тогда нет.
    private func загрузитьПоРазделам(_ где: ГдеИскать) async {
        let куки = await SiteSession.куки()
        let ответы = await Self.запросить(куки: куки, где: где)
        guard !Task.isCancelled else { return }
        guard !ответы.isEmpty else {
            неудача = ряды.isEmpty && вип.isEmpty
            /* Этап 34: на экране осталась копия главной с диска — сказать, что она не свежая. */
            устарело = показаноСДиска && !неудача
            if неудача { числаГотовы = true }
            return
        }
        var новые: [Ряд] = []
        var числа: [String: Int] = [:]
        for раздел in порядок where !раздел.вакансии {
            guard let страница = ответы[раздел.ключ] else { continue }
            if let всего = страница.total, всего > 0 { числа[раздел.ключ] = всего }
            if !страница.items.isEmpty {
                новые.append(Ряд(раздел: раздел, товары: Array(страница.items.prefix(10)), вакансии: [],
                                 всего: страница.total))
            }
        }
        неудача = false
        ряды = новые
        счёт = числа
        числаГотовы = true
        /* Этап 34: по разделам VIP и total не приходят, и это уже не главная home=1 — ни её места, ни «как было». */
        вип = []
        всегоОбъявлений = nil
        показанныйКлюч = nil
        показаноСДиска = false
        устарело = false
        спроситьПодразделы()
    }

    /// Первая страница каждого раздела: api/listings.php?cat=<раздел>&per=10 (и город этапа 32) с куками, взятыми один раз.
    nonisolated private static func запросить(куки: [String: String], где: ГдеИскать) async -> [String: ListingsPage] {
        await withTaskGroup(of: ОтветРяда.self, returning: [String: ListingsPage].self) { группа in
            for раздел in РазделГлавной.все where раздел.ключ != "jobs" {
                let ключ = раздел.ключ
                группа.addTask {
                    var з = ListingsAPI.Запрос()
                    з.per = 10
                    з.cat = ключ
                    з.где = где
                    let страница = try? await ListingsAPI.загрузить(з, куки: куки).страница
                    return ОтветРяда(ключ: ключ, страница: страница)
                }
            }
            var итог: [String: ListingsPage] = [:]
            while let ответ = await группа.next() {
                if let страница = ответ.страница { итог[ответ.ключ] = страница }
            }
            return итог
        }
    }
}

/// Ответ на один раздел; nil — запрос не прошёл.
private struct ОтветРяда: @unchecked Sendable {
    let ключ: String
    let страница: ListingsPage?
}

// MARK: - Сетка плиток (.mh-hub)

/**
 Сетка главной на телефоне (@media max-width:599px): баннер — две верхние строки слева, справа две плитки «потяжелее»
 (is-prio, сплошная краска), ниже две строки по две светлые плитки. Высота верхних строк — clamp(86px, …, 118px),
 нижних — 88px, зазор — --vx-gap (10px). Этап 49: плитки — шесть из семи в порядке, который дала ПодборкиГлавной.
 */
struct ПлиткиГлавной: View {
    let разделы: [РазделГлавной]
    let слайды: [БаннерГлавной.Слайд]
    let название: (РазделГлавной) -> String
    let счёт: [String: Int]
    /// Ответ главной уже был — до него вместо чисел мерцание.
    let готово: Bool
    let выбрать: (РазделГлавной) -> Void
    let открыть: (URL) -> Void

    private static let верх: CGFloat = 104
    private static let низ: CGFloat = 88
    private static let зазор: CGFloat = 10

    init(разделы: [РазделГлавной], слайды: [БаннерГлавной.Слайд], название: @escaping (РазделГлавной) -> String,
         счёт: [String: Int], готово: Bool, выбрать: @escaping (РазделГлавной) -> Void, открыть: @escaping (URL) -> Void) {
        self.разделы = разделы
        self.слайды = слайды
        self.название = название
        self.счёт = счёт
        self.готово = готово
        self.выбрать = выбрать
        self.открыть = открыть
    }

    var body: some View {
        VStack(spacing: Self.зазор) {
            HStack(spacing: Self.зазор) {
                БаннерГлавной(слайды: слайды, открыть: открыть)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.верх * 2 + Self.зазор)
                VStack(spacing: Self.зазор) {
                    плитка(0, сплошная: true, высота: Self.верх)
                    плитка(1, сплошная: true, высота: Self.верх)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: Self.зазор) {
                плитка(2, сплошная: false, высота: Self.низ)
                плитка(3, сплошная: false, высота: Self.низ)
            }
            HStack(spacing: Self.зазор) {
                плитка(4, сплошная: false, высота: Self.низ)
                плитка(5, сплошная: false, высота: Self.низ)
            }
        }
        .padding(.horizontal, 16)
        /* Высоты плиток постоянные, как на сайте: дальше этого размера текста подписи в них не помещаются. */
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private func плитка(_ номер: Int, сплошная: Bool, высота: CGFloat) -> some View {
        if номер < разделы.count {
            let раздел = разделы[номер]
            ПлиткаРаздела(раздел: раздел, название: название(раздел), счёт: счёт[раздел.ключ], готово: готово,
                          сплошная: сплошная, высота: высота, действие: { выбрать(раздел) })
                .frame(maxWidth: .infinity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: высота)
        }
    }
}

/// Плитка раздела (.mh-tile): градиент по краске раздела, круг в углу, название, «N предложений» и картинка раздела.
struct ПлиткаРаздела: View {
    let раздел: РазделГлавной
    let название: String
    let счёт: Int?
    /// Этап 49: ответ главной был — число или подпись; нет — мерцающая полоска (.mh-tile-n:empty).
    let готово: Bool
    /// is-prio / is-solid — залита краской раздела, текст белый.
    let сплошная: Bool
    let высота: CGFloat
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема

    init(раздел: РазделГлавной, название: String, счёт: Int?, готово: Bool, сплошная: Bool, высота: CGFloat,
         действие: @escaping () -> Void) {
        self.раздел = раздел
        self.название = название
        self.счёт = счёт
        self.готово = готово
        self.сплошная = сплошная
        self.высота = высота
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(stops: остановки, startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                /* ::after — круг 104 px за правым нижним краем: 10 % краски (в тёмной 16 %), у сплошной — белый 14 %. */
                Circle()
                    .fill(сплошная ? Color.white.opacity(тёмная ? 0.12 : 0.14)
                                   : Color(uiColor: краска).opacity(тёмная ? 0.16 : 0.1))
                    .frame(width: 104, height: 104)
                    .offset(x: 22, y: 30)
                /* Владелец 25.09.2026, проверка на телефоне, сборка 33: КартинкаЛенты вместо AsyncImage — WebP плитки
                   распаковывается не на главной очереди и хранится в памяти (FeedImages.swift). */
                КартинкаЛенты(раздел.картинка, пунктов: размерКартинки, заполнить: false) {
                    Color.clear
                }
                .frame(width: размерКартинки, height: размерКартинки)
                .shadow(color: Color(red: 10 / 255, green: 28 / 255, blue: 20 / 255).opacity(0.26), radius: 6, x: 0, y: 6)
                .padding(.trailing, 6)
                .padding(.bottom, 4)
                .accessibilityHidden(true)
                подписи
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: высота)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            /* Проверка на телефоне, сборка 33 («лента подвисает»): тень — у подложки той же формы и заливкой
               (ShapeStyle.shadow), и только у сплошной плитки в светлой теме. Раньше .shadow висел на всей обрезанной
               плитке (градиент, круг, картинка, подписи) у всех шести — у светлых прозрачным цветом, но всё равно. */
            .background {
                if сплошная && !тёмная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                        .fill(Color(uiColor: краска)
                            .shadow(.drop(color: Color(uiColor: краска).opacity(0.3), radius: 10, x: 0, y: 8)))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .accessibilityHint(раздел.вакансии ? DesignText.т("on_site") : "")
        .accessibilityAddTraits(.isButton)
    }

    private var подписи: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(название)
                .font(сплошная ? Font.system(.callout, weight: .heavy) : Font.system(.subheadline, weight: .heavy))
                .foregroundStyle(сплошная ? Color.white : Theme.текст)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            строкаЧисла
        }
        /* .mh-hub>.mh-tile:not(.is-prio){padding:var(--m-4) var(--m-5)} — у светлых плиток отступ как у сплошных:
           владелец 26.09.2026 — «Товары, Услуги … слишком приподняты и зажаты к верху плашек». */
        .padding(.leading, сплошная ? 16 : 18)
        .padding(.trailing, сплошная ? 14 : 58)          // has-pic: у светлой плитки название не заходит на картинку
        .padding(.vertical, сплошная ? 14 : 16)
    }

    /// .mh-tile-n: число — «N предложений» (у «Работы» — «N вакансий»); ноль — у сплошной подпись раздела (is-sub), у
    /// светлой ничего; ответа ещё не было — мерцающая полоска 58 % ширины.
    @ViewBuilder
    private var строкаЧисла: some View {
        if !готово {
            GeometryReader { место in
                МерцаниеСайта(радиус: Theme.Радиус.xxs)
                    .frame(width: место.size.width * 0.58, height: 14)
            }
            .frame(height: 16)
            .padding(.top, 1)
        } else if let счёт, счёт > 0 {
            Text(раздел.вакансии ? DesignText.вакансий(счёт) : DesignText.предложений(счёт))
                .font(.system(size: сплошная ? 12 : 11, weight: .bold))
                .foregroundStyle(цветСчёта)
                .lineLimit(1)
        } else if сплошная {
            Text(DesignText.т("sub_" + раздел.ключ))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
    }

    private var тёмная: Bool { схема == .dark }
    private var краска: UIColor { Theme.hex(раздел.краска) }
    /// Картинка: у верхних — 64 % высоты плитки, у нижних — 84 % (is-photo, height:88% за вычетом отступа).
    private var размерКартинки: CGFloat { высота * (сплошная ? 0.64 : 0.84) }

    /// linear-gradient(150deg, …) плитки: светлая — от 22 % краски к 7 % на поверхности (в тёмной 26 % → 14 %),
    /// сплошная — от краски, подмешанной к белому, к краске, притушенной почти чёрным.
    private var остановки: [Gradient.Stop] {
        let к = краска
        if сплошная {
            let дно = тёмная ? UIColor.black : Theme.hex(0x0B1F17)
            return [
                Gradient.Stop(color: Color(uiColor: Theme.смесь(к, UIColor.white, тёмная ? 0.88 : 0.86)), location: 0),
                Gradient.Stop(color: Color(uiColor: Theme.смесь(к, дно, тёмная ? 0.86 : 0.94)), location: тёмная ? 0.6 : 0.55),
                Gradient.Stop(color: Color(uiColor: Theme.смесь(к, дно, тёмная ? 0.64 : 0.78)), location: 1)
            ]
        }
        let поверхность = тёмная ? Theme.hex(0x16161F) : UIColor.white
        let конец = Color(uiColor: Theme.смесь(к, поверхность, тёмная ? 0.14 : 0.07))
        return [
            Gradient.Stop(color: Color(uiColor: Theme.смесь(к, поверхность, тёмная ? 0.26 : 0.22)), location: 0),
            Gradient.Stop(color: конец, location: тёмная ? 0.62 : 0.7),
            Gradient.Stop(color: конец, location: 1)
        ]
    }

    /// .mh-tile-n: 82 % краски с чернилами (в тёмной — 55 % с белым), у сплошной — белый 86 %.
    private var цветСчёта: Color {
        if сплошная { return Color.white.opacity(0.86) }
        if тёмная { return Color(uiColor: Theme.смесь(краска, UIColor.white, 0.55)) }
        return Color(uiColor: Theme.смесь(краска, Theme.hex(0x13211B), 0.82))
    }

    private var голос: String {
        guard let счёт, счёт > 0 else { return название }
        return название + ", " + (раздел.вакансии ? DesignText.вакансий(счёт) : DesignText.предложений(счёт))
    }
}

// MARK: - Баннер (.mh-bn)

/**
 Баннер Kliko (.mh-bn): слайды сменяются наплывом раз в 6 с (MH_BN_EVERY), точки справа внизу.

 Этап 49: слайдов четыре, как у сайта — «Перенесём ваши объявления» (#2563EB), «Продавайте на Kliko» (#0F7A44),
 «Торгуйтесь по-настоящему» (#D97706) и «Деньги ждут у нас» (#7C3AED); порядок тасует ПодборкиГлавной раз за жизнь ленты
 (mhBannerInit — раз за загрузку страницы). Нажатие — лист со сведениями, как hpOpen сайта (ЛистСлайдаГлавной); точка —
 этот слайд и пауза на две смены (mhBannerGo). При «Уменьшении движения» слайды не листаются сами.
 */
struct БаннерГлавной: View {
    struct Слайд: Identifiable, Hashable {
        /// data-k слайда: import, sell, bid, escrow — ключ текстов «bn_<k>_*» и «hp_<k>_*».
        let id: String
        /// --bc слайда.
        let краска: UInt32
        /// .mh-bn-ic — ближайший SF Symbol к SVG сайта.
        let значок: String
    }

    /// Слайды .mh-bn главной в порядке разметки.
    static let слайды: [Слайд] = [
        Слайд(id: "import", краска: 0x2563EB, значок: "tray.and.arrow.down"),
        Слайд(id: "sell", краска: 0x0F7A44, значок: "storefront"),
        Слайд(id: "bid", краска: 0xD97706, значок: "text.bubble"),
        Слайд(id: "escrow", краска: 0x7C3AED, значок: "checkmark.shield")
    ]

    let слайды: [Слайд]
    let открыть: (URL) -> Void
    @State private var номер = 0
    /// Точку нажали — до этого времени слайд не меняется сам (mhBannerGo: 2 × MH_BN_EVERY).
    @State private var держатьДо = Date.distantPast
    /// Открытый лист слайда.
    @State private var открытый: Слайд? = nil
    /// Кнопка листа ведёт на страницу сайта — открыть, когда лист уже закрылся (иначе он остался бы над страницей).
    @State private var послеЗакрытия: URL? = nil
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(слайды: [Слайд], открыть: @escaping (URL) -> Void) {
        self.слайды = слайды
        self.открыть = открыть
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(слайды.enumerated()), id: \.element.id) { индекс, слайд in
                слайдВид(слайд)
                    .opacity(индекс == номер ? 1 : 0)
                    .allowsHitTesting(индекс == номер)
                    .accessibilityHidden(индекс != номер)
            }
            точки
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DesignText.т("banner"))
        /* Смена раз в 6 с; при «Уменьшении движения» слайд стоит, листают точками. */
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                if !безДвижения && слайды.count > 1 && Date() >= держатьДо && открытый == nil {
                    withAnimation(.easeInOut(duration: 0.45)) { номер = (номер + 1) % слайды.count }
                }
            }
        }
        .sheet(item: $открытый, onDismiss: {
            guard let адрес = послеЗакрытия else { return }
            послеЗакрытия = nil
            /* Проверенному продавцу — «Разместить объявление»: свой мастер подачи, как у баннера «Продавай на Kliko.kz». */
            if адрес.query == "go=add" && Config.нижниеВкладки && ПодачаОкно.shared.открыть(.новое) { return }
            открыть(адрес)
        }) { слайд in
            ЛистСлайдаГлавной(слайд: слайд, перейти: { путь in
                послеЗакрытия = Config.url(путь)
                открытый = nil
            }, закрыть: { открытый = nil })
        }
    }

    private func слайдВид(_ слайд: Слайд) -> some View {
        let краска = Theme.hex(слайд.краска)
        let заголовок = DesignText.т("bn_\(слайд.id)_t")
        let подпись = DesignText.т("bn_\(слайд.id)_s")
        return Button {
            открытый = слайд
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(uiColor: краска), Color(uiColor: Theme.смесь(краска, Theme.hex(0x0B1A12), 0.62))],
                               startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                Image(systemName: слайд.значок)
                    .font(.system(size: 92, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.16))
                    .offset(x: 18, y: -8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(заголовок)
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(4)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: 4) {
                        Text(DesignText.т("bn_\(слайд.id)_b"))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color(uiColor: краска))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
                    .padding(.top, 6)
                }
                .padding(16)
                .padding(.bottom, 6)
            }
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(заголовок + ". " + подпись)
        .accessibilityAddTraits(.isButton)
    }

    /// .mh-bn-d: выбранная — полоска 18×6 белая, прочие — точки 6×6 белые 42 %.
    private var точки: some View {
        HStack(spacing: 6) {
            ForEach(Array(слайды.enumerated()), id: \.element.id) { индекс, слайд in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { номер = индекс }
                    держатьДо = Date().addingTimeInterval(12)
                } label: {
                    Capsule()
                        .fill(индекс == номер ? Color.white : Color.white.opacity(0.42))
                        .frame(width: индекс == номер ? 18 : 6, height: 6)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("bn_\(слайд.id)_t"))
                .accessibilityAddTraits(индекс == номер ? .isSelected : [])
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 8)
    }
}

/**
 Лист слайда — .hp-ov сайта (hpOpen): квадрат со значком цветом слайда, заголовок и подзаголовок, пункты со значками,
 блок «Kliko AI соберёт объявление за вас» и кнопка. Тексты — .hp-p главной; у «Деньги ждут у нас» сайт показывает тот же
 лист, что у «Продавайте на Kliko», только фиолетовый, — так и здесь. Кнопки: перенос — «Начать перенос»
 (/cabinet?go=aiimport), продажа — «Регистрация продавца через eGov» (/cabinet?go=egov), торг — «Понятно». 🔴 Денег здесь
 нет: «Подкрепить деньгами?» у торга — картинка-пример (.hp-ofc, pointer-events: none), не кнопка.
 */
struct ЛистСлайдаГлавной: View {
    let слайд: БаннерГлавной.Слайд
    /// Путь страницы сайта для кнопки листа.
    let перейти: (String) -> Void
    let закрыть: () -> Void
    @Environment(\.colorScheme) private var схема
    /// TestFlight 1.10: кнопка «Продавайте на Kliko» — по общему состоянию входа (СессияПриложения).
    @ObservedObject private var сессия = СессияПриложения.shared

    init(слайд: БаннерГлавной.Слайд, перейти: @escaping (String) -> Void, закрыть: @escaping () -> Void) {
        self.слайд = слайд
        self.перейти = перейти
        self.закрыть = закрыть
    }

    private struct Пункт: Identifiable {
        let id: Int
        let значок: String
        let ключ: String
    }

    /// Чьи тексты: у «Деньги ждут у нас» — продажи.
    private var тексты: String { слайд.id == "escrow" ? "sell" : слайд.id }

    private var пункты: [Пункт] {
        switch тексты {
        case "import":
            return [Пункт(id: 1, значок: "tray.and.arrow.down", ключ: "hp_import_1"),
                    Пункт(id: 2, значок: "list.bullet.rectangle", ключ: "hp_import_2"),
                    Пункт(id: 3, значок: "checkmark", ключ: "hp_import_3")]
        case "bid":
            return [Пункт(id: 1, значок: "bubble.left", ключ: "hp_bid_1"),
                    Пункт(id: 2, значок: "checkmark.shield", ключ: "hp_bid_2"),
                    Пункт(id: 3, значок: "banknote", ключ: "hp_bid_3")]
        default:
            return [Пункт(id: 1, значок: "banknote", ключ: "hp_sell_1"),
                    Пункт(id: 2, значок: "checkmark.shield", ключ: "hp_sell_2"),
                    Пункт(id: 3, значок: "bubble.left", ключ: "hp_sell_3"),
                    Пункт(id: 4, значок: "checkmark.circle", ключ: "hp_sell_4")]
        }
    }

    private var краска: UIColor { Theme.hex(слайд.краска) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                    .padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(пункты) { пункт in
                        строка(пункт)
                    }
                }
                .padding(.bottom, 16)
                if тексты != "bid" {
                    блокAI
                        .padding(.bottom, 16)
                }
                кнопка
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) {
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(DesignText.т("close"))
        }
        .background(Theme.поверхность)
        .листПоВысоте()
    }

    /// .hp-hd: квадрат 56 со значком (140°: краска → краска 68 % к почти чёрному), заголовок 21/800, подзаголовок серым.
    private var шапка: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: слайд.значок)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 56, height: 56)
                .background(LinearGradient(colors: [Color(uiColor: краска),
                                                    Color(uiColor: Theme.смесь(краска, Theme.hex(0x0B1A12), 0.68))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(DesignText.т("hp_\(тексты)_t"))
                .font(.system(.title2, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .padding(.trailing, 36)
                .accessibilityAddTraits(.isHeader)
            Text(DesignText.т("hp_\(тексты)_s"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// .hp-l li: значок в квадрате 36 (краска 20 % к поверхности, рамка краски 30 %), жирная строка и серая подпись.
    private func строка(_ пункт: Пункт) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: пункт.значок)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(uiColor: краска))
                .frame(width: 36, height: 36)
                .background(Color(uiColor: смесьСПоверхностью(0.2)),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Color(uiColor: краска).opacity(0.3), lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DesignText.т(пункт.ключ))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(DesignText.т(пункт.ключ + "s"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                if пункт.ключ == "hp_bid_3" {
                    примерПредложения
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// .hp-ofc — картинка-пример «Ваше предложение · 150 000 ₸ · Подкрепить деньгами?»; не нажимается.
    private var примерПредложения: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(DesignText.т("hp_bid_card_h").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Theme.текстВторой)
            Text("150\u{00A0}000\u{00A0}₸")
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(Theme.текст)
            Text(DesignText.т("hp_bid_card_b"))
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.top, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Theme.поверхность2,
                    in: UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.md, bottomLeadingRadius: Theme.Радиус.md,
                                               bottomTrailingRadius: Theme.Радиус.xxs, topTrailingRadius: Theme.Радиус.md,
                                               style: .continuous))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.md, bottomLeadingRadius: Theme.Радиус.md,
                                   bottomTrailingRadius: Theme.Радиус.xxs, topTrailingRadius: Theme.Радиус.md,
                                   style: .continuous)
                .stroke(Theme.линия, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// .hp-ai: «Kliko AI соберёт объявление за вас» — квадрат 38 краски с искрами, подложка краски 13 % к surf2.
    private var блокAI: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 38, height: 38)
                .background(Color(uiColor: краска), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(DesignText.т("hp_ai_t"))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(DesignText.т("hp_ai_s"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(uiColor: смесьСПоверхностью(0.13)), Theme.поверхность2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Color(uiColor: краска).opacity(0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// .hp-go: 54 pt, скругление 14, градиент краски, белый текст.
    private var кнопка: some View {
        Button {
            switch тексты {
            case "import": перейти("/cabinet?go=aiimport")
            case "sell": перейти(путьПродажи)
            default: закрыть()
            }
        } label: {
            Text(DesignText.т(ключКнопки))
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(LinearGradient(colors: [Color(uiColor: краска),
                                                    Color(uiColor: Theme.смесь(краска, Theme.hex(0x0B1A12), 0.72))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеСайта())
    }

    /**
     TestFlight 1.10 (владелец: «просит регу через eGov, хотя я зашёл уже»): кнопка продажи — по роли, а не всем одна.
     Гость — «Регистрация продавца через eGov» (?egov=1: окно eGov гостевой страницы; ?go=egov гостю ничего не делает,
     карта кабинета §0.10); вошедший без проверки — «Пройти верификацию через eGov» (?go=egov → requestVerification);
     проверенный продавец — «Разместить объявление» (?go=add). Проверенному регистрацию не показываем никогда.
     */
    private var путьПродажи: String {
        switch сессия.роль {
        case .гость: return "/cabinet?egov=1"
        case .вошёл: return "/cabinet?go=egov"
        case .продавец: return "/cabinet?go=add"
        }
    }

    private var ключКнопки: String {
        guard тексты == "sell" else { return "hp_" + тексты + "_go" }
        switch сессия.роль {
        case .гость: return "hp_sell_go"
        case .вошёл: return "hp_sell_go_verify"
        case .продавец: return "hp_sell_go_post"
        }
    }

    /// color-mix(in srgb, var(--bc) доля, var(--mk-surf)) — поверхность своей темы.
    private func смесьСПоверхностью(_ доля: CGFloat) -> UIColor {
        let база = краска
        return UIColor { признаки in
            Theme.смесь(база, признаки.userInterfaceStyle == .dark ? Theme.hex(0x16161F) : UIColor.white, доля)
        }
    }
}

// MARK: - Ряд раздела (.mh-row)

/**
 Ряд «• Электроника 26  Все ›»: полоса во всю ширину со скруглением 20 и отсветом краски раздела слева сверху, чётные
 ряды — на чуть зелёной подложке; карточки листаются вбок по 2,2 на экран. Раздел больше показанного — в конце ряда
 плитка «Смотреть все» с числом (.mh-rend).
 */
struct РядГлавной<Карточка: View>: View {
    let раздел: РазделГлавной
    let название: String
    /// Сколько карточек в ряду — от него «Смотреть все» (i > items.length у сайта).
    let показано: Int
    let всего: Int?
    /// Второй, четвёртый… ряд — .mh-row:nth-of-type(2n).
    let чётный: Bool
    let всё: () -> Void
    let карточки: Карточка
    @Environment(\.colorScheme) private var схема

    init(раздел: РазделГлавной, название: String, показано: Int, всего: Int?, чётный: Bool,
         всё: @escaping () -> Void, @ViewBuilder карточки: () -> Карточка) {
        self.раздел = раздел
        self.название = название
        self.показано = показано
        self.всего = всего
        self.чётный = чётный
        self.всё = всё
        self.карточки = карточки()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            заголовок
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    карточки
                    if let всего, всего > показано {
                        конецРяда(всего)
                            .containerRelativeFrame(.horizontal) { длина, _ in ШиринаКарточкиРяда.для(длина) }
                    }
                }
                .padding(.horizontal, 16)
                /* Владелец 25.09.2026, проверка на телефоне, сборка 33: прокрутка обрезает всё, что за её краем, и тень
                   карточек (до ~9 pt вниз) срезалась в 4 pt под ними ровной полосой. Снизу место под тень — внутри
                   прокрутки, а внешний отступ меньше на столько же: ряд той же высоты. */
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(полоса)
    }

    private var заголовок: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(uiColor: краска))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(название)
                .font(.system(.title3, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            if let всего, всего > 0 {
                Text(DesignText.число(всего))
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityLabel(числоСловом(всего))
            }
            Spacer(minLength: 8)
            Button(action: всё) {
                HStack(spacing: 2) {
                    Text(DesignText.т("row_all"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(цветСсылки)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DesignText.т("row_all") + ": " + название)
            .accessibilityHint(раздел.вакансии ? DesignText.т("on_site") : "")
        }
    }

    /// «26 предложений», у «Работы» — «3 вакансии» (_mhCount(n, jobs)).
    private func числоСловом(_ n: Int) -> String {
        раздел.вакансии ? DesignText.вакансий(n) : DesignText.предложений(n)
    }

    /// .mh-rend: плитка с кружком-стрелкой краски раздела, «Смотреть все» и числом — ведёт туда же, куда «Все».
    private func конецРяда(_ всего: Int) -> some View {
        Button(action: всё) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(Color(uiColor: краска), in: Circle())
                Text(DesignText.т("see_all"))
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(цветСсылки)
                Text(числоСловом(всего))
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(Color(uiColor: фонКонца), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignText.т("see_all") + ": " + название + ", " + числоСловом(всего))
        .accessibilityAddTraits(.isButton)
    }

    private var тёмная: Bool { схема == .dark }
    private var краска: UIColor { Theme.hex(раздел.краска) }

    /// .mh-rall: 85 % краски с чернилами, в тёмной — 55 % с белым.
    private var цветСсылки: Color {
        if тёмная { return Color(uiColor: Theme.смесь(краска, UIColor.white, 0.55)) }
        return Color(uiColor: Theme.смесь(краска, Theme.hex(0x13211B), 0.85))
    }

    private var фонКонца: UIColor {
        Theme.смесь(краска, тёмная ? Theme.hex(0x16161F) : UIColor.white, 0.07)
    }

    /// --mh-band: белая поверхность (в тёмной — 2 % белого к #16161f); чётный ряд — 6 % зелёного к #f4f8f6 (в тёмной —
    /// 5 % белого к #1c1c26). Поверх — отсвет краски раздела 8 % из левого верхнего угла.
    private var фонПолосы: UIColor {
        if чётный {
            return тёмная ? Theme.смесь(UIColor.white, Theme.hex(0x1C1C26), 0.05)
                          : Theme.смесь(Theme.hex(0x0F5132), Theme.hex(0xF4F8F6), 0.06)
        }
        return тёмная ? Theme.смесь(UIColor.white, Theme.hex(0x16161F), 0.02) : UIColor.white
    }

    private var полоса: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous)
            .fill(Color(uiColor: фонПолосы))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous)
                    .fill(RadialGradient(colors: [Color(uiColor: краска).opacity(0.08), Color.clear],
                                         center: .topLeading, startRadius: 0, endRadius: 280))
            }
            .accessibilityHidden(true)
    }
}

/**
 Ширина карточки ряда — grid-auto-columns .mh-rs: на телефоне (100 % − 2 зазора) / 2,2 от ширины ряда без полей 16 — две
 карточки и край третьей (155 pt на 393-pt экране); от 600 pt — / 3,3, от 960 — пять в ряд. Отдельно от РядГлавной: он
 обобщённый, а ширина нужна и тому, кто кладёт в него карточки (и заготовке рядов).
 */
enum ШиринаКарточкиРяда {
    static func для(_ длина: CGFloat) -> CGFloat {
        let поле = max(0, длина - 32)
        if длина >= 960 { return (поле - 40) / 5 }
        if длина >= 600 { return (поле - 30) / 3.3 }
        return max(120, (поле - 20) / 2.2)
    }
}

/// Нажатие как на сайте (.mh-tile:active, .mh-c:active): лёгкое сжатие до 98 %.
struct НажатиеСайта: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
