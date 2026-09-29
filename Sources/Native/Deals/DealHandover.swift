import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ПЕРЕДАЧА (#dm-clocal, этап 43; clocalRender сайта, карта §4.9, §9).

 Показывается для товара и услуги в held / shipped / delivered. Что рисовать — в том же порядке, что у сайта:
   1. перевозчик (ship_mode=carrier и доставка оплачена) — СДЭК / Exline / Avis: трек, этап, пункт приёма, «Оформить
      отправку» (car_points → car_order: отправку уже оплатил покупатель, запрос денег не двигает);
   2. посылка с кодом в коробке — свой БлокПосылки (DealParcel.swift): этапы, листок с QR для коробки (печать и
      «Отправить»), ввод кода, претензия, «Посылка потерялась», адрес — окно карты с parcel_from / parcel_addr;
   3. встреча с QR — свой БлокВстречи (DealMeet.swift): живой QR с таймером у продавца, «Сканировать код» у покупателя;
   4. способ не выбран (held) — «Как передадите товар?» / «Как хотите получить товар?»: ТК, «Заберу сам» / «Покупатель
      заберёт сам» → «Отвезу сам / Поеду сам» и «Передам курьеру / Отправлю курьера» (set_handover); платный курьер
      Яндекса и отмена оплаченного курьера — окна денег; вызов оплаченного курьера (clocal_start) — окно подтверждения
      или окно адреса (ПередачаСделкиМодель.вызватьОплаченного);
      способ выбран — «Из рук в руки» / «Доставка курьером» / «Отправка транспортной компанией»: что делать сейчас,
      «Откуда» / «Куда» с копированием, «Построить маршрут» (Яндекс Go и 2ГИС), «Вызвать курьера» (Яндекс Go — курьер,
      2ГИС — такси; нажатие отмечает courier_called), ссылка отслеживания (set_track, только Яндекс Go и inDrive),
      «Изменить способ…» (set_handover "" или handover_cancel);
   5. курьер по городу (clocal.delivery) — БлокКурьераПоГороду (DealCityCourier.swift): этапы, адреса, готовность
      продавца, заказ курьера Яндекса, коды, сроки, звонок курьеру, ссылка курьеру, отказ от товара;
      возврат — у продавца БлокВозвратаПродавцу (деньги), у покупателя и итог обеим сторонам — БлокВозвратаПокупателю
      (DealReturnBuyer.swift).
 Правка адресов (карта, «Указать точку», «Указать адрес» отправки) — своё окно ЛистТочкиСделки (DealPickupMap.swift,
 set_pickup сайта). «Отправить другому человеку — подарок» — своё окно «Кому передать» (СтрокаПолучателя,
 CabinetPlus/DealRecipient.swift, set_recipient сайта). Окна и вопросы передачи — СлойПередачиСделки (ниже).
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
        } else if let посылка = сделка.посылка {
            БлокПосылки(сделка: сделка, посылка: посылка, передача: модель.передача, действие: действие)
        } else if let встреча = сделка.встреча {
            БлокВстречи(сделка: сделка, встреча: встреча, передача: модель.передача, действие: действие)
        } else if let курьер = сделка.курьер {
            if сделка.продавец && ["returning", "returned_to_seller"].contains(курьер.статус) {
                /* Продавец подтверждает возврат сам (cancel {accept_fault} + clocal_return_confirm). */
                БлокВозвратаПродавцу(сделка: сделка, статус: курьер.статус, действие: действие)
            } else if ["returning", "returned_to_seller", "refunded"].contains(курьер.статус) {
                БлокВозвратаПокупателю(сделка: сделка, курьер: курьер, передача: модель.передача, действие: действие)
            } else {
                БлокКурьераПоГороду(сделка: сделка, курьер: курьер, модель: модель, передача: модель.передача,
                                    действие: действие)
            }
        } else if сделка.статус == "held" {
            if сделка.способПередачи.isEmpty { выборСпособа } else { блокСпособа }
        } else if !сделка.способПередачи.isEmpty && (сделка.статус == "shipped" || сделка.статус == "delivered") {
            блокСпособа
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
            if самовывоз && !межгород { панельСамовывоза }
            СтрокаПолучателя(сделка: сделка, модель: модель)
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

    /**
     u = !0===e.intercity сайта; плюс то, что сайт видит иначе: межгород в deal.carrier, отказ расчёта курьера
     «intercity» и сверка городов (logistics_partners). Межгород — только «Отправлю / Пусть отправит через ТК»:
     ни самовывоза, ни курьера Яндекса.
     */
    private var межгород: Bool {
        сделка.межгород || сделка.межгородДанные != nil || модель.межгородУзнали
    }

    @ViewBuilder
    private var вариантыСпособа: some View {
        let я = сделка.продавец
        let оплаченКурьер = сделка.курьерЯндексаОплачен
        if межгород {
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
        /* Курьер Яндекса: добавить (ship_add — оплата с баланса) или вызвать оплаченного (clocal_start — окно
           подтверждения или окно адреса доставки, ПередачаСделкиМодель.вызватьОплаченного). */
        if сделка.курьерДоступен && сделка.яндексДоступен && !сделка.услуга && !межгород && !оплаченКурьер && !я {
            вариант(т("hnd_ya_b"), т("shp_ya_add_s"), символ: "car", наСайт: ДеньгиКнопок.наСайте) {
                действие(.деньги(.курьерЯндекса))
            }
        }
        if сделка.курьерДоступен && !сделка.услуга && !межгород && оплаченКурьер {
            вариант(т(я ? "hnd_ya_s" : "hnd_ya_b"), Self.подписьОплаченногоКурьера(сделка), символ: "car") {
                модель.передача.вызватьОплаченного()
            }
        }
    }

    /// Подпись «Курьер Яндекса», когда доставка уже оплачена: бесплатная (за счёт продавца) или оплаченная покупателем.
    static func подписьОплаченногоКурьера(_ с: Сделка) -> String {
        let т = СделкиText.т
        if с.доставкаЗаСчётПродавца > 0 {
            return с.продавец ? String(format: т("hnd_ya_ss_free"), СделкиФормат.тенге(с.доставкаЗаСчётПродавца))
                              : т("hnd_ya_bs_free")
        }
        return т(с.продавец ? "hnd_ya_ss" : "hnd_ya_bs")
    }

    private func вариант(_ заголовок: String, _ подпись: String, символ: String, наСайт: Bool = false,
                         нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(alignment: .center, spacing: 12) {
                /* .clc-oi: 38×38, радиус 12, --tint-ok и --on-ok. */
                Image(systemName: символ)
                    .font(.system(size: 17))
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                    .frame(width: 38, height: 38)
                    .background(КраскаСделокКабинета.хорошоФон,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: наСайт ? "arrow.up.right.square" : "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            /* .clc-opt: поля 12, рамка 1.5 --line, радиус 14, фон --card. */
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
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
                /* Код продавца и «Я получил вещь» (pin_enter) — своим блоком. */
                БлокКодаПродавца(сделка: сделка, модель: модель, действие: действие)
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
                .background(буква == "A" ? Theme.зелёный : КраскаСделокКабинета.плохоТекст, in: Circle())
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
        if сделка.способПередачи != "self" && !ссылка.isEmpty && URL(string: ссылка) != nil {
            HStack(spacing: 8) {
                /* Не Safari и не сайт службы — свой лист «Отслеживание». */
                КнопкаСделки(т("trk_go"), вид: .главная, символ: "location") { действие(.отслеживание) }
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
        ЭтапыПередачи(подписи: [СделкиText.т("cstep_paid"), СделкиText.т("cstep_picked"), СделкиText.т("cstep_handed"),
                                СделкиText.т("cstep_done")], этап: этап)
    }
}

/// clocalBar / hovBar сайта: кружки этапов — пройденные с ✓, текущий акцентом, дальше серые.
struct ЭтапыПередачи: View {
    let подписи: [String]
    let этап: Int

    var body: some View {
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
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписи.indices.contains(этап) ? подписи[этап] : (подписи.last ?? ""))
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
                /* Трек есть — статус службы своим листом, без сайта перевозчика. */
                КнопкаСделки(т("car_track"), вид: .вторая, символ: "location") { действие(.отслеживание) }
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

// MARK: - Общие детали блоков передачи (посылка, встреча, возврат, курьер)

/// .clc-code / .hov-code сайта: подпись и код крупно; код выделяется для копирования и всегда слева направо.
struct ПлашкаКодаПередачи: View {
    let подпись: String
    let код: String
    /// clocalCodeBox — подпись сверху; hovCodeBox — код сверху, подпись под ним.
    var подписьСверху = true

    var body: some View {
        VStack(spacing: 4) {
            if подписьСверху { подписьВид }
            Text(код)
                .font(.system(size: 28, weight: .heavy, design: .monospaced))
                .tracking(3)
                .foregroundStyle(Theme.текст)
                .textSelection(.enabled)
                .environment(\.layoutDirection, .leftToRight)
            if !подписьСверху { подписьВид }
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var подписьВид: some View {
        Text(подпись)
            .font(.system(size: 13))
            .foregroundStyle(Theme.текстВторой)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// hovInput сайта: четыре цифры, цифровая клавиатура (любые цифры клавиатуры становятся 0–9).
struct ПолеКодаПередачи: View {
    let подпись: String
    @Binding var текст: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
            TextField("0000", text: Binding(get: { текст }, set: { текст = ПередачаСделкиМодель.цифры($0) }))
                .keyboardType(.numberPad)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .leftToRight)
                .modifier(ПолеДенегСделки())
                .accessibilityLabel(подпись)
        }
    }
}

/// .hov-link сайта: тихая ссылка под блоком («Посылка потерялась или разбита», «Получил, но кода не было»).
struct СсылкаПередачи: View {
    let текст: String
    var доступна = true
    let действие: () -> Void

    init(_ текст: String, доступна: Bool = true, действие: @escaping () -> Void) {
        self.текст = текст
        self.доступна = доступна
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 13, weight: .semibold))
                .underline()
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!доступна)
        .opacity(доступна ? 1 : 0.55)
    }
}

/**
 hovSwitchBtn сайта: можно — «Изменить способ передачи / получения» (hovSwitch → вопрос карточки → handover_cancel);
 нельзя, но способ ещё не начат — та же кнопка с замком (hovSwitchLocked: «Условия выбрал покупатель»); иначе ничего.
 */
struct КнопкаСменыСпособа: View {
    let продавец: Bool
    let можно: Bool
    let показатьЗамок: Bool
    let действие: (НажатиеСделки) -> Void

    var body: some View {
        if можно || показатьЗамок {
            КнопкаСделки(СделкиText.т(продавец ? "hnd_switch" : "hnd_switch_b"), вид: .вторая,
                         символ: можно ? "arrow.triangle.2.circlepath" : "lock") {
                действие(можно ? .сменитьСпособ : .способЗаперт)
            }
            .opacity(можно ? 1 : 0.72)
        }
    }

    /// hovCanSwitch: покупатель — всегда; продавец — только если способ выбрал он сам (по умолчанию выбирает покупатель).
    static func разрешено(роль: String, выбрал: String) -> Bool {
        роль == "buyer" || (выбрал.isEmpty ? "buyer" : выбрал) == "seller"
    }
}

/// hovWhoChose: покупателю — «Способ выбрал продавец. Решаете вы…», пока способ ещё не начат.
struct КтоВыбралСпособ: View {
    let роль: String
    let выбрал: String
    let вНачале: Bool

    var body: some View {
        if роль == "buyer" && !выбрал.isEmpty && выбрал != "buyer" && вНачале {
            ЗаметкаСделки(Text(ПередачаText.т("hnd_by_seller")), вид: .предупреждение)
        }
    }
}

// MARK: - Окна передачи поверх карточки

/**
 Окна передачи (посылка, встреча, возврат, курьер): лист по высоте для претензии, отказа, адреса и звонка, камера для
 QR, окно карты для адреса посылки, вопрос перед действием. Всё из ПередачаСделкиМодель — окно живёт, даже если блок
 карточки перерисовался после опроса.
 */
struct СлойПередачиСделки: ViewModifier {
    @ObservedObject var передача: ПередачаСделкиМодель
    @ObservedObject var карточка: КарточкаСделкиМодель

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear
                    .sheet(item: $передача.лист) { лист in
                        листПередачи(лист)
                    }
            }
            .background {
                Color.clear
                    .sheet(item: $передача.вопрос) { в in
                        ОкноВопросаПередачи(слова: передача.слова(в), подтвердить: { подтвердитьПозже(в) },
                                            отмена: { передача.вопрос = nil })
                    }
            }
    }

    @ViewBuilder
    private func листПередачи(_ лист: ЛистПередачи) -> some View {
        switch лист {
        case .претензия:
            ОкноПретензииПосылки(передача: передача)
        case .отказ:
            ОкноОтказаОтТовара(передача: передача)
        case .адрес(let вид):
            ОкноАдресаКурьера(вид: вид, сделка: карточка.сделка, передача: передача,
                              наКарте: { картаКуда() })
        case .звонок(let звонок):
            ОкноЗвонкаКурьеру(звонок: звонок, закрыть: { передача.лист = nil })
        case .сканер(let встреча):
            СканерКодаСделки(встреча: встреча, передача: передача)
        case .адресПосылки(let откуда):
            if let с = карточка.сделка {
                ЛистТочкиСделки(цель: ТочкаНаКартеСделки.посылки(с, откуда: откуда), модель: карточка)
            }
        }
    }

    /// Лист вопроса сперва уезжает, потом — действие: следом может открыться окно eGov.
    @MainActor
    private func подтвердитьПозже(_ в: ВопросПередачи) {
        let м = передача
        м.вопрос = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            м.подтвердить(в)
        }
    }

    /// «Указать на карте» окна «Куда привезти товар?» (hovAddrEdit): окно уезжает, открывается карта точки доставки
    /// (set_pickup) — её показывает экран карточки по просьбеТочкиКуда.
    @MainActor
    private func картаКуда() {
        передача.лист = nil
        let к = карточка
        Task { @MainActor in
            /* Лист уезжает — потом карта, иначе второй лист не покажется. */
            try? await Task.sleep(nanoseconds: 300_000_000)
            к.просьбаТочкиКуда += 1
        }
    }
}

/// boostConfirm сайта своим листом: значок, заголовок, текст, главная кнопка и «Отмена».
struct ОкноВопросаПередачи: View {
    let слова: СловаВопросаПередачи
    let подтвердить: () -> Void
    let отмена: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: слова.символ)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(слова.опасная ? КраскаСделокКабинета.плохоТекст : КраскаСделокКабинета.хорошоТекст)
                        .frame(width: 40, height: 40)
                        .background(слова.опасная ? КраскаСделокКабинета.плохоФон : КраскаСделокКабинета.хорошоФон,
                                    in: Circle())
                        .accessibilityHidden(true)
                    Text(слова.заголовок)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }
                if !слова.текст.isEmpty {
                    Text(слова.текст)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текстВторой)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    КнопкаСделки(слова.кнопка, вид: слова.опасная ? .опасная : .главная) { подтвердить() }
                    КнопкаСделки(СделкиText.т("btn_cancel"), вид: .вторая) { отмена() }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }
}

/// Шапка небольшого окна передачи: заголовок и крестик (.clc-mh сайта).
struct ШапкаОкнаПередачи: View {
    let заголовок: String
    let закрыть: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(заголовок)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 32, height: 32)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(СделкиText.т("close"))
        }
    }
}

/// Ошибка внутри окна передачи (плашка карточки была бы под листом).
struct ОшибкаОкнаПередачи: View {
    let текст: String?

    var body: some View {
        if let текст, !текст.isEmpty {
            ЗаметкаСделки(Text(текст), вид: .плохо, символ: "exclamationmark.circle")
        }
    }
}
