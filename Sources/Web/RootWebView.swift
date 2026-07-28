import SwiftUI

/// Корень приложения: PWA в WebView + прелоадер + экран «нет связи».
///
/// Раскладка:
///  • Фиксированная адаптивная подложка (systemBackground) под статус-баром и внизу —
///    статус-бар выглядит «влитым», как в Яндекс.Такси; авто-тема (тёмная/светлая).
///  • WebView уважает верхний safe-area (инсет под монобровь — контент не лезет под вырез).
///  • Низ приподнят на 5px (padding.bottom 5) — контент не липнет к домашней полоске.
struct RootWebView: View {
    @StateObject private var bridge = WebBridge.shared
    @State private var minElapsed = false     // минимум показа сплэша, чтобы лого не мелькал

    // Сплэш держим, пока сайт не загрузился ИЛИ не прошёл минимум времени.
    private var showSplash: Bool { !(bridge.isLoaded && minElapsed) }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()      // strip под статус-баром + низ, фикс., авто-тема

            WebContainer(bridge: bridge)
                .padding(.bottom, 5)                         // низ +5px
                // верхний safe-area НЕ игнорируем → инсет под монобровь сохранён

            if bridge.loadFailed {
                OfflineView { bridge.retry() }
                    .transition(.opacity)
            } else if showSplash {
                SplashView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .animation(.easeInOut(duration: 0.25), value: bridge.loadFailed)
        .task {
            // Минимум ~1.6с показа прелоадера (логотип + подсказка успевают появиться).
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            minElapsed = true
        }
    }
}
