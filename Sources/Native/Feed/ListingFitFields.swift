import Foundation

/**
 ПОЛЯ ОБЪЯВЛЕНИЯ ДЛЯ «МОЕГО» (пачка 83; docs/SERVER_NEW_FOR_MINE.md §1.1, §2.2, §5; docs/SERVER_STANDARDS.md §2–3;
 docs/SERVER_SIZES.md §2.5; docs/SERVER_MY_THINGS.md §2.1).

 Сервер начинает отдавать стандарты полями, а не только текстом: std ({семья: {поле: значение}}), std_src, qty, parts
 шин и дисков, size_sys и size_all одежды, size_avail магазина, collection и collection_new, fit_match подбора сервера.
 Разбор терпимый, как у всего объявления (Listing.swift): значение строкой, числом, да-нет или списком; не разобралось —
 пусто, объявление от этого не падает. Ищутся только присланные ключи (c.contains) — первая лента не медленнее.

 Кто читает: сверка «Моего» — шины и диски (РазборАвтоподбора.из, AutoFitParse.swift: parts первыми), стандарты дома и
 компьютера (РазборСтандартов.разобрать, StandardsNormalize.swift: std первым слоем), одежда и обувь
 (СовместимостьМоего, MyThingsMatch.swift: size_all, storage в системе size_sys, size_avail); «Для вас» — уровень
 сервера fit_match (не лучше своего, ForYouModel.swift) и сезон шин (ForYouSeason.swift).

 Пачка 84 (ответ сервера 17.10.2026: std, std_src, qty, parts, плоские tyre_* и rim_*, size_sys и size_all, fit_match
 и fit_applied включены на проде). Только добавления: std терпит краткую форму семьи, std_src — и объектом по семьям,
 qty читается и без std, плоские tyre_* и rim_* дополняют parts, fit_match.std — ещё by и text (из текста — не лучше
 «Проверьте»), деталь — словами телефона; fit_applied страницы — ListingsPage.применёноСервером.
 */

// MARK: - Значение поля

/// Значение поля в любом виде PHP: строка, число, да-нет, список (через запятую); null и пусто — nil.
struct ЗначениеПоляЛенты: Decodable {
    let текст: String?

    static let пределДлины = 200

    init(from decoder: Decoder) throws {
        let з = try decoder.singleValueContainer()
        if з.decodeNil() {
            текст = nil
        } else if let s = try? з.decode(String.self) {
            let чистая: String = s.trimmingCharacters(in: .whitespacesAndNewlines)
            текст = чистая.isEmpty ? nil : String(чистая.prefix(Self.пределДлины))
        } else if let b = try? з.decode(Bool.self) {
            текст = b ? "1" : "0"
        } else if let d = try? з.decode(Double.self), d.isFinite, abs(d) < 1e15 {
            текст = d == d.rounded() ? String(Int(d)) : String(d)
        } else if let список = try? з.decode([ЗначениеПоляЛенты].self) {
            let части: [String] = список.compactMap { (элемент: ЗначениеПоляЛенты) -> String? in элемент.текст }
            текст = части.isEmpty ? nil : String(части.joined(separator: ",").prefix(Self.пределДлины))
        } else {
            текст = nil
        }
    }

    /// {поле: значение} без пустых, ключи — без пробелов по краям, не больше 24 полей.
    static func словарь(_ сырые: [String: ЗначениеПоляЛенты]) -> [String: String] {
        var итог: [String: String] = [:]
        for ключ in сырые.keys.sorted() {
            let чистый: String = ключ.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !чистый.isEmpty, чистый.count <= 40, let текст = сырые[ключ]?.текст else { continue }
            итог[чистый] = текст
            if итог.count >= 24 { break }
        }
        return итог
    }
}

// MARK: - Стандарты продавца (пачка 84: ответ сервера 17.10.2026 — std, std_src, qty включены на проде)

/**
 Значение одной семьи std (docs/SERVER_STANDARDS.md §3.1): объект {поле: значение} или краткая форма одним значением
 ({"lamp_base": "E14"} — это первое главное поле семьи). Выдача обещает объектную форму, но разбор терпит обе: семья
 краткой формой не роняет весь std.
 */
struct ЗначенияСемьиЛенты: Decodable {
    let поля: [String: String]
    /// Краткая форма; nil — пришёл объект (или ничего годного).
    let кратко: String?

    init(from decoder: Decoder) throws {
        let з = try decoder.singleValueContainer()
        if let объект = try? з.decode([String: ЗначениеПоляЛенты].self) {
            поля = ЗначениеПоляЛенты.словарь(объект)
            кратко = nil
        } else {
            поля = [:]
            кратко = (try? з.decode(ЗначениеПоляЛенты.self))?.текст
        }
    }

    /// Поля семьи: объект — как есть, краткая форма — первым главным полем; семья незнакома — пусто (сверка её не знает).
    func поляСемьи(_ ключ: String) -> [String: String] {
        guard let кратко else { return поля }
        guard let семья = СемьяСтандарта(rawValue: ключ), let главное = семья.главные.first else { return [:] }
        return [главное: кратко]
    }
}

/**
 std_src (§3.1): строкой на всё объявление или объектом по семьям ({"ram_module": "scan"}). "" и не пришёл — слово
 продавца; незнакомое значение — как текст (не лучше «Проверьте»: лишнее «Подходит» дороже лишнего «Проверьте»).
 */
struct ИсточникиСтандартаЛенты: Decodable {
    /// Общий источник; объектом — nil.
    let общий: String?
    /// Источник по семьям (ключ — семья каталога); строкой — пусто.
    let поСемьям: [String: String]

    init(from decoder: Decoder) throws {
        let з = try decoder.singleValueContainer()
        if let строка = try? з.decode(String.self) {
            общий = строка.trimmingCharacters(in: .whitespacesAndNewlines)
            поСемьям = [:]
        } else if let объект = try? з.decode([String: ЗначениеПоляЛенты].self) {
            /* Пустое и null у семьи выпадают — у такой семьи общий источник: слово продавца. */
            общий = nil
            поСемьям = ЗначениеПоляЛенты.словарь(объект)
        } else {
            общий = nil
            поСемьям = [:]
        }
    }

    /// Источник приложения по строке договора: "" — продавец, знакомый — свой, незнакомый — текст.
    static func источник(_ строка: String) -> ИсточникСтандарта {
        let чистая: String = строка.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if чистая.isEmpty { return .продавец }
        return ИсточникСтандарта(rawValue: чистая) ?? .текст
    }
}

// MARK: - Шины и диски плоскими полями

/**
 Плоские tyre_* и rim_* (docs/SERVER_DIMENSIONS.md §1.3; ответ сервера 17.10.2026 — в выдаче рядом с parts). Сверка шин
 и дисков читает parts (РазборАвтоподбора.принять), поэтому плоские поля кладутся туда же под ключами parts — только
 недостающее: своё parts продавца не затирается.
 */
enum ПлоскиеКолёсаЛенты {
    /// tyre_* → ключ parts шины.
    static let шины: [(String, String)] = [("tyre_w", "width"), ("tyre_h", "profile"), ("tyre_r", "diameter")]
    /// rim_* → ключ parts диска.
    static let диски: [(String, String)] = [("rim_r", "diameter"), ("rim_j", "width_j"), ("rim_et", "et"),
                                            ("rim_pcd", "pcd"), ("rim_dia", "dia")]

    /// Все плоские ключи — чтобы искать в ответе только их.
    static var ключи: [String] {
        let шинные: [String] = шины.map { (пара: (String, String)) -> String in пара.0 }
        let дисковые: [String] = диски.map { (пара: (String, String)) -> String in пара.0 }
        return шинные + дисковые
    }

    /**
     parts, дополненный плоскими полями. Вид — из parts.kind; нет его — по полям: есть rim_* — диск, только tyre_* —
     шина. У диска ширина и профиль шины тоже кладутся (колёса в сборе: посадка шины — диаметр диска).
     */
    static func дополнить(_ parts: [String: String], плоскими плоские: [String: String]) -> [String: String] {
        guard !плоские.isEmpty else { return parts }
        var итог: [String: String] = parts
        let естьДиск: Bool = диски.contains { (пара: (String, String)) -> Bool in плоские[пара.0] != nil }
        let естьШина: Bool = шины.contains { (пара: (String, String)) -> Bool in плоские[пара.0] != nil }
        var вид: String = (итог["kind"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if вид.isEmpty {
            if естьДиск {
                вид = "wheel"
            } else if естьШина {
                вид = "tire"
            }
            if !вид.isEmpty { итог["kind"] = вид }
        }
        if вид == "wheel" {
            for (плоское, ключ) in диски where итог[ключ] == nil {
                if let значение = плоские[плоское] { итог[ключ] = значение }
            }
            for (плоское, ключ) in шины where ключ != "diameter" && итог[ключ] == nil {
                if let значение = плоские[плоское] { итог[ключ] = значение }
            }
        } else if вид == "tire" {
            for (плоское, ключ) in шины where итог[ключ] == nil {
                if let значение = плоские[плоское] { итог[ключ] = значение }
            }
        }
        return итог
    }
}

// MARK: - Коллекция

/// Партия магазина (collection, §5.1): «Осень-зима 2026», сезон ss · aw · all, год 2020…2100.
struct КоллекцияОбъявления: Hashable, Decodable {
    let название: String
    let сезон: String
    let год: Int?

    private enum CodingKeys: String, CodingKey {
        case название = "name"
        case сезон = "season"
        case год = "year"
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        let имя: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .название))?.текст ?? ""
        название = String(имя.prefix(60))
        let своё: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .сезон))?.текст ?? ""
        let нижнее: String = своё.lowercased()
        сезон = ["ss", "aw", "all"].contains(нижнее) ? нижнее : ""
        let годСтрокой: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .год))?.текст ?? ""
        if let n = Int(годСтрокой), (2020...2100).contains(n) {
            год = n
        } else {
            год = nil
        }
    }
}

// MARK: - Подбор сервера

/// Вид fit_match: строкой («car»: "ok") или объектом («std»: {level, part, g, by, text}).
struct ВидПодбораСервера: Decodable {
    let уровень: String?
    let деталь: String?
    let группа: Int?
    /// by — уровень по каждой сверенной семье ({"lamp_base": "adapt"}); строкой — пусто.
    let поСемьям: [String: String]
    /// text: true — сверено по значению из текста продавца (std_src: "text"): не лучше «Проверьте».
    let изТекста: Bool

    private enum CodingKeys: String, CodingKey {
        case level, part, g, by, text
    }

    init(from decoder: Decoder) throws {
        if let строка = try? decoder.singleValueContainer().decode(String.self) {
            уровень = строка.trimmingCharacters(in: .whitespaces).lowercased()
            деталь = nil
            группа = nil
            поСемьям = [:]
            изТекста = false
            return
        }
        guard let к = try? decoder.container(keyedBy: CodingKeys.self) else {
            уровень = nil
            деталь = nil
            группа = nil
            поСемьям = [:]
            изТекста = false
            return
        }
        уровень = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .level))?.текст?.lowercased()
        деталь = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .part))?.текст
        let номер: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .g))?.текст ?? ""
        группа = Int(номер)
        let семьи: [String: ЗначениеПоляЛенты] = (try? к.decode([String: ЗначениеПоляЛенты].self, forKey: .by)) ?? [:]
        var уровни: [String: String] = [:]
        for (семья, значение) in ЗначениеПоляЛенты.словарь(семьи) { уровни[семья] = значение.lowercased() }
        поСемьям = уровни
        let текст: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .text))?.текст ?? ""
        изТекста = текст == "1" || текст.lowercased() == "true"
    }
}

/**
 fit_match подбора сервера (§2.2): уровень по видам — car, phone, laptop, size, std. Уровень на телефоне — не лучше
 уровня сервера: в нём учтено доверие к продавцу (§8.3), которого телефон не видит.
 */
struct УровеньСервераОбъявления: Hashable {
    /// Вид → уровень сервера строкой («ok», «adapt», «rings», «check»…).
    var виды: [String: String] = [:]
    /// Деталь у adapt («E14→E27»).
    var деталь: String? = nil
    /// Номер группы fit_std, по которой подошло.
    var группа: Int? = nil
    /// fit_match.std.by — уровень по каждой сверенной семье («lamp_base»: «adapt»).
    var поСемьям: [String: String] = [:]
    /// fit_match.std.text — сверено по значению из текста: уровень std не лучше «Проверьте».
    var изТекста = false

    /// Уровень сервера для вида в шкале приложения; вид не прислан — nil. Незнакомое значение — «Проверьте»
    /// (docs/SERVER_MY_THINGS.md §3.1), сверено по тексту — тоже не лучше «Проверьте».
    func уровень(_ вид: String) -> УровеньАвтоподбора? {
        guard let строка = виды[вид] else { return nil }
        let свой: УровеньАвтоподбора
        switch строка {
        case "ok", "universal": свой = .подходит
        case "adapt", "rings", "spacers", "rings+spacers": свой = .доработка
        case "check", "text", "tight", "loose": свой = .проверить
        case "no": свой = .неПодходит
        default: свой = .проверить
        }
        if вид == "std" && изТекста { return max(свой, .проверить) }
        return свой
    }

    /// Вид fit_match профиля сверки «Моего»: car, phone, laptop, size; дом и компьютер — std (fit_std).
    static func видПрофиля(_ профиль: ИтогСовместимостиМоего.Профиль) -> String {
        switch профиль {
        case .машина: return "car"
        case .телефон: return "phone"
        case .ноутбук: return "laptop"
        case .размер: return "size"
        case .дом, .компьютер: return "std"
        }
    }

    /// Уровень сервера для профиля сверки; не прислан — nil.
    func уровень(профиля профиль: ИтогСовместимостиМоего.Профиль) -> УровеньАвтоподбора? {
        уровень(Self.видПрофиля(профиль))
    }

    /**
     Деталь сервера словами телефона (§2.2: причину собирает телефон): «E14→E27» — «переходник E14 → E27»,
     «plate 100→200» — «пластина-переходник VESA»; прочий канон — как пришёл, коротко. Нет — nil.
     */
    var показДетали: String? {
        guard let канон = деталь?.trimmingCharacters(in: .whitespacesAndNewlines), !канон.isEmpty else { return nil }
        let нижний: String = канон.lowercased()
        if нижний.hasPrefix("plate") { return СтандартыText.т("st_vesa_plate") }
        if канон.contains("→") && !канон.contains(" ") {
            let части: [String] = канон.components(separatedBy: "→")
            let переход: String = части.joined(separator: " → ")
            return String(format: СтандартыText.т("st_adapter"), переход)
        }
        return String(канон.prefix(60))
    }

    /// Из разобранного fit_match; ничего годного — nil.
    static func собрать(_ сырые: [String: ВидПодбораСервера]) -> УровеньСервераОбъявления? {
        var итог = УровеньСервераОбъявления()
        for ключ in сырые.keys.sorted() {
            guard let сырой = сырые[ключ], let строка = сырой.уровень, !строка.isEmpty else { continue }
            let имя: String = ключ.lowercased()
            итог.виды[имя] = строка
            if итог.деталь == nil, let деталь = сырой.деталь, !деталь.isEmpty { итог.деталь = деталь }
            if итог.группа == nil { итог.группа = сырой.группа }
            if имя == "std" {
                итог.поСемьям = сырой.поСемьям
                итог.изТекста = сырой.изТекста
            }
        }
        return итог.виды.isEmpty ? nil : итог
    }
}
