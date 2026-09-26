import SwiftUI
import UIKit

/**
 «КАТЕГОРИИ» НИЖНЕЙ ПАНЕЛИ — КАК В МОБИЛЬНОЙ ВЕРСИИ САЙТА (владелец: «при нажатии «Категории» чтобы так же открывался,
 как в мобильной версии PWA»; «и такая же стрелка назад»).

 Как это устроено у сайта на телефоне (js/bottombar.min.js ulxBBCats, js/marketplace-home.min.js mhCats,
 js/marketplace-catov.min.js, css/marketplace-parts.min.css «mh-cats» и «mk-catov-v4»):
   · «Категории» на главной включают режим категорий (html.mk-cats) прямо на главной: шапка уезжает вверх, ряды,
     VIP и «Показать все» гаснут, сверху поднимается поле «Найти категорию» (#mh-cq), плитки встают сеткой в две
     колонки и поднимаются по очереди (mhRise 0,36 с, задержка 120 мс + 45 мс на плитку). Баннер и две «тяжёлые»
     плитки главной остаются наверху, под ними — светлые плитки всех корней MK_CATS в порядке дерева: название, число
     предложений (_MK_SRVCOUNTS, сумма по подразделам) или, пока чисел нет, три первых подраздела. Нижняя панель
     остаётся; второе нажатие «Категории» режим выключает (ulxBBCats → mhCats(false)).
   · Плитка раздела главной (Авто, Недвижимость, Электроника, Услуги, Животные, Товары) ведёт в ленту раздела
     (mkHomeGo), «Работа» — в вакансии; плитка остального корня открывает его подразделы (mhCatGo → ulxCatOpenAt):
     панель #mk-catov на весь экран, въезжает справа (ctgSlideIn), панель сайта под ней не видна. Шапка — «‹» слева
     (.ctg-ib: круг 40, без фона, значок цвета текста), название раздела по центру, «×» справа. Первая строка —
     «Все в разделе «…»», дальше подразделы строками: значок 40 × 40 на подложке краски корня, название, число, «›».
     Подраздел с детьми — следующий уровень, без детей — лента с ним (ulxCatGo), с марками — «Все» и марки
     (ulxBrandGo: раздел и марка в поиске). «‹» на первом уровне и «×» — назад к плиткам.
   · Поиск — по всему дереву (ulxCatSearchHTML): плитки прячутся, вместо них карточка строк с путём «Корень › …»,
     сначала совпавшие с начала, потом короткие, не больше 60; подсветки совпадения у сайта нет. Строка с детьми
     открывает панель сразу на этом разделе с полным путём назад (ulxCatSearchGo), лист — ленту.
   · Карты, справки, документов и поддержки в этом режиме у сайта нет — они в подвале страницы.

 Здесь то же нативно: экран поверх ленты, панель сайта — своя копия поверх (её «Категории» закрывает экран, остальные
 пункты — как обычно), уровни — NavigationStack с системным въездом и смахиванием назад (СмахнутьНазад: системная
 шапка спрятана, «‹» — как у сайта). Названия — справочник сайта на языке приложения (ЗагрузкаКаталогаПоиска), числа —
 api/listings.php?counts=1 (ГлавнаяAPI.числа), значки — ближайшие SF Symbols к SVG сайта (MK_CATS icon у корней и
 таблица по ключу раздела у подразделов, как у marketplace-catov).
 */
enum ДействиеЛистаКатегорий: Equatable {
    /// Карта объявлений.
    case карта
    /// Раздел ленты по ключу («transport», «goods»…); «jobs» — вакансии.
    case раздел(String)
    /// Страница сайта.
    case страница(URL)
}

// MARK: - Дерево разделов

/// MK_CFLAT сайта из справочника поиска: имена на языке приложения, дети в порядке дерева, марки листьев.
struct ДеревоКатегорийСайта {
    struct Узел {
        let имя: String
        let родитель: String?
        let бренды: [String]
    }

    private(set) var узлы: [String: Узел] = [:]
    private(set) var порядок: [String] = []
    private(set) var корни: [String] = []
    private var дети: [String: [String]] = [:]
    /// MK_CAT_COLOR: корень → «#DC2626».
    private var краски: [String: String] = [:]

    init(_ каталог: КаталогПоиска) {
        краски = каталог.краски
        for ключ in каталог.порядок {
            guard let узел = каталог.узлы[ключ] else { continue }
            узлы[ключ] = Узел(имя: узел.имя.isEmpty ? ключ : узел.имя, родитель: узел.родитель, бренды: узел.бренды)
            порядок.append(ключ)
            if let родитель = узел.родитель {
                дети[родитель, default: []].append(ключ)
            } else {
                корни.append(ключ)
                if краски[ключ] == nil && !узел.краска.isEmpty { краски[ключ] = узел.краска }
            }
        }
    }

    var пустое: Bool { порядок.isEmpty }

    func имя(_ ключ: String) -> String { узлы[ключ]?.имя ?? ключ }

    func родитель(_ ключ: String) -> String? { узлы[ключ]?.родитель }

    func подразделы(_ ключ: String) -> [String] { дети[ключ] ?? [] }

    func марки(_ ключ: String) -> [String] { узлы[ключ]?.бренды ?? [] }

    /// Есть куда войти: подразделы или марки (A(e) сайта). Иначе раздел — лист, и нажатие ведёт в ленту.
    func естьВнутри(_ ключ: String) -> Bool {
        !подразделы(ключ).isEmpty || !марки(ключ).isEmpty
    }

    /// Корень раздела; неизвестный — сам себе корень.
    func корень(_ ключ: String) -> String {
        var текущий = ключ
        var шаги = 0
        while let выше = родитель(текущий), шаги < 12 {
            текущий = выше
            шаги += 1
        }
        return текущий
    }

    /// Путь от корня до раздела включительно (m ulxCatSearchGo).
    func цепочка(_ ключ: String) -> [String] {
        var итог: [String] = []
        var текущий: String? = ключ
        var шаги = 0
        while let т = текущий, шаги < 12 {
            итог.insert(т, at: 0)
            текущий = родитель(т)
            шаги += 1
        }
        return итог
    }

    /// Подпись строки найденного — предки через « › », без самого раздела (T(t) сайта).
    func путьСловами(_ ключ: String) -> String {
        цепочка(ключ).dropLast().map { имя($0) }.joined(separator: " › ")
    }

    /// Краска строки и плитки — краска корня (u(t) сайта).
    func краска(_ ключ: String) -> UIColor {
        let к = корень(ключ)
        if let строка = краски[к], !строка.isEmpty { return Theme.hex(строка) }
        if let раздел = РазделГлавной.с(ключом: к) { return Theme.hex(раздел.краска) }
        return Theme.hex(0x1D7D4A)
    }

    /// ulxCatSearchHTML: имя содержит запрос; сначала совпавшие с начала, потом короче, дальше — порядок дерева; до 60.
    func найти(_ запрос: String) -> [String] {
        let искомое = запрос.lowercased()
        guard !искомое.isEmpty else { return [] }
        var найдено: [(ключ: String, сНачала: Bool, длина: Int, номер: Int)] = []
        for (номер, ключ) in порядок.enumerated() {
            let нижнее = имя(ключ).lowercased()
            guard let место = нижнее.range(of: искомое) else { continue }
            найдено.append((ключ: ключ, сНачала: место.lowerBound == нижнее.startIndex, длина: нижнее.count, номер: номер))
        }
        найдено.sort { a, b in
            if a.сНачала != b.сНачала { return a.сНачала }
            if a.длина != b.длина { return a.длина < b.длина }
            return a.номер < b.номер
        }
        return найдено.prefix(60).map { $0.ключ }
    }
}

// MARK: - Значки

/// Значок раздела — i(t) marketplace-catov: свой SVG у корня (MK_CATS icon), у подраздела — по ключу из таблицы сайта,
/// не нашёлся — у родителя и выше. Здесь — ближайшие SF Symbols.
enum ЗначкиКатегорийСайта {
    /// Значок строки «Все в разделе» и запасной — стопка слоёв сайта.
    static let все = "square.stack.3d.up"

    /// Таблица a[] marketplace-catov.min.js в том же порядке: первое совпадение побеждает.
    private static let таблица: [(String, String)] = [
        (#"computer|desktop|all-in-one|моноблок|компьют|monitor|монитор"#, "desktopcomputer"),
        (#"game|gaming|console|консол|gamepad|геймпад|\bvr\b|vr-|виртуал"#, "gamecontroller"),
        (#"cash|касс"#, "banknote"),
        (#"print|принтер|мфу|scanner|сканер|office|оргтех"#, "printer"),
        (#"headphone|наушник"#, "headphones"),
        (#"watch|часы|браслет"#, "applewatch"),
        (#"speaker|колонк|акустик|receiver|ресивер|theater|кинотеатр|media-player|медиаплеер"#, "hifispeaker"),
        (#"charger|заряд|кабел"#, "powerplug"),
        (#"projector|проектор"#, "videoprojector"),
        (#"network|сетев|router|роутер"#, "wifi"),
        (#"\bups\b|ups-|battery|ибп|аккумулят"#, "battery.100.bolt"),
        (#"keyboard|mouse|клавиат|мыш"#, "keyboard"),
        (#"photo|lens|объектив|mirrorless|беззеркал|camcorder|action-camera|tripod|штатив"#, "camera"),
        (#"food|корм|feed|nutrition"#, "drop"),
        (#"care|уход|груминг"#, "drop"),
        (#"phone|smartphone|\bтелефон"#, "iphone"),
        (#"laptop|notebook|ноут"#, "laptopcomputer"),
        (#"\btv\b|телевизор|телек"#, "tv"),
        (#"cpu|gpu|видеокарт|процессор|компонент|компл"#, "cpu"),
        (#"drone|дрон|квадро"#, "airplane"),
        (#"camera|\bфото|видеокамер"#, "camera"),
        (#"wheel|tire|шин[аы]|диск|колёс|колес"#, "steeringwheel"),
        (#"truck|грузов|газель|фур"#, "truck.box"),
        (#"tow|эвакуат"#, "car.side"),
        (#"\bcar\b|auto|легков|автомобил"#, "car"),
        (#"dog|собак|щен"#, "pawprint"),
        (#"cat|кошк|кот[а-я]?\b|котят"#, "pawprint"),
        (#"bird|птиц|попуга"#, "pawprint"),
        (#"fish|рыб|аквариум"#, "pawprint"),
        (#"rodent|грызун|хомяк|крыс"#, "pawprint"),
        (#"reptil|рептил|амфиб|ящер|зме"#, "pawprint"),
        (#"pet|живот|питом"#, "pawprint"),
        (#"shoe|обув|кросс|ботин"#, "shoe"),
        (#"barbell|gym|фитнес|тренаж|спорт"#, "dumbbell"),
        (#"beauty|космет|красот|парикмах|макияж"#, "scissors"),
        (#"perfum|парфюм|аромат"#, "drop"),
        (#"paint|ремонт|отдел|строй|краск"#, "paintbrush"),
        (#"needle|шить|одежд|ткан|мужск|женск"#, "tshirt"),
        (#"furnitur|мебел|диван|стол|шкаф|интерьер|двер"#, "sofa"),
        (#"tool|инструм|услуг|мастер"#, "wrench.and.screwdriver"),
        (#"bolt|электр|энерг|освещен|свет"#, "bolt"),
        (#"tag|скидк|цена|аксессуар"#, "tag"),
        (#"box|доставк|посылк"#, "shippingbox"),
        (#"home|\bдом\b|недвиж|кварт|участ"#, "house"),
        (#"toy|игрушк|игр[аы]"#, "pawprint"),
        (#"heart|избран"#, "heart")
    ]

    static func значок(_ ключ: String, в дерево: ДеревоКатегорийСайта) -> String {
        var текущий: String? = ключ
        var шаги = 0
        while let т = текущий, шаги < 8 {
            guard let выше = дерево.родитель(т) else { return РазделыСайта.значок(т) }
            if let найден = поКлючу(т) { return найден }
            текущий = выше
            шаги += 1
        }
        return все
    }

    private static func поКлючу(_ ключ: String) -> String? {
        let нижний = ключ.lowercased()
        for (образец, значок) in таблица where нижний.range(of: образец, options: .regularExpression) != nil {
            return значок
        }
        return nil
    }
}

// MARK: - Данные экрана

/// Дерево на языке приложения и числа разделов. Живёт, пока открыт экран.
@MainActor
final class МодельКатегорийСайта: ObservableObject {
    @Published private(set) var дерево: ДеревоКатегорийСайта? = nil
    /// Справочник не пришёл, а показать нечего — строка «Не удалось загрузить» с «Повторить».
    @Published private(set) var неудача = false
    /// Раздел → объявлений в нём и во всех подразделах (mkCatDescendants); только больше нуля.
    @Published private(set) var итоги: [String: Int] = [:]
    private var сырые: [String: Int] = [:]
    private var грузим = false

    init() {
        if let готовый = ЗагрузкаКаталогаПоиска.сейчас, !готовый.пустой {
            дерево = ДеревоКатегорийСайта(готовый)
        }
    }

    func число(_ ключ: String) -> Int { итоги[ключ] ?? 0 }

    func загрузить() async {
        guard !грузим else { return }
        грузим = true
        defer { грузим = false }
        неудача = false
        let каталог = await ЗагрузкаКаталогаПоиска.получить()
        if !каталог.пустой {
            дерево = ДеревоКатегорийСайта(каталог)
        } else if дерево == nil {
            неудача = true
        }
        пересчитать()
        сырые = await Self.числа()
        пересчитать()
    }

    /// counts=1, как mkLoadCounts; при регионе или районе сайт чисел не показывает (_mkCountsHonest).
    private static func числа() async -> [String: Int] {
        let где = ГдеИскать.сохранённое()
        guard ГлавнаяAPI.счётЧестный(где) else { return [:] }
        let куки = await SiteSession.куки()
        guard let ответ = try? await ГлавнаяAPI.числа(где, куки: куки) else { return [:] }
        return ответ.счёт
    }

    private func пересчитать() {
        guard let дерево, !сырые.isEmpty else {
            итоги = [:]
            return
        }
        var суммы: [String: Int] = [:]
        for (ключ, сколько) in сырые where сколько > 0 {
            var текущий: String? = ключ
            var шаги = 0
            while let т = текущий, шаги < 12 {
                суммы[т, default: 0] += сколько
                текущий = дерево.родитель(т)
                шаги += 1
            }
        }
        /* «Товары» главной — набор корней (MK_VSETS.goods), своего узла в дереве у него нет. */
        let товары = СчётРазделов.наборТоваров.reduce(0) { итог, ключ in итог + (суммы[ключ] ?? 0) }
        if товары > 0 { суммы["goods"] = товары }
        итоги = суммы
    }
}

/// Шаг стека уровней — раздел, чьи подразделы на экране.
struct ШагКатегорийСайта: Hashable {
    let ключ: String
}

// MARK: - Экран

struct ЭкранКатегорийСайта: View {
    /// Копия нижней панели сайта поверх экрана: она видна над плитками, уровни её закрывают, как #mk-catov сайта.
    let панель: НижняяПанельСайта
    let местоПодПанелью: CGFloat
    let открыть: (URL) -> Void
    let закрыть: () -> Void
    /// Лента с разделом (и маркой в поиске) — экран закрывает вызывающий.
    let перейти: (ИскомоеЛенты) -> Void

    @StateObject private var модель = МодельКатегорийСайта()
    @State private var путь: [ШагКатегорийСайта] = []
    /// Плитки разделов главной: у сайта в хабе шесть из семи (MK_HOME_V сервера, _mhHubShuffle при входе на главную),
    /// режим категорий показывает те же шесть, седьмой нет. Здесь — новые шесть на каждое открытие (как на главной).
    @State private var шесть: [РазделГлавной]
    /// Две «тяжёлые» плитки (is-prio): первые две из шести после тасовки.
    @State private var сплошные: [РазделГлавной]
    @State private var слайды: [БаннерГлавной.Слайд]

    init(панель: НижняяПанельСайта, местоПодПанелью: CGFloat, открыть: @escaping (URL) -> Void,
         закрыть: @escaping () -> Void, перейти: @escaping (ИскомоеЛенты) -> Void) {
        self.панель = панель
        self.местоПодПанелью = местоПодПанелью
        self.открыть = открыть
        self.закрыть = закрыть
        self.перейти = перейти
        let новые = ПодборкиГлавной.новыеПлитки()
        _шесть = State(initialValue: новые)
        _сплошные = State(initialValue: Array(новые.prefix(2)))
        _слайды = State(initialValue: БаннерГлавной.слайды.shuffled())
    }

    var body: some View {
        NavigationStack(path: $путь) {
            КореньКатегорийСайта(модель: модель, панель: панель, местоПодПанелью: местоПодПанелью,
                                 шесть: шесть, сплошные: сплошные, слайды: слайды, открыть: открыть, закрыть: закрыть,
                                 плитка: { ключ in нажатьПлитку(ключ) },
                                 найденное: { ключ in нажатьНайденное(ключ) })
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ШагКатегорийСайта.self) { шаг in
                    УровеньКатегорийСайта(модель: модель, ключ: шаг.ключ,
                                          назад: { if !путь.isEmpty { путь.removeLast() } },
                                          кКорню: { путь.removeAll() },
                                          войти: { ключ in войти(ключ) },
                                          вЛенту: { ключ, марка in вЛенту(ключ, марка: марка) })
                }
        }
        .task { await модель.загрузить() }
    }

    /// Плитка: раздел главной — его лента (mkHomeGo), остальной корень — его подразделы (ulxCatOpenAt).
    private func нажатьПлитку(_ ключ: String) {
        if РазделГлавной.с(ключом: ключ) != nil {
            вЛенту(ключ, марка: "")
        } else if let дерево = модель.дерево, дерево.естьВнутри(ключ) {
            путь = [ШагКатегорийСайта(ключ: ключ)]
        } else {
            вЛенту(ключ, марка: "")
        }
    }

    /// Строка найденного: с подразделами — панель на этом разделе с полным путём (ulxCatSearchGo), лист — лента.
    private func нажатьНайденное(_ ключ: String) {
        guard let дерево = модель.дерево, дерево.естьВнутри(ключ) else {
            вЛенту(ключ, марка: "")
            return
        }
        путь = дерево.цепочка(ключ).map { ШагКатегорийСайта(ключ: $0) }
    }

    /// Подраздел уровня (ulxCatPick): есть что внутри — следующий уровень, иначе лента.
    private func войти(_ ключ: String) {
        if let дерево = модель.дерево, дерево.естьВнутри(ключ) {
            путь.append(ШагКатегорийСайта(ключ: ключ))
        } else {
            вЛенту(ключ, марка: "")
        }
    }

    /// ulxCatGo / ulxBrandGo: лента с разделом; «Работа» — вакансии, как плитка главной.
    private func вЛенту(_ ключ: String, марка: String) {
        ОткликСайта.выбор()
        let корень = модель.дерево?.корень(ключ) ?? ключ
        if корень == "jobs" {
            закрыть()
            if Config.нижниеВкладки {
                ОкноВакансий.открыть(nil)
            } else if let адрес = Config.страницаСайта("?cat=jobs") {
                открыть(адрес)
            }
            return
        }
        перейти(ИскомоеЛенты(текст: марка, раздел: ключ))
    }
}

// MARK: - Плитки и поиск (режим mk-cats главной)

private struct КореньКатегорийСайта: View {
    @ObservedObject var модель: МодельКатегорийСайта
    let панель: НижняяПанельСайта
    let местоПодПанелью: CGFloat
    let шесть: [РазделГлавной]
    let сплошные: [РазделГлавной]
    let слайды: [БаннерГлавной.Слайд]
    let открыть: (URL) -> Void
    let закрыть: () -> Void
    let плитка: (String) -> Void
    let найденное: (String) -> Void

    @State private var запрос = ""
    @FocusState private var вФокусе: Bool
    /// Плитки поднимаются по очереди при первом показе (mk-cats-in, mhRise).
    @State private var поднялись = false
    @Environment(\.colorScheme) private var схема

    private static let зазор: CGFloat = 10

    init(модель: МодельКатегорийСайта, панель: НижняяПанельСайта, местоПодПанелью: CGFloat,
         шесть: [РазделГлавной], сплошные: [РазделГлавной], слайды: [БаннерГлавной.Слайд],
         открыть: @escaping (URL) -> Void,
         закрыть: @escaping () -> Void, плитка: @escaping (String) -> Void, найденное: @escaping (String) -> Void) {
        self.модель = модель
        self.панель = панель
        self.местоПодПанелью = местоПодПанелью
        self.шесть = шесть
        self.сплошные = сплошные
        self.слайды = слайды
        self.открыть = открыть
        self.закрыть = закрыть
        self.плитка = плитка
        self.найденное = найденное
    }

    var body: some View {
        GeometryReader { место in
            let высота = высотаПлитки(место.size.height + место.safeAreaInsets.top + место.safeAreaInsets.bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    шапка
                        .modifier(ПодъёмКатегорийСайта(видно: поднялись, задержка: 0))
                    if чистыйЗапрос.isEmpty {
                        сетка(высота)
                    } else {
                        найденноеКарточкой
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .оставитьМестоПодПанелью(местоПодПанелью)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            /* Как у сайта: с клавиатурой панели нет. */
            if !вФокусе {
                панель
            }
        }
        .onAppear {
            ПанельПоПрокрутке.shared.сбросить()
            if !поднялись { поднялись = true }
        }
    }

    private var тёмная: Bool { схема == .dark }

    private var чистыйЗапрос: String {
        запрос.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// .mh-hub: grid-auto-rows clamp(92px, (50svh − 44px) / 3, 140px).
    private func высотаПлитки(_ экран: CGFloat) -> CGFloat {
        min(140, max(92, (экран * 0.5 - 44) / 3))
    }

    // MARK: Шапка: «‹» и «Найти категорию» (.mh-csearch)

    private var шапка: some View {
        HStack(spacing: 4) {
            КнопкаШапкиКатегорий(значок: "chevron.backward", подпись: КатегорииText.т("back"), действие: закрыть)
            поле
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
    }

    private var поле: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(КатегорииText.т("find"), text: $запрос)
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($вФокусе)
            if !запрос.isEmpty {
                Button { запрос = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .fill(Theme.поверхность
                    .shadow(.drop(color: Self.тень.opacity(тёмная ? 0 : 0.06), radius: 1, x: 0, y: 1))
                    .shadow(.drop(color: Self.тень.opacity(тёмная ? 0 : 0.14), radius: 8, x: 0, y: 6)))
        }
        .overlay {
            if тёмная {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { вФокусе = true }
    }

    private static let тень = Color(red: 16 / 255, green: 40 / 255, blue: 28 / 255)

    // MARK: Сетка плиток

    private func сетка(_ высота: CGFloat) -> some View {
        VStack(spacing: Self.зазор) {
            HStack(spacing: Self.зазор) {
                БаннерГлавной(слайды: слайды, открыть: открыть)
                    .frame(maxWidth: .infinity)
                    .frame(height: высота * 2 + Self.зазор)
                VStack(spacing: Self.зазор) {
                    ForEach(сплошные) { раздел in
                        ПлиткаРаздела(раздел: раздел, название: DesignText.т("v_" + раздел.ключ),
                                      счёт: числоИлиНет(раздел.ключ), готово: true, сплошная: true, высота: высота,
                                      действие: { плитка(раздел.ключ) })
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(ПодъёмКатегорийСайта(видно: поднялись, задержка: 0.06))
            if let дерево = модель.дерево {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Self.зазор), GridItem(.flexible(), spacing: Self.зазор)],
                          spacing: Self.зазор) {
                    ForEach(Array(светлые(дерево).enumerated()), id: \.element) { номер, ключ in
                        светлаяПлитка(ключ, дерево: дерево, высота: высота)
                            .modifier(ПодъёмКатегорийСайта(видно: поднялись, задержка: 0.12 + 0.045 * Double(min(номер, 12))))
                    }
                }
            } else if модель.неудача {
                неудача
            } else {
                SiteSpinner.крупный
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            }
        }
        .padding(.horizontal, 16)
        /* Высоты плиток постоянные, как на сайте: дальше этого размера текста подписи в них не помещаются. */
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Светлые плитки в порядке --co сайта: из разделов главной — остальные четыре из шести (седьмого у сайта в хабе
    /// нет), остальные корни MK_CATS (.mh-tile--cat) — все, как были. «Товары» своего корня в дереве не имеют
    /// (--co 99) — в конце.
    private func светлые(_ дерево: ДеревоКатегорийСайта) -> [String] {
        let тяжёлые = Set(сплошные.map { $0.ключ })
        let показанные = Set(шесть.map { $0.ключ })
        let корни = дерево.корни.filter { ключ in
            if тяжёлые.contains(ключ) { return false }
            if РазделГлавной.с(ключом: ключ) != nil { return показанные.contains(ключ) }
            return true
        }
        let вДереве = Set(корни)
        let вне = шесть.map { $0.ключ }.filter { ключ in
            !тяжёлые.contains(ключ) && !вДереве.contains(ключ) && дерево.узлы[ключ] == nil
        }
        return корни + вне
    }

    private func числоИлиНет(_ ключ: String) -> Int? {
        let n = модель.число(ключ)
        return n > 0 ? n : nil
    }

    private func светлаяПлитка(_ ключ: String, дерево: ДеревоКатегорийСайта, высота: CGFloat) -> some View {
        let раздел = РазделГлавной.с(ключом: ключ)
        let название = раздел != nil ? DesignText.т("v_" + ключ) : дерево.имя(ключ)
        let n = модель.число(ключ)
        let подпись: String
        if n > 0 {
            подпись = ключ == "jobs" ? DesignText.вакансий(n) : DesignText.предложений(n)
        } else if раздел != nil {
            подпись = DesignText.т("sub_" + ключ)
        } else {
            подпись = дерево.подразделы(ключ).prefix(3).map { дерево.имя($0) }.joined(separator: ", ")
        }
        return ПлиткаКатегорийСайта(название: название, подпись: подпись, числом: n > 0, краска: дерево.краска(ключ),
                                    картинка: раздел?.картинка, значок: РазделыСайта.значок(ключ), высота: высота,
                                    действие: { плитка(ключ) })
    }

    private var неудача: some View {
        VStack(spacing: 10) {
            Text(DesignText.т("fail"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
            Button {
                Task { await модель.загрузить() }
            } label: {
                Text(DesignText.т("retry"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Theme.оттенокАкцента, in: Capsule())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Найденное (#mh-cres)

    @ViewBuilder
    private var найденноеКарточкой: some View {
        if let дерево = модель.дерево {
            let ключи = дерево.найти(чистыйЗапрос)
            VStack(spacing: 0) {
                if ключи.isEmpty {
                    Text(КатегорииText.т("none"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(Array(ключи.enumerated()), id: \.element) { номер, ключ in
                        if номер > 0 { РазделительКатегорий() }
                        СтрокаКатегорийСайта(название: дерево.имя(ключ), подпись: дерево.путьСловами(ключ),
                                             число: модель.число(ключ),
                                             значок: ЗначкиКатегорийСайта.значок(ключ, в: дерево), инициалы: nil,
                                             краска: дерево.краска(ключ), всё: false,
                                             действие: { найденное(ключ) })
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .fill(Theme.поверхность
                        .shadow(.drop(color: Self.тень.opacity(тёмная ? 0 : 0.06), radius: 1, x: 0, y: 1)))
            }
            .overlay {
                if тёмная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
            }
            .padding(.horizontal, 16)
        } else {
            SiteSpinner.крупный
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        }
    }
}

/// mhRise: подъём на 16 pt с проявлением, 0,36 с по cubic-bezier(.2,.8,.2,1). При «Уменьшении движения» — сразу.
private struct ПодъёмКатегорийСайта: ViewModifier {
    let видно: Bool
    let задержка: Double

    init(видно: Bool, задержка: Double) {
        self.видно = видно
        self.задержка = задержка
    }

    func body(content: Content) -> some View {
        content
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 16)
            .animation(ДвижениеСайта.мягко(Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.36).delay(задержка)),
                       value: видно)
    }
}

/// Светлая плитка режима категорий (html.mk-cats .mh-hub>.mh-tile:not(.is-prio)): градиент по краске корня, круг
/// в углу, название 16 pt, число предложений или подразделы, картинка раздела главной или значок корня 64 pt.
private struct ПлиткаКатегорийСайта: View {
    let название: String
    let подпись: String
    /// Подпись — число (.mh-tile-n), а не подразделы (.is-sub).
    let числом: Bool
    let краска: UIColor
    let картинка: URL?
    let значок: String
    let высота: CGFloat
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема

    init(название: String, подпись: String, числом: Bool, краска: UIColor, картинка: URL?, значок: String,
         высота: CGFloat, действие: @escaping () -> Void) {
        self.название = название
        self.подпись = подпись
        self.числом = числом
        self.краска = краска
        self.картинка = картинка
        self.значок = значок
        self.высота = высота
        self.действие = действие
    }

    var body: some View {
        Button(action: { ОткликСайта.выбор(); действие() }) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(stops: остановки, startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                /* ::after — круг 104 pt за правым нижним краем: 10 % краски, в тёмной 16 %. */
                Circle()
                    .fill(Color(uiColor: краска).opacity(тёмная ? 0.16 : 0.1))
                    .frame(width: 104, height: 104)
                    .offset(x: 22, y: 30)
                картинкаПлитки
                    .accessibilityHidden(true)
                подписи
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: высота)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(название + ", " + подпись)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var картинкаПлитки: some View {
        if let картинка {
            let размер = min(высота * 0.72, 88)
            КартинкаЛенты(картинка, пунктов: размер, заполнить: false) {
                Color.clear
            }
            .frame(width: размер, height: размер)
            .padding(.trailing, 6)
            .padding(.bottom, 4)
        } else {
            Image(systemName: значок)
                .font(.system(size: 36, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: краска))
                .frame(width: 64, height: 64)
                .padding(.trailing, 4)
                .padding(.bottom, 4)
        }
    }

    private var подписи: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(название)
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.16)
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
            if числом {
                Text(подпись)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(цветСчёта)
                    .lineLimit(1)
            } else if !подпись.isEmpty {
                Text(подпись)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 60)
        .padding(.vertical, 12)
    }

    private var тёмная: Bool { схема == .dark }

    /// linear-gradient(150deg, …): от 22 % краски к 7 % на поверхности (в тёмной 26 % → 14 %).
    private var остановки: [Gradient.Stop] {
        let поверхность = тёмная ? Theme.hex(0x16161F) : UIColor.white
        let конец = Color(uiColor: Theme.смесь(краска, поверхность, тёмная ? 0.14 : 0.07))
        return [
            Gradient.Stop(color: Color(uiColor: Theme.смесь(краска, поверхность, тёмная ? 0.26 : 0.22)), location: 0),
            Gradient.Stop(color: конец, location: тёмная ? 0.62 : 0.7),
            Gradient.Stop(color: конец, location: 1)
        ]
    }

    /// .mh-tile-n: 82 % краски с чернилами, в тёмной — 55 % с белым.
    private var цветСчёта: Color {
        if тёмная { return Color(uiColor: Theme.смесь(краска, UIColor.white, 0.55)) }
        return Color(uiColor: Theme.смесь(краска, Theme.hex(0x13211B), 0.82))
    }
}

// MARK: - Уровень подразделов (#mk-catov)

private struct УровеньКатегорийСайта: View {
    @ObservedObject var модель: МодельКатегорийСайта
    let ключ: String
    let назад: () -> Void
    let кКорню: () -> Void
    let войти: (String) -> Void
    let вЛенту: (String, String) -> Void

    init(модель: МодельКатегорийСайта, ключ: String, назад: @escaping () -> Void, кКорню: @escaping () -> Void,
         войти: @escaping (String) -> Void, вЛенту: @escaping (String, String) -> Void) {
        self.модель = модель
        self.ключ = ключ
        self.назад = назад
        self.кКорню = кКорню
        self.войти = войти
        self.вЛенту = вЛенту
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                if let дерево = модель.дерево {
                    LazyVStack(spacing: 0) {
                        строки(дерево)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                } else {
                    SiteSpinner.крупный
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        /* Системная шапка спрятана — жест «от края — назад» возвращает посредник, как у страницы объявления. */
        .background(СмахнутьНазад().frame(width: 0, height: 0))
    }

    /// .ctg-h: сетка 48 | название | 48, высота 56, по бокам 8.
    private var шапка: some View {
        HStack(spacing: 0) {
            КнопкаШапкиКатегорий(значок: "chevron.backward", подпись: КатегорииText.т("back"), действие: назад)
                .frame(width: 48)
            Text(модель.дерево?.имя(ключ) ?? "")
                .font(.system(size: 16, weight: .heavy))
                .tracking(-0.16)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            КнопкаШапкиКатегорий(значок: "xmark", подпись: DesignText.т("close"), действие: кКорню)
                .frame(width: 48)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 56)
    }

    @ViewBuilder
    private func строки(_ дерево: ДеревоКатегорийСайта) -> some View {
        let подразделы = дерево.подразделы(ключ)
        let краска = дерево.краска(ключ)
        if !подразделы.isEmpty {
            СтрокаКатегорийСайта(название: String(format: КатегорииText.т("all_in"), дерево.имя(ключ)), подпись: nil,
                                 число: модель.число(ключ), значок: ЗначкиКатегорийСайта.все, инициалы: nil,
                                 краска: краска, всё: true, действие: { вЛенту(ключ, "") })
            ForEach(подразделы, id: \.self) { подраздел in
                РазделительКатегорий()
                СтрокаКатегорийСайта(название: дерево.имя(подраздел), подпись: nil, число: модель.число(подраздел),
                                     значок: ЗначкиКатегорийСайта.значок(подраздел, в: дерево), инициалы: nil,
                                     краска: краска, всё: false, действие: { войти(подраздел) })
            }
        } else {
            /* Лист с марками: «Все» и марки (кружок с буквами марки — логотипы у сайта SVG). */
            СтрокаКатегорийСайта(название: КатегорииText.т("all"), подпись: nil, число: модель.число(ключ),
                                 значок: ЗначкиКатегорийСайта.все, инициалы: nil, краска: краска, всё: true,
                                 действие: { вЛенту(ключ, "") })
            ForEach(дерево.марки(ключ), id: \.self) { марка in
                РазделительКатегорий()
                СтрокаКатегорийСайта(название: марка, подпись: nil, число: 0, значок: nil,
                                     инициалы: Self.буквы(марка), краска: краска, всё: false,
                                     действие: { вЛенту(ключ, марка) })
            }
        }
    }

    /// .ctg-logo i: две первые буквы или цифры марки заглавными.
    private static func буквы(_ марка: String) -> String {
        let буквы = String(марка.filter { $0.isLetter || $0.isNumber }.prefix(2)).uppercased()
        return буквы.isEmpty ? "?" : буквы
    }
}

// MARK: - Части

/// .ctg-row: значок 40 × 40 на подложке краски, название, подпись пути, число и «›»; высота от 56.
private struct СтрокаКатегорийСайта: View {
    let название: String
    let подпись: String?
    let число: Int
    let значок: String?
    /// Марка: белый кружок с буквами вместо значка (.ctg-brand .ctg-logo).
    let инициалы: String?
    let краска: UIColor
    /// .is-all — «Все в разделе»: название жирнее.
    let всё: Bool
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема

    init(название: String, подпись: String?, число: Int, значок: String?, инициалы: String?, краска: UIColor,
         всё: Bool, действие: @escaping () -> Void) {
        self.название = название
        self.подпись = подпись
        self.число = число
        self.значок = значок
        self.инициалы = инициалы
        self.краска = краска
        self.всё = всё
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                иконка
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(название)
                        .font(.system(size: 15, weight: всё ? .heavy : .semibold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                    if let подпись, !подпись.isEmpty {
                        Text(подпись)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if число > 0 {
                    Text(DesignText.число(число))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.текстВторой)
                }
                Image(systemName: "chevron.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 4)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСтрокиКатегорий())
    }

    @ViewBuilder
    private var иконка: some View {
        if let инициалы {
            Text(инициалы)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color(uiColor: Theme.hex(0x5F6C63)))
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
                .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
        } else {
            Image(systemName: значок ?? ЗначкиКатегорийСайта.все)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(цветЗначка)
                .frame(width: 40, height: 40)
                .background(подложка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
    }

    private var тёмная: Bool { схема == .dark }

    /// .ctg-row-ic: 12 % краски на поверхности (в тёмной 22 %).
    private var подложка: Color {
        let поверхность = тёмная ? Theme.hex(0x16161F) : UIColor.white
        return Color(uiColor: Theme.смесь(краска, поверхность, тёмная ? 0.22 : 0.12))
    }

    /// Значок — краска, в тёмной — 60 % краски с белым.
    private var цветЗначка: Color {
        тёмная ? Color(uiColor: Theme.смесь(краска, UIColor.white, 0.6)) : Color(uiColor: краска)
    }
}

/// .ctg-row+.ctg-row::before — линия от 52 pt до правого края.
private struct РазделительКатегорий: View {
    init() {}

    var body: some View {
        Theme.линия
            .frame(height: 1)
            .padding(.leading, 52)
            .accessibilityHidden(true)
    }
}

/// .ctg-row:active — подложка --mk-surf2 под строкой.
private struct НажатиеСтрокиКатегорий: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.поверхность2 : Color.clear)
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}

/// .ctg-ib сайта (#mk-catov-back, .ctg-x): круг 40 pt без фона и рамки, значок цвета текста (SVG 22 px, линия 2,2);
/// под пальцем — подложка --mk-surf2, как :hover сайта.
private struct КнопкаШапкиКатегорий: View {
    let значок: String
    let подпись: String
    let действие: () -> Void

    init(значок: String, подпись: String, действие: @escaping () -> Void) {
        self.значок = значок
        self.подпись = подпись
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: значок == "xmark" ? 17 : 19, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиШапкиКатегорий())
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(подпись)
    }
}

private struct НажатиеКнопкиШапкиКатегорий: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(configuration.isPressed ? Theme.поверхность2 : Color.clear))
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}
