import SafariServices
import SwiftUI
import UIKit
import WebKit

/**
 БЕЗ ПЕРЕХОДОВ НА САЙТ (владелец: «главное, чтобы на сайт не прыгал с приложения»).

 Все адреса, которые экраны приложения раньше отдавали странице сайта (WebBridge.pendingURL, корневое «открыть»,
 ПереходыКабинета.открыть), идут через WebBridge.перейти: свой экран — им; своего экрана нет — это окно «Страница
 недоступна в приложении» с «Назад», а не сайт. Здесь — то, что показывает перейти:
   · недоступна — своё окно поверх верхнего экрана (ПоверхВсего);
   · внешняя — чужая страница (не kliko.kz) листом Safari внутри приложения;
   · исключение — вход через Apple и подключение соцсетей, пока сервер не умеет свои ответы (docs/SERVER_NATIVE_AUTH.md):
     та же страница, но листом внутри приложения (ЛистСтраницыСайта), без ухода со своего экрана.
 */
@MainActor
enum БезСайта {
    /// Последний показ окна «недоступна»: два вызова подряд (кнопка и её запасной путь) не ставят два окна.
    private static var показано = Date.distantPast

    /// Своего экрана у адреса нет — окно «Страница недоступна в приложении».
    static func недоступна(_ адрес: URL? = nil) {
        сообщить(заголовок: БезСайтаText.т("na_t"), текст: БезСайтаText.т("na_s"))
    }

    /// Своё окно-сообщение с «Назад» и «Написать в поддержку» поверх того, что на экране.
    static func сообщить(заголовок: String, текст: String) {
        let сейчас = Date()
        guard сейчас.timeIntervalSince(показано) > 1.5 else { return }
        показано = сейчас
        ПоверхВсего.показать(большой: false) { закрыть in
            ОкноНедоступно(заголовок: заголовок, текст: текст, закрыть: закрыть)
        }
    }

    /// Чужая страница (не kliko.kz): лист Safari внутри приложения; показать некуда — система.
    static func внешняя(_ адрес: URL) {
        Task { @MainActor in
            for _ in 0..<12 {
                if let верх = ПоверхВсего.верхний() {
                    let настройка = SFSafariViewController.Configuration()
                    настройка.entersReaderIfAvailable = false
                    let окно = SFSafariViewController(url: адрес, configuration: настройка)
                    окно.preferredControlTintColor = UIColor(Theme.зелёный)
                    окно.dismissButtonStyle = .close
                    верх.present(окно, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
        }
    }

    /**
     Разрешённые страницы нашего домена, у которых своего ответа сервера ещё нет: вход через Apple
     (apple_auth.php, запасной путь ВходApple) и подключение соцсетей (social_connect.php, запасной путь
     ПодключениеСоцсети). true — показаны листом внутри приложения.
     */
    static func исключение(_ адрес: URL) -> Bool {
        let имя = адрес.lastPathComponent.lowercased()
        let вход: Bool
        switch имя {
        case "apple_auth.php", "apple_auth": вход = true
        case "social_connect.php", "social_connect": вход = false
        default: return false
        }
        ПоверхВсего.показать(смахивается: false) { закрыть in
            ЛистСтраницыСайта(адрес: адрес, заголовок: БезСайтаText.т(вход ? "apple_t" : "social_t"), закрыть: {
                закрыть()
                БезСайта.послеИсключения(вход: вход)
            })
        }
        return true
    }

    /// После листа входа или соцсети — общее состояние входа сверяется с кабинетом (как после ОкноEgov).
    private static func послеИсключения(вход: Bool) {
        Task { @MainActor in
            if вход {
                let uid = (try? await КабинетСайта.состояние())?.uid ?? ""
                if !uid.isEmpty {
                    await КабинетСайта.послеВхода(uid: uid)
                    NotificationCenter.default.post(name: ОкнаПриложения.вошли, object: nil)
                }
            }
            СессияПриложения.shared.запросить(кабинет: true)
        }
    }

    /**
     Своего точного экрана нет, но есть ближайший: объявление с лишними параметрами (/?item=, ?item=&chat=1) — его
     карточка; прочий адрес ленты (незнакомые параметры, негодный номер) — лента, как «Главная»; любой другой адрес
     кабинета — корень вкладки «Кабинет». nil — ближайшего нет.
     */
    static func ближайший(_ адрес: URL) -> NativeRouter.Цель? {
        guard let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: true) else { return nil }
        let путь = части.path.replacingOccurrences(of: "^/[a-z]{2}/[a-z]{2}(?=/|$)", with: "",
                                                   options: .regularExpression)
        let товар = (части.queryItems?.first(where: { $0.name == "item" })?.value ?? "")
            .trimmingCharacters(in: .whitespaces)
        let ленты: Set<String> = ["", "/", "/index.php", "/marketplace", "/marketplace/", "/marketplace.php"]
        if ленты.contains(путь), !товар.isEmpty, Config.нативнаяКарточка,
           товар.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            return .объявление(id: товар)
        }
        if ленты.contains(путь) || СсылкиЛенты.разделSEO(части.path) != nil {
            return .найти(ИскомоеЛенты(текст: "", раздел: ""))
        }
        if АдресаКабинета.кабинет(части.path), NativeRouter.доступна(.кабинет) { return .кабинет }
        return nil
    }

    /// Для Text со ссылками и Link: адрес нашего домена — через WebBridge.перейти, прочее — как обычно.
    static var действиеСсылки: OpenURLAction {
        OpenURLAction { адрес in
            guard Config.deepLink(адрес.absoluteURL) != nil else { return .systemAction }
            MainActor.assumeIsolated { WebBridge.shared.перейти(адрес) }
            return .handled
        }
    }
}

// MARK: - Окно «Страница недоступна в приложении»

struct ОкноНедоступно: View {
    let заголовок: String
    let текст: String
    let закрыть: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .padding(.top, 26)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(текст)
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                закрыть()
            } label: {
                Text(БезСайтаText.т("back"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Button {
                закрыть()
                ПоддержкаПоверх.показать(тема: "other", задержка: 500_000_000)
            } label: {
                Text(БезСайтаText.т("support"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.фонСтраницы.ignoresSafeArea())
    }
}

// MARK: - Разрешённая страница листом внутри приложения

/**
 Страница нашего домена листом поверх экрана — только для исключений (вход через Apple, подключение соцсетей). Хранилище —
 WKWebsiteDataStore.default(), общее со слоем сайта и транспортом кабинета: там живёт сессия. Лист закрывается сам, когда
 страница вернулась в кабинет или на главную (вход и подключение закончены) или позвала kliko://; иначе — «Закрыть».
 */
struct ЛистСтраницыСайта: View {
    let адрес: URL
    let заголовок: String
    let закрыть: () -> Void
    @State private var грузится = true

    var body: some View {
        NavigationStack {
            СтраницаЛиста(адрес: адрес, грузится: $грузится, закрыть: закрыть)
                .ignoresSafeArea(edges: .bottom)
                .background(Theme.фонСтраницы.ignoresSafeArea())
                .navigationTitle(заголовок)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(БезСайтаText.т("close")) { закрыть() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if грузится { SiteSpinner() }
                    }
                }
        }
    }
}

private struct СтраницаЛиста: UIViewRepresentable {
    let адрес: URL
    @Binding var грузится: Bool
    let закрыть: () -> Void

    func makeCoordinator() -> Координатор { Координатор(грузится: $грузится, закрыть: закрыть) }

    func makeUIView(context: Context) -> WKWebView {
        let настройка = WKWebViewConfiguration()
        настройка.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: настройка)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.load(URLRequest(url: адрес))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Координатор: NSObject, WKNavigationDelegate, WKUIDelegate {
        let грузится: Binding<Bool>
        let закрыть: () -> Void
        private var первыйРазрешён = false
        private var закончено = false

        init(грузится: Binding<Bool>, закрыть: @escaping () -> Void) {
            self.грузится = грузится
            self.закрыть = закрыть
        }

        private func закрытьПотом() {
            guard !закончено else { return }
            закончено = true
            let закрыть = self.закрыть
            DispatchQueue.main.async { закрыть() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, !закончено else {
                decisionHandler(закончено ? .cancel : .allow)
                return
            }
            let схема = (url.scheme ?? "").lowercased()
            if схема == Config.scheme {
                decisionHandler(.cancel)
                закрытьПотом()
                return
            }
            if схема != "http" && схема != "https" && схема != "about" && схема != "data" && схема != "blob" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            let главная = navigationAction.targetFrame?.isMainFrame ?? true
            if главная && первыйРазрешён && Config.deepLink(url) != nil {
                /* Вернулись в кабинет или на главную — вход или подключение закончены: лист закрывается, сайт не
                   показывается. */
                let путь = url.path
                if Config.главная(url) || АдресаКабинета.кабинет(путь) {
                    decisionHandler(.cancel)
                    закрытьПотом()
                    return
                }
            }
            if главная { первыйРазрешён = true }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            грузится.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            грузится.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            грузится.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            грузится.wrappedValue = false
        }

        /// target="_blank" — в этом же листе.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            закрытьПотом()
        }
    }
}

// MARK: - Тексты

/// Тексты окон «без сайта» на языке телефона (kk/ru/en/ar) — тем же способом, что LinksText.
enum БезСайтаText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["na_t": "Страница недоступна в приложении",
               "na_s": "Этого раздела в приложении пока нет — мы уже переносим его сюда. Если нужна помощь, напишите нам.",
               "deal_t": "Этот шаг пока недоступен в приложении",
               "deal_s": "Сделка и деньги в безопасности. Если нужна помощь с этим шагом, напишите в поддержку — ответим здесь, в приложении.",
               "back": "Назад", "support": "Написать в поддержку", "close": "Закрыть",
               "apple_t": "Вход через Apple", "social_t": "Подключение соцсети"],
        "kk": ["na_t": "Бет қолданбада қолжетімсіз",
               "na_s": "Бұл бөлім қолданбада әзірге жоқ — біз оны осында көшіріп жатырмыз. Көмек керек болса, бізге жазыңыз.",
               "deal_t": "Бұл қадам қолданбада әзірге қолжетімсіз",
               "deal_s": "Мәміле мен ақша қауіпсіз. Осы қадам бойынша көмек керек болса, қолдауға жазыңыз — жауапты осында, қолданбада береміз.",
               "back": "Артқа", "support": "Қолдауға жазу", "close": "Жабу",
               "apple_t": "Apple арқылы кіру", "social_t": "Әлеуметтік желіні қосу"],
        "en": ["na_t": "This page isn't available in the app",
               "na_s": "This section isn't in the app yet — we're moving it here. If you need help, write to us.",
               "deal_t": "This step isn't available in the app yet",
               "deal_s": "Your deal and money are safe. If you need help with this step, write to support — we'll answer right here in the app.",
               "back": "Back", "support": "Write to support", "close": "Close",
               "apple_t": "Sign in with Apple", "social_t": "Connect a social account"],
        "ar": ["na_t": "هذه الصفحة غير متاحة في التطبيق",
               "na_s": "هذا القسم غير موجود في التطبيق بعد — ننقله إليه الآن. إذا احتجت إلى مساعدة، راسلنا.",
               "deal_t": "هذه الخطوة غير متاحة في التطبيق بعد",
               "deal_s": "صفقتك وأموالك في أمان. إذا احتجت إلى مساعدة في هذه الخطوة، راسل الدعم — سنرد هنا في التطبيق.",
               "back": "رجوع", "support": "راسل الدعم", "close": "إغلاق",
               "apple_t": "تسجيل الدخول عبر Apple", "social_t": "ربط حساب تواصل اجتماعي"]
    ]
}
