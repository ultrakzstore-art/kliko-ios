import SwiftUI
import UIKit
import PhotosUI

/**
 СДЕЛКА С ПОДПИСЬЮ eGov — СВОЁ ОКНО (edsOpen / _edsRender модуля js/cabinet-eds.min.js; владелец: «на сайт не прыгать»).

 Окно «Сделка с подписью eGov» сверху вниз, как у сайта: товар, цена, плашка статуса, «номер · вы продаёте/покупаете ·
 как платить»; полоса «Договор · Встреча/Доставка · Акт · Готово»; способ передачи (выбор — встреча, курьер Яндекса,
 почта с наложенным платежом; реквизиты продавца с проверкой Луна и сканом карты; оплата и вызов курьера; отправка почтой;
 курьер в пути с картой, сроками, звонком и кодом; код посылки); договор с подписями сторон и «Подписать через eGov»;
 встреча — звонок, код передачи с QR или ввод кода с записью места; акт и его подпись; оплата продавцу после курьера;
 «Сделка завершена», спор и решение поддержки, отмена и истечение; документы (своё окно PDF); протокол; «Сообщить о
 проблеме» и «Отменить сделку». Подпись — своим окном eGov (ПотокEgov.шаг, otpStepOpen сайта); пополнение — лист
 «Пополнить кошелёк»; обращение по спору — своя переписка. Страница сайта не открывается ни в одном шаге.
 */
struct ЭкранСделкиEDS: View {
    @StateObject private var модель: МодельСделкиEDS
    let закрыть: () -> Void

    init(id: String, токен: String = "", закрыть: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: МодельСделкиEDS(id: id, токен: токен))
        self.закрыть = закрыть
    }

    /// Ссылка QR (eds.php?action=go&t=): номер сделки окно узнаёт само.
    init(переход токен: String, закрыть: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: МодельСделкиEDS(переход: токен))
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        NavigationStack {
            содержимое
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.фонСтраницы.ignoresSafeArea())
                .modifier(ШапкаСделок(заголовок: т("eds_title")))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(т("close")) { закрыть() }
                    }
                }
                .navigationDestination(isPresented: обращениеОткрыто) {
                    ЭкранОбращения(номер: модель.обращение ?? "")
                }
        }
        .tint(Theme.акцент)
        .overlay(alignment: .bottom) {
            ZStack {
                if let текст = модель.тост {
                    ТостEDS(текст: текст)
                        .padding(.bottom, 28)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: модель.тост)
        }
        .task { await модель.появилась() }
        .onAppear { модель.продолжить() }
        .onDisappear {
            /* Сканер карты во весь экран закрывает окно сделки собой — это не уход из сделки. */
            guard модель.лист != .сканер else { return }
            модель.исчезла()
            NotificationCenter.default.post(name: .klikoСделкаEDSЗакрыта, object: nil)
        }
        .modifier(ОкнаСделкиEDS(модель: модель))
    }

    private var обращениеОткрыто: Binding<Bool> {
        Binding(get: { модель.обращение != nil }, set: { if !$0 { модель.обращение = nil } })
    }

    @ViewBuilder
    private var содержимое: some View {
        if let код = модель.кодПередачи {
            ВидКодаПередачиEDS(модель: модель, код: код)
        } else if let посылка = модель.кодПосылки {
            ВидКодаПосылкиEDS(модель: модель, код: посылка)
        } else if let сделка = модель.сделка {
            ScrollView {
                ТелоСделкиEDS(модель: модель, сделка: сделка)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await модель.загрузить() }
        } else {
            состояние
        }
    }

    @ViewBuilder
    private var состояние: some View {
        switch модель.загрузка {
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: т("login_t"), подпись: т("login_s"), кнопка: т("login"),
                       действие: { модель.войтиВКабинет() })
        case .ошибка(let текст):
            ПустоСайта(значок: "exclamationmark.triangle", заголовок: текст, кнопка: т("retry"),
                       действие: { Task { await модель.загрузить() } })
        case .ссылкаНеВедёт:
            ПустоСайта(значок: "link", заголовок: т("go_fail_t"), подпись: т("go_fail_s"), кнопка: т("my_deals"),
                       действие: { кМоимСделкам() })
        case .идёт, .готово:
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    /// «Мои сделки» — там блок «Сделки с подписью eGov».
    private func кМоимСделкам() {
        закрыть()
        guard NativeRouter.доступна(.сделки) else { return }
        WebBridge.shared.лентаВидна = true
        NativeRouter.shared.цель = .сделки
    }
}

// MARK: - Окна: вопросы, листы, сканер

private struct ОкнаСделкиEDS: ViewModifier {
    @ObservedObject var модель: МодельСделкиEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    func body(content: Content) -> some View {
        content
            .alert(заголовок(модель.вопрос), isPresented: вопросНаЭкране, presenting: модель.вопрос) { вопрос in
                кнопки(вопрос)
            } message: { вопрос in
                Text(текст(вопрос))
            }
            .sheet(item: листНаЭкране, onDismiss: { модель.листЗакрыт() }) { лист in
                окно(лист)
            }
            .fullScreenCover(isPresented: сканерНаЭкране) {
                СканерКартыEDS(найдено: { номер in
                    модель.лист = nil
                    модель.картаСоСканера(номер)
                }, закрыть: { текст in
                    модель.лист = nil
                    if let текст { модель.показать(текст) }
                })
            }
    }

    private var вопросНаЭкране: Binding<Bool> {
        Binding(get: { модель.вопрос != nil }, set: { if !$0 { модель.вопрос = nil } })
    }

    private var листНаЭкране: Binding<МодельСделкиEDS.Лист?> {
        Binding(get: { модель.лист == .сканер ? nil : модель.лист }, set: { новый in
            if новый == nil && модель.лист == .сканер { return }
            модель.лист = новый
        })
    }

    private var сканерНаЭкране: Binding<Bool> {
        Binding(get: { модель.лист == .сканер }, set: { if !$0 && модель.лист == .сканер { модель.лист = nil } })
    }

    // MARK: Вопросы (cabConfirm)

    private func заголовок(_ вопрос: МодельСделкиEDS.Вопрос?) -> String {
        guard let вопрос else { return "" }
        switch вопрос {
        case .ссылка(let посылка):
            return т(посылка ? "eds_parcel_got" : "eds_confirm_meet")
        case .плата(let плата, _, _):
            return т("eds_fee_short_t", ["n": ФорматEDS.деньги(плата)])
        case .нехватка:
            return т("eds_short_t")
        case .курьер:
            return т("eds_ship_courier")
        case .кодКурьеру:
            return т("eds_cr_code")
        case .оплачено:
            return т("eds_paid_btn")
        case .звонок:
            return т("yac_call_t")
        }
    }

    private func текст(_ вопрос: МодельСделкиEDS.Вопрос) -> String {
        switch вопрос {
        case .ссылка(let посылка):
            return т(посылка ? "eds_parcel_link_q" : "eds_confirm_link_q")
        case .плата(_, let нехватка, _):
            return т("eds_fee_short", ["n": ФорматEDS.деньги(нехватка)])
        case .нехватка(let текст):
            return текст
        case .курьер(let текст, _):
            return текст
        case .кодКурьеру(let код):
            return код + "\n\n" + т("eds_cr_code_n")
        case .оплачено:
            return т("eds_paid_q", ["p": ФорматEDS.деньги(модель.сделка?.цена ?? 0)])
        case .звонок(let номер, let добавочный, let минут, let ttl):
            var строки = [т("yac_call_num") + ": " + номер]
            if !добавочный.isEmpty { строки.append(т("yac_call_ext") + ": " + добавочный) }
            var подсказка = т("yac_call_h")
            if ttl { подсказка += " " + т("yac_call_ttl", ["n": String(минут)]) }
            строки.append("")
            строки.append(подсказка)
            return строки.joined(separator: "\n")
        }
    }

    @ViewBuilder
    private func кнопки(_ вопрос: МодельСделкиEDS.Вопрос) -> some View {
        switch вопрос {
        case .ссылка(let посылка):
            Button(т(посылка ? "eds_parcel_confirm" : "eds_confirm_meet")) { модель.подтвердитьПоСсылке() }
            Button(т("eds_back"), role: .cancel) {}
        case .плата(_, _, let пополнить):
            Button(т("eds_fee_topup")) { потом { модель.пополнить(пополнить) } }
            Button(т("eds_back"), role: .cancel) {}
        case .нехватка:
            Button(т("eds_topup")) { потом { модель.пополнить(0) } }
            Button(т("eds_back"), role: .cancel) {}
        case .курьер(_, let заказ):
            Button(т("eds_ship_pick_ok")) { модель.выбратьКурьера(заказ) }
            Button(т("eds_back"), role: .cancel) {}
        case .кодКурьеру:
            Button(т("eds_parcel_done"), role: .cancel) {}
        case .оплачено:
            Button(т("eds_paid_yes")) { модель.отметитьОплату() }
            Button(т("eds_back"), role: .cancel) {}
        case .звонок(let номер, let добавочный, _, _):
            Button(т("yac_call_go")) { модель.набрать(номер, добавочный: добавочный) }
            Button(т("yac_call_close"), role: .cancel) {}
        }
    }

    /// Лист после вопроса — когда вопрос уже уехал.
    private func потом(_ действие: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { действие() }
    }

    // MARK: Листы

    @ViewBuilder
    private func окно(_ лист: МодельСделкиEDS.Лист) -> some View {
        switch лист {
        case .пополнение:
            if let пополнение = модель.пополнение {
                ЭкранПополнения(модель: пополнение, открыть: { ПоверхВсего.открытьАдрес($0) },
                                закрыть: { модель.лист = nil })
            }
        case .карта:
            let доставка = модель.сделка?.доставка ?? ДоставкаEDS()
            ЛистТочкиEDS(адрес: доставка.кудаАдрес, дверь: доставка.кудаДверь) { адрес, точка, дверь in
                модель.точкаКурьера(адрес: адрес, точка: точка, дверь: дверь)
            }
        case .отмена:
            ЛистВопросаEDS(заголовок: т("eds_cancel"), текст: т("eds_cancel_q"), подсказка: т("eds_cancel_ph"),
                           кнопка: т("eds_cancel"), отмена: т("eds_keep"), опасно: true,
                           ответ: { модель.отменить($0) }, закрыть: { модель.лист = nil })
        case .проблема:
            let продавец = модель.сделка?.продавец ?? false
            ЛистВопросаEDS(заголовок: т("eds_report"), текст: т("eds_report_q"),
                           подсказка: т(продавец ? "eds_report_ph_s" : "eds_report_ph_b"),
                           кнопка: т("eds_report_send"), отмена: т("eds_back"),
                           ответ: { модель.сообщить($0) }, закрыть: { модель.лист = nil })
        case .сканер:
            EmptyView()
        }
    }
}

// MARK: - Тело сделки (_edsRender)

private struct ТелоСделкиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                ШапкаСделкиEDS(сделка: сделка)
                if let шаг = сделка.шаг {
                    ШагиEDS(названия: [т("eds_step_contract"), т(сделка.встреча ? "eds_step_meet" : "eds_step_ship"),
                                       т("eds_step_act"), т("eds_step_done")], текущий: шаг)
                }
                БлокДоставкиEDS(модель: модель, сделка: сделка)
                БлокДоговораEDS(модель: модель, сделка: сделка)
                if сделка.статус == "signed" && сделка.встреча {
                    БлокВстречиEDS(модель: модель, сделка: сделка)
                }
                if ["met", "completed", "disputed"].contains(сделка.статус) {
                    БлокАктаEDS(модель: модель, сделка: сделка)
                }
                if сделка.способ == "courier" && сделка.статус == "met" {
                    БлокОплатыПослеEDS(модель: модель, сделка: сделка)
                }
            }
            Group {
                итоги
                СсылкиДокументовEDS(модель: модель, сделка: сделка)
                if !сделка.события.isEmpty {
                    ПротоколEDS(сделка: сделка)
                }
                действия
            }
        }
    }

    /// Готово, спор, решение поддержки, отмена, истечение.
    @ViewBuilder
    private var итоги: some View {
        let решение = сделка.спор?.решение
        if сделка.статус == "completed" && решение == nil {
            ПлашкаEDS(.хорошо, т("eds_done"))
        }
        if сделка.статус == "disputed", let спор = сделка.спор {
            БлокСпораEDS(модель: модель, сделка: сделка, спор: спор)
        }
        if let решение {
            let готово = решение.итог == "completed"
            let когда = решение.когда.isEmpty ? "" : " · " + ФорматEDS.когда(решение.когда)
            let заметка = решение.заметка.isEmpty ? "" : "\n" + решение.заметка
            ПлашкаEDS(готово ? .хорошо : .внимание,
                      текст: Text(т("eds_disp_res") + ": " + т(готово ? "eds_disp_res_done" : "eds_disp_res_cancel")).bold()
                        + Text(когда + заметка))
            if !(сделка.спор?.обращение ?? "").isEmpty {
                РядКнопокEDS {
                    КнопкаEDS(т("eds_ticket_open"), символ: "doc.text", главная: false) { модель.открытьОбращение() }
                }
            }
        }
        if сделка.статус == "cancelled" && сделка.естьОтмена && решение == nil {
            let причина = сделка.причинаОтмены.isEmpty ? "" : " «" + сделка.причинаОтмены + "»"
            ПлашкаEDS(.внимание, т(сделка.отменил == сделка.роль ? "eds_cancelled_me" : "eds_cancelled_other") + причина)
        }
        if сделка.статус == "expired" {
            ПлашкаEDS(.внимание, т("eds_expired_note"))
        }
    }

    /// «Сообщить о проблеме» и «Отменить сделку».
    @ViewBuilder
    private var действия: some View {
        if сделка.можно.сообщить || сделка.можно.отменить {
            РядКнопокEDS {
                if сделка.можно.сообщить {
                    КнопкаEDS(т("eds_report"), символ: "exclamationmark.triangle", главная: false,
                              занята: модель.идёт == "report", доступна: модель.идёт == nil) {
                        модель.лист = .проблема
                    }
                }
                if сделка.можно.отменить {
                    КнопкаEDS(т("eds_cancel"), главная: false, занята: модель.идёт == "cancel",
                              доступна: модель.идёт == nil) {
                        модель.лист = .отмена
                    }
                }
            }
        }
    }
}

// MARK: - Шапка (.eds-head)

private struct ШапкаСделкиEDS: View {
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        let плашка = СтатусEDS.плашка(сделка.статус, способ: сделка.способ)
        HStack(alignment: .center, spacing: 12) {
            КартинкаЛенты(Config.url(сделка.фото), пунктов: 56) {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "shippingbox")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(сделка.название)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(ФорматEDS.тенге(сделка.цена))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize()
                    ПилюляEDS(вид: плашка.вид, текст: плашка.текст)
                }
                Text(подпись)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// «номер · вы продаёте · оплата — …».
    private var подпись: String {
        let роль = т(сделка.продавец ? "eds_you_seller" : "eds_you_buyer")
        let оплата: String
        switch сделка.способ {
        case "courier": оплата = т("eds_pay_note_after")
        case "post": оплата = т("eds_pay_note_cod")
        default: оплата = т("eds_pay_note")
        }
        return [сделка.id, роль, оплата].joined(separator: " · ")
    }
}

// MARK: - Способ передачи (_edsShipHtml)

private struct БлокДоставкиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    private var доставка: ДоставкаEDS { сделка.доставка ?? ДоставкаEDS() }
    private var способ: String { доставка.способ }
    private var курьер: Bool { способ == "courier" }
    private var почта: Bool { способ == "post" }

    /// Цена доставки: «бесплатно, платит продавец» или «N ₸».
    private var ценаДоставки: String {
        доставка.платит == "seller" ? т("eds_ship_free") : ФорматEDS.тенге(доставка.стоимость)
    }

    var body: some View {
        if сделка.можно.выбратьДоставку {
            выбор
        } else if способ != "meet" {
            СекцияEDS {
                заголовокИЦена
                реквизиты
                оплатаДоставки
                вызовКурьера
                отправкаПочтой
                if сделка.статус == "shipping" {
                    вПути
                }
                if доставка.ошибкаВызова && сделка.можно.вызватьКурьера {
                    ПлашкаEDS(.внимание, т("eds_cr_err"))
                }
            }
        }
    }

    // MARK: Выбор способа (can.ship_set)

    private var выбор: some View {
        let занят = модель.идёт != nil
        return СекцияEDS {
            ЗаголовокEDS(текст: т("eds_ship_h"), символ: "box.truck")
            VStack(spacing: 8) {
                ВариантEDS(символ: "person.2", заголовок: т("eds_ship_meet"), подпись: т("eds_ship_meet_s"),
                           выбран: способ == "meet", доступен: !занят) {
                    модель.выбратьСпособ("meet")
                }
                if доставка.курьерВозможен {
                    ВариантEDS(символ: "box.truck", заголовок: т("eds_ship_courier"),
                               подпись: курьер ? т("eds_ship_courier_on", ["a": доставка.кудаАдрес, "f": ценаДоставки])
                                               : т("eds_ship_courier_s"),
                               выбран: курьер, доступен: !занят) {
                        модель.выбратьСпособ("courier")
                    }
                }
                ВариантEDS(символ: "shippingbox", заголовок: т("eds_ship_post"), подпись: т("eds_ship_post_s"),
                           выбран: почта, доступен: !занят) {
                    модель.выбратьСпособ("post")
                }
            }
        }
    }

    // MARK: Заголовок, куда и цена

    @ViewBuilder
    private var заголовокИЦена: some View {
        ЗаголовокEDS(текст: т(курьер ? "eds_ship_courier" : "eds_ship_post"), символ: курьер ? "box.truck" : "shippingbox")
        if курьер {
            СтрокаEDS(ключ: т("eds_ship_to"), значение: доставка.кудаАдрес)
            let оплачена = доставка.оплачена ? " · " + т("eds_ship_paid") : ""
            let возвращена = доставка.возвращена ? " · " + т("eds_ship_back") : ""
            СтрокаEDS(ключ: т("eds_ship_fee"), значение: ценаДоставки + оплачена + возвращена)
        } else {
            ЗаметкаEDS(т("eds_ship_post_n"))
        }
    }

    // MARK: Реквизиты продавца (can.pay_to)

    @ViewBuilder
    private var реквизиты: some View {
        if сделка.можно.реквизиты {
            БлокРеквизитовEDS(модель: модель, реквизиты: доставка.реквизиты)
        } else if курьер && сделка.продавец && сделка.статус == "signing" && доставка.реквизиты.есть {
            СтрокаEDS(ключ: т("eds_payto_short"), значение: доставка.реквизиты.показ)
        }
    }

    // MARK: Оплата доставки (can.ship_pay) и ожидание

    @ViewBuilder
    private var оплатаДоставки: some View {
        if сделка.можно.оплатитьДоставку {
            ЗаметкаEDS(т("eds_ship_pay_n"))
            КнопкаEDS(т("eds_ship_pay", ["f": ФорматEDS.тенге(доставка.стоимость)]), символ: "creditcard",
                      занята: модель.идёт == "ship_pay", доступна: модель.идёт == nil) {
                модель.оплатитьДоставку()
            }
        } else if курьер && сделка.статус == "signed" {
            if сделка.покупатель {
                ЗаметкаEDS(т(доставка.платит == "seller" ? "eds_ship_wait_seller_free" : "eds_ship_wait_seller"))
            } else if !сделка.можно.вызватьКурьера {
                ЗаметкаEDS(т("eds_ship_wait_buyer"))
            }
        }
    }

    // MARK: Вызов курьера (can.ship_call)

    @ViewBuilder
    private var вызовКурьера: some View {
        if сделка.можно.вызватьКурьера {
            ЗаметкаEDS(т("eds_ship_call_n"))
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_ship_pickup"))
                TextField(т("co_to_ph2"), text: $модель.заборАдрес)
                    .textContentType(.fullStreetAddress)
                    .onChange(of: модель.заборАдрес) { _, новое in
                        if новое.count > 300 { модель.заборАдрес = String(новое.prefix(300)) }
                    }
                    .modifier(ПолеEDS())
            }
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_ship_pickup_door"))
                TextField("", text: $модель.заборДверь)
                    .onChange(of: модель.заборДверь) { _, новое in
                        if новое.count > 40 { модель.заборДверь = String(новое.prefix(40)) }
                    }
                    .modifier(ПолеEDS())
                    .accessibilityLabel(т("eds_ship_pickup_door"))
            }
            КнопкаEDS(т(доставка.курьер?.сорвался == true ? "eds_ship_recall" : "eds_ship_call"), символ: "box.truck",
                      занята: модель.идёт == "ship_call", доступна: модель.идёт == nil) {
                модель.вызватьКурьера()
            }
        }
    }

    // MARK: Отправка почтой (can.post_send)

    @ViewBuilder
    private var отправкаПочтой: some View {
        if сделка.можно.отправитьПочтой {
            ЗаметкаEDS(т("eds_post_n"))
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_post_carrier"))
                Picker(т("eds_post_carrier"), selection: $модель.перевозчик) {
                    Text(т("eds_post_kazpost")).tag("kazpost")
                    Text(т("eds_post_cdek")).tag("cdek")
                    Text(т("eds_post_other")).tag("other")
                }
                .pickerStyle(.segmented)
            }
            if модель.перевозчик == "other" {
                VStack(alignment: .leading, spacing: 4) {
                    ПодписьПоляEDS(текст: т("eds_post_name"))
                    TextField("", text: $модель.названиеПеревозчика)
                        .onChange(of: модель.названиеПеревозчика) { _, новое in
                            if новое.count > 60 { модель.названиеПеревозчика = String(новое.prefix(60)) }
                        }
                        .modifier(ПолеEDS())
                        .accessibilityLabel(т("eds_post_name"))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_post_track"))
                TextField("", text: $модель.трек)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: модель.трек) { _, новое in
                        if новое.count > 40 { модель.трек = String(новое.prefix(40)) }
                    }
                    .modifier(ПолеEDS())
                    .accessibilityLabel(т("eds_post_track"))
            }
            КнопкаEDS(т("eds_post_send"), символ: "shippingbox", занята: модель.идёт == "post_send",
                      доступна: модель.идёт == nil) {
                модель.отправитьПочтой()
            }
        } else if почта && сделка.статус == "signed" && сделка.покупатель {
            ЗаметкаEDS(т("eds_post_wait"))
        }
    }

    // MARK: В пути (shipping)

    @ViewBuilder
    private var вПути: some View {
        if курьер, let к = доставка.курьер {
            КурьерВПутиEDS(модель: модель, сделка: сделка, курьер: к)
        }
        if почта, let п = доставка.почта {
            СтрокаEDS(ключ: т("eds_post_carrier"), значение: п.название)
            СтрокаEDS(ключ: т("eds_post_track"), значение: п.трек)
            if let адрес = URL(string: п.адрес), !п.адрес.isEmpty {
                РядКнопокEDS {
                    КнопкаEDS(т("eds_post_where"), символ: "shippingbox", главная: false) {
                        ОткрытьСсылкуEDS.открыть(адрес)
                    }
                }
            }
            if сделка.покупатель {
                ЗаметкаEDS(т("eds_post_buyer"))
            }
        }
        if сделка.можно.кодПосылки {
            РядКнопокEDS {
                КнопкаEDS(т("eds_parcel_show"), символ: "qrcode", главная: false, занята: модель.идёт == "parcel_code",
                          доступна: модель.идёт == nil) {
                    модель.кодПосылкиПоказать()
                }
            }
        }
        if сделка.можно.ввестиКод {
            ЗаметкаEDS(т("eds_parcel_enter_n"))
            ПолеКодаEDS(модель: модель)
            КнопкаEDS(т("eds_parcel_confirm"), символ: "checkmark", занята: модель.идёт == "enter",
                      доступна: модель.идёт == nil) {
                модель.ввестиКод()
            }
        }
    }
}

/// Курьер Яндекса в пути: статус, кто везёт, карта, сроки, звонок, «Где курьер», код для курьера.
private struct КурьерВПутиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS
    let курьер: КурьерEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        СтрокаEDS(ключ: т("eds_cr_status"), значение: статус)
        if !курьер.имя.isEmpty {
            СтрокаEDS(ключ: т("eds_cr_who"),
                      значение: [курьер.имя, курьер.машина].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if курьер.где != nil || курьер.откуда != nil || курьер.куда != nil {
            КартаКурьераEDS(откуда: курьер.откуда, куда: курьер.куда, где: курьер.где)
        }
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let строки = сроки
            if !строки.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(строки.enumerated()), id: \.offset) { пара in
                        HStack(alignment: .firstTextBaseline) {
                            Text(пара.element.0)
                                .foregroundStyle(Theme.текстВторой)
                            Spacer(minLength: 8)
                            Text(ФорматEDS.эта(пара.element.1, сейчас: модель.сейчасСервера))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.текст)
                        }
                        .font(.system(size: 14))
                    }
                }
            }
        }
        if курьер.звонок || !курьер.отслеживание.isEmpty || сделка.можно.кодКурьеру {
            РядКнопокEDS {
                if курьер.звонок {
                    КнопкаEDS(т("eds_cr_call"), символ: "phone", занята: модель.идёт == "courier_phone",
                              доступна: модель.идёт == nil) {
                        модель.позвонитьКурьеру()
                    }
                }
                if let адрес = URL(string: курьер.отслеживание), !курьер.отслеживание.isEmpty {
                    КнопкаEDS(т("eds_cr_track"), символ: "box.truck", главная: false) {
                        ОткрытьСсылкуEDS.открыть(адрес)
                    }
                }
                if сделка.можно.кодКурьеру {
                    КнопкаEDS(т("eds_cr_code"), символ: "checkmark", занята: модель.идёт == "courier_code",
                              доступна: модель.идёт == nil) {
                        модель.кодКурьеру()
                    }
                }
            }
        }
        if курьер.сорвался && сделка.покупатель {
            ЗаметкаEDS(т("eds_cr_failed_b"))
        }
    }

    private var статус: String {
        let с = курьер.статус
        if курьер.снят { return т("eds_cr_cancelled") }
        if курьер.сорвался { return т("eds_cr_failed") }
        if с == "pickup_arrived" || с == "ready_for_pickup_confirmation" { return т("eds_cr_at_seller") }
        if с == "delivery_arrived" || с == "ready_for_delivery_confirmation" { return т("eds_cr_at_buyer") }
        switch курьер.этап {
        case "picked": return т("eds_cr_picked")
        case "delivered": return т("eds_cr_delivered")
        case "returning", "returned": return т("eds_cr_returning")
        default: return т("eds_cr_search")
        }
    }

    /// _edsEtaHtml: возврат — «Курьер будет у вас» / «Вернёт продавцу»; иначе до забора и до вручения.
    private var сроки: [(String, Double)] {
        let с = курьер.статус
        let возврат = ["returning", "return_arrived", "ready_for_return_confirmation"].contains(с)
        let везёт = ["pickuped", "delivery_arrived", "ready_for_delivery_confirmation"].contains(с)
        let продавец = сделка.продавец
        var итог: [(String, Double)] = []
        if возврат {
            if курьер.етаВ > 0 { итог.append((т(продавец ? "yac_eta_you" : "yac_eta_back"), курьер.етаВ)) }
        } else {
            if !везёт && курьер.етаА > 0 { итог.append((т(продавец ? "yac_eta_you" : "yac_eta_seller"), курьер.етаА)) }
            if курьер.етаБ > 0 { итог.append((т(продавец ? "yac_eta_buyer" : "yac_eta_you2"), курьер.етаБ)) }
        }
        return итог
    }
}

/// Чужая страница (Яндекс, перевозчик) — листом Safari внутри приложения; наша — своим экраном (без сайта).
enum ОткрытьСсылкуEDS {
    @MainActor
    static func открыть(_ адрес: URL) {
        if Config.deepLink(адрес) != nil {
            ПоверхВсего.открытьАдрес(адрес)
        } else {
            БезСайта.внешняя(адрес)
        }
    }
}

// MARK: - Реквизиты продавца (edsPayToEdit / edsPayToSave)

private struct БлокРеквизитовEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let реквизиты: РеквизитыEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        ЗаметкаEDS(текст: Text(т("eds_payto_h")).bold())
        if реквизиты.есть {
            СтрокаEDS(ключ: т("eds_payto_now"), значение: реквизиты.показ)
            if !модель.правимРеквизиты {
                РядКнопокEDS {
                    КнопкаEDS(т("eds_payto_edit"), символ: "creditcard", главная: false) {
                        модель.правимРеквизиты = true
                    }
                }
            }
        }
        if !реквизиты.есть || модель.правимРеквизиты {
            форма
        }
    }

    private var форма: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_payto_type"))
                Picker(т("eds_payto_type"), selection: $модель.типРеквизитов) {
                    Text(т("eds_payto_kaspi")).tag("kaspi")
                    Text(т("eds_payto_card")).tag("card")
                    Text(т("eds_payto_account")).tag("account")
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(ПолеEDS())
            }
            поле
            РядКнопокEDS {
                КнопкаEDS(т("eds_payto_save"), символ: "creditcard", главная: false, занята: модель.идёт == "pay_to",
                          доступна: модель.идёт == nil) {
                    модель.сохранитьРеквизиты()
                }
            }
        }
    }

    @ViewBuilder
    private var поле: some View {
        switch модель.типРеквизитов {
        case "card":
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_payto_val_card"))
                HStack(spacing: 8) {
                    TextField(text: $модель.карта, prompt: Text(verbatim: "0000 0000 0000 0000")) {
                        Text(т("eds_payto_val_card"))
                    }
                    .keyboardType(.numberPad)
                    .textContentType(.creditCardNumber)
                    .monospacedDigit()
                    .modifier(ПолеEDS(ошибка: модель.ошибкаКарты != nil))
                    if КамераКартыEDS.есть {
                        Button {
                            модель.лист = .сканер
                        } label: {
                            Image(systemName: "camera")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.текст)
                                .frame(width: 46, height: 42)
                                .background(Theme.поверхность,
                                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                        .accessibilityLabel(т("eds_scan_t"))
                        .accessibilityHint(т("a11y_scan"))
                    }
                }
                if let ошибка = модель.ошибкаКарты {
                    Text(ошибка)
                        .font(.system(size: 13))
                        .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case "account":
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_payto_val_acc"))
                TextField(т("eds_payto_acc_ph"), text: $модель.счёт, axis: .vertical)
                    .lineLimit(3...5)
                    .autocorrectionDisabled()
                    .onChange(of: модель.счёт) { _, новое in
                        if новое.count > 400 { модель.счёт = String(новое.prefix(400)) }
                    }
                    .modifier(ПолеEDS())
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                ПодписьПоляEDS(текст: т("eds_payto_val_kaspi"))
                TextField(text: номерKaspi, prompt: Text(verbatim: "+7 (7__) ___-__-__")) {
                    Text(т("eds_payto_val_kaspi"))
                }
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .modifier(ПолеEDS())
            }
        }
    }

    /// Маска «+7 (7XX) XXX-XX-XX», как у полей телефона сайта (klkFmt).
    private var номерKaspi: Binding<String> {
        Binding(get: { модель.kaspi }, set: { модель.kaspi = НомерКЗ.формат($0) })
    }
}

// MARK: - Договор

private struct БлокДоговораEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    var body: some View {
        СекцияEDS {
            ЗаголовокEDS(текст: т("eds_doc_contract"), символ: "doc.text")
            ПодписьСтороныEDS(текст: т("eds_who_seller") + ": " + сделка.имяПродавца, когда: сделка.договорПродавец)
            ПодписьСтороныEDS(текст: т("eds_who_buyer") + ": " + сделка.имяПокупателя, когда: сделка.договорПокупатель)
            подписать
        }
    }

    @ViewBuilder
    private var подписать: some View {
        let срок = ФорматEDS.когда(сделка.срок)
        if сделка.можно.подписатьДоговор {
            let плата = сделка.плата
            ЗаметкаEDS(т("eds_sign_contract_hint", ["d": срок]))
            if плата > 0 {
                ЗаметкаEDS(т("eds_fee_note", ["n": ФорматEDS.деньги(плата)]))
            }
            КнопкаEDS(плата > 0 ? т("eds_sign_contract_fee", ["n": ФорматEDS.деньги(плата)]) : т("eds_sign_contract"),
                      символ: "signature", занята: модель.идёт == "sign_contract", доступна: модель.идёт == nil) {
                модель.подписать("contract")
            }
        } else if сделка.статус == "signing" && сделка.можно.реквизиты && !(сделка.доставка?.реквизиты.есть ?? false) {
            ЗаметкаEDS(т("eds_payto_first"))
        } else if сделка.статус == "signing" {
            ЗаметкаEDS(т("eds_wait_other", ["d": срок]))
        }
    }
}

// MARK: - Встреча (signed + meet)

private struct БлокВстречиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        СекцияEDS {
            ЗаголовокEDS(текст: т("eds_step_meet"), символ: "qrcode")
            let цифры = ФорматEDS.цифры(сделка.другаяТелефон)
            if !цифры.isEmpty {
                РядКнопокEDS {
                    КнопкаEDS(т("eds_call") + ": " + сделка.другаяИмя, символ: "phone", главная: false) {
                        if let адрес = URL(string: "tel:+" + цифры) { UIApplication.shared.open(адрес) }
                    }
                }
            }
            if сделка.можно.показатьКод {
                ЗаметкаEDS(т("eds_meet_seller"))
                ФлажокEDS(включён: $модель.гео, текст: т("eds_geo_opt"))
                КнопкаEDS(т("eds_show_code"), символ: "qrcode", занята: модель.идёт == "show_code",
                          доступна: модель.идёт == nil) {
                    модель.показатьКод()
                }
            }
            if сделка.можно.ввестиКод {
                ЗаметкаEDS(т("eds_meet_buyer"))
                ПолеКодаEDS(модель: модель)
                ФлажокEDS(включён: $модель.гео, текст: т("eds_geo_opt"))
                КнопкаEDS(т("eds_confirm_meet"), символ: "checkmark", занята: модель.идёт == "enter",
                          доступна: модель.идёт == nil) {
                    модель.ввестиКод()
                }
            }
            ЗаметкаEDS(EDSText.т("eds_meet_until", ["d": ФорматEDS.когда(сделка.срок)]))
        }
    }
}

/// #eds-code: 6 цифр, крупно по центру, код из SMS подставляется сам.
private struct ПолеКодаEDS: View {
    @ObservedObject var модель: МодельСделкиEDS

    var body: some View {
        TextField(text: код, prompt: Text(EDSText.т("eds_code_ph"))) {
            Text(EDSText.т("eds_code_ph"))
        }
        .keyboardType(.numberPad)
        .textContentType(.oneTimeCode)
        .font(.system(size: 24, weight: .semibold))
        .tracking(4.8)
        .monospacedDigit()
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.текст)
        .padding(10)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var код: Binding<String> {
        Binding(get: { модель.кодВвод }, set: { модель.кодВвод = String(ФорматEDS.цифры($0).prefix(6)) })
    }
}

// MARK: - Акт

private struct БлокАктаEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    var body: some View {
        СекцияEDS {
            ЗаголовокEDS(текст: т("eds_doc_act"), символ: "signature")
            ЗаметкаEDS(текстАкта)
            ПодписьСтороныEDS(текст: т("eds_who_seller"), когда: сделка.актПродавец)
            ПодписьСтороныEDS(текст: т("eds_who_buyer"), когда: сделка.актПокупатель)
            if сделка.можно.подписатьАкт {
                ЗаметкаEDS(подсказка)
                КнопкаEDS(т("eds_sign_act"), символ: "signature", занята: модель.идёт == "sign_act",
                          доступна: модель.идёт == nil) {
                    модель.подписать("act")
                }
            }
        }
    }

    /// Две строки акта: что подтверждает продавец и что — покупатель.
    private var текстАкта: String {
        let цена = ФорматEDS.деньги(сделка.цена)
        switch сделка.способ {
        case "courier":
            let часов = (сделка.доставка?.часовНаОплату ?? 0) > 0 ? (сделка.доставка?.часовНаОплату ?? 24) : 24
            return т("eds_act_seller_c", ["p": цена]) + "\n" + т("eds_act_buyer_c", ["p": цена, "h": String(часов)])
        case "post":
            return т("eds_act_seller_p", ["p": цена]) + "\n" + т("eds_act_buyer_p", ["p": цена])
        default:
            return т("eds_act_seller", ["p": цена]) + "\n" + т("eds_act_buyer", ["p": цена])
        }
    }

    private var подсказка: String {
        if !сделка.встреча {
            if сделка.покупатель {
                return т(сделка.способ == "courier" ? "eds_act_hint_buyer_c" : "eds_act_hint_buyer_p")
            }
            return т("eds_act_hint_seller_d")
        }
        return т(сделка.покупатель ? "eds_act_hint_buyer" : "eds_act_hint_seller")
    }
}

// MARK: - Оплата продавцу после курьера (_edsPayAfterHtml)

private struct БлокОплатыПослеEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    private var доставка: ДоставкаEDS { сделка.доставка ?? ДоставкаEDS() }

    var body: some View {
        if сделка.покупатель && сделка.актПокупатель != nil {
            оплата
        } else if сделка.продавец {
            if сделка.актПокупатель != nil {
                if сделка.актПродавец == nil {
                    ЗаметкаEDS(доставка.оплатаОтмечена ? т("eds_pay_marked")
                                                       : т("eds_pay_wait", ["d": ФорматEDS.когда(доставка.оплатитьДо)]))
                }
            } else {
                ЗаметкаEDS(т("eds_pay_wait_act"))
            }
        }
    }

    /// .eds-pay: рамка --acc-on 1,5, фон --tint-ok.
    private var оплата: some View {
        let р = доставка.реквизиты
        let способы = ["kaspi": т("eds_payto_kaspi"), "card": т("eds_payto_card"), "account": т("eds_payto_account")]
        return VStack(alignment: .leading, spacing: 8) {
            ЗаголовокEDS(текст: т("eds_pay_h", ["p": ФорматEDS.деньги(сделка.цена)]), символ: "creditcard")
            ЗаметкаEDS(способы[р.тип] ?? "")
            Text(р.показ)
                .font(.system(size: 20, weight: .heavy))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !доставка.оплатитьДо.isEmpty {
                ЗаметкаEDS(т("eds_pay_due", ["d": ФорматEDS.когда(доставка.оплатитьДо)]))
            }
            if р.открыты || сделка.можно.отметитьОплату {
                РядКнопокEDS {
                    if р.открыты {
                        КнопкаEDS(т("eds_copy"), символ: "doc.on.doc", главная: false) { модель.скопироватьРеквизиты() }
                    }
                    if сделка.можно.отметитьОплату {
                        КнопкаEDS(т("eds_paid_btn"), символ: "checkmark", занята: модель.идёт == "paid_mark",
                                  доступна: модель.идёт == nil) {
                            модель.вопрос = .оплачено
                        }
                    }
                }
            }
            if !сделка.можно.отметитьОплату && доставка.оплатаОтмечена {
                ПлашкаEDS(.хорошо, т("eds_paid_done"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаСделокКабинета.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(КраскаСделокКабинета.акцент, lineWidth: 1.5)
        }
    }
}

// MARK: - Спор

private struct БлокСпораEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS
    let спор: СпорEDS

    @State private var фото: PhotosPickerItem? = nil

    /// Свой init: с private @State встроенный был бы private — ТелоСделкиEDS его не видит.
    init(модель: МодельСделкиEDS, сделка: СделкаEDS, спор: СпорEDS) {
        self.модель = модель
        self.сделка = сделка
        self.спор = спор
    }

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    /// «Фото к спору: N из 6 …» (если есть) и «Пока идёт разбор…».
    private var заметкаПаузы: String {
        let пауза = т("eds_disp_pause")
        guard спор.фото > 0 else { return пауза }
        return EDSText.т("eds_disp_photos", ["n": String(спор.фото)]) + " " + пауза
    }

    var body: some View {
        let я = спор.кто == сделка.роль
        let причина = спор.причина.isEmpty ? "" : "\n«" + спор.причина + "»"
        ПлашкаEDS(.плохо, текст: Text(т(я ? "eds_disp_me" : "eds_disp_other")).bold() + Text(причина))
        ЗаметкаEDS(т(я ? "eds_disp_me_n" : "eds_disp_other_n"))
        if !спор.обращение.isEmpty || спор.фото < 6 {
            РядКнопокEDS {
                if !спор.обращение.isEmpty {
                    КнопкаEDS(т(я ? "eds_ticket_open" : "eds_ticket_reply"), символ: "doc.text") {
                        модель.открытьОбращение()
                    }
                }
                if спор.фото < 6 {
                    PhotosPicker(selection: $фото, matching: .images) {
                        ЯрлыкКнопкиEDS(надпись: т("eds_disp_photo"), символ: "camera", главная: false,
                                       занята: модель.идёт == "dispute_photo", доступна: модель.идёт == nil)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                    .disabled(модель.идёт != nil)
                    .accessibilityLabel(т("eds_disp_photo"))
                }
            }
        }
        ЗаметкаEDS(заметкаПаузы)
            .onChange(of: фото) { _, выбрано in
                guard let выбрано else { return }
                фото = nil
                Task { @MainActor in
                    if let данные = try? await выбрано.loadTransferable(type: Data.self) {
                        модель.фотоСпора(данные)
                    } else {
                        модель.показать(EDSText.т("eds_disp_photo_bad"))
                    }
                }
            }
    }
}

// MARK: - Документы (.eds-links)

private struct СсылкиДокументовEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { ссылки }
            VStack(alignment: .leading, spacing: 8) { ссылки }
        }
    }

    @ViewBuilder
    private var ссылки: some View {
        ссылка(т("eds_doc_contract"), адрес: сделка.документДоговора)
        if !сделка.документАкта.isEmpty {
            ссылка(т("eds_doc_act"), адрес: сделка.документАкта)
        }
    }

    private func ссылка(_ название: String, адрес: String) -> some View {
        let есть = !адрес.isEmpty && адрес != "#"
        return Button {
            модель.открытьДокумент(адрес, заголовок: название)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(название)
                    .font(.system(size: 14, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(КраскаСделокКабинета.акцент)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .opacity(есть ? 1 : 0.55)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!есть)
    }
}

// MARK: - Протокол

private struct ПротоколEDS: View {
    let сделка: СделкаEDS

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        СвёрткаEDS(заголовок: т("eds_protocol"), подпись: т("eds_protocol_sub"), символ: "clock") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(сделка.события) { событие in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ФорматEDS.когда(событие.когда))
                            .monospacedDigit()
                            .foregroundStyle(Theme.текстВторой)
                            .frame(minWidth: 98, alignment: .leading)
                        Text(строка(событие))
                            .foregroundStyle(Theme.текст)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 13))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func строка(_ с: СобытиеEDS) -> String {
        let кто: String
        switch с.кто {
        case "buyer": кто = т("eds_who_buyer")
        case "seller": кто = т("eds_who_seller")
        case "system": кто = т("eds_who_system")
        default: кто = с.кто
        }
        var строка = кто + ": " + EDSText.событие(с.что)
        if с.место { строка += " · " + т("eds_ev_geo") }
        return строка
    }
}

// MARK: - Код передачи (edsShowCode) и код посылки (_edsParcelShow)

private struct ВидКодаПередачиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let код: МодельСделкиEDS.КодПередачи

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { EDSText.т(ключ, з) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ЗаголовокEDS(текст: т("eds_code_h"), символ: "qrcode")
                    .frame(maxWidth: .infinity, alignment: .leading)
                КодEDS(текст: код.код)
                QREDS(код.ссылка)
                TimelineView(.periodic(from: .now, by: 1)) { контекст in
                    let осталось = max(0, Int(код.истекает.timeIntervalSince(контекст.date).rounded()))
                    Text(осталось > 0 ? т("eds_code_left", ["t": Self.минуты(осталось)]) : т("eds_code_expired"))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                }
                ЗаметкаEDS(т("eds_code_hint", ["m": String(код.минут)]))
                РядКнопокEDS {
                    поделиться
                    КнопкаEDS(т("eds_code_back"), главная: false) { модель.закрытьКод() }
                }
                ЗаметкаEDS(т("eds_share_hint"))
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var поделиться: some View {
        let тема = т("eds_share_text", ["id": модель.сделка?.id ?? модель.id])
        if let адрес = URL(string: код.ссылка), !код.ссылка.isEmpty {
            ShareLink(item: адрес, subject: Text(тема), message: Text(тема)) {
                ЯрлыкКнопкиEDS(надпись: т("eds_share"), символ: "square.and.arrow.up", главная: false)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        }
    }

    /// «9:05».
    private static func минуты(_ секунд: Int) -> String {
        let с = секунд % 60
        return String(секунд / 60) + ":" + (с < 10 ? "0" : "") + String(с)
    }
}

private struct ВидКодаПосылкиEDS: View {
    @ObservedObject var модель: МодельСделкиEDS
    let код: МодельСделкиEDS.КодПосылки

    private func т(_ ключ: String) -> String { EDSText.т(ключ) }

    var body: some View {
        ScrollView {
            СекцияEDS {
                ЗаголовокEDS(текст: т("eds_parcel_h"), символ: "qrcode")
                КодEDS(текст: код.код.replacingOccurrences(of: "^(\\d{3})(\\d{3})", with: "$1 $2",
                                                           options: .regularExpression))
                QREDS(код.ссылка)
                ЗаметкаEDS(т("eds_parcel_n"))
                КнопкаEDS(т("eds_parcel_done"), главная: false) { модель.закрытьКод() }
            }
            .padding(16)
        }
    }
}
