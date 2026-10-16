import SwiftUI

/**
 «МОИ СДЕЛКИ» — СДЕЛКА ЦИФРОВОГО КОДА (ultra-site 16.10.2026, задание «Цифровые товары», Ц4).

 Купивший код на сайте видит в «Моих сделках» гарант-сделку с mode "digital": оплата → код зарезервирован → покупатель
 стирает защитный слой (код открывается) → окно проверки → «Код работает» или спор → замена кода из сейфа или возврат.
 Приложение показывает только название, сумму и статус: без шагов доставки, без «отправил / получил» и без открытия кода —
 escrow.php?action=digital_reveal не зовётся нигде (Apple 3.1.3(b): пользоваться в приложении купленным вне его можно,
 только если то же продаётся и через покупки Apple). Вместо шагов — строка «Цифровой код открывается в веб-версии
 кабинета», без ссылки. Спор (причина, «Договорились», доказательства) и чат сделки — как у прочих сделок.
 */
extension Сделка {
    /// mode "digital" — сделка цифрового кода.
    var цифровая: Bool { режим == ЦифровыеТовары.сделка }
}

/// Часть карточки сделки на месте мастера шагов: сумма, строка о веб-версии кабинета и спор, если он идёт.
struct ЧастьЦифровойСделки: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    init(сделка: Сделка, модель: КарточкаСделкиМодель, действие: @escaping (НажатиеСделки) -> Void) {
        self.сделка = сделка
        self.модель = модель
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            БлокСделки {
                ЗаголовокБлокаСделки(текст: ЦифровоеText.т("badge"), символ: "key")
                if сделка.сумма > 0 {
                    (Text(т(сделка.продавец ? "deal_sum" : "deal_price") + " ")
                        + Text(СделкиФормат.тенге(сделка.сумма)).bold())
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                }
                ЗаметкаСделки(Text(ЦифровоеText.т("deal_code_web")), вид: .инфо, символ: "lock")
            }
            /* Спор — тем же блоком, что у прочих сделок: причина, «Договорились» / вернуть деньги, доказательства. */
            if сделка.статус == "disputed" {
                БлокСпора(сделка: сделка, модель: модель, действие: действие)
            }
        }
    }
}

/// Слот карточки в списке сделок: та же строка одной высоты (30), что подсказки статуса, — без хода и доставки.
struct СлотЦифровойСделки: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "key")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(ЦифровоеText.т("deal_code_web"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ВидСтатусаСделки.инфо.текст)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(ВидСтатусаСделки.инфо.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ЦифровоеText.т("deal_code_web"))
    }
}
