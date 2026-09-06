import SwiftUI
import WebKit
import UIKit   // UIPasteboard: чтение системного буфера для моста вставки
import CoreLocation      // различить «гео выключено на устройстве» и «запрещено этому приложению»
import UserNotifications // статус уведомлений и запрос разрешения изнутри приложения

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
        /* ПОДПИСЬ ПРИЛОЖЕНИЯ В USER-AGENT. WKWebView честно считает себя браузером, и
           странице приходилось угадывать по косвенным признакам: «iPhone/iPad в UA, но
           ни Safari, ни CriOS». На iPad это ненадёжно — там UA умеет быть настольным.
           App Review отклонил сборку по 5.1.2(i) именно из-за окна про куки, которое
           внутри приложения показываться не должно, поэтому признак обязан быть точным,
           а не вероятным. applicationNameForUserAgent дописывает метку к стандартному UA. */
        cfg.applicationNameForUserAgent = "KlikoApp"
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        // Мост Live Activity сделки: PWA зовёт window.KlikoLive.{start,update,end}(deal).
        let ucc = cfg.userContentController
        ucc.add(context.coordinator, name: "klikoLive")
        // Мост буфера обмена. В WKWebView веб-страница НЕ может прочитать системный
        // буфер: navigator.clipboard.readText там либо отсутствует, либо отказывает —
        // это ограничение платформы, а не наша ошибка. Кнопка «Вставить» на странице
        // из-за этого выглядела сломанной. Читает буфер нативная сторона и отдаёт
        // строку обратно в страницу — так же, как это делает любое приложение.
        ucc.add(context.coordinator, name: "klikoPaste")
        // Мост «открыть настройки приложения». Из веб-страницы системные настройки
        // открыть НЕЛЬЗЯ: схемы вроде app-settings: браузеры закрыли давно. А человеку,
        // который однажды нажал «Запретить» геопозицию или уведомления, вернуть их
        // иначе почти невозможно — он не знает, где искать. Здесь страница просит
        // открыть свой раздел настроек, и это единственный способ довести его туда
        // одним нажатием. Ничего не читаем и не передаём: только открываем экран.
        ucc.add(context.coordinator, name: "klikoSettings")
        // Состояние разрешений. Веб-страница про них знает постыдно мало: браузерный
        // Permissions API отвечает «denied» и в случае «человек запретил Kliko», и в
        // случае «геолокация выключена на всём устройстве». Это два разных разговора:
        // в первом надо открыть настройки приложения, во втором — общие, и никакая
        // кнопка в настройках Kliko не поможет, пока выключен рубильник системы.
        // Нативная сторона различает их и говорит странице правду.
        ucc.add(context.coordinator, name: "klikoPerms")
        // Запрос разрешения на уведомления ИЗНУТРИ приложения. Пока статус
        // notDetermined, системное окно можно показать — и это куда лучше, чем гнать
        // человека в настройки за тем, что спрашивается одним нажатием.
        ucc.add(context.coordinator, name: "klikoAskPush")
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
        if let lt = bridge.liveToken, context.coordinator.lastLive != lt, bridge.isLoaded {
            context.coordinator.registerLive(lt, on: web)
        }
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let bridge: WebBridge
        weak var webView: WKWebView?
        var lastToken: String?
        var lastLive: LiveToken?

        init(bridge: WebBridge) { self.bridge = bridge }

        /// Собрать состояние разрешений и отдать его странице вызовом __klikoPerms.
        ///
        /// Геопозиция: locationServicesEnabled() — общий рубильник устройства,
        /// authorizationStatus — решение по ЭТОМУ приложению. Первый вызов документирован
        /// как блокирующий, поэтому уводим его с главной нити.
        /// Уведомления: getNotificationSettings — единственный честный источник; статус
        /// notDetermined означает, что окно ещё можно показать.
        func отдатьРазрешения() {
            DispatchQueue.global(qos: .userInitiated).async {
                let системаГео = CLLocationManager.locationServicesEnabled()
                let статусГео: String
                switch CLLocationManager().authorizationStatus {
                case .authorizedAlways, .authorizedWhenInUse: статусГео = "granted"
                case .denied, .restricted:                    статусГео = "denied"
                default:                                      статусГео = "notDetermined"
                }
                UNUserNotificationCenter.current().getNotificationSettings { настройки in
                    let статусПуш: String
                    switch настройки.authorizationStatus {
                    case .authorized, .provisional, .ephemeral: статусПуш = "granted"
                    case .denied:                               статусПуш = "denied"
                    default:                                    статусПуш = "notDetermined"
                    }
                    let данные: [String: Any] = [
                        "гео": ["система": системаГео, "приложение": статусГео],
                        "пуш": статусПуш
                    ]
                    let json = String(data: (try? JSONSerialization.data(withJSONObject: данные)) ?? Data(),
                                      encoding: .utf8) ?? "{}"
                    DispatchQueue.main.async { [weak self] in
                        self?.webView?.evaluateJavaScript("window.__klikoPerms && window.__klikoPerms(\(json))")
                    }
                }
            }
        }

        /// JS-API для сайта: window.KlikoLive.start/update/end(deal) → Live Activity сделки.
        /// Флаг window.KlikoNative даёт сайту понять, что он внутри приложения.
        static let liveBridgeJS = """
        window.KlikoNative = { platform:'ios', liveActivity:true, clipboard:true, perms:true };
        /* Разрешения. Страница зовёт KlikoPerms.read() и получает обещание с состоянием:
           {гео:{система, приложение}, пуш}. Различать «выключено на устройстве» и
           «запрещено этому приложению» в вебе нечем, а разговоры это разные. */
        window.__klikoPermCbs = [];
        window.__klikoPerms = function(состояние){
          var q = window.__klikoPermCbs; window.__klikoPermCbs = [];
          q.forEach(function(f){ try{ f(состояние); }catch(e){} });
        };
        window.KlikoPerms = {
          read: function(){
            return new Promise(function(resolve){
              var готово=false;
              window.__klikoPermCbs.push(function(с){ if(!готово){ готово=true; resolve(с); } });
              try{ window.webkit.messageHandlers.klikoPerms.postMessage({}); }
              catch(e){ if(!готово){ готово=true; resolve(null); } }
              setTimeout(function(){ if(!готово){ готово=true; resolve(null); } }, 2000);
            });
          },
          /* Спросить уведомления прямо здесь. Система покажет окно, только пока
             статус notDetermined; иначе вернётся прежнее состояние. */
          askPush: function(){
            return new Promise(function(resolve){
              var готово=false;
              window.__klikoPermCbs.push(function(с){ if(!готово){ готово=true; resolve(с); } });
              try{ window.webkit.messageHandlers.klikoAskPush.postMessage({}); }
              catch(e){ if(!готово){ готово=true; resolve(null); } }
              setTimeout(function(){ if(!готово){ готово=true; resolve(null); } }, 30000);
            });
          },
          openSettings: function(){ try{ window.webkit.messageHandlers.klikoSettings.postMessage({}); }catch(e){} }
        };
        /* Вставка из системного буфера. Страница зовёт KlikoPaste.read() и получает
           обещание; нативная сторона читает UIPasteboard и вызывает __klikoPasteDone.
           Ждём не дольше двух секунд: если ответа нет, страница покажет привычную
           подсказку про долгое нажатие, а не будет висеть. */
        window.__klikoPasteCbs = [];
        window.__klikoPasteDone = function(t){
          var q = window.__klikoPasteCbs; window.__klikoPasteCbs = [];
          q.forEach(function(f){ try{ f(String(t==null?'':t)); }catch(e){} });
        };
        window.KlikoPaste = { read: function(){
          return new Promise(function(resolve){
            var готово=false;
            window.__klikoPasteCbs.push(function(t){ if(!готово){ готово=true; resolve(t); } });
            try{ window.webkit.messageHandlers.klikoPaste.postMessage({}); }
            catch(e){ if(!готово){ готово=true; resolve(''); } }
            setTimeout(function(){ if(!готово){ готово=true; resolve(''); } }, 2000);
          });
        } };
        window.KlikoLive = {
          start:  function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'start',  deal:d||{}}); }catch(e){} },
          update: function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'update', deal:d||{}}); }catch(e){} },
          end:    function(d){ try{ window.webkit.messageHandlers.klikoLive.postMessage({action:'end',    deal:d||{}}); }catch(e){} }
        };
        """

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            // Буфер обмена: читаем и возвращаем строку в страницу.
            if message.name == "klikoPaste" {
                // UIPasteboard.string — то же, что видит человек в меню «Вставить».
                // Ничего не сохраняем и никуда не отправляем: строка уходит прямо в
                // страницу, которая её и запросила по нажатию кнопки.
                let text = UIPasteboard.general.string ?? ""
                let json = String(data: (try? JSONSerialization.data(withJSONObject: [text])) ?? Data(), encoding: .utf8) ?? "[\"\"]"
                let js = "window.__klikoPasteDone(\(json)[0])"
                DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(js) }
                return
            }
            // Состояние разрешений → в страницу.
            if message.name == "klikoPerms" {
                отдатьРазрешения()
                return
            }
            // Спросить разрешение на уведомления. Система покажет окно только пока
            // статус notDetermined; во всех прочих случаях просто вернём текущий —
            // страница сама решит, звать ли настройки.
            if message.name == "klikoAskPush" {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    if granted { DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() } }
                    self.отдатьРазрешения()
                }
                return
            }
            // Открыть раздел этого приложения в системных настройках.
            if message.name == "klikoSettings" {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                DispatchQueue.main.async { UIApplication.shared.open(url) }
                return
            }
            guard message.name == "klikoLive", let body = message.body as? [String: Any] else { return }
            DealActivityManager.shared.handle(body)
        }

        @objc func onPull(_ sender: UIRefreshControl) { webView?.reload() }

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
        /// бэкенд api/push_register.php привяжет его к вошедшему юзеру.
        ///
        /// 🔴 CSRF ОБЯЗАТЕЛЕН. Эндпоинт требует csrf_cab, и запрос без него получает
        /// {ok:false,error:'csrf'} — то есть токен устройства НЕ сохранялся, и ни один
        /// пуш не доходил. Ошибка была не видна: fetch с .catch() молчит, а приложение
        /// выглядело работающим. Токен страницы отдаёт inc/app_bridge.php как
        /// window.KlikoCsrf; у гостя его нет.
        ///
        /// lastToken запоминаем ТОЛЬКО при реальной отправке. Иначе первая попытка у
        /// гостя (моста ещё нет) считалась бы удачной, и после входа токен уже никогда
        /// бы не ушёл: человек вошёл, а уведомления молчат навсегда.
        func registerPush(token: String, on web: WKWebView) {
            guard lastToken != token else { return }
            let safe = token.filter { $0.isHexDigit }
            let js = """
            (function(){try{
              var c = window.KlikoCsrf || ''; if(!c) return false;
              fetch('/api/push_register.php',{method:'POST',credentials:'same-origin',
                headers:{'Content-Type':'application/json','X-Kliko-Csrf':c},
                body:JSON.stringify({token:'\(safe)',platform:'ios',csrf:c})}).catch(function(){});
              return true;
            }catch(e){ return false; }})();
            """
            web.evaluateJavaScript(js) { [weak self] res, _ in
                if (res as? Bool) == true { self?.lastToken = token }
            }
        }

        /// Токен плашки сделки: тем же путём и с тем же CSRF, но с kind:'live'.
        /// drop:true — активность закрылась, сервер должен забыть адресата.
        func registerLive(_ lt: LiveToken, on web: WKWebView) {
            guard lastLive != lt else { return }
            let deal = lt.deal.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            let tok  = lt.token.filter { $0.isHexDigit }
            if deal.isEmpty { return }
            if !lt.drop && tok.count < 32 { return }
            let js = """
            (function(){try{
              var c = window.KlikoCsrf || ''; if(!c) return false;
              fetch('/api/push_register.php',{method:'POST',credentials:'same-origin',
                headers:{'Content-Type':'application/json','X-Kliko-Csrf':c},
                body:JSON.stringify({kind:'live',deal:'\(deal)',token:'\(tok)',drop:\(lt.drop ? "true" : "false"),csrf:c})}).catch(function(){});
              return true;
            }catch(e){ return false; }})();
            """
            web.evaluateJavaScript(js) { [weak self] res, _ in
                if (res as? Bool) == true { self?.lastLive = lt }
            }
        }
    }
}
