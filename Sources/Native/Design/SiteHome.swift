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

 Разделы и краски — MK_HOME_V главной, картинки — MK_CATPIC (/img/cat-<раздел>.webp — публичные файлы сайта). «Работа»
 на главной приложения не стоит: её объявления — вакансии другого API (api/jobs.php), нативного экрана для них нет,
 а плитка, уводящая на сайт, среди разделов ленты путала бы. Сайт и сам показывает шесть плиток из семи.
 */
struct РазделГлавной: Identifiable, Hashable {
    /// Ключ раздела — cat= у api/listings.php и k в снимке главной (FeedSnapshot).
    let ключ: String
    /// Краска раздела — --vc плитки, «#DC2626».
    let краска: UInt32

    var id: String { ключ }

    /// Картинка плитки с сайта — MK_CATPIC: /img/cat-<раздел>.webp, 320 px. Малая (-s, 200 px) на экране 3× мылится.
    var картинка: URL? { Config.url("/img/cat-\(ключ).webp?v=1789893153") }

    /// MH_ORDER сайта без «Работы»: transport, realty, electronics, services, goods, animals.
    static let все: [РазделГлавной] = [
        РазделГлавной(ключ: "transport", краска: 0xDC2626),
        РазделГлавной(ключ: "realty", краска: 0x059669),
        РазделГлавной(ключ: "electronics", краска: 0x2563EB),
        РазделГлавной(ключ: "services", краска: 0x0D9488),
        РазделГлавной(ключ: "goods", краска: 0xD97706),
        РазделГлавной(ключ: "animals", краска: 0x7C3AED)
    ]
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
        /// Всего объявлений в разделе (total, с этапа 34 — verts[раздел].n); nil — сайт не прислал.
        let всего: Int?
        var id: String { раздел.ключ }
    }

    @Published private(set) var ряды: [Ряд] = []
    /// «N предложений» на плитках — только больше нуля.
    @Published private(set) var счёт: [String: Int] = [:]
    @Published private(set) var грузим = false
    /// Ни один запрос не прошёл, а показать нечего — строка «Не удалось загрузить подборки» с «Повторить».
    @Published private(set) var неудача = false
    /// Этап 34: vip[] ответа home=1 — блок «VIP-объявления» среди рядов. Пусто — блока нет.
    @Published private(set) var вип: [Listing] = []
    /// Этап 34: total ответа home=1 (нет его — counts=1) — число на «Показать все объявления». nil — не пришло.
    @Published private(set) var всегоОбъявлений: Int?
    /// Этап 34: на экране главная не для нынешнего запроса — копия с диска или прежнего места, а свежая не пришла:
    /// «Показано, как было в последний раз» с «Повторить» (.mh-stale сайта).
    @Published private(set) var устарело = false

    /// Этап 32: пока ряды грузились, их попросили снова (сменили город) — по окончании загрузить ещё раз, уже для него.
    private var ещёРаз = false

    /// Этап 34: чья главная на экране — ключ запроса home=1 (ГлавнаяAPI.ключ); nil — ряды по разделам или ничего.
    private var показанныйКлюч: String?
    /// Этап 34: на экране копия с диска, свежая ещё не приходила.
    private var показаноСДиска = false
    /// Этап 34: home=1 в этот запуск ответил не тем видом — дальше по разделам (этап 26), не спрашивая его снова.
    private var одинЗапросНеПонят = false
    /// Этап 34: порядок рядов — MH_ORDER сайта, перемешанный (mkHomeRender тасует его при каждом показе). Здесь — раз за
    /// запуск: копия с диска и свежий ответ приходят подряд, и ряды не прыгали бы у человека под пальцем.
    private let порядок: [РазделГлавной] = РазделГлавной.все.shuffled()
    /// Этап 34: где среди рядов VIP — у сайта после 1 + floor(random · рядов) рядов; случайная доля — тоже раз за запуск.
    private let доляВИП = Double.random(in: 0..<1)
    /// Этап 34: больше карточек в ряду не берём — сайт показывает все, что прислано, это страховка от неожиданно
    /// длинного ответа.
    private static let вРяду = 30

    init() {
        /* Этап 34 выключен — копия главной прежних запусков больше не нужна. */
        if !Config.главнаяОдинЗапрос { КэшГлавной.стереть() }
    }

    /// После скольких рядов стоит VIP (1…число рядов; у сайта d ≥ рядов — в конец). Рядов нет — 0: VIP сам по себе.
    var местоВИП: Int {
        guard !ряды.isEmpty else { return 0 }
        return min(ряды.count, 1 + Int(доляВИП * Double(ряды.count)))
    }

    /// .mh-busy сайта: главная обновляется поверх уже показанной — ряды и VIP притушены.
    var обновляем: Bool { грузим && (!ряды.isEmpty || !вип.isEmpty) }

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
            показать(сохранённый, числа: nil, ключ: ключ, сДиска: true)
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
        /* Раздел без n — числа counts=1 (mkLoadCounts), и только «честные»: вся страна или город. Один запрос, по
           надобности; не пришли — плитка без числа, как у сайта без счёта. */
        var числа: СчётРазделов? = nil
        let безЧисла = порядок.contains { раздел in ответ.разделы[раздел.ключ]?.всего == nil }
        if безЧисла && ГлавнаяAPI.счётЧестный(где) {
            числа = try? await ГлавнаяAPI.числа(где, куки: куки)
            guard !Task.isCancelled else { return true }
        }
        показать(ответ, числа: числа, ключ: ключ, сДиска: false)
        await КэшГлавной.сохранитьВФоне(сырое, ключ: ключ)
        return true
    }

    /// Ответ home=1 — на экран (mkHomeRender): ряды в перемешанном порядке, пустых разделов нет, ТОП в начале ряда
    /// вперемешку; числа плиток — n раздела (_mhTiles), нет его — сумма counts=1 по подразделам.
    private func показать(_ ответ: ОтветГлавной, числа: СчётРазделов?, ключ: String, сДиска: Bool) {
        var новые: [Ряд] = []
        var счётПлиток: [String: Int] = [:]
        for раздел in порядок {
            let сРаздела = ответ.разделы[раздел.ключ]
            let всегоВРазделе: Int? = сРаздела?.всего ?? числа.map { ч in ч.число(раздел.ключ) }
            if let всегоВРазделе, всегоВРазделе > 0 { счётПлиток[раздел.ключ] = всегоВРазделе }
            if let сРаздела, !сРаздела.товары.isEmpty {
                let товары = Self.топВперемешку(Self.безПовторов(Array(сРаздела.товары.prefix(Self.вРяду))))
                новые.append(Ряд(раздел: раздел, товары: товары, всего: всегоВРазделе))
            }
        }
        ряды = новые
        счёт = счётПлиток
        вип = Self.безПовторов(ответ.вип)
        всегоОбъявлений = ответ.всего ?? числа?.всего
        показанныйКлюч = ключ
        показаноСДиска = сДиска
        неудача = false
        устарело = false
    }

    /// Свежая главная не пришла (_mhFail): показать нечего — «Не удалось загрузить подборки»; на экране копия с диска или
    /// главная прежнего места — «Показано, как было в последний раз»; свежая этого же места — ничего, как у сайта.
    private func неПришло(_ ключ: String) {
        if ряды.isEmpty && вип.isEmpty {
            неудача = true
            устарело = false
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

    // MARK: - По разделам (этап 26)

    /// Ряды запросами по разделам — как на этапе 26: без рубильника этапа 34, с районом и когда home=1 не понят.
    private func загрузитьПоРазделам(_ где: ГдеИскать) async {
        let куки = await SiteSession.куки()
        let ответы = await Self.запросить(куки: куки, где: где)
        guard !Task.isCancelled else { return }
        guard !ответы.isEmpty else {
            неудача = ряды.isEmpty && вип.isEmpty
            /* Этап 34: на экране осталась копия главной с диска — сказать, что она не свежая. */
            устарело = показаноСДиска && !неудача
            return
        }
        var новые: [Ряд] = []
        var числа: [String: Int] = [:]
        for раздел in РазделГлавной.все {
            guard let страница = ответы[раздел.ключ] else { continue }
            if let всего = страница.total, всего > 0 { числа[раздел.ключ] = всего }
            if !страница.items.isEmpty {
                новые.append(Ряд(раздел: раздел, товары: Array(страница.items.prefix(10)), всего: страница.total))
            }
        }
        неудача = false
        ряды = новые
        счёт = числа
        /* Этап 34: по разделам VIP и total не приходят, и это уже не главная home=1 — ни её места, ни «как было». */
        вип = []
        всегоОбъявлений = nil
        показанныйКлюч = nil
        показаноСДиска = false
        устарело = false
    }

    /// Первая страница каждого раздела: api/listings.php?cat=<раздел>&per=10 (и город этапа 32) с куками, взятыми один раз.
    nonisolated private static func запросить(куки: [String: String], где: ГдеИскать) async -> [String: ListingsPage] {
        await withTaskGroup(of: ОтветРяда.self, returning: [String: ListingsPage].self) { группа in
            for раздел in РазделГлавной.все {
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
 нижних — 88px, зазор — --vx-gap (10px).
 */
struct ПлиткиГлавной: View {
    let название: (РазделГлавной) -> String
    let счёт: [String: Int]
    let выбрать: (РазделГлавной) -> Void
    let открыть: (URL) -> Void

    private static let верх: CGFloat = 104
    private static let низ: CGFloat = 88
    private static let зазор: CGFloat = 10

    init(название: @escaping (РазделГлавной) -> String, счёт: [String: Int],
         выбрать: @escaping (РазделГлавной) -> Void, открыть: @escaping (URL) -> Void) {
        self.название = название
        self.счёт = счёт
        self.выбрать = выбрать
        self.открыть = открыть
    }

    var body: some View {
        VStack(spacing: Self.зазор) {
            HStack(spacing: Self.зазор) {
                БаннерГлавной(открыть: открыть)
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
        if номер < РазделГлавной.все.count {
            let раздел = РазделГлавной.все[номер]
            ПлиткаРаздела(раздел: раздел, название: название(раздел), счёт: счёт[раздел.ключ], сплошная: сплошная,
                          высота: высота, действие: { выбрать(раздел) })
                .frame(maxWidth: .infinity)
        }
    }
}

/// Плитка раздела (.mh-tile): градиент по краске раздела, круг в углу, название, «N предложений» и картинка раздела.
struct ПлиткаРаздела: View {
    let раздел: РазделГлавной
    let название: String
    let счёт: Int?
    /// is-prio / is-solid — залита краской раздела, текст белый.
    let сплошная: Bool
    let высота: CGFloat
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема

    init(раздел: РазделГлавной, название: String, счёт: Int?, сплошная: Bool, высота: CGFloat,
         действие: @escaping () -> Void) {
        self.раздел = раздел
        self.название = название
        self.счёт = счёт
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
                    .fill(сплошная ? Color.white.opacity(0.14) : Color(uiColor: краска).opacity(тёмная ? 0.16 : 0.1))
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
        .accessibilityAddTraits(.isButton)
    }

    private var подписи: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(название)
                .font(сплошная ? Font.system(.callout, weight: .heavy) : Font.system(.subheadline, weight: .heavy))
                .foregroundStyle(сплошная ? Color.white : Theme.текст)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let счёт, счёт > 0 {
                Text(DesignText.предложений(счёт))
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(цветСчёта)
                    .lineLimit(1)
            }
        }
        .padding(.leading, сплошная ? 14 : 12)
        .padding(.trailing, сплошная ? 14 : 58)          // has-pic: у светлой плитки название не заходит на картинку
        .padding(.vertical, сплошная ? 12 : 10)
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
        return название + ", " + DesignText.предложений(счёт)
    }
}

/// Баннер Kliko (.mh-bn): слайды сменяются наплывом раз в 6 с (MH_BN_EVERY), точки справа внизу.
///
/// Из четырёх слайдов сайта взяты два, у которых есть своя страница: «Перенесём ваши объявления» (/cabinet) и «Продавайте
/// на Kliko» (/cabinet?add=1) — ссылки .mh-bn-s главной. «Торгуйтесь» и «Деньги ждут у нас» на сайте открывают окно
/// внутри страницы (hpOpen) без адреса; кнопка, которая никуда не ведёт, хуже её отсутствия.
struct БаннерГлавной: View {
    struct Слайд: Identifiable {
        let id: String
        let краска: UInt32
        let значок: String
        let путь: String
    }

    static let слайды: [Слайд] = [
        Слайд(id: "import", краска: 0x2563EB, значок: "square.and.arrow.down.on.square", путь: "/cabinet"),
        Слайд(id: "sell", краска: 0x0F7A44, значок: "tag", путь: "/cabinet?add=1")
    ]

    let открыть: (URL) -> Void
    @State private var номер = 0
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(Self.слайды.enumerated()), id: \.element.id) { индекс, слайд in
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
                if !безДвижения && Self.слайды.count > 1 {
                    withAnimation(.easeInOut(duration: 0.45)) { номер = (номер + 1) % Self.слайды.count }
                }
            }
        }
    }

    private func слайдВид(_ слайд: Слайд) -> some View {
        let краска = Theme.hex(слайд.краска)
        let заголовок = DesignText.т("bn_\(слайд.id)_t")
        let подпись = DesignText.т("bn_\(слайд.id)_s")
        return Button {
            if let u = Config.url(слайд.путь) { открыть(u) }
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
            ForEach(Array(Self.слайды.enumerated()), id: \.element.id) { индекс, слайд in
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { номер = индекс }
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

// MARK: - Ряд раздела (.mh-row)

/**
 Ряд «• Электроника 26  Все ›»: полоса во всю ширину со скруглением 20 и отсветом краски раздела слева сверху, чётные
 ряды — на чуть зелёной подложке; карточки листаются вбок по 2,2 на экран. Раздел больше показанного — в конце ряда
 плитка «Смотреть все» с числом (.mh-rend).
 */
struct РядГлавной<Карточка: View>: View {
    let раздел: РазделГлавной
    let название: String
    let товары: [Listing]
    let всего: Int?
    /// Второй, четвёртый… ряд — .mh-row:nth-of-type(2n).
    let чётный: Bool
    let всё: () -> Void
    let карточка: (Listing) -> Карточка
    @Environment(\.colorScheme) private var схема

    init(раздел: РазделГлавной, название: String, товары: [Listing], всего: Int?, чётный: Bool,
         всё: @escaping () -> Void, @ViewBuilder карточка: @escaping (Listing) -> Карточка) {
        self.раздел = раздел
        self.название = название
        self.товары = товары
        self.всего = всего
        self.чётный = чётный
        self.всё = всё
        self.карточка = карточка
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            заголовок
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(товары) { товар in
                        карточка(товар)
                            .containerRelativeFrame(.horizontal) { длина, _ in Self.ширина(длина) }
                    }
                    if let всего, всего > товары.count {
                        конецРяда(всего)
                            .containerRelativeFrame(.horizontal) { длина, _ in Self.ширина(длина) }
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

    /// grid-auto-columns: calc((100% - 2 * gap) / 2.2) — две карточки и край третьей; на широком экране не шире 220.
    private static func ширина(_ длина: CGFloat) -> CGFloat {
        min(220, max(120, (длина - 20) / 2.2))
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
                    .accessibilityLabel(DesignText.предложений(всего))
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
        }
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
                Text(DesignText.предложений(всего))
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
        .accessibilityLabel(DesignText.т("see_all") + ": " + название + ", " + DesignText.предложений(всего))
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

/// Нажатие как на сайте (.mh-tile:active, .mh-c:active): лёгкое сжатие до 98 %.
struct НажатиеСайта: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
