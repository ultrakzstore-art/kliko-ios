import SwiftUI
import UIKit

/**
 ПОДАЧА — ШАГИ «ЦЕНА И СОСТОЯНИЕ», «АДРЕС», «ДОПОЛНИТЕЛЬНО», «ПРОВЕРКА» И ОКНО «ПРОВЕРЬТЕ ПЕРЕД ПУБЛИКАЦИЕЙ», ЭТАП 42
 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 «Цена и состояние» — #add-card-price: состояние с подписями раздела, «Ваша цена» (у услуг — «необязательно» и
 «Договорная»), «Торг», подсказка «Срочно / Рынок / Высокая» (price_stats или оценка Kliko AI), аренда (посуточно /
 помесячно, залог, мин. срок, комплект, «Продаю тоже»), обмен или бартер, склад магазина. «Адрес» — #add-card-where:
 режим работы или время для связи, область → район → город, адрес. «Дополнительно» — рассрочка и кредит, доставка,
 знаки доверия (уходят после подачи). «Проверка» и окно перед публикацией — showPublishConfirm модуля compose:
 карточка как её увидят покупатели, «Вещь работает?», «Гарант-сделка» с причинами блокировки, ТОП (🔴 деньги —
 только Config.цифровыеПокупки), «Этого уже ждут».
 */

// MARK: - Цена и состояние

struct ШагЦена: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            КарточкаПодачи(т("step_price")) {
                if модель.состояниеВидно { состояние }
                if модель.правка && модель.нужнаИсправность { БлокИсправности(модель: модель) }
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
                        ПолеПодачи(т("form_stock_ph"), текст: цифры($модель.форма.склад, 6), клавиатура: .numberPad)
                    }
                }
            }
        }
    }

    /// updateCondUI: «Б/У / Новый», у недвижимости «Вторичный рынок / Новостройка», у транспорта «С пробегом / Без пробега».
    private var состояние: some View {
        let подписи = модель.подписиСостояния
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_condition"))
            HStack(spacing: 8) {
                ЧипПодачи(подписи.б, выбран: модель.форма.состояние == "used") { модель.форма.состояние = "used" }
                ЧипПодачи(подписи.н, выбран: модель.форма.состояние == "new") { модель.форма.состояние = "new" }
            }
        }
    }

    private var цена: some View {
        let услуга = модель.услугаИлиРабота
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("form_your_price") + " ₸", необязательно: услуга)
            ПолеПодачи("0", текст: ценаСвязь, клавиатура: .numberPad, заблокировано: услуга && модель.форма.торг)
            ПереключательПодачи(т(услуга ? "price_negotiable" : "form_bargain"), включено: торгСвязь)
            if услуга && модель.ценаЧислом == 0 {
                Text(т("form_no_price_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
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
        Button {
            модель.форма.цена = String(цена)
        } label: {
            VStack(spacing: 2) {
                Text(подпись)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Text(ПодачаМодель.деньги(цена) + " ₸")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// Блок аренды (#f-rent-block, setRentPeriod).
    private var аренда: some View {
        let недвижимость = модель.режим == .недвижимость
        let помесячно = модель.форма.период == "month"
        return КарточкаПодачи {
            if !недвижимость {
                ПереключательПодачи(т("form_for_rent"), включено: $модель.форма.аренда)
            }
            if модель.форма.аренда {
                if !недвижимость {
                    HStack(spacing: 8) {
                        ЧипПодачи(т("form_daily"), выбран: !помесячно) { сменитьПериод("day") }
                        ЧипПодачи(т("form_monthly"), выбран: помесячно) { сменитьПериод("month") }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т(помесячно ? "rent_price_month" : "form_price_per_day"))
                        ПолеПодачи(помесячно ? "150 000" : "5 000", текст: цифры($модель.форма.ставка, 12),
                                   клавиатура: .numberPad)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("form_deposit_field"))
                        ПолеПодачи("50 000", текст: цифры($модель.форма.залог, 12), клавиатура: .numberPad)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(т("form_min_rent"))
                    ПотокЧипов(зазор: 8) {
                        ForEach(срокиАренды, id: \.self) { срок in
                            ЧипПодачи(срок.подпись, выбран: модель.форма.минСрок == срок.ключ) {
                                модель.форма.минСрок = срок.ключ
                            }
                        }
                    }
                }
                if !недвижимость {
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(т("rent_kit"))
                        ПолеПодачи(т("rent_kit_ph"), текст: комплект)
                    }
                    ПереключательПодачи(т("also_sell"), подпись: т("also_sell_s"), включено: $модель.форма.тожеПродаю)
                }
                ЗаметкаПодачи(т("form_rent_note"), тон: .инфо, значок: "info.circle")
            }
        }
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

    /// Смена периода: мин. срок, которого нет в новом списке, — первый вариант (как у сайта).
    private func сменитьПериод(_ период: String) {
        var ф = модель.форма
        ф.период = период
        let допустимые = период == "month" ? ["1", "2", "3", "6", "12"] : ["1", "2", "3", "7", "14", "30"]
        if !допустимые.contains(ф.минСрок) { ф.минСрок = "1" }
        модель.форма = ф
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
            HStack(spacing: 8) {
                ЧипПодачи(ПодачаText.т("wrk_yes"), выбран: модель.форма.работает == "ok") { модель.форма.работает = "ok" }
                ЧипПодачи(ПодачаText.т("wrk_no"), выбран: модель.форма.работает == "bad") { модель.форма.работает = "bad" }
            }
        }
    }
}

// MARK: - Адрес

struct ШагАдрес: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var список: СписокВыбора? = nil
    @State private var свой = false

    init(модель: ПодачаМодель) {
        self.модель = модель
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
        VStack(alignment: .leading, spacing: 12) {
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
        }
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
        return КарточкаПодачи(т("form_location")) {
            СтрокаВыбора(регион?.имя ?? "", подсказка: т("form_region_ph")) {
                let м = модель
                список = СписокВыбора(заголовок: т("form_region_ph"),
                                      варианты: м.справочники.регионы.map { ВариантПоля(ключ: $0.id, подпись: $0.имя) }) { ключ in
                    м.выбратьРегион(ключ)
                }
            }
            if let регион, !регион.районы.isEmpty {
                СтрокаВыбора(регион.районы.first(where: { $0.id == модель.форма.район })?.имя ?? "",
                             подсказка: т(город ? "district_city_ph" : "form_district_ph")) {
                    let м = модель
                    список = СписокВыбора(заголовок: т(город ? "district_city_ph" : "form_district_ph"),
                                          варианты: регион.районы.map { ВариантПоля(ключ: $0.id, подпись: $0.имя) },
                                          сброс: т("spec_unset")) { ключ in
                        м.выбратьРайон(ключ)
                    }
                }
            }
            if город {
                ПолеПодачи(т("form_city_ph"), текст: Binding.constant(регион?.имя ?? ""), заблокировано: true)
            } else {
                let города = городаСписка(регион)
                if города.isEmpty {
                    ПолеПодачи(т("form_city_ph"), текст: городСвязь, заглавные: .words)
                } else {
                    СтрокаВыбора(модель.форма.город, подсказка: т("form_city_ph")) {
                        let м = модель
                        список = СписокВыбора(заголовок: т("form_city_ph"),
                                              варианты: города.map { ВариантПоля(ключ: $0, подпись: $0) },
                                              своё: т("spec_other_write")) { имя in
                            м.выбратьГород(имя)
                        }
                    }
                }
            }
            ПолеПодачи(т("form_address_ph"), текст: адресСвязь)
            Text(т("form_addr_hint"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func городаСписка(_ регион: РегионКЗ?) -> [String] {
        guard let регион else { return [] }
        if !модель.форма.район.isEmpty, let район = регион.районы.first(where: { $0.id == модель.форма.район }) {
            return район.города
        }
        var все: [String] = []
        for район in регион.районы { все.append(contentsOf: район.города) }
        return все
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
    let открытьСайт: (String) -> Void

    init(модель: ПодачаМодель, открытьСайт: @escaping (String) -> Void) {
        self.модель = модель
        self.открытьСайт = открытьСайт
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// WR_STOPS сайта; без PRO — до 7 дней (WR_FREE_MAX).
    private static let сроки: [Int] = [0, 3, 7, 14, 30, 60, 90, 180, 270, 365]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаметкаПодачи(т("form_additional_note"), тон: .серый, значок: "slider.horizontal.3")
            if модель.правка {
                /* У опубликованного сайт сохраняет эти настройки сразу своими окнами (openPayment / openDelivery /
                   openTrust) — отдельно от edit_item. Здесь — своё окно тех же полей (MyListings/PublishedSettings.swift). */
                КарточкаПодачи(т("form_additional"), подпись: т("cfg_edit_note")) {
                    КнопкаПодачиВторая(т("cfg_setup")) {
                        ЛистНастроекОбъявления.показать(модель: модель)
                    }
                }
            } else {
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
                ПодписьПоля(т("del_approx_time"))
                HStack(spacing: 8) {
                    ПолеПодачи(т("del_days_ph"), текст: дни)
                    Text(т("del_days_unit"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
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
        return КарточкаПодачи(т("wr_title"), подпись: т("wr_note")) {
            if let срок = срочные.first {
                VStack(alignment: .leading, spacing: 6) {
                    ПодписьПоля(срок.подпись)
                    ПотокЧипов(зазор: 8) {
                        ForEach(Self.сроки.filter { $0 <= предел }, id: \.self) { дни in
                            ЧипПодачи(ШагДополнительно.срокГарантии(дни), выбран: модель.форма.гарантияДней == дни) {
                                var ф = модель.форма
                                ф.гарантияДней = дни
                                ф.доверияЗадано = true
                                модель.форма = ф
                            }
                        }
                    }
                    if !модель.страница.pro {
                        Text(т("wr_pro_note"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
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
        VStack(alignment: .leading, spacing: 12) {
            КарточкаПодачи(т("pc_title"), подпись: т("pc_sub")) {
                ПревьюПодачи(модель: модель)
                if !модель.правка && модель.нужнаИсправность { БлокИсправности(модель: модель) }
                БлокГаранта(модель: модель)
                if модель.режим == .услуга {
                    ЗаметкаПодачи(т("pc_svc_note"), тон: .инфо, значок: "info.circle")
                }
                ЗаметкаПодачи(т("pc_mod_note"), тон: .серый, значок: "shield")
            }
            if !модель.правка { топ }
            if модель.ждут > 0 {
                ЗаметкаПодачи(т("reach_n").replacingOccurrences(of: "{n}", with: String(модель.ждут)), тон: .хорошо,
                              значок: "person.2")
            }
        }
    }

    /// ТОП при подаче. 🔴 Деньги: без Config.цифровыеПокупки — только сведения и текст сайта, покупки нет.
    @ViewBuilder
    private var топ: some View {
        if let выбран = модель.форма.топ {
            КарточкаПодачи(String(format: т("top_bar"), выбран.подпись),
                           подпись: String(format: т("top_bar_s"), ПодачаМодель.деньги(выбран.цена))) {
                КнопкаПодачиВторая(т("top_remove")) { модель.убратьТоп() }
            }
        } else if !модель.страница.пакеты.isEmpty {
            КарточкаПодачи(т("pups_badge") + " · " + т("pups_h"),
                           подпись: String(format: т("pups_sub"), модель.лимитФото)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• " + String(format: т("pups_30"), модель.лимитФото))
                    Text("• " + т("pups_top"))
                    Text("• " + т("pups_search"))
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
                if Config.цифровыеПокупки {
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
                } else {
                    ЗаметкаПодачи(т("no_digital"), тон: .серый, значок: "lock")
                }
            }
        }
    }
}

/// Карточка «Так объявление увидят покупатели» (showPublishConfirm): фото, название, цена, чипы, описание.
struct ПревьюПодачи: View {
    @ObservedObject var модель: ПодачаМодель

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            фото
            VStack(alignment: .leading, spacing: 8) {
                Text(модель.форма.название.isEmpty ? "—" : модель.форма.название)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.текст)
                цена
                ПотокЧипов(зазор: 6) {
                    ForEach(чипы, id: \.self) { чип in
                        Text(чип)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.текст)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.поверхность2, in: Capsule())
                    }
                }
                let описание = модель.форма.описание.trimmingCharacters(in: .whitespacesAndNewlines)
                if !описание.isEmpty {
                    Text(описание)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var фото: some View {
        let первая = модель.плитки.first(where: { $0.готова })
        Group {
            if let превью = первая?.превью {
                Color.clear.overlay { Image(uiImage: превью).resizable().scaledToFill() }
            } else if let адрес = первая.flatMap({ Config.url($0.url) }) {
                Color.clear.overlay {
                    AsyncImage(url: адрес) { фаза in
                        if let изображение = фаза.image {
                            изображение.resizable().scaledToFill()
                        } else {
                            Theme.поверхность2
                        }
                    }
                }
            } else {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "photo")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
        .frame(height: первая == nil ? 120 : 190)
        .frame(maxWidth: .infinity)
        .clipped()
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.md, topTrailingRadius: Theme.Радиус.md,
                                          style: .continuous))
    }

    @ViewBuilder
    private var цена: some View {
        if модель.режим == .услуга {
            Label(т("pc_no_price"), systemImage: "checkmark.shield")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
        } else {
            let число = модель.форма.аренда && модель.ценаЧислом == 0 ? модель.ставкаЧислом : модель.ценаЧислом
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(число > 0 ? ПодачаМодель.деньги(число) + " ₸" : (модель.форма.торг ? т("price_negotiable") : "—"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                if число > 0 && модель.форма.торг {
                    Text("· " + т("torg_small"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
    }

    /// Чипы: раздел, город, состояние (не у услуг и недвижимости), «N фото».
    private var чипы: [String] {
        var итог: [String] = []
        let раздел = модель.справочники.имя(модель.форма.раздел)
        if !раздел.isEmpty { итог.append(раздел) }
        let город = модель.форма.город.trimmingCharacters(in: .whitespaces)
        if !город.isEmpty { итог.append("📍 " + город) }
        if модель.режим != .услуга && модель.режим != .недвижимость && модель.состояниеВидно {
            итог.append(модель.форма.состояние == "new" ? т("pc_new") : т("cond_used"))
        }
        итог.append(String(format: т("pc_photos"), модель.готовыеФото.count))
        return итог
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
                    ЗаметкаПодачи(т("pc_esc_off"), тон: .серый)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(т("pc_sub"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                    ПревьюПодачи(модель: модель)
                    if модель.нужнаИсправность { БлокИсправности(модель: модель) }
                    БлокГаранта(модель: модель)
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
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 10) {
                    КнопкаПодачиВторая(т("pc_back")) { закрыть() }
                    КнопкаПодачи(т("pc_publish"), занято: модель.отправляем) { модель.опубликовать() }
                }
                .padding(12)
                .background(Theme.поверхность)
            }
            .navigationTitle(т("pc_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Theme.акцент)
    }
}
