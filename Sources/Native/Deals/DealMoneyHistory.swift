import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — «ДЕНЬГИ И ДОКУМЕНТЫ», «ИСТОРИЯ СДЕЛКИ», ЧЕК (этап 43, владелец 26.09.2026).

 Только показ, как свёрнутые блоки dmFold сайта и окно showReceipt. Документы (договор и акт аренды, акт работ,
 гарантийный талон) — ссылки /escrow.php?action=…&id=: их ловит ПереходыКабинета и показывает своим окном PDF с
 «Поделиться» и «Печать» (CabinetPlus/DocumentViewer.swift); «Попросить продавца подписать» —
 warranty_ask, своё. Чек рисуется из той же сделки, «Распечатать» — системная печать (printReceipt сайта открывает окно
 печати браузера).
 */
struct ДеньгиИДокументы: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let открыть: (URL) -> Void
    let действие: (НажатиеСделки) -> Void

    @State private var открыт = false
    /// Рубильник баллов админки: выключены — «, баллы тоже возвращены» не пишем.
    @ObservedObject private var сессия = СессияПриложения.shared

    init(сделка: Сделка, модель: КарточкаСделкиМодель, открыть: @escaping (URL) -> Void,
         действие: @escaping (НажатиеСделки) -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.открыть = открыть
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    /// MK_SHOWN_RATE страницы кабинета (0.019, карта §4.1): доля «Комиссии гаранта (1,9%)» в сборе, остальное — «Сервисный
    /// сбор». Отдельного API у значения нет; в словаре подпись та же — «1,9%».
    private static let показаннаяДоля = 0.019

    var body: some View {
        СвёрткаСделки(заголовок: т("fold_money"), символ: "creditcard", открыт: $открыт) {
            VStack(alignment: .leading, spacing: 10) {
                if !сделка.товар.isEmpty {
                    кнопкаОбъявления
                }
                суммы
                документы
                талон
                if сделка.статус == "cancelled" {
                    let кому = сделка.продавец ? т("dl_returned_to_buyer") : т("dl_returned_to_you")
                    let баллы = сессия.баллыВключены && сделка.баллыСписано > 0 && !сделка.продавец ? т("dl_points_back") : ""
                    ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_deal_cancelled_money") + " " + кому + баллы + "."), вид: .инфо,
                                  поЦентру: true)
                }
            }
        }
    }

    /// a.dmb.lnk «Посмотреть объявление»: во всю ширину, --tint-ok и --on-ok, рамка 1.5 --line, радиус 12, 14/700.
    private var кнопкаОбъявления: some View {
        Button {
            if let адрес = Config.url("/marketplace.php?item=" + СделкиAPI.вАдрес(сделка.товар)) { открыть(адрес) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 15))
                    .accessibilityHidden(true)
                Text(т("dl_view_listing"))
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(КраскаСделокКабинета.хорошоФон,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }

    // MARK: Суммы

    private var сумма: Int { сделка.сумма }
    private var остаток: Int { max(0, сделка.сумма - сделка.аванс) }
    private var естьАванс: Bool { сделка.авансПроцент > 0 }

    private var суммы: some View {
        VStack(alignment: .leading, spacing: 6) {
            строка(первая, СделкиФормат.тенге(сумма))
            if (сделка.задаток || сделка.аренда) && сделка.полнаяЦена > 0 {
                строка(т(сделка.задаток ? "dl_full_price" : "dl_item_value"), СделкиФормат.тенге(сделка.полнаяЦена), серое: true)
            }
            if сделка.продавец { продавцу } else { покупателю }
        }
        /* Финансовый блок renderDeal: --surf2, рамка 1.5 --line, радиус 12, поля 12/14. */
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    /// Черта над итогом: border-top 1px --line, отступ сверху 4 (с зазором строк — 10).
    private var черта: some View {
        Rectangle()
            .fill(Theme.линия)
            .frame(height: 1)
            .padding(.top, 4)
            .accessibilityHidden(true)
    }

    private var первая: String {
        if сделка.задаток { return т("dl_deposit_reserve") }
        if сделка.аренда { return т("dstep_pledge") }
        if сделка.услуга { return т("dl_service_amount") }
        return т("dl_item_price")
    }

    /// f() в renderDeal: сбор делится на «Комиссию гаранта (1,9%)» и «Сервисный сбор».
    @ViewBuilder
    private func сбор(_ всего: Int, подпись: String, знак: String) -> some View {
        let доля = min(всего, Int((Double(сумма) * Self.показаннаяДоля).rounded()))
        let сервис = max(0, всего - доля)
        if сервис > 0 {
            строка(подпись, знак + СделкиФормат.тенге(доля))
            строка(т("co_service"), знак + СделкиФормат.тенге(сервис))
        } else {
            строка(подпись, знак + СделкиФормат.тенге(всего))
        }
    }

    @ViewBuilder
    private var покупателю: some View {
        сбор(сделка.сборПокупателя, подпись: т("dl_service_charge"), знак: "+")
        if сделка.доставкаЗаСчётПродавца > 0 {
            строка(т("co_ship_row"), т("co_ship_free_b"))
        }
        if сделка.доставка > 0 {
            let подпись = сделка.черезПеревозчика ? String(format: т("co_ship_row_car"), сделка.перевозчик.имя) : т("co_ship_row")
            строка(подпись, "+" + СделкиФормат.тенге(сделка.доставка))
        }
        черта
        строка(т("promo_total"), СделкиФормат.тенге(сделка.кОплате), жирная: true, краска: КраскаСделокКабинета.синий)
        if сделка.услуга && естьАванс {
            строка(String(format: т("dl_adv_to_exec"), сделка.авансПроцент), СделкиФормат.тенге(сделка.аванс), мелкая: true)
            строка(т("dl_rest_after_accept"), СделкиФормат.тенге(остаток), мелкая: true)
        }
        if ["held", "disputed"].contains(сделка.статус) {
            let вернётся = сделка.услуга ? остаток : сделка.кОплате
            let пометка = сделка.услуга && естьАванс ? т("dl_rest_adv_kept") : т("dl_full_no_fee")
            строка(т("dl_on_cancel_back"), СделкиФормат.тенге(вернётся) + " " + пометка, мелкая: true,
                   краска: КраскаСделокКабинета.хорошоТекст)
        } else if !сделка.услуга && ["shipped", "delivered"].contains(сделка.статус) {
            строка(т("dl_cancel_after_ship"), т("dl_cancel_fee") + " " + т("dl_better_dispute"), мелкая: true, серое: true)
        }
    }

    @ViewBuilder
    private var продавцу: some View {
        сбор(сделка.сборПродавца, подпись: т("dl_platform_comm"), знак: "−")
        черта
        if сделка.статус == "cancelled" {
            строка(т("dl_seller_payout"), "0 ₸", жирная: true, серое: true)
        } else {
            строка(т("dl_you_get"), СделкиФормат.тенге(сделка.продавецПолучит), жирная: true, краска: КраскаСделокКабинета.хорошоТекст)
        }
        if сделка.услуга && естьАванс {
            строка(т("dl_of_which_adv"), СделкиФормат.тенге(сделка.аванс), мелкая: true)
            строка(т("dl_rest_after_accept_l"), СделкиФормат.тенге(max(0, сделка.продавецПолучит - сделка.аванс)), мелкая: true)
        }
    }

    private func строка(_ подпись: String, _ значение: String, жирная: Bool = false, мелкая: Bool = false,
                        серое: Bool = false, краска: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(подпись)
                .font(.system(size: мелкая ? 12 : 13, weight: жирная ? .bold : .regular))
                .foregroundStyle(жирная ? Theme.текст : Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: мелкая ? 12 : 13, weight: .bold))
                .foregroundStyle(краска ?? (серое ? Theme.текстВторой : Theme.текст))
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Документы

    @ViewBuilder
    private var документы: some View {
        let номер = СделкиAPI.вАдрес(сделка.id)
        if сделка.аренда {
            ссылка(т("dl_rent_contract"), символ: "doc.text", путь: "/escrow.php?action=rental_contract&id=" + номер,
                   пометка: т("dl_autofilled"))
            ссылка(т("dl_handover_act"), символ: "doc.text", путь: "/escrow.php?action=rental_act&id=" + номер,
                   пометка: т("dl_auto_realty"))
        }
        if сделка.услуга && ["delivered", "sold"].contains(сделка.статус) {
            ссылка(т("dl_work_act"), символ: "doc.text", путь: "/escrow.php?action=service_act&id=" + номер,
                   пометка: т("dl_autofilled"))
        }
    }

    /// dealWarrantyDocRow: талон после оплаты (или уже подписанный); покупателю — «Попросить продавца подписать».
    @ViewBuilder
    private var талон: some View {
        let дней = сделка.режим == "goods" ? сделка.гарантияДней : 0
        let подписан = сделка.талонПодписан
        let оплачена = ["held", "shipped", "delivered", "confirmed"].contains(сделка.статус)
        if (дней > 0 || подписан) && (подписан || оплачена) {
            ссылка(т("wc_doc"), символ: "checkmark.shield", путь: "/escrow.php?action=warranty_card&id=" + СделкиAPI.вАдрес(сделка.id),
                   пометка: т(подписан ? "wc_doc_signed" : "wc_doc_wait"))
            if !подписан && !сделка.продавец {
                КнопкаСделки(т("wc_ask"), вид: .вторая, символ: "bell", доступна: !модель.занято) { действие(.попроситьТалон) }
            }
        }
    }

    private func ссылка(_ текст: String, символ: String, путь: String, пометка: String = "") -> some View {
        Button {
            if let адрес = Config.url(путь) { открыть(адрес) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: символ)
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                if !пометка.isEmpty {
                    Text(пометка)
                        .font(.system(size: 12))
                        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                }
                Spacer(minLength: 4)
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - История сделки

struct ИсторияСделки: View {
    let сделка: Сделка

    @State private var открыт = false

    init(сделка: Сделка) {
        self.сделка = сделка
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    /// DEAL_TL_KEY сайта: подпись по статусу, иначе заметка сервера.
    private static let подписи: [String: String] = [
        "pending": "dl_tl_pending", "proposed": "dl_tl_proposed", "accepted": "dl_tl_accepted", "held": "dl_tl_held",
        "shipped": "dl_tl_shipped", "delivered": "dl_tl_delivered", "confirmed": "dl_tl_confirmed",
        "cancelled": "dl_tl_cancelled", "disputed": "dl_tl_disputed"
    ]

    var body: some View {
        СвёрткаСделки(заголовок: т("fold_history"), символ: "clock", открыт: $открыт) {
            VStack(alignment: .leading, spacing: 6) {
                Text(т("dl_history").uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.bottom, 2)
                ForEach(сделка.история) { событие in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(КраскаСделокКабинета.синий)
                            .frame(width: 8, height: 8)
                            .padding(.top, 4)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(подпись(событие))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.текст)
                            Text(СделкиФормат.сВременем(событие.когда))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if !сделка.доказательства.isEmpty {
                    доказательства
                        .padding(.top, 8)
                }
            }
        }
    }

    private func подпись(_ с: СобытиеСделки) -> String {
        if let ключ = Self.подписи[с.статус] { return т(ключ) }
        if !с.заметка.isEmpty { return с.заметка }
        return с.статус
    }

    private var доказательства: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("dl_evidence_word").uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(Theme.текстВторой)
                .padding(.bottom, 2)
            ForEach(сделка.доказательства) { д in
                VStack(alignment: .leading, spacing: 6) {
                    (Text(т(д.покупатель ? "dl_role_buyer" : "dl_role_seller") + ": ").bold() + Text(д.заметка))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    /* data/evidence/<img> — относительный путь страницы кабинета: /kz/<язык>/data/evidence/. */
                    if !д.картинка.isEmpty {
                        КартинкаЛенты(Config.страницаСайта("data/evidence/" + д.картинка), пунктов: 300, заполнить: false) {
                            Theme.поверхность2
                        }
                        .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        .accessibilityLabel(т("a11y_evidence"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
    }
}

// MARK: - Чек (showReceipt)

struct ЧекСделки: View {
    let сделка: Сделка
    let закрыть: () -> Void

    /// Рубильник баллов админки (СессияПриложения): выключены — строк «Скидка баллами» и «Начислено баллов» в чеке нет.
    /// Не @ObservedObject: чек — лист на один показ, а приватное хранимое свойство закрыло бы ЧекСделки(сделка:закрыть:).
    private var баллыВключены: Bool { СессияПриложения.shared.баллыВключены }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var завершена: Bool { ["confirmed", "resolved", "expired"].contains(сделка.статус) }

    /// Статус чека: свои слова окна сайта; незнакомый — как есть.
    private var статус: String {
        let ключи: [String: String] = ["confirmed": "rc_st_confirmed", "resolved": "rc_st_resolved",
                                        "expired": "rc_st_expired", "held": "rc_st_held", "delivered": "rc_st_delivered",
                                        "disputed": "rc_st_disputed", "cancelled": "rc_st_cancelled",
                                        "pending": "rc_st_pending"]
        if let ключ = ключи[сделка.статус] { return т(ключ) }
        return сделка.статус
    }

    private var сбор: Int { сделка.продавец ? сделка.сборПродавца : сделка.сборПокупателя }
    private var итого: Int { сделка.продавец ? сделка.продавецПолучит : (сделка.оплачено > 0 ? сделка.оплачено : сделка.кОплате) }
    private var баллов: Int { сделка.продавец ? сделка.баллыПродавцу : сделка.баллыПокупателю }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    шапка
                    VStack(alignment: .leading, spacing: 14) {
                        Text(статус)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(завершена ? КраскаСделокКабинета.хорошоТекст : КраскаСделокКабинета.предупреждениеТекст)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(завершена ? КраскаСделокКабинета.хорошоФон : КраскаСделокКабинета.предупреждениеФон, in: Capsule())
                            .frame(maxWidth: .infinity)
                        товар
                        деньги
                        детали
                        if !сделка.отзывПокупателя.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(т("rc_review"))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Theme.текстВторой)
                                Text("«" + сделка.отзывПокупателя + "»")
                                    .font(.system(size: 14).italic())
                                    .foregroundStyle(Theme.текст)
                            }
                        }
                        HStack(spacing: 10) {
                            КнопкаСделки(т("rc_print"), вид: .главная, символ: "printer") { напечатать() }
                            КнопкаСделки(т("close"), вид: .вторая) { закрыть() }
                        }
                    }
                    .padding(18)
                }
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: т("rc_t")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
    }

    private var шапка: some View {
        /* Шапка чека: градиент #0f7a44 → #1d9e5e в обеих темах, поля 24/20/20. */
        VStack(spacing: 4) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 32))
                .accessibilityHidden(true)
            Text(т("rc_t"))
                .font(.system(size: 19, weight: .heavy))
            Text(т("rc_s"))
                .font(.system(size: 12))
                .opacity(0.8)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x0F7A44)), Color(uiColor: Theme.hex(0x1D9E5E))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.xl, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                          topTrailingRadius: Theme.Радиус.xl, style: .continuous))
    }

    private var товар: some View {
        HStack(spacing: 12) {
            КартинкаЛенты(Config.url(сделка.фото), пунктов: 54) {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "shippingbox")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(сделка.название.isEmpty ? т("deals_item_fallback") : сделка.название)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(сделка.продавец ? String(format: т("rc_buyer"), сделка.имяПокупателя.isEmpty ? "—" : сделка.имяПокупателя)
                                     : т("rc_mine"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// Таблица денег чека: рамка 1.5 --line, радиус 12, строки 10/14 через черту 1px; итог — на --tint-ok.
    private var деньги: some View {
        VStack(spacing: 0) {
            ячейка(т("rc_price"), СделкиФормат.тенге(сделка.сумма))
            ячейка(т("rc_fee"), (сделка.продавец ? "− " : "+ ") + СделкиФормат.тенге(сбор),
                   краска: КраскаСделокКабинета.плохоТекст)
            if баллыВключены && !сделка.продавец && сделка.баллыСписано > 0 {
                ячейка(т("rc_points"), "−" + СделкиФормат.тенге(сделка.баллыСписано), краска: КраскаСделокКабинета.иИТекст,
                       подписьКраской: true)
            }
            if баллыВключены && (сделка.баллыПокупателю > 0 || сделка.баллыПродавцу > 0) {
                ячейка(т("rc_points_got"), "+" + СделкиФормат.деньги(баллов), краска: КраскаСделокКабинета.иИТекст,
                       подписьКраской: true)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(т(сделка.продавец ? "rc_got" : "rc_paid"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                Text(СделкиФормат.тенге(итого))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(сделка.продавец ? КраскаСделокКабинета.хорошоТекст : КраскаСделокКабинета.инфоТекст)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(КраскаСделокКабинета.хорошоФон)
            .accessibilityElement(children: .combine)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    /// Строка таблицы денег: 13 серым, значение 13 жирным; черта 1px снизу.
    private func ячейка(_ подпись: String, _ значение: String, краска: Color? = nil, подписьКраской: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(подпись)
                    .font(.system(size: 13))
                    .foregroundStyle(подписьКраской ? (краска ?? Theme.текстВторой) : Theme.текстВторой)
                Spacer(minLength: 8)
                Text(значение)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(краска ?? Theme.текст)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var детали: some View {
        VStack(spacing: 8) {
            строка(т("rc_no"), сделка.id)
            строка(т("rc_created"), СделкиФормат.полная(сделка.создана))
            if !сделка.завершена.isEmpty {
                строка(т("rc_done"), СделкиФормат.полная(сделка.завершена))
            }
            if сделка.оценкаПокупателя > 0 {
                HStack {
                    Text(т("rc_rating"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                    Spacer(minLength: 8)
                    ЗвёздыСделки(звёзд: сделка.оценкаПокупателя, размер: 13)
                    Text("(" + String(сделка.оценкаПокупателя) + "/5)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
    }

    private func строка(_ подпись: String, _ значение: String, жирная: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(подпись)
                .font(.system(size: 14, weight: жирная ? .bold : .regular))
                .foregroundStyle(жирная ? Theme.текст : Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Печать

    /// Тот же чек простой разметкой — системное окно печати (или «Сохранить в PDF»).
    private func напечатать() {
        func экран(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var строки: [(String, String)] = [
            (т("rc_price"), СделкиФормат.тенге(сделка.сумма)),
            (т("rc_fee"), (сделка.продавец ? "− " : "+ ") + СделкиФормат.тенге(сбор))
        ]
        if баллыВключены && !сделка.продавец && сделка.баллыСписано > 0 {
            строки.append((т("rc_points"), "−" + СделкиФормат.тенге(сделка.баллыСписано)))
        }
        строки.append((т(сделка.продавец ? "rc_got" : "rc_paid"), СделкиФормат.тенге(итого)))
        строки.append((т("rc_no"), сделка.id))
        строки.append((т("rc_created"), СделкиФормат.полная(сделка.создана)))
        if !сделка.завершена.isEmpty { строки.append((т("rc_done"), СделкиФормат.полная(сделка.завершена))) }
        if сделка.оценкаПокупателя > 0 { строки.append((т("rc_rating"), String(сделка.оценкаПокупателя) + "/5")) }
        let таблица = строки.map { "<tr><td>" + экран($0.0) + "</td><td style=\"text-align:right\"><b>" + экран($0.1) + "</b></td></tr>" }
            .joined()
        var html = "<html><head><meta charset=\"utf-8\"></head><body style=\"font-family:-apple-system,sans-serif\">"
        html += "<h2 style=\"text-align:center\">" + экран(т("rc_t")) + "</h2>"
        html += "<p style=\"text-align:center;color:#555\">" + экран(т("rc_s")) + "</p>"
        html += "<p style=\"text-align:center\"><b>" + экран(статус) + "</b></p>"
        html += "<p><b>" + экран(сделка.название.isEmpty ? т("deals_item_fallback") : сделка.название) + "</b></p>"
        html += "<table style=\"width:100%;border-collapse:collapse\">" + таблица + "</table>"
        if !сделка.отзывПокупателя.isEmpty {
            html += "<p><i>" + экран(т("rc_review")) + ": «" + экран(сделка.отзывПокупателя) + "»</i></p>"
        }
        html += "</body></html>"
        let печать = UIPrintInteractionController.shared
        let сведения = UIPrintInfo(dictionary: nil)
        сведения.jobName = т("rc_t") + " " + сделка.id
        сведения.outputType = .general
        печать.printInfo = сведения
        печать.printFormatter = UIMarkupTextPrintFormatter(markupText: html)
        _ = печать.present(animated: true, completionHandler: nil)
    }
}
