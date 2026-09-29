import SwiftUI
import UIKit

/**
 ПОСЫЛКА С КОДОМ В КОРОБКЕ — СВОЙ БЛОК (hovParcelPanel сайта, карта §9.7, CAB @559602–586000).

 Этапы: продавцу «Код в коробку · В пути · Вскрыто · Расчёт», покупателю «Собирают · В пути · Вскрыли · Расчёт».
   · packing — продавец видит листок в коробку (hovParcelSlip: QR на /cabinet.php?parcel=<open_token>, цифры my_code,
     «Вскройте посылку и наведите камеру…»; «Распечатать листок» и «Отправить листок»), «Откуда забрать» с «Изменить
     адрес» (окно карты → parcel_from), «Кому / Куда» с маршрутом, курьером и копированием, «Отдал курьеру» (parcel_sent,
     без адреса покупателя недоступно); покупатель — «Куда доставить» (окно карты → parcel_addr) и «Вызвать курьера»;
   · sent — покупатель вводит код с листка (parcel_open {code}) или сканирует QR листка своей камерой (parcel_open
     {token} после «Вы точно получили товар?»), «Посылка не пришла или разбита» (parcel_lost); продавец — «Посылка
     потерялась или разбита» и «Получил, но кода внутри не было» (parcel_nocode);
   · opened — покупатель видит свой код для продавца и «Внутри не то — открыть спор» (parcel_claim, причина ≥ 3 знаков);
     продавец вводит код покупателя — «Подтвердить и получить деньги» (parcel_release), «Неверных попыток: N из 6»;
   · claim — спор о содержимом и «Открыть переписку по спору»; lost — кто подаёт претензию службе; done — готово.
 Смена способа — handover_cancel (вопрос карточки «Изменить способ…»), пока посылка собирается.
 */
struct БлокПосылки: View {
    let сделка: Сделка
    let посылка: ПосылкаСделки
    @ObservedObject var передача: ПередачаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    /// role посылки ("seller" / "buyer"); нет — роль в сделке.
    private var я: Bool { посылка.роль.isEmpty ? сделка.продавец : посылка.роль == "seller" }
    private var роль: String { я ? "seller" : "buyer" }
    private var статус: String { посылка.статус }

    /// done — 4, opened и claim — 2, sent — 1, иначе 0.
    private var этап: Int {
        switch статус {
        case "done": return 4
        case "opened", "claim": return 2
        case "sent": return 1
        default: return 0
        }
    }

    private var подписиЭтапов: [String] {
        я ? [т("prc_s1"), т("prc_s2"), т("prc_s3"), т("prc_s4")] : [т("prc_b1"), т("prc_b2"), т("prc_b3"), т("prc_b4")]
    }

    var body: some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: СделкиText.т(сделка.посылкаЧерезТК ? "prc_h_tk" : "prc_h_cr"), символ: "shippingbox")
            ЭтапыПередачи(подписи: подписиЭтапов, этап: этап)
            содержимое
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if статус == "done" {
            ЗаметкаСделки(Text(т(я ? "prc_done_s" : "prc_done")), вид: .хорошо, символ: "checkmark.circle")
        } else if статус == "lost" {
            ЗаметкаСделки(Text(т("prc_lost_note")), вид: .плохо)
            (Text(т("prc_lost_who") + " ")
             + (посылка.ктоПретензия == роль ? ТекстСделки.сЖирным(т("prc_lost_you")) : Text(т("prc_lost_other"))))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            кодПродавца
            if статус == "claim" {
                ЗаметкаСделки(Text(т("prc_claim_note")), вид: .плохо)
                КнопкаСделки(т("prc_claim_open"), вид: .главная, символ: "bubble.left.and.exclamationmark.bubble.right") {
                    действие(.спор)
                }
            } else if я {
                продавцу
            } else {
                покупателю
            }
        }
    }

    // MARK: - Продавец

    /// Листок в коробку (packing и есть open_token) или код продавца с подписью этапа.
    @ViewBuilder
    private var кодПродавца: some View {
        if я && !посылка.мойКод.isEmpty {
            if статус == "packing" && !посылка.токен.isEmpty {
                ЛистокВКоробку(посылка: посылка, номер: номер)
            } else {
                ПлашкаКодаПередачи(подпись: подписьКода, код: посылка.мойКод, подписьСверху: false)
            }
        }
    }

    private var номер: String { посылка.номер.isEmpty ? сделка.id : посылка.номер }

    private var подписьКода: String {
        let ключи: [String: String] = ["packing": "prc_code_packing", "sent": "prc_code_sent", "opened": "prc_code_opened",
                                        "claim": "prc_code_claim"]
        return т(ключи[статус] ?? "prc_code_def")
    }

    @ViewBuilder
    private var продавцу: some View {
        Group {
            if статус == "packing" {
                откудаЗабрать
                куда
                КнопкаСделки(т("prc_sent_btn"), вид: .главная, символ: "shippingbox.and.arrow.backward",
                             доступна: !передача.идёт && !посылка.адресКуда.isEmpty) {
                    передача.посылкаУКурьера()
                }
            } else if статус == "sent" {
                ЗаметкаСделки(Text(т("prc_s_sent")), вид: .предупреждение)
                ПодписьСделки(т("prc_s_sent_sub"))
                СсылкаПередачи(т("prc_lost_s"), доступна: !передача.идёт) { передача.вопрос = .потеряна }
                СсылкаПередачи(т("prc_nocode_b"), доступна: !передача.идёт) { передача.вопрос = .безКода }
            } else if статус == "opened" {
                ЗаметкаСделки(Text(т("prc_s_opened")), вид: .хорошо, символ: "checkmark.circle")
                ПодписьСделки(т("prc_s_opened_sub"))
                ПолеКодаПередачи(подпись: т("prc_s_in"), текст: $передача.кодПосылки)
                КнопкаСделки(т("prc_release_btn"), вид: .главная, символ: "checkmark.seal", доступна: !передача.идёт) {
                    передача.деньгиЗаПосылку()
                }
                ошибки
            }
        }
        let можноСменить = статус == "packing"
            && КнопкаСменыСпособа.разрешено(роль: "seller", выбрал: посылка.организатор)
        КнопкаСменыСпособа(продавец: true, можно: можноСменить, показатьЗамок: статус == "packing", действие: действие)
    }

    /// «Откуда забрать»: адрес посылки или сделки и «Изменить адрес» (hovFromEdit → окно карты → parcel_from).
    private var откудаЗабрать: some View {
        let адрес = посылка.адресОткуда.isEmpty ? сделка.адресОткуда : посылка.адресОткуда
        return VStack(alignment: .leading, spacing: 6) {
            Text(т("apk_from_t"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            HStack(alignment: .center, spacing: 8) {
                Text(адрес.isEmpty ? СделкиText.т("apk_none2") : адрес)
                    .font(.system(size: 14))
                    .foregroundStyle(адрес.isEmpty ? Theme.текстВторой : Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(т("apk_edit")) { передача.лист = .адресПосылки(откуда: true) }
                    .font(.system(size: 14, weight: .semibold))
                    .tint(Theme.акцент)
                    .disabled(передача.идёт)
            }
        }
    }

    /// hovShipTo: «Кому» и «Куда»; есть адрес — маршрут к покупателю, «Вызвать курьера», копирование для заявки.
    @ViewBuilder
    private var куда: some View {
        let п = сделка.собеседник
        let имя = п.имя.isEmpty ? т("prc_to_buyer") : п.имя
        let кому = п.телефон.isEmpty ? имя : имя + ", " + п.телефон
        let адрес = посылка.адресКуда
        VStack(alignment: .leading, spacing: 4) {
            (Text(т("prc_to_who") + " ") + Text(кому).bold())
            (Text(т("prc_to_where") + " ") + Text(адрес.isEmpty ? т("prc_to_none") : адрес).bold())
        }
        .font(.system(size: 14))
        .foregroundStyle(Theme.текст)
        .fixedSize(horizontal: false, vertical: true)
        if адрес.isEmpty {
            ЗаметкаСделки(Text(т("prc_to_need")), вид: .предупреждение)
        } else {
            КнопкаСделки(СделкиText.т("hnd_route") + " " + т("hnd_to_buyer"), вид: .вторая,
                         символ: "point.topleft.down.to.point.bottomright.curvepath") {
                действие(.маршрут(адрес: адрес, точка: посылка.точкаКуда))
            }
            кнопкаКурьера
            СсылкаПередачи(т("prc_to_copy")) {
                действие(.скопировать([п.имя, п.телефон, адрес].filter { !$0.isEmpty }.joined(separator: ", ")))
            }
        }
    }

    // MARK: - Покупатель

    @ViewBuilder
    private var покупателю: some View {
        Group {
            if статус == "packing" {
                ЗаметкаСделки(Text(т("prc_b_wait")), вид: .предупреждение)
                адресПокупателя
                ПодписьСделки(т("prc_b_addr_s"))
                кнопкаКурьера
            } else if статус == "sent" {
                ПодписьСделки(т("prc_b_sent"))
                ЗаметкаСделки(Text(т("prc_b_sent_warn")), вид: .плохо, символ: "hand.raised")
                ПолеКодаПередачи(подпись: т("prc_b_in"), текст: $передача.кодПосылки)
                КнопкаСделки(т("prc_open_btn"), вид: .главная, символ: "shippingbox", доступна: !передача.идёт) {
                    передача.вскрытьПосылку()
                }
                /* Своя камера: QR листка → parcel_open {token} после «Вы точно получили товар?». */
                КнопкаСделки(т("prc_scan"), вид: .вторая, символ: "qrcode.viewfinder", доступна: !передача.идёт) {
                    передача.лист = .сканер(встреча: false)
                }
                ошибки
                СсылкаПередачи(т("prc_lost_b"), доступна: !передача.идёт) { передача.вопрос = .потеряна }
            } else if статус == "opened" {
                ПлашкаКодаПередачи(подпись: т("prc_b_opened"), код: посылка.мойКод.isEmpty ? "····" : посылка.мойКод,
                            подписьСверху: false)
                ПодписьСделки(т("prc_b_opened_sub"))
                КнопкаСделки(т("prc_claim_btn"), вид: .главная, символ: "exclamationmark.bubble", доступна: !передача.идёт) {
                    передача.лист = .претензия
                }
            }
        }
        КтоВыбралСпособ(роль: "buyer", выбрал: посылка.организатор, вНачале: статус == "packing")
        КнопкаСменыСпособа(продавец: false, можно: статус == "packing", показатьЗамок: false, действие: действие)
    }

    /// «Куда доставить»: адрес посылки, «точка на карте», «Указать адрес» / «Изменить адрес» (hovAddrEdit → parcel_addr).
    private var адресПокупателя: some View {
        let адрес = посылка.адресКуда
        return VStack(alignment: .leading, spacing: 6) {
            Text(т("prc_b_to"))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            Text(адрес.isEmpty ? СделкиText.т("apk_none2") : адрес)
                .font(.system(size: 14))
                .foregroundStyle(адрес.isEmpty ? Theme.текстВторой : Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            if посылка.точкаКуда != nil {
                Label(т("apk_pin"), systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
            }
            КнопкаСделки(т(адрес.isEmpty ? "apk_set" : "apk_edit"), вид: адрес.isEmpty ? .главная : .вторая,
                         символ: "mappin.and.ellipse", доступна: !передача.идёт) {
                передача.лист = .адресПосылки(откуда: false)
            }
        }
    }

    // MARK: - Общее

    /// hovCourierBtn: нужна точка или адрес с обеих сторон; обе точки есть — выбор Яндекс Go / 2ГИС на экране карточки.
    @ViewBuilder
    private var кнопкаКурьера: some View {
        let откуда = посылка.точкаОткуда ?? сделка.точкаОткуда
        let куда = посылка.точкаКуда
        if (откуда != nil || !сделка.адресОткуда.isEmpty) && (куда != nil || !сделка.адресКуда.isEmpty) {
            КнопкаСделки(СделкиText.т("hnd_call_courier"), вид: .вторая, символ: "car") {
                действие(.курьер(откуда: откуда, куда: куда))
            }
        }
    }

    /// «Неверных попыток: N из 6».
    @ViewBuilder
    private var ошибки: some View {
        if посылка.ошибок > 0 {
            ЗаметкаСделки(Text(ПередачаText.т("prc_fails", n: String(посылка.ошибок))), вид: .плохо)
        }
    }
}

// MARK: - Листок в коробку (hovParcelSlip, hovParcelQR, hovParcelPrint)

/// Подсказка, белый листок с QR и цифрами, «Положите листок ВНУТРЬ коробки…», печать и отправка картинкой.
struct ЛистокВКоробку: View {
    let посылка: ПосылкаСделки
    let номер: String

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьСделки(т("prc_slip_prev"))
            ЛистокПосылки(код: посылка.мойКод, токен: посылка.токен, номер: номер)
            ПодписьСделки(т("prc_slip_why"))
            HStack(spacing: 8) {
                КнопкаСделки(т("prc_print"), вид: .вторая, символ: "printer") { напечатать() }
                КнопкаСделки(т("prc_share"), вид: .вторая, символ: "square.and.arrow.up") { отправить() }
            }
        }
    }

    /// hovParcelPrint: листок отдельной картинкой — системное окно печати (AirPrint).
    @MainActor
    private func напечатать() {
        guard let картинка = ЛистокПосылки.картинка(код: посылка.мойКод, токен: посылка.токен, номер: номер) else { return }
        let сведения = UIPrintInfo(dictionary: nil)
        сведения.outputType = .general
        сведения.jobName = т("prc_slip_h")
        let печать = UIPrintInteractionController.shared
        печать.printInfo = сведения
        печать.printingItem = картинка
        _ = печать.present(animated: true, completionHandler: nil)
    }

    /// Та же картинка — системным листом «Поделиться» (сохранить, отправить себе на компьютер, распечатать позже).
    @MainActor
    private func отправить() {
        guard let картинка = ЛистокПосылки.картинка(код: посылка.мойКод, токен: посылка.токен, номер: номер) else { return }
        ПоделитьсяСайта.системныйЛист([картинка])
    }
}

/// .hov-qr сайта: белый листок (в тёмной теме тоже), «Листок в посылку», QR, цифры, подсказка и номер сделки.
struct ЛистокПосылки: View {
    let код: String
    let токен: String
    let номер: String

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    /// QR листка: /kz/<язык>/cabinet.php?parcel=<open_token> (hovParcelQR сайта).
    static func адрес(_ токен: String) -> String {
        Config.страницаСайта("cabinet.php?parcel=" + СделкиAPI.вАдрес(токен))?.absoluteString ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(т("prc_slip_h"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color(uiColor: Theme.hex(0x0B1F14)))
            КартинкаQRПередачи(текст: Self.адрес(токен), подпись: т("prc_slip_h"))
                .frame(maxWidth: 230)
            Text(код)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .tracking(4)
                .foregroundStyle(Color(uiColor: Theme.hex(0x0B1F14)))
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
            Text(т("prc_slip_s"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Color(uiColor: Theme.hex(0x5B6B62)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(т("prc_slip_d") + номер)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Color(uiColor: Theme.hex(0x8A9A91)))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    /// Листок картинкой для печати и отправки: ширина 320 точек, втрое плотнее, светлая тема.
    @MainActor
    static func картинка(код: String, токен: String, номер: String) -> UIImage? {
        let вид = ЛистокПосылки(код: код, токен: токен, номер: номер)
            .frame(width: 320)
            .padding(12)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let рисовальщик = ImageRenderer(content: вид)
        рисовальщик.scale = 3
        return рисовальщик.uiImage
    }
}

/// QR передачи (листок посылки, код встречи): тёмный #0b1f14 на белом, модули без сглаживания, поле вокруг.
struct КартинкаQRПередачи: View {
    let текст: String
    let подпись: String

    var body: some View {
        Group {
            if let картинка = КэшQRПередачи.картинка(текст) {
                Image(uiImage: картинка)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Color.white.aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(10)
        .background(Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(.isImage)
    }
}

/// Готовые QR по тексту: код встречи рисуется каждую секунду таймера — CIFilter только при новом тексте.
@MainActor
enum КэшQRПередачи {
    private static var готовые: [String: UIImage] = [:]

    static func картинка(_ текст: String) -> UIImage? {
        guard !текст.isEmpty else { return nil }
        if let есть = готовые[текст] { return есть }
        guard let новая = ПоделитьсяСайта.qr(текст, модуль: 8) else { return nil }
        if готовые.count > 16 { готовые.removeAll() }
        готовые[текст] = новая
        return новая
    }
}

// MARK: - Претензия к содержимому (hovParcelClaim)

/// «Что не так с содержимым?»: поле до 300 знаков (≥ 3), «Открыть спор» → parcel_claim.
struct ОкноПретензииПосылки: View {
    @ObservedObject var передача: ПередачаСделкиМодель
    @State private var текст = ""
    @FocusState private var фокус: Bool

    /// Явный init: окно открывает слой карточки из другого файла.
    init(передача: ПередачаСделкиМодель) {
        self.передача = передача
    }

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ШапкаОкнаПередачи(заголовок: т("prc_claim_t"), закрыть: { передача.лист = nil })
                Text(т("prc_claim_l"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                TextField(т("prc_claim_ph"), text: $текст, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($фокус)
                    .modifier(ПолеДенегСделки())
                    .onChange(of: текст) { _, новое in
                        if новое.count > 300 { текст = String(новое.prefix(300)) }
                    }
                ПодписьСделки(т("prc_claim_s"))
                ОшибкаОкнаПередачи(текст: передача.ошибкаОкна)
                КнопкаСделки(т("prc_claim_ok"), вид: .главная, символ: "exclamationmark.bubble", доступна: !передача.идёт) {
                    отправить()
                }
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
        .onAppear { фокус = true }
    }

    private func отправить() {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard чистый.count >= 3 else {
            передача.ошибкаОкна = т("prc_claim_need")
            return
        }
        фокус = false
        передача.претензия(чистый)
    }
}
