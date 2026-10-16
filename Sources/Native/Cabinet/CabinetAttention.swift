import SwiftUI

/**
 «ТРЕБУЕТ ВНИМАНИЯ» НА ГЛАВНОЙ КАБИНЕТА (задание сервера 1.13, Б5: блок главной кабинета сайта cab_home_v2 нативно).

 Под плитками — сделки, где ход за человеком: строка «чей ход» сервера (next: lead, text, срок — СлотХодаСделки), а у
 старого ответа без next — спор и «получено — подтвердите» у покупателя. Не больше трёх строк; больше — «Все сделки · N».
 Данные — тот же ответ my_deals, что у значка плитки «Сделки» (СделкиМодель.внимание), своих запросов нет. Нечего
 делать — блока нет совсем: пустой «Всё спокойно» не нужен, плитки и так говорят, что сделок нет.
 */
struct ВниманиеКабинета: View {
    let сделки: [СделкаКратко]
    let открыть: (String) -> Void
    let все: () -> Void

    private static let строк = 3

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            заголовок
            ForEach(сделки.prefix(Self.строк)) { сделка in
                СтрокаВниманияКабинета(сделка: сделка) { открыть(сделка.id) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if сделки.count > Self.строк {
                Button(action: все) {
                    HStack(spacing: 6) {
                        Text(КабинетГлавнаяText.т("att_all") + " · \(сделки.count)")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.зелёный)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеСайта())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        .animation(ДвижениеСайта.смена, value: сделки.map(\.id))
    }

    private var заголовок: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                .accessibilityHidden(true)
            Text(КабинетГлавнаяText.т("att_title"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
            ЗначокСчётчикаКабинета(сделки.count)
                .accessibilityLabel(String(format: КабинетГлавнаяText.т("att_count"), сделки.count))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Строка блока: фото товара, название и под ним слот «чей ход» (или своя строка по статусу), стрелка.
private struct СтрокаВниманияКабинета: View {
    let сделка: СделкаКратко
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 10) {
                фото
                VStack(alignment: .leading, spacing: 4) {
                    Text(сделка.название.isEmpty ? КабинетГлавнаяText.т("tile_deals") : сделка.название)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    слот
                }
                СтрелкаСтрокиКабинета()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var слот: some View {
        if let ход = сделка.ход, ход.мойХод {
            СлотХодаСделки(ход: ход)
        } else {
            let спор = сделка.статус == "disputed"
            HStack(spacing: 6) {
                Image(systemName: спор ? "exclamationmark.bubble.fill" : "checkmark.seal")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(КабинетГлавнаяText.т(спор ? "att_disputed" : "att_delivered"))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(ВидСтатусаСделки.предупреждение.текст)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background(ВидСтатусаСделки.предупреждение.фон,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        }
    }

    private var фото: some View {
        КартинкаЛенты(Config.url(сделка.фото), пунктов: 48) {
            ZStack {
                Theme.поверхность2
                Image(systemName: "shippingbox")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}
