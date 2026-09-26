import SwiftUI

/**
 ОПЛАТА, ДОСТАВКА И ЗНАКИ ДОВЕРИЯ ОПУБЛИКОВАННОГО ОБЪЯВЛЕНИЯ — СВОЁ ОКНО ВМЕСТО cabinet.php?edit=
 (владелец 26.09.2026: «всё приложение нативное»).

 У опубликованного объявления сайт правит эти настройки не мастером, а тремя окнами, и сохраняет каждое сразу
 (карта кабинета §2.4.19):
   · openPayment → POST cabinet.php?action=save_payment {csrf, item_id, installment, installment_mode "bank"|"notary",
     installment_commission (PAY_CFG 5…30, по умолчанию 10), installment_banks[], credit, credit_rate (10…50, по
     умолчанию 25), credit_banks[]} → «Способы оплаты сохранены»; нет pay_allowed — «Для этой категории
     рассрочка/кредит недоступны»;
   · openDelivery → POST save_delivery {csrf, item_id, ship_free, ship_days, ship_carrier, ship_scope "all"|"regions"|
     "city", ship_regions[]} → «Доставка сохранена»; транспортную компанию по умолчанию (ship_carrier) магазин PRO
     выбирает из chat.php?action=logistics_partners (ВыборПеревозчика, CabinetPlus/CarrierPicker.swift), остальным —
     «Только для PRO», перевозчик сохраняется как был;
   · openTrust → POST save_trust {csrf, item_id, warranty_days, trust{ключ:true}} → «Знаки доверия сохранены», ответ
     clamped — «Без PRO гарантия — до 7 дней: сохранили 7 дней».
 Здесь — одно окно с тремя блоками (какие видны — по разделу, как renderCfgRows), «Сохранить» шлёт запросы только
 изменённых блоков, по очереди. Значения — из записи my_items, которую мастер уже загрузил для правки.
 */
struct НастройкиОпубликованного: Equatable {
    var номер: String
    var название: String
    var цена: Int
    var блоки: [String]
    var знаки: [ЗнакДоверия]
    var pro: Bool
    var оплатаРазрешена: Bool

    var рассрочка: Bool
    var режимРассрочки: String
    var наценка: Double
    var банкиРассрочки: [String]
    var кредит: Bool
    var ставка: Double
    var банкиКредита: [String]

    var доставкаБесплатно: Bool
    var доставкаДней: String
    var перевозчик: String
    var куда: String
    var регионы: [String]
    var свойРегион: String

    var гарантия: Int
    var отмечено: [String]

    /// Запись my_items (showEdit сайта) → настройки окна.
    init(номер: String, запись з: [String: Any], блоки: [String], знаки: [ЗнакДоверия], pro: Bool) {
        typealias A = МоиОбъявленияAPI
        self.номер = номер
        название = A.строка(з["title"]).isEmpty ? A.строка(з["model"]) : A.строка(з["title"])
        цена = A.целое(з["price"])
        self.блоки = блоки
        self.знаки = знаки
        self.pro = pro
        /* pay_allowed не пришло — не запрещаем: решает сервер. */
        оплатаРазрешена = з["pay_allowed"] == nil || A.да(з["pay_allowed"])
        рассрочка = A.да(з["installment"])
        режимРассрочки = A.строка(з["installment_mode"]) == "notary" ? "notary" : "bank"
        let н = A.число(з["installment_commission"])
        наценка = min(30, max(5, н > 0 ? н.rounded() : 10))
        банкиРассрочки = НастройкиОпубликованного.список(з["installment_banks"])
        кредит = A.да(з["credit"])
        let с = A.число(з["credit_rate"])
        ставка = min(50, max(10, с > 0 ? с.rounded() : 25))
        банкиКредита = НастройкиОпубликованного.список(з["credit_banks"])
        доставкаБесплатно = A.да(з["ship_free"])
        доставкаДней = A.строка(з["ship_days"])
        перевозчик = A.строка(з["ship_carrier"])
        let сфера = A.строка(з["ship_scope"])
        куда = (сфера == "regions" || сфера == "city") ? сфера : "all"
        регионы = НастройкиОпубликованного.список(з["ship_regions"])
        var регион = A.строка(з["region"])
        if регион.isEmpty {
            let город = A.строка(з["city"])
            регион = ГеоДанные.регионы.first(where: { $0.название == город || $0.города.contains(город) })?.ключ ?? ""
        }
        свойРегион = регион
        гарантия = max(0, A.целое(з["warranty_days"]))
        var флаги: [String] = []
        if let доверие = з["trust"] as? [String: Any] {
            for (ключ, значение) in доверие where A.да(значение) || (значение as? Bool) == true { флаги.append(ключ) }
        }
        отмечено = флаги.sorted()
    }

    static func == (a: НастройкиОпубликованного, b: НастройкиОпубликованного) -> Bool {
        a.телоОплаты as NSDictionary == b.телоОплаты as NSDictionary
            && a.телоДоставки as NSDictionary == b.телоДоставки as NSDictionary
            && a.телоДоверия as NSDictionary == b.телоДоверия as NSDictionary
    }

    private static func список(_ значение: Any?) -> [String] {
        ((значение as? [Any]) ?? []).map { МоиОбъявленияAPI.строка($0) }.filter { !$0.isEmpty }
    }

    var телоОплаты: [String: Any] {
        ["item_id": номер, "installment": рассрочка, "installment_mode": режимРассрочки,
         "installment_commission": Int(наценка), "installment_banks": банкиРассрочки,
         "credit": кредит, "credit_rate": Int(ставка), "credit_banks": банкиКредита]
    }

    var телоДоставки: [String: Any] {
        let свои = куда == "regions" ? регионы.filter { $0 != свойРегион } : [String]()
        return ["item_id": номер, "ship_free": доставкаБесплатно, "ship_days": доставкаДней,
                "ship_carrier": перевозчик, "ship_scope": куда, "ship_regions": свои]
    }

    var телоДоверия: [String: Any] {
        var флаги: [String: Bool] = [:]
        for ключ in отмечено { флаги[ключ] = true }
        return ["item_id": номер, "warranty_days": гарантия, "trust": флаги]
    }
}

/// PAY_CFG.banks сайта — в его порядке.
private struct БанкСайта: Identifiable {
    let id: String
    let имя: String
}

private let банкиСайта: [БанкСайта] = [
    БанкСайта(id: "kaspi", имя: "Kaspi"), БанкСайта(id: "halyk", имя: "Halyk"),
    БанкСайта(id: "freedom", имя: "Freedom"), БанкСайта(id: "forte", имя: "ForteBank"),
    БанкСайта(id: "jusan", имя: "Jusan"), БанкСайта(id: "eurasian", имя: "Eurasian")
]

struct ЛистНастроекОбъявления: View {
    let исходные: НастройкиОпубликованного
    let готово: (String) -> Void
    let закрыть: () -> Void

    @State private var н: НастройкиОпубликованного
    @State private var сохраняем = false
    @State private var ошибка: String? = nil

    /// WR_STOPS сайта; без PRO — до 7 дней (WR_FREE_MAX).
    private static let сроки: [Int] = [0, 3, 7, 14, 30, 60, 90, 180, 270, 365]

    init(исходные: НастройкиОпубликованного, готово: @escaping (String) -> Void, закрыть: @escaping () -> Void) {
        self.исходные = исходные
        self.готово = готово
        self.закрыть = закрыть
        _н = State(initialValue: исходные)
    }

    /// Открыть из мастера правки (полноэкранного) — поверх него, из верхнего контроллера.
    @MainActor
    static func показать(модель: ПодачаМодель) {
        let настройки = НастройкиОпубликованного(номер: модель.номерПравки, запись: модель.исходник,
                                                  блоки: модель.строкиДополнительно, знаки: модель.знакиДоверия,
                                                  pro: модель.страница.pro)
        ПоверхВсего.показать(смахивается: false) { закрыть in
            ЛистНастроекОбъявления(исходные: настройки, готово: { текст in модель.показать(текст) }, закрыть: закрыть)
        }
    }

    private func т(_ ключ: String) -> String { НастройкиОбъявленияText.т(ключ) }

    /// «Название · 150 000 ₸», как <p> в шапке окон сайта.
    private var подзаголовок: String {
        guard н.цена > 0 else { return н.название }
        let цена = DesignText.число(н.цена) + "\u{00A0}₸"
        return н.название + " · " + цена
    }
    private func тП(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !н.название.isEmpty {
                        Text(подзаголовок)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                    }
                    if н.блоки.contains("pay") { оплата }
                    if н.блоки.contains("del") { доставка }
                    if н.блоки.contains("trust") { доверие }
                    if let ошибка {
                        Text(ошибка)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.скидкаТекст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        сохранить()
                    } label: {
                        HStack(spacing: 8) {
                            if сохраняем { SiteSpinner.белый }
                            Text(сохраняем ? т("saving") : т("save_btn"))
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .opacity(н == исходные ? 0.55 : 1)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    .disabled(сохраняем || н == исходные)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(тП("cfg_setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("cancel")) { закрыть() }
                        .disabled(сохраняем)
                }
            }
        }
        .tint(Theme.акцент)
    }

    // MARK: - Оплата (openPayment)

    @ViewBuilder
    private var оплата: some View {
        БлокНастроек(заголовок: тП("pay_methods"), значок: "wallet.pass") {
            if !н.оплатаРазрешена {
                Text(т("pay_cat_unavailable"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                Toggle(isOn: $н.рассрочка) { ПодписьНастройки(тП("pay_installment")) }
                    .tint(Theme.зелёный)
                if н.рассрочка {
                    Picker("", selection: $н.режимРассрочки) {
                        Text(тП("pay_with_bank")).tag("bank")
                        Text(т("pay_notary")).tag("notary")
                    }
                    .pickerStyle(.segmented)
                    ползунок(т("pay_markup"), значение: $н.наценка, пределы: 5...30)
                    if н.режимРассрочки == "bank" {
                        банки($н.банкиРассрочки)
                    }
                    доплата
                }
                Divider()
                Toggle(isOn: $н.кредит) { ПодписьНастройки(тП("pay_credit")) }
                    .tint(Theme.зелёный)
                if н.кредит {
                    ползунок(т("pay_annual_rate"), значение: $н.ставка, пределы: 10...50)
                    Text(т("pay_avg_rate"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                    банки($н.банкиКредита)
                }
            }
        }
    }

    /// «Покупатель доплатит <b>N ₸</b> за рассрочку…».
    private var доплата: some View {
        let сумма = Int((Double(н.цена) * н.наценка / 100).rounded())
        let жирное = Text(DesignText.число(сумма) + "\u{00A0}₸").bold()
        return (Text(т("pay_buyer_pays_a") + " ") + жирное + Text(" " + т("pay_buyer_pays_b")))
            .font(.system(size: 12))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ползунок(_ подпись: String, значение: Binding<Double>, пределы: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 4)
                Text(String(Int(значение.wrappedValue)) + "%")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.зелёный2)
            }
            Slider(value: значение, in: пределы, step: 1)
                .tint(Theme.зелёный)
                .accessibilityLabel(подпись)
                .accessibilityValue(String(Int(значение.wrappedValue)) + "%")
        }
    }

    /// payBankChips: чипы банков, выбранные — залиты.
    private func банки(_ выбранные: Binding<[String]>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(банкиСайта) { банк in
                let вкл = выбранные.wrappedValue.contains(банк.id)
                Button {
                    if вкл {
                        выбранные.wrappedValue.removeAll { $0 == банк.id }
                    } else {
                        выбранные.wrappedValue.append(банк.id)
                    }
                } label: {
                    Text(банк.имя)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(вкл ? Color.white : Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(вкл ? Theme.зелёный2 : Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(вкл ? Color.clear : Theme.линия, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(вкл ? .isSelected : [])
            }
        }
    }

    // MARK: - Доставка (openDelivery)

    private var доставка: some View {
        БлокНастроек(заголовок: тП("del_settings"), значок: "shippingbox") {
            Toggle(isOn: $н.доставкаБесплатно) {
                VStack(alignment: .leading, spacing: 3) {
                    ПодписьНастройки(тП("del_free_ship"))
                    Text(тП("del_free_note"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.зелёный)
            if н.доставкаБесплатно {
                Text(т("del_free_ya"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьНастройки(тП("del_approx_time"))
                HStack(spacing: 8) {
                    TextField(тП("del_days_ph"), text: Binding(get: { н.доставкаДней }, set: { новое in
                        н.доставкаДней = String(новое.prefix(12))
                    }))
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                    Text(тП("del_days_unit"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Divider()
            ПодписьНастройки(т("del_where_t"))
            VStack(spacing: 8) {
                вариантКуда("all", значок: "globe.asia.australia", подпись: т("del_where_all"), под: т("del_where_all_s"))
                вариантКуда("regions", значок: "map", подпись: т("del_where_regions"), под: т("del_where_regions_s"))
                вариантКуда("city", значок: "mappin.and.ellipse", подпись: т("del_where_city"), под: т("del_where_city_s"))
            }
            if н.куда == "regions" { регионы }
            Text(т("del_where_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            ВыборПеревозчика(pro: н.pro, перевозчик: $н.перевозчик)
        }
    }

    private func вариантКуда(_ ключ: String, значок: String, подпись: String, под: String) -> some View {
        let вкл = н.куда == ключ
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            н.куда = ключ
        } label: {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(вкл ? Theme.зелёный2 : Theme.текстВторой)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(подпись)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(под)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 4)
                Image(systemName: вкл ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(вкл ? Theme.зелёный2 : Theme.линия)
            }
            .padding(12)
            .background(вкл ? Theme.оттенокАкцента : Theme.поверхность, in: форма)
            .overlay {
                форма.strokeBorder(вкл ? Theme.зелёный2 : Theme.линия, lineWidth: вкл ? 1.5 : 1)
            }
            .contentShape(форма)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }

    /// Области: своя отмечена и заперта («своя»), прочие — галочки.
    private var регионы: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ГеоДанные.регионы) { регион in
                let свой = регион.ключ == н.свойРегион
                let вкл = свой || н.регионы.contains(регион.ключ)
                Button {
                    guard !свой else { return }
                    if вкл {
                        н.регионы.removeAll { $0 == регион.ключ }
                    } else {
                        н.регионы.append(регион.ключ)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: вкл ? "checkmark.square.fill" : "square")
                            .font(.system(size: 18))
                            .foregroundStyle(вкл ? Theme.зелёный2 : Theme.текстВторой)
                        Text(регион.название)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текст)
                        if свой {
                            Text(т("del_where_own"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(свой)
                .accessibilityAddTraits(вкл ? .isSelected : [])
            }
        }
    }

    // MARK: - Знаки доверия (openTrust)

    private var доверие: some View {
        let срочные = н.знаки.filter { $0.срок }
        let флажки = н.знаки.filter { !$0.срок }
        let предел = н.pro ? 365 : 7
        return БлокНастроек(заголовок: тП("wr_title"), значок: "checkmark.shield") {
            Text(тП("wr_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if let срок = срочные.first {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            ПодписьНастройки(срок.подпись == "Гарантия" ? т("wr_seller_t") : срок.подпись)
                            Text(т("wr_from_receipt"))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        Spacer(minLength: 4)
                        Text(Self.срокГарантии(н.гарантия))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(н.гарантия > 0 ? Theme.зелёный2 : Theme.текстВторой)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Self.сроки.filter { $0 <= предел }, id: \.self) { дни in
                            let вкл = н.гарантия == дни
                            Button {
                                н.гарантия = дни
                            } label: {
                                Text(Self.срокГарантии(дни))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(вкл ? Color.white : Theme.текст)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(вкл ? Theme.зелёный2 : Theme.поверхность2, in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(вкл ? Color.clear : Theme.линия, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(вкл ? .isSelected : [])
                        }
                    }
                    if !н.pro {
                        Label(тП("wr_pro_note"), systemImage: "lock")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
            }
            if !флажки.isEmpty {
                Divider()
                ПодписьНастройки(тП("wr_checks_h"))
                ForEach(флажки) { знак in
                    Toggle(isOn: флаг(знак.id)) {
                        Text(знак.подпись)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текст)
                    }
                    .tint(Theme.зелёный)
                }
            }
        }
    }

    /// warrTerm сайта: «Нет», «3 дня», «7 дней», «1 месяц», «12 месяцев» (то же правило, что у мастера подачи).
    static func срокГарантии(_ дни: Int) -> String {
        if дни <= 0 { return ПодачаText.т("wr_none") }
        let месяцы = дни == 365 ? 12 : (дни >= 30 && дни % 30 == 0 ? дни / 30 : 0)
        let число = месяцы > 0 ? месяцы : дни
        let ключ = (месяцы > 0 ? "wr_m" : "wr_d") + ПодачаText.множественное(число)
        return String(число) + " " + ПодачаText.т(ключ)
    }

    private func флаг(_ ключ: String) -> Binding<Bool> {
        Binding(get: { н.отмечено.contains(ключ) }, set: { новое in
            н.отмечено.removeAll { $0 == ключ }
            if новое { н.отмечено.append(ключ) }
        })
    }

    // MARK: - Сохранение

    /// savePayment / saveDelivery / saveTrust сайта — только изменённые блоки, по очереди. Всё удалось — окно
    /// закрывается и мастер показывает плашку; иначе ошибка остаётся здесь.
    private func сохранить() {
        guard !сохраняем else { return }
        var запросы: [(хвост: String, тело: [String: Any], готово: String)] = []
        let оплатаНовая = н.телоОплаты as NSDictionary
        if н.блоки.contains("pay") && н.оплатаРазрешена && оплатаНовая != исходные.телоОплаты as NSDictionary {
            запросы.append((хвост: "save_payment", тело: н.телоОплаты, готово: т("pay_saved")))
        }
        let доставкаНовая = н.телоДоставки as NSDictionary
        if н.блоки.contains("del") && доставкаНовая != исходные.телоДоставки as NSDictionary {
            запросы.append((хвост: "save_delivery", тело: н.телоДоставки, готово: т("del_saved")))
        }
        let доверьеНовое = н.телоДоверия as NSDictionary
        if н.блоки.contains("trust") && доверьеНовое != исходные.телоДоверия as NSDictionary {
            запросы.append((хвост: "save_trust", тело: н.телоДоверия, готово: т("wr_saved")))
        }
        guard !запросы.isEmpty else {
            закрыть()
            return
        }
        сохраняем = true
        ошибка = nil
        Task { @MainActor in
            defer { сохраняем = false }
            var итоги: [String] = []
            for запрос in запросы {
                do {
                    let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=" + запрос.хвост, тело: запрос.тело)
                    guard МоиОбъявленияAPI.да(j["ok"]) else {
                        let e = МоиОбъявленияAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                        ошибка = МоиОбъявленияAPI.нетСессии(j) ? т("login") : (e.isEmpty ? т("err_generic") : e)
                        return
                    }
                    if запрос.хвост == "save_trust" && МоиОбъявленияAPI.да(j["clamped"]) {
                        итоги.append(тП("wr_clamped"))
                    } else {
                        итоги.append(запрос.готово)
                    }
                } catch {
                    ошибка = т("err_net")
                    return
                }
            }
            закрыть()
            готово(итоги.joined(separator: " · "))
        }
    }
}

/// Карточка блока окна: значок и заголовок, под ними содержимое — .promo-card сайта в краске Theme.
private struct БлокНастроек<Содержимое: View>: View {
    let заголовок: String
    let значок: String
    @ViewBuilder let содержимое: () -> Содержимое

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 34, height: 34)
                    .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            содержимое()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
    }
}

private struct ПодписьНастройки: View {
    let текст: String

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        Text(текст)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.текст)
    }
}

/// Тексты окна. Русские — сайта (js/i18n-cabinet-ru.js): pay_notary, pay_markup, pay_annual_rate, pay_buyer_pays_a/b,
/// pay_avg_rate, pay_saved, pay_cat_unavailable, del_free_ya, del_where_*, del_saved, wr_saved, wr_seller_t,
/// wr_from_receipt, save_btn, saving, err_generic, err_net.
enum НастройкиОбъявленияText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "pay_notary": "Без банка · нотариус", "pay_markup": "Наценка за рассрочку", "pay_annual_rate": "Годовая ставка",
            "pay_buyer_pays_a": "Покупатель доплатит",
            "pay_buyer_pays_b": "за рассрочку (эта наценка покрывает комиссию банка). Вы получаете полную цену.",
            "pay_avg_rate": "Средняя по РК: 19–39% номинал, ГЭСВ до ~50%.", "pay_saved": "Способы оплаты сохранены",
            "pay_cat_unavailable": "Для этой категории рассрочка/кредит недоступны",
            "del_free_ya": "Выберет покупатель курьера Яндекса — его стоимость вычтем из вашей выплаты по сделке. Курьер дороже вашей выручки за товар не предлагается.",
            "del_where_t": "Куда отправляю", "del_where_all": "Весь Казахстан", "del_where_all_s": "отправляете в любой регион",
            "del_where_regions": "Своя область и выбранные", "del_where_regions_s": "отметьте области, куда отправляете",
            "del_where_city": "Только свой город", "del_where_city_s": "встреча, самовывоз и курьер по городу",
            "del_where_note": "Встреча и самовывоз доступны покупателю из любого региона — ограничение касается только отправки.",
            "del_where_own": "своя", "del_saved": "Доставка сохранена", "wr_saved": "Знаки доверия сохранены",
            "wr_seller_t": "Гарантия продавца", "wr_from_receipt": "срок — с даты получения товара",
            "save_btn": "Сохранить", "saving": "Сохранение…", "cancel": "Отмена", "err_generic": "Ошибка",
            "err_net": "Ошибка сети", "login": "Войдите в кабинет"
        ],
        "kk": [
            "pay_notary": "Банксіз · нотариус", "pay_markup": "Бөліп төлеу үстемесі", "pay_annual_rate": "Жылдық мөлшерлеме",
            "pay_buyer_pays_a": "Сатып алушы қосымша төлейді",
            "pay_buyer_pays_b": "бөліп төлеу үшін (бұл үстеме банк комиссиясын жабады). Сіз толық бағаны аласыз.",
            "pay_avg_rate": "ҚР бойынша орташа: номинал 19–39%, ЖТСМ ~50%-ға дейін.", "pay_saved": "Төлем тәсілдері сақталды",
            "pay_cat_unavailable": "Бұл санат үшін бөліп төлеу/несие қолжетімсіз",
            "del_free_ya": "Сатып алушы Яндекс курьерін таңдаса — оның құны мәміле бойынша төлеміңізден шегеріледі. Тауардан түскен табыстан қымбат курьер ұсынылмайды.",
            "del_where_t": "Қайда жіберемін", "del_where_all": "Бүкіл Қазақстан", "del_where_all_s": "кез келген өңірге жібересіз",
            "del_where_regions": "Өз облысым және таңдалғандар", "del_where_regions_s": "жіберетін облыстарды белгілеңіз",
            "del_where_city": "Тек өз қалам", "del_where_city_s": "кездесу, алып кету және қала ішіндегі курьер",
            "del_where_note": "Кездесу мен алып кету кез келген өңірдегі сатып алушыға қолжетімді — шектеу тек жіберуге қатысты.",
            "del_where_own": "өзім", "del_saved": "Жеткізу сақталды", "wr_saved": "Сенім белгілері сақталды",
            "wr_seller_t": "Сатушы кепілдігі", "wr_from_receipt": "мерзімі — тауарды алған күннен бастап",
            "save_btn": "Сақтау", "saving": "Сақталуда…", "cancel": "Бас тарту", "err_generic": "Қате",
            "err_net": "Желі қатесі", "login": "Кабинетке кіріңіз"
        ],
        "en": [
            "pay_notary": "No bank · notary", "pay_markup": "Installment markup", "pay_annual_rate": "Annual rate",
            "pay_buyer_pays_a": "The buyer pays an extra",
            "pay_buyer_pays_b": "for the installment plan (this markup covers the bank fee). You get the full price.",
            "pay_avg_rate": "Kazakhstan average: 19–39% nominal, APR up to ~50%.", "pay_saved": "Payment options saved",
            "pay_cat_unavailable": "Installments/credit aren't available for this category",
            "del_free_ya": "If the buyer picks a Yandex courier, its cost is deducted from your payout for the deal. A courier costing more than your revenue from the item isn't offered.",
            "del_where_t": "Where I ship", "del_where_all": "All of Kazakhstan", "del_where_all_s": "you ship to any region",
            "del_where_regions": "My region and selected ones", "del_where_regions_s": "tick the regions you ship to",
            "del_where_city": "My city only", "del_where_city_s": "meetup, pickup and city courier",
            "del_where_note": "Meetups and pickup are open to buyers from any region — the limit applies to shipping only.",
            "del_where_own": "mine", "del_saved": "Delivery saved", "wr_saved": "Trust badges saved",
            "wr_seller_t": "Seller warranty", "wr_from_receipt": "counted from the day the item is received",
            "save_btn": "Save", "saving": "Saving…", "cancel": "Cancel", "err_generic": "Error",
            "err_net": "Network error", "login": "Sign in to your account"
        ],
        "ar": [
            "pay_notary": "بدون بنك · كاتب عدل", "pay_markup": "هامش التقسيط", "pay_annual_rate": "النسبة السنوية",
            "pay_buyer_pays_a": "سيدفع المشتري إضافة",
            "pay_buyer_pays_b": "مقابل التقسيط (يغطي هذا الهامش عمولة البنك). تحصل أنت على السعر كاملًا.",
            "pay_avg_rate": "المتوسط في كازاخستان: 19–39% اسميًا، والفعلي حتى ~50%.", "pay_saved": "تم حفظ طرق الدفع",
            "pay_cat_unavailable": "التقسيط/الائتمان غير متاح لهذه الفئة",
            "del_free_ya": "إذا اختار المشتري مندوب Yandex تُخصم تكلفته من مستحقاتك في الصفقة. لا يُعرض مندوب أغلى من عائدك من السلعة.",
            "del_where_t": "إلى أين أشحن", "del_where_all": "كل كازاخستان", "del_where_all_s": "تشحن إلى أي منطقة",
            "del_where_regions": "منطقتي ومناطق مختارة", "del_where_regions_s": "حدّد المناطق التي تشحن إليها",
            "del_where_city": "مدينتي فقط", "del_where_city_s": "لقاء، استلام شخصي ومندوب داخل المدينة",
            "del_where_note": "اللقاء والاستلام الشخصي متاحان للمشتري من أي منطقة — القيد يخص الشحن فقط.",
            "del_where_own": "منطقتي", "del_saved": "تم حفظ التوصيل", "wr_saved": "تم حفظ علامات الثقة",
            "wr_seller_t": "ضمان البائع", "wr_from_receipt": "يُحسب من تاريخ استلام السلعة",
            "save_btn": "حفظ", "saving": "جارٍ الحفظ…", "cancel": "إلغاء", "err_generic": "خطأ",
            "err_net": "خطأ في الشبكة", "login": "سجّل الدخول إلى حسابك"
        ]
    ]
}
