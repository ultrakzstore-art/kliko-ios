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
        /* С ВЕРСИЕЙ (1.6): «KlikoApp/1.6». Метка без версии — сборки до 1.6, у которых строка состояния тёмная всегда;
           сайт по ней оставляет белую вуаль над зелёной шапкой (inc/mk_green_top.php, mk-gtop-app15). С версией
           приложение само ставит светлые часы на тёмном верху (мост klikoBars), и шапка уходит под вырез целиком. */
        let версия = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.6"
        cfg.applicationNameForUserAgent = "KlikoApp/" + версия
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
        // Геопозиция через систему, а не через окно WebKit (см. GeoBridge). WKWebView спрашивал
        // «kliko.kz хочет использовать геопозицию» на каждой новой странице и не помнил ответа;
        // iOS спрашивает один раз на всё приложение и помнит решение навсегда.
        ucc.add(context.coordinator, name: "klikoGeo")
        // Получатель из контактов (см. ContactsBridge): системный список, разрешение на контакты не нужно —
        // приложение получает только выбранные человеком имя и номер.
        ucc.add(context.coordinator, name: "klikoContacts")
        // ВЫХОД НАЧИСТО (владелец 16.09.2026: «старая сессия, когда вышел в приложении — очистить, чтобы не приходили чужие
        // сообщения на другую сессию; чистая должна быть как попа младенца»). Страница перед выходом зовёт klikoLogout
        // (inc/app_bridge.php): забываем токены устройства и плашки сделки, закрываем плашку, а когда сервер ответил
        // выходом (адрес с bye=1) — стираем всё, что WebView хранит на телефоне. Раньше не стираем: без куки сессии
        // сервер не узнал бы, чьи адреса уведомлений снимать.
        ucc.add(context.coordinator, name: "klikoLogout")
        // Строка состояния под цвет верха страницы (1.6): страница говорит «light» — тёмный верх, светлые часы, «dark» —
        // наоборот (см. блок klikoBars в liveBridgeJS и KlikoHostingController).
        ucc.add(context.coordinator, name: "klikoBars")
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
        rc.attributedTitle = Coordinator.фразаОбновления()   // подпись под колесом: «потяни ещё — обновится», каждый раз другая
        rc.addTarget(context.coordinator, action: #selector(Coordinator.onPull(_:)), for: .valueChanged)
        web.scrollView.refreshControl = rc

        /* Настоящий прогресс загрузки для прелоадера — доля, которую считает сам WebKit. */
        context.coordinator.progressObs = web.observe(\.estimatedProgress, options: [.initial, .new]) { w, _ in
            let p = w.estimatedProgress
            Task { @MainActor in WebBridge.shared.progress = p }
        }
        context.coordinator.webView = web
        context.coordinator.geo.webView = web
        context.coordinator.contacts.webView = web
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
        var progressObs: NSKeyValueObservation?
        /// Выход запрошен страницей — стереть данные WebView, как только сервер ответит выходом (bye=1).
        var wipeAfterLogout = false
        /// Геопозиция для страницы через CoreLocation (мост klikoGeo).
        let geo = GeoBridge()
        /// Выбор получателя из контактов телефона (мост klikoContacts).
        let contacts = ContactsBridge()

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
        window.KlikoNative = { platform:'ios', liveActivity:true, clipboard:true, perms:true, geo:true, contacts:true, bars:true };
        /* СТРОКА СОСТОЯНИЯ ПОД ЦВЕТ ВЕРХА СТРАНИЦЫ (1.6, владелец 17.09.2026: «стиль хедера — градиент… выложи в TestFlight»).
           Зелёная шапка витрины уходит под Dynamic Island, и тёмные часы на ней не читаются; светлый кабинет — наоборот.
           Смотрим, что лежит под строкой состояния: вуаль безопасной зоны (--sa-veil) поверх первого непрозрачного слоя,
           градиенты тоже, фото — тёмное. Говорим приложению «light» (светлые часы) или «dark» только при смене.
           Без обратных косых черт: строка живёт в Swift-литерале, где они значат своё. */
        (function(){
          if (window.top !== window) return;
          var м = window.webkit && window.webkit.messageHandlers;
          if (!м || !м.klikoBars) return;
          var было = '', ждём = false;
          function разбор(s, от){
            s = String(s || '');
            var i = s.indexOf('rgb', от || 0); if (i < 0) return null;
            var a = s.indexOf('(', i), b = s.indexOf(')', a); if (a < 0 || b < 0) return null;
            var тело = s.slice(a + 1, b), ч = тело.split(',');
            if (ч.length < 3) ч = тело.split(' ').filter(function(x){ return x && x !== '/'; });
            var r = parseFloat(ч[0]), g = parseFloat(ч[1]), bl = parseFloat(ч[2]), al = ч.length > 3 ? parseFloat(ч[3]) : 1;
            if (isNaN(r) || isNaN(g) || isNaN(bl)) return null;
            if (isNaN(al)) al = 1;
            return {r: r, g: g, b: bl, a: al, конец: b + 1};
          }
          function фон(el){
            var cs = getComputedStyle(el), c = разбор(cs.backgroundColor, 0);
            if (c && c.a >= 0.5) return c;
            var im = cs.backgroundImage;
            if (im && im !== 'none') {
              var сумма = {r: 0, g: 0, b: 0}, n = 0, поз = 0, шаг = 0;
              while (шаг++ < 12) { var к = разбор(im, поз); if (!к) break; поз = к.конец; if (к.a >= 0.5) { сумма.r += к.r; сумма.g += к.g; сумма.b += к.b; n++; } }
              if (n) return {r: сумма.r / n, g: сумма.g / n, b: сумма.b / n, a: 1};
            }
            return null;
          }
          function подСтрокой(){
            var el = document.elementFromPoint(Math.round(window.innerWidth / 2), 4), шаг = 0;
            while (el && шаг++ < 30) {
              var т = el.tagName;
              if (т === 'IMG' || т === 'VIDEO' || т === 'CANVAS' || т === 'IFRAME') return {r: 40, g: 40, b: 40, a: 1};
              var c = фон(el); if (c) return c;
              el = el.parentElement;
            }
            return фон(document.documentElement) || {r: 255, g: 255, b: 255, a: 1};
          }
          function решить(){
            ждём = false;
            if (!document.documentElement || !document.body) return;
            var низ = подСтрокой();
            var в = разбор(getComputedStyle(document.documentElement).getPropertyValue('--sa-veil'), 0);
            if (в && в.a > 0) низ = {r: в.r * в.a + низ.r * (1 - в.a), g: в.g * в.a + низ.g * (1 - в.a), b: в.b * в.a + низ.b * (1 - в.a)};
            var яркость = (0.2126 * низ.r + 0.7152 * низ.g + 0.0722 * низ.b) / 255;
            var стиль = яркость < 0.6 ? 'light' : 'dark';
            if (стиль !== было) { было = стиль; try { м.klikoBars.postMessage(стиль); } catch (e) {} }
          }
          function скоро(){ if (ждём) return; ждём = true; setTimeout(решить, 80); }
          ['DOMContentLoaded', 'load', 'pageshow', 'resize', 'scroll', 'visibilitychange', 'transitionend', 'animationend', 'touchend', 'click'].forEach(function(e){
            window.addEventListener(e, скоро, {passive: true, capture: true});
          });
          document.addEventListener('DOMContentLoaded', function(){
            try { new MutationObserver(скоро).observe(document.documentElement, {attributes: true, subtree: true, childList: true, attributeFilter: ['class', 'style', 'data-theme', 'hidden', 'open']}); } catch (e) {}
          });
          setInterval(function(){ if (document.visibilityState !== 'hidden') решить(); }, 1500);
        })();
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
        /* ГЕОПОЗИЦИЯ — ЧЕРЕЗ СИСТЕМУ. Окно WebKit «сайт хочет знать ваше местоположение»
           появлялось на каждой новой странице и ответа не помнило: витрина, кабинет, карта и
           доставка спрашивали заново. navigator.geolocation здесь отвечает мостом klikoGeo:
           iOS спрашивает один раз на всё приложение и помнит решение. Только в главном окне —
           ответы моста приходят туда, во вложенные рамки их не доставить. */
        (function(){
          if (window.top !== window) return;
          var м = window.webkit && window.webkit.messageHandlers;
          if (!м || !м.klikoGeo) return;
          var ждут = {}, номер = 0;
          function ошибка(код, текст){ return {code: код, message: текст || '', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3}; }
          window.__klikoGeo = function(id, r){
            var ж = ждут[id]; if (!ж) return;
            if (!ж.watch) delete ждут[id];
            if (r && r.ok) {
              var н = function(v){ return (v === undefined) ? null : v; };
              try { ж.ok({coords: {latitude: r.lat, longitude: r.lon, accuracy: r.acc, altitude: н(r.alt), altitudeAccuracy: н(r.altAcc), heading: н(r.heading), speed: н(r.speed)}, timestamp: r.ts || Date.now()}); } catch (e) {}
            } else if (ж.err) {
              try { ж.err(ошибка((r && r.code) || 2, r && r.message)); } catch (e) {}
            }
          };
          function послать(сообщ){ try { м.klikoGeo.postMessage(сообщ); return true; } catch (e) { return false; } }
          var гео = {
            getCurrentPosition: function(ok, err, опц){
              опц = опц || {};
              var id = ++номер;
              ждут[id] = {ok: ok, err: err, watch: false};
              var срок = (typeof опц.timeout === 'number' && опц.timeout > 0 && опц.timeout !== Infinity) ? опц.timeout : 0;
              var возраст = (typeof опц.maximumAge === 'number') ? (опц.maximumAge === Infinity ? 1e12 : опц.maximumAge) : 0;
              if (!послать({op: 'get', id: id, high: !!опц.enableHighAccuracy, maxAge: возраст, timeout: срок})) {
                delete ждут[id];
                if (err) { try { err(ошибка(2, 'bridge')); } catch (e) {} }
              }
            },
            watchPosition: function(ok, err, опц){
              опц = опц || {};
              var id = ++номер;
              ждут[id] = {ok: ok, err: err, watch: true};
              послать({op: 'watch', id: id, high: !!опц.enableHighAccuracy});
              return id;
            },
            clearWatch: function(id){ delete ждут[id]; послать({op: 'clear', id: id}); }
          };
          try { Object.defineProperty(navigator, 'geolocation', {value: гео, configurable: true}); } catch (e) {}
          /* Permissions API про геопозицию — по решению системы для приложения. Иначе фоновые
             места сайта (js/geo.js) считали бы, что «ещё не спрашивали», и не брали координаты
             даже после разрешения. */
          try {
            if (navigator.permissions && navigator.permissions.query) {
              var исходный = navigator.permissions.query.bind(navigator.permissions);
              navigator.permissions.query = function(описание){
                if (описание && описание.name === 'geolocation' && window.KlikoPerms) {
                  return KlikoPerms.read().then(function(с){
                    var г = (с && с['гео']) || {};
                    var сост = (г['система'] === false || г['приложение'] === 'denied') ? 'denied'
                             : (г['приложение'] === 'granted' ? 'granted' : 'prompt');
                    return {name: 'geolocation', state: сост, onchange: null};
                  });
                }
                return исходный(описание);
              };
            }
          } catch (e) {}
        })();
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
        /* Получатель из телефонной книги. Страница зовёт KlikoContacts.pick() и получает обещание {ok, name, phone};
           ok:false с code 'cancel' — человек закрыл список. Разрешение на контакты не нужно (ContactsBridge). */
        window.__klikoContactCbs = {};
        window.__klikoContact = function(id, r){
          var f = window.__klikoContactCbs[id]; delete window.__klikoContactCbs[id];
          if (f) { try { f(r || {ok:false}); } catch (e) {} }
        };
        window.KlikoContacts = { pick: function(){
          return new Promise(function(resolve){
            var id = Math.floor(Math.random() * 1000000000);
            window.__klikoContactCbs[id] = resolve;
            try { window.webkit.messageHandlers.klikoContacts.postMessage({id: id}); }
            catch (e) { delete window.__klikoContactCbs[id]; resolve({ok:false, code:'bridge'}); }
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
            // Геопозиция: запрос страницы → CoreLocation → ответ в страницу (см. GeoBridge).
            if message.name == "klikoGeo" {
                if let body = message.body as? [String: Any] { geo.handle(body) }
                return
            }
            // Получатель из контактов: системный список, ответ уйдёт в страницу (ContactsBridge).
            if message.name == "klikoContacts" {
                let id = ((message.body as? [String: Any])?["id"] as? NSNumber)?.intValue ?? 0
                contacts.pick(id: id)
                return
            }
            // Выход: токены забыть сразу (следующий вход отправит токен уже новому аккаунту), плашку сделки закрыть,
            // данные WebView стереть после ответа сервера (didFinish).
            if message.name == "klikoLogout" {
                lastToken = nil
                lastLive = nil
                wipeAfterLogout = true
                Task { await DealActivityManager.shared.end() }
                return
            }
            // Верх страницы тёмный или светлый → стиль строки состояния (KlikoHostingController через WebBridge).
            if message.name == "klikoBars" {
                let светлые = ((message.body as? String) ?? "") == "light"
                Task { @MainActor in WebBridge.shared.statusBarLight = светлые }
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

        /// Подпись при потягивании вниз. Владелец 15.09.2026: «пусть выходит упоминание — подтяни ещё, обновится; слова
        /// подбери сам и каждый раз разные, интересные». Фраза меняется после каждого обновления, язык — первый язык
        /// телефона (kk/ru/en/ar), по умолчанию русский.
        static let фразыОбновления: [String: [String]] = [
            "ru": ["Потяни ещё — обновится", "Отпускай, сейчас освежим", "Ещё чуть-чуть — и всё свежее",
                   "Проверяем, что нового на витрине", "Потяни — вдруг уже появилось то самое", "Свежие объявления уже в пути",
                   "Ещё немного — и лента обновится", "Смотрим, кто что выставил"],
            "kk": ["Тағы тартыңыз — жаңарады", "Жіберіңіз, қазір жаңартамыз", "Витринада не жаңалық бар екен",
                   "Жаңа хабарландырулар жолда", "Сәл ғана — лента жаңарады"],
            "en": ["Pull a bit more to refresh", "Let go — freshening things up", "Checking what's new",
                   "Fresh listings on the way", "Almost there — the feed is updating"],
            "ar": ["اسحب أكثر قليلًا للتحديث", "اترك — نحدّث الآن", "نتحقق من الجديد",
                   "إعلانات جديدة في الطريق", "لحظة — تتحدث القائمة"]
        ]
        static func фразаОбновления() -> NSAttributedString {
            let код = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
            let список = фразыОбновления[код] ?? фразыОбновления["ru"] ?? []
            let текст = список.randomElement() ?? ""
            return NSAttributedString(string: текст, attributes: [
                .foregroundColor: UIColor.secondaryLabel,
                .font: UIFont.preferredFont(forTextStyle: .footnote)
            ])
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
            webView.scrollView.refreshControl?.attributedTitle = Coordinator.фразаОбновления()   // в следующий раз — другая фраза
            bridge.loadFailed = false
            if !bridge.isLoaded { bridge.isLoaded = true }
            if wipeAfterLogout, let адрес = webView.url?.absoluteString, адрес.contains("bye=1") {
                wipeAfterLogout = false
                /* Всё, что сайт хранил на телефоне: куки, localStorage, IndexedDB, Cache Storage, сервис-воркеры, кэш.
                   Сервер уже снял привязки уведомлений этой сессии и погасил её — остатков не будет ни там, ни здесь. */
                WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                        modifiedSince: Date(timeIntervalSince1970: 0)) {}
            }
            if let t = bridge.apnsToken { registerPush(token: t, on: webView) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.scrollView.refreshControl?.attributedTitle = Coordinator.фразаОбновления()   // в следующий раз — другая фраза
            failIfOffline(error)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            webView.scrollView.refreshControl?.attributedTitle = Coordinator.фразаОбновления()   // в следующий раз — другая фраза
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
