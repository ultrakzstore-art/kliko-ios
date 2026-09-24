import SwiftUI
import UIKit
import UserNotifications

@main
struct OLXWatchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.watchAccent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshAll() } }
        }
    }
}

/// Пуши: регистрация токена и открытие объявления по тапу на уведомление.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            if AppModel.shared.configured { await AppModel.shared.requestPushPermission() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await AppModel.shared.didReceiveDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in AppModel.shared.error = "Пуши не подключились: \(error.localizedDescription)" }
    }

    // Пуш, пришедший при открытом приложении, тоже показываем — и обновляем ленту.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in await AppModel.shared.refreshFeed() }
        completionHandler([.banner, .list, .sound])
    }

    // Тап по пушу — сразу объявление на OLX (в приложении OLX, если стоит, иначе в Safari).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let adId = info["ad_id"] as? Int
        let link = (info["url"] as? String).flatMap(URL.init(string:))
        Task { @MainActor in
            AppModel.shared.highlightedAdId = adId
            await AppModel.shared.refreshFeed()
            if let link { _ = await UIApplication.shared.open(link, options: [:]) }
            completionHandler()
        }
    }
}
