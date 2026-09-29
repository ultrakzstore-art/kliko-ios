import SwiftUI
import UIKit

/**
 СОЗДАНИЕ СДЕЛКИ И КОДЫ ИЗ ССЫЛОК (этап 44, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 🔴 Только за Config.деньгиСделок (false): без рубильника АдресаКабинета эти ссылки не разбирает, и они открывают
 страницу кабинета сайта, как раньше.

 Ссылки кабинета, которые сайт разбирает сам при загрузке (карта §4.8, §4.21):
   · ?start_deal=<pid>[&pay=<метод>][&term=<мес>] — chat.php?action=widget_data (только чтение) → «Нужна верификация»
     (escrowNeedVerify) или окно «Безопасная сделка» / «Бронь через задаток» / «Аренда с залогом» с шагами, суммами и
     сбором mkDealFee → «Оформить сделку» → ход «Создаём безопасную сделку» → escrow.php?action=create {product_id,
     hold_type:"full", amount (задаток и аренда), pay_method, pay_term} → «Мои сделки», вкладка «Я покупатель», карточка;
     need_terms — окно «Условия обновились» (этап 40), потом «Оформить» ещё раз нажатием;
   · ?start_service=<pid> — «Заказать через гаранта» (openServiceOrder): сумма, аванс 0–50 % шагом 5, что сделать (до 500
     знаков), срок → create {kind:"service", amount, advance_pct, scope, deadline};
   · ?meet=<qr> (QR встречи с экрана продавца) и ?parcel=<token> (листок в коробке) — сайт сразу шлёт meet_scan /
     parcel_open {token}; это подтверждение получения и выплата продавцу, поэтому здесь сперва «Вы точно получили товар?».
 Системная камера открывает эти адреса универсальной ссылкой — отдельный сканер приложению не нужен (при живой проверке:
 открывает ли iOS /kz/<язык>/cabinet.php?meet= приложением, а не Safari, — это файл apple-app-site-association сайта).
 */

// MARK: - Слой «Моих сделок»: задания из ссылок

struct СлойЗаданийСделок: ViewModifier {
    let открыть: (URL) -> Void

    @State private var лист: ЛистЗадания? = nil
    @State private var код: КодИзСсылки? = nil
    @State private var итогКода: String? = nil
    @State private var шлёмКод = false

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    enum ЛистЗадания: Identifiable {
        case сделка(товар: String, оплата: String, срок: Int)
        case услуга(товар: String)

        var id: String {
            switch self {
            case .сделка(let товар, _, _): return "deal-" + товар
            case .услуга(let товар): return "service-" + товар
            }
        }
    }

    struct КодИзСсылки: Equatable, Identifiable {
        let встреча: Bool
        let токен: String

        var id: String { токен }
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    func body(content: Content) -> some View {
        content
            .sheet(item: $лист) { л in
                switch л {
                case .сделка(let товар, let оплата, let срок):
                    ОкноНовойСделки(товар: товар, оплата: оплата, срок: срок, открыть: открыть, создана: { создана($0) })
                case .услуга(let товар):
                    ОкноЗаказаУслуги(товар: товар, открыть: открыть, создана: { создана($0) })
                }
            }
            /* «Вы точно получили товар?» — код отпускает деньги продавцу: оформленным листом, как вопросы о деньгах. */
            .background {
                Color.clear
                    .sheet(item: $код) { к in
                        ОкноВопросаДенег(вопрос: .код(""), слова: словаКода, подтвердить: { подтвердитьКод(к) },
                                         отмена: { код = nil })
                    }
            }
            .alert(итогКода ?? "", isPresented: итогНаЭкране) {
                Button(СделкиText.т("hnd_lock_ok"), role: .cancel) {}
            }
            .onAppear { забрать() }
            .onReceive(NotificationCenter.default.publisher(for: ЗаданияДенегСделок.пришло)) { _ in забрать() }
    }

    private var словаКода: ДеньгиСделкиМодель.ТекстВопроса {
        ДеньгиСделкиМодель.ТекстВопроса(заголовок: т("pin_b_ask"), текст: т("pin_b_ask_m"), кнопка: т("pin_b_ask_ok"),
                                        опасная: false, толькоПонятно: false)
    }

    /// Лист уезжает, потом — запрос (после него может открыться карточка сделки).
    private func подтвердитьКод(_ к: КодИзСсылки) {
        код = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { отправитьКод(к) }
    }

    private var итогНаЭкране: Binding<Bool> {
        Binding(get: { итогКода != nil }, set: { показан in
            if !показан { итогКода = nil }
        })
    }

    private func забрать() {
        guard Config.деньгиСделок else { return }
        let задание = ЗаданияДенегСделок.shared.забрать { з in
            if case .шлюз = з { return false }
            return true
        }
        guard let задание else { return }
        switch задание {
        case .сделка(let товар, let оплата, let срок):
            лист = .сделка(товар: товар, оплата: оплата, срок: срок)
        case .услуга(let товар):
            лист = .услуга(товар: товар)
        case .код(let встреча, let токен):
            код = КодИзСсылки(встреча: встреча, токен: токен)
        case .шлюз:
            break
        }
    }

    /// Сделка создана: «Мои сделки» на вкладке «Я покупатель» и её карточка (showDeals, dealsTab("buyer"), openDeal).
    private func создана(_ номер: String) {
        лист = nil
        СделкиМодель.shared.выбрать(.buyer)
        СделкиМодель.shared.рольПриОткрытии = .buyer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NativeRouter.shared.цель = .сделка(id: номер)
        }
    }

    /**
     meet_scan / parcel_open {token} — один раз, после «Да, вещь у меня». ok — «Получение подтверждено…» /
     «Вскрытие подтверждено…» и карточка сделки (deal_id); иначе message или hovErr(error), как у сайта.
     */
    private func отправитьКод(_ к: КодИзСсылки) {
        guard !шлёмКод else { return }
        шлёмКод = true
        Task { @MainActor in
            defer { шлёмКод = false }
            do {
                let хвост = к.встреча ? "chat.php?action=meet_scan" : "chat.php?action=parcel_open"
                let j = try await ДеньгиСделкиAPI.отправитьОдинРаз(хвост, тело: ["token": к.токен])
                if СделкиAPI.да(j["ok"]) {
                    итогКода = т(к.встреча ? "meet_ok" : "prc_opened")
                    let номер = СделкиAPI.строка(j["deal_id"])
                    if СделкиAPI.годныйНомер(номер) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            NativeRouter.shared.цель = .сделка(id: номер)
                        }
                    }
                    return
                }
                let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                итогКода = m.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : m
            } catch {
                итогКода = СделкиText.т("err_no_conn")
            }
        }
    }
}

// MARK: - Модель создания (widget_data → create)

@MainActor
final class НоваяСделкаМодель: ObservableObject {
    /// product и seller ответа widget_data.
    struct Товар: Equatable {
        var название: String = ""
        var фото: String = ""
        var вид: String = "goods"
        var цена: Int = 0
        var полная: Int = 0
        var заморозка: Int = 0
        var продавец: String = ""
        /// ship_free: доставку оплачивает продавец.
        var доставкаБесплатно = false
    }

    enum Этап: Equatable {
        case загрузка
        case ошибка(String)
        case верификация
        case готово(Товар)
    }

    struct Условия: Identifiable {
        let id = UUID()
        let редакция: String
        let пункты: [String]
    }

    @Published private(set) var этап: Этап = .загрузка
    @Published private(set) var ход: ХодДенег? = nil
    @Published var условия: Условия? = nil
    @Published var сообщение: String? = nil
    @Published private(set) var ставки = СтавкиСделки()
    @Published private(set) var идёт = false
    /// «Как получить» и «Куда привезти» (только товар) — своя модель, её окно наблюдает отдельно.
    let доставка: ДоставкаНовойСделки

    init() {
        доставка = ДоставкаНовойСделки()
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    /// GET chat.php?action=widget_data&pid= (только чтение) и ставки сбора со страницы кабинета.
    /// безГаранта — текст, если у товара гаранта нет (no_escrow: пауза гаранта, «без гаранта», запчасти): так делает
    /// ?start_deal= сайта — одна строка вместо окна со сбором и кнопкой, от которой сервер откажет. Услуга не проверяет.
    func загрузить(товар: String, нетТовара: String, безГаранта: String? = nil) async {
        этап = .загрузка
        do {
            guard let j = try await ДеньгиСделкиAPI.получить("chat.php?action=widget_data&pid=" + СделкиAPI.вАдрес(товар)),
                  СделкиAPI.да(j["ok"]), let p = j["product"] as? [String: Any] else {
                этап = .ошибка(нетТовара)
                return
            }
            if let безГаранта, СделкиAPI.да(j["no_escrow"]) {
                этап = .ошибка(безГаранта)
                return
            }
            if let страница = try? await КабинетСайта.страницаКабинета() {
                ставки = СтавкиСделки.изСтраницы(страница.html)
            }
            let покупатель = (j["buyer"] as? [String: Any]) ?? [:]
            if !СделкиAPI.да(покупатель["verified"]) {
                этап = .верификация
                return
            }
            let готовый = Self.разобрать(p, продавец: (j["seller"] as? [String: Any]) ?? [:])
            этап = .готово(готовый)
            if готовый.вид == "goods" {
                await доставка.начать(товар: товар, бесплатная: готовый.доставкаБесплатно)
            }
        } catch {
            этап = .ошибка(т("ep_conn"))
        }
    }

    private static func разобрать(_ p: [String: Any], продавец s: [String: Any]) -> Товар {
        typealias A = СделкиAPI
        var т = Товар()
        let название = A.строка(p["title"])
        т.название = название.isEmpty ? A.строка(p["model"]) : название
        т.фото = A.строка(p["img"])
        let вид = A.строка(p["mode"])
        т.вид = вид.isEmpty ? "goods" : вид
        т.цена = A.целое(p["price"])
        /* null!=r.full_price сайта: нет поля или null — цена. */
        let полная = p["full_price"]
        let заморозка = p["freeze_amount"]
        т.полная = (полная == nil || полная is NSNull) ? т.цена : A.целое(полная)
        т.заморозка = (заморозка == nil || заморозка is NSNull) ? т.цена : A.целое(заморозка)
        т.продавец = A.строка(s["name"])
        т.доставкаБесплатно = A.да(p["ship_free"])
        return т
    }

    /**
     create — один раз, по нажатию. ok → номер сделки; need_terms → окно соглашения (после него — снова нажатие);
     need_verification → message или «Нужна верификация»; иначе «Ошибка: <error|запасной>».
     */
    func создать(тело: [String: Any], заголовок: String, шаги: [ШагХода], готово: String, запасной: String,
                 создана: @escaping (String) -> Void) {
        guard !идёт else { return }
        идёт = true
        сообщение = nil
        Task { @MainActor in
            defer { self.идёт = false }
            self.ход = ХодДенег(заголовок: заголовок, подпись: self.т("ep_wait"), процент: 0)
            let запрос = Task { @MainActor () async throws -> [String: Any] in
                try await ДеньгиСделкиAPI.отправитьОдинРаз("escrow.php?action=create", тело: тело)
            }
            for шаг in шаги {
                self.ход?.процент = шаг.процент
                self.ход?.подпись = шаг.текст
                try? await Task.sleep(nanoseconds: шаг.мс * 1_000_000)
            }
            let j: [String: Any]
            do {
                j = try await запрос.value
            } catch {
                j = ["ok": false, "error": "", "message": self.т("ep_conn")]
            }
            await ЗапускХода.итог(j, готово: готово, ход: { self.ход = $0 }, закрыт: { false })
            self.ход = nil
            let номер = СделкиAPI.строка((j["deal"] as? [String: Any])?["id"])
            if СделкиAPI.да(j["ok"]) && !номер.isEmpty {
                создана(номер)
                return
            }
            if СделкиAPI.да(j["need_terms"]) {
                let с = try? await КабинетСайта.состояние()
                self.условия = Условия(редакция: с?.редакция ?? "", пункты: с?.чтоИзменилось ?? [])
                return
            }
            if МоиОбъявленияAPI.нетСессии(j) {
                self.сообщение = ТекстыОшибокСделки.текст("auth")
                return
            }
            let e = СделкиAPI.строка(j["error"])
            let m = СделкиAPI.строка(j["message"])
            if e == "ship_quote" && self.доставка.включена {
                /* Цена доставки устарела (или пункт выдачи не подходит) — как mkEcoPay: текст и новый расчёт. */
                self.сообщение = self.доставка.ценаУстарела(причина: СделкиAPI.строка(j["reason"]))
                return
            }
            if e == "need_verification" {
                self.сообщение = m.isEmpty ? self.т("sd_need_ver") : m
                return
            }
            if !m.isEmpty && e.isEmpty {
                self.сообщение = m
                return
            }
            self.сообщение = ДеньгиСделкиAPI.ошибка(e.isEmpty ? запасной : e)
        }
    }
}

// MARK: - Общие куски окон создания

/// «Нужна верификация» (escrowNeedVerify): «Пройти верификацию» — страница сайта (этап 46), «Позже».
struct НужнаВерификацияСделки: View {
    let пройти: () -> Void
    let позже: () -> Void

    var body: some View {
        let т: (String) -> String = ДеньгиСделкиText.т
        VStack(spacing: 14) {
            Image(systemName: "person.badge.shield.checkmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.зелёный)
                .accessibilityHidden(true)
            Text(т("nv_t"))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.текст)
            ТекстСделки.сЖирным(т("nv_m"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            КнопкаСделки(т("nv_go"), вид: .главная, символ: "checkmark.shield", наСайт: true) { пройти() }
            КнопкаСделки(т("nv_later"), вид: .тихая) { позже() }
        }
        .padding(20)
    }
}

/// Строка «подпись — сумма» итогов.
struct СтрокаСуммыСделки: View {
    let подпись: String
    let значение: String
    var главная = false

    var body: some View {
        HStack {
            Text(подпись)
                .foregroundStyle(главная ? Theme.текст : Theme.текстВторой)
                .fontWeight(главная ? .bold : .regular)
            Spacer(minLength: 8)
            Text(значение)
                .fontWeight(главная ? .heavy : .bold)
                .foregroundStyle(главная ? Theme.зелёный : Theme.текст)
        }
        .font(.system(size: главная ? 16 : 14))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Безопасная сделка» (?start_deal=)

struct ОкноНовойСделки: View {
    let товар: String
    let оплата: String
    let срок: Int
    let открыть: (URL) -> Void
    let создана: (String) -> Void

    @StateObject private var модель = НоваяСделкаМодель()
    @Environment(\.dismiss) private var закрыть
    /// Окно карты «Куда доставить».
    @State private var точкаДоставки: ТочкаНаКартеСделки? = nil

    init(товар: String, оплата: String, срок: Int, открыть: @escaping (URL) -> Void, создана: @escaping (String) -> Void) {
        self.товар = товар
        self.оплата = оплата
        self.срок = срок
        self.открыть = открыть
        self.создана = создана
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    var body: some View {
        /* Лист по высоте содержимого (.mk-eco-box сайта): без пустого низа; закрыть — крестиком в углу. */
        ScrollView {
            содержимое
                .padding(.bottom, 8)
                .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(СделкиText.т("close"))
        }
        .overlay {
            if let ход = модель.ход { ХодДенегВид(ход: ход, закрыть: {}) }
        }
        .background {
            Color.clear
                .sheet(item: $модель.условия) { у in
                    ОкноСоглашения(редакция: у.редакция, пункты: у.пункты, принято: { модель.условия = nil },
                                   выйти: { модель.условия = nil }, нуженВход: { модель.условия = nil })
                }
        }
        .background {
            Color.clear
                .sheet(item: $точкаДоставки) { цель in
                    ЛистТочкиСделки(цель: цель, модель: nil, выбрано: { модель.доставка.выбран($0) })
                }
        }
        .листПоВысоте()
        .task { await модель.загрузить(товар: товар, нетТовара: т("sd_nf"), безГаранта: т("esc_paused_t")) }
    }

    /// «Изменить адрес»: окно карты без сделки — адрес уходит в расчёт доставки и в create.
    private func изменитьАдрес() {
        let а = модель.доставка.адрес
        var дверь = ДверьСделки()
        if let д = а?.дверь {
            дверь.уПодъезда = СделкиAPI.да(д["out"])
            дверь.квартира = СделкиAPI.строка(д["flat"])
            дверь.подъезд = СделкиAPI.строка(д["porch"])
            дверь.этаж = СделкиAPI.строка(д["floor"])
            дверь.домофон = СделкиAPI.строка(д["code"])
            дверь.комментарий = СделкиAPI.строка(д["note"])
        }
        точкаДоставки = ТочкаНаКартеСделки(сторона: "to", адрес: а?.текст ?? "", точка: а?.точка, дверь: дверь)
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.этап {
        case .загрузка:
            SiteSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .ошибка(let текст):
            Text(текст)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .верификация:
            НужнаВерификацияСделки(пройти: { пройтиВерификацию() }, позже: { закрыть() })
        case .готово(let т):
            ПодтверждениеНовойСделки(товар: т, ставки: модель.ставки, доставка: модель.доставка,
                                     сообщение: модель.сообщение, идёт: модель.идёт,
                                     изменитьАдрес: { изменитьАдрес() }, оформить: { оформить(т) })
        }
    }

    private func пройтиВерификацию() {
        закрыть()
        if let адрес = Config.страницаСайта("cabinet.php?go=verify") { открыть(адрес) }
    }

    /// create: amount — только у задатка и аренды; pay_method и pay_term — только если пришли в ссылке.
    private func оформить(_ т: НоваяСделкаМодель.Товар) {
        var тело: [String: Any] = ["product_id": товар, "hold_type": "full"]
        if т.вид == "deposit" || т.вид == "rent" { тело["amount"] = т.заморозка }
        if !оплата.isEmpty { тело["pay_method"] = оплата }
        if срок > 0 { тело["pay_term"] = срок }
        if т.вид == "goods" {
            /* Доставка, как mkEcoPay сайта: не посчитана или межгород без ТК — сначала подсказка, create не уходит. */
            if let ошибка = модель.доставка.ошибкаПередОформлением() {
                модель.сообщение = ошибка
                return
            }
            модель.доставка.дополнить(&тело)
        }
        let шаги: [ШагХода] = [ШагХода(текст: self.т("sd_ep_s1"), процент: 35, мс: 750),
                               ШагХода(текст: self.т("sd_ep_s2"), процент: 75, мс: 700)]
        модель.создать(тело: тело, заголовок: self.т("sd_ep_t"), шаги: шаги, готово: self.т("sd_ep_ok"),
                       запасной: self.т("sd_fail"), создана: создана)
    }
}

/// Содержимое окна подтверждения ?start_deal=: товар, «Как проходит сделка», суммы, метки, кнопка.
struct ПодтверждениеНовойСделки: View {
    let товар: НоваяСделкаМодель.Товар
    let ставки: СтавкиСделки
    @ObservedObject var доставка: ДоставкаНовойСделки
    let сообщение: String?
    let идёт: Bool
    let изменитьАдрес: () -> Void
    let оформить: () -> Void

    init(товар: НоваяСделкаМодель.Товар, ставки: СтавкиСделки, доставка: ДоставкаНовойСделки, сообщение: String?,
         идёт: Bool, изменитьАдрес: @escaping () -> Void, оформить: @escaping () -> Void) {
        self.товар = товар
        self.ставки = ставки
        self.доставка = доставка
        self.сообщение = сообщение
        self.идёт = идёт
        self.изменитьАдрес = изменитьАдрес
        self.оформить = оформить
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    private var задаток: Bool { товар.вид == "deposit" }
    private var аренда: Bool { товар.вид == "rent" }
    private var приставка: String { задаток ? "d" : (аренда ? "r" : "g") }
    private var сбор: Int { ставки.сбор(товар.заморозка) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(т(задаток ? "sd_t_dep" : (аренда ? "sd_t_rent" : "sd_t_goods")))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            шапка
            Text(т("sd_how").uppercased())
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.зелёный)
            ForEach(1...3, id: \.self) { n in
                HStack(alignment: .top, spacing: 10) {
                    Text(String(n))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Theme.зелёный)
                        .frame(width: 28, height: 28)
                        .background(КраскаСделокКабинета.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        .accessibilityHidden(true)
                    ТекстСделки.сЖирным(т("sd_" + приставка + String(n)))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if доставка.включена {
                БлокДоставкиНовойСделки(доставка: доставка, изменитьАдрес: изменитьАдрес)
            }
            суммы
            МеткиГарантииСделки(подписи: [1, 2, 3].map { т("sd_c_" + приставка + String($0)) })
            if let ошибка = сообщение {
                ЗаметкаСделки(Text(ошибка), вид: .плохо, символ: "exclamationmark.triangle")
            }
            КнопкаСделки(т(задаток ? "sd_go_dep" : (аренда ? "sd_go_rent" : "sd_go_goods")), вид: .главная,
                         символ: "lock.shield", доступна: !идёт) { оформить() }
        }
        .padding(20)
    }

    private var шапка: some View {
        HStack(spacing: 12) {
            КартинкаЛенты(Config.url(товар.фото), пунктов: 52) {
                Theme.поверхность2
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(товар.название)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                (Text((товар.продавец.isEmpty ? "—" : товар.продавец) + " · ")
                 + Text(СделкиФормат.тенге(товар.цена)).bold().foregroundColor(Theme.зелёный))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    private var суммы: some View {
        VStack(spacing: 6) {
            СтрокаСуммыСделки(подпись: т(задаток ? "sd_dep" : (аренда ? "sd_pledge" : "sd_price")),
                               значение: СделкиФормат.тенге(товар.заморозка))
            if задаток {
                СтрокаСуммыСделки(подпись: т("sd_full"), значение: СделкиФормат.тенге(товар.полная))
            }
            СтрокаСуммыСделки(подпись: т("sd_fee"), значение: "+" + СделкиФормат.тенге(сбор))
            if доставка.цена > 0 {
                /* #mk-eco-shiprow: цена выбранной доставки входит в сумму к заморозке. */
                СтрокаСуммыСделки(подпись: доставка.подписьЦены, значение: "+" + СделкиФормат.тенге(доставка.цена))
            }
            Divider()
            СтрокаСуммыСделки(подпись: т("sd_total"), значение: СделкиФормат.тенге(товар.заморозка + сбор + доставка.цена),
                               главная: true)
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

// MARK: - «Заказать через гаранта» (?start_service=, openServiceOrder)

struct ОкноЗаказаУслуги: View {
    let товар: String
    let открыть: (URL) -> Void
    let создана: (String) -> Void

    @StateObject private var модель = НоваяСделкаМодель()
    @Environment(\.dismiss) private var закрыть
    @State private var сумма = ""
    @State private var аванс: Double = 0
    @State private var что = ""
    @State private var сроком = false
    @State private var когда = Date()

    init(товар: String, открыть: @escaping (URL) -> Void, создана: @escaping (String) -> Void) {
        self.товар = товар
        self.открыть = открыть
        self.создана = создана
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    /// parseInt сайта; цифры арабской клавиатуры — тоже.
    private var суммаЧислом: Int {
        Int(сумма.compactMap { $0.wholeNumberValue }.map { String($0) }.joined().prefix(12)) ?? 0
    }

    private var процент: Int { Int(аванс.rounded()) }

    var body: some View {
        /* Лист по высоте содержимого, закрыть — крестиком в углу (как окно «Безопасная сделка»). */
        ScrollView {
            содержимое
                .padding(20)
                .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(СделкиText.т("close"))
        }
        .overlay {
            if let ход = модель.ход { ХодДенегВид(ход: ход, закрыть: {}) }
        }
        .sheet(item: $модель.условия) { у in
            ОкноСоглашения(редакция: у.редакция, пункты: у.пункты, принято: { модель.условия = nil },
                           выйти: { модель.условия = nil }, нуженВход: { модель.условия = nil })
        }
        .листПоВысоте()
        .task { await модель.загрузить(товар: товар, нетТовара: т("so_nf")) }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.этап {
        case .загрузка:
            SiteSpinner()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .ошибка(let текст):
            Text(текст)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        case .верификация:
            НужнаВерификацияСделки(пройти: {
                закрыть()
                if let адрес = Config.страницаСайта("cabinet.php?go=verify") { открыть(адрес) }
            }, позже: { закрыть() })
        case .готово(let т):
            форма(т)
        }
    }

    private func форма(_ товарУслуги: НоваяСделкаМодель.Товар) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(т("so_t"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text((товарУслуги.название.isEmpty ? т("so_svc") : товарУслуги.название) + " · "
                 + (товарУслуги.продавец.isEmpty ? т("so_exec") : товарУслуги.продавец))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
            ЗаметкаСделки(ТекстСделки.сЖирным(т("so_info")), вид: .инфо, символ: "lock.shield")
            поля
            итоги
            if let сообщение = модель.сообщение {
                ЗаметкаСделки(Text(сообщение), вид: .плохо, символ: "exclamationmark.triangle")
            }
            КнопкаСделки(т("so_send"), вид: .главная, символ: "paperplane", доступна: !модель.идёт) { отправить() }
            Text(т("so_send_s"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private var поля: some View {
        VStack(alignment: .leading, spacing: 12) {
            полеСуммы
            полеРаботы
        }
    }

    @ViewBuilder
    private var полеСуммы: some View {
        подпись(т("so_amount"))
        TextField(т("so_amount_ph"), text: $сумма)
            .keyboardType(.numberPad)
            .modifier(ПолеДенегСделки())
        ПодписьСделки(т("so_amount_s"))
        HStack {
            подпись(т("so_adv"))
            Spacer(minLength: 8)
            Text(String(процент) + "% · " + СделкиФормат.тенге(Int((Double(суммаЧислом) * Double(процент) / 100).rounded())))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.зелёный)
        }
        Slider(value: $аванс, in: 0...50, step: 5)
            .tint(Theme.акцент)
            .accessibilityLabel(т("a11y_adv"))
            .accessibilityValue(String(процент) + "%")
        ПодписьСделки(т("so_adv_s"))
    }

    @ViewBuilder
    private var полеРаботы: some View {
        подпись(т("so_scope"))
        TextField(т("so_scope_ph"), text: $что, axis: .vertical)
            .lineLimit(3...6)
            .modifier(ПолеДенегСделки())
            .onChange(of: что) { _, новое in
                if новое.count > 500 { что = String(новое.prefix(500)) }
            }
        Toggle(isOn: $сроком) {
            (Text(т("so_dl")).bold() + Text(" " + т("so_opt")).foregroundColor(Theme.текстВторой))
                .font(.system(size: 14))
        }
        .tint(Theme.зелёный)
        .accessibilityLabel(т("a11y_deadline"))
        if сроком {
            DatePicker(т("so_dl"), selection: $когда, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.compact)
        }
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.текст)
    }

    private var итоги: some View {
        let сбор = модель.ставки.сбор(суммаЧислом)
        return VStack(spacing: 6) {
            СтрокаСуммыСделки(подпись: т("so_sum"), значение: СделкиФормат.тенге(суммаЧислом))
            СтрокаСуммыСделки(подпись: т("so_fee"), значение: "+" + СделкиФормат.тенге(сбор))
            Divider()
            СтрокаСуммыСделки(подпись: т("so_total"), значение: СделкиФормат.тенге(суммаЧислом + сбор), главная: true)
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// Пустая сумма — «Укажите согласованную сумму»; срок — «YYYY-MM-DD» или пусто, как input type=date сайта.
    private func отправить() {
        let n = суммаЧислом
        guard n >= 1 else {
            модель.сообщение = т("so_need_amount")
            return
        }
        var срок = ""
        if сроком {
            let ф = DateFormatter()
            ф.locale = Locale(identifier: "en_US_POSIX")
            ф.calendar = Calendar(identifier: .gregorian)
            ф.dateFormat = "yyyy-MM-dd"
            срок = ф.string(from: когда)
        }
        let тело: [String: Any] = ["product_id": товар, "kind": "service", "amount": n, "advance_pct": процент,
                                   "scope": что.trimmingCharacters(in: .whitespacesAndNewlines), "deadline": срок]
        let шаги: [ШагХода] = [ШагХода(текст: т("so_ep_s1"), процент: 40, мс: 700),
                               ШагХода(текст: т("so_ep_s2"), процент: 80, мс: 650)]
        модель.создать(тело: тело, заголовок: т("so_ep_t"), шаги: шаги, готово: т("so_ep_ok"), запасной: т("so_fail"),
                       создана: создана)
    }
}
