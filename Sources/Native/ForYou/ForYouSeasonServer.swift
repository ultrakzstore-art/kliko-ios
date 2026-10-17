import Foundation

/**
 «ДЛЯ ВАС» — ПРАВИЛА СЕЗОНА С СЕРВЕРА (пачка 83; docs/SERVER_NEW_FOR_MINE.md §4.1). Только при ключе season_rules
 (по умолчанию выключен): ключ выключен — ни одного запроса, правила сервера сняты, работают встроенные
 (ForYouSeason.swift).

 GET /api/for_mine.php?action=season&lang=<язык> — без куков, не чаще раза в сутки, с ETag (304 — без тела). Ответ
 публичный: в адресе нет ничего из «Моего». Последний ответ лежит в UserDefaults (общие даты сезона, не «Моё»).
 «Не поддерживается» (404, 405, 410, 501, не JSON, ok false) — до перезапуска не спрашиваем; временный сбой (обрыв,
 таймаут, 5xx, 429) — повтор при следующем открытии полки.
 */
@MainActor
enum ПравилаСезонаСервера {
    private static let ключОтвета = "kliko.foryou.season.json"
    private static let ключМетки = "kliko.foryou.season.etag"
    private static let ключКогда = "kliko.foryou.season.at"
    private static var неПоддерживается = false
    private static var идёт = false
    /// Спрашивать не чаще, с.
    private static let сутки: Double = 86_400

    /// Разобранный ответ: правила и свои даты городов.
    struct Ответ: Sendable {
        let правила: [ПравилоСезонаДляВас]
        let гео: [String: [String: [Int]]]
    }

    /// Полка начала работу: ключ выключен — снять правила сервера; включён — взять сохранённые и раз в сутки спросить.
    static func обновить() {
        guard РубильникиНовинок.сезонСервера else {
            СезонДляВас.поставитьСервера(nil, гео: [:])
            return
        }
        let хранилище = UserDefaults.standard
        if let данные = хранилище.data(forKey: ключОтвета), let ответ = разобрать(данные) {
            СезонДляВас.поставитьСервера(ответ.правила, гео: ответ.гео)
        }
        let было: Double = хранилище.double(forKey: ключКогда)
        let сейчас: Double = Date().timeIntervalSince1970
        let прошло: Double = сейчас - было
        guard !неПоддерживается, !идёт, прошло > сутки else { return }
        идёт = true
        Task { @MainActor in
            await ПравилаСезонаСервера.загрузить()
            ПравилаСезонаСервера.идёт = false
        }
    }

    private static func загрузить() async {
        let язык: String = ПримерочнаяText.язык
        guard let адрес = Config.url("/api/for_mine.php?action=season&lang=" + язык) else { return }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        let хранилище = UserDefaults.standard
        if хранилище.data(forKey: ключОтвета) != nil, let метка = хранилище.string(forKey: ключМетки) {
            запрос.setValue(метка, forHTTPHeaderField: "If-None-Match")
        }
        guard let пара = try? await СетьНовинокМоего.сессия.data(for: запрос),
              let http = пара.1 as? HTTPURLResponse else { return }
        let код: Int = http.statusCode
        if код == 304 {
            хранилище.set(Date().timeIntervalSince1970, forKey: ключКогда)
            return
        }
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) {
            неПоддерживается = true
            return
        }
        guard код == 200 else { return }
        guard let ответ = разобрать(пара.0) else {
            неПоддерживается = true
            return
        }
        хранилище.set(пара.0, forKey: ключОтвета)
        if let метка = http.value(forHTTPHeaderField: "ETag"), !метка.isEmpty {
            хранилище.set(метка, forKey: ключМетки)
        } else {
            хранилище.removeObject(forKey: ключМетки)
        }
        хранилище.set(Date().timeIntervalSince1970, forKey: ключКогда)
        /* Пока ждали ответ, ключ могли выключить — тогда правила сервера не ставим. */
        guard РубильникиНовинок.сезонСервера else { return }
        СезонДляВас.поставитьСервера(ответ.правила, гео: ответ.гео)
    }

    /// «ММ-ДД» → месяц × 100 + число; не дата — nil.
    nonisolated static func день(_ строка: String) -> Int? {
        let части: [String] = строка.split(separator: "-").map { (кусок: Substring) -> String in String(кусок) }
        guard части.count == 2, let месяц = Int(части[0]), let число = Int(части[1]),
              (1...12).contains(месяц), (1...31).contains(число) else { return nil }
        return месяц * 100 + число
    }

    /// Ответ §4.1: только ok true; правил не больше 40, разделов у правила — 20; ничего годного — nil.
    nonisolated static func разобрать(_ данные: Data) -> Ответ? {
        guard let корень = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any],
              (корень["ok"] as? Bool) == true,
              let сырые = корень["rules"] as? [[String: Any]] else { return nil }
        var правила: [ПравилоСезонаДляВас] = []
        for сырое in сырые.prefix(40) {
            guard let ключ = сырое["key"] as? String, !ключ.isEmpty,
                  let с = день((сырое["from"] as? String) ?? ""), let по = день((сырое["to"] as? String) ?? "")
            else { continue }
            let вес: Int = (сырое["w"] as? NSNumber)?.intValue ?? 1
            let разделы: [String] = Array(((сырое["cats"] as? [String]) ?? []).prefix(20))
            guard !разделы.isEmpty else { continue }
            var сезоныШин: Set<String> = []
            let стандарт: String = (сырое["std"] as? String) ?? ""
            if стандарт.hasPrefix("tyre_season:") {
                let значения: String = String(стандарт.dropFirst("tyre_season:".count))
                for значение in значения.split(separator: ",") {
                    let чистое: String = значение.trimmingCharacters(in: .whitespaces)
                    if !чистое.isEmpty { сезоныШин.insert(чистое) }
                }
            }
            правила.append(ПравилоСезонаДляВас(String(ключ.prefix(40)), с: с, по: по, вес: вес, разделы: разделы,
                                               сезоныШин: сезоныШин))
        }
        guard !правила.isEmpty else { return nil }
        var гео: [String: [String: [Int]]] = [:]
        if let города = корень["geo"] as? [String: Any] {
            for (город, сырое) in города.prefix(40) {
                guard let своё = сырое as? [String: Any] else { continue }
                var даты: [String: [Int]] = [:]
                for (ключ, пара) in своё {
                    guard let границы = пара as? [String: Any],
                          let с = день((границы["from"] as? String) ?? ""),
                          let по = день((границы["to"] as? String) ?? "") else { continue }
                    даты[ключ] = [с, по]
                }
                if !даты.isEmpty { гео[город] = даты }
            }
        }
        return Ответ(правила: правила, гео: гео)
    }
}
