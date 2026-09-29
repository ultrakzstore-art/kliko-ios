import SwiftUI

/**
 ВОЗВРАТ ТОВАРА У ПОКУПАТЕЛЯ И ИТОГ ВОЗВРАТА — СВОЙ БЛОК (clocalReturnPanel, clocalReturnReason, clocalRefuseModal сайта;
 карта §9.10, CAB @586089–603500).

 Показывается при delivery.status ∈ returning | returned_to_seller | refunded (у продавца, пока возврат идёт, — свой
 БлокВозвратаПродавцу с деньгами). Расчёт — как у сайта: c = actual_pay || total_pay || amount; l — доставка туда
 (только если заявка курьера жива: ship_claim_id, отмена не «free», не сорвалась); d = l + ship_return_fee при yandex_on;
 причина defect | wrong | notdesc — доставку туда и обратно платит продавец (return_fault = seller), иначе покупатель.
   · Покупатель, причины ещё нет, а доставка стоит денег: «Почему отказались?…» и пять причин →
     chat.php?action=clocal_return_reason {deal_id, reason} → «Причина записана».
   · Причина есть: «Вам вернётся вся сумма — N…» или «Вам вернётся N: доставка туда и обратно (R) за ваш счёт…»;
     доставки нет — «Верните товар продавцу…» / «Продавец получает товар…».
   · «Продавец затягивает возврат? Открыть спор» — окно спора карточки.
   · refunded — обеим сторонам: «Возврат завершён — деньги вернулись покупателю» и кто оплатил доставку (ship_payer,
     ship_seller_charge / ship_buyer_charge).
 */
struct БлокВозвратаПокупателю: View {
    let сделка: Сделка
    let курьер: КурьерСделки
    @ObservedObject var передача: ПередачаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    /// Причины возврата сайта — в его порядке.
    static let причины: [String] = ["defect", "wrong", "notdesc", "size", "changed"]

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var причинаИзвестна: Bool { Self.причины.contains(курьер.причинаВозврата) }
    private var винаПродавца: Bool { причинаИзвестна && курьер.винаВозврата == "seller" }

    /// c сайта: actual_pay || total_pay || amount.
    private var оплачено: Int {
        if сделка.оплачено > 0 { return сделка.оплачено }
        return сделка.кОплате > 0 ? сделка.кОплате : сделка.сумма
    }

    /// d сайта: доставка туда (живая заявка курьера) и обратно — только при курьере Яндекса.
    private var дорога: Int {
        let д = сделка.деньги
        let заявкаЖива = !д.заявкаКурьера.isEmpty && д.отменаЗаявки != "free" && !д.заявкаСорвалась
        let туда = заявкаЖива ? (сделка.доставка > 0 ? сделка.доставка : сделка.доставкаЗаСчётПродавца) : 0
        return курьер.яндекс ? туда + д.обратнаяДоставка : 0
    }

    var body: some View {
        БлокСделки {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 17))
                    .accessibilityHidden(true)
                Text(СделкиText.т("ret_h"))
                    .font(.system(size: 14, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(КраскаСделокКабинета.плохоТекст)
            .accessibilityAddTraits(.isHeader)
            if причинаИзвестна {
                (Text(т("ret_reason") + ": ") + Text(т("ret_r_" + курьер.причинаВозврата)).bold())
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            if курьер.статус == "refunded" {
                ЗаметкаСделки(Text(итог), вид: .хорошо, символ: "checkmark")
            } else if !сделка.продавец {
                покупателю
            }
        }
    }

    /// «Возврат завершён…» и, если доставка стоила денег, кто её оплатил.
    private var итог: String {
        let d = дорога
        guard d > 0 else { return т("ret_closed") }
        let д = сделка.деньги
        let кто: String
        switch д.платилДоставку {
        case "seller":
            кто = ПередачаText.т("ret_closed_s", n: СделкиФормат.тенге(д.доставкаСПродавца > 0 ? д.доставкаСПродавца : d))
        case "platform":
            кто = т("ret_closed_p")
        default:
            кто = ПередачаText.т("ret_closed_b", n: СделкиФормат.тенге(д.доставкаСПокупателя > 0 ? д.доставкаСПокупателя : d))
        }
        return т("ret_closed") + ". " + кто
    }

    @ViewBuilder
    private var покупателю: some View {
        let d = дорога
        let c = оплачено
        if d > 0 && !причинаИзвестна {
            ЗаметкаСделки(Text(ПередачаText.т("ret_b_ask", n: СделкиФормат.тенге(d))), вид: .предупреждение)
            VStack(spacing: 8) {
                ForEach(Self.причины, id: \.self) { код in
                    КнопкаПричиныВозврата(текст: т("ret_r_" + код), доступна: !передача.идёт) {
                        передача.причинаВозврата(код)
                    }
                }
            }
        } else if d > 0 {
            let текст = винаПродавца
                ? ПередачаText.т("ret_b_full", n: СделкиФормат.тенге(c))
                : ПередачаText.т("ret_b_part", n: СделкиФормат.тенге(max(0, c - d)))
                    .replacingOccurrences(of: "{r}", with: СделкиФормат.тенге(d))
            ЗаметкаСделки(Text(текст), вид: .предупреждение)
        } else {
            let ключ = курьер.статус == "returned_to_seller" ? "ret_b_back" : "ret_b_self"
            ЗаметкаСделки(Text(ПередачаText.т(ключ, n: СделкиФормат.тенге(c))), вид: .предупреждение)
        }
        КнопкаСделки(т("ret_b_dispute"), вид: .вторая, символ: "exclamationmark.bubble") { действие(.спор) }
    }
}

/// .clc-reason сайта: причина во всю ширину, текст слева, жирный, на --surf2 в рамке.
struct КнопкаПричиныВозврата: View {
    let текст: String
    var доступна = true
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступна)
        .opacity(доступна ? 1 : 0.55)
    }
}

// MARK: - «Не приму — оформить возврат» (clocalRefuseModal, clocalDoRefuse)

/// «Оформить возврат»: почему возвращаете — пять причин; нажатие — clocal_refuse {deal_id, reason}.
struct ОкноОтказаОтТовара: View {
    @ObservedObject var передача: ПередачаСделкиМодель

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ШапкаОкнаПередачи(заголовок: т("ret_rf_t"), закрыть: { передача.лист = nil })
                ПодписьСделки(т("ret_rf_s"))
                VStack(spacing: 8) {
                    ForEach(БлокВозвратаПокупателю.причины, id: \.self) { код in
                        КнопкаПричиныВозврата(текст: т("ret_r_" + код), доступна: !передача.идёт) {
                            передача.отказаться(код)
                        }
                    }
                }
                ОшибкаОкнаПередачи(текст: передача.ошибкаОкна)
                КнопкаСделки(СделкиText.т("close"), вид: .вторая) { передача.лист = nil }
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
}
