import Foundation

/// Точка конфигурации. Меняй apiBase, если домен/стейдж другой.
enum Config {
    /// Базовый URL продакшена. Все запросы идут сюда (URLSession сам держит cookie-сессию).
    static let apiBase = URL(string: "https://kliko.kz")!

    /// Абсолютный URL для картинок/относительных путей из API.
    static func url(_ path: String) -> URL? {
        let p = path.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return nil }
        if p.hasPrefix("http://") || p.hasPrefix("https://") { return URL(string: p) }
        return URL(string: p, relativeTo: apiBase)
    }

    /// Своя схема приложения: kliko://open?u=<полный адрес страницы>. Регистрирует CFBundleURLTypes (project.yml).
    static let scheme = "kliko"

    /// Домены, которые нам разрешено открывать. www — на случай ссылки со старой визитки: сайт сам перебросит.
    private static let свои: Set<String> = ["kliko.kz", "www.kliko.kz"]

    /// Адрес нашего домена или nil.
    private static func свой(_ u: URL) -> URL? {
        guard let h = u.host?.lowercased(), свои.contains(h) else { return nil }
        guard let s = u.scheme?.lowercased(), s == "https" || s == "http" else { return nil }
        return u
    }

    /**
     Внешняя ссылка → страница, которую грузим в WebView.

     Приходят три вида:
       · универсальная ссылка (`applinks:kliko.kz`) — уже https нашего домена, iOS проверила домен за нас;
       · `widgetURL` плашки сделки — тоже https нашего домена;
       · `kliko://open?u=<адрес>` — кнопка «Открыть в приложении» на самом сайте.

     🔴 ПРОВЕРЯЕМ ДОМЕН, А НЕ ВЕРИМ НА СЛОВО. Схему kliko:// может вызвать кто угодно — страница в Safari,
     письмо, чужая программа. Без проверки вызов `kliko://open?u=https://чужой.сайт` открыл бы чужую страницу
     ВНУТРИ нашей обёртки, где живут куки сессии: чужой скрипт оказался бы на одном экране с кабинетом.
     Адрес не наш — не открываем ничего (nil), а не «на всякий случай главную»: молчание честнее подмены.
     */
    static func deepLink(_ u: URL) -> URL? {
        if let s = u.scheme?.lowercased(), s == "https" || s == "http" { return свой(u) }
        guard u.scheme?.lowercased() == scheme else { return nil }
        let части = URLComponents(url: u, resolvingAgainstBaseURL: false)
        guard let цель = части?.queryItems?.first(where: { $0.name == "u" })?.value, !цель.isEmpty else {
            return apiBase                      // kliko:// без адреса — просто «открой приложение»
        }
        guard let адрес = URL(string: цель) else { return nil }
        return свой(адрес)
    }
}
