import SwiftUI
import UIKit
import Combine

/// Корневой контроллер окна: SwiftUI-экран (RootWebView) + строка состояния под цвет верха страницы.
///
/// ЗАЧЕМ СВОЙ КОНТРОЛЛЕР (1.6, владелец 17.09.2026: «стиль хедера — градиент… выложи в TestFlight»). Витрина с зелёной
/// шапкой уходит под Dynamic Island, а строка состояния у SwiftUI-приложения следует только теме системы: в светлой теме
/// часы тёмные, и на зелёном их не прочитать. Поэтому сборка 1.5 держала над шапкой белую вуаль. У SwiftUI нет
/// модификатора «светлые часы для этого экрана» — стиль строки состояния решает корневой UIViewController, и приложение
/// получает его, создав окно само (SceneDelegate), а не через WindowGroup.
final class KlikoHostingController: UIHostingController<AnyView> {
    /// Стиль часов и значков. Меняется по сигналу страницы (мост klikoBars), пока виден сплэш — системный.
    var стильСтроки: UIStatusBarStyle = .default {
        didSet {
            guard oldValue != стильСтроки else { return }
            UIView.animate(withDuration: 0.2) { self.setNeedsStatusBarAppearanceUpdate() }
        }
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { стильСтроки }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }
}

/// Окно приложения. Раньше его создавал SwiftUI (WindowGroup в KlikoApp.swift); теперь — сцена UIKit, чтобы корнем стал
/// KlikoHostingController. Всё остальное прежнее: тот же RootWebView, те же мосты, пуши — в AppDelegate.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var подписка: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let сцена = scene as? UIWindowScene else { return }
        let корень = KlikoHostingController(rootView: AnyView(RootWebView().tint(Theme.green)))
        let окно = UIWindow(windowScene: сцена)
        окно.rootViewController = корень
        window = окно
        окно.makeKeyAndVisible()

        let мост = WebBridge.shared
        let замок = AppLock.shared
        /* Пока виден сплэш, экран «нет связи» или замок входа — системный стиль: под ними подложка systemBackground, а не
           страница. Потом — то, что сказала страница: светлые часы на тёмном верху, тёмные на светлом. */
        let замокВиден = замок.$locked.combineLatest(замок.$cover, замок.$enabled).map { заперт, закрыт, вкл in вкл && (заперт || закрыт) }
        /* Нативная лента на экране — тоже системный стиль: у неё системный фон, а не верх страницы (nil — системный). */
        let стильСтраницы = мост.$statusBarLight.combineLatest(мост.$лентаВидна)
            .map { светлые, лента -> UIStatusBarStyle? in лента ? nil : (светлые ? .lightContent : .darkContent) }
        подписка = Publishers.CombineLatest4(стильСтраницы, мост.$splashDone, мост.$loadFailed, замокВиден)
            .receive(on: DispatchQueue.main)
            .sink { [weak корень] стиль, сплэшУшёл, нетСвязи, подЗамком in
                guard let стиль, сплэшУшёл, !нетСвязи, !подЗамком else { корень?.стильСтроки = .default; return }
                корень?.стильСтроки = стиль
            }

        // Холодный старт по нажатию на плашку сделки (widgetURL) или по кнопке «Открыть в приложении»
        // (kliko://open?u=…). Раньше это ловил .onOpenURL у WindowGroup.
        // Адрес проходит через Config.deepLink: он переводит схему в страницу и отсекает чужие домены.
        // Объявление и переписка открываются нативными экранами (этап 8, WebBridge.открытьСнаружи), прочее — сайтом.
        if let адрес = connectionOptions.urlContexts.first?.url, let наш = Config.deepLink(адрес) { мост.открытьСнаружи(наш) }

        // Холодный старт по ссылке сайта из поиска, письма или сообщения (Universal Links, applinks:kliko.kz).
        // Домен здесь уже проверила iOS — по файлу apple-app-site-association; Config.deepLink страхует.
        if let ссылка = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
           let адрес = ссылка.webpageURL, let наш = Config.deepLink(адрес) { мост.открытьСнаружи(наш) }
    }

    /// Плашка сделки или кнопка «Открыть в приложении», когда приложение уже запущено.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let адрес = URLContexts.first?.url, let наш = Config.deepLink(адрес) { WebBridge.shared.открытьСнаружи(наш) }
    }

    /// Ссылка сайта из поиска, письма или чужого приложения, когда наше уже запущено (Universal Links).
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let адрес = userActivity.webpageURL, let наш = Config.deepLink(адрес) else { return }
        WebBridge.shared.открытьСнаружи(наш)
    }

    // Вход по Face ID (AppLock): закрыть содержимое при уходе, запереть после минуты в фоне, спросить при возврате.
    func sceneWillResignActive(_ scene: UIScene)    { AppLock.shared.sceneWillResignActive() }
    func sceneDidEnterBackground(_ scene: UIScene)  { AppLock.shared.sceneDidEnterBackground() }
    func sceneWillEnterForeground(_ scene: UIScene) { AppLock.shared.sceneWillEnterForeground() }
    func sceneDidBecomeActive(_ scene: UIScene)     { AppLock.shared.sceneDidBecomeActive() }
}
