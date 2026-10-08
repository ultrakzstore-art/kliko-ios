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
    /* Этап 15: .default — «по теме», а тему теперь может навязать кабинет (окну — overrideUserInterfaceStyle). Не гадаем,
       чью тему система возьмёт для .default — iPhone или окна: решаем сами по теме этого контроллера, а она от окна.
       Тёмная — светлые часы, светлая — тёмные. Сплэш, замок, «нет связи» и нативный слой стоят на systemBackground, и он
       перекрашивается той же темой окна, так что часы совпадают с фоном. Стиль страницы (klikoBars) — как был. */
    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard стильСтроки == .default else { return стильСтроки }
        return traitCollection.userInterfaceStyle == .dark ? .lightContent : .darkContent
    }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        /* Тема сменилась — выбором в кабинете или самим iPhone при «Системной» — спросить стиль часов заново: сам
           UIKit явный .lightContent/.darkContent не пересчитывает. */
        registerForTraitChanges([UITraitUserInterfaceStyle.self],
                                action: #selector(UIViewController.setNeedsStatusBarAppearanceUpdate))
    }
}

/// Окно приложения. Раньше его создавал SwiftUI (WindowGroup в KlikoApp.swift); теперь — сцена UIKit, чтобы корнем стал
/// KlikoHostingController. Всё остальное прежнее: тот же RootWebView, те же мосты, пуши — в AppDelegate.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var подписка: AnyCancellable?
    /// Этап 15: смена темы в кабинете → окно.
    private var подпискаТемы: AnyCancellable?
    /// Предупреждение и запрет устаревшей версии (ForcedUpdate.swift): своё окно над всем приложением, включая листы.
    private var окноОбновленияПоверх: UIWindow?
    private var подпискаОбновления: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let сцена = scene as? UIWindowScene else { return }
        let корень = KlikoHostingController(rootView: AnyView(RootWebView().tint(Theme.green)))
        let окно = UIWindow(windowScene: сцена)
        окно.rootViewController = корень
        /* Этап 15: тема из кабинета — окну целиком и до показа, иначе первый кадр мелькнул бы темой iPhone. От окна её
           берут SwiftUI, системные окна поверх и страница сайта (WKWebView без своей темы → prefers-color-scheme). */
        окно.overrideUserInterfaceStyle = ВыборТемы.shared.тема.стильОкна
        window = окно
        окно.makeKeyAndVisible()

        #if DEBUG
        /* СЪЁМКА ЭКРАНОВ В CI (этап 23): аргументы запуска `-klikoOpen <адрес>` и `-klikoSite <адрес>` (UserDefaults читает
           их сам). Открыть ссылку через simctl openurl нельзя: iOS каждый раз спрашивает «Открыть в Kliko?», и вопрос
           попадает на снимок. klikoOpen — как вход снаружи (нативная карточка); klikoSite — страница сайта в обёртке
           приложения: эталон, на который равняются нативные экраны (у сайта в Safari сверху ещё плашка «В приложении
           удобнее»). Только в отладочной сборке. */
        let аргументы = UserDefaults.standard
        if let строка = аргументы.string(forKey: "klikoOpen"), let адрес = URL(string: строка) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { WebBridge.shared.открытьСнаружи(адрес) }
        } else if let строка = аргументы.string(forKey: "klikoSite"), let адрес = URL(string: строка) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                WebBridge.shared.открытьСайтВместоЛенты()
                WebBridge.shared.pendingURL = адрес
            }
        }
        #endif

        /* Сменили тему в кабинете — перекрашиваем окно наплывом. Первое значение уже стоит на окне (dropFirst); значение
           берём из события, а не из ВыборТемы: @Published шлёт его до записи. Часы перестроит KlikoHostingController —
           он слушает смену темы сам. */
        подпискаТемы = ВыборТемы.shared.$тема
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak окно] тема in
                guard let окноСцены = окно else { return }
                let стиль = тема.стильОкна
                guard окноСцены.overrideUserInterfaceStyle != стиль else { return }
                UIView.transition(with: окноСцены, duration: 0.3,
                                  options: [.transitionCrossDissolve, .allowUserInteraction],
                                  animations: { окноСцены.overrideUserInterfaceStyle = стиль },
                                  completion: nil)
            }

        /* Версия отстала от App Store на порог выпусков — предупреждение, потом запрет. Окно поверх всего, а не лист на
           корне: лист не встанет над уже открытым листом или экраном во весь экран. Проверка — в sceneDidBecomeActive. */
        подпискаОбновления = ПринудительноеОбновление.shared.$показ
            .map { $0 != .нет }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak сцена] нужно in
                guard let self, let сцена else { return }
                self.показатьОкноОбновления(нужно, сцена: сцена)
            }

        let мост = WebBridge.shared
        let замок = AppLock.shared
        /* Пока виден сплэш, экран «нет связи» или замок входа — системный стиль: под ними подложка systemBackground, а не
           страница. Потом — то, что сказала страница: светлые часы на тёмном верху, тёмные на светлом. */
        let замокВиден = замок.$locked.combineLatest(замок.$cover, замок.$enabled).map { заперт, закрыт, вкл in вкл && (заперт || закрыт) }
        /* Нативная лента на экране — тоже системный стиль: у неё системный фон, а не верх страницы (nil — системный).
           Этап 25: кроме корня ленты с зелёной шапкой сайта — там часы светлые в обеих темах, как у сайта. */
        let вид = ВидСайта.shared
        /* Этап 28: и над фото страницы объявления как на сайте — оно уходит под часы, под ним затемнение. */
        let зелёныйВерх = вид.$кореньЛенты.combineLatest(вид.$вкладкаЛенты, вид.$фотоПодЧасами)
            .map { корень, вкладка, фото -> Bool in (корень && вкладка) || фото }
        let стильСтраницы = мост.$statusBarLight.combineLatest(мост.$лентаВидна, зелёныйВерх)
            .map { светлые, лента, зелёный -> UIStatusBarStyle? in
                if лента { return зелёный ? UIStatusBarStyle.lightContent : nil }
                return светлые ? UIStatusBarStyle.lightContent : UIStatusBarStyle.darkContent
            }
        подписка = Publishers.CombineLatest4(стильСтраницы, мост.$splashDone, мост.$loadFailed, замокВиден)
            .receive(on: DispatchQueue.main)
            .sink { [weak корень] стиль, сплэшУшёл, нетСвязи, подЗамком in
                if сплэшУшёл { ЗамерыСкорости.заставкаУшла() }      // один раз за запуск (PerfTelemetry.swift)
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

        // Этап 10. Холодный старт по результату в поиске iPhone (Spotlight) — объявление, как по ссылке сайта.
        if let адрес = connectionOptions.userActivities.lazy.compactMap({ ПоискТелефона.адрес(из: $0) }).first {
            мост.открытьСнаружи(адрес)
        }
        // Меню иконки — заново при каждом запуске; холодный старт по его пункту приходит сюда, а не в performActionFor.
        БыстрыеДействия.обновить()
        if let пункт = connectionOptions.shortcutItem { БыстрыеДействия.выполнить(пункт) }
        // Поиск iPhone выключен — то, что клали туда прежние запуски, убираем, а не ждём истечения срока.
        if !Config.spotlight { ПоискТелефона.стереть() }
        // Число на иконке выключено (этап 11) — то, что ставили прежние запуски, убираем.
        ЗначокПриложения.прибрать()
        // Этап 13: копии объявлений для карточки без сети следят за избранным и «Вы смотрели»; рубильник выключен —
        // копии прежних запусков стираются.
        КарточкиБезСети.shared.запустить()
        // Офлайн-режим: общий монитор сети и очередь неотправленных сообщений — после запуска, каждый своим вызовом
        // (их init никого не трогает: взаимная инициализация синглтонов роняла 1.11 (58)).
        СетьПриложения.shared.запустить()
        ОчередьСообщений.shared.запустить()
        // Этап 16: виденная версия («Что нового») и дата установки (просьба оценить) — на каждом запуске, даже когда
        // листа не будет: иначе обновление после такого запуска сошло бы за первую установку, а три дня тишины
        // отсчитывались бы от случайного дня, а не от установки.
        ЧтоНового.отметитьЗапуск()
        ПросьбаОценить.запомнитьУстановку()
    }

    /// Окно предупреждения или запрета устаревшей версии: показать над приложением или убрать.
    private func показатьОкноОбновления(_ нужно: Bool, сцена: UIWindowScene) {
        guard нужно else {
            окноОбновленияПоверх?.isHidden = true
            window?.makeKey()
            return
        }
        if окноОбновленияПоверх == nil {
            let контроллер = UIHostingController(rootView: СлойОбновленияПриложения())
            контроллер.view.backgroundColor = .clear
            let окно = UIWindow(windowScene: сцена)
            окно.windowLevel = UIWindow.Level.alert + 1
            окно.backgroundColor = .clear
            окно.rootViewController = контроллер
            окноОбновленияПоверх = окно
        }
        окноОбновленияПоверх?.overrideUserInterfaceStyle = window?.overrideUserInterfaceStyle ?? .unspecified
        окноОбновленияПоверх?.makeKeyAndVisible()
    }

    /// Плашка сделки или кнопка «Открыть в приложении», когда приложение уже запущено.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let адрес = URLContexts.first?.url, let наш = Config.deepLink(адрес) { WebBridge.shared.открытьСнаружи(наш) }
    }

    /// Ссылка сайта из поиска, письма или чужого приложения, когда наше уже запущено (Universal Links), и результат
    /// в поиске iPhone (Spotlight, этап 10) — объявление, которое человек смотрел.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let объявление = ПоискТелефона.адрес(из: userActivity) {
            WebBridge.shared.открытьСнаружи(объявление)
            return
        }
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let адрес = userActivity.webpageURL, let наш = Config.deepLink(адрес) else { return }
        WebBridge.shared.открытьСнаружи(наш)
    }

    /// Быстрое действие с иконки, когда приложение уже запущено (этап 10).
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(БыстрыеДействия.выполнить(shortcutItem))
    }

    // Вход по Face ID (AppLock): закрыть содержимое при уходе, запереть после минуты в фоне, спросить при возврате.
    func sceneWillResignActive(_ scene: UIScene)    { AppLock.shared.sceneWillResignActive() }
    func sceneDidEnterBackground(_ scene: UIScene)  {
        AppLock.shared.sceneDidEnterBackground()
        ПроверкаПоисков.запланировать()             // этап 12: проверка сохранённых поисков — не раньше чем через час
        ЗамерыСкорости.вФон()                       // замеры скорости — на диск и пачкой на сервер (PerfTelemetry.swift)
    }
    func sceneWillEnterForeground(_ scene: UIScene) { AppLock.shared.sceneWillEnterForeground() }
    func sceneDidBecomeActive(_ scene: UIScene)     {
        AppLock.shared.sceneDidBecomeActive()
        // Запуск и возврат: версия App Store (не чаще раза в 6 часов) и предупреждение или запрет устаревшей версии.
        Task { await ПринудительноеОбновление.shared.проверить() }
        ЗамерыСкорости.приАктивности()              // раз в сутки — пачка замеров скорости
    }
}

/// СЪЁМКА КАДРОВ APP STORE В CI (ios-check.yml, job screens): аргумент запуска `-klikoSheet <имя>` открывает лист сам —
/// garant (окно «Как работает Безопасная сделка» на ленте), filters (фильтры ленты), qr (QR-код открытой карточки).
/// Только в отладочной сборке; в выпуске всегда nil.
enum СъёмкаCI {
    static var лист: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "klikoSheet")
        #else
        return nil
        #endif
    }
}
