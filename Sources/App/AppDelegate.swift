import UIKit
import UserNotifications

/// APNs: спрашиваем разрешение, регистрируемся, отдаём токен в WebBridge (он зальёт его
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
        requestPushAuthorization()
        // Холодный старт по тапу на уведомление.
        if let notif = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handlePayload(notif)
        }
        return true
    }

    /// Разрешение на пуши (первый запуск). Разрешили → регистрируемся в APNs.
    func requestPushAuthorization() {
        #if DEBUG
        /* Съёмка экранов в CI (этап 23): системное окно разрешения закрывало бы ленту на снимке. */
        if UserDefaults.standard.bool(forKey: "klikoNoPushPrompt") { return }
        #endif
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
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
        completionHandler([.banner, .sound, .badge])
    }

    // Тап по уведомлению → deep-link внутрь PWA.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
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

    /// payload: {"aps":{...}, "url":"/cabinet.php?s=messages"} (или полный https-URL).
    private func handlePayload(_ info: [AnyHashable: Any]) {
        guard let url = info["url"] as? String, !url.isEmpty else { return }
        Task { @MainActor in WebBridge.shared.openPath(url) }
    }
}
