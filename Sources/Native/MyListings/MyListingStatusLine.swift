import SwiftUI

/**
 РОВНАЯ СХЕМА «МОИХ ОБЪЯВЛЕНИЙ» — СЛОТ СТАТУСА (владелец 13.10.2026: «высота карточек с подсказками статуса»; «стили
 независимо от названия — схема должна быть ровной везде в приложении»).

 Раньше значок статуса переносился на две-три строки («Отклонено — причина», «Не видно покупателям — подтвердите
 личность через eGov»), а под карточкой вырастали отдельные блоки («Отклонено несколько раз…», «В ТОПе до …»,
 «Бесплатно поднимем через N дн.») — карточка с подсказкой выходила выше соседних. Теперь это одна строка постоянной
 высоты у всех карточек: значок и первое сведение рядом. Не влезло — многоточие и «ⓘ», весь текст — по нажатию, в
 окошке над строкой (popover и на iPhone). VoiceOver читает строку целиком.
 */

/// Сведение к значку статуса: символ SF Symbols, текст и краска.
struct СведениеСтатусаОбъявления: Identifiable {
    let символ: String
    let текст: String
    let цвет: Color

    var id: String { символ + "|" + текст }

    init(символ: String, текст: String, цвет: Color) {
        self.символ = символ
        self.текст = текст
        self.цвет = цвет
    }
}

/// Слот статуса карточки «Моего объявления» — ровно одна строка одной высоты у всех карточек списка.
struct СтрокаСтатусаОбъявления: View {
    let значок: ЗначокОбъявления
    let сведения: [СведениеСтатусаОбъявления]

    /// Окошко с полным текстом статуса и всеми сведениями.
    @State private var подробно = false

    init(значок: ЗначокОбъявления, сведения: [СведениеСтатусаОбъявления]) {
        self.значок = значок
        self.сведения = сведения
    }

    /// Высота слота — по самому высокому значку («Опубликовано» с полями 4): у всех видов одна.
    static let высота: CGFloat = 24

    var body: some View {
        /* Влезло целиком — как было; нет — та же строка с многоточием и «ⓘ», нажатие открывает весь текст. */
        ViewThatFits(in: .horizontal) {
            целиком
            сжато
        }
        .frame(minHeight: Self.высота, alignment: .leading)
        .popover(isPresented: $подробно, arrowEdge: .bottom) {
            ПодробностиСтатусаОбъявления(значок: значок, сведения: сведения)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Всё влезло: значок и первое сведение без обрезки. Нажимается, только если сведений больше одного.
    @ViewBuilder
    private var целиком: some View {
        if сведения.count > 1 {
            кнопка(ряд(сжатый: false))
        } else {
            ряд(сжатый: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(голос)
        }
    }

    /// Не влезло: обрезка многоточием и «ⓘ»; нажатие — весь текст.
    private var сжато: some View {
        кнопка(ряд(сжатый: true))
    }

    private func кнопка<Подпись: View>(_ подпись: Подпись) -> some View {
        Button {
            подробно = true
        } label: {
            подпись
        }
        .buttonStyle(.plain)
        .accessibilityLabel(голос)
        .accessibilityHint(РовныеКарточкиText.т("more_hint"))
    }

    private func ряд(сжатый: Bool) -> some View {
        HStack(spacing: 6) {
            ЯрлыкСтатуса(значок: значок, вОднуСтроку: true)
                .layoutPriority(1)
            if let первое = сведения.first {
                сведение(первое)
            }
            if сжатый || сведения.count > 1 {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .layoutPriority(2)
                    .accessibilityHidden(true)
            }
            /* Сжатая строка — во всю ширину: нажимается вся, а не только значок. */
            if сжатый {
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
    }

    /// Сведение рядом со значком: символ 10 и текст 11 в строку.
    private func сведение(_ с: СведениеСтатусаОбъявления) -> some View {
        HStack(spacing: 3) {
            Image(systemName: с.символ)
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(с.текст)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(с.цвет)
    }

    /// Голос слота: статус, подсказка сайта (если есть) и все сведения — целиком, без обрезки.
    private var голос: String {
        var части = [значок.текст]
        if let подсказка = значок.подсказка, !подсказка.isEmpty { части.append(подсказка) }
        части.append(contentsOf: сведения.map(\.текст))
        return части.joined(separator: ", ")
    }
}

/// Окошко слота статуса: значок с полным текстом, подсказка сайта и все сведения строками.
struct ПодробностиСтатусаОбъявления: View {
    let значок: ЗначокОбъявления
    let сведения: [СведениеСтатусаОбъявления]

    init(значок: ЗначокОбъявления, сведения: [СведениеСтатусаОбъявления]) {
        self.значок = значок
        self.сведения = сведения
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЯрлыкСтатуса(значок: значок)
            if let подсказка = значок.подсказка, !подсказка.isEmpty {
                строка(СведениеСтатусаОбъявления(символ: "info.circle", текст: подсказка, цвет: Theme.текстВторой))
            }
            ForEach(сведения) { с in
                строка(с)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .presentationBackground(Theme.поверхность)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func строка(_ с: СведениеСтатусаОбъявления) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: с.символ)
                .accessibilityHidden(true)
            Text(с.текст)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(с.цвет)
        .accessibilityElement(children: .combine)
    }
}
