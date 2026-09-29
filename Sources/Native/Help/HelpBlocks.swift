import SwiftUI

/**
 БЛОКИ СТАТЬИ СТРАНИЦЫ САЙТА — СВОИМИ ВИДАМИ (справочный центр, соглашение, оферта, политика, оплата, тарифы).

 Раздел статьи — карточка (.help-card сайта: белая, рамка, скругление 14, поля 16). Отступы между блоками — по виду
 соседей (ОтступСтатьи): перед заголовком больше, после заголовка меньше, пункты списка и вопросы плотнее — ровный
 ритм, а не одинаковые 10 pt на всё. Размеры шрифта растут с «Размером текста» iOS (@ScaledMetric от 15 pt). Длинные
 слова и адреса переносятся, ничего не вылезает за карточку; справа налево (арабский) — зеркально.
 */

/// Раздел статьи одной карточкой.
struct КарточкаСтатьи: View {
    let блоки: [БлокСтатьи]
    @Binding var раскрытые: Set<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(блоки.enumerated()), id: \.element.id) { номер, блок in
                БлокСтатьиВид(блок: блок, раскрытые: $раскрытые, маркерРяда: ОтступСтатьи.маркерРяда(блоки, номер))
                    .padding(.top, номер == 0 ? 0 : ОтступСтатьи.сверху(блок, после: блоки[номер - 1]))
                    .id(блок.id)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// Отступ блока от предыдущего — по виду обоих.
enum ОтступСтатьи {
    static func сверху(_ блок: БлокСтатьи, после прежний: БлокСтатьи) -> CGFloat {
        if case .заголовок(let уровень) = блок.вид {
            return уровень <= 2 ? 22 : 16
        }
        if case .заголовок = прежний.вид { return 8 }
        switch (блок.вид, прежний.вид) {
        case (.пункт, .пункт):
            return 6
        case (.вопрос, .вопрос), (.карточка, .карточка):
            return 8
        case (.примечание, .картинка):
            return 6
        default:
            return 12
        }
    }

    /**
     Маркер пункта, под текстом которого стоит продолжение (второй абзац пункта, <dd>): продолжение под «10.» — вровень
     с текстом «10.», а не с текстом «•». У самого пункта с маркером — пусто.
     */
    static func маркерРяда(_ блоки: [БлокСтатьи], _ номер: Int) -> String {
        guard блоки.indices.contains(номер), case .пункт(let свой, let уровень) = блоки[номер].вид, свой.isEmpty else {
            return ""
        }
        var место = номер - 1
        while место >= 0 {
            guard case .пункт(let маркер, let его) = блоки[место].вид else { return "" }
            if его == уровень, !маркер.isEmpty { return маркер }
            if его < уровень { return "" }
            место -= 1
        }
        return ""
    }

    /**
     Ширина места под маркер: у всех пунктов одного вида одна, текст пунктов — ровной колонкой, перенос строки — под
     текстом, а не под номером. «•» — узко; «1.»…«99.», «а)», «IV.» — одна ширина; «4.2.», «4.12.1.» — шире.
     */
    static func ширинаМаркера(_ маркер: String, размер: CGFloat) -> CGFloat {
        let знаков = маркер.count
        if знаков == 0 || маркер == "•" || маркер == "◦" { return размер * 1.2 }
        if знаков <= 3 { return размер * 1.9 }
        if знаков <= 6 { return размер * 3.0 }
        return размер * 0.62 * CGFloat(знаков)
    }
}

/// Один блок статьи.
struct БлокСтатьиВид: View {
    let блок: БлокСтатьи
    @Binding var раскрытые: Set<Int>
    /// Маркер пункта, которого этот блок — продолжение (ОтступСтатьи.маркерРяда): для ровного отступа.
    var маркерРяда: String = ""

    @ScaledMetric(relativeTo: .body) private var размер: CGFloat = 15

    var body: some View {
        switch блок.вид {
        case .заголовок(let уровень):
            ЗаголовокСтатьи(блок: блок, размер: размерЗаголовка(уровень), жирность: уровень <= 2 ? .heavy : .bold)
        case .абзац:
            ТекстСтатьи(текст: блок.текст, размер: размер)
        case .пункт(let маркер, let уровень):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(маркер)
                    .font(.system(size: размер, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minWidth: ОтступСтатьи.ширинаМаркера(маркер.isEmpty ? маркерРяда : маркер, размер: размер),
                           alignment: .trailing)
                    .accessibilityHidden(маркер == "•" || маркер == "◦" || маркер.isEmpty)
                ТекстСтатьи(текст: блок.текст, размер: размер)
            }
            .padding(.leading, CGFloat(max(0, уровень - 1)) * (размер * 1.2 + 8))
        case .цитата:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.акцент)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                ТекстСтатьи(текст: блок.текст, размер: размер, краска: Theme.текстВторой)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .примечание:
            ТекстСтатьи(текст: блок.текст, размер: размер - 2, краска: Theme.текстВторой)
        case .разделитель:
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .accessibilityHidden(true)
        case .вопрос(let ответ, _):
            ВопросСтатьи(блок: блок, ответ: ответ, раскрытые: $раскрытые)
        case .таблица(let строки, let шапка):
            ТаблицаСтатьи(строки: строки, шапка: шапка)
        case .картинка(let адрес, let пропорция):
            КартинкаСтатьи(адрес: адрес, пропорция: пропорция, подпись: блок.простой)
        case .карточка(let адрес):
            ПлиткаСтатьи(блок: блок, адрес: адрес)
        case .сводка:
            СводкаПлиток(текст: блок.простой)
        }
    }

    private func размерЗаголовка(_ уровень: Int) -> CGFloat {
        switch уровень {
        case 1: return размер * 1.55
        case 2: return размер * 1.25
        case 3: return размер * 1.07
        default: return размер
        }
    }
}

/**
 Заголовок раздела. Номер сайта в своём значке («<span>1</span>Оператор данных» политики, соглашения, оферты) —
 зелёным кружком перед названием, как у сайта, а не слитно «1Оператор данных».
 */
struct ЗаголовокСтатьи: View {
    let блок: БлокСтатьи
    let размер: CGFloat
    let жирность: Font.Weight

    var body: some View {
        if let номер = РазборСтатьи.номерЗаголовка(блок.простой) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                /* «1» — кружок, «4.2», «IV» — пилюля той же высоты. */
                Text(номер.номер)
                    .font(.system(size: размер * 0.62, weight: .heavy))
                    .foregroundStyle(Theme.поверхность)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, номер.номер.count > 2 ? размер * 0.3 : 0)
                    .frame(minWidth: размер * 1.35, minHeight: размер * 1.35)
                    .background(Theme.акцент, in: Capsule())
                    .accessibilityHidden(true)
                Text(номер.название)
                    .font(.system(size: размер, weight: жирность))
                    .foregroundStyle(Theme.текст)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(номер.номер + ". " + номер.название)
            .accessibilityAddTraits(.isHeader)
        } else {
            Text(блок.текст)
                .font(.system(size: размер, weight: жирность))
                .foregroundStyle(Theme.текст)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/**
 Плитка раздела справки (ссылка-карточка сайта): значок, название, подпись и стрелка — своей карточкой, как разделы
 статьи (поверхность, рамка 1.5, скругление 14, поля 16). Нажатие — адрес плитки: якорь этой же страницы прокручивает
 к разделу, другая статья справки открывается следующим экраном.
 */
struct ПлиткаСтатьи: View {
    let блок: БлокСтатьи
    let адрес: URL

    @ScaledMetric(relativeTo: .body) private var размер: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var сторонаЗначка: CGFloat = 38
    @Environment(\.openURL) private var открытьАдрес
    @Environment(\.нажатьПлиткуСтатьи) private var нажатьПлитку

    var body: some View {
        Button {
            /* Экран статьи знает плитку целиком (название, подпись, метки) — ему и решать, куда вести. */
            if let нажатьПлитку {
                нажатьПлитку(блок)
            } else {
                открытьАдрес(адрес)
            }
        } label: {
            HStack(spacing: 12) {
                if !блок.значок.isEmpty {
                    Text(блок.значок)
                        .font(.system(size: размер + 3))
                        .frame(width: сторонаЗначка, height: сторонаЗначка)
                        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(блок.простой)
                        .font(.system(size: размер, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !блок.подпись.isEmpty {
                        Text(блок.подпись)
                            .font(.system(size: размер - 2))
                            .foregroundStyle(Theme.текстВторой)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
    }
}

/// Сводка над плитками («67 ответов в 14 разделах»): мелко, вторым цветом.
struct СводкаПлиток: View {
    let текст: String

    @ScaledMetric(relativeTo: .footnote) private var размер: CGFloat = 13

    var body: some View {
        Text(текст)
            .font(.system(size: размер, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Ряд плиток разделов: сводка и плитки, каждая своей карточкой.
struct РядПлитокСтатьи: View {
    let блоки: [БлокСтатьи]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(блоки) { блок in
                БлокРядаПлиток(блок: блок)
                    .id(блок.id)
            }
        }
    }
}

/// Один блок ряда плиток: плитка, сводка (с отступом от края, как подписи над карточками) или прочее.
private struct БлокРядаПлиток: View {
    let блок: БлокСтатьи

    var body: some View {
        switch блок.вид {
        case .карточка(let адрес):
            ПлиткаСтатьи(блок: блок, адрес: адрес)
        case .сводка:
            СводкаПлиток(текст: блок.простой)
                .padding(.horizontal, 4)
                .padding(.top, 4)
        default:
            Text(блок.простой)
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Текст статьи: абзац, пункт, цитата. Ссылки — акцентом; без ссылок текст можно выделить и скопировать.
struct ТекстСтатьи: View {
    let текст: AttributedString
    let размер: CGFloat
    var краска: Color = Theme.текст

    private var естьСсылки: Bool {
        текст.runs.contains(where: { $0.link != nil })
    }

    /// <u>/<ins> разбора (ПодчёркнутоСтатьи) — подчёркиванием SwiftUI.
    private var показ: AttributedString {
        var итог = текст
        for кусок in текст.runs where кусок[ПодчёркнутоСтатьи.self] == true {
            итог[кусок.range][AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = .single
        }
        return итог
    }

    var body: some View {
        Text(показ)
            .font(.system(size: размер))
            .lineSpacing(размер * 0.25)
            .foregroundStyle(краска)
            .tint(Theme.акцент)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(ВыделениеСтатьи(можно: !естьСсылки))
    }
}

/// Выделение текста — только там, где нет ссылок (выделение перехватывает нажатие на ссылку).
private struct ВыделениеСтатьи: ViewModifier {
    let можно: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if можно {
            content.textSelection(.enabled)
        } else {
            content
        }
    }
}

/// <details>/<summary> и раскрывашки на скрипте: вопрос строкой, ответ раскрывается.
struct ВопросСтатьи: View {
    let блок: БлокСтатьи
    let ответ: [БлокСтатьи]
    @Binding var раскрытые: Set<Int>

    @ScaledMetric(relativeTo: .body) private var размер: CGFloat = 15

    private var открыт: Bool { раскрытые.contains(блок.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ДвижениеСайта.смена) {
                    if открыт { раскрытые.remove(блок.id) } else { раскрытые.insert(блок.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(блок.текст)
                        .font(.system(size: размер, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .rotationEffect(.degrees(открыт ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(СправкаText.т("a11y_faq"))
            .accessibilityAddTraits(открыт ? [.isSelected] : [])
            if открыт {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ответ.enumerated()), id: \.element.id) { номер, часть in
                        БлокСтатьиВид(блок: часть, раскрытые: $раскрытые,
                                      маркерРяда: ОтступСтатьи.маркерРяда(ответ, номер))
                            .padding(.top, номер == 0 ? 0 : ОтступСтатьи.сверху(часть, после: ответ[номер - 1]))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }
}

/// Таблица статьи: до трёх колонок — сеткой с линиями; шире — строка карточкой «название колонки: значение»
/// (на ширине телефона четыре колонки не читаются).
struct ТаблицаСтатьи: View {
    let строки: [[AttributedString]]
    let шапка: Bool

    @ScaledMetric(relativeTo: .subheadline) private var размер: CGFloat = 14

    private var колонок: Int { строки.map { $0.count }.max() ?? 0 }

    var body: some View {
        if колонок <= 3 {
            сетка
        } else {
            карточки
        }
    }

    private var сетка: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(Array(строки.enumerated()), id: \.offset) { номер, строка in
                if номер > 0 {
                    Rectangle()
                        .fill(Theme.линия)
                        .frame(height: 1)
                }
                GridRow {
                    ForEach(0..<колонок, id: \.self) { колонка in
                        ячейка(колонка < строка.count ? строка[колонка] : AttributedString(),
                               заглавная: шапка && номер == 0)
                            .padding(.vertical, 9)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private func ячейка(_ текст: AttributedString, заглавная: Bool) -> some View {
        Text(текст)
            .font(.system(size: размер, weight: заглавная ? .bold : .regular))
            .foregroundStyle(заглавная ? Theme.текстВторой : Theme.текст)
            .tint(Theme.акцент)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var карточки: some View {
        let названия: [AttributedString] = шапка ? (строки.first ?? []) : []
        let данные: [[AttributedString]] = шапка ? Array(строки.dropFirst()) : строки
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(данные.enumerated()), id: \.offset) { _, строка in
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(строка.enumerated()), id: \.offset) { колонка, значение in
                        if !значение.characters.isEmpty {
                            поле(колонка < названия.count ? названия[колонка] : AttributedString(), значение,
                                 первое: колонка == 0)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func поле(_ название: AttributedString, _ значение: AttributedString, первое: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !название.characters.isEmpty {
                Text(название)
                    .font(.system(size: размер - 2, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(значение)
                .font(.system(size: размер, weight: первое && название.characters.isEmpty ? .bold : .regular))
                .foregroundStyle(Theme.текст)
                .tint(Theme.акцент)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Картинка статьи: по ширине карточки, пока грузится — серая подложка нужной пропорции; не загрузилась — не видна.
struct КартинкаСтатьи: View {
    let адрес: URL
    let пропорция: Double?
    let подпись: String

    var body: some View {
        AsyncImage(url: адрес) { фаза in
            if let картинка = фаза.image {
                картинка
                    .resizable()
                    .scaledToFit()
            } else if фаза.error != nil {
                EmptyView()
            } else {
                Theme.поверхность2
                    .aspectRatio(CGFloat(пропорция ?? 16.0 / 9.0), contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityLabel(подпись)
        .accessibilityHidden(подпись.isEmpty)
    }
}

/**
 Поле поиска справки (.help-search сайта): пилюля с лупой, текстом и крестиком «очистить». Стоит в шапке экрана над
 прокруткой, на непрозрачном фоне страницы: карточки под ним не просвечивают.
 */
struct ПолеПоискаСправки: View {
    @Binding var текст: String

    @FocusState private var вФокусе: Bool
    @ScaledMetric(relativeTo: .body) private var размер: CGFloat = 15

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: размер, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(СправкаText.т("search"), text: $текст)
                .font(.system(size: размер))
                .foregroundStyle(Theme.текст)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($вФокусе)
                .onSubmit { вФокусе = false }
            if !текст.isEmpty {
                Button {
                    текст = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 24, height: 24)
                        .background(Theme.поверхность2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(СправкаText.т("search_clear"))
            }
        }
        .frame(minHeight: 26)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.поверхность, in: Capsule())
        .overlay {
            Capsule().strokeBorder(вФокусе ? Theme.акцент : Theme.линия, lineWidth: 1.5)
        }
        .contentShape(Capsule())
        .onTapGesture { вФокусе = true }
    }
}

// MARK: - Нажатие плитки раздела

private struct КлючНажатияПлиткиСтатьи: EnvironmentKey {
    static let defaultValue: ((БлокСтатьи) -> Void)? = nil
}

extension EnvironmentValues {
    /// Что делает плитка раздела: ставит экран статьи (ЭкранСтраницыСайта). Нет — плитка открывает свой адрес.
    var нажатьПлиткуСтатьи: ((БлокСтатьи) -> Void)? {
        get { self[КлючНажатияПлиткиСтатьи.self] }
        set { self[КлючНажатияПлиткиСтатьи.self] = newValue }
    }
}
