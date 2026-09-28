import UIKit
import UserNotifications

/**
 РАЗРЕШЕНИЕ НА ПУШИ — ПО ДЕЛУ, А НЕ ПРИ ЗАПУСКЕ. App Review просит спрашивать в контексте: гостю уведомлять не о чем
 (сообщения, сделки, заявки — всё после входа). Поэтому при запуске окна нет: уже разрешено — только регистрация в APNs
 (токен уходит в веб-сессию как раньше, через WebBridge.apnsToken). Системное окно — после входа (СессияПриложения)
 или по кнопке страницы и кабинета (klikoAskPush, ДанныеТелефона.попроситьУведомления).
 */
enum РазрешениеПушей {
    /// Запуск: окна нет; разрешено раньше — регистрируемся, токен дойдёт до сайта.
    static func приЗапуске() {
        UNUserNotificationCenter.current().getNotificationSettings { настройки in
            guard разрешено(настройки.authorizationStatus) else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    /// Вошёл: окно, пока система ещё может его показать; разрешено — просто регистрация. Отказ — не настаиваем.
    static func послеВхода() {
        #if DEBUG
        /* Съёмка экранов в CI (этап 23): системное окно закрывало бы снимок. */
        if UserDefaults.standard.bool(forKey: "klikoNoPushPrompt") { return }
        #endif
        UNUserNotificationCenter.current().getNotificationSettings { настройки in
            let статус = настройки.authorizationStatus
            if разрешено(статус) {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                return
            }
            guard статус == .notDetermined else { return }
            /* Секунда — лист входа успевает закрыться, окно встаёт уже над витриной. */
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { да, _ in
                    guard да else { return }
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            }
        }
    }

    private static func разрешено(_ статус: UNAuthorizationStatus) -> Bool {
        switch статус {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
