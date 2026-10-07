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
 окно перед публикацией — showPublishConfirm модуля compose. ТОПа при подаче (платно) в приложении нет вовсе.
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
        /* #add-card-price — одна карточка: состояние, цена, аренда, обмен, склад. */
        КарточкаПодачи(т("step_price"), значок: "wallet.pass") {
            if модель.состояниеВидно { состояние }
            if модель.правка && модель.нужнаИсправность { БлокИсправности(модель: модель) }
            цена
            if let подсказка = модель.подсказкаЦены { якоря(подсказка) }
            if let рынок = модель.рынок {
                ЗаметкаПодачи(рынок, тон: модель.рынокДорого ? .внимание : .хорошо, значок: "chart.line.uptrend.xyaxis")
            }
            if модель.арендаДоступна { аренда }
            if модель.обменВиден { обмен }
            if модель.страница.состояние?.магазин == true && модель.режим == .товар {
                VStack(alignment: .leading, spacing: 8) {
                    ПодписьПоля(т("form_in_stock"))
                    ПолеПодачи(т("form_stock_ph"), текст: цифры($модель.форма.склад, 6), клавиатура: .numberPad,
                               фокус: фокус, ключ: "stock")
                }
            }
        }
    }

    /// updateCondUI: ряд .chips «Б/У / Новый», у недвижимости «Вторичный рынок / Новостройка», у транспорта
    /// «С пробегом / Без пробега».
    private var состояние: some View {
        let подписи = модель.подписиСостояния
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьПоля(т("form_condition"))
            HStack(spacing: 8) {
                ЧипПодачи(подписи.б, выбран: модель.форма.состояние == "used") { модель.форма.состояние = "used" }
                ЧипПодачи(подписи.н, выбран: модель.форма.состояние == "new") { модель.форма.состояние = "new" }
            }
        }
    }

    /// «Ваша цена» (div.field-lbl.row): справа в строке подписи — флажок «Торг» (у услуг — «Договорная»).
    private var цена: some View {
        let услуга = модель.услугаИлиРабота
        let ошибка = модель.форма.аренда ? nil : модель.ошибка("price")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ПодписьПоля(т("form_your_price"), необязательно: услуга)
                Spacer(minLength: 4)
                флажокТорга(услуга)
            }
            ПолеЦены(текст: ценаСвязь, заблокировано: услуга && модель.форма.торг, ошибка: ошибка != nil,
                     фокус: фокус, ключ: "price")
            СтрокаОшибки(ошибка)
            if услуга && модель.ценаЧислом == 0 { ПодсказкаПоля(т("form_no_price_hint")) }
        }
    }

    /// Флажок 24×24 (кромка 2 --line, скругление 8) и #f-neg-label 13/600 серым.
    private func флажокТорга(_ услуга: Bool) -> some View {
        let включено = модель.форма.торг
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
        return Button {
            let связь = торгСвязь
            связь.wrappedValue = !связь.wrappedValue
            ОткликСайта.выбор()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    форма.fill(включено ? Theme.зелёный : КраскаПодачи.карточка)
                    форма.strokeBorder(включено ? Theme.зелёный : КраскаПодачи.линия, lineWidth: 2)
                    if включено {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
                Text(т(услуга ? "price_negotiable" : "form_bargain"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(включено ? .isSelected : [])
    }

    /// Обмен или бартер (.sw-row) и пояснение #f-exch-note под строкой.
    private var обмен: some View {
        VStack(alignment: .leading, spacing: 0) {
            ПереключательПодачи(т(модель.услугаИлиРабота ? "form_ready_barter" : "form_ready_exchange"),
                                включено: $модель.форма.обмен)
            ПодсказкаПоля(т(модель.услугаИлиРабота ? "form_barter_note" : "form_exchange_note"))
                .padding(.top, 6)
                .padding(.leading, 2)
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
                якорь(т("form_price_urgent"), п.низ, п)
                якорь(т("form_price_market"), п.середина, п)
                якорь(т("form_price_high"), п.верх, п)
            }
            /* #f-psug-smp: «Похожие на Kliko.kz: …» — по каким объявлениям посчитано. */
            if let похожие = модель.похожиеЦены {
                Text(похожие)
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func якорь(_ подпись: String, _ цена: Int, _ подсказка: ПодсказкаЦены) -> some View {
        let выбран = модель.якорьВыбран(цена, подсказка)
        return Button {
            модель.форма.цена = String(цена)
            ОткликСайта.выбор()
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
            .background(выбран ? КраскаПодачи.хорошоФон : КраскаПодачи.поле,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбран ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: выбран ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    /// Блок аренды (#f-rent-block, setRentPeriod): строка «Сдаю в аренду», под ней .rent-box на --surf2.
    private var аренда: some View {
        let недвижимость = модель.режим == .недвижимость
        return VStack(alignment: .leading, spacing: 10) {
            if недвижимость {
                ПодписьПоля(т("card_rent"))
            } else {
                ПереключательПодачи(т("form_for_rent"), включено: $модель.форма.аренда)
            }
            if модель.форма.аренда { коробкаАренды(недвижимость) }
        }
    }

    private func коробкаАренды(_ недвижимость: Bool) -> some View {
        let помесячно = модель.форма.период == "month"
        let ошибка = модель.форма.аренда ? модель.ошибка("price") : nil
        return VStack(alignment: .leading, spacing: 12) {
            if !недвижимость {
                СегментАрендыПодачи([ВариантПоля(ключ: "day", подпись: т("form_daily")),
                                     ВариантПоля(ключ: "month", подпись: т("form_monthly"))],
                                    значение: период)
            }
            /* .rent-grid 1fr 1fr: поля ставки и залога — на одной линии, подписи в одну строку. */
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    подписьАренды(т(помесячно ? "rent_price_month" : "form_price_per_day"))
                    ПолеПодачи(помесячно ? "150 000" : "5 000", текст: деньгиСвязь($модель.форма.ставка),
                               клавиатура: .numberPad, фокус: фокус, ключ: "rate", ошибка: ошибка != nil)
                }
                VStack(alignment: .leading, spacing: 6) {
                    подписьАренды(т("form_deposit_field"))
                    ПолеПодачи("50 000", текст: деньгиСвязь($модель.форма.залог), клавиатура: .numberPad,
                               фокус: фокус, ключ: "deposit")
                }
            }
            СтрокаОшибки(ошибка)
            VStack(alignment: .leading, spacing: 6) {
                подписьАренды(т("form_min_rent"))
                МенюВыбора(срокиАренды, значение: $модель.форма.минСрок, подсказка: т("form_min_rent"))
            }
            if !недвижимость {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("rent_kit"), необязательно: true, мелкая: true)
                    ПолеПодачи(т("rent_kit_short"), текст: комплект, фокус: фокус, ключ: "kit")
                    ПодсказкаПоля(т("rent_kit_ph"))
                }
                ПереключательПодачи(т("also_sell"), подпись: т("also_sell_s"), включено: $модель.форма.тожеПродаю)
            }
            ПодсказкаПоля(т("form_rent_note"))
        }
        .padding(14)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1.5)
        }
    }

    /// .rent-lbl: 12/600 серым, в одну строку.
    private func подписьАренды(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        /* #add-card-where «Где и когда»: сначала часы (#f-hours-field), потом местоположение. */
        КарточкаПодачи(т("where_card"), значок: "mappin.and.ellipse") {
            часы
            место
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
        return VStack(alignment: .leading, spacing: 0) {
            /* .hours-lbl 15/600 и «· необязательно»; у услуг режим работы обязателен. */
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(т(услуга ? "hours_work_title" : "hours_call_title"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.текст)
                if услуга {
                    Text("*")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаПодачи.плохоТекст)
                } else {
                    Text("· " + т("form_optional"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .accessibilityElement(children: .combine)
            Text(т(услуга ? "hours_work_sub" : "hours_call_sub"))
                .font(.system(size: 12))
                .lineSpacing(6)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
                .padding(.bottom, 12)
            ПотокЧипов(зазор: 8) {
                ForEach(пресеты, id: \.self) { п in
                    ЧипЧасовПодачи(п.подпись, значок: п.режим == "range" ? "clock" : "shuffle", выбран: !свой && выбран(п)) {
                        свой = false
                        var ф = модель.форма
                        ф.часы = п.режим
                        ф.часыС = п.с
                        ф.часыДо = п.до
                        ф.часыВыбраны = true
                        модель.форма = ф
                    }
                }
                ЧипЧасовПодачи(т(услуга ? "hours_custom" : "hours_custom_time"), значок: "slider.horizontal.3",
                               выбран: свой) {
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
                .padding(.top, 10)
            }
            СтрокаОшибки(ошибка)
                .padding(.top, ошибка == nil ? 0 : 6)
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
                    .foregroundStyle(КраскаПодачи.текст)
                Spacer(minLength: 0)
                Image(systemName: "clock")
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
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
        return VStack(alignment: .leading, spacing: 14) {
            ПодписьПоля(т("form_location"))
            СтрокаВыбора(регион?.имя ?? "", подсказка: т("form_region_ph")) {
                выбратьРегион()
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
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.ценаСкидка, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .id("city")
                }
                СтрокаОшибки(ошибка)
            }
            VStack(alignment: .leading, spacing: 6) {
                ПодписьПоля(т("address_label"), необязательно: true, мелкая: true)
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
                              своё: т("spec_other_write"), предел: 0) { имя in
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
    let открытьАдрес: (String) -> Void
    /// Открытое окно настройки строки: pay · del · trust; пусто — закрыто.
    @State private var настройка = ""
    /// Строки «Уточнить» раскрыты.
    @State private var раскрыто = false

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding, открытьАдрес: @escaping (String) -> Void) {
        self.модель = модель
        self.фокус = фокус
        self.открытьАдрес = открытьАдрес
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
                секция
            }
        }
        .sheet(isPresented: настройкаОткрыта) {
            листНастройки
        }
    }

    // MARK: .advcfg-sec — строки «Настроить»

    /// Настроено ли что-то — тогда строки видны сразу.
    private var настроено: Bool {
        let ф = модель.форма
        return ф.рассрочка || ф.кредит || ф.доставкаЗадана || ф.доверияЗадано
    }

    private var показатьСтроки: Bool { раскрыто || настроено }

    private var секция: some View {
        КарточкаПодачи {
            VStack(alignment: .leading, spacing: 0) {
                /* Свёрнуто (владелец, обход новичком): «Уточнить (необязательно)» — строки по нажатию. */
                Button {
                    фокус.wrappedValue = nil
                    guard !настроено else { return }
                    withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.2))) { раскрыто.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .accessibilityHidden(true)
                        Text(т("step_extra"))
                            .font(.system(size: 14, weight: .heavy))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if !настроено {
                            Image(systemName: раскрыто ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.текстВторой)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(КраскаПодачи.текст)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(показатьСтроки ? "" : т("cfg_collapsed"))
                Text(т("extra_sub"))
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.bottom, показатьСтроки ? 12 : 0)
                if показатьСтроки {
                    строкиНастроек
                }
            }
        }
    }

    private var строкиНастроек: some View {
        VStack(spacing: 10) {
            if модель.строкиДополнительно.contains("pay") {
                строка("pay", заголовок: т("cfg_pay_t"), значок: "creditcard", итог: итогОплаты)
            }
            if модель.строкиДополнительно.contains("del") {
                строка("del", заголовок: т("cfg_del_t"), значок: "truck.box", итог: итогДоставки)
            }
            if модель.строкиДополнительно.contains("trust") {
                строка("trust", заголовок: т("wr_title"), значок: "checkmark.shield", итог: итогДоверия)
            }
        }
    }

    /// .advcfg-row: значок на --tint-ok, заголовок и сводка в одну строку, «Настроить».
    private func строка(_ ключ: String, заголовок: String, значок: String, итог: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 34, height: 34)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(заголовок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(итог)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                фокус.wrappedValue = nil
                настройка = ключ
            } label: {
                Text(т("cfg_setup"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(КраскаПодачи.акцентТекст)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.зелёный2, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(12)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    /// _cfgSummary: «Рассрочка · Кредит» или «Выключено».
    private var итогОплаты: String {
        var части: [String] = []
        if модель.форма.рассрочка { части.append(т("pay_installment")) }
        if модель.форма.кредит { части.append(т("pay_credit")) }
        return части.isEmpty ? т("cfg_off") : части.joined(separator: " · ")
    }

    /// «Бесплатная · ~3 дн.» или умолчание — цену предложат службы доставки.
    private var итогДоставки: String {
        var части: [String] = []
        if модель.форма.доставкаБесплатно { части.append(т("cfg_del_free")) }
        let дни = модель.форма.доставкаДней.trimmingCharacters(in: .whitespaces)
        if !дни.isEmpty { части.append("~" + дни + " " + т("cfg_days")) }
        return части.isEmpty ? т("cfg_del_def") : части.joined(separator: " · ")
    }

    /// «Гарантия 7 дней · знаков: 2» или «Не выбраны».
    private var итогДоверия: String {
        var части: [String] = []
        if модель.форма.гарантияДней > 0 {
            части.append(т("wr_short") + " " + ШагДополнительно.срокГарантии(модель.форма.гарантияДней))
        }
        let знаков = модель.форма.знаки.count
        if знаков > 0 { части.append(т("wr_signs_n").replacingOccurrences(of: "{n}", with: String(знаков))) }
        return части.isEmpty ? т("wr_not_chosen") : части.joined(separator: " · ")
    }

    private var настройкаОткрыта: Binding<Bool> {
        Binding(get: { !настройка.isEmpty }, set: { открыт in
            if !открыт { настройка = "" }
        })
    }

    /// Окно настройки строки (openPayment / openDelivery / openTrust сайта для черновика): те же поля.
    private var листНастройки: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch настройка {
                    case "pay": оплата
                    case "del": доставка
                    case "trust": доверие
                    default: EmptyView()
                    }
                }
                .padding(14)
                .мерилоФормы()
            }
            .background(КраскаПодачи.фон)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(заголовокНастройки)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("done")) { настройка = "" }
                }
            }
        }
        .tint(Theme.акцент)
        /* По высоте полей настройки — без пустоты снизу; длинная — до полного. */
        .листПоВысоте()
    }

    private var заголовокНастройки: String {
        switch настройка {
        case "pay": return т("cfg_pay_t")
        case "del": return т("cfg_del_t")
        default: return т("wr_title")
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
                ПолеПодачи(т("del_days_ph"), текст: дни, единица: т("del_days_unit"))
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
    let открытьАдрес: (String) -> Void

    init(модель: ПодачаМодель, открытьАдрес: @escaping (String) -> Void) {
        self.модель = модель
        self.открытьАдрес = открытьАдрес
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
            if модель.ждут > 0 {
                ЗаметкаПодачи(т("reach_n").replacingOccurrences(of: "{n}", with: String(модель.ждут)), тон: .хорошо,
                              значок: "person.2")
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

/// Окно «Проверьте перед публикацией» (showPublishConfirm): шапка с глазом, превью объявления, заметки,
/// «← Изменить» (1 доля) и «✓ Опубликовать» (2 доли).
struct ОкноПроверкиПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    @Environment(\.dismiss) private var закрыть

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ПревьюОкнаПодачи(модель: модель)
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
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
            }
        }
        .background(КраскаПодачи.карточка.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GeometryReader { г in
                HStack(spacing: 10) {
                    Button { закрыть() } label: {
                        Text(т("pc_back"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    .frame(width: max(0, (г.size.width - 10) / 3))
                    КнопкаПодачи("✓ " + т("pc_publish"), занято: модель.отправляем) { модель.опубликовать() }
                }
            }
            .frame(height: 46)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(КраскаПодачи.карточка.ignoresSafeArea(edges: .bottom))
        }
        .tint(Theme.акцент)
    }

    /// Шапка: глаз на --tint-ok, «Проверьте перед публикацией», «Так объявление увидят покупатели», «×».
    private var шапка: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 38, height: 38)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("pc_title"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(т("pc_sub"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("close"))
        }
        .padding(.top, 20)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

/// Превью в окне проверки (showPublishConfirm): фото 190, название, цена --on-ok («· торг»), чипы раздела, города,
/// состояния и числа фото, начало описания.
struct ПревьюОкнаПодачи: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        let ф = модель.форма
        let название = ф.название.trimmingCharacters(in: .whitespacesAndNewlines)
        let описание = ф.описание.trimmingCharacters(in: .whitespacesAndNewlines)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            обложка
            VStack(alignment: .leading, spacing: 8) {
                Text(название.isEmpty ? "—" : название)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineSpacing(2)
                    .lineLimit(3)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(цена)
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if ф.торг && модель.ценаЧислом > 0 {
                        Text("· " + т("form_bargain").lowercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                ПотокЧипов(зазор: 6) {
                    ForEach(Array(чипы.enumerated()), id: \.offset) { _, чип in
                        HStack(spacing: 4) {
                            if let значок = чип.значок {
                                Image(systemName: значок)
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(чип.текст)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(КраскаПодачи.текст)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(КраскаПодачи.поле, in: Capsule())
                    }
                }
                if !описание.isEmpty {
                    Text(описание)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(5)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
    }

    /// Первое фото — со снимка на телефоне или по адресу сервера; нет фото — серая заглушка 120.
    @ViewBuilder
    private var обложка: some View {
        let первая = модель.плитки.first(where: { $0.ошибка == nil && ($0.превью != nil || $0.готова) })
        if let картинка = первая?.превью {
            Color.clear
                .frame(height: 190)
                .overlay {
                    Image(uiImage: картинка)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if let адрес = первая.flatMap({ Config.url($0.url) }) {
            /* Адрес фото сервера — только картинка, нажатием не открывается. */
            Color.clear
                .frame(height: 190)
                .overlay {
                    AsyncImage(url: адрес) { фаза in
                        if let изображение = фаза.image {
                            изображение.resizable().scaledToFill()
                        } else {
                            КраскаПодачи.поле
                        }
                    }
                }
                .clipped()
        } else {
            КраскаПодачи.поле
                .frame(height: 120)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                }
        }
    }

    private var цена: String {
        let цена = модель.ценаЧислом
        if цена > 0 { return ПодачаМодель.деньги(цена) + " ₸" }
        let ставка = модель.ставкаЧислом
        if модель.форма.аренда && ставка > 0 { return ПодачаМодель.деньги(ставка) + " ₸" }
        return т("price_negotiable")
    }

    private var чипы: [(текст: String, значок: String?)] {
        let ф = модель.форма
        var итог: [(текст: String, значок: String?)] = []
        let раздел = модель.справочники.имя(ф.раздел)
        if !раздел.isEmpty { итог.append((раздел, nil)) }
        if !ф.город.isEmpty { итог.append((ф.город, "mappin")) }
        if модель.состояниеВидно {
            let подписи = модель.подписиСостояния
            итог.append((ф.состояние == "new" ? подписи.н : подписи.б, nil))
        }
        let фото = модель.плитки.filter { $0.ошибка == nil }.count
        if фото > 0 { итог.append((String(фото) + " " + т("photo").lowercased(), nil)) }
        return итог
    }
}
