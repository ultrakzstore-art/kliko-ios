import SwiftUI

/// Kliko — нативная обёртка PWA (kliko.kz) в WKWebView.
/// Натив только там, где сайт не может: прелоадер с лого, пуши (APNs), безопасные зоны.
@main
struct KlikoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootWebView()
                .tint(Theme.green)
                // Тап по Live Activity сделки (widgetURL) → открыть нужный экран в PWA.
                .onOpenURL { url in WebBridge.shared.pendingURL = url }
        }
    }
}
