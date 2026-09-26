import Foundation

/**
 СТАТЬЯ СТРАНИЦЫ САЙТА → НАТИВНЫЕ БЛОКИ (этап 50, владелец: «всё приложение нативным»).

 Справочный центр (/kz/<язык>/help и его разделы #safe, #pro, #rules), соглашение, оферта, политика, «Оплата и возврат»,
 «Тарифы» — у сайта это статические страницы без API (карта кабинета §6.8.3). Приложение качает ту же страницу и
 вынимает из неё только статью: заголовки, абзацы, списки, ссылки, вопросы-ответы (<details>/<summary>), таблицы
 строками. Никакого WebView и никакого NSAttributedString(html:) (он поднимает WebKit на главном потоке): свой простой
 разбор тегов, текст — AttributedString с жирным, курсивом и ссылками.

 Где статья: <main>, иначе <article>, иначе <body>. Шапка, подвал, меню, формы, скрипты, стили, картинки SVG, скрытое
 (hidden, aria-hidden, display:none) и окна (modal, overlay, toast, drawer, bottombar, cookie, popup, sheet) — мимо.
 Якоря (id, name) прилипают к следующему блоку: help#safe прокручивает к нему.

 Чистые функции без главного потока — их зовут из Task.detached.
 */

/// Блок статьи.
struct БлокСтатьи: Identifiable {
    enum Вид {
        case заголовок(Int)
        case абзац
        /// Пункт списка: маркер («•», «1.») и глубина вложенности (1…).
        case пункт(маркер: String, уровень: Int)
        case цитата
        case разделитель
        /// <details>: вопрос — текст блока, ответ — вложенные блоки.
        case вопрос([БлокСтатьи])
    }

    let id: Int
    let вид: Вид
    let текст: AttributedString
    /// Якоря (id/name элементов), что стояли перед блоком.
    var якоря: [String]

    /// Простой текст без разметки — для оглавления и VoiceOver.
    var простой: String { String(текст.characters) }
}

/// Разобранная статья.
struct СтатьяСайта {
    var заголовок: String
    var блоки: [БлокСтатьи]

    /// Годится ли статья: хотя бы два блока с текстом (страница, собранная скриптом, даст пустоту — тогда сайт).
    var годится: Bool {
        блоки.filter { !$0.простой.isEmpty }.count >= 2
    }

    /// Заголовки второго уровня — оглавление вверху.
    var разделы: [БлокСтатьи] {
        блоки.filter {
            if case .заголовок(let уровень) = $0.вид { return уровень == 2 }
            return false
        }
    }

    /// Блок с якорем (или вопрос, внутри которого он).
    func блок(якоря якорь: String) -> Int? {
        let искомый = якорь.lowercased()
        for блок in блоки {
            if блок.якоря.contains(where: { $0.lowercased() == искомый }) { return блок.id }
            if case .вопрос(let ответ) = блок.вид,
               ответ.contains(where: { $0.якоря.contains(where: { $0.lowercased() == искомый }) }) {
                return блок.id
            }
        }
        return nil
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
        разбор.сбросить()
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

    /// Содержимое первого <тег …> до последнего </тег>.
    private static func внутренность(_ html: String, тег: String) -> String? {
        guard let начало = html.range(of: "<" + тег, options: .caseInsensitive) else { return nil }
        /* <main> или <main …>, но не <mainframe>. */
        let после = html[начало.upperBound...]
        let допустимые: Set<Character> = [">", " ", "\n", "\t", "\r"]
        guard let первый = после.first, допустимые.contains(первый) else { return nil }
        guard let конецОткрытия = после.firstIndex(of: ">") else { return nil }
        let тело = html[html.index(after: конецОткрытия)...]
        guard let закрытие = тело.range(of: "</" + тег, options: [.caseInsensitive, .backwards]) else {
            return String(тело)
        }
        return String(тело[..<закрытие.lowerBound])
    }

    private static func заголовокTitle(_ html: String) -> String {
        guard let внутри = внутренность(html, тег: "title") else { return "" }
        var текст = декодировать(внутри).trimmingCharacters(in: .whitespacesAndNewlines)
        /* «Помощь — Kliko.kz» → «Помощь». */
        for разделитель in [" — ", " | ", " - ", " · "] {
            if let r = текст.range(of: разделитель) { текст = String(текст[..<r.lowerBound]) }
        }
        return текст
    }

    /// Комментарии и элементы с сырым текстом (скрипты, стили, SVG, шаблоны, поля ввода) — целиком прочь.
    private static func убратьЛишнее(_ html: String) -> String {
        var итог = html
        let шаблоны = [
            "<!--[\\s\\S]*?-->",
            "<(script|style|noscript|svg|template|iframe|select|textarea|canvas|video|audio|object)\\b[\\s\\S]*?</\\1\\s*>"
        ]
        for шаблон in шаблоны {
            guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive]) else { continue }
            let весь = NSRange(итог.startIndex..<итог.endIndex, in: итог)
            итог = выражение.stringByReplacingMatches(in: итог, options: [], range: весь, withTemplate: " ")
        }
        return итог
    }

    // MARK: - Сущности

    private static let именные: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}", "laquo": "«", "raquo": "»",
        "mdash": "—", "ndash": "–", "hellip": "…", "minus": "−", "copy": "©", "reg": "®", "trade": "™", "rarr": "→",
        "larr": "←", "middot": "·", "bull": "•", "times": "×", "deg": "°", "shy": "", "thinsp": "\u{2009}",
        "ensp": "\u{2002}", "emsp": "\u{2003}", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "sbquo": "‚", "euro": "€", "tenge": "₸", "numero": "№", "sect": "§", "plusmn": "±", "check": "✓", "zwj": "",
        "zwnj": "", "lrm": "", "rlm": ""
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
            guard let код, let скаляр = Unicode.Scalar(код) else { return nil }
            return String(Character(скаляр))
        }
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

    /// Открытый <details>: блоки ответа и вопрос.
    private struct Раскрытие {
        var вопрос: AttributedString = AttributedString()
        var якоряВопроса: [String] = []
        var блоки: [БлокСтатьи] = []
    }

    /// Открытый список: нумерованный или нет и счётчик.
    private struct Список {
        let нумерованный: Bool
        var номер: Int
    }

    private struct Разбор {
        let база: URL
        var итог: [БлокСтатьи] = []
        var первыйH1 = ""

        private var стек: [String] = []
        private var глубинаПропуска: Int? = nil
        private var куски: [Кусок] = []
        private var видСейчас: БлокСтатьи.Вид = .абзац
        private var жирный = 0
        private var курсив = 0
        private var ссылки: [URL?] = []
        private var якоря: [String] = []
        private var раскрытия: [Раскрытие] = []
        private var списки: [Список] = []
        private var вВопросе = false
        private var счётчик = 0
        private var пробелБыл = true

        init(база: URL) {
            self.база = база
        }

        private static let пустые: Set<String> = ["br", "img", "hr", "input", "meta", "link", "source", "wbr", "area",
                                                   "base", "col", "embed", "param", "track"]
        private static let пропускаемые: Set<String> = ["header", "footer", "nav", "form", "dialog", "aside", "label",
                                                        "picture", "figure", "map"]
        private static let блочные: Set<String> = ["p", "div", "section", "blockquote", "tr", "dd", "dt", "figcaption",
                                                   "table", "ul", "ol", "li", "details", "summary", "h1", "h2", "h3",
                                                   "h4", "h5", "h6", "pre", "address", "center", "dl", "tbody", "thead",
                                                   "button"]
        private static let окна = try? NSRegularExpression(
            pattern: "(^|[\\s_-])(modal|overlay|toast|drawer|bottombar|bottom-bar|bb|cookie|popup|sheet|sr-only|visually-hidden|skip|breadcrumbs?|share|tabbar|topbar|navbar|menu)([\\s_-]|$)",
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
            if !самозакрытый { стек.append(имя) }
            if глубинаПропуска != nil { return }
            if пропустить(имя, атрибуты) {
                if !самозакрытый { глубинаПропуска = стек.count }
                return
            }
            if let якорь = атрибуты["id"] ?? атрибуты["name"], !якорь.isEmpty, имя != "meta" {
                якоря.append(якорь)
            }
            switch имя {
            case "br":
                куски.append(Кусок(текст: "\n", жирный: false, курсив: false, ссылка: nil))
                пробелБыл = true
            case "hr":
                сбросить()
                добавить(.разделитель, AttributedString())
            case "b", "strong":
                жирный += 1
            case "button":
                /* Раскрывашка на скрипте (<button>вопрос</button><div>ответ</div>): вопрос — жирной строкой. */
                сбросить()
                жирный += 1
            case "i", "em":
                курсив += 1
            case "a":
                ссылки.append(ссылка(атрибуты["href"]))
            case "td", "th":
                if куски.contains(where: { !$0.текст.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    куски.append(Кусок(текст: " · ", жирный: false, курсив: false, ссылка: nil))
                }
            case "ul", "ol":
                сбросить()
                списки.append(Список(нумерованный: имя == "ol", номер: Int(атрибуты["start"] ?? "") ?? 1))
            case "li":
                сбросить()
                var маркер = "•"
                if var последний = списки.last {
                    if последний.нумерованный {
                        маркер = String(последний.номер) + "."
                        последний.номер += 1
                        списки[списки.count - 1] = последний
                    } else if списки.count > 1 {
                        маркер = "◦"
                    }
                }
                видСейчас = .пункт(маркер: маркер, уровень: max(1, списки.count))
            case "details":
                сбросить()
                раскрытия.append(Раскрытие())
            case "summary":
                сбросить()
                вВопросе = true
            case "blockquote":
                сбросить()
                видСейчас = .цитата
            default:
                if имя.count == 2, имя.hasPrefix("h"), let уровень = Int(String(имя.dropFirst())), (1...6).contains(уровень) {
                    сбросить()
                    видСейчас = .заголовок(уровень)
                } else if Разбор.блочные.contains(имя) {
                    сбросить()
                }
            }
        }

        private mutating func закрыть(_ имя: String) {
            guard let место = стек.lastIndex(of: имя) else { return }
            стек.removeSubrange(место...)
            if let глубина = глубинаПропуска {
                if стек.count < глубина { глубинаПропуска = nil }
                return
            }
            switch имя {
            case "b", "strong":
                жирный = max(0, жирный - 1)
            case "button":
                сбросить()
                жирный = max(0, жирный - 1)
            case "i", "em":
                курсив = max(0, курсив - 1)
            case "a":
                if !ссылки.isEmpty { ссылки.removeLast() }
            case "ul", "ol":
                сбросить()
                if !списки.isEmpty { списки.removeLast() }
            case "summary":
                if var открытое = раскрытия.last {
                    открытое.вопрос = собрать()
                    открытое.якоряВопроса = якоря
                    якоря = []
                    куски = []
                    пробелБыл = true
                    раскрытия[раскрытия.count - 1] = открытое
                } else {
                    сбросить()
                }
                вВопросе = false
                видСейчас = .абзац
            case "details":
                сбросить()
                guard let готовое = раскрытия.popLast() else { return }
                if готовое.вопрос.characters.isEmpty && готовое.блоки.isEmpty { return }
                счётчик += 1
                let блок = БлокСтатьи(id: счётчик, вид: .вопрос(готовое.блоки), текст: готовое.вопрос,
                                      якоря: готовое.якоряВопроса)
                положить(блок)
            case "li", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6":
                сбросить()
                видСейчас = .абзац
            default:
                if Разбор.блочные.contains(имя) {
                    сбросить()
                }
            }
        }

        private func пропустить(_ имя: String, _ атрибуты: [String: String]) -> Bool {
            if Разбор.пропускаемые.contains(имя) { return true }
            if атрибуты["hidden"] != nil { return true }
            if (атрибуты["aria-hidden"] ?? "").lowercased() == "true" { return true }
            let стиль = (атрибуты["style"] ?? "").lowercased().replacingOccurrences(of: " ", with: "")
            if стиль.contains("display:none") || стиль.contains("visibility:hidden") { return true }
            if (атрибуты["role"] ?? "").lowercased() == "dialog" { return true }
            let класс = (атрибуты["class"] ?? "") + " " + (атрибуты["id"] ?? "")
            if let окна = Разбор.окна {
                let весь = NSRange(класс.startIndex..<класс.endIndex, in: класс)
                if окна.firstMatch(in: класс, options: [], range: весь) != nil { return true }
            }
            return false
        }

        private func ссылка(_ href: String?) -> URL? {
            guard let href = href?.trimmingCharacters(in: .whitespacesAndNewlines), !href.isEmpty,
                  !href.lowercased().hasPrefix("javascript:") else { return nil }
            let чистый = РазборСтатьи.декодировать(href)
            if чистый.hasPrefix("#") {
                var части = URLComponents(url: база, resolvingAgainstBaseURL: false)
                части?.fragment = String(чистый.dropFirst())
                return части?.url
            }
            return URL(string: чистый, relativeTo: база)?.absoluteURL
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
            куски.append(Кусок(текст: чистый, жирный: жирный > 0, курсив: курсив > 0, ссылка: ссылки.last ?? nil))
        }

        /// Куски → AttributedString без пробелов по краям.
        private func собрать() -> AttributedString {
            var итог = AttributedString()
            for кусок in куски {
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

        /// Закончить текущий блок.
        /// Вид блока остаётся, пока текста не было: у <li><p>…</p></li> пункт не превращается в абзац.
        mutating func сбросить() {
            guard !вВопросе, !куски.isEmpty else { return }
            let текст = собрать()
            куски = []
            пробелБыл = true
            let вид = видСейчас
            видСейчас = .абзац
            guard !текст.characters.isEmpty else { return }
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
                итог[String(имя).lowercased()] = РазборСтатьи.декодировать(String(значение))
            }
            return итог
        }

        private static func пробел(_ c: Unicode.Scalar) -> Bool {
            c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{0C}"
        }
    }
}
