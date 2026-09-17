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
        /* Пока виден сплэш или экран «нет связи» — системный стиль: под ними подложка systemBackground, а не страница.
           Потом — то, что сказала страница: светлые часы на тёмном верху, тёмные на светлом. */
        подписка = Publishers.CombineLatest3(мост.$statusBarLight, мост.$splashDone, мост.$loadFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak корень] светлые, сплэшУшёл, нетСвязи in
                корень?.стильСтроки = (!сплэшУшёл || нетСвязи) ? .default : (светлые ? .lightContent : .darkContent)
            }

        // Холодный старт по нажатию на плашку сделки (widgetURL): раньше это ловил .onOpenURL у WindowGroup.
        if let адрес = connectionOptions.urlContexts.first?.url { мост.pendingURL = адрес }
    }

    /// Нажатие на плашку сделки, когда приложение уже запущено.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let адрес = URLContexts.first?.url { WebBridge.shared.pendingURL = адрес }
    }
}
