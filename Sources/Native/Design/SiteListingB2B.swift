import SwiftUI

/**
 «СЧЁТ ДЛЯ ЮРЛИЦА» НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ — mkB2bBtn / mkB2bOpen сайта, своим листом.

 Кнопка — у объявления с b2b, если продавец известен и это не я (MK_ME). Сайт ставит её после «Способов оплаты» перед
 чертой продавца (у оптового объявления — внутри блока «Оптовые условия», которого у приложения нет, — там же).
 Поток, как у сайта:
   · POST cabinet.php?action=b2b_seller_goods {csrf, seller_id} → goods[{id, title, price, no_price, stock, wholesale,
     tiers[{qty, price}]}], seller{name, bin}; пусто — «У продавца нет товаров для заказа»;
   · позиции с галочкой и количеством (не больше склада), цена опта по ступеням (_mkB2bPrice), итог «N поз. · M шт.»
     и «скидка по объёму»; позиция без цены — «Узнать цену» (страница того объявления);
   · «Сформировать счёт» — POST b2b_order_create {csrf, seller_id, items[{item_id, qty}], vat_on}; need_company — форма
     реквизитов (POST save_company {csrf, company{name, bin}}, затем снова b2b_order_create); ok — «Счёт выписан»
     с реквизитами продавца из order{no, total, valid_until, seller{name, bin, iik, bank, bik}}.
 vat_on — 0: у вошедшего сайт НДС не берёт (_mkB2bVat остаётся {payer: 0}). Гость у сайта получает счёт по ссылке
 (api/guest_invoice.php) — в приложении вместо этого свой вход: ссылка вела бы на страницу сайта. Деньги не двигаются —
 это счёт для банковского перевода.
 */
struct КнопкаСчётаЮрлица: View {
    let товар: Listing
    let открыть: ((URL) -> Void)?
    @ObservedObject private var сессия = СессияПриложения.shared
    @State private var лист = false

    init(товар: Listing, открыть: ((URL) -> Void)?) {
        self.товар = товар
        self.открыть = открыть
    }

    /// mkB2bBtn: t.b2b и seller_id; «не я» — в body (сессия меняется).
    static func есть(_ товар: Listing) -> Bool {
        товар.поляВида.b2b && !(товар.продавецID ?? "").isEmpty
    }

    private var продавец: String { товар.продавецID ?? "" }

    var body: some View {
        if !продавец.isEmpty && продавец != сессия.id {
            Button {
                нажали()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(ТекстыСчётаИОбмена.т("b2b_order_cta"))
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(Theme.зелёный2)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.зелёный2, lineWidth: 1.6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .sheet(isPresented: $лист) {
                ЛистСчётаЮрлица(продавец: продавец, объявление: товар.id, открыть: открыть)
            }
        }
    }

    private func нажали() {
        guard сессия.вошёл == true else {
            if !ОкнаПриложения.shared.показать(.вход) { ВходПоверх.показать() }
            return
        }
        лист = true
    }
}

// MARK: - Данные

/// Ступень опта: от штук — цена.
struct СтупеньОптаСчёта: Equatable {
    let штук: Int
    let цена: Double
}

/// Позиция продавца для счёта (goods[] ответа b2b_seller_goods).
struct ПозицияСчёта: Identifiable, Equatable {
    let id: String
    let название: String
    let цена: Double
    let безЦены: Bool
    let склад: Int
    let опт: Bool
    let ступени: [СтупеньОптаСчёта]

    init?(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        название = A.строка(j["title"])
        цена = A.число(j["price"])
        безЦены = A.да(j["no_price"])
        склад = A.целое(j["stock"])
        опт = A.да(j["wholesale"])
        let сырые = (j["tiers"] as? [[String: Any]]) ?? []
        ступени = сырые.map { СтупеньОптаСчёта(штук: A.целое($0["qty"]), цена: A.число($0["price"])) }
    }

    /// _mkB2bPrice: у опта — цена последней ступени, до которой дотянуло количество.
    func ценаЗа(_ штук: Int) -> Double {
        guard опт else { return цена }
        var итог = цена
        for ступень in ступени where штук >= ступень.штук && ступень.цена > 0 {
            итог = ступень.цена
        }
        return итог
    }

    /// Не меньше одной и не больше склада (data-max), если склад указан.
    func вПределах(_ штук: Int) -> Int {
        let снизу = max(1, штук)
        return склад > 0 ? min(снизу, склад) : снизу
    }
}

/// Выписанный счёт (order ответа b2b_order_create).
struct ЗаказСчёта: Equatable {
    var номер = ""
    var сумма: Double = 0
    var получатель = ""
    var бин = ""
    var счёт = ""
    var банк = ""
    var бик = ""
    var оплатитьДо = ""

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        номер = A.строка(j["no"])
        сумма = A.число(j["total"])
        let п = (j["seller"] as? [String: Any]) ?? [:]
        получатель = A.строка(п["name"])
        бин = A.строка(п["bin"])
        счёт = A.строка(п["iik"])
        банк = A.строка(п["bank"])
        бик = A.строка(п["bik"])
        оплатитьДо = Self.дата(A.строка(j["valid_until"]))
    }

    /// toLocaleDateString("ru-RU"): «05.10.2026».
    private static func дата(_ строка: String) -> String {
        guard !строка.isEmpty else { return "" }
        var найдена = СделкиФормат.дата(строка)
        if найдена == nil {
            let ф = DateFormatter()
            ф.locale = Locale(identifier: "en_US_POSIX")
            ф.dateFormat = "yyyy-MM-dd"
            найдена = ф.date(from: String(строка.prefix(10)))
        }
        guard let д = найдена else { return "" }
        let вывод = DateFormatter()
        вывод.locale = Locale(identifier: "ru_RU")
        вывод.dateFormat = "dd.MM.yyyy"
        return вывод.string(from: д)
    }
}

/// Итог отмеченного (mkB2bCalc).
struct ИтогСчётаЮрлица {
    var позиций = 0
    var штук = 0
    var сумма: Double = 0
    var скидка: Double = 0
}

// MARK: - Модель

@MainActor
final class МодельСчётаЮрлица: ObservableObject {
    enum Шаг: Equatable {
        case загрузка
        case позиции
        case реквизиты
        case готово
        /// Счёт выписать нечего или сайт отказал — текст по центру.
        case пусто(String)
        /// Сессии нет (auth / csrf).
        case вход
    }

    @Published private(set) var шаг: Шаг = .загрузка
    @Published private(set) var позиции: [ПозицияСчёта] = []
    /// .mk-b2b-co: «Название · БИН …».
    @Published private(set) var компания = ""
    @Published private(set) var отмечены: Set<String> = []
    @Published private(set) var штуки: [String: Int] = [:]
    @Published var название = ""
    @Published var бин = ""
    @Published private(set) var занято = false
    @Published private(set) var сообщение: String? = nil
    @Published private(set) var заказ = ЗаказСчёта()

    let продавец: String
    let объявление: String

    private typealias A = МоиОбъявленияAPI

    init(продавец: String, объявление: String) {
        self.продавец = продавец
        self.объявление = объявление
    }

    private func т(_ ключ: String) -> String { ТекстыСчётаИОбмена.т(ключ) }

    var итог: ИтогСчётаЮрлица {
        var и = ИтогСчётаЮрлица()
        for п in позиции where отмечены.contains(п.id) && !п.безЦены {
            let n = п.вПределах(штуки[п.id] ?? 1)
            let цена = п.ценаЗа(n)
            и.позиций += 1
            и.штук += n
            и.сумма += цена * Double(n)
            и.скидка += (п.цена - цена) * Double(n)
        }
        return и
    }

    func отметить(_ п: ПозицияСчёта) {
        guard !п.безЦены else { return }
        if отмечены.contains(п.id) {
            отмечены.remove(п.id)
        } else {
            отмечены.insert(п.id)
        }
    }

    func изменить(_ п: ПозицияСчёта, на шаг: Int) {
        штуки[п.id] = п.вПределах((штуки[п.id] ?? 1) + шаг)
    }

    func штук(_ п: ПозицияСчёта) -> Int { п.вПределах(штуки[п.id] ?? 1) }

    /// mkB2bOpen.
    func загрузить() async {
        шаг = .загрузка
        do {
            let j = try await A.отправить("cabinet.php?action=b2b_seller_goods", тело: ["seller_id": продавец])
            guard A.да(j["ok"]) else {
                let код = A.строка(j["error"])
                шаг = код == "auth" || код == "csrf" ? .вход : .пусто(текстОшибки(j))
                return
            }
            let готовые = ((j["goods"] as? [[String: Any]]) ?? []).compactMap { ПозицияСчёта($0) }
            guard !готовые.isEmpty else {
                шаг = .пусто(т("b2b_no_goods"))
                return
            }
            позиции = готовые
            if let п = j["seller"] as? [String: Any] {
                let имя = A.строка(п["name"])
                let номер = A.строка(п["bin"])
                компания = номер.isEmpty ? имя : имя + " · " + т("b2b_bin") + " " + номер
            }
            /* Своё объявление отмечено сразу (o = n.id === t). */
            if let своя = готовые.first(where: { $0.id == объявление && !$0.безЦены }) {
                отмечены = [своя.id]
            }
            шаг = .позиции
        } catch {
            шаг = .пусто(т("no_conn"))
        }
    }

    /// mkB2bSend.
    func выписать() async {
        let строки: [[String: Any]] = позиции.filter { отмечены.contains($0.id) && !$0.безЦены }.map { п in
            ["item_id": п.id, "qty": self.штук(п)] as [String: Any]
        }
        guard !строки.isEmpty else {
            показать(т("b2b_pick"))
            return
        }
        guard !занято else { return }
        занято = true
        defer { занято = false }
        do {
            let тело: [String: Any] = ["seller_id": продавец, "items": строки, "vat_on": 0]
            let j = try await A.отправить("cabinet.php?action=b2b_order_create", тело: тело)
            if A.да(j["ok"]) {
                заказ = ЗаказСчёта((j["order"] as? [String: Any]) ?? [:])
                шаг = .готово
            } else if A.да(j["need_company"]) {
                шаг = .реквизиты
            } else {
                let код = A.строка(j["error"])
                if код == "auth" || код == "csrf" {
                    шаг = .вход
                } else {
                    показать(текстОшибки(j))
                }
            }
        } catch {
            показать(т("no_conn"))
        }
    }

    /// mkB2bReqSave: название и 12 цифр БИН/ИИН → save_company → снова счёт.
    func сохранитьРеквизиты() async {
        let имя = название.trimmingCharacters(in: .whitespacesAndNewlines)
        let цифры = String(бин.filter { $0.isASCII && $0.isNumber })
        guard !имя.isEmpty else {
            показать(т("b2b_req_need_name"))
            return
        }
        guard цифры.count == 12 else {
            показать(т("b2b_req_need_bin"))
            return
        }
        guard !занято else { return }
        занято = true
        let ответ: [String: Any]
        do {
            let компанияТело: [String: Any] = ["name": имя, "bin": цифры]
            ответ = try await A.отправить("cabinet.php?action=save_company", тело: ["company": компанияТело])
        } catch {
            занято = false
            показать(т("no_conn"))
            return
        }
        занято = false
        guard A.да(ответ["ok"]) else {
            показать(текстОшибки(ответ))
            return
        }
        шаг = .позиции
        await выписать()
    }

    func назад() {
        шаг = .позиции
    }

    private func текстОшибки(_ j: [String: Any]) -> String {
        ИнбоксAPI.текстОшибки(j, запасной: т("err_generic"))
    }

    private func показать(_ текст: String) {
        сообщение = текст
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, self.сообщение == текст else { return }
            self.сообщение = nil
        }
    }
}

// MARK: - Лист

struct ЛистСчётаЮрлица: View {
    @StateObject private var модель: МодельСчётаЮрлица
    let открыть: ((URL) -> Void)?
    @Environment(\.dismiss) private var закрыть

    init(продавец: String, объявление: String, открыть: ((URL) -> Void)?) {
        _модель = StateObject(wrappedValue: МодельСчётаЮрлица(продавец: продавец, объявление: объявление))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ТекстыСчётаИОбмена.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                шапка
                содержимое
                if let сообщение = модель.сообщение {
                    Text(сообщение)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.скидкаТекст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .листСКнопкойВнизу { низ }
        .task { await модель.загрузить() }
    }

    private var заголовок: String {
        switch модель.шаг {
        case .реквизиты: return т("b2b_req_title")
        case .готово:
            let номер = модель.заказ.номер
            return номер.isEmpty ? т("b2b_done_title") : т("b2b_done_title") + " №" + номер
        default: return т("b2b_sheet_title")
        }
    }

    private var шапка: some View {
        HStack(alignment: .top) {
            Text(заголовок)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            КнопкаЗакрытьМеста { закрыть() }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.шаг {
        case .загрузка:
            SiteSpinner()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .пусто(let текст):
            подпись(текст)
                .padding(.vertical, 8)
        case .вход:
            подпись(т("b2b_login"))
                .padding(.vertical, 8)
        case .позиции:
            списокПозиций
        case .реквизиты:
            формаРеквизитов
        case .готово:
            готово
        }
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Позиции (.mk-kp-list)

    private var списокПозиций: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !модель.компания.isEmpty {
                Text(модель.компания)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            подпись(т("b2b_sheet_sub"))
            VStack(spacing: 8) {
                ForEach(модель.позиции) { п in строкаПозиции(п) }
            }
            итогСчёта
        }
    }

    private func строкаПозиции(_ п: ПозицияСчёта) -> some View {
        let отмечена = модель.отмечены.contains(п.id)
        return HStack(spacing: 10) {
            Button {
                модель.отметить(п)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: п.безЦены ? "circle.dashed" : (отмечена ? "checkmark.square.fill" : "square"))
                        .font(.system(size: 20))
                        .foregroundStyle(отмечена ? Theme.зелёный2 : Theme.текстВторой)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(п.название)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        ценаПозиции(п)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(п.безЦены)
            .accessibilityAddTraits(отмечена ? .isSelected : [])
            if п.безЦены {
                Button {
                    узнатьЦену(п)
                } label: {
                    Text(т("b2b_ask_btn"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(Theme.зелёный2, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            } else {
                количество(п)
                    .opacity(отмечена ? 1 : 0.5)
            }
        }
        .padding(10)
        .background(отмечена ? Theme.мята : Theme.поверхность2,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    @ViewBuilder
    private func ценаПозиции(_ п: ПозицияСчёта) -> some View {
        if п.безЦены {
            Text(т("b2b_price_ask"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
        } else {
            let цена = п.ценаЗа(модель.штук(п))
            HStack(spacing: 6) {
                Text(СделкиФормат.тенге(Int(цена.rounded())))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(цена < п.цена ? Theme.зелёный2 : Theme.текст)
                if п.склад > 0 {
                    Text(т("b2b_in_stock") + " " + String(п.склад))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                }
                if п.опт && !п.ступени.isEmpty {
                    Text(т("b2b_has_tiers"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                }
            }
        }
    }

    /// .mk-kp-qty: − число ＋.
    private func количество(_ п: ПозицияСчёта) -> some View {
        HStack(spacing: 0) {
            Button {
                модель.изменить(п, на: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("−")
            Text(String(модель.штук(п)))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .frame(minWidth: 26)
            Button {
                модель.изменить(п, на: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("+")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.текст)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// #mk-b2b-sum.
    @ViewBuilder
    private var итогСчёта: some View {
        let и = модель.итог
        if и.позиций > 0 {
            VStack(spacing: 6) {
                строкаИтога(String(и.позиций) + " " + т("b2b_pos") + " · " + String(и.штук) + " " + т("pcs"),
                            СделкиФормат.тенге(Int(и.сумма.rounded())), цвет: Theme.текст)
                if и.скидка > 0 {
                    строкаИтога(т("b2b_saved"), "−" + СделкиФормат.тенге(Int(и.скидка.rounded())), цвет: Theme.зелёный2)
                }
            }
            .padding(.top, 4)
        } else {
            строкаИтога(т("b2b_pick"), "", цвет: Theme.текстВторой)
                .padding(.top, 4)
        }
    }

    private func строкаИтога(_ подпись: String, _ значение: String, цвет: Color) -> some View {
        HStack {
            Text(подпись)
                .font(.system(size: 13))
                .foregroundStyle(цвет == Theme.текст ? Theme.текстВторой : цвет)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(цвет)
        }
    }

    // MARK: Реквизиты (mkB2bReqForm)

    private var формаРеквизитов: some View {
        VStack(alignment: .leading, spacing: 12) {
            подпись(т("b2b_req_sub"))
            поле(т("b2b_req_name"), текст: $модель.название, образец: т("b2b_name_ph"), цифры: false)
            поле(т("b2b_req_bin"), текст: $модель.бин, образец: т("b2b_bin_ph"), цифры: true)
        }
    }

    private func поле(_ подпись: String, текст: Binding<String>, образец: String, цифры: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(подпись)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
            TextField(образец, text: текст)
                .keyboardType(цифры ? .numberPad : .default)
                .textInputAutocapitalization(цифры ? .never : .sentences)
                .autocorrectionDisabled()
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .onChange(of: текст.wrappedValue) { _, новое in
                    /* maxlength: 12 цифр у БИН, 200 знаков у названия. */
                    let предел = цифры ? 12 : 200
                    if новое.count > предел { текст.wrappedValue = String(новое.prefix(предел)) }
                }
        }
    }

    // MARK: Готово (mkB2bDone)

    private var готово: some View {
        let з = модель.заказ
        return VStack(alignment: .leading, spacing: 10) {
            Text(СделкиФормат.тенге(Int(з.сумма.rounded())))
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(Theme.текст)
            подпись(т("b2b_done_sub"))
            VStack(spacing: 6) {
                строкаРеквизита(т("b2b_pay_to"), з.получатель)
                строкаРеквизита(т("b2b_bin"), з.бин)
                строкаРеквизита(т("b2b_iik"), з.счёт)
                строкаРеквизита(т("b2b_bank"), з.банк)
                строкаРеквизита(т("b2b_bik"), з.бик)
                строкаРеквизита(т("b2b_pay_by"), з.оплатитьДо)
            }
            .padding(12)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
    }

    @ViewBuilder
    private func строкаРеквизита(_ подпись: String, _ значение: String) -> some View {
        if !значение.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(подпись)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Text(значение)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: Низ листа

    @ViewBuilder
    private var низ: some View {
        switch модель.шаг {
        case .загрузка:
            EmptyView()
        case .пусто:
            главнаяКнопка(т("close")) { закрыть() }
        case .вход:
            главнаяКнопка(т("login_btn")) { войти() }
        case .позиции:
            главнаяКнопка(модель.занято ? т("b2b_sending") : т("b2b_send"), занято: модель.занято) {
                Task { await модель.выписать() }
            }
        case .реквизиты:
            VStack(spacing: 6) {
                главнаяКнопка(модель.занято ? т("b2b_saving") : т("b2b_req_save"), занято: модель.занято) {
                    Task { await модель.сохранитьРеквизиты() }
                }
                втораяКнопка(т("b2b_back")) { модель.назад() }
            }
        case .готово:
            VStack(spacing: 6) {
                главнаяКнопка(т("b2b_done_ok")) { закрыть() }
                втораяКнопка(т("b2b_to_docs")) { вДокументы() }
            }
        }
    }

    private func главнаяКнопка(_ подпись: String, занято: Bool = false,
                               действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.зелёный2.opacity(занято ? 0.6 : 1),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(занято)
    }

    private func втораяКнопка(_ подпись: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.зелёный2)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func войти() {
        закрыть()
        if !ОкнаПриложения.shared.показать(.вход, задержка: 400_000_000) { ВходПоверх.показать() }
    }

    /// mkB2bAsk: позиция без цены — её объявление (там чат с продавцом); своё — оно уже под листом.
    private func узнатьЦену(_ п: ПозицияСчёта) {
        закрыть()
        guard п.id != модель.объявление, let адрес = Config.url("/?item=" + п.id) else { return }
        открыть?(адрес)
    }

    /// «Открыть в «Документах»» — cabinet.php?s=company (свой экран «Счета»).
    private func вДокументы() {
        закрыть()
        if let адрес = Config.url("/cabinet.php?s=company") { открыть?(адрес) }
    }
}
