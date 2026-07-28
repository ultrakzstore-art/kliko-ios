import UIKit
import UserNotifications

/// APNs: спрашиваем разрешение, регистрируемся, отдаём токен в WebBridge (он зальёт его
/// в веб-сессию → api/push_register.php привяжет к юзеру). По тапу на пуш открываем нужный
/// экран внутри PWA (deep-link). Категории (чат / подписка на объявление / новости-акции)
/// различает сервер полем "url" в payload — клиент просто ведёт туда.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        requestPushAuthorization()
        // Холодный старт по тапу на уведомление.
        if let notif = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handlePayload(notif)
        }
        return true
    }

    /// Разрешение на пуши (первый запуск). Разрешили → регистрируемся в APNs.
    func requestPushAuthorization() {
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
        handlePayload(response.notification.request.content.userInfo)
        completionHandler()
    }

    /// payload: {"aps":{...}, "url":"/cabinet.php?s=messages"} (или полный https-URL).
    private func handlePayload(_ info: [AnyHashable: Any]) {
        guard let url = info["url"] as? String, !url.isEmpty else { return }
        Task { @MainActor in WebBridge.shared.openPath(url) }
    }
}
