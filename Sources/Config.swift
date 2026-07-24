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
}
