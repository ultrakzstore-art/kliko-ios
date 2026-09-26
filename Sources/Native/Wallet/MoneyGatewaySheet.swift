import SwiftUI
import UIKit
import WebKit

/**
 ЛИСТ СТРАНИЦЫ БАНКА — ВВОД КАРТЫ ВНУТРИ ПРИЛОЖЕНИЯ (подготовлено 26.09.2026, живёт за Config.деньгиКошелька и
 Config.деньгиСделок — сами рубильники здесь не читаются: лист открывают только их модели).

 Кто открывает: пополнение кошелька (pay.php?action=create → redirect_url), оплата сделки картой (escrow.php?action=pay_card
 → redirect_url), курьер картой (ship_add_card → redirect_url), карта для выплаты (payout_link → url). Сайт ведёт на эти
 адреса той же вкладкой (location.href); приложение — листом поверх своего экрана, вкладку сайта не трогает.

 Почему WKWebView, а не SFSafariViewController: адрес возврата банка (…/cabinet…?topup=ok|fail[&deal=][&ship=1],
 ?payout=back) нужно поймать до загрузки, а навигация Safari-листа закрыта от приложения; к тому же банк может вернуть
 человека через pay.php нашего домена, которому нужны куки сессии. Хранилище — WKWebsiteDataStore.default(), общее с
 вкладкой сайта (WebContainer) и транспортом кабинета.

 Как узнаём итог — как сайт (обработчик ?topup= и ?payout=back страницы кабинета, js/cabinet.min.js):
   · перехват вызывающего (ВозвратКошелька.разобрать / ВозвратСоШлюза.разобрать) — переход на наш домен с topup= или
     payout=back отменяется, лист закрывается, итог уходит модели (сверка pay.php?action=confirm, payout_outcome);
   · любой другой переход главной рамки на наш домен, кроме служебных (pay.php, /api/), — человек ушёл со страницы банка
     (кнопка «Вернуться в магазин» банка, адрес возврата без параметров): лист закрывается как «закрыли сами» — вызывающий
     перечитывает кошелёк или сделку, денег приложение не двигает;
   · window.close() страницы — так же.
 Ссылки на приложения банков (не http/https) уходят в систему. Смахнуть лист нельзя — только «Закрыть». Жест «назад»
 выключен: шаг назад на странице банка мог бы отправить форму оплаты второй раз. По той же причине «Повторить» есть только
 у первой загрузки (GET страницы банка, ещё ничего не оплачено); сбой позже — только «Закрыть».
 */
enum ШлюзОплаты {
    /// Наш домен по https.
    static func свой(_ адрес: URL) -> Bool {
        let хост = (адрес.host ?? "").lowercased()
        return адрес.scheme?.lowercased() == "https" && (хост == "kliko.kz" || хост == "www.kliko.kz")
    }

    /// Служебный платёжный адрес нашего домена (pay.php…, /pay/, /api/): через него банк может вернуть человека, а сервер
    /// перешлёт дальше, на кабинет с ?topup= — такой адрес грузится в листе.
    static func служебный(_ адрес: URL) -> Bool {
        let путь = адрес.path.lowercased()
        let имя = адрес.lastPathComponent.lowercased()
        return имя.hasPrefix("pay") || путь.contains("/pay/") || путь.contains("/api/")
    }
}

// MARK: - Состояние листа

@MainActor
final class СостояниеШлюза: ObservableObject {
    @Published var грузится = true
    /// Главная рамка не загрузилась (didFailProvisionalNavigation).
    @Published var сбой = false
    /// Хоть одна страница открылась — «Повторить» больше не предлагаем.
    @Published var былаСтраница = false
    /// Хост открытой страницы — под заголовком, с замком: человек видит, где вводит карту.
    @Published var хост = ""

    let адрес: URL
    weak var web: WKWebView?

    init(адрес: URL) {
        self.адрес = адрес
    }

    /// Первая загрузка не удалась: тот же GET страницы банка ещё раз (оплаты на ней ещё не было).
    func повторить() {
        guard !былаСтраница, let web else { return }
        сбой = false
        грузится = true
        web.load(URLRequest(url: адрес))
    }
}

// MARK: - Лист

struct ЛистШлюза: View {
    let адрес: URL
    let заголовок: String
    let подписьЗакрыть: String
    /// true — адрес возврата пойман (переход отменён, вызывающий сам закрывает лист и разбирает итог).
    let перехват: (URL) -> Bool
    /// «Закрыть», window.close(), уход на наш домен без итога.
    let закрыть: () -> Void

    @StateObject private var состояние: СостояниеШлюза

    init(адрес: URL, заголовок: String, подписьЗакрыть: String, перехват: @escaping (URL) -> Bool,
         закрыть: @escaping () -> Void) {
        self.адрес = адрес
        self.заголовок = заголовок
        self.подписьЗакрыть = подписьЗакрыть
        self.перехват = перехват
        self.закрыть = закрыть
        _состояние = StateObject(wrappedValue: СостояниеШлюза(адрес: адрес))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                СтраницаШлюза(адрес: адрес, состояние: состояние, перехват: перехват, закрыть: закрыть)
                    .ignoresSafeArea(edges: .bottom)
                if состояние.сбой {
                    окноСбоя
                }
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(подписьЗакрыть) { закрыть() }
                }
                ToolbarItem(placement: .principal) {
                    шапка
                }
                ToolbarItem(placement: .confirmationAction) {
                    if состояние.грузится && !состояние.сбой {
                        SiteSpinner()
                            .accessibilityLabel(ТекстШлюза.т("loading"))
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var шапка: some View {
        VStack(spacing: 1) {
            Text(заголовок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            if !состояние.хост.isEmpty {
                Label(состояние.хост, systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var окноСбоя: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(ТекстШлюза.т("fail_t"))
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(ТекстШлюза.т(состояние.былаСтраница ? "fail_s" : "fail_s0"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !состояние.былаСтраница {
                КнопкаСделки(ТекстШлюза.т("retry"), вид: .главная, символ: "arrow.clockwise") {
                    состояние.повторить()
                }
            }
            КнопкаСделки(подписьЗакрыть, вид: .вторая) { закрыть() }
        }
        .padding(22)
        .frame(maxWidth: 380)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.фонСтраницы.opacity(0.96).ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

// MARK: - WKWebView листа

struct СтраницаШлюза: UIViewRepresentable {
    let адрес: URL
    let состояние: СостояниеШлюза
    let перехват: (URL) -> Bool
    let закрыть: () -> Void

    func makeCoordinator() -> Координатор {
        Координатор(состояние: состояние, перехват: перехват, закрыть: закрыть)
    }

    func makeUIView(context: Context) -> WKWebView {
        let настройка = WKWebViewConfiguration()
        настройка.websiteDataStore = .default()
        настройка.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: настройка)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false
        web.accessibilityLabel = ТекстШлюза.т("a11y")
        состояние.web = web
        web.load(URLRequest(url: адрес))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Координатор) {
        coordinator.закончено = true
        web.stopLoading()
        web.navigationDelegate = nil
        web.uiDelegate = nil
    }

    final class Координатор: NSObject, WKNavigationDelegate, WKUIDelegate {
        let состояние: СостояниеШлюза
        let перехват: (URL) -> Bool
        let закрыть: () -> Void
        /// Итог отдан (или лист закрывается) — больше никаких переходов и второго итога.
        var закончено = false
        /// Первый переход главной рамки (адрес банка из ответа сервера) уже разрешён.
        private var первыйРазрешён = false

        init(состояние: СостояниеШлюза, перехват: @escaping (URL) -> Bool, закрыть: @escaping () -> Void) {
            self.состояние = состояние
            self.перехват = перехват
            self.закрыть = закрыть
        }

        private func закрытьПотом() {
            закончено = true
            let закрыть = self.закрыть
            DispatchQueue.main.async { закрыть() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if закончено {
                decisionHandler(.cancel)
                return
            }
            if перехват(url) {
                закончено = true
                decisionHandler(.cancel)
                return
            }
            let схема = (url.scheme ?? "").lowercased()
            if схема != "http" && схема != "https" && схема != "about" && схема != "data" && схема != "blob" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            let главная = navigationAction.targetFrame?.isMainFrame ?? true
            if главная && первыйРазрешён && ШлюзОплаты.свой(url) && !ШлюзОплаты.служебный(url) {
                decisionHandler(.cancel)
                закрытьПотом()
                return
            }
            if главная { первыйРазрешён = true }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            состояние.грузится = true
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            состояние.хост = webView.url?.host ?? ""
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            состояние.грузится = false
            if let s = webView.url?.scheme?.lowercased(), s == "https" || s == "http" {
                состояние.былаСтраница = true
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            состояние.грузится = false
            guard !закончено, !Self.отменено(error) else { return }
            состояние.сбой = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            состояние.грузится = false
        }

        /// Отмену перехода (свой перехват, ссылка на приложение банка) за сбой не считаем.
        private static func отменено(_ error: Error) -> Bool {
            let e = error as NSError
            if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return true }
            return e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard !закончено else { return }
            закрытьПотом()
        }
    }
}

// MARK: - Лист пополнения поверх карточки сделки

/**
 «Недостаточно средств» у оплаты сделки или курьера, когда картой нельзя (showTopup сайта): при Config.деньгиКошелька —
 тот же экран «Пополнить кошелёк», что у кошелька, со своей моделью; выключен — вызывающий открывает кабинет сайта.
 */
struct ЛистПополненияКошелька: View {
    @StateObject private var модель: ПополнениеМодель
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    init(открыть: @escaping (URL) -> Void, закрыть: @escaping () -> Void) {
        self.открыть = открыть
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: ПополнениеМодель())
    }

    var body: some View {
        ЭкранПополнения(модель: модель, открыть: открыть, закрыть: закрыть)
    }
}

// MARK: - Слова листа (свои слова приложения: у сайта этого окна нет)

private enum ТекстШлюза {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "a11y": "Страница оплаты банка",
        "loading": "Загрузка",
        "fail_t": "Страница банка не открылась",
        "fail_s0": "Проверьте интернет и попробуйте ещё раз. Деньги не списаны — оплата идёт только на странице банка.",
        "fail_s": "Связь со страницей банка прервалась. Закройте окно — баланс и сделка обновятся, повторно ничего не спишется.",
        "retry": "Повторить",
    ]

    private static let kk: [String: String] = [
        "a11y": "Банктің төлем беті",
        "loading": "Жүктелуде",
        "fail_t": "Банк беті ашылмады",
        "fail_s0": "Интернетті тексеріп, қайталап көріңіз. Ақша алынған жоқ — төлем тек банк бетінде жүреді.",
        "fail_s": "Банк бетімен байланыс үзілді. Терезені жабыңыз — баланс пен мәміле жаңарады, ештеңе қайта алынбайды.",
        "retry": "Қайталау",
    ]

    private static let en: [String: String] = [
        "a11y": "Bank payment page",
        "loading": "Loading",
        "fail_t": "The bank page didn't open",
        "fail_s0": "Check your connection and try again. No money was charged — payment happens only on the bank page.",
        "fail_s": "The connection to the bank page was lost. Close this window — your balance and deal will refresh, nothing will be charged twice.",
        "retry": "Try again",
    ]

    private static let ar: [String: String] = [
        "a11y": "صفحة الدفع لدى البنك",
        "loading": "جارٍ التحميل",
        "fail_t": "لم تُفتح صفحة البنك",
        "fail_s0": "تحقّق من الاتصال وحاول مرة أخرى. لم يُخصم أي مبلغ — الدفع يتم فقط في صفحة البنك.",
        "fail_s": "انقطع الاتصال بصفحة البنك. أغلق النافذة — سيتحدّث الرصيد والصفقة، ولن يُخصم شيء مرتين.",
        "retry": "إعادة المحاولة",
    ]
}
