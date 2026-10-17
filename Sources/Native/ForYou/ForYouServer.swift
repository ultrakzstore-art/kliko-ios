import Foundation

/**
 «ДЛЯ ВАС» — КРЮЧОК ПОД ОТБОР НА СЕРВЕРЕ (docs/SERVER_MY_THINGS.md §3 «Фильтры ленты», §3.7 «Признаки готовности в
 схеме», §10 «Приватность»).

 Договор: значения из «Моего» (fit_car, fit_phone, fit_laptop, size, fit_level) — только телом POST на
 api/listings.php, остальное (cat, город, per, sort) — в адресе, как у GET; ответ тот же. Какие виды сервер применяет,
 он объявляет в схеме подачи — rules.fit_filters ({"car": true, "phone": true, …}); схему приложение уже держит в
 Caches (ЗагрузкаСхемыПодачи, Posting/PostingSchema.swift) — здесь читается этот файл (нет его или старше суток —
 один публичный GET схемы за запуск, ПризнакиПодбораСервера).

 Пачка 83 (docs/SERVER_NEW_FOR_MINE.md §2, §11) держала крючок за ключом админки std_server_fit. Пачка 84 (ответ
 сервера 17.10.2026, §3: лента с fit_* телом POST включена на проде по всем видам): POST раздела идёт, когда схема
 подачи объявила вид в rules.fit_filters (ПризнакиПодбораСервера), — машина fit_car, телефон fit_phone, ноутбук
 fit_laptop, гардероб size, дом fit_std (кровать и бельё, цоколь, VESA; окна и шторы — на телефоне: у семьи curtain
 каталога fit_std: false). В адресе — только то, что и у GET (раздел, город, per, sort=new), значения — телом, БЕЗ
 КУКОВ (§2.1: сервер не связывает тело с человеком), тело и ответ не пишутся ни в журнал приложения, ни на диск. Сверка
 на телефоне остаётся: уровень — не лучше fit_match сервера (СовместимостьМоего.оценить), а где телефону сверить не по
 чему — уровень сервера (ПодборДляВас.сверитьВсё). POST не прошёл или сервер тело не применил (нет fit_applied) — тот
 же раздел обычным GET, и до перезапуска — только GET (§2.3). Вид не объявлен — как раньше: GET и сверка на телефоне.
 subs.php kind:"fit" приложение не создаёт (ответ сервера 17.10.2026 §4): «Новинки» — только api/for_mine.php.
 Компьютер (fit_std ОЗУ, M.2, видеокарта) — позже.
 */

/**
 Рубильники «Новинок для моего» (docs/SERVER_NEW_FOR_MINE.md §11). Все по умолчанию выключены: значение сборки — false,
 включает и выключает только админка (НастройкиСервера.вклВыкл). Пока ключа нет в белом списке приложения
 (НастройкиСервера.ключиФлагов, System/RemoteSettings.swift), сервер его не включит — и нового запроса нет.
 */
enum РубильникиНовинок {
    /// std_server_fit — подбор «Для вас» телом POST (§2).
    static var подборНаСервере: Bool { НастройкиСервера.вклВыкл("std_server_fit", сборка: false) }
    /// fit_subs — подписка «Новинки для моего» без входа и push (§3, MyThingsWatch.swift).
    static var подписка: Bool { НастройкиСервера.вклВыкл("fit_subs", сборка: false) }
    /// season_rules — правила сезона с сервера (§4, ForYouSeasonServer.swift); встроенные работают и без него.
    static var сезонСервера: Bool { НастройкиСервера.вклВыкл("season_rules", сборка: false) }
    /// fit_subs_daily — push в сутки, 1…3; не прислал сервер — 1 (подпись «не чаще раза в день»).
    static var вСутки: Int {
        let число: Int = НастройкиСервера.целоеЧисло("fit_subs_daily") ?? 1
        return max(1, min(3, число))
    }
}

enum ОтборСервераДляВас {
    private static let сеть = СетьСайта.Запросы(json: true, безКэша: true)

    /// Вид §3 для профиля: car, phone, laptop, size; у дома и компьютера — nil (их вид — std, fit_std).
    static func вид(_ профиль: ИтогСовместимостиМоего.Профиль) -> String? {
        switch профиль {
        case .машина: return "car"
        case .телефон: return "phone"
        case .ноутбук: return "laptop"
        case .размер: return "size"
        case .дом, .компьютер: return nil
        }
    }

    /// Тела POST по разделам: только объявленные сервером виды (rules.fit_filters) и только значения «Моего»; вида нет
    /// или значения нет — у раздела тела нет (обычный GET).
    static func тела(_ запросы: [ЗапросПодбораМоего], моё: ЗаписьМоего,
                     объявлено: Set<String>) -> [String: [String: String]] {
        guard !объявлено.isEmpty else { return [:] }
        var итог: [String: [String: String]] = [:]
        for запрос in запросы where итог[запрос.раздел] == nil {
            if let т = Self.тело(запрос, моё: моё, объявлено: объявлено) { итог[запрос.раздел] = т }
        }
        return итог
    }

    /// Отпечаток тела — только в памяти (страница раздела помнит, с каким телом её взяли): «» — GET, без тела.
    static func отпечаток(_ поля: [String: String]?) -> String {
        guard let поля, !поля.isEmpty else { return "" }
        let пары: [String] = поля.keys.sorted().map { (ключ: String) -> String in ключ + "=" + (поля[ключ] ?? "") }
        return пары.joined(separator: "&")
    }

    /// rules.fit_filters сохранённой схемы подачи (файл в Caches, имя — как у ЗагрузкаСхемыПодачи); нет — пусто.
    static func признаки() async -> Set<String> {
        let язык = ПримерочнаяText.язык
        return await Task.detached(priority: .utility) { () -> Set<String> in
            guard let папка = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let данные = try? Data(contentsOf: папка.appendingPathComponent("kliko_post_schema_" + язык + ".json")),
                  let корень = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any],
                  let правила = корень["rules"] as? [String: Any],
                  let флаги = правила["fit_filters"] as? [String: Any] else { return [] }
            return Set(флаги.compactMap { пара in (пара.value as? Bool) == true ? пара.key.lowercased() : nil })
        }.value
    }

    /// Файла схемы на телефоне нет или он старше суток.
    static func схемаУстарела() async -> Bool {
        let язык = ПримерочнаяText.язык
        return await Task.detached(priority: .utility) { () -> Bool in
            guard let папка = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                return false
            }
            let путь: String = папка.appendingPathComponent("kliko_post_schema_" + язык + ".json").path
            guard let свойства = try? FileManager.default.attributesOfItem(atPath: путь),
                  let когда = свойства[.modificationDate] as? Date else { return true }
            return Date().timeIntervalSince(когда) > 24 * 3600
        }.value
    }

    /**
     Тело запроса раздела: {"fit_car": "…", "fit_level": "parts"}; вид не объявлен или в «Моём» нет значения — nil.
     Только значения стандартов: ни имён вещей, ни подписей, ни комнат. Одежда и обувь — взрослые таблицы этого раздела;
     дом — fit_std (кровать и бельё, цоколь, VESA); компьютер — позже (сервер ещё не объявил его семьи).
     */
    static func тело(_ запрос: ЗапросПодбораМоего, моё: ЗаписьМоего, объявлено: Set<String>) -> [String: String]? {
        let имяВида: String = УровеньСервераОбъявления.видПрофиля(запрос.профиль)
        guard объявлено.contains(имяВида) else { return nil }
        let поле: String
        let строка: String?
        switch запрос.профиль {
        case .машина:
            поле = "fit_car"
            строка = моё.главнаяМашина.flatMap { (м: МашинаМоего) -> String? in Self.значениеПосадки(м) }
        case .телефон:
            поле = "fit_phone"
            строка = моё.телефон.flatMap { (т: ТелефонМоего) -> String? in Self.slug(т.модель) }
        case .ноутбук:
            поле = "fit_laptop"
            строка = СовместимостьМоего.диагональНоутбука(моё).map { (д: Double) -> String in String(format: "%.1f", д) }
        case .размер:
            поле = "size"
            строка = Self.размерыРаздела(запрос.раздел, моё.тело.размеры)
        case .дом:
            поле = "fit_std"
            строка = Self.стандартыДома(запрос.раздел, моё.дом)
        case .компьютер:
            поле = "fit_std"
            строка = nil
        }
        guard let строка, !строка.isEmpty else { return nil }
        return [поле: строка, "fit_level": "parts"]
    }

    /// Значение части fit_std: только латиница, цифры, «.» и «-», до 24 знаков — без разделителей запроса.
    private static func чисто(_ значение: String) -> String? {
        let допустимо: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let отобрано: String = String(значение.filter { (знак: Character) -> Bool in допустимо.contains(знак) })
        let итог: String = String(отобрано.prefix(24))
        return итог.isEmpty ? nil : итог
    }

    /// Кровать детской комнаты: вещи детей никуда не уходят (docs/STANDARDS.md §8.4), даже у семей с fit_std: true.
    private static func кроватьДетской(_ кровать: КроватьМоего, _ дом: ДомМоего) -> Bool {
        дом.комната(кровать.комната)?.вид == .детская
    }

    /**
     fit_std (docs/SERVER_STANDARDS.md §4.3) раздела дома: группы через «|» — по вещи «Моего» (до 12), части
     «семья.поле:значение» через «;» — потребность вещи (need каталога). Только семьи с fit_std: true каталога: кровать
     и бельё (bedding, beds), цоколь (lighting), VESA (tv-audio). Шторы и окна (curtain — fit_std: false), проёмы,
     потолок и матрас — на телефоне; шаблон VESA «обычно по диагонали» не шлётся (сервер исключил бы подходящее).
     Нечего — nil.
     */
    static func стандартыДома(_ раздел: String, _ дом: ДомМоего) -> String? {
        var группы: [String] = []
        switch раздел {
        case "bedding", "beds":
            for кровать in дом.кровати where !Self.кроватьДетской(кровать, дом) {
                guard let место = кровать.место.flatMap({ (с: String) -> String? in Self.чисто(с) }) else { continue }
                var части: [String] = ["bed_size.size:" + место]
                if раздел == "bedding" {
                    части.append("bedding.size:" + место)
                    if let высота = кровать.матрасВысота { части.append("bedding.mattress_h:" + String(высота)) }
                    if let одеяло = кровать.одеяло.flatMap({ (с: String) -> String? in Self.чисто(с) }) {
                        части.append("bedding.duvet:" + одеяло)
                    }
                }
                группы.append(части.joined(separator: ";"))
            }
        case "lighting":
            for цоколь in дом.цоколи.keys.sorted() {
                if let своё = Self.чисто(цоколь) { группы.append("lamp_base.base:" + своё) }
            }
        case "tv-audio":
            for экран in дом.экраны {
                guard let шаблон = экран.vesa.flatMap({ (с: String) -> String? in Self.чисто(с) }) else { continue }
                var части: [String] = ["vesa.pattern:" + шаблон]
                if let вес = экран.вес { части.append("vesa.kg:" + ЧислаАвтоподбора.ч(вес)) }
                if let диагональ = экран.диагональ { части.append("vesa.diag:" + ЧислаАвтоподбора.ч(диагональ)) }
                группы.append(части.joined(separator: ";"))
            }
        default:
            break
        }
        var свои: [String] = []
        for группа in группы where !свои.contains(группа) {
            свои.append(группа)
            if свои.count >= 12 { break }
        }
        return свои.isEmpty ? nil : свои.joined(separator: "|")
    }

    /// Раздел ленты вида размера: одежда и обувь взрослых; бельё, кольца, шапки и перчатки — не шлются.
    private static func разделРазмера(_ вид: ВидРазмераМоего) -> String? {
        switch вид {
        case .обувьЖ: return "womens-shoes"
        case .обувьМ: return "mens-shoes"
        case .одеждаЖ, .джинсыЖ: return "womens-clothing"
        case .одеждаМ, .джинсыМ: return "mens-clothing"
        case .бельё, .кольцо, .шапка, .перчатки: return nil
        }
    }

    /// size раздела (§3.5): только размеры, чья таблица отбирает в этом разделе; без «|» и «:» внутри частей. Нет — nil.
    static func размерыРаздела(_ раздел: String, _ список: [РазмерМоего]) -> String? {
        let свои: [РазмерМоего] = список.filter { (р: РазмерМоего) -> Bool in
            guard р.вид.обувь || р.вид.одежда, Self.разделРазмера(р.вид) == раздел else { return false }
            let части: String = р.система + р.значение
            return !части.contains("|") && !части.contains(":") && !р.значение.isEmpty
        }
        return Self.размеры(свои)
    }

    /// fit_car (§3.2): «pcd:5x114.3;dia:60.1;et:35..45;r:16,17,18;tyre:215/55R17»; посадки нет — nil.
    static func значениеПосадки(_ авто: МашинаМоего) -> String? {
        guard let посадка = авто.посадка, !посадка.пустая else { return nil }
        var части: [String] = []
        if let болты = посадка.разболтовка {
            части.append("pcd:" + String(болты.отверстий) + "x" + ЧислаАвтоподбора.ч(болты.pcd))
        }
        if let dia = посадка.dia { части.append("dia:" + ЧислаАвтоподбора.ч(dia)) }
        if let низ = посадка.etMin, let верх = посадка.etMax {
            части.append("et:" + ЧислаАвтоподбора.ч(низ) + ".." + ЧислаАвтоподбора.ч(верх))
        }
        let диаметры = посадка.штатныеДиаметры
        if !диаметры.isEmpty { части.append("r:" + диаметры.map { ЧислаАвтоподбора.ч($0) }.joined(separator: ",")) }
        if let шина = посадка.шины.first { части.append("tyre:" + шина.подпись.replacingOccurrences(of: " ", with: "")) }
        return части.isEmpty ? nil : части.joined(separator: ";")
    }

    private static let русскиеСлова: [String: String] = [
        "айфон": "iphone", "самсунг": "samsung", "галакси": "galaxy", "редми": "redmi", "сяоми": "xiaomi",
        "ксиоми": "xiaomi", "хонор": "honor", "поко": "poco", "пиксель": "pixel", "про": "pro", "макс": "max",
        "плюс": "plus", "ультра": "ultra", "мини": "mini"
    ]
    private static let лишниеСлова: Set<String> = ["5g", "4g", "lte", "nfc", "dual", "sim", "apple"]
    /// Линейка без марки впереди — марка первым словом (§3.3, п. 4).
    private static let маркиЛинеек: [String: String] = [
        "galaxy": "samsung", "redmi": "xiaomi", "poco": "xiaomi", "pixel": "google"
    ]

    /**
     fit_phone (§3.3): slug из написания — строчные, русские слова латиницей, «+» — plus, без 5g, lte, памяти и скобок,
     Apple без марки, линейка без марки — с маркой («galaxy-s24» → «samsung-galaxy-s24»). Псевдонимы и годы каталога
     (iphone-se-2022 → iphone-se-3) — дело сервера.
     */
    static func slug(_ модель: String) -> String? {
        /* Разбито на шаги с явными типами: длинная цепочка map и filter с замыканиями — риск «unable to type-check». */
        let строка: String = модель.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "+", with: " plus ")
        let части: [String] = строка.components(separatedBy: CharacterSet.alphanumerics.inverted)
        var слова: [String] = []
        for часть in части where !часть.isEmpty {
            let слово: String = русскиеСлова[часть] ?? часть
            if лишниеСлова.contains(слово) { continue }
            if слово.hasSuffix("gb"), Int(String(слово.dropLast(2))) != nil { continue }
            let латиница: Bool = слово.allSatisfy { (знак: Character) -> Bool in
                знак.isASCII && (знак.isLetter || знак.isNumber)
            }
            if !латиница { continue }
            слова.append(слово)
        }
        guard let первое = слова.first else { return nil }
        if let марка = маркиЛинеек[первое] { слова.insert(марка, at: 0) }
        return слова.joined(separator: "-")
    }

    /// size (§3.5): «clothes_men:INT:M|shoes_men:US M:9.5» — таблица, система, значение; пусто — nil.
    static func размеры(_ список: [РазмерМоего]) -> String? {
        let части = список.map { $0.вид.rawValue + ":" + $0.система + ":" + $0.значение }
        return части.isEmpty ? nil : части.joined(separator: "|")
    }

    /**
     POST ленты: адрес — тот же, что у GET (ListingsAPI.адрес, в нём нет «Моего»), значения — телом JSON, без куков
     (§2.1): тело ни с кем не связывается, своё объявление отсекает телефон. Срок — 15 с (§0 договора). Тело и ответ
     никуда не пишутся: ни в журнал приложения, ни на диск (ответ сервера — private, no-store).
     */
    static func загрузить(_ з: ListingsAPI.Запрос, тело: [String: String]) async throws -> ListingsPage {
        var запрос = URLRequest(url: ListingsAPI.адрес(з))
        запрос.httpMethod = "POST"
        запрос.timeoutInterval = 15
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.httpBody = try JSONSerialization.data(withJSONObject: тело)
        let (данные, ответ) = try await сеть.data(for: запрос)
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ListingsAPI.Ошибка.статус(http.statusCode)
        }
        return try await ListingsAPI.разобратьВФоне(данные)
    }
}

/**
 Признаки подбора на сервере на этот запуск (rules.fit_filters из кэша схемы подачи) — общие для полки «Для вас» и рядов
 «Подходит вам». Читаются из файла один раз и сразу (загрузка разделов сети схемы не ждёт); файла схемы нет или он
 старше суток — один раз за запуск схема спрашивается у сайта в фоне (публичный GET без куков с ETag —
 ЗагрузкаСхемыПодачи.загрузить; в нём нет ничего из «Моего»), и признаки новой схемы — для следующих загрузок. Пока
 признаков нет — подбор как раньше: GET раздела и сверка на телефоне.
 */
@MainActor
enum ПризнакиПодбораСервера {
    /// Прочитанные признаки; nil — в этот запуск ещё не читали.
    private(set) static var известные: Set<String>? = nil
    private static var чтение: Task<Set<String>, Never>? = nil
    private static var освежали = false
    /// POST не прошёл или сервер тело не применил (нет fit_applied) — до перезапуска прежний путь (§2.3 договора).
    private(set) static var безПоста = false

    /// Признаки с учётом отказа: после отказа — пусто (тела не собираются).
    static var действующие: Set<String>? {
        guard let есть = известные else { return nil }
        return безПоста ? [] : есть
    }

    static func прочитать() async -> Set<String> {
        if let есть = известные { return есть }
        if let идёт = чтение { return await идёт.value }
        let задача = Task<Set<String>, Never> { () -> Set<String> in
            await ОтборСервераДляВас.признаки()
        }
        чтение = задача
        let итог: Set<String> = await задача.value
        известные = итог
        чтение = nil
        освежитьВФоне()
        return итог
    }

    /// Схемы нет или она старше суток — один раз за запуск спросить её у сайта; признаки новой схемы — для следующих
    /// загрузок (304 и неудача — остаются прежние).
    private static func освежитьВФоне() {
        guard !освежали else { return }
        освежали = true
        Task<Void, Never> { @MainActor () -> Void in
            let устарела: Bool = await ОтборСервераДляВас.схемаУстарела()
            guard устарела else { return }
            let свежая: СхемаПодачи? = await ЗагрузкаСхемыПодачи.загрузить()
            guard свежая != nil else { return }
            let новые: Set<String> = await ОтборСервераДляВас.признаки()
            известные = новые
        }
    }

    /// Отказ POST: прежний путь до перезапуска.
    static func отказ() {
        безПоста = true
    }

    /// В этот запуск значения стандартов уходили телом POST (полка «Для вас» или ряды «Подходит вам») — применил их
    /// сервер или нет, ответил ли вовсе: вступление «Для вас» больше не говорит «никуда не уходят» (fv_lead_server).
    private(set) static var отправляли = false

    /// Тело POST со значениями стандартов уходит — отметка до запроса.
    static func отметитьОтправку() {
        if !отправляли { отправляли = true }
    }
}
