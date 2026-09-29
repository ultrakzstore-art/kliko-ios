import UIKit
import UserNotifications

/// APNs: регистрируемся (разрешение спрашивает РазрешениеПушей после входа), отдаём токен в WebBridge (он зальёт его
/// в веб-сессию → api/push_register.php привяжет к юзеру). По тапу на пуш открываем нужный
/// экран внутри PWA (deep-link). Категории (чат / подписка на объявление / новости-акции)
/// различает сервер полем "url" в payload — клиент просто ведёт туда.
/// Точка входа приложения (1.6). Раньше ею был SwiftUI App (KlikoApp.swift) с WindowGroup; окно теперь создаёт
/// SceneDelegate, чтобы корневым контроллером стал KlikoHostingController — он решает, светлые часы или тёмные.
@main
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Сцена окна — SceneDelegate (то же имя «Default», что в UIApplicationSceneManifest в project.yml).
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let конфиг = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        конфиг.delegateClass = SceneDelegate.self
        return конфиг
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Этап 12: обработчик фоновой проверки сохранённых поисков — строго до конца запуска, иначе iOS роняет
        // приложение при первом же фоновом запуске задания.
        ПроверкаПоисков.зарегистрировать()
        // Покупки App Store (StoreKit 2): слушатель Transaction.updates — с самого запуска, чтобы продления PRO, одобренные
        // «Попросить купить» и незакрытые покупки дошли до сайта. Выключен Config.цифровыеПокупки — StoreKit не трогаем.
        if Config.цифровыеПокупки {
            Task { @MainActor in ПокупкиApple.shared.запустить() }
        }
        /* Окно разрешения — после входа (РазрешениеПушей.послеВхода); здесь только регистрация, если уже разрешено. */
        РазрешениеПушей.приЗапуске()
        // Холодный старт по тапу на уведомление.
        if let notif = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handlePayload(notif)
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in WebBridge.shared.apnsToken = token }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs register failed: \(error.localizedDescription)")
        #endif
    }

    // Пуш пришёл, когда приложение открыто — всё равно показываем баннер.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        /* Список «Чата» и число непрочитанных — заново сразу: пуш о сообщении пришёл раньше, чем опрос (12 с) его увидит. */
        NotificationCenter.default.post(name: .klikoПушПришёл, object: nil)
        сделкаИзПуша(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    // Тап по уведомлению → deep-link внутрь PWA.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        сделкаИзПуша(info)
        // Этап 12: своё локальное уведомление о новых по сохранённому поиску узнаём по метке в userInfo и ведём в
        // ленту с этим поиском. У пушей сайта метки нет — они, как раньше, идут по "url".
        if let искомое = ПроверкаПоисков.искомое(из: info) {
            /* Этап 36: у подписки сайта — и её город. */
            let город = ПроверкаПоисков.город(из: info)
            Task { @MainActor in ПроверкаПоисков.открыть(искомое, город: город) }
        } else if let номер = СнижениеЦены.номер(из: info) {
            // Этап 21: уведомление о снижении цены в избранном — та же метка, своё значение; ведёт в нативную карточку.
            Task { @MainActor in СнижениеЦены.открыть(номер) }
        } else {
            handlePayload(info)
        }
        completionHandler()
    }

    /// Пуш о сделке — сделка могла закрыться: её объявление перечитают экраны (DealListingBack.swift).
    private func сделкаИзПуша(_ info: [AnyHashable: Any]) {
        let тип = (info["type"] as? String) ?? ""
        let сделка = info["deal_id"].map { "\($0)" } ?? ""
        let сделкаEDS = info["eds_id"].map { "\($0)" } ?? ""
        guard !сделка.isEmpty || !сделкаEDS.isEmpty else { return }
        Task { @MainActor in ОбъявлениеПослеСделки.пуш(тип: тип, сделка: сделка, сделкаEDS: сделкаEDS) }
    }

    /// payload: {"aps":{...}, "url":"/cabinet.php?s=messages"} (или полный https-URL).
    private func handlePayload(_ info: [AnyHashable: Any]) {
        guard let url = info["url"] as? String, !url.isEmpty else { return }
        Task { @MainActor in WebBridge.shared.openPath(url) }
    }
}

extension Notification.Name {
    /// Пуш пришёл, пока приложение открыто (willPresent): вкладки перечитывают список «Чата» и число непрочитанных.
    static let klikoПушПришёл = Notification.Name("kliko.push.willPresent")
}
