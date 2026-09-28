import SwiftUI
import PhotosUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — УСЛУГА, СПОР, ОЦЕНКА (этап 43, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Услуга (kind=service, renderDeal сайта поверх товара): «Что нужно сделать», аванс, «Подтвердить условия» и «Отклонить
 заявку» исполнителя (accept_terms — без денег), остальное — деньги (страница сайта).
 Спор в карточке (disputed): причина, «Решение модератора за 24–48 часов», «Решить между собой» (деньги — сайт),
 «Загрузить доказательство для модератора» (upload_evidence — своё).
 Оценка после сделки (dealReviewEdit): звёзды, реакция, подсказки «Что понравилось?» / «Что случилось?», отзыв.
 */
struct ДействияУслуги: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var сумма: String { СделкиФормат.тенге(сделка.сумма) }
    private var аванс: String { СделкиФормат.тенге(сделка.аванс) }
    private var остаток: String { СделкиФормат.тенге(max(0, сделка.сумма - сделка.аванс)) }
    private var естьАванс: Bool { сделка.авансПроцент > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            чтоСделать
            switch (сделка.статус, сделка.продавец) {
            case ("proposed", true): заявкаИсполнителю
            case ("proposed", false): заявкаЗаказчика
            case ("accepted", false): согласованоЗаказчику
            case ("accepted", true): согласованоИсполнителю
            case ("held", true): вРаботеИсполнителю
            case ("held", false): вРаботеЗаказчику
            case ("delivered", false): выполненоЗаказчику
            case ("delivered", true): выполненоИсполнителю
            default: EmptyView()
            }
        }
    }

    /// Блок «Что нужно сделать» и «Срок:» (t в ветке услуги).
    @ViewBuilder
    private var чтоСделать: some View {
        if !сделка.чтоСделать.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(т("dl_what_to_do").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.текстВторой)
                Text(сделка.чтоСделать)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if !сделка.срокУслуги.isEmpty {
                    (Text(Image(systemName: "calendar")) + Text(" " + т("dl_term") + " ") + Text(сделка.срокУслуги).bold())
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
    }

    /// n: «Аванс P% (V ₸) уходит исполнителю сразу при оплате, остаток H ₸ — после приёмки работы.»
    private var строкаАванса: Text {
        guard естьАванс else { return Text("") }
        return Text("\n" + т("dl_advance") + " ") + Text(String(сделка.авансПроцент) + "%").bold()
            + Text(" (" + аванс + ") " + т("dl_advance_note_a") + " ") + Text(остаток).bold()
            + Text(" " + т("dl_advance_note_b"))
    }

    @ViewBuilder
    private var заявкаИсполнителю: some View {
        ЗаметкаСделки(Text(т("dl_svc_proposed_note")) + строкаАванса, вид: .инфо, символ: "doc.text")
        КнопкаСделки(т("dl_confirm_terms"), вид: .главная, символ: "checkmark.circle", доступна: !модель.занято) {
            действие(.подтвердитьУсловия)
        }
        КнопкаСделки(т("dl_decline_request"), вид: .опасная, доступна: !модель.занято) { действие(.отклонитьЗаявку) }
    }

    @ViewBuilder
    private var заявкаЗаказчика: some View {
        ЗаметкаСделки(Text(т("dl_request_sent")).bold() + Text("\n" + т("dl_request_sent_note")).font(.system(size: 13))
                      + строкаАванса, вид: .предупреждение, символ: "hourglass", поЦентру: true)
        КнопкаСделки(т("dl_cancel_request"), вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
    }

    @ViewBuilder
    private var согласованоЗаказчику: some View {
        ЗаметкаСделки(Text(т("dl_contractor_confirmed")).bold() + Text(" " + т("svc_pay_note")) + строкаАванса,
                      вид: .хорошо, символ: "checkmark.circle")
        КнопкаСделки(т("bc_pay"), вид: .главная, символ: "lock", сумма: СделкиФормат.тенге(сделка.кОплате),
                     наСайт: ДеньгиКнопок.наСайте) {
            действие(.деньги(.оплатить))
        }
        VStack(spacing: 2) {
            Text(т("dl_pay_escrow_note"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
            Text(т("dl_amount_word") + " " + сумма + " + " + т("dl_service_fee"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        КнопкаСделки(т("dl_cancel"), вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
    }

    @ViewBuilder
    private var согласованоИсполнителю: some View {
        let авансЧасть = естьАванс ? " " + т("dl_get_advance") + " " + аванс + " " + т("dl_and") : ""
        ЗаметкаСделки(Text(т("dl_you_confirmed")).bold()
                      + Text("\n" + т("dl_await_pay_svc_a") + авансЧасть + " " + т("dl_can_start")).font(.system(size: 13)),
                      вид: .предупреждение, символ: "hourglass", поЦентру: true)
        КнопкаСделки(т("dl_cancel"), вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
    }

    @ViewBuilder
    private var вРаботеИсполнителю: some View {
        let деньги: Text = естьАванс
            ? Text(т("dl_advance") + " ") + Text(аванс).bold() + Text(" " + т("dl_already_yours") + " ") + Text(остаток).bold()
                + Text(" " + т("dl_frozen"))
            : Text(т("dl_amount_word") + " ") + Text(сумма).bold() + Text(" " + т("dl_frozen_f"))
        ЗаметкаСделки(Text(т("dl_paid_escrow_svc")).bold() + Text(" ") + деньги + Text(" " + т("dl_after_acceptance")),
                      вид: .хорошо, символ: "lock")
        /* «Работа выполнена» (seller_confirm) переводит услугу к приёмке и запускает выплату — деньги, этап 44. */
        if Config.деньгиСделок {
            /* Этап 44: #dm-seller-note сайта — комментарий уходит в seller_confirm {note}. */
            TextField(ДеньгиСделкиText.т("dl_note_ph2"), text: $модель.заметкаИсполнителя, axis: .vertical)
                .lineLimit(2...4)
                .modifier(ПолеДенегСделки())
        }
        КнопкаСделки(т("dl_work_done_btn"), вид: .главная, символ: "checkmark.circle", наСайт: ДеньгиКнопок.наСайте) {
            действие(.деньги(.работаВыполнена))
        }
        КнопкаСделки(т("dl_cancel_refund_rest_client") + (естьАванс ? т("dl_advance_no_refund") : "") + ")",
                     вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
    }

    @ViewBuilder
    private var вРаботеЗаказчику: some View {
        let деньги = естьАванс
            ? [т("dl_advance"), аванс, т("dl_advance_materials"), остаток, т("dl_at_platform")].joined(separator: " ")
            : т("dl_sum_at_platform")
        ЗаметкаСделки(Text(т("dl_paid_started")).bold() + Text(" " + деньги + " " + т("dl_goes_after_accept")),
                      вид: .инфо, символ: "hammer")
        КнопкаСделки(т("dl_cancel_refund_rest") + (естьАванс ? т("dl_advance_no_refund") : "") + ")",
                     вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
    }

    @ViewBuilder
    private var выполненоЗаказчику: some View {
        ТаймерСделки(сделка: сделка)
        ЗаметкаСделки(Text(т("dl_work_done_mark")).bold() + Text(" " + т("dl_check_result")), вид: .хорошо,
                      символ: "checkmark.circle")
        КнопкаСделки(т("dl_ok_work_short"), вид: .главная, символ: "checkmark.circle", наСайт: ДеньгиКнопок.наСайте) {
            действие(.деньги(.принять))
        }
        КнопкаСделки(т("dl_wrong_short"), вид: .тихая, символ: "exclamationmark.triangle") { действие(.спор) }
    }

    private var выполненоИсполнителю: some View {
        let деньги = естьАванс ? т("dl_rest") + " " + остаток : т("dl_payment_word")
        let текст = [т("dl_you_marked_done"), String(сделка.часовНаПроверку), т("h_short"), "—", деньги, т("dl_auto_to_you")]
            .joined(separator: " ")
        return ЗаметкаСделки(Text(текст), вид: .хорошо, символ: "checkmark.circle")
    }
}

// MARK: - Спор в карточке

struct БлокСпора: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    @State private var выбор: PhotosPickerItem? = nil
    @State private var имяФото = ""

    init(сделка: Сделка, модель: КарточкаСделкиМодель, действие: @escaping (НажатиеСделки) -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            строка("exclamationmark.circle", Text(т("dl_dispute_reason")).bold()
                   + Text(" " + (сделка.причинаСпора.isEmpty ? "—" : сделка.причинаСпора)).italic())
            строка("clock", Text(т("dl_dsp_wait")))
            if !сделка.продавец && сделка.аренда {
                строка("lock", Text(т("dl_rent_disp_wait")))
            } else {
                раздел(т("dl_dsp_self"))
                if сделка.продавец {
                    КнопкаСделки(т("dl_dsp_seller_ok"), вид: .опасная, символ: "arrow.uturn.backward",
                                 наСайт: ДеньгиКнопок.наСайте) {
                        действие(.деньги(.вернутьПокупателю))
                    }
                } else {
                    КнопкаСделки(т("dl_dsp_buyer_ok"), вид: .главная, символ: "checkmark.circle",
                                 наСайт: ДеньгиКнопок.наСайте) {
                        действие(.деньги(.договорились))
                    }
                }
            }
            раздел(т("dl_upload_evidence"))
            строка("info.circle", Text(т("dl_dsp_ev_hint")).italic())
            TextField(т("dl_evidence_ph"), text: $модель.доказательство, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 15))
                .padding(10)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
            HStack(spacing: 8) {
                PhotosPicker(selection: $выбор, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperclip")
                            .accessibilityHidden(true)
                        Text(модель.фотоДоказательства == nil ? т("dl_ev_pick") : (имяФото.isEmpty ? т("ev_picked") : имяФото))
                            .lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(модель.фотоДоказательства == nil ? Theme.текстВторой : КраскаСделокКабинета.хорошоТекст)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                Button {
                    модель.отправитьДоказательство()
                } label: {
                    Text(т("dl_dsp_send"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 42)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(модель.занято)
            }
        }
        .onChange(of: выбор) { _, новый in
            загрузитьФото(новый)
        }
    }

    private func загрузитьФото(_ элемент: PhotosPickerItem?) {
        guard let элемент else {
            модель.фотоДоказательства = nil
            return
        }
        Task { @MainActor in
            let данные = try? await элемент.loadTransferable(type: Data.self)
            модель.фотоДоказательства = данные
            имяФото = данные == nil ? "" : т("ev_picked")
        }
    }

    private func строка(_ символ: String, _ текст: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: символ)
                .font(.system(size: 14))
                .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                .accessibilityHidden(true)
            текст
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func раздел(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.текстВторой)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Окно «Открыть спор» (dealDisputeOpen)

/// Причина спора: код, название, подпись (disputeReasons сайта).
struct ПричинаСпора: Identifiable, Equatable {
    let id: String
    let название: String
    let подпись: String

    /// Покупатель — шесть причин; продавец аренды — три и «Другое»; прочий продавец — две и «Другое».
    static func список(продавец: Bool, аренда: Bool) -> [ПричинаСпора] {
        let коды: [String]
        if продавец {
            коды = аренда ? ["not_returned", "returned_damaged", "late_return", "other"] : ["return_fault", "no_contact", "other"]
        } else {
            коды = ["defect", "wrong", "notdesc", "missing", "damaged", "other"]
        }
        return коды.map { код in
            ПричинаСпора(id: код, название: СделкиText.т("dr_" + код), подпись: СделкиText.т("dr_" + код + "_s"))
        }
    }
}

struct ОкноСпора: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let закрыть: () -> Void

    @State private var причина: String
    @State private var текст = ""
    @State private var выбор: PhotosPickerItem? = nil
    @State private var фото: Data? = nil
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(сделка: Сделка, модель: КарточкаСделкиМодель, закрыть: @escaping () -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.закрыть = закрыть
        let первая = ПричинаСпора.список(продавец: сделка.продавец, аренда: сделка.аренда).first?.id ?? "other"
        _причина = State(initialValue: первая)
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(т("dsp_s"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(ПричинаСпора.список(продавец: сделка.продавец, аренда: сделка.аренда)) { п in
                        строкаПричины(п)
                    }
                    TextField(т("dsp_note_ph"), text: $текст, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.system(size: 15))
                        .padding(10)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1.5)
                        }
                    PhotosPicker(selection: $выбор, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "camera")
                                .accessibilityHidden(true)
                            Text(фото == nil ? т("dsp_photo") : т("ev_picked"))
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(фото == nil ? Theme.акцент : КраскаСделокКабинета.хорошоТекст)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    ПодписьСделки(т("dsp_hint"))
                    if let ошибка {
                        Text(ошибка)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 10) {
                        КнопкаСделки(т("dsp_cancel"), вид: .вторая) { закрыть() }
                        КнопкаСделки(идёт ? т("dsp_going") : т("dsp_go"), вид: .опасная, доступна: !идёт) { отправить() }
                    }
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: т("dsp_t")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("dsp_cancel")) { закрыть() }
                }
            }
        }
        .onChange(of: выбор) { _, новый in
            guard let новый else {
                фото = nil
                return
            }
            Task { @MainActor in
                фото = try? await новый.loadTransferable(type: Data.self)
            }
        }
        .interactiveDismissDisabled(идёт)
    }

    private func строкаПричины(_ п: ПричинаСпора) -> some View {
        let выбрана = причина == п.id
        return Button {
            причина = п.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: выбрана ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(выбрана ? КраскаСделокКабинета.плохоТекст : Theme.текстВторой)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(п.название)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(п.подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(выбрана ? КраскаСделокКабинета.плохоФон : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    /// dspSend: ошибка — в этом же окне (#dsp-err), успех — окно закрывается, в карточке плашка «Спор открыт…».
    private func отправить() {
        ошибка = nil
        идёт = true
        модель.открытьСпор(код: причина, текст: текст, фото: фото) { итог in
            идёт = false
            guard let итог else {
                закрыть()
                return
            }
            if !итог.isEmpty { ошибка = итог }
        }
    }
}

// MARK: - Редактор оценки (dealReviewEdit)

struct РедакторОценкиСделки: View {
    /// Продавец оценивает покупателя — другие подписи и подсказки.
    let оцениваюПокупателя: Bool
    /// goods / service / rent — какие подсказки (_dealFbKind).
    let вид: String
    @Binding var звёзды: Int
    @Binding var отзыв: String
    let занято: Bool
    let сохранить: () -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        КоробкаОценкиСделки(заголовок: т(оцениваюПокупателя ? "dl_rate_buyer_t" : "dl_your_rating")) {
            ЗвёздыСделки(звёзд: звёзды, размер: 30, выбрать: { звёзды = $0 })
            if звёзды >= 1 { реакция }
            if звёзды >= 1 { подсказки }
            TextField(т(оцениваюПокупателя ? "dl_review_ph_b" : "dl_review_ph"), text: $отзыв, axis: .vertical)
                .lineLimit(3...6)
                .font(.system(size: 15))
                .padding(10)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
            КнопкаСделки(т("dl_review_save"), вид: .главная, доступна: !занято) { сохранить() }
        }
    }

    /// DEAL_REACT: лицо и два слова под числом звёзд.
    private var реакция: some View {
        let вид: ВидЗаметкиСделки = звёзды >= 4 ? .хорошо : (звёзды == 3 ? .предупреждение : .плохо)
        return ЗаметкаСделки(Text(т("dl_react_" + String(звёзды) + "_t")).bold()
                             + Text("\n" + т("dl_react_" + String(звёзды) + "_s")).font(.system(size: 13)),
                             вид: вид, символ: звёзды >= 4 ? "face.smiling" : "face.dashed")
    }

    /// dealFbChips: четыре подсказки «Что понравилось?» (4–5 звёзд) или «Что случилось?»; нажатие дописывает или убирает
    /// фразу в отзыве (dealFbChip).
    private var подсказки: some View {
        let хорошо = звёзды >= 4
        let кто = оцениваюПокупателя ? "buyer" : вид
        let фразы: [String] = (1...4).map { т("dl_fb_" + кто + "_" + (хорошо ? "pos" : "neg") + "_" + String($0)) }
        let выбраны = Set(ОтзывСделки.части(отзыв))
        return VStack(alignment: .leading, spacing: 6) {
            Text(т(хорошо ? "dl_fb_ask_pos" : "dl_fb_ask_neg"))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            /* .dm-chips: flex-wrap, зазор 8. */
            ПотокЧипов(зазор: 8) {
                ForEach(фразы, id: \.self) { фраза in
                    фишка(фраза, вкл: выбраны.contains(фраза))
                }
            }
        }
    }

    /// .dm-chip: пилюля в рамке; выбранная — градиент --g2 → #0f7a44 с белым текстом.
    private func фишка(_ фраза: String, вкл: Bool) -> some View {
        let фон: AnyShapeStyle = вкл
            ? AnyShapeStyle(LinearGradient(colors: [Theme.зелёный2, Color(uiColor: Theme.hex(0x0F7A44))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
            : AnyShapeStyle(Theme.поверхность)
        return Button {
            отзыв = ОтзывСделки.переключить(фраза, в: отзыв)
        } label: {
            Text(фраза)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(вкл ? Color.white : Theme.текст)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(фон, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(вкл ? Color.clear : Theme.линия, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }
}

/// Фразы подсказок в отзыве: «А. Б.» — как dealFbChip сайта.
enum ОтзывСделки {
    static func части(_ отзыв: String) -> [String] {
        отзыв.components(separatedBy: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func переключить(_ фраза: String, в отзыв: String) -> String {
        var список = части(отзыв)
        if let i = список.firstIndex(of: фраза) {
            список.remove(at: i)
        } else {
            список.append(фраза)
        }
        return список.isEmpty ? "" : список.joined(separator: ". ") + "."
    }
}
