import Foundation

/**
 СНИМОК ДЛЯ ВИДЖЕТА «Kliko» (общий для приложения и виджет-расширения).

 Приложение пишет его в общий контейнер App Group (group.kz.kliko.app), когда сверяет непрочитанные (ЗначокПриложения)
 и сделки (СделкиМодель.обновитьЗначок), и просит WidgetKit перерисовать виджет. Виджет только читает: своей сети у
 него нет, куки сессии живут в приложении.

 Нет App Group в профиле подписи (возможность не включена у App ID) — UserDefaults(suiteName:) вернёт пустой набор,
 виджет покажет «Откройте Kliko», приложение работает как раньше.
 */
struct СнимокВиджетаKliko: Codable, Equatable {
    /// Одна активная сделка — строка среднего виджета.
    struct Сделка: Codable, Equatable, Identifiable {
        var id: String
        var название: String
        /// Подпись статуса, как в «Моих сделках» («Деньги у Kliko»).
        var статус: String
        /// SF Symbol статуса.
        var символ: String
        /// "seller" / "buyer".
        var роль: String
        /// Доставка, если её отслеживают: «СДЭК · В пути»; пусто — нет.
        var доставка: String = ""
    }

    var вошёл: Bool = false
    var непрочитано: Int = 0
    var активных: Int = 0
    /// Первые незакрытые — не больше трёх.
    var сделки: [Сделка] = []
    var обновлено: Date = Date(timeIntervalSince1970: 0)
    /// Когда сделки сверены в последний раз (приложение решает, пора ли спросить снова).
    var сделкиСверены: Date = Date(timeIntervalSince1970: 0)

    static let группа = "group.kz.kliko.app"
    private static let ключ = "kliko.widget.snapshot.v1"

    static func прочитать() -> СнимокВиджетаKliko {
        guard let набор = UserDefaults(suiteName: группа), let данные = набор.data(forKey: ключ),
              let снимок = try? JSONDecoder().decode(СнимокВиджетаKliko.self, from: данные) else {
            return СнимокВиджетаKliko()
        }
        return снимок
    }

    /// true — записано и отличается от прежнего (тогда стоит перерисовать виджет).
    @discardableResult
    static func записать(_ снимок: СнимокВиджетаKliko) -> Bool {
        guard let набор = UserDefaults(suiteName: группа),
              let данные = try? JSONEncoder().encode(снимок) else { return false }
        if набор.data(forKey: ключ) == данные { return false }
        набор.set(данные, forKey: ключ)
        return true
    }

    /// Ссылки нажатий — их понимает Config.deepLink приложения (CabinetRouter).
    static let ссылкаСделок = URL(string: "https://kliko.kz/cabinet.php?go=deals")
    static let ссылкаСообщений = URL(string: "https://kliko.kz/cabinet.php?go=messages")
    static func ссылкаСделки(_ id: String) -> URL? {
        let номер = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return URL(string: "https://kliko.kz/cabinet.php?deal=" + номер)
    }
}
