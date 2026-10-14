import SwiftUI
import UIKit

/**
 «РАЗБОР ОБЪЯВЛЕНИЯ» (ultra-site 07–14.10.2026: «Разбор объявления: кнопка в окне товара и новая дверь api/brief.php»,
 «цена по рынку для легковых машин», «цена по рынку для квартир», «доводы ИИ и метка «по рынку»»).

 Двери:
   · GET api/brief.php?id=<номер> (вход не нужен, только чтение) → {ok, market: null | {n, min, max, mid, diff, ext?,
     unit?, area?, m2_min?, m2_max?, m2_mid?, m2_own?}, chip: "" | "low" | "same"}; рубильник item_brief выключен —
     {ok:false, off:true}: кнопки «Разбор объявления» и метки нет. Старый сервер без chip — метки нет, кнопка есть;
   · POST chat.php?action=brief_ai {id, lang, own?} (сессия, как чат объявления) → {ok, pros[≤3], cons[≤3], ask[≤3],
     verdict, cached?, own_ai_run?}; отказ — off (раздела нет до перезапуска), need:"auth" (войти), need:"paid" (своя
     фраза, без кнопок покупки), ai_blocked, disabled, ai_day_cap, rate_limited, wait, error item|empty|fail (текст
     сервера), отказ своего ИИ (окно ОкноСвоегоИИ). Запрос — только по нажатию человека.
 Метка у цены — только по полю chip: «Ниже рынка на X%» (X = |market.diff|) и «На уровне рынка»; пороги не считаем.
 В ответах и на экране — только числа: ни источника, ни ссылок.
 */

// MARK: - Данные

/// market из api/brief.php — цены похожих объявлений.
struct РынокРазбора: Equatable {
    /// n — сколько похожих.
    let похожих: Int
    let минимум: Double
    let максимум: Double
    /// mid — середина (медиана).
    let середина: Double
    /// diff — на сколько процентов цена объявления отличается от середины (отрицательное — дешевле).
    let разница: Double
    /// ext — в набор вошли цены внешнего рынка.
    let внешний: Bool
    /// unit: "m2" — квартиры: сравнение по цене за м², шкала пересчитана на площадь этой квартиры.
    let заМетр: Bool
    let площадь: Double?
    let серединаЗаМетр: Double?
}

/// Доводы ИИ из chat.php?action=brief_ai.
struct ДоводыРазбора: Equatable {
    let плюсы: [String]
    let минусы: [String]
    let вопросы: [String]
    let вывод: String
    /// own_ai_run — собрал свой ИИ человека: пометка «через ваш ИИ».
    let своимИИ: Bool

    init(_ j: [String: Any]) {
        плюсы = Self.список(j["pros"])
        минусы = Self.список(j["cons"])
        вопросы = Self.список(j["ask"])
        вывод = (РазборОбъявленияAPI.строка(j["verdict"]) ?? "")
        своимИИ = ОтветСвоегоИИ.своим(j)
    }

    var пусто: Bool { плюсы.isEmpty && минусы.isEmpty && вопросы.isEmpty && вывод.isEmpty }

    /// Строки массива (не больше трёх, как обещает сервер); не строки и пустые — мимо.
    private static func список(_ значение: Any?) -> [String] {
        guard let массив = значение as? [Any] else { return [] }
        return Array(массив.compactMap { РазборОбъявленияAPI.строка($0) }.prefix(3))
    }
}

// MARK: - Двери

enum РазборОбъявленияAPI {
    enum ИтогРынка: Equatable {
        case готово(рынок: РынокРазбора?, чип: String)
        /// off — рубильник item_brief выключен (или дверь не ответила ok).
        case выключено
        case сеть
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// Доводы ИИ отвечают дольше: модель думает до минуты.
    private static let сессияИИ: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 90
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// GET api/brief.php?id= — цена по рынку и метка chip.
    @MainActor
    static func рынок(_ номер: String) async -> ИтогРынка {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/brief.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "id", value: номер)]
        guard let адрес = ч?.url else { return .сеть }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let результат = try? await сессия.data(for: запрос) else { return .сеть }
        guard let j = (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any] else {
            /* Не JSON — старый сервер без двери (404-страница): как выключено, не повторяем. */
            return .выключено
        }
        guard да(j["ok"]), !да(j["off"]) else { return .выключено }
        let чип = (строка(j["chip"]) ?? "").lowercased()
        let рынок = (j["market"] as? [String: Any]).flatMap { разобратьРынок($0) }
        return .готово(рынок: рынок, чип: чип)
    }

    /// market → РынокРазбора; нет похожих или границ — nil (как market: null).
    static func разобратьРынок(_ м: [String: Any]) -> РынокРазбора? {
        let похожих = Int(число(м["n"]) ?? 0)
        guard похожих > 0, let минимум = число(м["min"]), let максимум = число(м["max"]),
              let середина = число(м["mid"]), максимум > 0, максимум >= минимум else { return nil }
        return РынокРазбора(похожих: похожих, минимум: минимум, максимум: максимум, середина: середина,
                            разница: число(м["diff"]) ?? 0, внешний: да(м["ext"]),
                            заМетр: строка(м["unit"]) == "m2", площадь: число(м["area"]),
                            серединаЗаМетр: число(м["m2_mid"]))
    }

    /// POST chat.php?action=brief_ai {id, lang, own?}: куки сессии и X-Kliko-Csrf, как отправка в чат объявления
    /// (правка сервера 97). nil — сеть оборвалась или ответ не JSON.
    @MainActor
    static func доводы(_ номер: String, свой: Bool) async -> [String: Any]? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("chat.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: "brief_ai")]
        guard let адрес = ч?.url else { return nil }
        var тело: [String: Any] = ["id": номер, "lang": ТекстыРазбора.язык]
        if свой { тело["own"] = 1 }
        let токен = await SiteSession.csrf()
        if let токен { тело["csrf"] = токен }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        if let токен { запрос.setValue(токен, forHTTPHeaderField: "X-Kliko-Csrf") }
        запрос.httpBody = try? JSONSerialization.data(withJSONObject: тело)
        guard let результат = try? await сессияИИ.data(for: запрос) else { return nil }
        return (try? JSONSerialization.jsonObject(with: результат.0)) as? [String: Any]
    }

    // MARK: Разбор значений (как JS: 1, "1", true — да)

    static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    static func строка(_ значение: Any?) -> String? {
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = значение as? NSNumber { return n.stringValue }
        return nil
    }

    static func число(_ значение: Any?) -> Double? {
        var пришло: Double?
        if let n = значение as? NSNumber {
            пришло = n.doubleValue
        } else if let s = значение as? String {
            пришло = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        guard let итог = пришло, итог.isFinite, abs(итог) < 1e15 else { return nil }
        return итог
    }

    /// Текст сервера для человека (text, error) — не машинный код вроде «rate_limited».
    static func текстДляЧеловека(_ j: [String: Any]) -> String? {
        for поле in ["text", "error", "msg"] {
            guard let текст = строка(j[поле]) else { continue }
            if текст.range(of: "^[a-z][a-z0-9_:]{1,24}$", options: .regularExpression) != nil { continue }
            return текст
        }
        return nil
    }
}

// MARK: - Состояние разбора одной страницы

/// Разбор открытого объявления: дверь рынка — при показе страницы, доводы ИИ — по нажатию.
@MainActor
final class МодельРазбораОбъявления: ObservableObject {
    enum Доводы: Equatable {
        case нет
        case грузим
        case готово(ДоводыРазбора)
        case вход
        case отказ(String)
    }

    /// api/brief.php ответила ok — кнопка «Разбор объявления» есть.
    @Published private(set) var доступен = false
    @Published private(set) var рынок: РынокРазбора? = nil
    /// chip: "low", "same" или пусто.
    @Published private(set) var чип = ""
    @Published private(set) var доводы: Доводы = .нет
    /// Дверь доводов ответила off — раздела доводов нет до перезапуска приложения.
    @Published private(set) var доводыВыключены = false

    /// off двери доводов за этот запуск: другие объявления раздел уже не показывают.
    private static var доводыОтключеныЗаЗапуск = false
    /// Дверь рынка ответила off (или её нет) — до этого времени следующие объявления её не спрашивают (15 минут).
    private static var рынокВыключенДо: Date? = nil
    private var номер = ""
    private var задача: Task<Void, Never>? = nil

    init() {
        доводыВыключены = Self.доводыОтключеныЗаЗапуск || !Config.доводыИИРазбора
    }

    /// Цена по рынку и метка — один раз на объявление; другой номер (листание) — заново.
    func загрузить(_ новый: String) async {
        guard Config.разборОбъявления, !новый.isEmpty, новый != номер else { return }
        номер = новый
        задача?.cancel()
        доступен = false
        рынок = nil
        чип = ""
        доводы = .нет
        /* Дверь недавно ответила off (может, на другой странице) — не спрашиваем; метка прошлого объявления уже стёрта. */
        if let до = Self.рынокВыключенДо, до > Date() { return }
        let итог = await РазборОбъявленияAPI.рынок(новый)
        /* Страница ушла до ответа (.task отменён) — номер забываем: следующий показ спросит дверь снова. */
        guard номер == новый, !Task.isCancelled else {
            if номер == новый { номер = "" }
            return
        }
        switch итог {
        case .готово(let пришло, let метка):
            рынок = пришло
            чип = метка
            withAnimation(ДвижениеСайта.появление) { доступен = true }
        case .выключено:
            Self.рынокВыключенДо = Date().addingTimeInterval(15 * 60)
        case .сеть:
            /* Нет сети — следующий показ страницы спросит снова. */
            номер = ""
        }
    }

    /// «Разобрать с ИИ» — только по нажатию человека; повтор после отказа — тем же.
    func попроситьДоводы() {
        guard !номер.isEmpty, доводы != .грузим, !доводыВыключены else { return }
        let товар = номер
        let свой = СвойИИМодель.shared.активен
        withAnimation(ДвижениеСайта.смена) { доводы = .грузим }
        задача = Task { @MainActor [weak self] in
            let ответ = await РазборОбъявленияAPI.доводы(товар, свой: свой)
            guard let self, !Task.isCancelled, self.номер == товар else { return }
            self.принять(ответ)
        }
    }

    private func принять(_ ответ: [String: Any]?) {
        typealias A = РазборОбъявленияAPI
        guard let j = ответ else {
            показать(.отказ(ТекстыРазбора.т("br_ai_net")))
            return
        }
        if A.да(j["ok"]) {
            let пришло = ДоводыРазбора(j)
            if пришло.пусто {
                показать(.отказ(ТекстыРазбора.т("br_ai_fail")))
            } else {
                ОткликСайта.успех()
                показать(.готово(пришло))
            }
            return
        }
        if A.да(j["off"]) {
            Self.доводыОтключеныЗаЗапуск = true
            withAnimation(ДвижениеСайта.смена) {
                доводыВыключены = true
                доводы = .нет
            }
            return
        }
        /* Отказ своего ИИ — окно с действиями (настройки, выключить свой ИИ); под кнопкой — его текст. */
        if let отказ = ОкноСвоегоИИ.показатьЕслиОтказ(j) {
            показать(.отказ(отказ.текст))
            return
        }
        let нужно = A.строка(j["need"]) ?? ""
        if нужно == "auth" || A.строка(j["error"]) == "auth" {
            показать(.вход)
            return
        }
        /* need:"paid" — без кнопок покупки и без текста сервера о ценах (в приложении цифровое не продаём). */
        if нужно == "paid" {
            показать(.отказ(ТекстыРазбора.т("br_ai_paid")))
            return
        }
        показать(.отказ(A.текстДляЧеловека(j) ?? ТекстыРазбора.т("br_ai_fail")))
    }

    private func показать(_ новое: Доводы) {
        withAnimation(ДвижениеСайта.смена) { доводы = новое }
    }
}

// MARK: - Метка у цены и кнопка под ней

/// «Ниже рынка на 12%» / «На уровне рынка» — только по полю chip сервера.
struct ЧипРынкаОбъявления: View {
    let чип: String
    let разница: Double?

    init(чип: String, разница: Double?) {
        self.чип = чип
        self.разница = разница
    }

    static func есть(_ чип: String) -> Bool { чип == "low" || чип == "same" }

    /// Текст метки; другой chip — nil.
    static func текст(чип: String, разница: Double?) -> String? {
        switch чип {
        case "low":
            let процентов = Int(abs(разница ?? 0).rounded())
            return процентов > 0 ? String(format: ТекстыРазбора.т("br_low"), процентов) : ТекстыРазбора.т("br_low_plain")
        case "same":
            return ТекстыРазбора.т("br_same")
        default:
            return nil
        }
    }

    var body: some View {
        if let текст = Self.текст(чип: чип, разница: разница) {
            let ниже = чип == "low"
            HStack(spacing: 5) {
                Image(systemName: ниже ? "arrow.down.right" : "equal")
                    .font(.system(size: 11, weight: .heavy))
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ниже ? Theme.зелёный2 : Theme.текстВторой)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(ниже ? Theme.оттенокАкцента : Theme.поверхность2, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(ниже ? Theme.зелёный2.opacity(0.28) : Theme.линия, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Что сделать окну, когда лист «Разбора» уедет.
enum ПослеРазбора: Equatable {
    /// Вопрос из «Что спросить продавца» — в строку ввода чата.
    case вопрос(String)
    /// Главная кнопка окна (купить, арендовать, заказать…).
    case главное
    case связаться
    case вход
}

/**
 «Разбор объявления» под ценой: светлая капсула с искрой; нажатие — лист разбора. Его кнопки зовут само окно
 (ВестиОкнаОбъявления): вопрос — в чат, «Купить безопасно» — главная кнопка панели; новых путей к оплате нет.
 */
struct КнопкаРазбораОбъявления: View {
    let товар: Listing
    @ObservedObject private var модель: МодельРазбораОбъявления
    @State private var открыт = false
    @State private var после: ПослеРазбора? = nil
    @State private var искра = false

    init(товар: Listing, модель: МодельРазбораОбъявления) {
        self.товар = товар
        _модель = ObservedObject(wrappedValue: модель)
    }

    var body: some View {
        Button { открыт = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .symbolEffect(.pulse, options: .repeat(2), value: искра)
                    .accessibilityHidden(true)
                Text(ТекстыРазбора.т("br_btn"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                LinearGradient(colors: [Theme.оттенокАкцента, Theme.поверхность2],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Theme.зелёный2.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.95))
        .accessibilityHint(ТекстыРазбора.т("br_btn_sub"))
        .onAppear {
            if !ДвижениеСайта.тихо { искра = true }
        }
        .sheet(isPresented: $открыт, onDismiss: { выполнитьПосле() }) {
            ЛистРазбораОбъявления(товар: товар, модель: модель) { что in
                после = что
                открыт = false
            }
        }
    }

    /// Лист уехал — то, что он попросил: панель окна делает это своими кнопками.
    private func выполнитьПосле() {
        guard let что = после else { return }
        после = nil
        switch что {
        case .вопрос(let текст):
            ВестиОкнаОбъявления.послать(ВестиОкнаОбъявления.чат, товар: товар.id, текст: текст)
        case .главное:
            ВестиОкнаОбъявления.послать(ВестиОкнаОбъявления.главное, товар: товар.id)
        case .связаться:
            ВестиОкнаОбъявления.послать(ВестиОкнаОбъявления.связаться, товар: товар.id)
        case .вход:
            if !ОкнаПриложения.shared.показать(.вход, задержка: 150_000_000) { ВходПоверх.показать() }
        }
    }
}
