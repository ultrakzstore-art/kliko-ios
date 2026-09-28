import Foundation

/**
 СТАТЬЯ СТРАНИЦЫ САЙТА → НАТИВНЫЕ БЛОКИ (этап 50, владелец: «всё приложение нативным»).

 Справочный центр (/kz/<язык>/help и его разделы #safe, #pro, #rules), соглашение, оферта, политика, «Оплата и возврат»,
 «Тарифы» — у сайта это статические страницы без API (карта кабинета §6.8.3). Приложение качает ту же страницу и
 вынимает из неё только статью. Никакого WebView и никакого NSAttributedString(html:) (он поднимает WebKit на главном
 потоке): свой разбор тегов, текст — AttributedString с жирным, курсивом и ссылками.

 Что понимает разбор:
   · заголовки h1–h6, абзацы, цитаты, подписи (figcaption), разделители;
   · списки ul/ol любой вложенности: маркер, номер (start), продолжение пункта (второй <p> внутри <li>) — с отступом
     пункта, а не голым абзацем; dl — термин жирным, определение с отступом;
   · вопросы-ответы: <details>/<summary> (open — раскрыт) и раскрывашки на скрипте — кнопка или элемент с классом
     вопроса (faq-q, accordion-button, …) либо aria-expanded, а ответ — следующий за ним элемент, даже скрытый hidden
     или display:none (сайт раскрывает его скриптом);
   · таблицы — ячейками (шапка из <th>), вложенная таблица — текстом ячейки;
   · картинки статьи (src, data-src; значки, логотипы, SVG и мелочь — мимо);
   · ссылка-карточка (<a> с блоками внутри: плитки разделов справки) — одной карточкой: заголовок и подпись;
   · незакрытые <p>, <li>, <a>, <b> — закрываются вместе с родителем, как у браузера.

 Где статья: <main>, иначе <article>, иначе <body>. Шапка, подвал, меню, формы, поиск, скрипты, стили, SVG, скрытое
 (hidden, aria-hidden, display:none — кроме ответов и вкладок) и окна (modal, overlay, toast, drawer, bottombar, cookie,
 popup, sheet) — мимо. Якоря (id, name) прилипают к следующему блоку: help#safe прокручивает к нему. Ссылки на оплату
 услуг (продвижение, ТОП, PRO, покупка) из статьи вынимаются: в приложении их нет (правило App Store 3.1.1).

 Чистые функции без главного потока — их зовут из Task.detached.
 */

/// Блок статьи.
struct БлокСтатьи: Identifiable {
    enum Вид {
        case заголовок(Int)
        case абзац
        /// Пункт списка: маркер («•», «1.»; пусто — продолжение пункта) и глубина вложенности (1…).
        case пункт(маркер: String, уровень: Int)
        case цитата
        /// Подпись к картинке, мелкий серый текст.
        case примечание
        case разделитель
        /// Раскрывашка: вопрос — текст блока, ответ — вложенные блоки; открыт — <details open>.
        case вопрос([БлокСтатьи], открыт: Bool)
        /// Таблица: строки ячеек; шапка — первая строка из <th>.
        case таблица([[AttributedString]], шапка: Bool)
        /// Картинка статьи; пропорция — ширина к высоте из атрибутов, если были. Текст блока — alt.
        case картинка(URL, пропорция: Double?)
        /// Ссылка-карточка: текст — заголовок, подпись — остальное.
        case карточка(URL)
    }

    let id: Int
    var вид: Вид
    var текст: AttributedString
    var подпись: String
    /// Якоря (id/name элементов), что стояли перед блоком.
    var якоря: [String]

    init(id: Int, вид: Вид, текст: AttributedString, подпись: String = "", якоря: [String] = []) {
        self.id = id
        self.вид = вид
        self.текст = текст
        self.подпись = подпись
        self.якоря = якоря
    }

    /// Простой текст без разметки — для оглавления и VoiceOver.
    var простой: String { String(текст.characters) }

    /// Весь текст блока с ответами и ячейками — для поиска по справке.
    var весьТекст: String {
        var части: [String] = [простой, подпись]
        switch вид {
        case .вопрос(let ответ, _):
            for блок in ответ { части.append(блок.весьТекст) }
        case .таблица(let строки, _):
            for строка in строки {
                for ячейка in строка { части.append(String(ячейка.characters)) }
            }
        case .картинка:
            return ""
        default:
            break
        }
        return части.joined(separator: " ")
    }

    /// Есть ли у блока якорь (без учёта регистра).
    func естьЯкорь(_ искомый: String) -> Bool {
        якоря.contains(where: { $0.lowercased() == искомый })
    }
}

/// Раздел статьи: блоки от заголовка второго уровня до следующего — одна карточка экрана.
struct РазделСтатьи: Identifiable {
    let id: Int
    let блоки: [БлокСтатьи]
}

/// Разобранная статья.
struct СтатьяСайта {
    var заголовок: String
    var блоки: [БлокСтатьи]

    /// Годится ли статья: хотя бы два блока с текстом (страница, собранная скриптом, даст пустоту — тогда сайт).
    var годится: Bool {
        блоки.filter { !$0.простой.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count >= 2
    }

    /// Заголовки разделов (h2 и h1, кроме первого) — оглавление вверху.
    var разделы: [БлокСтатьи] {
        let первый = первыйЗаголовок?.id
        return блоки.filter {
            guard $0.id != первый else { return false }
            if case .заголовок(let уровень) = $0.вид { return уровень <= 2 }
            return false
        }
    }

    /// Первый h1 статьи, если он стоит до всякого текста, — заголовок страницы над карточками.
    var первыйЗаголовок: БлокСтатьи? {
        for блок in блоки {
            if case .заголовок(1) = блок.вид { return блок }
            if case .картинка = блок.вид { continue }
            if case .разделитель = блок.вид { continue }
            return nil
        }
        return nil
    }

    /// Есть ли плитки-ссылки (своя навигация страницы) — тогда оглавление лишнее.
    var естьКарточки: Bool {
        блоки.contains(where: {
            if case .карточка = $0.вид { return true }
            return false
        })
    }

    /**
     Блоки по карточкам экрана: всё до первого h2 — одна, дальше — каждая от h2 до следующего h2. Первый h1 —
     заголовок страницы, он стоит над карточками отдельно (ЭкранСтраницыСайта), в карточки не попадает; следующие h1
     (если сайт ими делит разделы) — как h2.
     */
    var части: [РазделСтатьи] {
        var итог: [РазделСтатьи] = []
        var текущие: [БлокСтатьи] = []
        let первый = первыйЗаголовок?.id
        for блок in блоки {
            if блок.id == первый { continue }
            if case .заголовок(let уровень) = блок.вид {
                if уровень <= 2, !текущие.isEmpty {
                    итог.append(РазделСтатьи(id: текущие[0].id, блоки: текущие))
                    текущие = []
                }
            }
            текущие.append(блок)
        }
        if !текущие.isEmpty { итог.append(РазделСтатьи(id: текущие[0].id, блоки: текущие)) }
        /* Карточка из одного разделителя — пустая рамка. */
        return итог.filter { часть in
            часть.блоки.contains(where: {
                if case .разделитель = $0.вид { return false }
                return true
            })
        }
    }

    /// Блок с якорем (или вопрос, внутри которого он) — id верхнего блока.
    func блок(якоря якорь: String) -> Int? {
        let искомый = якорь.lowercased()
        for блок in блоки {
            if блок.естьЯкорь(искомый) { return блок.id }
            if case .вопрос(let ответ, _) = блок.вид, СтатьяСайта.естьЯкорь(искомый, в: ответ) {
                return блок.id
            }
        }
        return nil
    }

    private static func естьЯкорь(_ искомый: String, в блоки: [БлокСтатьи]) -> Bool {
        for блок in блоки {
            if блок.естьЯкорь(искомый) { return true }
            if case .вопрос(let ответ, _) = блок.вид, естьЯкорь(искомый, в: ответ) { return true }
        }
        return false
    }
}

enum РазборСтатьи {

    // MARK: - Вход

    static func разобрать(_ html: String, адрес: URL) -> СтатьяСайта {
        let заголовокСтраницы = заголовокTitle(html)
        let корень = вырезатьКорень(html)
        let чистый = убратьЛишнее(корень)
        var разбор = Разбор(база: адрес)
        разбор.пройти(Array(чистый.unicodeScalars))
        разбор.закончить()
        var заголовок = разбор.первыйH1
        if заголовок.isEmpty { заголовок = заголовокСтраницы }
        return СтатьяСайта(заголовок: заголовок, блоки: разбор.итог)
    }

    // MARK: - Корень статьи

    private static func вырезатьКорень(_ html: String) -> String {
        for тег in ["main", "article", "body"] {
            if let внутри = внутренность(html, тег: тег) { return внутри }
        }
        return html
    }

    /// Содержимое первого <тег …> до последнего </тег>. <mainframe> и «<main» внутри строк скрипта — мимо.
    private static func внутренность(_ html: String, тег: String) -> String? {
        let допустимые: Set<Character> = [">", " ", "\n", "\t", "\r", "/"]
        var откуда = html.startIndex
        while let начало = html.range(of: "<" + тег, options: .caseInsensitive, range: откуда..<html.endIndex) {
            let после = html[начало.upperBound...]
            guard let первый = после.first, допустимые.contains(первый),
                  let конецОткрытия = после.firstIndex(of: ">") else {
                откуда = начало.upperBound
                continue
            }
            let тело = html[html.index(after: конецОткрытия)...]
            guard let закрытие = тело.range(of: "</" + тег, options: [.caseInsensitive, .backwards]) else {
                return String(тело)
            }
            return String(тело[..<закрытие.lowerBound])
        }
        return nil
    }

    private static func заголовокTitle(_ html: String) -> String {
        guard let внутри = внутренность(html, тег: "title") else { return "" }
        var текст = декодировать(внутри).trimmingCharacters(in: .whitespacesAndNewlines)
        /* «Помощь — Kliko.kz» → «Помощь». */
        for разделитель in [" — ", " | ", " - ", " · ", " – "] {
            if let r = текст.range(of: разделитель) { текст = String(текст[..<r.lowerBound]) }
        }
        return текст
    }

    /// Комментарии и элементы с сырым текстом (скрипты, стили, SVG, шаблоны, поля ввода) — целиком прочь.
    private static func убратьЛишнее(_ html: String) -> String {
        var итог = html
        let шаблоны = [
            "<!--[\\s\\S]*?-->",
            "<(script|style|noscript|svg|template|iframe|select|textarea|canvas|video|audio|object|math)\\b[\\s\\S]*?</\\1\\s*>"
        ]
        for шаблон in шаблоны {
            guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive]) else { continue }
            let весь = NSRange(итог.startIndex..<итог.endIndex, in: итог)
            итог = выражение.stringByReplacingMatches(in: итог, options: [], range: весь, withTemplate: " ")
        }
        return итог
    }

    // MARK: - Ссылки на оплату

    private static let оплатаВыражение = try? NSRegularExpression(
        pattern: "promote|checkout|payment|topup|top-up|[?&](go|s|open|buy|tab)=(pro|top|promo|premium|aipack|ai_pack|slots?|combo|buy|pay|coupon|club)([&#]|$)|[?&](top|promo|buy|pay|coupon)=|/(pay|buy|billing)(\\.php)?(/|\\?|#|$)",
        options: [.caseInsensitive])

    /// Ссылка на оплату платных услуг сайта (продвижение, ТОП, PRO, пакеты, покупка) — в приложении не показывается.
    static func оплата(_ адрес: URL) -> Bool {
        guard let выражение = оплатаВыражение else { return false }
        /* Якорь страницы (#payment в справке) — не оплата: смотрим адрес без него. */
        var части = URLComponents(url: адрес, resolvingAgainstBaseURL: false)
        части?.fragment = nil
        /* Страницы справки и подвала (help?topic=promote, oplata) — сведения, а не оплата. */
        let путь = (части?.path ?? адрес.path).lowercased()
        if путь.range(of: "/(help|soglashenie|oferta|privacy|oplata|tarify)(\\.php)?(/|$)", options: .regularExpression) != nil {
            return false
        }
        let строка = части?.url?.absoluteString ?? адрес.absoluteString
        let весь = NSRange(строка.startIndex..<строка.endIndex, in: строка)
        return выражение.firstMatch(in: строка, options: [], range: весь) != nil
    }

    // MARK: - Сущности

    private static let именные: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "laquo": "«", "raquo": "»",
        "mdash": "—", "ndash": "–", "hellip": "…", "minus": "−", "copy": "©", "reg": "®", "trade": "™", "rarr": "→",
        "larr": "←", "uarr": "↑", "darr": "↓", "harr": "↔", "middot": "·", "bull": "•", "times": "×", "divide": "÷",
        "deg": "°", "shy": "", "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}", "lsquo": "‘",
        "rsquo": "’", "ldquo": "“", "rdquo": "”", "bdquo": "„", "sbquo": "‚", "prime": "′", "Prime": "″",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "tenge": "₸", "numero": "№", "sect": "§", "para": "¶",
        "plusmn": "±", "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "infin": "∞", "frac12": "½", "frac14": "¼",
        "frac34": "¾", "sup1": "¹", "sup2": "²", "sup3": "³", "check": "✓", "star": "☆", "hearts": "♥",
        "iexcl": "¡", "iquest": "¿", "zwj": "", "zwnj": "", "lrm": "", "rlm": "", "zwsp": ""
    ]

    /// &amp; &#8212; &#x2014; и прочие — в символы.
    static func декодировать(_ текст: String) -> String {
        guard текст.contains("&") else { return текст }
        var итог = ""
        итог.reserveCapacity(текст.count)
        var i = текст.startIndex
        while i < текст.endIndex {
            let c = текст[i]
            guard c == "&", let конец = текст[i...].prefix(12).firstIndex(of: ";") else {
                итог.append(c)
                i = текст.index(after: i)
                continue
            }
            let имя = String(текст[текст.index(after: i)..<конец])
            if let замена = сущность(имя) {
                итог += замена
                i = текст.index(after: конец)
            } else {
                итог.append(c)
                i = текст.index(after: i)
            }
        }
        return итог
    }

    private static func сущность(_ имя: String) -> String? {
        if имя.hasPrefix("#") {
            let число = имя.dropFirst()
            let код: UInt32?
            if число.hasPrefix("x") || число.hasPrefix("X") {
                код = UInt32(число.dropFirst(), radix: 16)
            } else {
                код = UInt32(число, radix: 10)
            }
            guard let значение = код, let скаляр = Unicode.Scalar(значение) else { return nil }
            /* Невидимые (мягкий перенос, нулевой ширины, метки направления) — прочь. */
            let невидимые: [UInt32] = [0xAD, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF]
            if невидимые.contains(значение) { return "" }
            return String(Character(скаляр))
        }
        if let точное = именные[имя] { return точное }
        return именные[имя.lowercased()]
    }

    // MARK: - Проход по тегам

    /// Кусок строки текста со своим начертанием.
    private struct Кусок {
        var текст: String
        var жирный: Bool
        var курсив: Bool
        var ссылка: URL?
    }

    /**
     Открытая раскрывашка. <details>: глубина — место самого <details> в стеке. На скрипте (кнопка): глубины нет,
     вопросГлубина — место кнопки, ответГлубина — её родителя (ответ — следующий в нём элемент), ответЭлемент — место
     элемента-ответа, когда он открылся.
     */
    private struct Раскрытие {
        var глубина: Int?
        var открыт = false
        var вопрос = AttributedString()
        var якоряВопроса: [String] = []
        var блоки: [БлокСтатьи] = []
        var вопросГлубина: Int?
        var ответГлубина: Int?
        var ответЭлемент: Int?
        var подъёмов = 0

        var поКнопке: Bool { глубина == nil }
        /// Вопрос по кнопке прочитан, ответ ещё не начался.
        var ждётОтвет: Bool { глубина == nil && вопросГлубина == nil && ответЭлемент == nil && ответГлубина != nil }
    }

    /// Открытый список: нумерованный или нет, счётчик и место в стеке.
    private struct Список {
        let нумерованный: Bool
        var номер: Int
        let глубина: Int
    }

    /// Открытая ссылка: адрес, место в стеке и где начались её блоки (для ссылки-карточки).
    private struct ОткрытаяСсылка {
        let адрес: URL?
        let глубина: Int
        let уровень: Int
        let начало: Int
        var блочная = false
        /// Ссылка на оплату услуг: плитка или кнопка с ней убирается целиком.
        var оплатная = false
    }

    /// Открытая таблица: готовые строки, текущая строка и шапка.
    private struct Таблица {
        var строки: [[AttributedString]] = []
        var строка: [AttributedString] = []
        var строкаИзTh = true
        var шапка = false
    }

    private struct Разбор {
        let база: URL
        var итог: [БлокСтатьи] = []
        var первыйH1 = ""

        private var стек: [String] = []
        private var глубинаПропуска: Int? = nil
        private var куски: [Кусок] = []
        private var видСейчас: БлокСтатьи.Вид = .абзац
        /// Места в стеке открытых <b>/<strong>/<dt> и <i>/<em>: незакрытый тег гаснет с родителем.
        private var жирные: [Int] = []
        private var курсивы: [Int] = []
        private var ссылки: [ОткрытаяСсылка] = []
        private var якоря: [String] = []
        private var раскрытия: [Раскрытие] = []
        private var списки: [Список] = []
        /// Места открытых <li> и <dd>: второй абзац пункта — продолжение с отступом.
        private var пункты: [Int] = []
        private var цитаты: [Int] = []
        private var вВопросе = false
        private var таблица: Таблица? = nil
        private var вЯчейке = false
        private var вложенныеТаблицы = 0
        private var счётчик = 0
        private var пробелБыл = true

        init(база: URL) {
            self.база = база
        }

        private static let пустые: Set<String> = ["br", "img", "hr", "input", "meta", "link", "source", "wbr", "area",
                                                   "base", "col", "embed", "param", "track"]
        private static let пропускаемые: Set<String> = ["header", "footer", "nav", "form", "dialog", "aside", "label",
                                                        "map", "fieldset", "legend", "search", "menu"]
        private static let блочные: Set<String> = ["p", "div", "section", "blockquote", "tr", "dd", "dt", "figcaption",
                                                   "table", "ul", "ol", "li", "details", "summary", "h1", "h2", "h3",
                                                   "h4", "h5", "h6", "pre", "address", "center", "dl", "tbody", "thead",
                                                   "tfoot", "figure", "caption", "article", "main", "hgroup"]
        private static let окна = try? NSRegularExpression(
            pattern: "(^|[\\s_-])(modal|overlay|toast|drawer|bottombar|bottom-bar|bb|cookie|cookies|popup|sheet|sr-only|visually-hidden|skip|breadcrumbs?|crumbs|share|tabbar|topbar|navbar|menu|search|searchbar|totop|scrolltop|lang|langs|feedback|helpful|vote|rating)([\\s_-]|$)",
            options: [.caseInsensitive])
        /// Скрытое, которое сайт показывает скриптом: ответы, панели, вкладки.
        private static let раскрываемое = try? NSRegularExpression(
            pattern: "(answer|ans|panel|collapse|content|body|faq|acc|tab|spoiler|more|details|text)",
            options: [.caseInsensitive])

        // MARK: Проход

        mutating func пройти(_ з: [Unicode.Scalar]) {
            var i = 0
            var текст = String.UnicodeScalarView()
            let n = з.count
            while i < n {
                let c = з[i]
                if c == "<", i + 1 < n, Разбор.начало(з[i + 1]) {
                    if !текст.isEmpty {
                        принятьТекст(String(текст))
                        текст = String.UnicodeScalarView()
                    }
                    var j = i + 1
                    var кавычка: Unicode.Scalar? = nil
                    while j < n {
                        let d = з[j]
                        if let к = кавычка {
                            if d == к { кавычка = nil }
                        } else if d == "\"" || d == "'" {
                            кавычка = d
                        } else if d == ">" {
                            break
                        }
                        j += 1
                    }
                    var внутри = String.UnicodeScalarView()
                    внутри.append(contentsOf: з[(i + 1)..<min(j, n)])
                    принятьТег(String(внутри))
                    i = j + 1
                } else {
                    текст.append(c)
                    i += 1
                }
            }
            if !текст.isEmpty { принятьТекст(String(текст)) }
        }

        /// Конец страницы: всё незакрытое — закрыть.
        mutating func закончить() {
            стек.removeAll()
            if вЯчейке { закончитьЯчейку() }
            if таблица != nil { закончитьТаблицу() }
            if вВопросе { закончитьВопрос() }
            сбросить()
            while !раскрытия.isEmpty { закончитьРаскрытие() }
            while !ссылки.isEmpty { закрытьСсылку() }
            сбросить()
        }

        private static func начало(_ c: Unicode.Scalar) -> Bool {
            c == "/" || c == "!" || (c.properties.isAlphabetic && c.isASCII)
        }

        // MARK: Теги

        private mutating func принятьТег(_ сырой: String) {
            if сырой.hasPrefix("!") { return }
            let закрывающий = сырой.hasPrefix("/")
            let тело = закрывающий ? String(сырой.dropFirst()) : сырой
            let имя = String(тело.prefix(while: { $0.isLetter || $0.isNumber })).lowercased()
            guard !имя.isEmpty else { return }
            if закрывающий {
                закрыть(имя)
            } else {
                let самозакрытый = тело.hasSuffix("/") || Разбор.пустые.contains(имя)
                открыть(имя, атрибуты: Разбор.атрибуты(тело), самозакрытый: самозакрытый)
            }
        }

        private mutating func открыть(_ имя: String, атрибуты: [String: String], самозакрытый: Bool) {
            if глубинаПропуска != nil {
                if !самозакрытый { стек.append(имя) }
                return
            }
            /* Раскрывашка по кнопке ждёт ответ: следующий элемент родителя — ответ, даже скрытый. */
            var ответСейчас = false
            if !самозакрытый, let последнее = раскрытия.last, последнее.ждётОтвет,
               let родитель = последнее.ответГлубина, стек.count == родитель {
                ответСейчас = true
            }
            if !самозакрытый { стек.append(имя) }
            if пропустить(имя, атрибуты, ответ: ответСейчас) {
                if !самозакрытый { глубинаПропуска = стек.count }
                return
            }
            let вопрос = !вВопросе && !самозакрытый && !вЯчейке && Разбор.этоВопрос(имя, атрибуты)
            /* Кнопка не вопроса (в вопросе — его часть): интерфейс сайта («Копировать», «Наверх»), мимо. */
            if имя == "button", !вВопросе, !вопрос {
                if !самозакрытый { глубинаПропуска = стек.count }
                return
            }
            var якорь: String? = nil
            if let значение = атрибуты["id"] ?? атрибуты["name"], !значение.isEmpty, имя != "meta" {
                якорь = значение
            }
            if вЯчейке {
                if let якорь { якоря.append(якорь) }
                открытьВЯчейке(имя, атрибуты: атрибуты)
                return
            }
            if вопрос {
                /* Новый вопрос-кнопка, пока прежний ждёт ответ, — прежний без ответа. */
                if let последнее = раскрытия.last, последнее.ждётОтвет {
                    закончитьРаскрытие()
                }
                начатьВопросКнопкой()
                if let якорь { якоря.append(якорь) }
                return
            }
            if ответСейчас, !раскрытия.isEmpty {
                раскрытия[раскрытия.count - 1].ответЭлемент = стек.count
            }
            let блочный = Разбор.блочные.contains(имя) || заголовок(имя) != nil
            /* Текст до блока — свой абзац, а якорь блока — самому блоку, а не этому абзацу. */
            if блочный { сбросить() }
            if let якорь { якоря.append(якорь) }
            if блочный, !вВопросе, !ссылки.isEmpty {
                ссылки[ссылки.count - 1].блочная = true
            }
            /* Внутри плитки каждая часть (значок, название, подпись) — своим куском: заголовок и подпись порознь. */
            if !вВопросе, let последняя = ссылки.last, последняя.блочная, стек.count == последняя.глубина + 1 {
                сбросить()
            }
            switch имя {
            case "br":
                перенос()
            case "hr":
                сбросить()
                добавить(.разделитель, AttributedString())
            case "img":
                картинка(атрибуты)
            case "b", "strong":
                if !самозакрытый { жирные.append(стек.count) }
            case "i", "em", "cite", "dfn":
                if !самозакрытый { курсивы.append(стек.count) }
            case "a":
                guard !самозакрытый else { break }
                let сырой = адрес(атрибуты["href"])
                let оплатная = сырой.map { РазборСтатьи.оплата($0) } ?? false
                /* Плитка или кнопка-ссылка сайта (class="help-card", "btn", …) — карточкой, даже без блоков внутри. */
                let этоПлитка = !вВопросе && Разбор.плитка(атрибуты["class"] ?? "")
                if этоПлитка { сбросить() }
                let контейнер = раскрытия.last?.блоки.count ?? итог.count
                ссылки.append(ОткрытаяСсылка(адрес: оплатная ? nil : сырой, глубина: стек.count,
                                             уровень: раскрытия.count, начало: контейнер, блочная: этоПлитка,
                                             оплатная: оплатная))
            case "table":
                if таблица != nil {
                    вложенныеТаблицы += 1
                } else {
                    сбросить()
                    таблица = Таблица()
                }
            case "tr":
                if таблица != nil, вложенныеТаблицы == 0 {
                    закончитьСтроку()
                    таблица?.строкаИзTh = true
                }
            case "td", "th":
                if таблица != nil, вложенныеТаблицы == 0 {
                    начатьЯчейку(th: имя == "th")
                }
            case "caption":
                сбросить()
                видСейчас = .примечание
            case "ul", "ol":
                сбросить()
                списки.append(Список(нумерованный: имя == "ol", номер: Int(атрибуты["start"] ?? "") ?? 1,
                                     глубина: стек.count))
            case "li":
                сбросить()
                var маркер = "•"
                if var последний = списки.last {
                    if последний.нумерованный {
                        if let значение = Int(атрибуты["value"] ?? "") { последний.номер = значение }
                        маркер = String(последний.номер) + "."
                        последний.номер += 1
                        списки[списки.count - 1] = последний
                    } else if списки.count > 1 {
                        маркер = "◦"
                    }
                }
                пункты.append(стек.count)
                видСейчас = .пункт(маркер: маркер, уровень: max(1, списки.count))
            case "dt":
                сбросить()
                жирные.append(стек.count)
            case "dd":
                сбросить()
                пункты.append(стек.count)
                видСейчас = .пункт(маркер: "", уровень: max(1, списки.count + 1))
            case "details":
                guard !вВопросе else { break }
                сбросить()
                var новое = Раскрытие()
                новое.глубина = стек.count
                новое.открыт = атрибуты["open"] != nil
                раскрытия.append(новое)
            case "summary":
                if !вВопросе, var последнее = раскрытия.last, последнее.глубина != nil, последнее.вопросГлубина == nil,
                   последнее.вопрос.characters.isEmpty {
                    сбросить()
                    последнее.вопросГлубина = стек.count
                    раскрытия[раскрытия.count - 1] = последнее
                    вВопросе = true
                } else {
                    сбросить()
                    жирные.append(стек.count)
                }
            case "blockquote":
                сбросить()
                цитаты.append(стек.count)
                видСейчас = .цитата
            case "figcaption":
                сбросить()
                видСейчас = .примечание
            default:
                if let уровень = заголовок(имя) {
                    сбросить()
                    видСейчас = .заголовок(уровень)
                } else if блочный {
                    сбросить()
                }
            }
        }

        private mutating func закрыть(_ имя: String) {
            guard let место = стек.lastIndex(of: имя) else { return }
            стек.removeSubrange(место...)
            if let глубина = глубинаПропуска {
                if стек.count < глубина { глубинаПропуска = nil }
                подчистить()
                return
            }
            if вЯчейке {
                закрытьВЯчейке(имя)
                подчистить()
                return
            }
            switch имя {
            case "table":
                if вложенныеТаблицы > 0 {
                    вложенныеТаблицы -= 1
                } else {
                    закончитьТаблицу()
                }
            case "tr":
                if вложенныеТаблицы == 0 { закончитьСтроку() }
            case "caption":
                сбросить()
                видСейчас = .абзац
            case "li", "dd", "dt", "blockquote", "figcaption", "h1", "h2", "h3", "h4", "h5", "h6":
                сбросить()
                видСейчас = .абзац
            default:
                if Разбор.блочные.contains(имя) {
                    сбросить()
                }
            }
            подчистить()
        }

        /// После любого закрытия: погасить всё, что было открыто внутри закрытого (как браузер с незакрытыми тегами).
        private mutating func подчистить() {
            let n = стек.count
            if вЯчейке, !стек.contains("td"), !стек.contains("th") {
                закончитьЯчейку()
            }
            if таблица != nil, вложенныеТаблицы == 0, !стек.contains("table") {
                закончитьТаблицу()
            }
            if вВопросе, let последнее = раскрытия.last, let г = последнее.вопросГлубина, г > n {
                закончитьВопрос()
            }
            while let последнее = раскрытия.last {
                if let г = последнее.глубина {
                    guard г > n else { break }
                    закончитьРаскрытие()
                    continue
                }
                if последнее.вопросГлубина != nil { break }
                if let э = последнее.ответЭлемент {
                    guard э > n else { break }
                    закончитьРаскрытие()
                    continue
                }
                if let родитель = последнее.ответГлубина, родитель > n {
                    /* Кнопка была одна в обёртке (<h3><button>…</button></h3>): ответ — сосед обёртки. */
                    if последнее.подъёмов < 1, последнее.блоки.isEmpty {
                        раскрытия[раскрытия.count - 1].ответГлубина = n
                        раскрытия[раскрытия.count - 1].подъёмов += 1
                        break
                    }
                    закончитьРаскрытие()
                    continue
                }
                break
            }
            while let последняя = ссылки.last, последняя.глубина > n {
                закрытьСсылку()
            }
            жирные.removeAll { $0 > n }
            курсивы.removeAll { $0 > n }
            списки.removeAll { $0.глубина > n }
            пункты.removeAll { $0 > n }
            цитаты.removeAll { $0 > n }
        }

        private func заголовок(_ имя: String) -> Int? {
            guard имя.count == 2, имя.hasPrefix("h"), let уровень = Int(String(имя.dropFirst())),
                  (1...6).contains(уровень) else { return nil }
            return уровень
        }

        private func пропустить(_ имя: String, _ атрибуты: [String: String], ответ: Bool) -> Bool {
            if Разбор.пропускаемые.contains(имя) { return true }
            if (атрибуты["role"] ?? "").lowercased() == "dialog" { return true }
            if (атрибуты["role"] ?? "").lowercased() == "tablist" { return true }
            let класс = (атрибуты["class"] ?? "") + " " + (атрибуты["id"] ?? "")
            if let окна = Разбор.окна {
                let весь = NSRange(класс.startIndex..<класс.endIndex, in: класс)
                if окна.firstMatch(in: класс, options: [], range: весь) != nil { return true }
            }
            /* Скрытое: ответ раскрывашки, вкладку и панель сайт показывает скриптом — их оставляем. */
            let стиль = (атрибуты["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            let скрыто = атрибуты["hidden"] != nil || (атрибуты["aria-hidden"] ?? "").lowercased() == "true"
                || стиль.contains("display:none") || стиль.contains("visibility:hidden")
            guard скрыто else { return false }
            if ответ { return false }
            let роль = (атрибуты["role"] ?? "").lowercased()
            if роль == "tabpanel" || роль == "region" { return false }
            if имя == "img" { return true }
            if let раскрываемое = Разбор.раскрываемое {
                let весь = NSRange(класс.startIndex..<класс.endIndex, in: класс)
                if раскрываемое.firstMatch(in: класс, options: [], range: весь) != nil { return false }
            }
            return true
        }

        /// Начало вопроса раскрывашки на скрипте: кнопка с aria-expanded / aria-controls, data-toggle=collapse или
        /// элемент с классом вопроса (faq-q, faq__question, accordion-button, spoiler-head, …).
        private static func этоВопрос(_ имя: String, _ атрибуты: [String: String]) -> Bool {
            let пропуск: Set<String> = ["a", "li", "ul", "ol", "table", "tr", "td", "th", "details", "summary", "img",
                                        "br", "hr", "section", "main", "article", "p"]
            if пропуск.contains(имя) { return false }
            let класс = (атрибуты["class"] ?? "").lowercased()
            let переключатель = (атрибуты["data-toggle"] ?? атрибуты["data-bs-toggle"] ?? "").lowercased()
            let роль = (атрибуты["role"] ?? "").lowercased()
            if имя == "button" {
                if атрибуты["aria-expanded"] != nil || атрибуты["aria-controls"] != nil { return true }
                if переключатель == "collapse" { return true }
                if классВопроса(класс) { return true }
                /* Кнопка в вопросах сайта (class="faq-item") — тоже вопрос, иначе её текст пропал бы. */
                let вопросные = ["faq", "accordion", "spoiler", "collapse"]
                return вопросные.contains(where: { класс.contains($0) })
            }
            if роль == "button", атрибуты["aria-expanded"] != nil || атрибуты["aria-controls"] != nil { return true }
            if переключатель == "collapse" { return true }
            return классВопроса(класс)
        }

        private static func классВопроса(_ класс: String) -> Bool {
            let корни: Set<String> = ["faq", "faqs", "acc", "accordion", "accord", "spoiler", "collapse", "collapsible",
                                      "qa", "expand", "expander", "question", "vopros"]
            let хвосты: Set<String> = ["q", "question", "head", "header", "heading", "title", "toggle", "btn",
                                       "button", "trigger", "summary", "ask"]
            for слово in класс.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }) {
                /* Одно слово («question», «faq») — скорее обёртка вопроса с ответом, чем сам вопрос. */
                let части = слово.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
                guard части.count >= 2, let последняя = части.last else { continue }
                if хвосты.contains(последняя), части.dropLast().contains(where: { корни.contains($0) }) { return true }
            }
            return false
        }

        /// Адрес ссылки без проверки на оплату (для плитки: понять, что она ведёт к оплате, и убрать её).
        private func адрес(_ href: String?) -> URL? {
            guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                  !href.lowercased().hasPrefix("javascript:") else { return nil }
            let чистый = РазборСтатьи.декодировать(href)
            let результат: URL?
            if чистый.hasPrefix("#") {
                guard чистый.count > 1 else { return nil }
                var части = URLComponents(url: база, resolvingAgainstBaseURL: false)
                части?.fragment = String(чистый.dropFirst())
                результат = части?.url
            } else if let прямой = URL(string: чистый, relativeTo: база) {
                результат = прямой.absoluteURL
            } else {
                let закодированный = чистый.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? чистый
                результат = URL(string: закодированный, relativeTo: база)?.absoluteURL
            }
            return результат
        }

        private func ссылка(_ href: String?) -> URL? {
            guard let готовый = адрес(href), !РазборСтатьи.оплата(готовый) else { return nil }
            return готовый
        }

        private static let плиткаВыражение = try? NSRegularExpression(
            pattern: "(^|[\\s_-])(card|cards|tile|tiles|cat|cats|category|topic|topics|box|block|btn|button|cta)([\\s_-]|$)",
            options: [.caseInsensitive])

        private static func плитка(_ класс: String) -> Bool {
            guard !класс.isEmpty, let выражение = плиткаВыражение else { return false }
            let весь = NSRange(класс.startIndex..<класс.endIndex, in: класс)
            return выражение.firstMatch(in: класс, options: [], range: весь) != nil
        }

        // MARK: Картинки

        private mutating func картинка(_ а: [String: String]) {
            guard !вВопросе, !вЯчейке else { return }
            var источник = а["data-src"] ?? а["data-lazy-src"] ?? а["data-original"] ?? ""
            if источник.isEmpty { источник = а["src"] ?? "" }
            let нижний = источник.lowercased()
            if нижний.isEmpty || нижний.hasPrefix("data:") || нижний.contains(".svg") { return }
            let класс = (а["class"] ?? "").lowercased()
            let значки = ["icon", "ico", "logo", "emoji", "avatar", "flag", "badge", "spinner", "pixel", "loader"]
            if значки.contains(where: { класс.contains($0) }) { return }
            let ширина = Разбор.число(а["width"])
            let высота = Разбор.число(а["height"])
            if let ш = ширина, ш < 64 { return }
            if let в = высота, в < 64 { return }
            guard let адрес = ссылка(источник) else { return }
            var пропорция: Double? = nil
            if let ш = ширина, let в = высота, в > 0, ш > 0 { пропорция = ш / в }
            сбросить()
            добавить(.картинка(адрес, пропорция: пропорция), AttributedString(а["alt"] ?? ""))
        }

        private static func число(_ строка: String?) -> Double? {
            guard let строка else { return nil }
            let цифры = строка.prefix(while: { $0.isNumber || $0 == "." })
            return Double(String(цифры))
        }

        // MARK: Таблицы

        private mutating func начатьЯчейку(th: Bool) {
            куски = []
            пробелБыл = true
            вЯчейке = true
            if !th { таблица?.строкаИзTh = false }
        }

        private mutating func закончитьЯчейку() {
            guard вЯчейке else { return }
            let ячейка = собрать()
            куски = []
            пробелБыл = true
            вЯчейке = false
            вложенныеТаблицы = 0
            таблица?.строка.append(ячейка)
        }

        private mutating func закончитьСтроку() {
            if вЯчейке { закончитьЯчейку() }
            guard var т = таблица else { return }
            let строка = т.строка
            т.строка = []
            if строка.contains(where: { !$0.characters.isEmpty }) {
                if т.строки.isEmpty, т.строкаИзTh { т.шапка = true }
                т.строки.append(строка)
            }
            т.строкаИзTh = true
            таблица = т
        }

        private mutating func закончитьТаблицу() {
            закончитьСтроку()
            guard let т = таблица else { return }
            таблица = nil
            вложенныеТаблицы = 0
            куски = []
            пробелБыл = true
            guard !т.строки.isEmpty else { return }
            let колонок = т.строки.map { $0.count }.max() ?? 0
            if колонок <= 1 {
                /* Таблица в одну колонку — вёрстка, а не данные: строки абзацами. */
                for строка in т.строки {
                    if let ячейка = строка.first, !ячейка.characters.isEmpty { добавить(.абзац, ячейка) }
                }
                return
            }
            добавить(.таблица(т.строки, шапка: т.шапка), AttributedString())
        }

        /// Внутри ячейки блоки — переносами строки, вложенная таблица — текстом.
        private mutating func открытьВЯчейке(_ имя: String, атрибуты: [String: String]) {
            switch имя {
            case "br", "tr":
                if имя == "tr", вложенныеТаблицы == 0 {
                    закончитьСтроку()
                    return
                }
                перенос()
            case "b", "strong", "dt":
                жирные.append(стек.count)
            case "i", "em":
                курсивы.append(стек.count)
            case "a":
                ссылки.append(ОткрытаяСсылка(адрес: ссылка(атрибуты["href"]), глубина: стек.count,
                                             уровень: раскрытия.count, начало: Int.max))
            case "table":
                вложенныеТаблицы += 1
                перенос()
            case "td", "th":
                if вложенныеТаблицы == 0 {
                    /* Прежняя ячейка без </td>. */
                    закончитьЯчейку()
                    начатьЯчейку(th: имя == "th")
                } else if куски.contains(where: { !$0.текст.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    куски.append(Кусок(текст: " · ", жирный: false, курсив: false, ссылка: nil))
                    пробелБыл = true
                }
            case "li":
                перенос()
                if !куски.isEmpty {
                    куски.append(Кусок(текст: "• ", жирный: false, курсив: false, ссылка: nil))
                    пробелБыл = true
                }
            default:
                if Разбор.блочные.contains(имя) { перенос() }
            }
        }

        private mutating func закрытьВЯчейке(_ имя: String) {
            switch имя {
            case "table":
                if вложенныеТаблицы > 0 {
                    вложенныеТаблицы -= 1
                } else {
                    закончитьТаблицу()
                }
            case "td", "th":
                if вложенныеТаблицы == 0 { закончитьЯчейку() }
            case "tr":
                if вложенныеТаблицы == 0 { закончитьСтроку() } else { перенос() }
            default:
                if Разбор.блочные.contains(имя) { перенос() }
            }
        }

        // MARK: Раскрывашки

        private mutating func начатьВопросКнопкой() {
            сбросить()
            var новое = Раскрытие()
            новое.вопросГлубина = стек.count
            раскрытия.append(новое)
            вВопросе = true
        }

        /// Вопрос прочитан: <summary> закрылся или кнопка (элемент-вопрос).
        private mutating func закончитьВопрос() {
            guard var последнее = раскрытия.last else {
                вВопросе = false
                return
            }
            последнее.вопрос = Разбор.очиститьВопрос(собрать())
            последнее.якоряВопроса += якоря
            якоря = []
            куски = []
            пробелБыл = true
            вВопросе = false
            видСейчас = .абзац
            последнее.вопросГлубина = nil
            if последнее.поКнопке {
                последнее.ответГлубина = стек.count
            }
            if последнее.поКнопке && последнее.вопрос.characters.isEmpty {
                /* Кнопка-значок без текста («+», «×») — не вопрос. */
                раскрытия.removeLast()
                return
            }
            раскрытия[раскрытия.count - 1] = последнее
        }

        private mutating func закончитьРаскрытие() {
            if вВопросе {
                let было = раскрытия.count
                закончитьВопрос()
                /* Пустая кнопка-значок уже снята — её раскрывашка и была последней. */
                if раскрытия.count < было { return }
            }
            сбросить()
            guard let готовое = раскрытия.popLast() else { return }
            let вопрос = готовое.вопрос
            if вопрос.characters.isEmpty {
                /* <details> без <summary>: содержимое как есть. */
                for блок in готовое.блоки { положить(блок) }
                return
            }
            if готовое.блоки.isEmpty {
                /* Ответа нет — вопрос жирной строкой. */
                счётчик += 1
                положить(БлокСтатьи(id: счётчик, вид: .абзац, текст: вопрос, якоря: готовое.якоряВопроса))
                return
            }
            счётчик += 1
            положить(БлокСтатьи(id: счётчик, вид: .вопрос(готовое.блоки, открыт: готовое.открыт), текст: вопрос,
                                якоря: готовое.якоряВопроса))
        }

        /// Значки раскрывашки по краям вопроса («+», «›», «▾») — прочь.
        private static func очиститьВопрос(_ строка: AttributedString) -> AttributedString {
            let значки: Set<Character> = ["+", "−", "–", "-", "›", "»", "▾", "▼", "⌄", "˅", "∨", "×", "✕", "⌃", "▸", "▶",
                                          "❯", "〉", "↓", "⏷", "▿"]
            var итог = строка
            while let последний = итог.characters.last, последний.isWhitespace || значки.contains(последний) {
                let до = итог.characters.index(before: итог.endIndex)
                итог.removeSubrange(до..<итог.endIndex)
            }
            while let первый = итог.characters.first, первый.isWhitespace || (значки.contains(первый) && первый != "-") {
                итог.removeSubrange(итог.startIndex..<итог.characters.index(after: итог.startIndex))
            }
            return итог
        }

        // MARK: Ссылки-карточки

        private mutating func закрытьСсылку() {
            guard let открытая = ссылки.last else { return }
            if открытая.блочная {
                сбросить()
            }
            ссылки.removeLast()
            guard открытая.блочная, открытая.уровень == раскрытия.count else { return }
            var контейнер = раскрытия.last?.блоки ?? итог
            guard открытая.начало < контейнер.count else { return }
            guard let адрес = открытая.адрес else {
                /* Плитка «Продвинуть», «Купить ТОП» — в приложении её нет вовсе (правило App Store 3.1.1). */
                if открытая.оплатная {
                    контейнер.removeSubrange(открытая.начало...)
                    сохранить(контейнер)
                }
                return
            }
            let свои = Array(контейнер[открытая.начало...])
            /* Картинки и значки в плитке — украшение; заголовок — первый блок с буквами. */
            let текстовые = свои.filter { блок in
                if case .картинка = блок.вид { return false }
                if case .разделитель = блок.вид { return false }
                return блок.простой.contains(where: { $0.isLetter || $0.isNumber })
            }
            guard let первый = текстовые.first else { return }
            контейнер.removeSubrange(открытая.начало...)
            var заголовок = AttributedString(первый.простой)
            заголовок.inlinePresentationIntent = .stronglyEmphasized
            let подпись = текстовые.dropFirst().map { $0.простой }.joined(separator: " ")
            let якоряКарточки = свои.flatMap { $0.якоря }
            счётчик += 1
            контейнер.append(БлокСтатьи(id: счётчик, вид: .карточка(адрес), текст: заголовок, подпись: подпись,
                                        якоря: якоряКарточки))
            сохранить(контейнер)
        }

        /// Блоки текущего места (статья или ответ раскрывашки) — обратно.
        private mutating func сохранить(_ контейнер: [БлокСтатьи]) {
            if раскрытия.isEmpty {
                итог = контейнер
            } else {
                раскрытия[раскрытия.count - 1].блоки = контейнер
            }
        }

        // MARK: Текст

        private mutating func принятьТекст(_ сырой: String) {
            guard глубинаПропуска == nil else { return }
            let текст = РазборСтатьи.декодировать(сырой)
            var чистый = ""
            чистый.reserveCapacity(текст.count)
            for c in текст {
                if c.isWhitespace && c != "\u{00A0}" {
                    if !пробелБыл { чистый.append(" ") }
                    пробелБыл = true
                } else {
                    чистый.append(c)
                    пробелБыл = false
                }
            }
            guard !чистый.isEmpty else { return }
            /* Текст прямо у родителя кнопки-вопроса, а не в соседнем элементе, — у вопроса ответа нет. */
            if !вЯчейке, let последнее = раскрытия.last, последнее.ждётОтвет,
               чистый.contains(where: { !$0.isWhitespace }) {
                закончитьРаскрытие()
            }
            куски.append(Кусок(текст: чистый, жирный: !жирные.isEmpty, курсив: !курсивы.isEmpty,
                               ссылка: ссылки.last?.адрес))
        }

        /// <br> и блок внутри ячейки: перенос строки без пробела перед ним и не больше одной пустой строки.
        private mutating func перенос() {
            guard let последний = куски.last else { return }
            if последний.текст.hasSuffix(" ") {
                куски[куски.count - 1].текст = String(последний.текст.dropLast())
            }
            let хвост = куски.suffix(2).map { $0.текст }
            if хвост.count == 2, хвост.allSatisfy({ $0 == "\n" }) { return }
            куски.append(Кусок(текст: "\n", жирный: false, курсив: false, ссылка: nil))
            пробелБыл = true
        }

        /// Куски → AttributedString без пробелов по краям.
        private func собрать() -> AttributedString {
            var итог = AttributedString()
            for кусок in куски where !кусок.текст.isEmpty {
                var часть = AttributedString(кусок.текст)
                var намерение: InlinePresentationIntent = []
                if кусок.жирный || вВопросе { намерение.insert(.stronglyEmphasized) }
                if кусок.курсив { намерение.insert(.emphasized) }
                if !намерение.isEmpty { часть.inlinePresentationIntent = намерение }
                if let ссылка = кусок.ссылка { часть.link = ссылка }
                итог.append(часть)
            }
            return обрезать(итог)
        }

        private func обрезать(_ строка: AttributedString) -> AttributedString {
            var итог = строка
            while let первый = итог.characters.first, первый.isWhitespace {
                итог.removeSubrange(итог.startIndex..<итог.characters.index(after: итог.startIndex))
            }
            while let последний = итог.characters.last, последний.isWhitespace {
                let до = итог.characters.index(before: итог.endIndex)
                итог.removeSubrange(до..<итог.endIndex)
            }
            return итог
        }

        /**
         Закончить текущий блок. Вид блока остаётся, пока текста не было: у <li><p>…</p></li> пункт не превращается
         в абзац. Второй абзац внутри пункта — продолжение пункта (без маркера, с тем же отступом), внутри цитаты —
         цитата.
         */
        mutating func сбросить() {
            guard !вВопросе, !вЯчейке, !куски.isEmpty else { return }
            let текст = собрать()
            куски = []
            пробелБыл = true
            var вид = видСейчас
            видСейчас = .абзац
            guard !текст.characters.isEmpty else { return }
            if case .абзац = вид {
                if !цитаты.isEmpty {
                    вид = .цитата
                } else if !пункты.isEmpty {
                    вид = .пункт(маркер: "", уровень: max(1, списки.count))
                }
            }
            if case .заголовок(1) = вид, первыйH1.isEmpty {
                первыйH1 = String(текст.characters)
            }
            добавить(вид, текст)
        }

        private mutating func добавить(_ вид: БлокСтатьи.Вид, _ текст: AttributedString) {
            счётчик += 1
            let блок = БлокСтатьи(id: счётчик, вид: вид, текст: текст, якоря: якоря)
            якоря = []
            положить(блок)
        }

        private mutating func положить(_ блок: БлокСтатьи) {
            if раскрытия.isEmpty {
                итог.append(блок)
            } else {
                раскрытия[раскрытия.count - 1].блоки.append(блок)
            }
        }

        // MARK: Атрибуты

        /// name="value", name='value', name=value, name — в словарь (имена строчными, значения с сущностями).
        static func атрибуты(_ тело: String) -> [String: String] {
            var итог: [String: String] = [:]
            let з = Array(тело.unicodeScalars)
            var i = 0
            /* Имя тега пропускаем. */
            while i < з.count, !Разбор.пробел(з[i]) { i += 1 }
            while i < з.count {
                while i < з.count, Разбор.пробел(з[i]) || з[i] == "/" { i += 1 }
                var имя = String.UnicodeScalarView()
                while i < з.count, !Разбор.пробел(з[i]), з[i] != "=", з[i] != "/" {
                    имя.append(з[i])
                    i += 1
                }
                if имя.isEmpty { i += 1; continue }
                while i < з.count, Разбор.пробел(з[i]) { i += 1 }
                var значение = String.UnicodeScalarView()
                if i < з.count, з[i] == "=" {
                    i += 1
                    while i < з.count, Разбор.пробел(з[i]) { i += 1 }
                    if i < з.count, з[i] == "\"" || з[i] == "'" {
                        let кавычка = з[i]
                        i += 1
                        while i < з.count, з[i] != кавычка {
                            значение.append(з[i])
                            i += 1
                        }
                        i += 1
                    } else {
                        while i < з.count, !Разбор.пробел(з[i]) {
                            значение.append(з[i])
                            i += 1
                        }
                    }
                }
                let ключ = String(имя).lowercased()
                if итог[ключ] == nil {
                    итог[ключ] = РазборСтатьи.декодировать(String(значение))
                }
            }
            return итог
        }

        private static func пробел(_ c: Unicode.Scalar) -> Bool {
            c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{0C}"
        }
    }
}

// MARK: - «Тарифы» без цен и покупок

/**
 Страница «Тарифы» в приложении — только описание (правило App Store 3.1.1, платные услуги продаются лишь на сайте):
 блоки с ценой («990 ₸», «от 4 990 тг/мес») и призывы купить («Купить», «Подключить», «Оплатить») — прочь, цена из
 заголовка тарифа («PRO — 4 990 ₸/мес» → «PRO») — прочь, колонки таблиц с ценами — прочь, ссылки (кроме почты и
 телефона) и плитки-ссылки — прочь. Над статьёй экран ставит «Эта возможность недоступна в приложении.».
 */
extension РазборСтатьи {
    static func безПокупок(_ статья: СтатьяСайта) -> СтатьяСайта {
        var итог = статья
        итог.блоки = безПокупок(статья.блоки)
        return итог
    }

    private static let ценаВыражение = try? NSRegularExpression(
        pattern: "\\d[\\d\\s\\u00A0\\u202F.,]*\\s?(₸|тг|тенге|теңге|kzt|₽|руб|\\$|€|usd|eur)|(₸|\\$|€)\\s?\\d",
        options: [.caseInsensitive])

    private static let ценаВЗаголовке = try? NSRegularExpression(
        pattern: "(\\s*[—–:·|-]\\s*|\\s+(за|от|по|for|from|бастап)\\s+)?(\\d[\\d\\s\\u00A0\\u202F.,]*\\s?(₸|тг|тенге|теңге|kzt|₽|руб|\\$|€|usd|eur)|(₸|\\$|€)\\s?\\d[\\d\\s\\u00A0\\u202F.,]*)(\\s*/\\s*[^\\s,.;)]+)?",
        options: [.caseInsensitive])

    private static let покупки = ["купить", "оплатить", "подключить", "оформить", "продлить", "приобрести",
                                  "перейти к оплате", "выбрать тариф", "активировать", "buy", "pay", "purchase",
                                  "subscribe", "upgrade", "get ", "сатып", "төле", "қосу", "рәсімде", "ұзарту",
                                  "اشتر", "ادفع", "اشترك"]

    static func естьЦена(_ текст: String) -> Bool {
        guard let выражение = ценаВыражение else { return false }
        let весь = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        return выражение.firstMatch(in: текст, options: [], range: весь) != nil
    }

    /// Короткий призыв купить («Купить ТОП», «Подключить PRO») — кнопка сайта, а не описание.
    static func призывКупить(_ текст: String) -> Bool {
        let строка = текст.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !строка.isEmpty, строка.count <= 40 else { return false }
        return покупки.contains(where: { строка.hasPrefix($0) })
    }

    private static func безЦены(_ текст: String) -> String {
        guard let выражение = ценаВЗаголовке else { return текст }
        let весь = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        let без = выражение.stringByReplacingMatches(in: текст, options: [], range: весь, withTemplate: "")
        let края = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "—–-:·|()"))
        return без.trimmingCharacters(in: края)
    }

    /// Ссылки текста — прочь, кроме почты и телефона.
    private static func безСсылок(_ текст: AttributedString) -> AttributedString {
        var итог = текст
        var лишние: [Range<AttributedString.Index>] = []
        for кусок in текст.runs {
            guard let адрес = кусок.link else { continue }
            let схема = (адрес.scheme ?? "").lowercased()
            if схема == "mailto" || схема == "tel" { continue }
            лишние.append(кусок.range)
        }
        for диапазон in лишние {
            итог[диапазон].link = nil
        }
        return итог
    }

    private static func безПокупок(_ блоки: [БлокСтатьи]) -> [БлокСтатьи] {
        var итог: [БлокСтатьи] = []
        for исходный in блоки {
            var блок = исходный
            switch исходный.вид {
            case .заголовок:
                let текст = безЦены(исходный.простой)
                if текст.isEmpty || призывКупить(текст) { continue }
                блок.текст = AttributedString(текст)
            case .вопрос(let ответ, let открыт):
                let чистый = безПокупок(ответ)
                if чистый.isEmpty || естьЦена(исходный.простой) { continue }
                блок.вид = .вопрос(чистый, открыт: открыт)
                блок.текст = безСсылок(исходный.текст)
            case .таблица(let строки, let шапка):
                guard let таблица = таблицаБезЦен(строки, шапка: шапка) else { continue }
                блок.вид = .таблица(таблица, шапка: шапка)
            case .карточка:
                continue
            case .картинка, .разделитель:
                break
            default:
                if естьЦена(исходный.простой) || призывКупить(исходный.простой) { continue }
                блок.текст = безСсылок(исходный.текст)
            }
            итог.append(блок)
        }
        /* Заголовок, под которым после чистки ничего не осталось (до следующего такого же или старше), — прочь. */
        var чистые: [БлокСтатьи] = []
        for (номер, блок) in итог.enumerated() {
            if case .заголовок(let уровень) = блок.вид {
                let дальше = итог.dropFirst(номер + 1).first
                var пусто = дальше == nil
                if let дальше, case .заголовок(let следующий) = дальше.вид, следующий <= уровень { пусто = true }
                if пусто { continue }
            }
            чистые.append(блок)
        }
        return чистые
    }

    /// Колонки, где есть цена или «Купить», — прочь целиком; осталась одна шапка — таблицы нет.
    private static func таблицаБезЦен(_ строки: [[AttributedString]], шапка: Bool) -> [[AttributedString]]? {
        var ценовые = Set<Int>()
        for (номерСтроки, строка) in строки.enumerated() {
            if шапка && номерСтроки == 0 { continue }
            for (номер, ячейка) in строка.enumerated() {
                let текст = String(ячейка.characters)
                if естьЦена(текст) || призывКупить(текст) { ценовые.insert(номер) }
            }
        }
        var новые: [[AttributedString]] = []
        for строка in строки {
            var ячейки: [AttributedString] = []
            for (номер, ячейка) in строка.enumerated() where !ценовые.contains(номер) {
                ячейки.append(безСсылок(ячейка))
            }
            if ячейки.contains(where: { !$0.characters.isEmpty }) { новые.append(ячейки) }
        }
        let данных = шапка ? новые.count - 1 : новые.count
        guard данных > 0 else { return nil }
        return новые
    }
}
