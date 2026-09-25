import BackgroundTasks
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
        // Сборщик крутится, пока приложение на экране; в фоне — только когда iOS разбудит.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.start()
            case .background: model.stop()
            default: break
            }
        }
    }
}

/// Уведомления (показываем и при открытом приложении, тап — объявление на OLX) и фоновое обновление.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Регистрировать обработчик обязательно до конца запуска.
        for id in [AppModel.refreshTaskId, AppModel.processingTaskId] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                Task { @MainActor in AppModel.shared.handleBackgroundTask(task) }
            }
        }
        Task { @MainActor in await AppModel.shared.requestNotifications() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await AppModel.shared.didReceiveDeviceToken(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in AppModel.shared.error = "Пуши не подключились: \(message)" }
    }

    // Тихий пуш-будильник от сервера: проверяем OLX с телефона, пока iOS даёт ~30 секунд.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { @MainActor in
            let found = await AppModel.shared.handleWakePush()
            completionHandler(found ? .newData : .noData)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let adId = info["ad_id"] as? Int
        let link = (info["url"] as? String).flatMap(URL.init(string:))
        Task { @MainActor in
            AppModel.shared.highlightedAdId = adId
            if let link { AppLink.open(link) }
            completionHandler()
        }
    }
}
