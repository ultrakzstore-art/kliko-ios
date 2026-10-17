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

/// Вид fit_match: строкой («car»: "ok") или объектом («std»: {level, part, g}).
struct ВидПодбораСервера: Decodable {
    let уровень: String?
    let деталь: String?
    let группа: Int?

    private enum CodingKeys: String, CodingKey {
        case level, part, g
    }

    init(from decoder: Decoder) throws {
        if let строка = try? decoder.singleValueContainer().decode(String.self) {
            уровень = строка.trimmingCharacters(in: .whitespaces).lowercased()
            деталь = nil
            группа = nil
            return
        }
        guard let к = try? decoder.container(keyedBy: CodingKeys.self) else {
            уровень = nil
            деталь = nil
            группа = nil
            return
        }
        уровень = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .level))?.текст?.lowercased()
        деталь = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .part))?.текст
        let номер: String = (try? к.decode(ЗначениеПоляЛенты.self, forKey: .g))?.текст ?? ""
        группа = Int(номер)
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

    /// Уровень сервера для вида в шкале приложения; вид не прислан или незнаком — nil.
    func уровень(_ вид: String) -> УровеньАвтоподбора? {
        guard let строка = виды[вид] else { return nil }
        switch строка {
        case "ok", "universal": return .подходит
        case "adapt", "rings", "spacers", "rings+spacers": return .доработка
        case "check", "text", "tight", "loose": return .проверить
        case "no": return .неПодходит
        default: return nil
        }
    }

    /// Из разобранного fit_match; ничего годного — nil.
    static func собрать(_ сырые: [String: ВидПодбораСервера]) -> УровеньСервераОбъявления? {
        var итог = УровеньСервераОбъявления()
        for ключ in сырые.keys.sorted() {
            guard let вид = сырые[ключ], let уровень = вид.уровень, !уровень.isEmpty else { continue }
            итог.виды[ключ.lowercased()] = уровень
            if итог.деталь == nil, let деталь = вид.деталь, !деталь.isEmpty { итог.деталь = деталь }
            if итог.группа == nil { итог.группа = вид.группа }
        }
        return итог.виды.isEmpty ? nil : итог
    }
}
