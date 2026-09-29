import Foundation

/**
 ПОДАЧА ОБЪЯВЛЕНИЯ — СПРАВОЧНИКИ И ЗНАЧЕНИЯ СТРАНИЦЫ, ЭТАП 42 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Откуда что (карта кабинета §2.3, §0.7):
   · дерево разделов — js/cats-<язык>.js сайта (var MK_CATS=[…], 13 корней, 561 узел; имена на языке страницы);
   · характеристики, бренды, поля мастеров недвижимости и запчастей, регионы — js/cab-refs.js (var KLK_CAB_REFS={…}:
     E_SPECS, BRAND_LIST, REALTY_FIELDS, PARTS_FIELDS, GEO_KZ);
   · что сервер печатает только в страницу кабинета — CAB_PREF_GEO, CAB_PREF_HOURS, CAB_PREF_ESCROW_OFF, MK_ESCROW_MIN,
     CAB_NEED_EGOV, TRUST_SETS, CAT_WORKS_JS, PROMO_CFG, IS_PRO, HAS_AI_KEY, AI_BLOCKED и адреса двух файлов выше
     (с меткой версии ?v=, как их подключает сама страница).

 🔴 СВОЙ РАЗБОР JSON, А НЕ JSONSerialization. У REALTY_FIELDS и PARTS_FIELDS варианты — объект {"studio":"Студия","1":"1",…}:
 порядок ключей и есть порядок чипов на сайте. NSDictionary порядок теряет — «Студия» встала бы в конец, «5+» в середину.
 Поэтому здесь маленький разборщик, который хранит пары по порядку. Файлы генерирует сайт (tools/build_*_js.php), в них
 чистый JSON после «=» — его и читаем, а не выполняем чужой скрипт.

 Справочники — общие для всех (не личные данные), живут в памяти до закрытия приложения; значения страницы — личные
 (адрес по умолчанию), живут только в модели открытого мастера.
 */

// MARK: - JSON с порядком ключей

enum ДанныеJSON {
    case объект([(String, ДанныеJSON)])
    case массив([ДанныеJSON])
    case строка(String)
    case число(Double)
    case логика(Bool)
    case пусто

    subscript(ключ: String) -> ДанныеJSON? {
        guard case .объект(let пары) = self else { return nil }
        for пара in пары where пара.0 == ключ { return пара.1 }
        return nil
    }

    var пары: [(String, ДанныеJSON)] {
        if case .объект(let п) = self { return п }
        return []
    }

    var элементы: [ДанныеJSON] {
        if case .массив(let м) = self { return м }
        return []
    }

    /// Строка как её напечатал бы JS: число без «.0», логика — true/false.
    var текст: String {
        switch self {
        case .строка(let с): return с
        case .число(let ч): return ДанныеJSON.строкаЧисла(ч)
        case .логика(let л): return л ? "true" : "false"
        default: return ""
        }
    }

    var значение: Double {
        switch self {
        case .число(let ч): return ч
        case .строка(let с): return Double(с.trimmingCharacters(in: .whitespaces)) ?? 0
        case .логика(let л): return л ? 1 : 0
        default: return 0
        }
    }

    var да: Bool {
        switch self {
        case .логика(let л): return л
        case .число(let ч): return ч != 0
        case .строка(let с): return с == "1" || с == "true"
        default: return false
        }
    }

    static func строкаЧисла(_ ч: Double) -> String {
        if ч.isFinite && ч == ч.rounded() && abs(ч) < 1e15 { return String(Int64(ч)) }
        return String(ч)
    }
}

/// Разбор JSON по байтам UTF-8 с сохранением порядка ключей.
struct РазборJSON {
    private let б: [UInt8]
    private var и: Int

    private init(_ байты: [UInt8], с началом: Int) {
        б = байты
        и = началом
    }

    /// Значение сразу после маркера («var MK_CATS=», «CAB_PREF_GEO =»): пробелы и «=» пропускаются.
    static func после(_ маркер: String, в байтах: [UInt8]) -> ДанныеJSON? {
        let м = Array(маркер.utf8)
        guard !м.isEmpty, байтах.count >= м.count else { return nil }
        var найдено = -1
        var i = 0
        let предел = байтах.count - м.count
        while i <= предел {
            if байтах[i] == м[0] {
                var j = 1
                while j < м.count && байтах[i + j] == м[j] { j += 1 }
                if j == м.count {
                    найдено = i + м.count
                    break
                }
            }
            i += 1
        }
        guard найдено >= 0 else { return nil }
        var р = РазборJSON(байтах, с: найдено)
        р.пропустить(знакРавно: true)
        return р.значение()
    }

    static func разобрать(_ байты: [UInt8]) -> ДанныеJSON? {
        var р = РазборJSON(байты, с: 0)
        return р.значение()
    }

    private mutating func пропустить(знакРавно: Bool = false) {
        while и < б.count {
            let c = б[и]
            if c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || (знакРавно && c == 0x3D) {
                и += 1
            } else {
                break
            }
        }
    }

    private mutating func значение() -> ДанныеJSON? {
        пропустить()
        guard и < б.count else { return nil }
        let c = б[и]
        if c == 0x7B { return объект() }
        if c == 0x5B { return массив() }
        if c == 0x22 {
            guard let с = строка() else { return nil }
            return .строка(с)
        }
        if слово("true") { return .логика(true) }
        if слово("false") { return .логика(false) }
        if слово("null") { return .пусто }
        return число()
    }

    private mutating func слово(_ w: String) -> Bool {
        let байты = Array(w.utf8)
        guard и + байты.count <= б.count else { return false }
        for k in 0..<байты.count where б[и + k] != байты[k] { return false }
        и += байты.count
        return true
    }

    private mutating func объект() -> ДанныеJSON? {
        и += 1
        var пары: [(String, ДанныеJSON)] = []
        пропустить()
        if и < б.count && б[и] == 0x7D {
            и += 1
            return .объект(пары)
        }
        while и < б.count {
            пропустить()
            guard и < б.count, б[и] == 0x22, let ключ = строка() else { return nil }
            пропустить()
            guard и < б.count, б[и] == 0x3A else { return nil }
            и += 1
            guard let з = значение() else { return nil }
            пары.append((ключ, з))
            пропустить()
            guard и < б.count else { return nil }
            if б[и] == 0x2C {
                и += 1
                continue
            }
            if б[и] == 0x7D {
                и += 1
                return .объект(пары)
            }
            return nil
        }
        return nil
    }

    private mutating func массив() -> ДанныеJSON? {
        и += 1
        var элементы: [ДанныеJSON] = []
        пропустить()
        if и < б.count && б[и] == 0x5D {
            и += 1
            return .массив(элементы)
        }
        while и < б.count {
            guard let з = значение() else { return nil }
            элементы.append(з)
            пропустить()
            guard и < б.count else { return nil }
            if б[и] == 0x2C {
                и += 1
                continue
            }
            if б[и] == 0x5D {
                и += 1
                return .массив(элементы)
            }
            return nil
        }
        return nil
    }

    private mutating func строка() -> String? {
        и += 1
        var байты: [UInt8] = []
        while и < б.count {
            let c = б[и]
            if c == 0x22 {
                и += 1
                return String(decoding: байты, as: UTF8.self)
            }
            if c == 0x5C {
                guard и + 1 < б.count else { return nil }
                let e = б[и + 1]
                и += 2
                switch e {
                case 0x6E: байты.append(0x0A)
                case 0x74: байты.append(0x09)
                case 0x72: байты.append(0x0D)
                case 0x62: байты.append(0x08)
                case 0x66: байты.append(0x0C)
                case 0x75:
                    guard var код = шестнадцать() else { return nil }
                    /* Суррогатная пара 📱 — один символ. */
                    if код >= 0xD800 && код <= 0xDBFF, и + 1 < б.count, б[и] == 0x5C, б[и + 1] == 0x75 {
                        и += 2
                        if let низ = шестнадцать(), низ >= 0xDC00 && низ <= 0xDFFF {
                            код = 0x10000 + ((код - 0xD800) << 10) + (низ - 0xDC00)
                        }
                    }
                    if let символ = Unicode.Scalar(код) {
                        байты.append(contentsOf: Array(String(Character(символ)).utf8))
                    }
                default:
                    байты.append(e)
                }
                continue
            }
            байты.append(c)
            и += 1
        }
        return nil
    }

    private mutating func шестнадцать() -> UInt32? {
        guard и + 4 <= б.count else { return nil }
        var итог: UInt32 = 0
        for k in 0..<4 {
            let c = б[и + k]
            var цифра: UInt32 = 0
            if c >= 0x30 && c <= 0x39 {
                цифра = UInt32(c - 0x30)
            } else if c >= 0x41 && c <= 0x46 {
                цифра = UInt32(c - 0x41 + 10)
            } else if c >= 0x61 && c <= 0x66 {
                цифра = UInt32(c - 0x61 + 10)
            } else {
                return nil
            }
            итог = итог * 16 + цифра
        }
        и += 4
        return итог
    }

    private mutating func число() -> ДанныеJSON? {
        let начало = и
        while и < б.count {
            let c = б[и]
            let цифра = c >= 0x30 && c <= 0x39
            if цифра || c == 0x2D || c == 0x2B || c == 0x2E || c == 0x65 || c == 0x45 {
                и += 1
            } else {
                break
            }
        }
        guard и > начало else { return nil }
        let текст = String(decoding: б[начало..<и], as: UTF8.self)
        guard let ч = Double(текст) else { return nil }
        return .число(ч)
    }
}

// MARK: - Справочники

/// Узел MK_CATS: ключ (slug), имя на языке страницы, родитель, дети по порядку.
struct РазделПодачи: Equatable {
    let ключ: String
    let имя: String
    let родитель: String?
    let дети: [String]
}

/// Вариант выбора: ключ, который уходит на сервер, и подпись на экране.
struct ВариантПоля: Equatable, Hashable {
    let ключ: String
    let подпись: String
}

/// Поле мастеров недвижимости и запчастей (REALTY_FIELDS / PARTS_FIELDS): {id, label, type, opt?, unit?, req?}.
struct ПолеМастера: Equatable, Identifiable {
    let id: String
    let подпись: String
    /// chips · num · select · toggle · text · ptype (справочник /api/parts_types.php).
    let вид: String
    let варианты: [ВариантПоля]
    let единица: String
    let обязательно: Bool
}

/// Поле E_SPECS: f — поле API (cpu, gpu, ram, storage, year), n + u — подпись, v — варианты (пусто — число).
/// Поле схемы сайта (СхемаПодачи) — то же плюс вид, подписи значений, подсказка, шаг и обязательность.
struct ПолеХарактеристики: Equatable, Identifiable {
    let поле: String
    let подпись: String
    let варианты: [String]
    var id: String { поле }
    /// Вид из схемы: select · number · year · text; "" — поле E_SPECS из cab-refs.js (год — списком, пустой список — число).
    var вид: String = ""
    /// Подписи значений на языке телефона (ключ — русское значение, которое уходит на сервер); пусто — значение и есть подпись.
    var подписиВариантов: [ВариантПоля] = []
    var подсказка: String = ""
    /// Шаг числа («0.1» — дробное: клавиатура с точкой).
    var шаг: String = ""
    var обязательно: Bool = false
    /// У списка есть «Другое (вписать)…».
    var своё: Bool = true
    /// Второй уровень каскада (модели семейства): значение — «семейство модель» одной строкой.
    var подварианты: [String: [String]] = [:]

    /// Год выпуска — выбором из списка лет.
    var год: Bool { вид.isEmpty ? поле == "year" : вид == "year" }

    /// Поле ввода (текст или число), а не выбор.
    var вводом: Bool {
        if вид.isEmpty { return варианты.isEmpty && поле != "year" }
        return вид == "text" || вид == "number"
    }

    /// Клавиатура поля ввода: число — цифры (с точкой, если шаг дробный), текст — обычная.
    var числом: Bool { вид.isEmpty || вид == "number" }
    var дробное: Bool { шаг.contains(".") }

    /// Варианты с подписями для показа.
    var вариантыСПодписью: [ВариантПоля] {
        guard !подписиВариантов.isEmpty else { return варианты.map { ВариантПоля(ключ: $0, подпись: $0) } }
        return подписиВариантов
    }
}

struct РайонКЗ: Equatable, Identifiable {
    let id: String
    let имя: String
    let города: [String]
}

/// Регион GEO_KZ: город республиканского значения (type "city") — город сам, районы — районы города.
struct РегионКЗ: Equatable, Identifiable {
    let id: String
    let имя: String
    let город: Bool
    let районы: [РайонКЗ]
}

struct СправочникиПодачи {
    var разделы: [String: РазделПодачи] = [:]
    var корни: [String] = []
    var характеристики: [String: [ПолеХарактеристики]] = [:]
    var бренды: [String: [String]] = [:]
    /// deal (sale | rent) → kind (apartment | house | commercial | land) → поля.
    var недвижимость: [String: [String: [ПолеМастера]]] = [:]
    /// kind (part | tire | wheel | oil | light | accessory | audio) → поля.
    var запчасти: [String: [ПолеМастера]] = [:]
    var регионы: [РегионКЗ] = []

    var пусто: Bool { разделы.isEmpty }

    /// Корень раздела (cabRootSection сайта). Неизвестный — сам себе корень.
    func корень(_ ключ: String) -> String {
        var текущий = ключ
        var шаги = 0
        while let родитель = разделы[текущий]?.родитель, шаги < 25 {
            текущий = родитель
            шаги += 1
        }
        return текущий
    }

    /// Раздел или его предок — один из данных.
    func внутри(_ ключ: String, _ предки: Set<String>) -> Bool {
        var текущий: String? = ключ
        var шаги = 0
        while let узел = текущий, шаги < 25 {
            if предки.contains(узел) { return true }
            текущий = разделы[узел]?.родитель
            шаги += 1
        }
        return false
    }

    /// Цепочка от корня до раздела: [корень, …, раздел].
    func цепочка(_ ключ: String) -> [String] {
        var путь: [String] = []
        var текущий: String? = ключ
        var шаги = 0
        while let узел = текущий, !узел.isEmpty, шаги < 25 {
            путь.insert(узел, at: 0)
            текущий = разделы[узел]?.родитель
            шаги += 1
        }
        return путь
    }

    func имя(_ ключ: String) -> String {
        разделы[ключ]?.имя ?? ""
    }

    /// Первое найденное вверх по дереву (specsFor, setBrandOptions сайта — до 10 уровней).
    func вверх<Т>(_ ключ: String, _ словарь: [String: Т]) -> Т? {
        var текущий: String? = ключ
        var шаги = 0
        while let узел = текущий, шаги < 10 {
            if let найдено = словарь[узел] { return найдено }
            текущий = разделы[узел]?.родитель
            шаги += 1
        }
        return nil
    }

    // MARK: Разбор файлов сайта

    static func разобрать(разделы файлРазделов: [UInt8], справочники файлСправочников: [UInt8]) -> СправочникиПодачи {
        var с = СправочникиПодачи()
        if let дерево = РазборJSON.после("var MK_CATS=", в: файлРазделов) {
            for корень in дерево.элементы {
                if let ключ = добавить(корень, родитель: nil, в: &с.разделы) { с.корни.append(ключ) }
            }
        }
        guard let refs = РазборJSON.после("var KLK_CAB_REFS=", в: файлСправочников) else { return с }
        if let specs = refs["E_SPECS"] {
            for (раздел, поля) in specs.пары {
                с.характеристики[раздел] = поля.элементы.map { поле -> ПолеХарактеристики in
                    let имя = поле["n"]?.текст ?? ""
                    let единица = поле["u"]?.текст ?? ""
                    return ПолеХарактеристики(поле: поле["f"]?.текст ?? "",
                                              подпись: единица.isEmpty ? имя : имя + ", " + единица,
                                              варианты: (поле["v"]?.элементы ?? []).map { $0.текст })
                }.filter { !$0.поле.isEmpty }
            }
        }
        if let бренды = refs["BRAND_LIST"] {
            for (раздел, список) in бренды.пары {
                с.бренды[раздел] = список.элементы.map { $0.текст }.filter { !$0.isEmpty }
            }
        }
        if let realty = refs["REALTY_FIELDS"] {
            for (сделка, виды) in realty.пары {
                var поВидам: [String: [ПолеМастера]] = [:]
                for (вид, поля) in виды.пары { поВидам[вид] = поляМастера(поля) }
                с.недвижимость[сделка] = поВидам
            }
        }
        if let parts = refs["PARTS_FIELDS"] {
            for (вид, поля) in parts.пары { с.запчасти[вид] = поляМастера(поля) }
        }
        if let geo = refs["GEO_KZ"] {
            с.регионы = geo.элементы.map { р -> РегионКЗ in
                let районы = (р["districts"]?.элементы ?? []).map { д -> РайонКЗ in
                    РайонКЗ(id: д["key"]?.текст ?? "", имя: д["name"]?.текст ?? "",
                            города: (д["cities"]?.элементы ?? []).map { $0.текст })
                }
                return РегионКЗ(id: р["key"]?.текст ?? "", имя: р["name"]?.текст ?? "",
                                город: (р["type"]?.текст ?? "") == "city", районы: районы)
            }.filter { !$0.id.isEmpty }
        }
        return с
    }

    private static func добавить(_ узел: ДанныеJSON, родитель: String?, в разделы: inout [String: РазделПодачи]) -> String? {
        guard let ключ = узел["slug"]?.текст, !ключ.isEmpty else { return nil }
        var дети: [String] = []
        for ребёнок in узел["children"]?.элементы ?? [] {
            if let к = добавить(ребёнок, родитель: ключ, в: &разделы) { дети.append(к) }
        }
        разделы[ключ] = РазделПодачи(ключ: ключ, имя: узел["name"]?.текст ?? ключ, родитель: родитель, дети: дети)
        return ключ
    }

    private static func поляМастера(_ поля: ДанныеJSON) -> [ПолеМастера] {
        поля.элементы.map { п -> ПолеМастера in
            ПолеМастера(id: п["id"]?.текст ?? "", подпись: п["label"]?.текст ?? "", вид: п["type"]?.текст ?? "text",
                        варианты: (п["opt"]?.пары ?? []).map { ВариантПоля(ключ: $0.0, подпись: $0.1.текст) },
                        единица: п["unit"]?.текст ?? "", обязательно: п["req"]?.да ?? false)
        }.filter { !$0.id.isEmpty }
    }
}

// MARK: - Значения страницы кабинета

/// Пакет ТОП из PROMO_CFG.packages: {key, label, top_days, bumps, price}.
struct ПакетТоп: Equatable, Identifiable {
    let id: String
    let подпись: String
    let днейТоп: Int
    let цена: Int
}

/// Знак доверия из TRUST_SETS: {key, label, type?:"days"} — «days» — это срок гарантии (warranty_days), а не флажок.
struct ЗнакДоверия: Equatable, Identifiable {
    let id: String
    let подпись: String
    let срок: Bool
}

struct СтраницаПодачи {
    /// Разобранная страница кабинета (вход, токен, IS_SHOP, CAB_AI). Опционал — чтобы значение по умолчанию не звало
    /// инициализатор типа из @MainActor-перечисления вне главного потока.
    var состояние: КабинетСайта.Состояние? = nil
    /// CAB_PREF_GEO — «Регион/адрес по умолчанию» из настроек.
    var регион = ""
    var район = ""
    var город = ""
    var адрес = ""
    var lat = ""
    var lon = ""
    /// CAB_PREF_HOURS — «Режим работы по умолчанию».
    var часы = ""
    var часыС = ""
    var часыДо = ""
    /// CAB_PREF_ESCROW_OFF — гарант в новых объявлениях выключен.
    var гарантВыключен = false
    /// MK_ESCROW_MIN — гарант от этой цены (20 000 ₸).
    var минимумГаранта = 0
    /// CAB_NEED_EGOV — плашка «Без верификации объявление не выйдет на витрину».
    var нуженEgov = false
    var знаки: [String: [ЗнакДоверия]] = [:]
    /// CAT_WORKS_JS: разделы, где спрашивают «Вещь работает?», и исключения.
    var работаетВ: [String] = []
    var работаетКроме: [String] = []
    var пакеты: [ПакетТоп] = []
    var скидкаТоп = 0
    var pro = false
    var ключИИ = false
    var иИЗаблокирован = false
    var путьРазделов = "/js/cats-ru.js"
    var путьСправочников = "/js/cab-refs.js"

    /// Разбор HTML кабинета (сверено по снимку user/kz_ru_cabinet_go_add.html).
    static func разобрать(_ html: String, состояние: КабинетСайта.Состояние) -> СтраницаПодачи {
        var с = СтраницаПодачи()
        с.состояние = состояние
        let байты = Array(html.utf8)
        if let гео = РазборJSON.после("CAB_PREF_GEO =", в: байты) {
            с.регион = гео["region"]?.текст ?? ""
            с.район = гео["district"]?.текст ?? ""
            с.город = гео["city"]?.текст ?? ""
            с.адрес = гео["address"]?.текст ?? ""
            с.lat = гео["lat"]?.текст ?? ""
            с.lon = гео["lon"]?.текст ?? ""
        }
        if let часы = РазборJSON.после("CAB_PREF_HOURS =", в: байты) {
            с.часы = часы["mode"]?.текст ?? ""
            с.часыС = часы["from"]?.текст ?? ""
            с.часыДо = часы["to"]?.текст ?? ""
        }
        с.гарантВыключен = найти(#"CAB_PREF_ESCROW_OFF\s*=\s*(true|false)"#, в: html) == "true"
        с.минимумГаранта = Int(найти(#"MK_ESCROW_MIN\s*=\s*(\d+)"#, в: html) ?? "") ?? 0
        с.нуженEgov = найти(#"CAB_NEED_EGOV\s*=\s*(true|false)"#, в: html) == "true"
        с.pro = найти(#"const IS_PRO\s*=\s*(true|false)"#, в: html) == "true"
        с.ключИИ = найти(#"HAS_AI_KEY\s*=\s*(true|false)"#, в: html) == "true"
        с.иИЗаблокирован = найти(#"AI_BLOCKED\s*=\s*(true|false)"#, в: html) == "true"
        if let знаки = РазборJSON.после("TRUST_SETS =", в: байты) {
            for (группа, список) in знаки.пары {
                с.знаки[группа] = список.элементы.map { з -> ЗнакДоверия in
                    ЗнакДоверия(id: з["key"]?.текст ?? "", подпись: з["label"]?.текст ?? "",
                                срок: (з["type"]?.текст ?? "") == "days")
                }.filter { !$0.id.isEmpty }
            }
        }
        if let работает = РазборJSON.после("CAT_WORKS_JS =", в: байты) {
            с.работаетВ = (работает["in"]?.элементы ?? []).map { $0.текст }
            с.работаетКроме = (работает["out"]?.элементы ?? []).map { $0.текст }
        }
        if let промо = РазборJSON.после("PROMO_CFG =", в: байты) {
            с.пакеты = (промо["packages"]?.элементы ?? []).map { п -> ПакетТоп in
                ПакетТоп(id: п["key"]?.текст ?? "", подпись: п["label"]?.текст ?? "",
                         днейТоп: Int(п["top_days"]?.значение ?? 0), цена: Int(п["price"]?.значение ?? 0))
            }.filter { !$0.id.isEmpty }
            с.скидкаТоп = Int(промо["discount_pct"]?.значение ?? 0)
        }
        if let путь = найти(#"src="(/js/cats-[a-z]+\.js[^"]*)""#, в: html) { с.путьРазделов = путь }
        if let путь = найти(#"src="(/js/cab-refs\.js[^"]*)""#, в: html) { с.путьСправочников = путь }
        return с
    }

    /// promoDisc сайта: цена со скидкой PROMO_CFG.discount_pct, округлённая до десятков.
    func ценаСоСкидкой(_ цена: Int) -> Int {
        guard скидкаТоп > 0 else { return цена }
        let сырая = Double(цена) * Double(100 - скидкаТоп) / 100 / 10
        return max(0, 10 * Int(сырая.rounded()))
    }

    private static func найти(_ шаблон: String, в тексте: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: []) else { return nil }
        let весь = NSRange(тексте.startIndex..<тексте.endIndex, in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь),
              совпадение.numberOfRanges > 1,
              let диапазон = Range(совпадение.range(at: 1), in: тексте) else { return nil }
        return String(тексте[диапазон])
    }
}

// MARK: - Загрузка справочников

/// Справочники в памяти: одни на все открытия мастера, пока не сменилась версия файлов (?v= в адресе).
@MainActor
enum ЗагрузкаСправочников {
    private static var готовые: СправочникиПодачи? = nil
    private static var ключ = ""

    static func загрузить(_ страница: СтраницаПодачи) async throws -> СправочникиПодачи {
        let новый = страница.путьРазделов + "|" + страница.путьСправочников
        if let есть = готовые, ключ == новый, !есть.пусто { return есть }
        let разделы = try await КабинетСайта.вызвать(страница.путьРазделов, отКорня: true)
        let справочники = try await КабинетСайта.вызвать(страница.путьСправочников, отКорня: true)
        guard разделы.код == 200, справочники.код == 200 else { throw КабинетСайта.Сбой.сеть }
        let текстРазделов = разделы.текст
        let текстСправочников = справочники.текст
        let итог = await Task.detached(priority: .userInitiated) { () -> СправочникиПодачи in
            СправочникиПодачи.разобрать(разделы: Array(текстРазделов.utf8), справочники: Array(текстСправочников.utf8))
        }.value
        guard !итог.пусто else { throw КабинетСайта.Сбой.приложение }
        готовые = итог
        ключ = новый
        return итог
    }
}
