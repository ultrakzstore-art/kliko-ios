import UIKit

/**
 БЫСТРЫЕ ДЕЙСТВИЯ С ИКОНКИ — ЭТАП 10 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Долгое нажатие на иконку Kliko: «Поиск» (лента с полем поиска наготове), «Сообщения», «Избранное». Нажатие приходит
 в SceneDelegate (на холодном старте — в connectionOptions.shortcutItem) и идёт через роутер ссылок этапа 8:
 WebBridge.открытьЭкран ставит NativeRouter.цель, вкладки её принимают.

 Пункты задаём из кода при каждом подключении сцены, а не в Info.plist (project.yml): подписи — на языке телефона
 тем же способом, что остальные тексты, а выключенный рубильник убирает пункты с иконки уже на следующем запуске.
 */
@MainActor
enum БыстрыеДействия {
    private static let поиск = "kz.kliko.app.search"
    private static let сообщения = "kz.kliko.app.messages"
    private static let избранное = "kz.kliko.app.favorites"

    /// Меню иконки заново. Без вкладок принимать пункты некому — меню пустое, прежние пункты с иконки уходят.
    static func обновить() {
        guard Config.быстрыеДействия, Config.нативнаяЛента, Config.нижниеВкладки else {
            UIApplication.shared.shortcutItems = []
            return
        }
        var пункты = [
            пункт(Self.поиск, SystemText.т("search"), значок: "magnifyingglass"),
            пункт(Self.сообщения, SystemText.т("messages"), значок: "bubble.left.and.bubble.right")
        ]
        if Config.избранное {
            пункты.append(пункт(Self.избранное, SystemText.т("favorites"), значок: "heart"))
        }
        UIApplication.shared.shortcutItems = пункты
    }

    /// Нажали пункт. Вкладок сейчас нет (лента сайта вместо нашей) — запасная страница сайта: главная с её поиском,
    /// переписка на сайте; у избранного страницы нет — просто открываем приложение. false — пункт не наш.
    @discardableResult
    static func выполнить(_ нажатый: UIApplicationShortcutItem) -> Bool {
        let мост = WebBridge.shared
        switch нажатый.type {
        case Self.поиск:
            мост.открытьЭкран(.поиск, запасной: Config.apiBase)
        case Self.сообщения:
            мост.открытьЭкран(.сообщения, запасной: Config.url("/cabinet.php?s=messages"))
        case Self.избранное:
            мост.открытьЭкран(.избранное, запасной: nil)
        default:
            return false
        }
        return true
    }

    private static func пункт(_ тип: String, _ название: String, значок: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: тип, localizedTitle: название, localizedSubtitle: nil,
                                  icon: UIApplicationShortcutIcon(systemImageName: значок), userInfo: nil)
    }
}
