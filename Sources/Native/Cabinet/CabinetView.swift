import SwiftUI
import UIKit
import UserNotifications

/**
 НАТИВНЫЙ КАБИНЕТ — ЭТАП 9 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Вкладка «Кабинет» раньше сразу открывала /cabinet.php. Теперь это экран настроек приложения: вошёл ли человек на
 сайте, Face ID, уведомления, данные на телефоне, версия. Профиль, объявления, сделки и кошелёк остаются страницами
 сайта: строки «Открыть кабинет» и «Сообщения на сайте» открывают их в веб-обёртке, как остальные вкладки. Других
 адресов кабинета приложение не знает, поэтому и строк больше нет.

 🔴 ВЫХОДА ЗДЕСЬ НЕТ. Выход — на сайте: страница зовёт klikoLogout, сервер закрывает сессию и снимает привязку пушей
 этого телефона, а WebContainer по bye=1 стирает всё, что лежит на телефоне. Своя кнопка выхода закрыла бы только
 половину: сервер продолжал бы слать уведомления ушедшего. Поэтому строка «Выйти» ведёт в кабинет сайта.

 Имени человека в шапке нет: какие поля лежат в window.KlikoUser, приложение не знает (исходников сайта под рукой нет),
 а чужое поле, показанное как имя, хуже честного «Вы вошли».
 */
struct CabinetView: View {
    @ObservedObject private var мост = WebBridge.shared
    @ObservedObject private var замок = AppLock.shared
    @ObservedObject private var избранное = FavoritesStore.shared
    @ObservedObject private var недавние = RecentStore.shared
    @Environment(\.scenePhase) private var фаза

    /// Открыть страницу сайта в веб-обёртке — так же, как из остальных вкладок.
    let открыть: (URL) -> Void

    /// Вошёл ли человек на сайте. nil — не знаем: страница под слоем ещё грузится или не ответила.
    @State private var вошёл: Bool? = nil
    /// Загруженная страница уже ответила хоть раз — дальше вместо колеса честное «не удалось проверить».
    @State private var проверили = false
    @State private var уведомления: UNAuthorizationStatus? = nil
    @State private var кэшБайт = 0
    /// Переключатель защиты входа — своё значение, а не прямо AppLock.enabled: пока система спрашивает Face ID, он
    /// стоит в новом положении, а не прыгает назад; не подтвердили — возвращаем.
    @State private var защита = false
    @State private var проверяемЗамок = false
    /// Что умеет телефон (AppLock.kind): faceID / touchID / opticID / passcode / none. Спрашиваем при показе, а не в
    /// body: body пересчитывается на каждый шаг загрузки страницы (WebBridge.progress), а LAContext не бесплатен.
    @State private var способВхода = "passcode"
    @State private var ошибкаЗамка: String? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        List {
            шапка
            разделСайта
            разделБезопасности
            разделУведомлений
            /* Этап 12: сохранённые поиски — рядом с уведомлениями: без них проверка молчит, и видно это здесь же. */
            if Config.сохранённыеПоиски { РазделСохранённыхПоисков(уведомления: уведомления) }
            разделДанных
            разделОПриложении
            if вошёл == true { разделВыхода }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(CabinetText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await освежить() }
        /* Вход меняется на сайте, уведомления — в Настройках iPhone: перечитываем при каждом показе вкладки, при
           первой загрузке страницы, при возврате с сайта и из Настроек. */
        .task { await освежить() }
        .onAppear {
            защита = замок.enabled
            способВхода = замок.kind()
        }
        .onChange(of: замок.enabled) { _, стало in защита = стало }
        .onChange(of: защита) { _, хочет in переключитьЗащиту(хочет) }
        .onChange(of: мост.isLoaded) { _, загружена in
            if загружена { Task { await освежить() } }
        }
        .onChange(of: мост.лентаВидна) { _, видна in
            if видна { Task { await освежить() } }
        }
        .onChange(of: фаза) { _, стала in
            if стала == .active { Task { await освежить() } }
        }
    }

    // MARK: - Шапка: вошёл или нет

    /// Страница ещё не ответила, вошёл ли человек, — колесо вместо «не удалось». Сайт не загрузился вовсе (нет
    /// связи) — ждать нечего.
    private var ждёмСайт: Bool { вошёл == nil && !проверили && !мост.loadFailed }

    private var шапка: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    if ждёмСайт {
                        ProgressView()
                    } else {
                        Image(systemName: вошёл == true ? "person.crop.circle.fill" : "person.crop.circle")
                            .font(.system(size: 44))
                            .foregroundStyle(вошёл == true ? Theme.green2 : Color.secondary)
                    }
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(заголовокШапки)
                        .font(.headline)
                    Text(подписьШапки)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var заголовокШапки: String {
        if let известно = вошёл { return CabinetText.т(известно ? "signed_in" : "signed_out") }
        return CabinetText.т(ждёмСайт ? "checking" : "unknown")
    }

    private var подписьШапки: String {
        if let известно = вошёл { return CabinetText.т(известно ? "signed_in_sub" : "signed_out_sub") }
        return CabinetText.т(ждёмСайт ? "checking_sub" : "unknown_sub")
    }

    // MARK: - Кабинет на сайте

    private var разделСайта: some View {
        Section {
            if вошёл == false {
                строкаСайта(CabinetText.т("login"), значок: "person.crop.circle.badge.plus", путь: "/cabinet.php")
            } else {
                строкаСайта(CabinetText.т("open_cabinet"), значок: "person.text.rectangle", путь: "/cabinet.php")
                строкаСайта(CabinetText.т("site_messages"), значок: "bubble.left.and.bubble.right",
                            путь: "/cabinet.php?s=messages")
            }
        } header: {
            Text(CabinetText.т("site"))
        } footer: {
            Text(CabinetText.т("site_footer"))
        }
    }

    /// Строка, которая открывает страницу сайта, — со стрелкой «наружу»: видно, что дальше сайт, а не экран приложения.
    private func строкаСайта(_ название: String, значок: String, путь: String) -> some View {
        Button {
            if let u = Config.url(путь) { открыть(u) }
        } label: {
            HStack {
                Label {
                    Text(название).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: значок).foregroundStyle(Theme.green2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Безопасность: вход по Face ID (AppLock)

    private var разделБезопасности: some View {
        Section {
            Toggle(isOn: $защита) {
                Label {
                    Text(String(format: CabinetText.т("lock_toggle"), AppLock.имяСпособа(способВхода)))
                } icon: {
                    Image(systemName: значокЗамка).foregroundStyle(Theme.green2)
                }
            }
            .tint(Theme.green2)
            .disabled(проверяемЗамок || способВхода == "none")
        } header: {
            Text(CabinetText.т("security"))
        } footer: {
            Text(подписьЗамка)
        }
    }

    private var значокЗамка: String {
        switch способВхода {
        case "faceID":  return "faceid"
        case "touchID": return "touchid"
        case "opticID": return "opticid"
        default:        return "lock.fill"
        }
    }

    private var подписьЗамка: String {
        if let текст = ошибкаЗамка { return текст }
        return CabinetText.т(способВхода == "none" ? "lock_none" : "lock_footer")
    }

    /// Человек тронул переключатель — проверка владельца системой, как у моста klikoLock на сайте (AppLock.setEnabled).
    /// Не подтвердил — переключатель назад; отменил сам — без упрёка, просто назад.
    private func переключитьЗащиту(_ хочет: Bool) {
        guard хочет != замок.enabled, !проверяемЗамок else { return }
        проверяемЗамок = true
        ошибкаЗамка = nil
        замок.setEnabled(хочет) { прошло, код in
            проверяемЗамок = false
            guard !прошло else { return }
            защита = замок.enabled
            if код != "cancel" {
                ошибкаЗамка = CabinetText.т(код == "unavailable" ? "lock_unavailable" : "lock_failed")
            }
        }
    }

    // MARK: - Уведомления

    private var разделУведомлений: some View {
        Section {
            LabeledContent(CabinetText.т("notif_row"), value: названиеСтатуса)
            /* Окно разрешения система показывает только до первого ответа; потом — лишь Настройки iPhone. */
            if уведомления == .notDetermined {
                Button(CabinetText.т("notif_ask")) {
                    Task {
                        await ДанныеТелефона.попроситьУведомления()
                        await освежить()
                    }
                }
            }
            Button(CabinetText.т("notif_settings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
        } header: {
            Text(CabinetText.т("notifications"))
        } footer: {
            if уведомления == .denied { Text(CabinetText.т("notif_off_footer")) }
        }
    }

    private var названиеСтатуса: String {
        guard let статус = уведомления else { return "…" }
        switch статус {
        case .authorized, .ephemeral: return CabinetText.т("notif_on")
        case .provisional:            return CabinetText.т("notif_quiet")
        case .denied:                 return CabinetText.т("notif_off")
        case .notDetermined:          return CabinetText.т("notif_unknown")
        @unknown default:             return CabinetText.т("notif_unknown")
        }
    }

    // MARK: - Данные на телефоне

    private var разделДанных: some View {
        Section {
            СтрокаОчистки(CabinetText.т("clear_cache"), значок: "internaldrive",
                          подпись: кэшБайт > 0 ? ДанныеТелефона.размер(кэшБайт) : nil,
                          вопрос: CabinetText.т("cache_q"), пояснение: CabinetText.т("cache_msg")) {
                Task {
                    await ДанныеТелефона.очиститьКэш()
                    кэшБайт = ДанныеТелефона.кэшБайт
                }
            }
            if Config.избранное {
                СтрокаОчистки(CabinetText.т("clear_favorites"), значок: "heart",
                              подпись: число(избранное.товары.count),
                              вопрос: CabinetText.т("favorites_q"), пояснение: CabinetText.т("favorites_msg"),
                              доступно: !избранное.товары.isEmpty) {
                    избранное.стереть()
                }
            }
            if Config.недавние {
                СтрокаОчистки(CabinetText.т("clear_viewed"), значок: "clock.arrow.circlepath",
                              подпись: число(недавние.товары.count),
                              вопрос: CabinetText.т("viewed_q"), пояснение: CabinetText.т("viewed_msg"),
                              доступно: !недавние.товары.isEmpty) {
                    недавние.очиститьПросмотры()
                }
                СтрокаОчистки(CabinetText.т("clear_search"), значок: "magnifyingglass",
                              подпись: число(недавние.запросы.count),
                              вопрос: CabinetText.т("search_q"), пояснение: CabinetText.т("search_msg"),
                              доступно: !недавние.запросы.isEmpty) {
                    недавние.очиститьЗапросы()
                }
            }
        } header: {
            Text(CabinetText.т("data"))
        } footer: {
            if Config.избранное || Config.недавние { Text(CabinetText.т("data_footer")) }
        }
    }

    private func число(_ сколько: Int) -> String? {
        сколько > 0 ? String(сколько) : nil
    }

    // MARK: - О приложении и выход

    private var разделОПриложении: some View {
        Section {
            LabeledContent(CabinetText.т("version"), value: Self.изПлиста("CFBundleShortVersionString"))
            LabeledContent(CabinetText.т("build"), value: Self.изПлиста("CFBundleVersion"))
        } header: {
            Text(CabinetText.т("about"))
        }
    }

    /// Версия и номер сборки — из Info.plist: туда их подставляет сборка (MARKETING_VERSION, CURRENT_PROJECT_VERSION).
    private static func изПлиста(_ ключ: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: ключ) as? String) ?? "—"
    }

    /// Не кнопка выхода, а дорога к нему: выходят на сайте (см. шапку файла).
    private var разделВыхода: some View {
        Section {
            Button {
                if let u = Config.url("/cabinet.php") { открыть(u) }
            } label: {
                Label(CabinetText.т("logout_row"), systemImage: "rectangle.portrait.and.arrow.right")
            }
        } footer: {
            Text(CabinetText.т("logout_footer"))
        }
    }

    // MARK: - Обновление

    /// Состояние экрана заново: вход — у загруженной страницы (SiteSession), уведомления — у системы, кэш — у URLCache.
    private func освежить() async {
        let сессия = await SiteSession.состояние()
        /* nil — страница не ответила (грузится или переходит). Известное раньше не забываем: мигать «не удалось» на
           каждом переходе хуже прошлого состояния, а выход сайт всё равно заканчивает загрузкой страницы с bye=1. */
        if let известно = сессия.вошёл { вошёл = известно }
        if мост.isLoaded { проверили = true }
        способВхода = замок.kind()          // код-пароль или Face ID могли настроить в Настройках, пока нас не было
        уведомления = await ДанныеТелефона.статусУведомлений()
        кэшБайт = ДанныеТелефона.кэшБайт
    }
}

/// Строка «Очистить …» с подтверждением: стирается сразу и насовсем, поэтому сначала спрашиваем.
private struct СтрокаОчистки: View {
    let название: String
    let значок: String
    /// Справа серым: сколько записей или места. nil — ничего.
    let подпись: String?
    let вопрос: String
    let пояснение: String
    let доступно: Bool
    let очистить: () -> Void
    @State private var спросить = false

    init(_ название: String, значок: String, подпись: String?, вопрос: String, пояснение: String,
         доступно: Bool = true, очистить: @escaping () -> Void) {
        self.название = название
        self.значок = значок
        self.подпись = подпись
        self.вопрос = вопрос
        self.пояснение = пояснение
        self.доступно = доступно
        self.очистить = очистить
    }

    var body: some View {
        Button(role: .destructive) {
            спросить = true
        } label: {
            HStack {
                Label(название, systemImage: значок)
                Spacer(minLength: 8)
                if let текст = подпись {
                    Text(текст)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!доступно)
        .confirmationDialog(вопрос, isPresented: $спросить, titleVisibility: .visible) {
            Button(CabinetText.т("clear"), role: .destructive, action: очистить)
            Button(CabinetText.т("cancel"), role: .cancel) {}
        } message: {
            Text(пояснение)
        }
    }
}

/**
 Данные приложения на телефоне для кабинета: общий кэш запросов и статус уведомлений.

 Кэш — URLCache.shared: фото ленты (AsyncImage) и ответы API, до 256 МБ на диске (WebContainer.большойКэш). Кэш
 WebKit (страницы сайта) не трогаем: он лежит рядом с куками сессии и стирается при выходе целиком.
 */
enum ДанныеТелефона {
    /// Сколько кэш занимает на диске, байт.
    static var кэшБайт: Int { URLCache.shared.currentDiskUsage }

    /// «42,3 МБ» — на языке телефона.
    static func размер(_ байт: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(байт), countStyle: .file)
    }

    /// Чистка сотен мегабайт — не на главной нити, чтобы экран не замирал.
    static func очиститьКэш() async {
        await Task.detached(priority: .utility) {
            URLCache.shared.removeAllCachedResponses()
        }.value
    }

    static func статусУведомлений() async -> UNAuthorizationStatus {
        await withCheckedContinuation { продолжение in
            UNUserNotificationCenter.current().getNotificationSettings { настройки in
                продолжение.resume(returning: настройки.authorizationStatus)
            }
        }
    }

    /// Тот же запрос, что при первом запуске (AppDelegate): разрешили — регистрируемся в APNs, токен уйдёт в веб-сессию.
    static func попроситьУведомления() async {
        let центр = UNUserNotificationCenter.current()
        let разрешили = (try? await центр.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard разрешили else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }
}
