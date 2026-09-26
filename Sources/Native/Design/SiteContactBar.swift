import SwiftUI
import UIKit

/**
 НИЖНЯЯ ПАНЕЛЬ ОБЪЯВЛЕНИЯ КАК НА САЙТЕ — ЭТАП 29 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Образец — .mk-mstickybar страницы объявления на телефоне (mkOpenModal в js/marketplace.min.js, .mk-stickyone и .mk-sb-*
 в css/marketplace.min.css): тёмно-зелёная «пилюля» со скруглением 18 — слева значок в светлом квадрате и две строки,
 справа, на затемнённой части, круглые «Позвонить» (белый 16 %) и WhatsApp (#25d366).

 КАКАЯ НАДПИСЬ — ПРАВИЛО САЙТА (W = mkIsService(r) ? A : «Предложить цену», иначе et — «Связаться»):
   · не услуга — «Предложить цену» / «Торг — ответ придёт в чат»;
   · услуга — кнопка гаранта A, если она есть: «Арендовать безопасно» у посуточной аренды без цены продажи, «Купить
     безопасно», если цена не ниже MK_ESCROW_MIN (20 000 ₸ на странице сайта), продавец проверен и не отказался от
     гаранта (no_escrow); иначе A пуста — «Связаться» / «Чат, звонок или WhatsApp».
 «Предложить цену» и «Связаться» открывают нативный чат с продавцом (ЧатЦель.продавец) — ответ на торг сайт тоже шлёт в
 чат; без нативной отправки — страницу объявления сайта. Гарант живёт только на сайте — его кнопка открывает страницу.
 Этап 38 (Config.чатОбъявления): как у сайта — чат объявления chat.php (ЧатЦель.объявление): «Предложить цену» —
 mkOfferOpen, то есть чат и сразу окно предложения цены; «Связаться» и круглая кнопка чата — mkChatOpen. Выключен —
 прежний диалог dm.php.

 ЗВОНОК И WHATSAPP — ТЕМ ЖЕ ЗАПРОСОМ, ЧТО САЙТ. mkContactGo → mkRevealCall / mkRevealWa → mkGetContact:
 fetch(_MKB+"marketplace.php?contact="+id, {method:"POST", body: JSON.stringify({csrf:_MKP_CSRF})}), _MKB = "/" (_ULX_BASE
 пуст). Ответ {ok, tel, disp, wa} — «tel:» из цифр и «+» и wa-ссылка с текстом «Здравствуйте! Интересует «…» за … ₸. Ещё
 актуально?»; {need_reg, msg} — нужен вход; {hidden, reason} — продавец скрыл номер («need_deal» — до оплаты сделки).
 Запрос идёт с куками веб-сессии и CSRF загруженной страницы (window._MKP_CSRF, запасной — KlikoCsrf), как чат (ChatAPI).
 Токена нет — страница не загружена — открываем объявление на сайте: там кнопка сработает сама. Кнопки видны, только
 если сайт их показал бы: has_phone и contact.call.ok / contact.wa.ok; нет ни одной — круглая кнопка чата. Вне режима
 работы звонок и WhatsApp не открываются (mkHoursGateModal) — окно «Звонок — в рабочее время».
 */
struct ПанельСвязиСайта: View {
    let товар: Listing
    let открыть: (URL) -> Void
    @State private var ждём: Канал? = nil
    @State private var окно: ОкноСвязи? = nil

    enum Канал { case звонок, whatsApp }

    init(товар: Listing, открыть: @escaping (URL) -> Void) {
        self.товар = товар
        self.открыть = открыть
    }

    var body: some View {
        HStack(spacing: 0) {
            главнаяЧасть
                .frame(maxHeight: .infinity)
            быстрыеКнопки
                .frame(maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .shadow(color: Theme.панельСвязиКонец.opacity(0.55), radius: 14, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.22), radius: 3, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(alignment: .top) { ПодложкаПанелиСвязи() }
        .alert(окно?.заголовок ?? "", isPresented: Binding(get: { окно != nil }, set: { if !$0 { окно = nil } }),
               presenting: окно) { о in
            if о.регистрация, let вход = Config.url("/cabinet.php") {
                Button(ListingPageText.т("reg")) { зарегистрироваться(вход) }
            }
            Button(ListingPageText.т(о.регистрация ? "later" : "ok"), role: .cancel) {}
        } message: { о in
            Text(о.текст)
        }
    }

    /// Свой экран входа и регистрации листом поверх вкладок, когда алерт уедет; слоя окон нет — страница сайта.
    private func зарегистрироваться(_ вход: URL) {
        if !ОкнаПриложения.shared.показать(.вход, задержка: 400_000_000, запасной: вход) { открыть(вход) }
    }

    // MARK: - Главная часть

    private enum Главная {
        case предложитьЦену
        case связаться
        /// Кнопка гаранта сайта — ключ подписи («buy_safe», «rent_safe»).
        case гарант(String)
    }

    /// Правило сайта для W / A / et (см. описание выше).
    private var главная: Главная {
        guard товар.услуга else { return .предложитьЦену }
        if товар.ценаАренды != nil { return .гарант("rent_safe") }
        let цена = товар.price ?? 0
        let нижеГаранта = цена > 0 && цена < Self.минимумГаранта
        if нижеГаранта || товар.безГаранта || !товар.продавецПроверен { return .связаться }
        return .гарант("buy_safe")
    }

    /// MK_ESCROW_MIN страницы сайта: ниже этой цены гаранта нет.
    private static let минимумГаранта: Double = 20_000

    /// Диалог с продавцом по объявлению — тот же маршрут, что «Написать» (этап 3). nil — нативной отправки нет.
    private var чат: ЧатЦель? {
        guard Config.нативныйЧат && Config.нативныйЧатОтправка, let продавец = товар.продавецID else { return nil }
        return ЧатЦель.продавец(id: продавец, имя: товар.продавец ?? "", объявление: товар.id)
    }

    /// Этап 38: куда ведёт кнопка чата — чат объявления сайта (chat.php) или, без него, диалог dm.php. предложить — это
    /// «Предложить цену»: чат откроется с окном предложения, как mkOfferOpen.
    private func цельЧата(предложить: Bool) -> ЧатЦель? {
        if Config.нативныйЧат && Config.чатОбъявления {
            return ЧатЦель.объявление(товар, предложить: предложить)
        }
        return чат
    }

    @ViewBuilder
    private var главнаяЧасть: some View {
        switch главная {
        case .предложитьЦену:
            кЧату(значок: "tag", заголовок: ListingPageText.т("offer"), подпись: ListingPageText.т("offer_sub"),
                  предложить: true)
        case .связаться:
            кЧату(значок: "message", заголовок: ListingPageText.т("contact"), подпись: ListingPageText.т("contact_sub"),
                  предложить: false)
        case .гарант(let ключ):
            Button {
                if let адрес = товар.адрес { открыть(адрес) }
            } label: {
                ПодписьПанелиСвязи(значок: "checkmark.shield", заголовок: ListingPageText.т(ключ), подпись: nil)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityHint(ListingPageText.т("on_site"))
        }
    }

    /// «Предложить цену» / «Связаться»: нативный чат, без него — страница объявления на сайте.
    @ViewBuilder
    private func кЧату(значок: String, заголовок: String, подпись: String, предложить: Bool) -> some View {
        if let цель = цельЧата(предложить: предложить) {
            NavigationLink(value: цель) {
                ПодписьПанелиСвязи(значок: значок, заголовок: заголовок, подпись: подпись)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        } else {
            Button {
                if let адрес = товар.адрес { открыть(адрес) }
            } label: {
                ПодписьПанелиСвязи(значок: значок, заголовок: заголовок, подпись: подпись)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityHint(ListingPageText.т("on_site"))
        }
    }

    // MARK: - Круглые кнопки (.mk-sb-quick)

    private var быстрыеКнопки: some View {
        HStack(spacing: 8) {
            if товар.звонок {
                круг(.звонок)
            }
            if товар.whatsApp {
                круг(.whatsApp)
            }
            if !товар.звонок && !товар.whatsApp {
                кругЧата
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        /* Без своей подложки и черты: тёмный прямоугольник за кругами читался «квадратиком» на зелёной пилюле
           (владелец 26.09.2026, TestFlight) — панель одна цельная, как у сайта, круги лежат прямо на ней. */
    }

    private func круг(_ канал: Канал) -> some View {
        Button {
            Task { await связаться(канал) }
        } label: {
            ZStack {
                if ждём == канал {
                    ProgressView()
                        .tint(Color.white)
                } else if канал == .звонок {
                    Image(systemName: "phone")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.white)
                } else {
                    ЗнакWhatsApp()
                }
            }
            .frame(width: 44, height: 44)
            .background(канал == .звонок ? Color.white.opacity(0.16) : Theme.whatsApp, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(канал == .звонок ? 0.28 : 0.35), Color.clear],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1)
            }
            .shadow(color: канал == .whatsApp ? Theme.whatsApp.opacity(0.6) : Color.clear, radius: 7, x: 0, y: 5)
            .contentShape(Circle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
        .disabled(ждём != nil)
        .accessibilityLabel(ListingPageText.т(канал == .звонок ? "call" : "wa"))
    }

    /// Ни звонка, ни WhatsApp — круглая кнопка чата (.mk-sb-chat), как у сайта.
    @ViewBuilder
    private var кругЧата: some View {
        let значок = Image(systemName: "message")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color.white)
            .frame(width: 44, height: 44)
            .background(Color.white.opacity(0.16), in: Circle())
            .contentShape(Circle())
        if let цель = цельЧата(предложить: false) {
            NavigationLink(value: цель) { значок }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
                .accessibilityLabel(ListingPageText.т("chat"))
        } else {
            Button {
                if let адрес = товар.адрес { открыть(адрес) }
            } label: {
                значок
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
            .accessibilityLabel(ListingPageText.т("chat"))
            .accessibilityHint(ListingPageText.т("on_site"))
        }
    }

    // MARK: - Звонок и WhatsApp

    private func связаться(_ канал: Канал) async {
        guard ждём == nil else { return }
        /* mkContactGo: вне часов работы номер не открывается — окно с часами приёма звонков. */
        if !товар.открытоСейчас() {
            let часы = товар.текстЧасов.map { "\n\n" + String(format: ListingPageText.т("hours_accepts"), $0) } ?? ""
            окно = ОкноСвязи(заголовок: ListingPageText.т("hours_gate_t"), текст: ListingPageText.т("hours_gate_b") + часы,
                             регистрация: false)
            return
        }
        ждём = канал
        defer { ждём = nil }
        КонтактыПродавца.отметить(канал == .звонок ? "call" : "msg", объявление: товар.id)
        let итог = await КонтактыПродавца.получить(товар.id)
        switch итог {
        case .номер(let tel, let wa):
            if канал == .звонок {
                let цифры = tel.filter { $0 == "+" || $0.isNumber }
                if !цифры.isEmpty, let адрес = URL(string: "tel:" + цифры) {
                    _ = await UIApplication.shared.open(адрес)
                } else {
                    окно = ОкноСвязи(заголовок: ListingPageText.т("num_unavail"), текст: "", регистрация: false)
                }
            } else if let адрес = ссылкаWhatsApp(wa) {
                _ = await UIApplication.shared.open(адрес)
            } else {
                окно = ОкноСвязи(заголовок: ListingPageText.т("contact_unavail"), текст: "", регистрация: false)
            }
        case .нуженВход(let текст):
            окно = ОкноСвязи(заголовок: ListingPageText.т("gate_account_t"),
                             текст: текст ?? ListingPageText.т("gate_account_b"), регистрация: true)
        case .скрыт(let причина):
            let сделка = причина == "need_deal"
            окно = ОкноСвязи(заголовок: ListingPageText.т(сделка ? "gate_deal_t" : "gate_phone_t"),
                             текст: ListingPageText.т(сделка ? "gate_deal_b" : "gate_phone_b"), регистрация: false)
        case .недоступно:
            окно = ОкноСвязи(заголовок: ListingPageText.т(канал == .звонок ? "num_unavail" : "contact_unavail"),
                             текст: "", регистрация: false)
        case .нетСессии:
            /* Страница сайта не загружена — токена нет. Там же, на странице объявления, кнопка сработает сама. */
            if let адрес = товар.адрес { открыть(адрес) }
        }
    }

    /// wa-ссылка сайта без её текста и с нашим: o.wa.split("?")[0] + "?text=" + encodeURIComponent(r).
    private func ссылкаWhatsApp(_ wa: String?) -> URL? {
        guard let wa, let основа = wa.split(separator: "?").first.map(String.init),
              var части = URLComponents(string: основа),
              let схема = части.scheme?.lowercased(), схема == "https" || схема == "whatsapp" else { return nil }
        let цена = товар.price.map { ListingCard.тенге($0) } ?? ListingCard.цена(товар)
        let текст = String(format: ListingPageText.т("wa_text"), товар.title, цена)
        части.queryItems = [URLQueryItem(name: "text", value: текст)]
        return части.url
    }
}

/// Окно после нажатия на звонок или WhatsApp: нужен вход, номер скрыт, вне часов, недоступно.
struct ОкноСвязи {
    let заголовок: String
    let текст: String
    /// Нужен вход — кнопка «Зарегистрироваться» (кабинет сайта).
    let регистрация: Bool
}

/// Левая часть пилюли: значок в светлом квадрате 34 pt (.so-ic) и две строки (.so-tx) на своём градиенте.
private struct ПодписьПанелиСвязи: View {
    let значок: String
    let заголовок: String
    let подпись: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.clear],
                                                     startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(заголовок)
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(-0.16)
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let строка = подпись {
                    Text(строка)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.панельСвязиНачало, Theme.кнопкаСвязиКонец],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(alignment: .top) {
            Color.white.opacity(0.22)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Под пилюлей — поверхность страницы, сверху она гаснет в прозрачность (.mk-mstickybar::before): текст, уходящий под
/// панель, не обрывается краем.
private struct ПодложкаПанелиСвязи: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.поверхность.opacity(0), Theme.поверхность], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            Theme.поверхность
        }
        .padding(.top, -12)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Знак WhatsApp: у SF Symbols его нет — пузырь-кольцо с хвостиком внизу слева и трубка внутри, как SVG сайта.
struct ЗнакWhatsApp: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 1.9)
                .frame(width: 18, height: 18)
            ХвостПузыря()
                .fill(Color.white)
            Image(systemName: "phone.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

private struct ХвостПузыря: Shape {
    func path(in r: CGRect) -> Path {
        var путь = Path()
        путь.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.68))
        путь.addLine(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.97))
        путь.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.minY + r.height * 0.87))
        путь.closeSubpath()
        return путь
    }
}

// MARK: - Запрос номера (mkGetContact сайта)

enum КонтактыПродавца {
    enum Итог {
        case номер(tel: String, wa: String?)
        case нуженВход(String?)
        case скрыт(String?)
        case недоступно
        /// Нет CSRF — страница сайта не загружена.
        case нетСессии
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    /// POST /marketplace.php?contact=<номер> с {csrf} и куками веб-сессии — ровно как mkGetContact.
    @MainActor
    static func получить(_ объявление: String) async -> Итог {
        guard let csrf = await токен() else { return .нетСессии }
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("marketplace.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "contact", value: объявление)]
        guard let адрес = ч?.url else { return .недоступно }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.httpBody = try? JSONSerialization.data(withJSONObject: ["csrf": csrf])
        guard let результат = try? await сессия.data(for: запрос) else { return .недоступно }
        let (данные, ответ) = результат
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        if код == 401 || код == 403 { return .нуженВход(nil) }
        guard let поля = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return .недоступно }
        if да(поля["need_reg"]) { return .нуженВход(строка(поля["msg"])) }
        if да(поля["hidden"]) { return .скрыт(строка(поля["reason"])) }
        guard да(поля["ok"]) else { return .недоступно }
        return .номер(tel: строка(поля["tel"]) ?? "", wa: строка(поля["wa"]))
    }

    /// mkTrackEv сайта: GET /marketplace.php?ev=call|msg&id=<номер> — счётчик обращений у продавца. Ответ не нужен.
    static func отметить(_ событие: String, объявление: String) {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("marketplace.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "ev", value: событие), URLQueryItem(name: "id", value: объявление)]
        guard let адрес = ч?.url else { return }
        Task { @MainActor in
            var запрос = URLRequest(url: адрес)
            запрос.httpShouldHandleCookies = false
            for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
            _ = try? await сессия.data(for: запрос)
        }
    }

    /// CSRF загруженной страницы: _MKP_CSRF витрины (им подписывает mkGetContact), запасной — KlikoCsrf моста. С этапа 35
    /// — общий геттер SiteSession.csrf(), тот же, что у чата и избранного.
    @MainActor
    private static func токен() async -> String? {
        await SiteSession.csrf()
    }

    private static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private static func строка(_ значение: Any?) -> String? {
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = значение as? NSNumber { return n.stringValue }
        return nil
    }
}
