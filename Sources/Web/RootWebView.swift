import SwiftUI

/// Корень приложения: PWA в WebView + прелоадер + экран «нет связи».
///
/// Раскладка:
///  • Адаптивная подложка (systemBackground) на весь экран — видна только до первой
///    отрисовки страницы; авто-тема (тёмная/светлая).
///  • WebView ВО ВЕСЬ ЭКРАН: под Dynamic Island / вырезом и до самого низа (см. ниже).
struct RootWebView: View {
    @StateObject private var bridge = WebBridge.shared
    @ObservedObject private var lock = AppLock.shared   // вход по Face ID: экран замка поверх всего (AppLock)
    @State private var minElapsed = false     // минимум показа сплэша, чтобы лого не мелькал

    /* ЛЕНТА ВМЕСТО ПУСТОГО ОЖИДАНИЯ (владелец 24.09.2026: «когда интернет кончается — очень долго работает»).
       Снимок читаем синхронно при создании экрана: файл крошечный, а нужен он на ПЕРВОМ кадре — уйдя в фон,
       мы бы сначала показали сплэш и только потом подменили его лентой, и это мигание было бы хуже ожидания. */
    @State private var снимок: FeedSnapshot? = FeedStore.прочитать()

    /* Минимум в 1,6 с придуман для сплэша: логотип не должен мелькать. Ленте он не нужен — это содержимое, а
       не заставка, и держать её лишнюю секунду поверх готовой страницы значит самому же замедлять запуск.
       Поэтому со снимком ждём ровно столько, сколько грузится страница. */
    private var showSplash: Bool { !(bridge.isLoaded && (minElapsed || снимок != nil)) }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()      // strip под статус-баром + низ, фикс., авто-тема

            WebContainer(bridge: bridge)
                /* ВО ВЕСЬ ЭКРАН (владелец 14.09.2026: «почему не полный экран на версии 1.2?»).
                   Сайт с 12.09 сам отступает от выреза и домашней полосы: viewport-fit=cover,
                   env(safe-area-inset-*) у шапок и нижних панелей, размытая вуаль под Dynamic
                   Island (inc/viewport.php, inc/pwa.php). А обёртка держала верхний отступ и
                   поднимала низ на 5px — поэтому страница начиналась под вырезом, в рамке.
                   Игнорируем только «рамку» устройства (.container), клавиатуру — НЕТ: иначе окно
                   перестало бы сжиматься под клавиатуру, и поле ввода чата ушло бы под неё. */
                .ignoresSafeArea(.container)

            if bridge.loadFailed {
                OfflineView { bridge.retry() }
                    .transition(.opacity)
            } else if showSplash {
                if let снимок {
                    /* Нажали карточку — говорим странице, куда идти, а превью держим до её готовности: убрать
                       его сразу значит показать белый экран вместо объявления. */
                    FeedPreview(снимок: снимок) { адрес in bridge.pendingURL = адрес }
                        .transition(.opacity)
                } else {
                    SplashView()
                        .transition(.opacity)
                }
            }

            /* Защита входа включена: заперто или приложение неактивно — содержимое закрыто (переключатель приложений
               не покажет переписку). Страница под замком продолжает жить: сессия и пуши не трогаются. */
            if lock.enabled && (lock.locked || lock.cover) {
                LockView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.locked)
        .animation(.easeInOut(duration: 0.15), value: lock.cover)
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        // Сплэш ушёл — строка состояния начинает следовать странице (SceneDelegate, KlikoHostingController).
        .onAppear { bridge.splashDone = !showSplash }
        .onChange(of: showSplash) { _, виден in bridge.splashDone = !виден }
        .animation(.easeInOut(duration: 0.25), value: bridge.loadFailed)
        .task {
            // Минимум ~1.6с показа прелоадера (логотип + подсказка успевают появиться).
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            minElapsed = true
        }
    }
}
