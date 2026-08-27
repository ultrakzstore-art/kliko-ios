import SwiftUI
import WebKit

/// Токен Live Activity сделки: адрес, по которому сервер дотягивается до плашки на
/// локскрине. `drop` — активность закрылась, адресата надо забыть.
/// Equatable, чтобы WebContainer не переотправлял один и тот же токен на каждой
/// перерисовке: fetch на каждый кадр SwiftUI — верный способ схватить рейт-лимит.
struct LiveToken: Equatable {
    let deal: String
    let token: String
    let drop: Bool
}

/// Общее состояние обёртки: статус загрузки, deep-link из пуша, APNs-токен.
/// Один на приложение (singleton) — к нему обращается и WebView, и AppDelegate (push).
@MainActor
final class WebBridge: ObservableObject {
    static let shared = WebBridge()

    @Published var isLoaded = false        // первая страница отрисована → прячем прелоадер
    @Published var loadFailed = false      // сеть недоступна → экран «нет связи» с «Повторить»
    @Published var apnsToken: String?      // токен устройства (ставит AppDelegate) → шлём в веб-сессию
    @Published var liveToken: LiveToken?   // токен плашки сделки (ставит DealActivityManager)
    @Published var pendingURL: URL?        // куда перейти по тапу на пуш (deep-link)

    weak var webView: WKWebView?

    /// Открыть путь/URL из пуша (тап по уведомлению чата/подписки/новости).
    func openPath(_ path: String) {
        let u = path.hasPrefix("http") ? URL(string: path)
                                       : URL(string: path, relativeTo: Config.apiBase)
        if let u { pendingURL = u }
    }

    /// Повторить загрузку после обрыва связи.
    func retry() {
        loadFailed = false
        isLoaded = false
        webView?.load(URLRequest(url: Config.apiBase))
    }
}
