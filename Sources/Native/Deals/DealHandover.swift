import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ПЕРЕДАЧА (#dm-clocal, этап 43; clocalRender сайта, карта §4.9).

 Показывается для товара и услуги в held / shipped / delivered. Что рисовать — в том же порядке, что у сайта:
   1. перевозчик (ship_mode=carrier и доставка оплачена) — СДЭК / Exline / Avis: трек, этап, пункт приёма, «Оформить
      отправку» (car_points → car_order: отправку уже оплатил покупатель, запрос денег не двигает);
   2. посылка с кодом в коробке, 3. встреча с QR — коды подтверждают получение и отпускают деньги (этап 44): заголовок
      сайта и страница сделки;
   4. способ не выбран (held) — «Как передадите товар?» / «Как хотите получить товар?»: ТК, «Заберу сам» / «Покупатель
      заберёт сам» → «Отвезу сам / Поеду сам» и «Передам курьеру / Отправлю курьера» (set_handover); платный курьер
      Яндекса и отмена оплаченного курьера — деньги, страница сайта;
      способ выбран — «Из рук в руки» / «Доставка курьером» / «Отправка транспортной компанией»: что делать сейчас,
      «Откуда» / «Куда» с копированием, «Построить маршрут» (Яндекс Go и 2ГИС), «Вызвать курьера» (Яндекс Go — курьер,
      2ГИС — такси; нажатие отмечает courier_called), ссылка отслеживания (set_track, только Яндекс Go и inDrive),
      «Изменить способ…» (set_handover "");
   5. курьер по городу (clocal.delivery) — этапы «Оплачено · Забрал · Вручил · Готово», статус Яндекса, коды для курьера,
      «Отследить курьера на карте»; вызов, готовность, отказ и возврат — деньги и коды (этап 44), страница сайта.
 Правка адресов (карта, «Указать точку», «Указать адрес» отправки) — своё окно ЛистТочкиСделки (DealPickupMap.swift,
 set_pickup сайта). «Отправить другому человеку — подарок» — пока страницей сделки сайта.
 */
struct БлокПередачи: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    @State private var полеСсылки = false

    init(сделка: Сделка, модель: КарточкаСделкиМодель, действие: @escaping (НажатиеСделки) -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    /// Блок есть только у товара и услуги в held / shipped / delivered (renderDeal → clocalLoad).
    static func нужен(_ с: Сделка) -> Bool {
        (с.режим == "goods" || с.режим == "service") && ["held", "shipped", "delivered"].contains(с.статус)
    }

    var body: some View {
        if сделка.черезПеревозчика {
            БлокПеревозчика(сделка: сделка, модель: модель, действие: действие)
        } else if сделка.естьПосылка {
            сводка(заголовок: т(сделка.посылкаЧерезТК ? "prc_h_tk" : "prc_h_cr"), символ: "shippingbox")
        } else if сделка.естьВстреча {
            сводка(заголовок: т("meet_t"), символ: "person.2")
        } else if let курьер = сделка.курьер {
            if Config.деньгиСделок && сделка.продавец && ["returning", "returned_to_seller"].contains(курьер.статус) {
                /* Этап 44: продавец подтверждает возврат сам (cancel {accept_fault} + clocal_return_confirm). */
                БлокВозвратаПродавцу(сделка: сделка, статус: курьер.статус, действие: действие)
            } else if ["returning", "returned_to_seller", "refunded"].contains(курьер.статус) {
                сводка(заголовок: т("ret_h"), символ: "arrow.uturn.backward")
            } else {
                блокКурьера(курьер)
            }
        } else if сделка.статус == "held" {
            if сделка.способПередачи.isEmpty { выборСпособа } else { блокСпособа }
        } else if !сделка.способПередачи.isEmpty && (сделка.статус == "shipped" || сделка.статус == "delivered") {
            блокСпособа
        }
    }

    /// Встреча, посылка, возврат: заголовок сайта и страница сделки — их шаги подтверждают передачу кодами (деньги).
    private func сводка(заголовок: String, символ: String) -> some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: заголовок, символ: символ)
            КнопкаСделки(т("site_deal"), вид: .вторая, наСайт: true) { действие(.наСайт) }
        }
    }

    // MARK: - Выбор способа (held, способ не выбран)

    private var выборСпособа: some View {
        let я = сделка.продавец
        return БлокСделки {
            ЗаголовокБлокаСделки(текст: т(я ? "hnd_q_s2" : "hnd_q_b"), символ: "shippingbox")
            ПодписьСделки(т(я ? "hnd_q_ss" : "hnd_q_s"))
            if я {
                ЗаметкаСделки(Text(т("hnd_wait_t")).bold() + Text("\n" + т("hnd_wait_s3")), вид: .предупреждение)
                строкаЗабора
            }
            вариантыСпособа
            if самовывоз { панельСамовывоза }
        }
    }

    private var самовывоз: Bool { модель.самовывозОткрыт }

    /// «Забирают у вас: адрес» — «Указать точку забора» открывает своё окно карты (ЛистТочкиСделки).
    private var строкаЗабора: some View {
        let адрес = адресСДверью(сделка.адресОткуда, сделка.дверьОткуда)
        return VStack(alignment: .leading, spacing: 6) {
            (Text(т("hnd_pick_from") + " ") + Text(адрес.isEmpty ? т("apk_none2") : адрес).bold())
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
            Button {
                действие(.точка(откуда: true))
            } label: {
                Label(т("hnd_pick_edit"), systemImage: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var вариантыСпособа: some View {
        let я = сделка.продавец
        let оплаченКурьер = сделка.курьерЯндексаОплачен
        if сделка.межгород {
            вариант(т(я ? "hnd_p_s" : "hnd_p_b"), т("hnd_p_sub"), символ: "truck.box") { действие(.способ("carrier")) }
        } else if я {
            вариант(т("hnd_self_s"), т("hnd_self_ss"), символ: "figure.walk") { модель.самовывозОткрыт.toggle() }
        } else if оплаченКурьер {
            /* Отменить оплаченного курьера (ship_drop) — деньги: страница сайта. */
            let подпись = сделка.доставка > 0
                ? String(format: т("shp_self_refund"), СделкиФормат.тенге(сделка.доставка)) : т("shp_self_free")
            вариант(т("hnd_self_b"), подпись, символ: "figure.walk", наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.заберуСам)) }
        } else {
            вариант(т("hnd_self_b"), т("hnd_self_bs"), символ: "figure.walk") { модель.самовывозОткрыт.toggle() }
        }
        /* Курьер Яндекса: добавить (ship_add — оплата с баланса) или вызвать оплаченного (clocal_start) — сайт. */
        if сделка.курьерДоступен && сделка.яндексДоступен && !сделка.услуга && !сделка.межгород && !оплаченКурьер && !я {
            вариант(т("hnd_ya_b"), т("shp_ya_add_s"), символ: "car", наСайт: ДеньгиКнопок.наСайте) {
                действие(.деньги(.курьерЯндекса))
            }
        }
        if сделка.курьерДоступен && !сделка.услуга && !сделка.межгород && оплаченКурьер {
            let подпись = подписьОплаченногоКурьера
            вариант(т(я ? "hnd_ya_s" : "hnd_ya_b"), подпись, символ: "car", наСайт: true) { действие(.наСайт) }
        }
    }

    /// Подпись «Курьер Яндекса», когда доставка уже оплачена: бесплатная (за счёт продавца) или оплаченная покупателем.
    private var подписьОплаченногоКурьера: String {
        let я = сделка.продавец
        if сделка.доставкаЗаСчётПродавца > 0 {
            return я ? String(format: т("hnd_ya_ss_free"), СделкиФормат.тенге(сделка.доставкаЗаСчётПродавца))
                     : т("hnd_ya_bs_free")
        }
        return т(я ? "hnd_ya_ss" : "hnd_ya_bs")
    }

    private func вариант(_ заголовок: String, _ подпись: String, символ: String, наСайт: Bool = false,
                         нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: символ)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 36, height: 36)
                    .background(Theme.мята, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: наСайт ? "arrow.up.right.square" : "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(модель.занято)
        .accessibilityHint(наСайт ? т("a11y_site") : "")
    }

    /// clocalSelfHtml: покупателю — адрес продавца и маршрут; обоим — «Кто повезёт / поедет?» и две кнопки.
    private var панельСамовывоза: some View {
        let я = сделка.продавец
        return VStack(alignment: .leading, spacing: 8) {
            if !я {
                let адрес = адресСДверью(сделка.адресОткуда, сделка.дверьОткуда)
                (Text(т("hnd_pick_at") + " ") + Text(адрес.isEmpty ? т("hnd_addr_chat") : адрес).bold())
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                if !сделка.адресОткуда.isEmpty || сделка.точкаОткуда != nil {
                    кнопкаМаршрута(адрес: сделка.адресОткуда, точка: сделка.точкаОткуда)
                } else {
                    ЗаметкаСделки(Text(т("hnd_no_geo")), вид: .предупреждение)
                }
            }
            ПодписьСделки(т(я ? "hnd_who_gives" : "hnd_who_goes"))
            КнопкаСделки(т(я ? "hnd_give_self" : "hnd_go_self"), вид: .главная, символ: "figure.walk",
                         доступна: !модель.занято) { действие(.способ("self")) }
            КнопкаСделки(т(я ? "hnd_give_courier" : "hnd_go_courier"), вид: .вторая, символ: "car",
                         доступна: !модель.занято) { действие(.способ("courier")) }
            ПодписьСделки(т("hnd_who_s"))
        }
    }

    // MARK: - Способ выбран (clocalModeHtml)

    private var блокСпособа: some View {
        let режим = сделка.способПередачи
        let заголовок = т(режим == "carrier" ? "md_carrier" : (режим == "courier" ? "md_courier" : "md_self"))
        return БлокСделки {
            ЗаголовокБлокаСделки(текст: заголовок, символ: режим == "self" ? "figure.walk" : "car")
            Text(чтоСейчас)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            строкиАдресов
            маршрутИКурьер
            if сделка.кодыВключены {
                if Config.деньгиСделок {
                    /* Этап 44: код продавца и «Я получил вещь» (pin_enter) — своим блоком. */
                    БлокКодаПродавца(сделка: сделка, модель: модель, действие: действие)
                } else {
                    /* Код продавца и его ввод покупателем подтверждают получение (pin_enter — деньги, этап 44). */
                    КнопкаСделки(т("site_deal"), вид: .вторая, символ: "number", наСайт: true) { действие(.наСайт) }
                }
            }
            отслеживание
            сменаСпособа
        }
    }

    /// clocalNow: одна строка «что делать сейчас».
    private var чтоСейчас: String {
        let я = сделка.продавец
        let сам = сделка.способПередачи == "self"
        if сделка.статус == "confirmed" || сделка.статус == "resolved" { return т("now_done") }
        if сделка.кодПринят { return т(я ? "now_s3c" : "now_b3b") }
        if сделка.статус == "shipped" || сделка.статус == "delivered" {
            if я { return т(сам ? "now_s2m" : "now_s2") }
            return т(сам ? "now_b2m" : "now_b2")
        }
        if сам { return т(я ? "now_s1m" : "now_b1m") }
        if выбралЯ { return т(я ? "now_s1" : "now_b1c") }
        return т(я ? "now_s1w" : "now_b1")
    }

    /// handover_by (по умолчанию buyer) совпадает с моей ролью.
    private var выбралЯ: Bool {
        (сделка.выбралСпособ.isEmpty ? "buyer" : сделка.выбралСпособ) == (сделка.продавец ? "seller" : "buyer")
    }

    /// «Откуда» и «Куда»: имя, телефон, адрес с подъездом — с кнопкой «Скопировать…».
    @ViewBuilder
    private var строкиАдресов: some View {
        let откуда = адресСДверью(сделка.адресОткуда, сделка.дверьОткуда)
        let куда = адресСДверью(сделка.адресКуда, сделка.дверьКуда)
        let я = [сделка.моёИмя, сделка.мойТелефон]
        let он = [сделка.собеседник.имя, сделка.собеседник.телефон]
        if сделка.продавец {
            строкаАдреса("A", т("ln_from"), (я + [откуда]).filter { !$0.isEmpty }.joined(separator: ", "), т("snd_copy_mine"))
            if сделка.способПередачи != "self" {
                строкаАдреса("B", т("ln_to"), (он + [куда]).filter { !$0.isEmpty }.joined(separator: ", "), т("rcp_copy"))
            }
        } else {
            строкаАдреса("A", т("ln_from"), (он + [откуда]).filter { !$0.isEmpty }.joined(separator: ", "), т("snd_copy"))
            if сделка.способПередачи != "self" {
                строкаАдреса("B", т("ln_to"), (я + [куда]).filter { !$0.isEmpty }.joined(separator: ", "), т("rcp_copy_mine"))
            }
        }
    }

    private func строкаАдреса(_ буква: String, _ подпись: String, _ текст: String, _ копировать: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(буква)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(буква == "A" ? Theme.зелёный : КраскаОбъявлений.плохоТекст, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(подпись)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Text(текст.isEmpty ? "—" : текст)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 4)
            if !текст.isEmpty {
                Button {
                    действие(.скопировать(текст))
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(копировать)
            }
        }
    }

    /// held/shipped без принятого кода: маршрут (сам) или «Вызвать курьера» (курьер вызывает тот, кто выбрал способ).
    @ViewBuilder
    private var маршрутИКурьер: some View {
        if (сделка.статус == "held" || сделка.статус == "shipped") && !сделка.кодПринят {
            if сделка.способПередачи == "self" {
                let адрес = сделка.продавец ? сделка.адресКуда : сделка.адресОткуда
                let точка = сделка.продавец ? сделка.точкаКуда : сделка.точкаОткуда
                if !адрес.isEmpty || точка != nil {
                    кнопкаМаршрута(адрес: адрес, точка: точка)
                }
            } else if естьКудаКурьеру {
                КнопкаСделки(т("hnd_call_courier"), вид: выбралЯ && !сделка.курьерВызван ? .главная : .вторая,
                             символ: "car") {
                    действие(.курьер(откуда: сделка.точкаОткуда, куда: сделка.точкаКуда))
                }
            }
        }
    }

    /// hovCourierBtn: нужна точка или адрес с обеих сторон.
    private var естьКудаКурьеру: Bool {
        (сделка.точкаОткуда != nil || !сделка.адресОткуда.isEmpty) && (сделка.точкаКуда != nil || !сделка.адресКуда.isEmpty)
    }

    private func кнопкаМаршрута(адрес: String, точка: ТочкаСделки?) -> some View {
        КнопкаСделки(т("hnd_route"), вид: .вторая, символ: "point.topleft.down.to.point.bottomright.curvepath") {
            действие(.маршрут(адрес: адрес, точка: точка))
        }
    }

    /// Ссылка отслеживания: не сам, held/shipped. Нет ссылки и курьер вызван — поле сразу; есть — «Где курьер» и
    /// «Изменить ссылку».
    @ViewBuilder
    private var отслеживание: some View {
        let можно = сделка.способПередачи != "self" && (сделка.статус == "held" || сделка.статус == "shipped")
        let ссылка = сделка.ссылкаСлежения
        if сделка.способПередачи != "self" && !ссылка.isEmpty, let адрес = URL(string: ссылка) {
            HStack(spacing: 8) {
                КнопкаСделки(т("trk_go"), вид: .главная, символ: "location") { действие(.ссылка(адрес)) }
                if можно && !полеСсылки {
                    КнопкаСделки(т("trk_edit"), вид: .вторая, символ: "pencil") {
                        модель.ссылкаСлежения = ссылка
                        полеСсылки = true
                    }
                }
            }
        } else if можно && !сделка.курьерВызван && !полеСсылки {
            КнопкаСделки(т("trk_add"), вид: .тихая, символ: "link") { полеСсылки = true }
        }
        if можно && (полеСсылки || (сделка.курьерВызван && ссылка.isEmpty)) {
            полеОтслеживания
        }
    }

    private var полеОтслеживания: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("trk_lbl"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            TextField(т("trk_ph"), text: $модель.ссылкаСлежения)
                .font(.system(size: 15))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .onChange(of: модель.ссылкаСлежения) { _, стало in
                    if стало.count > 500 { модель.ссылкаСлежения = String(стало.prefix(500)) }
                }
            HStack(spacing: 8) {
                КнопкаСделки(т("trk_paste"), вид: .вторая, символ: "doc.on.clipboard") { модель.вставитьИзБуфера() }
                КнопкаСделки(т("trk_save"), вид: .главная, доступна: !модель.занято) {
                    модель.сохранитьСсылку()
                    полеСсылки = false
                }
            }
            ПодписьСделки(т("trk_ask_s2"))
        }
    }

    /// «Изменить способ передачи / получения»: held; продавцу — только если способ выбрал он сам, иначе «Условия выбрал
    /// покупатель».
    @ViewBuilder
    private var сменаСпособа: some View {
        if сделка.статус == "held" {
            let моя = !сделка.продавец || сделка.выбралСпособ == "seller"
            Button {
                действие(моя ? .сменитьСпособ : .способЗаперт)
            } label: {
                Label(т(сделка.продавец ? "hnd_switch" : "hnd_switch_b"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            .buttonStyle(.plain)
            .disabled(модель.занято)
        }
    }

    // MARK: - Курьер по городу (clocal.delivery) — показ

    private func блокКурьера(_ к: КурьерСделки) -> some View {
        let этапы: [String: Int] = ["awaiting_courier": 1, "picked_up": 2, "delivered": 3, "returned": 1]
        let этап: Int = этапы[к.статус] ?? 0
        let код: (подпись: String, значение: String)? = {
            if сделка.продавец && к.статус == "awaiting_courier" && !к.кодЗабора.isEmpty { return (т("clc_code_s"), к.кодЗабора) }
            if !сделка.продавец && к.статус == "picked_up" && !к.пин.isEmpty { return (т("clc_pin_b"), к.пин) }
            return nil
        }()
        return БлокСделки {
            ЗаголовокБлокаСделки(текст: к.яндекс ? т("clc_ya_h") : т("md_courier"), символ: "car")
            ЭтапыКурьера(этап: этап)
            if к.яндекс && !к.статусЯндекса.isEmpty {
                Text(СтатусЯндекса.текст(к.статусЯндекса))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            if let код {
                VStack(spacing: 4) {
                    Text(код.подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                    Text(код.значение)
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.текст)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            if let адрес = URL(string: к.ссылкаСлежения), к.ссылкаСлежения.hasPrefix("https://") {
                КнопкаСделки(т("yac_track"), вид: .вторая, символ: "map") { действие(.ссылка(адрес)) }
            }
            КнопкаСделки(т("site_deal"), вид: .вторая, наСайт: true) { действие(.наСайт) }
        }
    }

    private func адресСДверью(_ адрес: String, _ дверь: ДверьСделки?) -> String {
        let д = дверь?.текст ?? ""
        if адрес.isEmpty { return "" }
        return д.isEmpty ? адрес : адрес + ", " + д
    }
}

/// clocalBar: «Оплачено · Забрал · Вручил · Готово».
struct ЭтапыКурьера: View {
    let этап: Int

    var body: some View {
        let подписи = [СделкиText.т("cstep_paid"), СделкиText.т("cstep_picked"), СделкиText.т("cstep_handed"),
                       СделкиText.т("cstep_done")]
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<подписи.count, id: \.self) { i in
                VStack(spacing: 4) {
                    Text(i < этап ? "✓" : String(i + 1))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(i <= этап ? Color.white : Theme.текстВторой)
                        .frame(width: 24, height: 24)
                        .background(i < этап ? Theme.зелёный : (i == этап ? Theme.акцент : Theme.поверхность2), in: Circle())
                    Text(подписи[i])
                        .font(.system(size: 11, weight: i == этап ? .bold : .regular))
                        .foregroundStyle(i == этап ? Theme.текст : Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписи.indices.contains(этап) ? подписи[этап] : "")
    }
}

/// clocalYaLabel: статус заказа Яндекс.Доставки словами сайта.
enum СтатусЯндекса {
    static func текст(_ код: String) -> String {
        let ключи: [String: String] = [
            "new": "yastat_new", "estimating": "yastat_est", "ready_for_approval": "yastat_ready",
            "accepted": "yastat_accepted", "performer_lookup": "yastat_lookup", "performer_draft": "yastat_lookup",
            "performer_found": "yastat_found", "pickup_arrived": "yastat_atseller",
            "ready_for_pickup_confirmation": "yastat_atseller", "pickuped": "yastat_picked",
            "delivery_arrived": "yastat_atbuyer", "ready_for_delivery_confirmation": "yastat_atbuyer",
            "pay_waiting": "yastat_handed", "delivered": "yastat_delivered", "delivered_finish": "yastat_delivered",
            "returning": "yastat_returning", "return_arrived": "yastat_atseller_ret", "returned": "yastat_returned_seller",
            "returned_finish": "yastat_returned", "cancelled": "yastat_cancelled", "cancelled_by_taxi": "yastat_cancelled_taxi",
            "failed": "yastat_nocourier", "performer_not_found": "yastat_nocourier"
        ]
        if let ключ = ключи[код] { return СделкиText.т(ключ) }
        return СделкиText.т("yastat_prefix") + код
    }
}

// MARK: - Перевозчик (dealCarrierHtml)

struct БлокПеревозчика: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var п: ПеревозчикСделки { сделка.перевозчик }
    private var я: Bool { сделка.продавец }

    var body: some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: String(format: т(п.доДвери ? "car_to_door" : "car_to_pvz"), п.имя),
                                 символ: "truck.box")
            if !я {
                let адрес = п.доДвери ? адресКуда : п.адресПВЗ
                if !адрес.isEmpty {
                    Text(адрес)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !сроки.isEmpty { ПодписьСделки(String(format: т("car_days"), сроки)) }
            содержимое
        }
        .onAppear {
            if нуженСписок { модель.загрузитьПункты() }
        }
        .onChange(of: нуженСписок) { _, нужен in
            if нужен { модель.загрузитьПункты() }
        }
    }

    private var адресКуда: String {
        let д = сделка.дверьКуда?.текст ?? ""
        if сделка.адресКуда.isEmpty { return "" }
        return д.isEmpty ? сделка.адресКуда : сделка.адресКуда + ", " + д
    }

    private var сроки: String {
        let от = п.днейОт
        let до = п.днейДо
        if от > 0 && до > 0 && от != до { return String(от) + "–" + String(до) }
        let одно = от > 0 ? от : до
        return одно > 0 ? String(одно) : ""
    }

    /// Этап: отменена — cancelled; оформлена, но без этапа — created.
    private var этап: String {
        if п.отменена { return "cancelled" }
        if п.этап.isEmpty && оформлена { return "created" }
        return п.этап
    }

    private var оформлена: Bool { !п.заказ.isEmpty || !п.трек.isEmpty }

    /// Продавцу в held без действующей отправки нужны пункты приёма — если адрес отправки на карте есть.
    private var нуженСписок: Bool {
        я && сделка.статус == "held" && сделка.точкаОткуда != nil && (!оформлена || этап == "cancelled")
    }

    @ViewBuilder
    private var содержимое: some View {
        if этап == "cancelled" && сделка.статус != "held" {
            ЗаметкаСделки(Text(СтадияПеревозчика.текст("cancelled") + (я ? "" : " " + т("car_cnl_b"))), вид: .плохо)
        } else if этап == "cancelled" && !я {
            ЗаметкаСделки(Text(т("car_st_reorder_b")), вид: .плохо)
        } else if !оформлена || этап == "cancelled" {
            неОформлена(заново: этап == "cancelled")
        } else {
            оформленная
        }
    }

    @ViewBuilder
    private func неОформлена(заново: Bool) -> some View {
        if !я {
            Text(String(format: т("car_b_wait"), п.имя))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        } else if сделка.статус == "held" {
            Text(String(format: т("car_s_give"), п.имя))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("car_from_lbl"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    Text(сделка.точкаОткуда != nil && !сделка.адресОткуда.isEmpty ? сделка.адресОткуда : "—")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                }
                Spacer(minLength: 4)
                /* Адрес отправки — точка на карте в своём окне (ЛистТочкиСделки, set_pickup). */
                Button(т(сделка.точкаОткуда != nil ? "car_from_edit" : "car_from_set")) { действие(.точка(откуда: true)) }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(Theme.акцент)
            }
            if сделка.точкаОткуда == nil {
                ЗаметкаСделки(Text(т("car_from_need")), вид: .плохо)
                КнопкаСделки(т("car_from_btn"), вид: .главная) { действие(.точка(откуда: true)) }
            } else {
                if заново { ЗаметкаСделки(Text(т("car_st_reorder_s")), вид: .плохо) }
                пункты
            }
        }
    }

    @ViewBuilder
    private var пункты: some View {
        if модель.пунктыОшибка {
            ЗаметкаСделки(Text(т("car_pts_err")), вид: .плохо)
            КнопкаСделки(т("img_retry"), вид: .вторая) { модель.загрузитьПункты(заново: true) }
        } else if let список = модель.пункты {
            if список.isEmpty {
                ЗаметкаСделки(Text(модель.пунктыСообщение.isEmpty ? т("car_e_no_points") : модель.пунктыСообщение), вид: .плохо)
            } else {
                Text(т("car_pt_lbl"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.текстВторой)
                Picker(т("car_pt_lbl"), selection: $модель.выбранПункт) {
                    Text(т("car_pt_pick")).tag("")
                    ForEach(список) { пункт in
                        Text(пункт.подпись).tag(пункт.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.текст)
                КнопкаСделки(т("car_ord_btn"), вид: .главная, символ: "truck.box", доступна: !модель.занято) {
                    модель.оформитьОтправку()
                }
            }
        } else {
            HStack(spacing: 8) {
                SiteSpinner()
                Text(т("car_pts_load"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    @ViewBuilder
    private var оформленная: some View {
        let текстЭтапа: String = {
            if этап == "created" && !я { return т("car_st_created_b") }
            if этап == "arrived" && п.доДвери { return т("car_st_arrived_d") }
            return СтадияПеревозчика.текст(этап)
        }()
        let вид: ВидЗаметкиСделки = Self.видыЭтапов[этап] ?? .предупреждение
        if !п.трек.isEmpty {
            if я && этап == "created" {
                VStack(spacing: 4) {
                    Text(п.трек)
                        .font(.system(size: 24, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.текст)
                        .textSelection(.enabled)
                    Text(т("car_num_say"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            } else {
                (Text(т("car_num") + " ") + Text(п.трек).bold())
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
            }
        }
        if я && !п.адресПриёма.isEmpty {
            (Text(т("car_pt_at") + " ") + Text(п.адресПриёма).bold())
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
        }
        if я && этап == "created", let точка = п.точкаПриёма { навигаторы(точка) }
        if !текстЭтапа.isEmpty { ЗаметкаСделки(Text(текстЭтапа), вид: вид) }
        if !я && !п.доДвери && этап == "arrived", let точка = п.точкаПВЗ { навигаторы(точка) }
        if !п.трек.isEmpty {
            HStack(spacing: 8) {
                КнопкаСделки(т("car_copy"), вид: .вторая, символ: "doc.on.doc") { действие(.скопировать(п.трек)) }
                if п.ссылкаТрека.hasPrefix("https://"), let адрес = URL(string: п.ссылкаТрека) {
                    КнопкаСделки(т("car_track"), вид: .вторая, символ: "location") { действие(.ссылка(адрес)) }
                }
            }
        }
    }

    private static let видыЭтапов: [String: ВидЗаметкиСделки] = [
        "arrived": .хорошо, "delivered": .хорошо, "problem": .плохо, "returning": .плохо, "returned": .плохо
    ]

    private func навигаторы(_ точка: ТочкаСделки) -> some View {
        HStack(spacing: 8) {
            if let адрес = НавигаторыСделки.маршрутКПункту(точка) {
                КнопкаСделки(т("carpt_route"), вид: .вторая, символ: "point.topleft.down.to.point.bottomright.curvepath") {
                    действие(.ссылка(адрес))
                }
            }
            if let адрес = НавигаторыСделки.таксиКПункту(точка) {
                КнопкаСделки(т("carpt_taxi"), вид: .вторая, символ: "car") { действие(.ссылка(адрес)) }
            }
        }
    }
}

/// dealCarStage: этап отправки перевозчиком.
enum СтадияПеревозчика {
    static func текст(_ этап: String) -> String {
        let ключи: [String: String] = [
            "created": "car_st_created", "accepted": "car_st_accepted", "in_transit": "car_st_in_transit",
            "arrived": "car_st_arrived", "delivered": "car_st_delivered", "returning": "car_st_returning",
            "returned": "car_st_returned", "cancelled": "car_st_cancelled", "problem": "car_st_problem"
        ]
        guard let ключ = ключи[этап] else { return "" }
        return СделкиText.т(ключ)
    }
}
