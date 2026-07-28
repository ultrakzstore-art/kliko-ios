import SwiftUI
import WebKit

/// PWA kliko.kz внутри нативной обёртки. Сессия живёт в cookie-хранилище WKWebView
/// (persistent) — вход/эскроу/чат работают как в браузере. Пуши регистрируются
/// инъекцией токена в веб-сессию (см. registerPush): бэкенд связывает токен с юзером
/// по той же сессии, без дублирования авторизации в нативе.
struct WebContainer: UIViewRepresentable {
    @ObservedObject var bridge: WebBridge

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []          // видео/аудио в ленте без лишнего тапа
        cfg.websiteDataStore = .default()                          // ПЕРСИСТЕНТНЫЕ cookie → сессия не слетает
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        // Мост Live Activity сделки: PWA зовёт window.KlikoLive.{start,update,end}(deal).
        let ucc = cfg.userContentController
        ucc.add(context.coordinator, name: "klikoLive")
        ucc.addUserScript(WKUserScript(source: Coordinator.liveBridgeJS,
                                       injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true             // свайп «назад», как в браузере
        web.scrollView.contentInsetAdjustmentBehavior = .never
        // Авто-тема: фон под цвет системы (иначе белая вспышка в тёмной теме до отрисовки).
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.scrollView.backgroundColor = .systemBackground
        if #available(iOS 15.0, *) { web.underPageBackgroundColor = .systemBackground }
        web.overrideUserInterfaceStyle = .unspecified             // следуем системной теме (prefers-color-scheme)
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif

        // Pull-to-refresh
        let rc = UIRefreshControl()
        rc.tintColor = UIColor(Theme.green2)
        rc.addTarget(context.coordinator, action: #selector(Coordinator.onPull(_:)), for: .valueChanged)
        web.scrollView.refreshControl = rc

        context.coordinator.webView = web
        bridge.webView = web
        web.load(URLRequest(url: Config.apiBase))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // Deep-link из пуша: перейти и сбросить.
        if let url = bridge.pendingURL {
            web.load(URLRequest(url: url))
            DispatchQueue.main.async { bridge.pendingURL = nil }
        }
        // Токен пришёл после загрузки страницы → регистрируем в веб-сессии.
        if let t = bridge.apnsToken, context.coordinator.lastToken != t, bridge.isLoaded {
            context.coordinator.registerPush(token: t, on: web)
        }
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let bridge: WebBridge
        weak var webView: WKWebView?
        var lastToken: String?

        init(bridge: WebBridge) { self.bridge = bridge }

        /// JS-API для сайта: window.KlikoLive.start/update/end(deal) → Live Activity сделки.
        /// Флаг window.KlikoNative даёт сайту понять, что он внутри приложения.
        static let liveBridgeJS = """
        window.KlikoNative = { platform:'ios', liveActivity:true };
        window.KlikoLive = {
          start:  function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'start',  deal:d||{}}); }catch(e){} },
          update: function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'update', deal:d||{}}); }catch(e){} },
          end:    function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'end',    deal:d||{}}); }catch(e){} }
        };
        """

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "klikoLive", let body = message.body as? [String: Any] else { return }
            DealActivityManager.shared.handle(body)
        }

        @objc func onРull(_ sender: UIRefreshControl) { webView?.reload() }

        // Ссылки в мессенджеры/звонок/почту — во внешние приложения; остальное (в т.ч.
        // платёжный шлюз и eGov-биометрия) остаётся в WebView, чтобы редиректы вернулись в приложение.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.allow); return }
            let scheme = (url.scheme ?? "").lowercased()
            if ["tel", "mailto", "sms", "whatsapp", "tg", "telegram", "itms-apps"].contains(scheme) {
                UIApplication.shared.open(url); decisionHandler(.cancel); return
            }
            if scheme == "http" || scheme == "https" {
                let host = (url.host ?? "").lowercased()
                let messenger = ["wa.me", "api.whatsapp.com", "t.me", "telegram.me"]
                if messenger.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    UIApplication.shared.open(url); decisionHandler(.cancel); return
                }
            }
            decisionHandler(.allow)
        }

        // target="_blank" → открыть в этом же WebView (иначе ссылка «проглатывается»).
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        // Камера/микрофон для getUserMedia (поиск по фото, QR, голосовые). OS всё равно спросит один раз.
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            bridge.loadFailed = false
            if !bridge.isLoaded { bridge.isLoaded = true }
            if let t = bridge.apnsToken { registerPush(token: t, on: webView) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            failIfOffline(error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            failIfOffline(error)
        }
        private func failIfOffline(_ error: Error) {
            // Показываем «нет связи» только если страница ещё не загружалась (иначе не мигаем на дозагрузках).
            if !bridge.isLoaded { bridge.loadFailed = true }
        }

        /// Регистрируем APNs-токен в текущей веб-сессии (cookie есть в WebView) —
        /// бэкенд api/push_register.php привяжет его к вошедшему юзеру. Гость → бэкенд тихо игнорит.
        func registerPush(token: String, on web: WKWebView) {
            guard lastToken != token else { return }
            lastToken = token
            let safe = token.filter { $0.isHexDigit }
            let js = """
            (function(){try{
              fetch('/api/push_register.php',{method:'POST',credentials:'same-origin',
                headers:{'Content-Type':'application/json'},
                body:JSON.stringify({token:'\(safe)',platform:'ios'})}).catch(function(){});
            }catch(e){}})();
            """
            web.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
