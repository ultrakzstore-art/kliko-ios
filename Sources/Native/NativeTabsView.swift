import SwiftUI

/**
 НИЖНИЕ ВКЛАДКИ — ЭТАП 4 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующий этап» → «Нижние вкладки»).

 Лента и Сообщения — настоящие вкладки: нативные экраны со своей навигацией, каждая помнит, где человек остановился.
 Разместить и Кабинет — пока страницы сайта: нажатие открывает страницу в веб-обёртке, а выбранной остаётся прежняя
 вкладка. Вернулся человек со страницы на главную — он снова в ленте (RootWebView прячет и показывает этот слой).

 🔴 НА СТРАНИЦАХ САЙТА ПАНЕЛИ НЕТ. Внутри страницы у сайта своя нижняя навигация; вторая, нативная, над ней — это
 две панели друг над другом и половина экрана под кнопками. Поэтому вкладки живут только на нативных экранах, а
 на сайте человек ходит его навигацией, и «Главная» сайта возвращает его сюда.

 Счётчик на «Сообщениях» — непрочитанные из dm.php list: при показе вкладок, при возврате со страницы сайта и раз в
 минуту, пока приложение на экране.
 */
struct NativeTabsView: View {
    enum Вкладка: Hashable { case лента, сообщения, разместить, кабинет }

    @ObservedObject private var мост = WebBridge.shared
    @StateObject private var чаты = ChatListModel()
    @State private var вкладка: Вкладка = .лента
    @Environment(\.scenePhase) private var фаза

    let открыть: (URL) -> Void
    let открытьСайт: () -> Void

    var body: some View {
        TabView(selection: $вкладка) {
            NativeFeedView(открыть: открыть, открытьСайт: открытьСайт)
                .tabItem { Label(TabsText.т("feed"), systemImage: "square.grid.2x2") }
                .tag(Вкладка.лента)

            if Config.нативныйЧат {
                NavigationStack {
                    ChatListView(модель: чаты, открыть: открыть)
                        .чатМаршруты(открыть: открыть)
                }
                .tabItem { Label(TabsText.т("messages"), systemImage: "bubble.left.and.bubble.right") }
                .badge(чаты.непрочитано)
                .tag(Вкладка.сообщения)
            }

            if Config.адресПодачи != nil {
                Color.clear
                    .tabItem { Label(TabsText.т("post"), systemImage: "plus.circle") }
                    .tag(Вкладка.разместить)
            }

            Color.clear
                .tabItem { Label(TabsText.т("cabinet"), systemImage: "person.crop.circle") }
                .tag(Вкладка.кабинет)
        }
        .tint(Theme.green)
        /* Разместить и Кабинет — не экраны, а переходы на сайт: открываем страницу и оставляем выбранной прежнюю
           вкладку, чтобы по возвращении человек был там, где был. */
        .onChange(of: вкладка) { было, стало in
            switch стало {
            case .разместить:
                вкладка = было
                if let путь = Config.адресПодачи, let u = Config.url(путь) { открыть(u) }
            case .кабинет:
                вкладка = было
                if let u = Config.url("/cabinet.php") { открыть(u) }
            default:
                break
            }
        }
        /* Вернулся со страницы сайта на главную — в ленту: «Главная» сайта ведёт на главную, а главная здесь — лента. */
        .onChange(of: мост.лентаВидна) { _, видна in
            guard видна else { return }
            вкладка = .лента
            Task { await обновитьСчётчик() }
        }
        .task {
            guard Config.нативныйЧат else { return }
            while !Task.isCancelled {
                await обновитьСчётчик()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    /// Непрочитанные — только когда вкладки на экране и приложение активно: опрос из фона и из-под страницы сайта
    /// тратил бы батарею впустую.
    private func обновитьСчётчик() async {
        guard Config.нативныйЧат, мост.лентаВидна, фаза == .active else { return }
        await чаты.загрузить()
    }
}

/// Подписи вкладок на языке телефона (kk/ru/en/ar).
enum TabsText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["feed": "Лента", "messages": "Сообщения", "post": "Разместить", "cabinet": "Кабинет"],
        "kk": ["feed": "Лента", "messages": "Хабарламалар", "post": "Жариялау", "cabinet": "Кабинет"],
        "en": ["feed": "Feed", "messages": "Messages", "post": "Sell", "cabinet": "Account"],
        "ar": ["feed": "الإعلانات", "messages": "الرسائل", "post": "انشر", "cabinet": "الحساب"]
    ]
}
