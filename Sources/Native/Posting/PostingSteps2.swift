import SwiftUI
import UIKit

/**
 ПОДАЧА — ШАГИ «ЦЕНА И СОСТОЯНИЕ», «АДРЕС», «ДОПОЛНИТЕЛЬНО», «ПРОВЕРКА» И ОКНО «ПРОВЕРЬТЕ ПЕРЕД ПУБЛИКАЦИЕЙ», ЭТАП 42
 (владелец 26.09.2026: «всё одно и то же, просто код разный») + TestFlight 1.10 («понятнее и проще»).

 «Цена и состояние» — #add-card-price: состояние сегментом с подписями раздела, большое поле «Ваша цена» с «₸» и
 разрядами (у услуг — «необязательно» и «Договорная»), «Торг», подсказка «Срочно / Рынок / Высокая» (price_stats или
 оценка Kliko AI), аренда (посуточно / помесячно, залог, мин. срок, комплект, «Продаю тоже»), обмен или бартер, склад
 магазина. «Адрес» — #add-card-where: режим работы или время для связи, область → район → город, адрес.
 «Дополнительно» — рассрочка и кредит, доставка, знаки доверия (уходят после подачи). «Проверка» — карточка, как её
 покажет витрина, разделы с «Изменить», «Вещь работает?», «Гарант-сделка» с причинами блокировки, «Этого уже ждут»;
 окно перед публикацией — showPublishConfirm модуля compose. ТОП (🔴 деньги) — только при Config.цифровыеПокупки: без
 него платного продвижения в мастере нет вовсе.
 */

// MARK: - Цена и состояние

struct ШагЦена: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if модель.состояниеВидно || (модель.правка && модель.нужнаИсправность) {
                КарточкаПодачи(т("form_condition")) {
                    if модель.состояниеВидно { состояние }
                    if модель.правка && модель.нужнаИсправность { БлокИсправности(модель: модель) }
                }
            }
            КарточкаПодачи(т("card_price")) {
                цена
                if let подсказка = модель.подсказкаЦены { якоря(подсказка) }
                if let рынок = модель.рынок {
                    ЗаметкаПодачи(рынок, тон: модель.рынокДорого ? .внимание : .хорошо, значок: "chart.line.uptrend.xyaxis")
                }
            }
            if модель.арендаДоступна { аренда }
            if модель.обменВиден {
                КарточкаПодачи {
                    ПереключательПодачи(т(модель.услугаИлиРабота ? "form_ready_barter" : "form_ready_exchange"),
                                        подпись: т(модель.услугаИлиРабота ? "form_barter_note" : "form_exchange_note"),
                                        включено: $модель.форма.обмен)
                }
            }
            if модель.страница.состояние?.магазин == true && модель.режим == .товар {
                КарточкаПодачи {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("form_in_stock"))
                        ПолеПодачи(т("form_stock_ph"), текст: цифры($модель.форма.склад, 6), клавиатура: .numberPad,
                                   фокус: фокус, ключ: "stock")
                    }
                }
            }
        }
    }

    /// updateCondUI: «Б/У / Новый», у недвижимости «Вторичный рынок / Новостройка», у транспорта «С пробегом / Без пробега».
    private var состояние: some View {
        let подписи = модель.подписиСостояния
        return ВыборСегментом([ВариантПоля(ключ: "used", подпись: подписи.б), ВариантПоля(ключ: "new", подпись: подписи.н)],
                              значение: $модель.форма.состояние)
    }

    private var цена: some View {
        let услуга = модель.услугаИлиРабота
        let ошибка = модель.форма.аренда ? nil : модель.ошибка("price")
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьПоля(т("form_your_price"), обязательно: !услуга && !модель.форма.аренда, необязательно: услуга)
            ПолеЦены(текст: ценаСвязь, заблокировано: услуга && модель.форма.торг, ошибка: ошибка != nil,
                     фокус: фокус, ключ: "price")
            СтрокаОшибки(ошибка)
            if услуга && модель.ценаЧислом == 0 { ПодсказкаПоля(т("form_no_price_hint")) }
            ПереключательПодачи(т(услуга ? "price_negotiable" : "form_bargain"),
                                подпись: т(услуга ? "negot_sub" : "bargain_sub"), включено: торгСвязь)
        }
    }

    /// Цена с пробелами между тысячами (priceFormat), в форме — только цифры, не больше 12.
    private var ценаСвязь: Binding<String> {
        let связь = $модель.форма.цена
        return Binding(get: {
            let число = Int(связь.wrappedValue) ?? 0
            return число > 0 ? ПодачаМодель.деньги(число) : ""
        }, set: { новое in
            let цифры = ПодачаМодель.цифры(новое)
            if цифры != связь.wrappedValue { связь.wrappedValue = цифры }
        })
    }

    /// У услуг «Договорная» блокирует поле цены и чистит его (toggleNegotiable).
    private var торгСвязь: Binding<Bool> {
        let м = модель
        return Binding(get: { м.форма.торг }, set: { новое in
            м.форма.торг = новое
            if новое && м.услугаИлиРабота { м.форма.цена = "" }
        })
    }

    /// «Подсказка цены — Срочно — Рынок — Высокая»: нажатие ставит цену.
    private func якоря(_ п: ПодсказкаЦены) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("form_price_hint") + " · " + п.подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            HStack(spacing: 8) {
                якорь(т("form_price_urgent"), п.низ)
                якорь(т("form_price_market"), п.середина)
                якорь(т("form_price_high"), п.верх)
            }
        }
    }

    private func якорь(_ подпись: String, _ цена: Int) -> some View {
        let выбран = модель.ценаЧислом == цена && цена > 0
        return Button {
            модель.форма.цена = String(цена)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 2) {
                Text(подпись)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Text(ПодачаМодель.деньги(цена) + " ₸")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(выбран ? Theme.акцент : Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(выбран ? Theme.оттенокАкцента : Theme.поверхность2,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(выбран ? Theme.акцент : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    /// Блок аренды (#f-rent-block, setRentPeriod).
    private var аренда: some View {
        let недвижимость = модель.режим == .недвижимость
        let помесячно = модель.форма.период == "month"
        let ошибка = модель.форма.аренда ? модель.ошибка("price") : nil
        return КарточкаПодачи(недвижимость ? т("card_rent") : nil) {
            if !недвижимость {
                ПереключательПодачи(т("form_for_rent"), включено: $модель.форма.аренда)
            }
            if модель.форма.аренда {
                if !недвижимость {
                    ВыборСегментом([ВариантПоля(ключ: "day", подпись: т("form_daily")),
                                    ВариантПоля(ключ: "month", подпись: т("form_monthly"))],
                                   значение: период)
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т(помесячно ? "rent_price_month" : "form_price_per_day"), обязательно: true)
                        ПолеПодачи(помесячно ? "150 000" : "5 000", текст: деньгиСвязь($модель.форма.ставка),
                                   клавиатура: .numberPad, фокус: фокус, ключ: "rate", ошибка: ошибка != nil)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("form_deposit_field"))
                        ПолеПодачи("50 000", текст: деньгиСвязь($модель.форма.залог), клавиатура: .numberPad,
                                   фокус: фокус, ключ: "deposit")
                    }
                }
                СтрокаОшибки(ошибка)
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("form_min_rent"))
                    МенюВыбора(срокиАренды, значение: $модель.форма.минСрок, подсказка: т("form_min_rent"))
                }
                if !недвижимость {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("rent_kit"), необязательно: true)
                        ПолеПодачи(т("rent_kit_short"), текст: комплект, фокус: фокус, ключ: "kit")
                        ПодсказкаПоля(т("rent_kit_ph"))
                    }
                    ПереключательПодачи(т("also_sell"), подпись: т("also_sell_s"), включено: $модель.форма.тожеПродаю)
                }
                ПодсказкаПоля(т("form_rent_note"))
            }
        }
    }

    private var период: Binding<String> {
        let м = модель
        return Binding(get: { м.форма.период == "month" ? "month" : "day" }, set: { новое in
            guard !новое.isEmpty else { return }
            var ф = м.форма
            ф.период = новое
            let допустимые = новое == "month" ? ["1", "2", "3", "6", "12"] : ["1", "2", "3", "7", "14", "30"]
            if !допустимые.contains(ф.минСрок) { ф.минСрок = "1" }
            м.форма = ф
        })
    }

    /// Варианты «Мин. срок аренды» — у суток и у месяцев свои (setRentPeriod).
    private var срокиАренды: [ВариантПоля] {
        if модель.форма.период == "month" {
            return [ВариантПоля(ключ: "1", подпись: т("form_1month")), ВариантПоля(ключ: "2", подпись: т("rent_2m")),
                    ВариантПоля(ключ: "3", подпись: т("rent_3m")), ВариантПоля(ключ: "6", подпись: т("rent_6m")),
                    ВариантПоля(ключ: "12", подпись: т("rent_12m"))]
        }
        return [ВариантПоля(ключ: "1", подпись: т("form_1day")), ВариантПоля(ключ: "2", подпись: т("form_2day")),
                ВариантПоля(ключ: "3", подпись: т("form_3day")), ВариантПоля(ключ: "7", подпись: т("form_1week")),
                ВариантПоля(ключ: "14", подпись: т("form_2week")), ВариантПоля(ключ: "30", подпись: т("form_1month"))]
    }

    /// rent_kit — не длиннее 200.
    private var комплект: Binding<String> {
        let связь = $модель.форма.комплект
        return Binding(get: { связь.wrappedValue }, set: { новое in связь.wrappedValue = String(новое.prefix(200)) })
    }

    private func цифры(_ связь: Binding<String>, _ предел: Int) -> Binding<String> {
        Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.цифры(новое, предел: предел)
        })
    }

    /// Ставка и залог — как цена: на экране с пробелами между тысячами, в форме только цифры (не больше 12).
    private func деньгиСвязь(_ связь: Binding<String>) -> Binding<String> {
        Binding(get: {
            let число = Int(связь.wrappedValue) ?? 0
            return число > 0 ? ПодачаМодель.деньги(число) : ""
        }, set: { новое in
            let цифры = ПодачаМодель.цифры(новое)
            if цифры != связь.wrappedValue { связь.wrappedValue = цифры }
        })
    }
}

/// «Вещь работает?» — Да / Нет (worksRequire, pcWorks): без ответа у б/у техники не отправить.
struct БлокИсправности: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(ПодачаText.т("wrk_q"), обязательно: true)
            ВыборСегментом([ВариантПоля(ключ: "ok", подпись: ПодачаText.т("wrk_yes")),
                            ВариантПоля(ключ: "bad", подпись: ПодачаText.т("wrk_no"))],
                           значение: $модель.форма.работает)
            СтрокаОшибки(модель.ошибка("works"))
        }
        .id("works")
    }
}

// MARK: - Адрес

struct ШагАдрес: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var список: СписокВыбора? = nil
    @State private var свой = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Пресет часов: режим, с, до и подпись.
    private struct Часы: Hashable {
        let режим: String
        let с: String
        let до: String
        let подпись: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            место
            часы
        }
        .sheet(item: $список) { с in
            ЛистВыбора(список: с)
        }
        .onAppear {
            свой = модель.форма.часы == "range" && !пресеты.contains(where: { $0.режим == "range" && $0.с == модель.форма.часыС
                                                                                && $0.до == модель.форма.часыДо })
        }
    }

    /// Пресеты сайта: услугам — 24/7, 09:00–18:00, 10:00–20:00, свой; товарам — в любое время, 09:00–21:00, 10:00–20:00, своё.
    private var пресеты: [Часы] {
        if модель.услугаИлиРабота {
            return [Часы(режим: "247", с: "", до: "", подпись: т("hours_247")),
                    Часы(режим: "range", с: "09:00", до: "18:00", подпись: "09:00–18:00"),
                    Часы(режим: "range", с: "10:00", до: "20:00", подпись: "10:00–20:00")]
        }
        return [Часы(режим: "", с: "", до: "", подпись: т("hours_anytime")),
                Часы(режим: "range", с: "09:00", до: "21:00", подпись: "09:00–21:00"),
                Часы(режим: "range", с: "10:00", до: "20:00", подпись: "10:00–20:00")]
    }

    private var часы: some View {
        let услуга = модель.услугаИлиРабота
        let ошибка = модель.ошибка("hours")
        return КарточкаПодачи(т(услуга ? "hours_work_title" : "hours_call_title") + (услуга ? " *" : ""),
                              подпись: т(услуга ? "hours_work_sub" : "hours_call_sub")) {
            ПотокЧипов(зазор: 8) {
                ForEach(пресеты, id: \.self) { п in
                    ЧипПодачи(п.подпись, выбран: !свой && выбран(п)) {
                        свой = false
                        var ф = модель.форма
                        ф.часы = п.режим
                        ф.часыС = п.с
                        ф.часыДо = п.до
                        ф.часыВыбраны = true
                        модель.форма = ф
                    }
                }
                ЧипПодачи(т(услуга ? "hours_custom" : "hours_custom_time"), выбран: свой) {
                    свой = true
                    var ф = модель.форма
                    ф.часы = "range"
                    if ф.часыС.isEmpty { ф.часыС = "09:00" }
                    if ф.часыДо.isEmpty { ф.часыДо = "18:00" }
                    ф.часыВыбраны = true
                    модель.форма = ф
                }
            }
            if свой {
                HStack(spacing: 10) {
                    выборВремени(т("hours_from"), $модель.форма.часыС)
                    выборВремени(т("hours_to"), $модель.форма.часыДо)
                }
            }
            СтрокаОшибки(ошибка)
        }
        .id("hours")
    }

    private func выбран(_ п: Часы) -> Bool {
        let ф = модель.форма
        if п.режим != "range" { return ф.часы == п.режим && (ф.часыВыбраны || !п.режим.isEmpty || !модель.услугаИлиРабота) }
        return ф.часы == "range" && ф.часыС == п.с && ф.часыДо == п.до
    }

    /// Время с шагом 30 минут, как input type=time с step 1800.
    private func выборВремени(_ подпись: String, _ связь: Binding<String>) -> some View {
        Menu {
            ForEach(ШагАдрес.времена, id: \.self) { время in
                Button(время) { связь.wrappedValue = время }
            }
        } label: {
            HStack {
                Text(подпись)
                    .foregroundStyle(Theme.текстВторой)
                Text(связь.wrappedValue.isEmpty ? "--:--" : связь.wrappedValue)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 0)
                Image(systemName: "clock")
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
        }
        .accessibilityLabel(подпись)
        .accessibilityValue(связь.wrappedValue)
    }

    static let времена: [String] = {
        var список: [String] = []
        for час in 0..<24 {
            let ч = час < 10 ? "0" + String(час) : String(час)
            список.append(ч + ":00")
            список.append(ч + ":30")
        }
        return список
    }()

    /// Область → район → город (geoFillDistricts / geoFillCities): у городов республиканского значения город — сам регион.
    private var место: some View {
        let регион = модель.справочники.регионы.first(where: { $0.id == модель.форма.регион })
        let город = регион?.город ?? false
        let ошибка = модель.ошибка("city")
        return КарточкаПодачи(т("form_location")) {
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("form_region_ph"), обязательно: true)
                СтрокаВыбора(регион?.имя ?? "", подсказка: т("form_region_ph")) {
                    выбратьРегион()
                }
            }
            if let регион, !регион.районы.isEmpty {
                СтрокаВыбора(регион.районы.first(where: { $0.id == модель.форма.район })?.имя ?? "",
                             подсказка: т(город ? "district_city_ph" : "form_district_ph")) {
                    выбратьРайон(регион, город: город)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if город {
                    ПолеПодачи(т("form_city_ph"), текст: Binding.constant(регион?.имя ?? ""), заблокировано: true)
                        .id("city")
                } else if модель.городВводом {
                    ПолеПодачи(т("form_city_ph"), текст: городСвязь, заглавные: .words, фокус: фокус, ключ: "city",
                               ошибка: ошибка != nil)
                } else {
                    СтрокаВыбора(модель.форма.город, подсказка: т("form_city_ph")) {
                        выбратьГород(регион)
                    }
                    .overlay {
                        if ошибка != nil {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(Theme.ценаСкидка, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .id("city")
                }
                СтрокаОшибки(ошибка)
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("address_label"), необязательно: true)
                ПолеПодачи(т("form_address_ph"), текст: адресСвязь, фокус: фокус, ключ: "address")
                ПодсказкаПоля(т("form_addr_hint"))
            }
        }
    }

    private func выбратьРегион() {
        let м = модель
        фокус.wrappedValue = nil
        список = СписокВыбора(заголовок: т("form_region_ph"),
                              варианты: м.справочники.регионы.map { ВариантПоля(ключ: $0.id, подпись: $0.имя) }) { ключ in
            м.выбратьРегион(ключ)
        }
    }

    private func выбратьРайон(_ регион: РегионКЗ, город: Bool) {
        let м = модель
        фокус.wrappedValue = nil
        список = СписокВыбора(заголовок: т(город ? "district_city_ph" : "form_district_ph"),
                              варианты: регион.районы.map { ВариантПоля(ключ: $0.id, подпись: $0.имя) },
                              сброс: т("spec_unset")) { ключ in
            м.выбратьРайон(ключ)
        }
    }

    private func выбратьГород(_ регион: РегионКЗ?) {
        let м = модель
        фокус.wrappedValue = nil
        let города = м.городаСписка(регион)
        список = СписокВыбора(заголовок: т("form_city_ph"),
                              варианты: города.map { ВариантПоля(ключ: $0, подпись: $0) },
                              своё: т("spec_other_write")) { имя in
            м.выбратьГород(имя)
        }
    }

    private var городСвязь: Binding<String> {
        let м = модель
        return Binding(get: { м.форма.город }, set: { новое in м.выбратьГород(новое) })
    }

    /// Точный адрес меняет точку на карте: старые lat/lon из настроек к новому адресу не подходят — убираем.
    private var адресСвязь: Binding<String> {
        let м = модель
        return Binding(get: { м.форма.адрес }, set: { новое in
            guard новое != м.форма.адрес else { return }
            var ф = м.форма
            ф.адрес = новое
            ф.lat = ""
            ф.lon = ""
            м.форма = ф
        })
    }
}

extension ПодачаМодель {
    /// geoSetTriple: новый регион — район пустой, город — сам регион у городов республиканского значения.
    func выбратьРегион(_ ключ: String) {
        guard ключ != форма.регион else { return }
        let регион = справочники.регионы.first(where: { $0.id == ключ })
        var ф = форма
        ф.регион = ключ
        ф.район = ""
        ф.город = (регион?.город ?? false) ? (регион?.имя ?? "") : ""
        ф.lat = ""
        ф.lon = ""
        форма = ф
    }

    func выбратьРайон(_ ключ: String) {
        guard ключ != форма.район else { return }
        let регион = справочники.регионы.first(where: { $0.id == форма.регион })
        var ф = форма
        ф.район = ключ
        if !(регион?.город ?? false) {
            let города = регион?.районы.first(where: { $0.id == ключ })?.города ?? []
            ф.город = города.count == 1 ? города[0] : (города.contains(ф.город) ? ф.город : "")
        }
        ф.lat = ""
        ф.lon = ""
        форма = ф
    }

    func выбратьГород(_ имя: String) {
        guard имя != форма.город else { return }
        var ф = форма
        ф.город = имя
        ф.lat = ""
        ф.lon = ""
        форма = ф
    }
}

// MARK: - Дополнительно

struct ШагДополнительно: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    let открытьСайт: (String) -> Void

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, открытьСайт: @escaping (String) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.открытьСайт = открытьСайт
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// WR_STOPS сайта; без PRO — до 7 дней (WR_FREE_MAX).
    private static let сроки: [Int] = [0, 3, 7, 14, 30, 60, 90, 180, 270, 365]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if модель.правка {
                /* У опубликованного сайт сохраняет эти настройки сразу своими окнами (openPayment / openDelivery /
                   openTrust) — отдельно от edit_item. Здесь — своё окно тех же полей (MyListings/PublishedSettings.swift). */
                КарточкаПодачи(т("form_additional"), подпись: т("cfg_edit_note")) {
                    КнопкаПодачиВторая(т("cfg_setup")) {
                        ЛистНастроекОбъявления.показать(модель: модель)
                    }
                }
            } else {
                ПодсказкаПоля(т("extra_sub"))
                if модель.строкиДополнительно.contains("pay") { оплата }
                if модель.строкиДополнительно.contains("del") { доставка }
                if модель.строкиДополнительно.contains("trust") { доверие }
            }
        }
    }

    private var оплата: some View {
        КарточкаПодачи(т("pay_methods")) {
            ПереключательПодачи(т("pay_installment"), подпись: т("pay_with_bank"), включено: $модель.форма.рассрочка)
            ПереключательПодачи(т("pay_credit"), включено: $модель.форма.кредит)
        }
    }

    private var доставка: some View {
        КарточкаПодачи(т("del_settings")) {
            ПереключательПодачи(т("del_free_ship"), подпись: т("del_free_note"), включено: бесплатно)
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("del_approx_time"), необязательно: true)
                ПолеПодачи(т("del_days_ph"), текст: дни, фокус: фокус, ключ: "deldays", единица: т("del_days_unit"))
            }
        }
    }

    private var бесплатно: Binding<Bool> {
        let м = модель
        return Binding(get: { м.форма.доставкаБесплатно }, set: { новое in
            var ф = м.форма
            ф.доставкаБесплатно = новое
            ф.доставкаЗадана = true
            м.форма = ф
        })
    }

    private var дни: Binding<String> {
        let м = модель
        return Binding(get: { м.форма.доставкаДней }, set: { новое in
            var ф = м.форма
            ф.доставкаДней = String(новое.prefix(12))
            ф.доставкаЗадана = true
            м.форма = ф
        })
    }

    private var доверие: some View {
        let знаки = модель.знакиДоверия
        let срочные = знаки.filter { $0.срок }
        let флажки = знаки.filter { !$0.срок }
        let предел = модель.страница.pro ? 365 : 7
        let срокиДней: [Int] = Self.сроки.filter { $0 <= предел }
        let варианты: [ВариантПоля] = срокиДней.map { ВариантПоля(ключ: String($0), подпись: ШагДополнительно.срокГарантии($0)) }
        return КарточкаПодачи(т("wr_title"), подпись: т("wr_note")) {
            if let срок = срочные.first {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(срок.подпись)
                    МенюВыбора(варианты, значение: срокСвязь, подсказка: т("wr_none"))
                    if !модель.страница.pro {
                        ПодсказкаПоля(т("wr_pro_note"))
                    }
                }
            }
            if !флажки.isEmpty {
                ПодписьПоля(т("wr_checks_h"))
                ForEach(флажки) { знак in
                    ПереключательПодачи(знак.подпись, включено: флаг(знак.id))
                }
            }
        }
    }

    /// Срок гарантии в днях строкой для меню: «0» — «Нет».
    private var срокСвязь: Binding<String> {
        let м = модель
        return Binding(get: { String(м.форма.гарантияДней) }, set: { новое in
            var ф = м.форма
            ф.гарантияДней = Int(новое) ?? 0
            ф.доверияЗадано = true
            м.форма = ф
        })
    }

    private func флаг(_ ключ: String) -> Binding<Bool> {
        let м = модель
        return Binding(get: { м.форма.знаки.contains(ключ) }, set: { новое in
            var ф = м.форма
            ф.знаки.removeAll { $0 == ключ }
            if новое { ф.знаки.append(ключ) }
            ф.доверияЗадано = true
            м.форма = ф
        })
    }

    /// warrTerm сайта: «Нет», «3 дня», «7 дней», «1 месяц», «12 месяцев».
    static func срокГарантии(_ дни: Int) -> String {
        if дни <= 0 { return ПодачаText.т("wr_none") }
        let месяцы = дни == 365 ? 12 : (дни >= 30 && дни % 30 == 0 ? дни / 30 : 0)
        let число = месяцы > 0 ? месяцы : дни
        let форма = ПодачаText.множественное(число)
        let ключ = (месяцы > 0 ? "wr_m" : "wr_d") + форма
        return String(число) + " " + ПодачаText.т(ключ)
    }
}

// MARK: - Проверка

struct ШагПроверка: View {
    @ObservedObject var модель: ПодачаМодель
    let открытьСайт: (String) -> Void

    init(модель: ПодачаМодель, открытьСайт: @escaping (String) -> Void) {
        self.модель = модель
        self.открытьСайт = открытьСайт
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаПодачи(т("pc_sub")) {
                КарточкаВитриныПодачи(модель: модель)
            }
            КарточкаПодачи(т("rv_sections")) {
                РазделыПроверки(модель: модель)
            }
            if (!модель.правка && модель.нужнаИсправность) || модель.запретГаранта != "hide" {
                КарточкаПодачи(т("rv_deal")) {
                    if !модель.правка && модель.нужнаИсправность { БлокИсправности(модель: модель) }
                    БлокГаранта(модель: модель)
                }
            }
            if модель.режим == .услуга {
                ЗаметкаПодачи(т("pc_svc_note"), тон: .инфо, значок: "info.circle")
            }
            ЗаметкаПодачи(т("pc_mod_note"), тон: .серый, значок: "shield")
            if !модель.правка { топ }
            if модель.ждут > 0 {
                ЗаметкаПодачи(т("reach_n").replacingOccurrences(of: "{n}", with: String(модель.ждут)), тон: .хорошо,
                              значок: "person.2")
            }
        }
    }

    /// ТОП при подаче. 🔴 Деньги: без Config.цифровыеПокупки платного продвижения в мастере нет вовсе.
    @ViewBuilder
    private var топ: some View {
        if let выбран = модель.форма.топ {
            КарточкаПодачи(String(format: т("top_bar"), выбран.подпись),
                           подпись: String(format: т("top_bar_s"), ПодачаМодель.деньги(выбран.цена))) {
                КнопкаПодачиВторая(т("top_remove")) { модель.убратьТоп() }
            }
        } else if Config.цифровыеПокупки && !модель.страница.пакеты.isEmpty {
            КарточкаПодачи(т("pups_badge") + " · " + т("pups_h"),
                           подпись: String(format: т("pups_sub"), модель.лимитФото)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• " + String(format: т("pups_30"), модель.лимитФото))
                    Text("• " + т("pups_top"))
                    Text("• " + т("pups_search"))
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
                ForEach(модель.страница.пакеты.filter { $0.днейТоп > 0 }) { пакет in
                    Button {
                        модель.выбратьТоп(пакет)
                    } label: {
                        HStack {
                            Text(пакет.подпись)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.текст)
                            Spacer()
                            if модель.проверяемТоп == пакет.id {
                                ProgressView()
                            } else {
                                Text(ПодачаМодель.деньги(модель.страница.ценаСоСкидкой(пакет.цена)) + " ₸")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(Theme.золото)
                            }
                        }
                        .padding(12)
                        .background(Theme.топФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!модель.проверяемТоп.isEmpty)
                }
            }
        }
    }
}

/// «Так объявление увидят покупатели» (showPublishConfirm): карточка витрины и начало описания.
struct ПревьюПодачи: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            КарточкаВитриныПодачи(модель: модель)
            let описание = модель.форма.описание.trimmingCharacters(in: .whitespacesAndNewlines)
            if !описание.isEmpty {
                Text(описание)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(4)
            }
        }
    }
}

/// «Гарант-сделка» (_pcEscrowBlock): переключатель, что он даёт, или почему заблокирован.
struct БлокГаранта: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        let запрет = модель.запретГаранта
        if запрет != "hide" {
            VStack(alignment: .leading, spacing: 8) {
                ПереключательПодачи(т("pc_escrow_t"), подпись: запрет.isEmpty ? т(модель.форма.гарант ? "esc_sw_on_s" : "esc_sw_off_s") : nil,
                                    включено: запрет.isEmpty ? $модель.форма.гарант : Binding.constant(false),
                                    заблокировано: !запрет.isEmpty)
                if !запрет.isEmpty {
                    ЗаметкаПодачи(текстЗапрета(запрет), тон: .внимание, значок: "lock")
                } else if модель.форма.гарант {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(пункты, id: \.self) { пункт in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.зелёныйЯркий)
                                    .accessibilityHidden(true)
                                Text(пункт)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.текст)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if модель.страница.состояние?.верифицирован == false {
                        ЗаметкаПодачи(т("pc_esc_verify"), тон: .внимание)
                    }
                } else {
                    ПодсказкаПоля(т("pc_esc_off"))
                }
            }
        }
    }

    /// _pcEscrowMode: услуга — оплата работы, недвижимость и транспорт (не запчасти) — задаток, остальное — товар.
    private var пункты: [String] {
        switch модель.режим {
        case .услуга: return [т("pc_esc_s1"), т("pc_esc_s2"), т("pc_esc_s3")]
        case .недвижимость, .авто: return [т("pc_esc_d1"), т("pc_esc_d2")]
        default: return [т("pc_esc_g1"), т("pc_esc_g2"), т("pc_esc_g3")]
        }
    }

    private func текстЗапрета(_ запрет: String) -> String {
        switch запрет {
        case "broken": return т("esc_lock_broken_l")
        case "parts": return т("esc_lock_parts_l")
        default:
            return т("esc_lock_min_l").replacingOccurrences(of: "{n}",
                                                           with: ПодачаМодель.деньги(модель.страница.минимумГаранта) + " ₸")
        }
    }
}

/// Окно «Проверьте перед публикацией» (showPublishConfirm): «← Изменить» и «Опубликовать».
struct ОкноПроверкиПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    @Environment(\.dismiss) private var закрыть

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ПодсказкаПоля(т("pc_sub"))
                    ПревьюПодачи(модель: модель)
                    if модель.нужнаИсправность || модель.запретГаранта != "hide" {
                        КарточкаПодачи {
                            if модель.нужнаИсправность { БлокИсправности(модель: модель) }
                            БлокГаранта(модель: модель)
                        }
                    }
                    if модель.режим == .услуга {
                        ЗаметкаПодачи(т("pc_svc_note"), тон: .инфо, значок: "info.circle")
                    }
                    ЗаметкаПодачи(т("pc_mod_note"), тон: .серый, значок: "shield")
                    if let топ = модель.форма.топ {
                        ЗаметкаПодачи(String(format: т("top_bar_s"), ПодачаМодель.деньги(топ.цена)), тон: .внимание,
                                      значок: "arrow.up.circle")
                    }
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    КнопкаПодачиВторая(т("pc_back")) { закрыть() }
                    КнопкаПодачи(т("pc_publish"), занято: модель.отправляем) { модель.опубликовать() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.поверхность.ignoresSafeArea(edges: .bottom))
            }
            .navigationTitle(т("pc_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.акцент)
    }
}
