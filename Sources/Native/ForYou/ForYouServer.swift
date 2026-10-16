import Foundation

/**
 «ДЛЯ ВАС» — КРЮЧОК ПОД ОТБОР НА СЕРВЕРЕ (docs/SERVER_MY_THINGS.md §3 «Фильтры ленты», §3.7 «Признаки готовности в
 схеме», §10 «Приватность»).

 Договор: значения из «Моего» (fit_car, fit_phone, fit_laptop, size, fit_level) — только телом POST на
 api/listings.php, остальное (cat, город, per, sort) — в адресе, как у GET; ответ тот же. Какие виды сервер применяет,
 он объявляет в схеме подачи — rules.fit_filters ({"car": true, "phone": true, …}); схему приложение уже держит в
 Caches (ЗагрузкаСхемыПодачи, Posting/PostingSchema.swift) — здесь читается только этот файл, без сети.

 По умолчанию крючок выключен (включён = false): v1 «ничего не уходит с телефона» — полка грузит раздел, как любая
 лента, и сверяет на телефоне. Включить — когда сервер закроет §10 (POST не в журналах) и владелец решит; тогда для
 объявленных видов значения уйдут телом, а сверка на телефоне всё равно остаётся — fit_applied ответа не обязателен.
 Дом и компьютер (fit_std) — позже, у сервера их ещё нет.
 */
enum ОтборСервераДляВас {
    /// Рубильник крючка. false — в сеть ничего из «Моего»; true — POST для видов из rules.fit_filters.
    static let включён = false

    private static let сеть = СетьСайта.Запросы(json: true, безКэша: true)

    /// Вид §3 для профиля: car, phone, laptop, size; у дома и компьютера — nil.
    static func вид(_ профиль: ИтогСовместимостиМоего.Профиль) -> String? {
        switch профиль {
        case .машина: return "car"
        case .телефон: return "phone"
        case .ноутбук: return "laptop"
        case .размер: return "size"
        case .дом, .компьютер: return nil
        }
    }

    /// Тела POST по разделам: только объявленные сервером виды и только при включённом крючке; иначе пусто.
    static func тела(_ запросы: [ЗапросПодбораМоего], моё: ЗаписьМоего) async -> [String: [String: String]] {
        guard включён, !запросы.isEmpty else { return [:] }
        let объявлено = await Self.признаки()
        guard !объявлено.isEmpty else { return [:] }
        var итог: [String: [String: String]] = [:]
        for запрос in запросы where итог[запрос.раздел] == nil {
            if let т = Self.тело(запрос, моё: моё, объявлено: объявлено) { итог[запрос.раздел] = т }
        }
        return итог
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
            return Set(флаги.compactMap { пара in (пара.value as? Bool) == true ? пара.key : nil })
        }.value
    }

    /// Тело запроса раздела: {"fit_car": "…", "fit_level": "parts"}; вид не объявлен или в «Моём» нет значения — nil.
    static func тело(_ запрос: ЗапросПодбораМоего, моё: ЗаписьМоего, объявлено: Set<String>) -> [String: String]? {
        guard let имяВида = Self.вид(запрос.профиль), объявлено.contains(имяВида) else { return nil }
        let строка: String?
        switch запрос.профиль {
        case .машина: строка = моё.главнаяМашина.flatMap { Self.значениеПосадки($0) }
        case .телефон: строка = моё.телефон.flatMap { Self.slug($0.модель) }
        case .ноутбук: строка = СовместимостьМоего.диагональНоутбука(моё).map { String(format: "%.1f", $0) }
        case .размер: строка = Self.размеры(моё.тело.размеры)
        case .дом, .компьютер: строка = nil
        }
        guard let строка, !строка.isEmpty else { return nil }
        let поле = имяВида == "size" ? "size" : "fit_" + имяВида
        return [поле: строка, "fit_level": "parts"]
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
        var слова = модель.lowercased().replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "+", with: " plus ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { русскиеСлова[$0] ?? $0 }
            .filter { слово in
                !лишниеСлова.contains(слово) && !(слово.hasSuffix("gb") && Int(слово.dropLast(2)) != nil)
                    && слово.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
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

    /// POST ленты: адрес — тот же, что у GET (ListingsAPI.адрес, в нём нет «Моего»), значения — телом JSON.
    static func загрузить(_ з: ListingsAPI.Запрос, тело: [String: String], куки: [String: String]) async throws
        -> ListingsPage {
        var запрос = URLRequest(url: ListingsAPI.адрес(з))
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.httpBody = try JSONSerialization.data(withJSONObject: тело)
        let (данные, ответ) = try await сеть.data(for: запрос)
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ListingsAPI.Ошибка.статус(http.statusCode)
        }
        return try await ListingsAPI.разобратьВФоне(данные)
    }
}
