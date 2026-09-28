import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ДЕЙСТВИЯ ПО РОЛИ И СТАТУСУ (этап 43; renderDeal сайта, матрица карты §4.5).

 Тексты и порядок — как у переменной w в renderDeal: товар (и задаток, и аренда) → спор → услуга поверх → оценка после
 сделки → гарантийный талон → возврат товара вместо всего. Своё приложение делает то, что без денег: спор, доказательства,
 «Подтвердить условия» / «Отклонить заявку» услуги, оценку после сделки, чек, просьбу подписать талон.
 🔴 ДЕНЬГИ (этап 44, Config.деньгиСделок = false) — «Заморозить», «Оплатить», «Отменить…», «Товар у меня — принять»,
 «Всё в порядке…», «Работа принята», «Работа выполнена», «Договорились…», «Согласен вернуть деньги…», «Подписать» (eGov):
 кнопка с теми же словами открывает страницу сделки сайта. Звёзды при «Всё в порядке» — часть того же денежного
 подтверждения (buyer_confirm {rating, review}), поэтому их ставят там же, на странице сайта.
 */
struct ДействияСделки: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    @State private var правкаОценки = false
    @State private var звёзды = 0
    @State private var отзыв = ""

    init(сделка: Сделка, модель: КарточкаСделкиМодель, действие: @escaping (НажатиеСделки) -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if сделка.идётВозврат {
                ЗаметкаСделки(ТекстСделки.сЖирным(т("ret_note")), вид: .предупреждение, символ: "arrow.uturn.backward")
            } else {
                основные
                if сделка.статус == "confirmed" { блокОценки }
                талонПодписать
            }
        }
    }

    // MARK: - Основные действия (w)

    @ViewBuilder
    private var основные: some View {
        if сделка.услуга && ["proposed", "accepted", "held", "delivered"].contains(сделка.статус) {
            ДействияУслуги(сделка: сделка, модель: модель, действие: действие)
        } else {
            switch сделка.статус {
            case "pending": ожидаетОплаты
            case "held": деньгиЗаморожены
            case "shipped": отправлено
            case "delivered": получено
            case "confirmed", "resolved", "expired": завершена
            case "disputed": БлокСпора(сделка: сделка, модель: модель, действие: действие)
            default: EmptyView()
            }
        }
    }

    private var сумма: String { СделкиФормат.тенге(сделка.сумма) }
    private var кОплате: String { СделкиФормат.тенге(сделка.кОплате) }

    @ViewBuilder
    private var ожидаетОплаты: some View {
        if сделка.продавец {
            ЗаметкаСделки(Text(т("dl_await_payment")) + Text("\n") + Text(т("dl_await_payment_note")).font(.system(size: 13)),
                          вид: .предупреждение, символ: "hourglass", поЦентру: true)
            КнопкаСделки(т("dl_cancel_deal"), вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
        } else {
            КнопкаСделки(т("dl_freeze_btn"), вид: .главная, символ: "lock", сумма: кОплате, наСайт: ДеньгиКнопок.наСайте) {
                действие(.деньги(.оплатить))
            }
            VStack(spacing: 2) {
                Text(т("dl_freeze_note"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                Text(т("dl_price") + " " + сумма + " + " + т("dl_service_fee"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            КнопкаСделки(т("dl_cancel_deal"), вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
        }
    }

    /// held: продавцу — «Деньги покупателя (X ₸) заморожены платформой»; покупателю — где деньги и чем подтвердят передачу.
    @ViewBuilder
    private var деньгиЗаморожены: some View {
        if сделка.продавец {
            let хвост = сделка.задаток ? т("dl_held_seller_deposit") : т("dl_held_seller_c")
            let деньги = т("dl_buyer_money_a") + " (" + сумма + ") " + т("dl_buyer_money_b")
            ЗаметкаСделки(Text(деньги).bold() + Text("\n" + хвост), вид: .хорошо, символ: "lock")
            пояснениеПередачи
            кнопкаОтмены(т("dl_cancel_refund100"))
        } else {
            Text(т(сделка.передача.isEmpty ? (сделка.курьерПоГороду ? "dl_held_b2" : "dl_held_b3") : "dl_held_b1"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            if !сделка.передача.isEmpty {
                КнопкаСделки(т("dl_got_btn"), вид: .главная, символ: "checkmark.circle", наСайт: ДеньгиКнопок.наСайте) {
                    действие(.деньги(.принять))
                }
            }
            кнопкаОтмены(т("dl_cancel_deal_refund"))
        }
    }

    /// x ? T : (delivery_local ? S : "") продавца: коды встречи или посылки, либо курьер по городу.
    @ViewBuilder
    private var пояснениеПередачи: some View {
        if !сделка.передача.isEmpty {
            ЗаметкаСделки(Text(т(сделка.передача == "meet" ? "ho_meet" : "ho_parcel")), вид: .инфо, символ: "info.circle")
        } else if сделка.курьерПоГороду {
            ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_courier_note")), вид: .инфо, символ: "info.circle")
        }
    }

    /// k() сайта: отмена — деньги (страница сайта); пока посылка в пути — неактивна и пояснение «Посылка уже в пути…».
    @ViewBuilder
    private func кнопкаОтмены(_ надпись: String) -> some View {
        if сделка.отменаЗаперта {
            КнопкаСделки(надпись, вид: .вторая, доступна: false) {}
            ЗаметкаСделки(Text(т("dl_cancel_locked")), вид: .инфо, символ: "info.circle")
        } else {
            КнопкаСделки(надпись, вид: .вторая, наСайт: ДеньгиКнопок.наСайте) { действие(.деньги(.отменить)) }
        }
    }

    @ViewBuilder
    private var отправлено: some View {
        if сделка.продавец {
            let остаток = сделка.наПроверкуСек
            let срок = [т("dl_auto_pay_in"), днейЧасов(остаток), "—", т("dl_auto_pay_you")].joined(separator: " ")
            let хвост: Text = остаток > 0 ? Text("\n" + срок).font(.system(size: 13)) : Text("")
            ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_shipped_seller")) + хвост, вид: .предупреждение,
                          символ: "square.and.arrow.up")
        } else {
            let отметка = сделка.задаток ? т("dl_seller_ready_deposit") : т("dl_seller_shipped_mark")
            let осталось = сделка.наПроверкуСек > 0
                ? " " + т("dl_left_word") + " " + СделкиФормат.осталось(сделка.наПроверкуСек) : ""
            let деньги = " " + т("dl_your_money") + " (" + кОплате + ") " + т("dl_still_frozen") + "\n"
            let подсказка = т("dl_receive_hint2") + осталось + "\n"
            ЗаметкаСделки(Text(отметка).bold() + Text(деньги) + Text(подсказка) + Text(т("dl_not_got")).bold(),
                          вид: .предупреждение, символ: "square.and.arrow.up")
            if сделка.курьерПоГороду {
                ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_courier_note")), вид: .инфо, символ: "info.circle")
            }
            КнопкаСделки(т("dl_ok_btn"), вид: .главная, символ: "checkmark.circle", наСайт: ДеньгиКнопок.наСайте) {
                действие(.деньги(.принять))
            }
            КнопкаСделки(т("dl_bad_btn"), вид: .тихая, символ: "exclamationmark.triangle") { действие(.спор) }
        }
    }

    /// «Xд Yч» строки продавца в shipped: дни — только если есть.
    private func днейЧасов(_ секунд: Double) -> String {
        let всего = Int(секунд)
        let дни = всего / 86400
        let часы = (всего % 86400) / 3600
        return (дни > 0 ? String(дни) + " " + т("dl_d_short") + " " : "") + String(часы) + т("h_short")
    }

    @ViewBuilder
    private var получено: some View {
        if сделка.продавец {
            let когда = сделка.осталосьСек > 0
                ? " " + т("dl_money_in") + " " + СделкиФормат.часыМинуты(сделка.осталосьСек) + "." : ""
            ЗаметкаСделки(Text(т("dl_buyer_got") + когда + " " + т("dl_unless_dispute")), вид: .хорошо,
                          символ: "checkmark.circle")
        } else {
            ТаймерСделки(сделка: сделка)
            КнопкаСделки(т("dl_ok_short"), вид: .главная, символ: "checkmark.circle", наСайт: ДеньгиКнопок.наСайте) {
                действие(.деньги(.принять))
            }
            КнопкаСделки(т("dl_wrong_short"), вид: .тихая, символ: "exclamationmark.triangle") { действие(.спор) }
        }
    }

    /// confirmed / resolved / expired: «Сделка завершена», оценка покупателя (если это не его собственная — её покажет блок
    /// оценки ниже) и чек.
    @ViewBuilder
    private var завершена: some View {
        let своя = сделка.статус == "confirmed" && !сделка.продавец && сделка.оценкаПокупателя > 0
        /* .dmn.ok.ctr: у resolved и expired — весы, у confirmed — галочка в круге. */
        VStack(spacing: 4) {
            Image(systemName: сделка.статус == "confirmed" ? "checkmark.circle" : "scale.3d")
                .font(.system(size: 22))
                .accessibilityHidden(true)
            Text(т("dl_deal_done"))
                .font(.system(size: 15, weight: .bold))
            if сделка.оценкаПокупателя > 0 && !своя {
                ЗвёздыСделки(звёзд: сделка.оценкаПокупателя, размер: 14)
            }
            if !сделка.отзывПокупателя.isEmpty && !своя {
                Text("«" + сделка.отзывПокупателя + "»")
                    .font(.system(size: 13).italic())
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(КраскаСделокКабинета.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(КраскаСделокКабинета.хорошоКромка, lineWidth: 1.5)
        }
        КнопкаСделки(т("dl_download_receipt"), вид: .главная, символ: "doc.text") { действие(.чек) }
    }

    // MARK: - Оценка после сделки (dealReviewBoxHTML)

    /// Покупатель оценивает продавца, продавец — покупателя; правка — пока открыто окно (review_edit_left*).
    @ViewBuilder
    private var блокОценки: some View {
        let оцениваюПокупателя = сделка.продавец
        let моя = оцениваюПокупателя ? сделка.оценкаПродавца : сделка.оценкаПокупателя
        let окно = оцениваюПокупателя ? сделка.правкаОценкиПокупателя : сделка.правкаОценки
        let мойОтзыв = оцениваюПокупателя ? сделка.отзывПродавца : сделка.отзывПокупателя
        if правкаОценки {
            РедакторОценкиСделки(оцениваюПокупателя: оцениваюПокупателя, вид: сделка.услуга ? "service" : (сделка.аренда ? "rent" : "goods"),
                                 звёзды: $звёзды, отзыв: $отзыв, занято: модель.занято) {
                модель.сохранитьОценку(оцениваем: оцениваюПокупателя, звёзд: звёзды, отзыв: отзыв) { готово in
                    if готово { правкаОценки = false }
                }
            }
        } else if моя == 0 {
            if окно > 0 {
                КоробкаОценкиСделки(заголовок: т(оцениваюПокупателя ? "dl_rate_buyer" : "dl_rate_seller")) {
                    Text(т(оцениваюПокупателя ? "dl_rate_late_b" : "dl_rate_late"))
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    КнопкаПравкиОценки(надпись: т("dl_rate_now"), символ: "star") {
                        звёзды = 0
                        отзыв = ""
                        правкаОценки = true
                    }
                }
            }
        } else {
            КоробкаОценкиСделки(заголовок: т(оцениваюПокупателя ? "dl_rate_seller_b" : "dl_your_rating")) {
                ЗвёздыСделки(звёзд: моя, размер: 22)
                if !мойОтзыв.isEmpty {
                    Text(мойОтзыв)
                        .font(.system(size: 13))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if окно > 0 {
                    КнопкаПравкиОценки(надпись: т("dl_review_change"), символ: "pencil") {
                        звёзды = моя
                        отзыв = мойОтзыв
                        правкаОценки = true
                    }
                }
            }
        }
    }

    // MARK: - Гарантийный талон продавцу (dealWarrantyCta)

    /// Подпись — warranty_sign; нужен eGov — своё окно ОкноEGov (otp_step_*), денег нет.
    @ViewBuilder
    private var талонПодписать: some View {
        if сделка.гарантияДней > 0 && сделка.режим == "goods" && сделка.продавец && !сделка.талонПодписан
            && ["held", "shipped", "delivered", "confirmed"].contains(сделка.статус) {
            БлокСделки {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: т("wc_cta_t"), СрокГарантии.текст(сделка.гарантияДней)))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                        ПодписьСделки(т("wc_cta_s"))
                    }
                }
                КнопкаСделки(т("wc_sign"), вид: .главная, доступна: !модель.занято) { действие(.подписатьТалон) }
            }
        }
    }
}

// MARK: - Коробка оценки (.dm-revbox, .dm-edit-btn)

/// .dm-revbox: серая подложка, рамка 1.5, радиус 18, поля 14; заголовок 11/800 серый с разрядкой.
struct КоробкаОценкиСделки<Содержимое: View>: View {
    let заголовок: String
    let содержимое: Содержимое

    init(заголовок: String, @ViewBuilder _ содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(заголовок)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.55)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            содержимое
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// .dm-edit-btn: во всю ширину, белая, зелёная рамка и текст.
struct КнопкаПравкиОценки: View {
    let надпись: String
    let символ: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: символ)
                    .font(.system(size: 15))
                    .accessibilityHidden(true)
                Text(надпись)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаСделокКабинета.хорошоКромка, lineWidth: 1.5)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

// MARK: - Таймер авто-подтверждения (g в renderDeal)

struct ТаймерСделки: View {
    let сделка: Сделка

    var body: some View {
        if сделка.статус == "delivered" && сделка.осталосьСек > 0 && !сделка.продавец {
            ЗаметкаСделки(Text(СделкиText.т("deal_autoconfirm") + " " + СделкиФормат.часыМинуты(сделка.осталосьСек)).bold()
                          + Text("\n" + СделкиText.т("dl_timer_note")).font(.system(size: 13)),
                          вид: .предупреждение, символ: "alarm")
        }
    }
}

// MARK: - Срок гарантии (warrTerm)

enum СрокГарантии {
    /**
     warrTerm сайта: 365 дней — «12 месяцев», кратно 30 — месяцы, иначе дни; форма слова — по правилам языка (ru/kk —
     1 / 2–4 / 5, en — 1 / много, ar — 1 / 2–10 / 11+). Слова — wr_d1…wr_m5 словаря.
     */
    static func текст(_ дней: Int) -> String {
        let месяцев = дней == 365 ? 12 : (дней >= 30 && дней % 30 == 0 ? дней / 30 : 0)
        let n = месяцев > 0 ? месяцев : дней
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let форма: String
        switch язык {
        case "en":
            форма = n == 1 ? "1" : "2"
        case "ar":
            форма = n == 1 ? "1" : (n >= 2 && n <= 10 ? "2" : "5")
        default:
            let r = n % 10
            let i = n % 100
            форма = (r == 1 && i != 11) ? "1" : ((r >= 2 && r <= 4 && (i < 10 || i >= 20)) ? "2" : "5")
        }
        return String(n) + " " + СделкиText.т((месяцев > 0 ? "wr_m" : "wr_d") + форма)
    }
}
