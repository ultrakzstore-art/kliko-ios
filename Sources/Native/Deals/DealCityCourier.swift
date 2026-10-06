import CoreLocation
import SwiftUI
import UIKit

/**
 КУРЬЕР ПО ГОРОДУ — СВОЙ БЛОК (clocal.delivery; clocalRender, clocalYandexPanel, clocalManual сайта, карта §9.5,
 CAB @452926–468000 и @530199–542700).

 Этапы «Оплачено · Забрал · Вручил · Готово», адреса «Забрать / Привезти» (без адреса — «точка на карте» или
 «уточняется»). Дальше — как у сайта:
   · Яндекс (yandex_on): статус заявки, код для курьера (или «код придёт в SMS»), курьер и машина, получатель-подарок,
     сроки («Курьер будет у вас · через ~N мин · 14:05»), «Позвонить курьеру» (clocal_courier_phone → окно с подменным
     номером и добавочным), «Отследить курьера на карте» (своя карточка «Отслеживание»), кто оплатил доставку;
     сбой (yandex_failed) — «Открыть спор — вернуть деньги» покупателю, «Заказать курьера снова» организатору;
   · без Яндекса, продавец ждёт курьера: «Я на месте, товар готов» (clocal_ready; без адреса — окно «Откуда забрать
     товар?»), «Забрать в другом месте — сменить точку» (clocal_set_pickup), 30 минут прошли — предупреждение; готов —
     «Сменить точку забора» и, если он организатор, «Заказать курьера Яндекса» (clocal_yandex_order) или ручной вызов;
   · покупатель ждёт: «Ждём продавца… (осталось ~N мин)», продавец не успел за 30 минут — «Отменить — вернуть деньги»
     (окно отмены сделки); продавец готов — «Вызовите курьера кнопкой ниже» / ручной вызов организатором;
   · курьер везёт: ПИН покупателя, «Осмотрите товар при получении», «Не приму — оформить возврат» (clocal_refuse);
   · ручной вызов (clocalManual): «Забрать» / «Привезти» с копированием, «Скопировать для курьера», «Построить маршрут»
     (2ГИС), код, «Отправить ссылку курьеру» (/courier.php?t=<courier_token>);
   · покупателю при оплаченном курьере, пока курьер не забрал, — «Заберу сам — отменить курьера» (ship_drop, окно денег).
 Время (ready_deadline, сроки Яндекса) — по часам сервера (srv_now), как clcSrvNow сайта.
 */
struct БлокКурьераПоГороду: View {
    let сделка: Сделка
    let курьер: КурьерСделки
    @ObservedObject var модель: КарточкаСделкиМодель
    @ObservedObject var передача: ПередачаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var я: Bool { сделка.продавец }
    /// y сайта: доставку организую я (arranger совпадает с моей ролью).
    private var организую: Bool { курьер.организатор == (я ? "seller" : "buyer") }

    private var этап: Int {
        let этапы: [String: Int] = ["awaiting_courier": 1, "picked_up": 2, "delivered": 3, "returned": 1]
        return этапы[курьер.статус] ?? 0
    }

    var body: some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: СделкиText.т(курьер.яндекс ? "clc_ya_h" : "md_courier"), символ: "car")
            ЭтапыКурьера(этап: этап)
            if курьер.яндекс {
                АдресаКурьера(сделка: сделка, курьер: курьер)
                ПанельЯндекса(сделка: сделка, курьер: курьер, модель: модель, передача: передача, действие: действие)
            } else {
                /* Минуты до конца срока готовности — по часам сервера, пересчёт раз в 20 с. */
                TimelineView(.periodic(from: .now, by: 20)) { _ in
                    безЯндекса
                }
            }
            if !я && курьер.статус == "awaiting_courier" && сделка.курьерЯндексаОплачен {
                КнопкаСделки(т("hnd_to_self"), вид: .вторая, символ: "figure.walk") { действие(.деньги(.заберуСам)) }
            }
        }
    }

    // MARK: - Без Яндекса (ручной вызов и готовность продавца)

    /// ready_deadline: осталось секунд по часам сервера (0 — срока нет).
    private var осталосьДоСрока: Double {
        курьер.срокГотовности > 0 ? курьер.срокГотовности - сделка.сейчасНаСервере : 0
    }

    /// x сайта: срок был и прошёл.
    private var поздно: Bool { курьер.срокГотовности > 0 && осталосьДоСрока <= 0 }

    /// k сайта: целые минуты вверх.
    private var минутДоСрока: Int { max(0, Int((min(осталосьДоСрока, 86_400) / 60).rounded(.up))) }

    @ViewBuilder
    private var безЯндекса: some View {
        VStack(alignment: .leading, spacing: 10) {
            if курьер.статус == "returned" {
                ЗаметкаСделки(Text(т("clc_ret_way")), вид: .предупреждение, символ: "arrow.uturn.backward")
            } else if курьер.статус == "delivered" {
                ЗаметкаСделки(Text(т(я ? "clc_dlv_s" : "clc_dlv_b")), вид: .хорошо, символ: "checkmark.circle")
            } else if я {
                if курьер.статус == "awaiting_courier" {
                    продавецЖдёт
                } else {
                    ЗаметкаСделки(Text(т("clc_handed_s")), вид: .хорошо, символ: "checkmark.circle")
                }
            } else if курьер.статус == "awaiting_courier" {
                покупательЖдёт
            } else {
                курьерВезёт
            }
        }
    }

    @ViewBuilder
    private var продавецЖдёт: some View {
        АдресаКурьера(сделка: сделка, курьер: курьер)
        if курьер.готов {
            КнопкаСделки(т("clc_pk_btn"), вид: .вторая, символ: "mappin.and.ellipse", доступна: !передача.идёт) {
                передача.лист = .адрес(.точкаЗабора)
            }
            if организую {
                if сделка.яндексДоступен && сделка.курьерЯндексаОплачен {
                    кнопкиЗаказа
                } else {
                    РучнойКурьер(сделка: сделка, курьер: курьер, модель: модель, действие: действие)
                }
            } else {
                ЗаметкаСделки(Text(т("clc_wait_org")), вид: .предупреждение)
                КодКурьера(курьер: курьер, продавец: true)
            }
        } else {
            if поздно {
                ЗаметкаСделки(Text(т("clc_late_s")), вид: .плохо, символ: "clock")
            } else {
                let хвост = курьер.срокГотовности > 0 ? ПередачаText.т("clc_left_s", n: String(минутДоСрока)) : ""
                let суть = т("clc_wait_s").replacingOccurrences(of: "{left}", with: хвост)
                ЗаметкаСделки(ТекстСделки.сЖирным(т(организую ? "clc_wait_s_org" : "clc_wait_s_b") + " " + суть),
                              вид: .предупреждение)
            }
            КнопкаСделки(т("clc_pk_btn2"), вид: .вторая, символ: "mappin.and.ellipse", доступна: !передача.идёт) {
                передача.лист = .адрес(.точкаЗабора)
            }
            КнопкаСделки(т("clc_ready_btn"), вид: .главная, символ: "car", доступна: !передача.идёт) {
                передача.товарГотов()
            }
        }
    }

    @ViewBuilder
    private var покупательЖдёт: some View {
        АдресаКурьера(сделка: сделка, курьер: курьер)
        if курьер.готов {
            if сделка.яндексДоступен {
                ЗаметкаСделки(Text(т(организую ? "clc_b_ready_org" : "clc_b_ready_go")), вид: .хорошо)
                if организую {
                    if сделка.курьерЯндексаОплачен {
                        кнопкиЗаказа
                    } else {
                        РучнойКурьер(сделка: сделка, курьер: курьер, модель: модель, действие: действие)
                    }
                }
            } else if организую {
                РучнойКурьер(сделка: сделка, курьер: курьер, модель: модель, действие: действие)
            } else {
                ЗаметкаСделки(Text(т("clc_b_ready_man")), вид: .предупреждение)
            }
        } else if поздно {
            ЗаметкаСделки(ТекстСделки.сЖирным(т("clc_b_late")), вид: .плохо, символ: "clock")
            /* dealCancel: окно отмены сделки — деньги вернутся полностью. */
            КнопкаСделки(т("clc_b_late_btn"), вид: .вторая, символ: "arrow.uturn.backward") { действие(.деньги(.отменить)) }
        } else {
            let хвост = курьер.срокГотовности > 0 ? ПередачаText.т("clc_left_b", n: String(минутДоСрока)) : ""
            ЗаметкаСделки(Text(т("clc_b_wait").replacingOccurrences(of: "{left}", with: хвост)), вид: .предупреждение)
        }
    }

    @ViewBuilder
    private var курьерВезёт: some View {
        КодКурьера(курьер: курьер, продавец: false)
        let вручил = курьер.статус == "delivered"
        ЗаметкаСделки(Text(т(вручил ? "clc_b_handed" : "clc_b_way") + " ") + ТекстСделки.сЖирным(т("clc_b_inspect")),
                      вид: вручил ? .хорошо : .предупреждение)
        КнопкаСделки(т("ret_rf_btn"), вид: .вторая, символ: "arrow.uturn.backward", доступна: !передача.идёт) {
            передача.лист = .отказ
        }
    }

    /// clocalOrderBtns: «Заказать курьера Яндекса» и «Доставка оплачена покупателем…» (не при yandex_on).
    @ViewBuilder
    private var кнопкиЗаказа: some View {
        КнопкаСделки(т("yac_order"), вид: .главная, символ: "car", доступна: !передача.идёт) { передача.заказатьЯндекс() }
        Text(т("yac_order_s"))
            .font(.system(size: 12))
            .foregroundStyle(Theme.текстВторой)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Адреса «Забрать / Привезти» (.clc-addr)

struct АдресаКурьера: View {
    let сделка: Сделка
    let курьер: КурьерСделки

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            строка(т("clc_from"), адрес: курьер.адресЗабора, точка: курьер.точкаЗабора, дверь: сделка.дверьОткуда,
                   краска: Theme.зелёный)
            строка(т("clc_to"), адрес: курьер.адресДоставки, точка: курьер.точкаДоставки, дверь: сделка.дверьКуда,
                   краска: КраскаСделокКабинета.плохоТекст)
        }
    }

    /// clocalAddrLabel: адрес (с подъездом и этажом), иначе «точка на карте», иначе «уточняется».
    private func строка(_ подпись: String, адрес: String, точка: ТочкаСделки?, дверь: ДверьСделки?,
                        краска: Color) -> some View {
        let д = дверь?.текст ?? ""
        let значение: Text
        if !адрес.isEmpty {
            значение = Text(д.isEmpty ? адрес : адрес + ", " + д).bold()
        } else if точка != nil {
            значение = Text(Image(systemName: "mappin")).foregroundColor(КраскаСделокКабинета.хорошоТекст)
                + Text(" " + т("clc_pt_map")).bold().foregroundColor(КраскаСделокКабинета.хорошоТекст)
        } else {
            значение = Text(т("clc_pt_tbd")).bold()
        }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(краска)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            (Text(подпись + " ") + значение)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

/// clocalCodeBox: продавцу, пока курьер едет за товаром, — код получения; покупателю, пока курьер везёт, — ПИН.
struct КодКурьера: View {
    let курьер: КурьерСделки
    let продавец: Bool

    var body: some View {
        if продавец && курьер.статус == "awaiting_courier" && !курьер.кодЗабора.isEmpty {
            ПлашкаКодаПередачи(подпись: СделкиText.т("clc_code_s"), код: курьер.кодЗабора)
        } else if !продавец && курьер.статус == "picked_up" && !курьер.пин.isEmpty {
            ПлашкаКодаПередачи(подпись: СделкиText.т("clc_pin_b"), код: курьер.пин)
        }
    }
}

// MARK: - Ручной вызов курьера (clocalManual)

struct РучнойКурьер: View {
    let сделка: Сделка
    let курьер: КурьерСделки
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var я: Bool { сделка.продавец }

    /// «адрес — контакт» (l и d сайта).
    private var откуда: String { Self.склеить(курьер.адресЗабора, курьер.контактОтправителя) }
    private var куда: String { Self.склеить(курьер.адресДоставки, курьер.контактПолучателя) }

    private static func склеить(_ адрес: String, _ контакт: String) -> String {
        контакт.isEmpty ? адрес : адрес + " — " + контакт
    }

    /// data-all сайта: «Забрать: …\nПривезти: …\nТовар: …».
    private var всё: String {
        var строки = [т("clc_from") + " " + откуда, т("clc_to") + " " + куда]
        if !курьер.товар.isEmpty { строки.append(т("clc_product") + " " + курьер.товар) }
        return строки.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаметкаСделки(Text(т(я ? "clc_man_s" : "clc_man_b")), вид: .предупреждение)
            VStack(alignment: .leading, spacing: 8) {
                участок(т("clc_leg_from"), курьер.адресЗабора, курьер.контактОтправителя, символ: "mappin", копия: откуда)
                участок(т("clc_leg_to"), курьер.адресДоставки, курьер.контактПолучателя, символ: "flag", копия: куда)
            }
            HStack(spacing: 8) {
                КнопкаСделки(т("clc_copy"), вид: .главная, символ: "doc.on.doc") { скопировать(всё) }
                КнопкаСделки(т("clc_route"), вид: .вторая, символ: "point.topleft.down.to.point.bottomright.curvepath") {
                    маршрут()
                }
            }
            КодКурьера(курьер: курьер, продавец: я)
            if !курьер.токенКурьера.isEmpty && курьер.организатор == (я ? "seller" : "buyer") {
                КнопкаСделки(т("clc_share"), вид: .вторая, символ: "link") { отправитьСсылку() }
            }
            Text(т("clc_man_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// .clc-leg: значок, «Забрать» / «Привезти», адрес и контакт, кнопка копирования; пусто — нет строки.
    @ViewBuilder
    private func участок(_ подпись: String, _ адрес: String, _ контакт: String, символ: String, копия: String) -> some View {
        if !адрес.isEmpty || !контакт.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: символ)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                    .frame(width: 30, height: 30)
                    .background(КраскаСделокКабинета.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm,
                                                                                    style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(подпись)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    if !адрес.isEmpty {
                        Text(адрес)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !контакт.isEmpty {
                        Text(контакт)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    скопировать(копия)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("clc_copy_a11y") + ": " + подпись)
            }
        }
    }

    /// clocalCopy: в буфер и «Данные скопированы — вставьте в заявку курьеру».
    @MainActor
    private func скопировать(_ текст: String) {
        guard !текст.isEmpty else { return }
        UIPasteboard.general.string = текст
        модель.показать(т("clc_copied"))
    }

    /// clocalRoutePick: 2ГИС — по двум точкам, по одной или поиском по адресу; адреса нет — «уточните в чате».
    @MainActor
    private func маршрут() {
        guard let адрес = Self.маршрут2ГИС(курьер) else {
            модель.показать(т("clc_no_addr"))
            return
        }
        действие(.ссылка(адрес))
    }

    static func маршрут2ГИС(_ к: КурьерСделки) -> URL? {
        let ч = НавигаторыСделки.ч
        if let а = к.точкаЗабора, let б = к.точкаДоставки {
            return URL(string: ["https://2gis.kz/directions/points/", ч(а.долгота), "%2C", ч(а.широта), "%7C",
                                ч(б.долгота), "%2C", ч(б.широта)].joined())
        }
        if let б = к.точкаДоставки {
            return URL(string: ["https://2gis.kz/directions/points/%7C", ч(б.долгота), "%2C", ч(б.широта)].joined())
        }
        if let а = к.точкаЗабора {
            return URL(string: ["https://2gis.kz/directions/points/%7C", ч(а.долгота), "%2C", ч(а.широта)].joined())
        }
        let текст = к.адресДоставки.isEmpty ? к.адресЗабора : к.адресДоставки
        let запрос = СделкиAPI.вАдрес(текст)
        return запрос.isEmpty ? nil : URL(string: "https://2gis.kz/search/" + запрос)
    }

    /// clocalShare: ссылка курьеру /courier.php?t=<courier_token> — системным листом «Поделиться».
    @MainActor
    private func отправитьСсылку() {
        guard let адрес = Config.url("/courier.php?t=" + СделкиAPI.вАдрес(курьер.токенКурьера)) else { return }
        ПоделитьсяСайта.системныйЛист([т("clc_share_x") + " " + адрес.absoluteString])
    }
}

// MARK: - Курьер Яндекса (clocalYandexPanel, clocalEtaHtml)

struct ПанельЯндекса: View {
    let сделка: Сделка
    let курьер: КурьерСделки
    @ObservedObject var модель: КарточкаСделкиМодель
    @ObservedObject var передача: ПередачаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var я: Bool { сделка.продавец }
    private var статус: String { курьер.статусЯндекса }
    /// a сайта: вручено или доставлено.
    private var вручено: Bool { ["delivered", "delivered_finish", "pay_waiting"].contains(статус) }

    var body: some View {
        if курьер.сбойЯндекса {
            сбой
        } else {
            ЗаметкаСделки(Text(СтатусЯндекса.текст(статус)), вид: вручено ? .хорошо : .предупреждение,
                          символ: вручено ? "checkmark.circle" : "clock")
            код
            if !курьер.имяКурьера.isEmpty { курьерИМашина }
            СтрокаПолучателя(сделка: сделка, модель: модель)
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                сроки
            }
            if курьер.звонок {
                КнопкаСделки(т("yac_call"), вид: .главная, символ: "phone", доступна: !передача.идёт) {
                    передача.позвонитьКурьеру()
                }
            }
            if (курьер.ссылкаСлежения.hasPrefix("https://") || !статус.isEmpty) && !вручено {
                /* Не страница Яндекса — своя карточка «Отслеживание» листом. */
                КнопкаСделки(СделкиText.т("yac_track"), вид: .вторая, символ: "map") { действие(.отслеживание) }
            }
            стоимость
        }
    }

    /// yandex_failed: курьер не довёз — спор покупателю; заявка не состоялась — «Заказать курьера снова».
    @ViewBuilder
    private var сбой: some View {
        let вПути = курьер.статус != "awaiting_courier"
        ЗаметкаСделки(Text(т(вПути ? "yac_fail_picked" : "yac_fail_new")), вид: .плохо, символ: "exclamationmark.triangle")
        if вПути && !я {
            КнопкаСделки(т("yac_dispute"), вид: .главная, символ: "exclamationmark.bubble") { действие(.спор) }
        } else if вПути {
            ЗаметкаСделки(Text(т("clc_seller_dispute")), вид: .серый)
        } else if курьер.организатор == (я ? "seller" : "buyer") || я {
            КнопкаСделки(т("yac_again"), вид: .главная, символ: "car", доступна: !передача.идёт) { передача.заказатьЯндекс() }
        }
    }

    /// Код для курьера (return — код возврата) и попытки; нет кода, но придёт SMS — строка об этом.
    @ViewBuilder
    private var код: some View {
        if !курьер.кодЯндекса.isEmpty {
            let ключ: String = курьер.кодДля == "return" ? "yac_code_ret"
                : (я ? "yac_code_s" : (сделка.подарок ? "yac_code_rcp" : "yac_code_b"))
            VStack(spacing: 4) {
                ПлашкаКодаПередачи(подпись: т(ключ), код: курьер.кодЯндекса)
                if курьер.кодПопыток > 0 {
                    Text(ПередачаText.т("yac_code_left", n: String(курьер.кодПопыток)))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        } else if курьер.кодВСМС {
            ПодписьСделки(т(я ? "yac_code_sms_s" : (сделка.подарок ? "yac_code_sms_rcp" : "yac_code_sms_b")))
        }
    }

    /// Курьер · машина · цвет на зелёной подложке.
    private var курьерИМашина: some View {
        var хвост = ""
        if !курьер.машина.isEmpty { хвост += " · " + курьер.машина }
        if !курьер.цветМашины.isEmpty { хвост += " · " + курьер.цветМашины }
        return HStack(spacing: 8) {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                .accessibilityHidden(true)
            (Text(курьер.имяКурьера).bold() + Text(хвост).foregroundColor(Theme.текстВторой))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(КраскаСделокКабинета.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// clocalEtaHtml: возврат — «Курьер будет у вас / Вернёт продавцу»; иначе «Курьер будет у …» (пока не забрал) и
    /// «Привезёт …».
    private var строкиСроков: [(String, Double)] {
        let возврат = ["returning", "return_arrived", "ready_for_return_confirmation"].contains(статус)
        let везёт = ["pickuped", "delivery_arrived", "ready_for_delivery_confirmation"].contains(статус)
        var строки: [(String, Double)] = []
        if возврат {
            if курьер.срокВозврата > 0 { строки.append((т(я ? "yac_eta_you" : "yac_eta_back"), курьер.срокВозврата)) }
        } else {
            if !везёт && курьер.срокУПродавца > 0 {
                строки.append((т(я ? "yac_eta_you" : "yac_eta_seller"), курьер.срокУПродавца))
            }
            if курьер.срокУПокупателя > 0 {
                let ключ = сделка.подарок ? "yac_eta_rcp" : (я ? "yac_eta_buyer" : "yac_eta_you2")
                строки.append((т(ключ), курьер.срокУПокупателя))
            }
        }
        return строки
    }

    @ViewBuilder
    private var сроки: some View {
        let строки = строкиСроков
        if !строки.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(строки.enumerated()), id: \.offset) { пара in
                    HStack(spacing: 8) {
                        Text(пара.element.0)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                        Spacer(minLength: 4)
                        Text(Self.срок(пара.element.1, сейчас: сделка.сейчасНаСервере))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// clocalEtaTxt: ≤ 90 с — «вот-вот»; меньше часа — «через ~N мин · 14:05»; иначе «к 14:05».
    static func срок(_ когда: Double, сейчас: Double) -> String {
        let т: (String) -> String = ПередачаText.т
        let осталось = когда - сейчас
        if осталось <= 90 { return т("yac_eta_now") }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.dateFormat = "HH:mm"
        let время = ф.string(from: Date(timeIntervalSince1970: когда))
        let минут = Int((min(осталось, 864_000) / 60).rounded())
        if минут < 60 {
            return ПередачаText.т("yac_eta_min", n: String(минут)) + " · " + время
        }
        return т("yac_eta_at").replacingOccurrences(of: "{t}", with: время)
    }

    /// Кто платит: оплачено при покупке, за счёт продавца, цена Яндекса или «по тарифу».
    @ViewBuilder
    private var стоимость: some View {
        Group {
            if сделка.доставка > 0 {
                Text(т("yac_paid") + " ") + Text(СделкиФормат.тенге(сделка.доставка)).bold()
            } else if сделка.доставкаЗаСчётПродавца > 0 {
                Text(я ? String(format: СделкиText.т("hnd_ya_ss_free"), СделкиФормат.тенге(сделка.доставкаЗаСчётПродавца))
                       : т("co_ship_free"))
            } else if курьер.ценаЯндекса > 0 {
                let валюта = курьер.валютаЯндекса.isEmpty || курьер.валютаЯндекса == "KZT" ? " ₸" : " " + курьер.валютаЯндекса
                Text(т("yac_price") + " ")
                    + Text(СделкиФормат.деньги(тенгеБезПереполнения(курьер.ценаЯндекса.rounded())) + валюта).bold()
            } else {
                Text(т("yac_tariff"))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.текстВторой)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Окно адреса (clocalModal: clocalReady, clocalPickupModal, clocalCallCourier)

struct ОкноАдресаКурьера: View {
    let вид: ВидАдресаКурьера
    let сделка: Сделка?
    @ObservedObject var передача: ПередачаСделкиМодель
    /// «Указать на карте» (только покупатель в «Куда привезти товар?»): окно уезжает, открывается карта точки доставки.
    let наКарте: () -> Void

    @StateObject private var место = МестоТелефона()
    @State private var адрес: String
    /// _clcGrab сайта: место, отмеченное «Определить».
    @State private var точка: ТочкаСделки? = nil
    @State private var гео: СостояниеГео = .нет
    @FocusState private var фокус: Bool

    private enum СостояниеГео: Equatable {
        case нет
        case ищем
        case есть
        case неВышло
    }

    init(вид: ВидАдресаКурьера, сделка: Сделка?, передача: ПередачаСделкиМодель, наКарте: @escaping () -> Void) {
        self.вид = вид
        self.сделка = сделка
        self.передача = передача
        self.наКарте = наКарте
        let начальный: String
        switch вид {
        case .готов:
            начальный = ""
        case .точкаЗабора:
            начальный = сделка?.курьер?.адресЗабора ?? ""
        case .куда(let продавец):
            начальный = продавец ? "" : (сделка?.адресКуда ?? "")
        }
        _адрес = State(initialValue: начальный)
    }

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var продавецКуда: Bool {
        if case .куда(let продавец) = вид { return продавец }
        return false
    }

    private var естьГео: Bool {
        if case .куда(let продавец) = вид { return !продавец }
        return true
    }

    private var естьКарта: Bool {
        if case .куда(let продавец) = вид { return !продавец }
        return false
    }

    private var слова: (заголовок: String, подпись: String, пусто: String, гео: String, пояснение: String, кнопка: String) {
        switch вид {
        case .готов:
            return (т("clc_rd_t"), т("clc_rd_l"), т("clc_rd_ph"), т("clc_here"), т("clc_rd_s"), т("clc_rd_ok"))
        case .точкаЗабора:
            return (т("clc_pk_t"), т("clc_pk_l"), т("clc_rd_ph"), т("clc_here"), т("clc_pk_s"), т("clc_pk_ok"))
        case .куда(let продавец):
            return (т(продавец ? "clc_call_ts" : "clc_call_tb"), т("clc_call_lbl"), т("clc_call_ph"), т("clc_geo_me"),
                    т(продавец ? "clc_call_ss" : "clc_call_sb"), т("clc_call_ok"))
        }
    }

    var body: some View {
        let с = слова
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ШапкаОкнаПередачи(заголовок: с.заголовок, закрыть: { передача.лист = nil })
                Text(с.подпись)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                TextField(с.пусто, text: $адрес, axis: .vertical)
                    .lineLimit(1...3)
                    .textContentType(.fullStreetAddress)
                    .focused($фокус)
                    .modifier(ПолеДенегСделки())
                    .onChange(of: адрес) { _, новое in
                        if новое.count > 300 { адрес = String(новое.prefix(300)) }
                    }
                if естьГео { кнопкаГео(с.гео) }
                if естьКарта {
                    КнопкаСделки(т("clc_map_pick"), вид: .вторая, символ: "map") { наКарте() }
                }
                ПодписьСделки(с.пояснение)
                ОшибкаОкнаПередачи(текст: передача.ошибкаОкна)
                КнопкаСделки(с.кнопка, вид: .главная, символ: "car", доступна: !передача.идёт) { отправить() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
        .onChange(of: место.координата?.latitude) { _, _ in
            guard let к = место.координата else { return }
            приняли(к.latitude, к.longitude)
        }
        .onChange(of: место.ищет) { _, ищет in
            if !ищет && место.координата == nil && гео == .ищем { неВышло() }
        }
        .onChange(of: место.номерСбоя) { _, _ in
            if гео == .ищем { неВышло() }
        }
    }

    /// clocalGrab: «Определяем…» → «✓ Местоположение отмечено» (адрес по точке — в пустое поле) или «Не удалось…».
    private func кнопкаГео(_ надпись: String) -> some View {
        let текст: String
        switch гео {
        case .нет: текст = надпись
        case .ищем: текст = т("clc_geo_wait")
        case .есть: текст = т("clc_geo_ok")
        case .неВышло: текст = т("clc_geo_fail")
        }
        return Button {
            гео = .ищем
            место.запросить()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 13, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(гео == .есть ? КраскаСделокКабинета.хорошоТекст : КраскаСделокКабинета.акцент)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(гео == .ищем)
    }

    private func приняли(_ широта: Double, _ долгота: Double) {
        guard let к = ТочкаСделки(широта, долгота) else {
            неВышло()
            return
        }
        точка = к
        гео = .есть
        guard адрес.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let координата = CLLocationCoordinate2DMake(широта, долгота)
        Task { @MainActor in
            if let найден = await ЛистТочкиСделки.адресПоТочке(координата),
               адрес.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                адрес = найден
            }
        }
    }

    private func неВышло() {
        гео = .неВышло
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if гео == .неВышло { гео = .нет }
        }
    }

    /// «Готов — вызвать курьера» / «Сохранить точку» / «Вызвать курьера»: пусто и без места — просьба (кроме точки забора).
    private func отправить() {
        let текст = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        switch вид {
        case .готов:
            guard !текст.isEmpty || точка != nil else {
                передача.ошибкаОкна = т("clc_rd_need")
                return
            }
            фокус = false
            передача.готовЗдесь(адрес: текст, точка: точка)
        case .точкаЗабора:
            фокус = false
            передача.точкаЗабора(адрес: текст, точка: точка)
        case .куда(let продавец):
            guard !текст.isEmpty || (!продавец && точка != nil) else {
                передача.ошибкаОкна = т("clc_call_need")
                return
            }
            фокус = false
            передача.вызватьКурьера(продавец: продавец, адрес: текст, точка: продавец ? nil : точка)
        }
    }
}

// MARK: - Звонок курьеру (clocalCourierCall)

/// «Звонок курьеру»: номер, добавочный, «Номер подменный…», «Номер действует ~N мин.», «Позвонить» и «Закрыть».
struct ОкноЗвонкаКурьеру: View {
    let звонок: ЗвонокКурьеруТрека
    let закрыть: () -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ШапкаОкнаПередачи(заголовок: т("yac_call_t"), закрыть: закрыть)
                VStack(alignment: .leading, spacing: 8) {
                    поле(т("yac_call_num"), звонок.номер)
                    if !звонок.добавочный.isEmpty { поле(т("yac_call_ext"), звонок.добавочный) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                ПодписьСделки(пояснение)
                if let адрес = звонок.адрес {
                    КнопкаСделки(т("yac_call_go"), вид: .главная, символ: "phone") { UIApplication.shared.open(адрес) }
                }
                КнопкаСделки(т("yac_call_close"), вид: .вторая) { закрыть() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }

    private var пояснение: String {
        let срок = звонок.минут > 0 ? " " + ПередачаText.т("yac_call_ttl", n: String(звонок.минут)) : ""
        return т("yac_call_h") + срок
    }

    private func поле(_ подпись: String, _ значение: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            Text(значение)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.текст)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}
