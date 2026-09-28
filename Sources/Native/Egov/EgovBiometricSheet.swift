import SwiftUI
import UIKit
import WebKit

/**
 ЕДИНСТВЕННЫЙ ЧУЖОЙ ШАГ ПОТОКА eGov — экран remote.biometric.kz.

 Там человек вводит код из SMS и проходит проверку лица камерой (liveness). Это страница сервиса eGov-биометрии: её
 нельзя повторить у себя — код и снимок лица уходят прямо в biometric.kz, kliko их не видит (bio_sec_note сайта).
 У сайта это iframe без адреса возврата (карта §2.4 C, §7.2 п. 4): поэтому не ASWebAuthenticationSession — ловить
 нечего, и камера в ней недоступна странице. Компактный лист с WKWebView и своей шапкой (таймер и «Назад»); итог
 узнаёт не страница, а опрос kliko в модели. Сообщение postMessage от страницы и её уход на kliko.kz — только повод
 опросить раньше, их содержимому не верим (как сайт).
 */
enum ВебБиометрииEgov {
    /// Имя обработчика сигнала от страницы.
    static let имяСигнала = "klikoEgovPoke"

    /// Любое сообщение страницы (виджет шлёт postMessage родителю, а он — сама страница) — сигнал «опроси».
    private static let скриптСигнала = """
    (function(){
      function poke(){ try { window.webkit.messageHandlers.klikoEgovPoke.postMessage(1); } catch (e) {} }
      window.addEventListener('message', poke);
      document.addEventListener('visibilitychange', function(){ if (document.visibilityState === 'visible') poke(); });
    })();
    """

    @MainActor
    static func создать(делегат: ДелегатБиометрииEgov) -> WKWebView {
        let настройка = WKWebViewConfiguration()
        настройка.websiteDataStore = .default()
        настройка.allowsInlineMediaPlayback = true
        настройка.mediaTypesRequiringUserActionForPlayback = []
        let версия = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.6"
        настройка.applicationNameForUserAgent = "KlikoApp/" + версия
        let сигнал = WKUserScript(source: скриптСигнала, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        настройка.userContentController.addUserScript(сигнал)
        настройка.userContentController.add(делегат, name: имяСигнала)
        let веб = WKWebView(frame: .zero, configuration: настройка)
        веб.navigationDelegate = делегат
        веб.uiDelegate = делегат
        веб.allowsBackForwardNavigationGestures = false
        веб.scrollView.contentInsetAdjustmentBehavior = .automatic
        веб.accessibilityLabel = ТекстыEgov.т("web_a11y")
        return веб
    }

    /// Хосты eGov-биометрии: им — камера и микрофон.
    static func хостEgov(_ хост: String) -> Bool {
        let х = хост.lowercased()
        return х == "biometric.kz" || х.hasSuffix(".biometric.kz")
    }

    static func хостKliko(_ хост: String) -> Bool {
        let х = хост.lowercased()
        return х == "kliko.kz" || х == "www.kliko.kz"
    }
}

/// Делегат страницы eGov. Модель держит его сама; он её — слабо (WKUserContentController держит обработчик крепко).
final class ДелегатБиометрииEgov: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var модель: МодельПотокаEgov?

    init(модель: МодельПотокаEgov) {
        self.модель = модель
    }

    private func грузится(_ значение: Bool) {
        Task { @MainActor [weak self] in
            self?.модель?.вебГрузится = значение
        }
    }

    private func толкнуть(закрыть: Bool) {
        Task { @MainActor [weak self] in
            guard let модель = self?.модель else { return }
            if закрыть { модель.листEgov = false }
            модель.толкнуть()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        толкнуть(закрыть: false)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        грузится(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        грузится(false)
        толкнуть(закрыть: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        грузится(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        грузится(false)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let схема = (url.scheme ?? "").lowercased()
        if схема != "http" && схема != "https" && схема != "about" && схема != "data" && схема != "blob" {
            /* Приложение eGov Mobile, tel: и прочее не-веб — системе. */
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame ?? true, ВебБиометрииEgov.хостKliko(url.host ?? "") {
            /* Страница eGov вернула на kliko.kz — её шаг кончился: лист закрываем, итог скажет опрос. */
            decisionHandler(.cancel)
            толкнуть(закрыть: true)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }

    /// Камера и микрофон — проверке лица biometric.kz; прочим — вопрос системы.
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(ВебБиометрииEgov.хостEgov(origin.host) ? .grant : .prompt)
    }
}

/// WKWebView из модели: тот же экземпляр при каждом показе листа.
struct СтраницаБиометрииEgov: UIViewRepresentable {
    let модель: МодельПотокаEgov

    func makeUIView(context: Context) -> WKWebView {
        модель.веб()
    }

    func updateUIView(_ web: WKWebView, context: Context) {}
}

/// Лист поверх потока: своя шапка (eGov, «Назад»), полоса с таймером, страница biometric.kz.
struct ЛистБиометрииEgov: View {
    @ObservedObject var модель: МодельПотокаEgov

    private var время: String {
        let с = max(0, модель.осталось)
        return String(с / 60) + ":" + String(format: "%02d", с % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(КраскаEgov.хорошо)
                        .accessibilityHidden(true)
                    Text(ТекстыEgov.т("confirm_wait"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(время)
                        .font(.system(size: 14, weight: .heavy).monospacedDigit())
                        .foregroundStyle(модель.осталось <= 60 ? КраскаEgov.плохо : Theme.текст)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.поверхность2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.линия).frame(height: 1)
                }
                .accessibilityElement(children: .combine)
                СтраницаБиометрииEgov(модель: модель)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay {
                        if модель.вебГрузится {
                            SiteSpinner(размер: 28, толщина: 3)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .background(Theme.поверхность.ignoresSafeArea())
            .navigationTitle(ТекстыEgov.т("web_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ТекстыEgov.т("back")) { модель.листEgov = false }
                }
            }
        }
        .tint(Theme.акцент)
        /* Смахнуть посреди проверки лица — легко случайно: закрывается только «Назад», и её можно открыть снова. */
        .interactiveDismissDisabled(true)
    }
}
