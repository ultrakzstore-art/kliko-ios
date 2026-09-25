import SwiftUI
import UIKit

/**
 ТЕМА ОФОРМЛЕНИЯ — ЭТАП 15 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026).

 В кабинете выбирают «Системная», «Светлая» или «Тёмная». Выбор ставится ОКНУ (UIWindow.overrideUserInterfaceStyle,
 SceneDelegate), а не экранам по отдельности: от окна тему наследуют SwiftUI (colorScheme), системные окна поверх него
 (контакты, медиатека, «Поделиться») и WKWebView — у него своей темы нет (overrideUserInterfaceStyle = .unspecified в
 WebContainer), и страница получает prefers-color-scheme от окна. Модификатор .preferredColorScheme так не умеет: он
 перекрасил бы SwiftUI, а страницу сайта под слоем оставил бы в теме iPhone.

 ГДЕ ХРАНИТСЯ. UserDefaults, как защита входа (AppLock): это настройка телефона, а не аккаунта, — при выходе (bye=1) не
 стирается. Ничего о человеке в ней нет.

 🔴 СТРАНИЦА САЙТА МОЖЕТ ПЕРЕБИТЬ. Приложение отдаёт ей только prefers-color-scheme. Если сайт держит ещё и свою тему
 (data-theme, localStorage), страница покажет её — исходников сайта под рукой нет, проверить нельзя. Часы над страницей
 и так следуют её верху (мост klikoBars), поэтому строка состояния останется читаемой при любом раскладе.
 Экран запуска (UILaunchScreen) система рисует до нашего кода — он всегда в теме iPhone.
 */
enum ТемаОформления: String, CaseIterable, Identifiable {
    case системная = "system"
    case светлая = "light"
    case тёмная = "dark"

    var id: String { rawValue }

    /// Название на языке телефона: ключ — rawValue (AppearanceText).
    var название: String { AppearanceText.т(rawValue) }

    var значок: String {
        switch self {
        case .системная: return "circle.lefthalf.filled"
        case .светлая:   return "sun.max"
        case .тёмная:    return "moon"
        }
    }

    /// Выбор действует: рубильник включён и есть где его поменять — нативный кабинет во вкладках. Иначе окно в теме
    /// iPhone, как до этапа 15: навязанную прежним запуском тему без кабинета было бы нечем снять.
    static var доступен: Bool {
        Config.выборТемы && Config.нативнаяЛента && Config.нижниеВкладки && Config.нативныйКабинет
    }

    /// Что ставить окну. .unspecified — следовать теме iPhone.
    var стильОкна: UIUserInterfaceStyle {
        guard Self.доступен else { return .unspecified }
        switch self {
        case .системная: return .unspecified
        case .светлая:   return .light
        case .тёмная:    return .dark
        }
    }
}

/// Выбранная тема — одна на приложение. Окно перекрашивает SceneDelegate, подписанный на $тема; раздел кабинета
/// (РазделОформления) меняет её выбором в меню.
@MainActor
final class ВыборТемы: ObservableObject {
    static let shared = ВыборТемы()

    private static let ключ = "kliko.appearance"

    /// Выбор человека. На диск — сразу: тема нужна уже на первом кадре следующего запуска.
    @Published var тема: ТемаОформления {
        didSet {
            guard тема != oldValue else { return }
            UserDefaults.standard.set(тема.rawValue, forKey: Self.ключ)
        }
    }

    private init() {
        let сохранено = UserDefaults.standard.string(forKey: Self.ключ).flatMap { ТемаОформления(rawValue: $0) }
        тема = сохранено ?? .системная
    }
}
