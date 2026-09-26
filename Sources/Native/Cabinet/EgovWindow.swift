import SwiftUI
import UIKit
import WebKit

/**
 eGOV В СИСТЕМНОМ ОКНЕ ПОВЕРХ ПРИЛОЖЕНИЯ (владелец, TestFlight 1.10: eGov «в нативе»).

 Раньше каждая кнопка eGov (вход, «Я продавец», восстановление по ИИН, подтверждение входа, «Пройти верификацию»)
 закрывала нативный экран и уводила приложение на вкладку сайта. Теперь eGov открывается листом поверх того экрана, где
 его нажали, и после удачи приложение само узнаёт о входе или верификации.

 ПОЧЕМУ WKWebView-ЛИСТ, А НЕ ASWebAuthenticationSession. У сайта eGov — не OAuth с адресом возврата (карта кабинета
 §1.2.4, §1.2.5, §1.7.2): форма ИИН и номера на странице кабинета → POST cabinet.php?action=flow_login_create
 (login_egov_create, kyc.php?action=flow_create) с csrf гостевой или вошедшей сессии → iframe
 https://remote.biometric.kz/flow/<session_id> (SMS-код и лицо, камера) → опрос flow_login_result / flow_result с тем же
 csrf и кукой сессии → сервер открывает сессию или ставит верификацию, страница делает reload. Callback-адреса нет —
 ASWebAuthenticationSession нечего ловить, а её куки (хранилище Safari) не те, что у страницы под слоем: токен и
 сессия, к которым привязан поток, остались бы в WKWebsiteDataStore приложения, а новая кука входа легла бы в Safari.
 Поэтому — WKWebView с тем же WKWebsiteDataStore.default(), что у страницы под слоем (WebContainer) и SiteSession:
 поток сайта идёт как есть, кука входа сразу общая. Камера — странице сайта и biometric.kz; ссылки не http(s)
 (приложение eGov Mobile и т. п.) — системе.

 Как узнаём конец: после каждой загрузки страницы сайта в листе читаем KlikoUser.id и IS_VERIFIED / CAB_IS_VERIFIED.
 Был гостем — стал вошедшим, или не был верифицирован — стал: успех → ulx_me_id и перезагрузка страницы под слоем
 (КабинетСайта.послеВхода — её загрузка перечитывает кабинет, как после входа паролем), уведомление завершено и
 «готово» вызывающего. Сайт увёл со страницы кабинета (bioAfterOk с return_deal → объявление) — поток сайта кончился:
 лист закрывается, а адрес открывается как обычная ссылка.
 */
@MainActor
enum ОкноEgov {
    /// Можно выключить и вернуть прежний путь — страницу сайта во вкладке.
    static let включено = true

    /// eGov прошёл (вход или верификация) — экраны, которым это важно, перечитывают себя.
    static let завершено = Notification.Name("kliko.egov.done")

    enum Итог {
        /// Вошли или прошли верификацию; uid вошедшего.
        case готово(uid: String)
        /// Сайт сам увёл на другую страницу — открыть её как обычно.
        case ушли(URL)
    }

    private static weak var показан: UIViewController?
    private static var открывается = false

    /// Адрес eGov сайта: кабинет с ?egov=1, ?egov_confirm=1, ?go=verify или ?go=egov.
    nonisolated static func этоEgov(_ адрес: URL) -> Bool {
        guard let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: false) else { return false }
        let путь = части.path
        guard путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil else {
            return false
        }
        for п in части.queryItems ?? [] {
            let значение = (п.value ?? "").lowercased()
            if п.name == "egov" && значение == "1" { return true }
            if п.name == "egov_confirm" && значение == "1" { return true }
            if п.name == "go" && (значение == "verify" || значение == "egov") { return true }
        }
        return false
    }

    /// Для корневого «открыть»: адрес eGov — лист поверх, true; иначе false, и адрес идёт своим путём.
    static func перехватить(_ адрес: URL) -> Bool {
        guard включено, этоEgov(адрес) else { return false }
        открыть(адрес)
        return true
    }

    /**
     Показать eGov поверх верхнего экрана. исходный — адрес кнопки (по нему видно «подтверждение входа» и return_deal);
     nil — по состоянию: гостю вход (?egov=1), вошедшему верификация (?go=verify). готово — после удачи.
     */
    static func открыть(_ исходный: URL? = nil, готово: (() -> Void)? = nil) {
        guard показан == nil, !открывается else { return }
        открывается = true
        Task { @MainActor in
            defer { ОкноEgov.открывается = false }
            guard let адрес = await ОкноEgov.выбратьАдрес(исходный) else { return }
            /* Вызывающий мог только что закрыть свой лист или алерт: ждём, пока UIKit его уберёт. */
            try? await Task.sleep(nanoseconds: 300_000_000)
            for _ in 0..<12 {
                if let верх = ОкноEgov.верхний() {
                    ОкноEgov.показать(адрес, над: верх, готово: готово)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            WebBridge.shared.pendingURL = адрес
        }
    }

    // MARK: - Адрес

    private static func выбратьАдрес(_ исходный: URL?) async -> URL? {
        var параметры: [URLQueryItem] = []
        if let исходный, let части = URLComponents(url: исходный.absoluteURL, resolvingAgainstBaseURL: false) {
            параметры = части.queryItems ?? []
        }
        if параметры.contains(where: { $0.name == "egov_confirm" && $0.value == "1" }) {
            return Config.страницаСайта("cabinet.php?egov_confirm=1")
        }
        let вошёл = await SiteSession.состояние().вошёл
        /* У вошедшего ?egov=1 ничего не делает (CAB читает только go), у гостя — ?go=verify и ?go=egov (обработчик в
           cabinet.min.js, который гостю не грузится; карта §0.10). Поэтому адрес — по тому, кто на странице. */
        if вошёл == false {
            return Config.страницаСайта("cabinet.php?egov=1")
        }
        if вошёл == true {
            var хвост = "cabinet.php?go=verify"
            if let сделка = параметры.first(where: { $0.name == "return_deal" })?.value, !сделка.isEmpty {
                хвост += "&return_deal=" + (сделка.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? сделка)
            }
            return Config.страницаСайта(хвост)
        }
        /* Страница под слоем не сказала: адрес кнопки как есть, без него — вход. */
        if let исходный { return исходный.absoluteURL }
        return Config.страницаСайта("cabinet.php?egov=1")
    }

    // MARK: - Показ поверх всего

    /// Верхний контроллер, над которым можно показать лист; nil — что-то ещё уезжает или приезжает.
    private static func верхний() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first,
              var верх = окно.rootViewController else { return nil }
        while let следующий = верх.presentedViewController {
            if следующий.isBeingDismissed || следующий.isBeingPresented { return nil }
            верх = следующий
        }
        if верх.isBeingDismissed { return nil }
        return верх
    }

    private static func показать(_ адрес: URL, над верх: UIViewController, готово: (() -> Void)?) {
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let экран = ЭкранEgov(адрес: адрес, конец: { [weak хост] итог in
            let лист: UIViewController? = хост
            Task { @MainActor in
                лист?.dismiss(animated: true)
                ОкноEgov.показан = nil
                if let итог { ОкноEgov.завершить(итог, готово: готово) }
            }
        })
        хост.rootView = AnyView(экран)
        хост.modalPresentationStyle = .pageSheet
        /* Смахнуть вниз посреди проверки лица — потерять её: закрывается только кнопкой. */
        хост.isModalInPresentation = true
        if let лист = хост.sheetPresentationController {
            лист.detents = [.large()]
            лист.prefersGrabberVisible = true
        }
        показан = хост
        верх.present(хост, animated: true)
    }

    private static func завершить(_ итог: Итог, готово: (() -> Void)?) {
        switch итог {
        case .готово(let uid):
            Task { @MainActor in
                /* Как после входа паролем: ulx_me_id и перезагрузка страницы под слоем — её загрузка перечитывает
                   кабинет (КабинетСайта.состояние в CabinetView), новый токен и «я» для чатов. */
                ИнбоксAPI.забыть()
                await КабинетСайта.послеВхода(uid: uid)
                NotificationCenter.default.post(name: ОкноEgov.завершено, object: nil)
                готово?()
            }
        case .ушли(let адрес):
            NotificationCenter.default.post(name: завершено, object: nil)
            WebBridge.shared.pendingURL = адрес
        }
    }

    // MARK: - Тексты

    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Верификация через eGov", "close": "Закрыть", "a11y": "Страница eGov"],
        "kk": ["title": "eGov арқылы верификация", "close": "Жабу", "a11y": "eGov беті"],
        "en": ["title": "eGov verification", "close": "Close", "a11y": "eGov page"],
        "ar": ["title": "التحقق عبر eGov", "close": "إغلاق", "a11y": "صفحة eGov"]
    ]
}

// MARK: - Лист

struct ЭкранEgov: View {
    let адрес: URL
    /// nil — закрыли кнопкой.
    let конец: (ОкноEgov.Итог?) -> Void
    @State private var грузится = true

    init(адрес: URL, конец: @escaping (ОкноEgov.Итог?) -> Void) {
        self.адрес = адрес
        self.конец = конец
    }

    var body: some View {
        NavigationStack {
            ВебEgov(адрес: адрес, грузится: $грузится, конец: конец)
                .ignoresSafeArea(edges: .bottom)
                .overlay {
                    if грузится {
                        ProgressView()
                            .controlSize(.large)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle(ОкноEgov.т("title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(ОкноEgov.т("close")) { конец(nil) }
                    }
                }
        }
        .tint(Theme.акцент)
    }
}

/// WKWebView листа eGov: хранилище страницы под слоем, подпись приложения в User-Agent, камера сайту и biometric.kz.
struct ВебEgov: UIViewRepresentable {
    let адрес: URL
    @Binding var грузится: Bool
    let конец: (ОкноEgov.Итог?) -> Void

    func makeCoordinator() -> Координатор {
        Координатор(грузится: $грузится, конец: конец)
    }

    func makeUIView(context: Context) -> WKWebView {
        let настройка = WKWebViewConfiguration()
        настройка.websiteDataStore = .default()
        настройка.allowsInlineMediaPlayback = true
        настройка.mediaTypesRequiringUserActionForPlayback = []
        /* Та же метка, что у страницы под слоем (WebContainer): сайт по ней знает, что он в приложении. */
        let версия = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.6"
        настройка.applicationNameForUserAgent = "KlikoApp/" + версия
        let web = WKWebView(frame: .zero, configuration: настройка)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.accessibilityLabel = ОкноEgov.т("a11y")
        web.load(URLRequest(url: адрес))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Координатор: NSObject, WKNavigationDelegate, WKUIDelegate {
        let грузится: Binding<Bool>
        let конец: (ОкноEgov.Итог?) -> Void
        /// Кто был на первой загруженной странице кабинета: uid и верифицирован ли.
        private var начало: (uid: String, проверен: Bool)? = nil
        private var закончено = false

        init(грузится: Binding<Bool>, конец: @escaping (ОкноEgov.Итог?) -> Void) {
            self.грузится = грузится
            self.конец = конец
        }

        /// Кто на странице: KlikoUser.id и IS_VERIFIED / CAB_IS_VERIFIED (const и let страницы видны по имени).
        private static let проверка = """
        (function(){
          var u = '', v = false;
          try { u = (window.KlikoUser && window.KlikoUser.id) ? String(window.KlikoUser.id) : ''; } catch (e) {}
          try { if (typeof IS_VERIFIED !== 'undefined' && IS_VERIFIED === true) v = true; } catch (e) {}
          try { if (typeof CAB_IS_VERIFIED !== 'undefined' && CAB_IS_VERIFIED === true) v = true; } catch (e) {}
          return JSON.stringify({u: u, v: v});
        })()
        """

        private static func нашСайт(_ адрес: URL?) -> Bool {
            guard let адрес, (адрес.scheme ?? "").lowercased() == "https",
                  let хост = адрес.host?.lowercased() else { return false }
            return хост == "kliko.kz" || хост == "www.kliko.kz"
        }

        private static func кабинет(_ адрес: URL) -> Bool {
            адрес.path.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            грузится.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            грузится.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            грузится.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            грузится.wrappedValue = false
            guard !закончено, let адрес = webView.url, Self.нашСайт(адрес) else { return }
            webView.evaluateJavaScript(Self.проверка) { [weak self] значение, _ in
                self?.сверить(значение as? String ?? "", адрес: адрес)
            }
        }

        private func сверить(_ ответ: String, адрес: URL) {
            guard !закончено else { return }
            var uid = ""
            var проверен = false
            if let данные = ответ.data(using: .utf8),
               let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] {
                uid = (объект["u"] as? String) ?? ""
                проверен = (объект["v"] as? Bool) ?? false
            }
            guard let начало else {
                self.начало = (uid, проверен)
                return
            }
            let вошли = начало.uid.isEmpty && !uid.isEmpty
            let прошли = !начало.проверен && проверен
            if вошли || прошли {
                закончено = true
                конец(.готово(uid: uid))
                return
            }
            if !Self.кабинет(адрес) {
                /* bioAfterOk → объявление сделки, «Вернуться на сайт» и т. п.: поток сайта в листе кончился. */
                закончено = true
                конец(.ушли(адрес))
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let схема = (url.scheme ?? "").lowercased()
            if схема != "http" && схема != "https" && схема != "about" && схема != "data" && схема != "blob" {
                /* Приложение eGov Mobile, tel:, mailto: — системе. */
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        /// Камера и микрофон — проверке лица biometric.kz (iframe) и странице сайта; прочим — вопрос системы.
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let хост = origin.host.lowercased()
            if хост == "kliko.kz" || хост == "www.kliko.kz" || хост == "biometric.kz" || хост.hasSuffix(".biometric.kz") {
                decisionHandler(.grant)
            } else {
                decisionHandler(.prompt)
            }
        }
    }
}
