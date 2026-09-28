import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ВИД РЕЖИМА «ВЫБРАТЬ» И МАСС-РЕДАКТОРА (состояние и запросы — MyListingsBulk.swift).

 Краски — кабинета сайта (css_cabinet-parts.min.css): кнопка #adv-selmode-btn (оттенок акцента, рамка акцента, пилюля),
 флажок .advsel-chk (белый круг 28 с тенью в верхнем углу карточки), рамка .advsel-on (2,5 акцента), нижняя панель
 #adv-selbar (зелёная, радиус lg: «N выбрано», «Все», «Готово»; ряд кнопок .act / .gold / .all по сетке от 132 пт),
 листы .advsh (заголовок и крестик, подписи .advsh-lbl заглавными, кнопки .advsh-b / .g / .r, поле с кнопкой
 .advsh-field), окно хода .advpr (значок, «N из M», полоса, итог). Тёмная тема — те же токены Theme.
 */

private func тМ(_ ключ: String) -> String { МассовыйРедакторText.т(ключ) }

// MARK: - Кнопка «Выбрать» / «Отмена»

/// #adv-selmode-btn: справа от поиска.
struct КнопкаВыбратьОбъявления: View {
    let включён: Bool
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 6) {
                Image(systemName: включён ? "xmark" : "checkmark.square")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
                Text(тМ(включён ? "sel_cancel" : "sel_btn"))
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.оттенокАкцента, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.акцент, lineWidth: 1) }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
        .fixedSize()
    }
}

/// «+ Добавить» в шапке экрана — мастер подачи.
struct КнопкаДобавитьВШапке: View {
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.footnote.weight(.heavy))
                    .accessibilityHidden(true)
                Text(тМ("hdr_add"))
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .leading,
                                       endPoint: .trailing), in: Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
        .accessibilityLabel(тМ("a11y_add"))
    }
}

// MARK: - Флажок на карточке

/// .advsel-chk: белый круг 28 с тенью, внутри — квадратик-флажок.
struct ФлажокВыбораОбъявления: View {
    let отмечен: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.поверхность)
                .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                .shadow(color: Color.black.opacity(0.22), radius: 4.5, y: 2)
            if отмечен {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.акцент)
                    .frame(width: 17, height: 17)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.поверхность)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.текстВторой, lineWidth: 1.5)
                    .frame(width: 17, height: 17)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

// MARK: - Нижняя панель

/// Кнопки ряда #adv-selbar .row2 — набор и порядок advSelBar сайта.
enum ДействиеПанелиВыбора: Hashable {
    case таблица, снять, цена, продвинуть, ещё, активировать, расписание, восстановить, навсегда

    enum Вид { case белая, золотая, прозрачная, опасная }

    /// «Продвинуть» — только при Config.цифровыеПокупки (покупка App Store); иначе кнопки нет.
    static func набор(_ вкладка: ВкладкаОбъявлений, правка: Bool) -> [ДействиеПанелиВыбора] {
        let покупки = Config.цифровыеПокупки
        var н: [ДействиеПанелиВыбора] = []
        switch вкладка {
        case .published:
            н.append(.таблица)
            if правка {
                н.append(.снять)
                н.append(.цена)
            }
            if покупки { н.append(.продвинуть) }
            if правка { н.append(.ещё) }
        case .inactive:
            н.append(.таблица)
            н.append(.активировать)
            н.append(.расписание)
            if правка {
                н.append(.цена)
                н.append(.ещё)
            } else if покупки {
                н.append(.продвинуть)
            }
        case .deleted:
            н.append(.восстановить)
            н.append(.навсегда)
        }
        return н
    }

    var подпись: String {
        switch self {
        case .таблица:      return тМ("b_table")
        case .снять:        return тМ("b_deact")
        case .цена:         return тМ("b_price")
        case .продвинуть:   return тМ("b_promote")
        case .ещё:          return тМ("b_more")
        case .активировать: return тМ("b_activate")
        case .расписание:   return тМ("b_sched")
        case .восстановить: return тМ("b_restore")
        case .навсегда:     return тМ("b_purge")
        }
    }

    var значок: String {
        switch self {
        case .таблица:      return "tablecells"
        case .снять:        return "eye.slash"
        case .цена:         return "tag"
        case .продвинуть:   return "arrow.up"
        case .ещё:          return "ellipsis"
        case .активировать: return "play.fill"
        case .расписание:   return "clock"
        case .восстановить: return "arrow.uturn.backward"
        case .навсегда:     return "trash"
        }
    }

    var вид: Вид {
        switch self {
        case .продвинуть: return .золотая
        case .ещё:        return .прозрачная
        case .навсегда:   return .опасная
        default:          return .белая
        }
    }
}

/// #adv-selbar: «N выбрано», «Все» / «Снять все», «Готово»; ниже — действия вкладки.
struct ПанельВыбораОбъявлений: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared
    let вкладка: ВкладкаОбъявлений
    let правка: Bool

    /// Свой init: с private-свойством поэлементный init стал бы private.
    init(вкладка: ВкладкаОбъявлений, правка: Bool) {
        self.вкладка = вкладка
        self.правка = правка
    }

    private static let фонНачало = Theme.цвет(0x1D7D4A, 0x1F7A4D)
    private static let фонКонец = Theme.цвет(0x0F5132, 0x145236)
    private static let золото = LinearGradient(colors: [Color(uiColor: Theme.hex(0xF4D06A)),
                                                        Color(uiColor: Theme.hex(0xC9A227))],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        VStack(spacing: 8) {
            верх
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 6)], spacing: 6) {
                ForEach(ДействиеПанелиВыбора.набор(вкладка, правка: правка), id: \.self) { д in
                    кнопка(д)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .fill(LinearGradient(colors: [Self.фонНачало, Self.фонКонец], startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .shadow(color: Self.фонНачало.opacity(0.5), radius: 16, y: 10)
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var верх: some View {
        HStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(String(редактор.выбрано.count))
                    .font(.footnote.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.акцент)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 23, minHeight: 23)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                       style: .continuous))
                Text(тМ("selected"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            прозрачная(редактор.всеОтмечены ? тМ("none") : тМ("all"), значок: "checkmark.square") {
                редактор.всеИлиНикого()
            }
            Spacer(minLength: 0)
            прозрачная(тМ("done"), значок: "checkmark") { редактор.выйти() }
        }
    }

    private func прозрачная(_ подпись: String, значок: String, нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(spacing: 5) {
                Image(systemName: значок)
                    .font(.caption.weight(.heavy))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.footnote.weight(.heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                        style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
    }

    private func кнопка(_ д: ДействиеПанелиВыбора) -> some View {
        Button { нажато(д) } label: {
            HStack(spacing: 5) {
                Image(systemName: д.значок)
                    .font(.caption.weight(.heavy))
                    .accessibilityHidden(true)
                Text(д.подпись)
                    .font(.footnote.weight(.heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(цвет(д.вид))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background { фон(д.вид) }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
    }

    private func цвет(_ вид: ДействиеПанелиВыбора.Вид) -> Color {
        switch вид {
        case .белая:      return Theme.акцент
        case .золотая:    return Color(uiColor: Theme.hex(0x3A2C05))
        case .прозрачная: return Color.white
        case .опасная:    return КраскаОбъявлений.плохоТекст
        }
    }

    @ViewBuilder
    private func фон(_ вид: ДействиеПанелиВыбора.Вид) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        switch вид {
        case .белая, .опасная:
            форма.fill(Theme.поверхность)
                .shadow(color: Color.black.opacity(0.18), radius: 6, y: 4)
        case .золотая:
            форма.fill(Self.золото)
                .shadow(color: Color(uiColor: Theme.hex(0xC9A227, 0.6)), radius: 7, y: 4)
        case .прозрачная:
            форма.fill(Color.white.opacity(0.15))
        }
    }

    private func нажато(_ д: ДействиеПанелиВыбора) {
        switch д {
        case .таблица:      редактор.открыть(.таблица)
        case .снять:        редактор.спросить(.снять)
        case .цена:         редактор.открыть(.цена)
        case .продвинуть:   редактор.продвинуть()
        case .ещё:          редактор.открыть(.ещё)
        case .активировать: редактор.спросить(.активировать)
        case .расписание:   редактор.открытьРасписание()
        case .восстановить: редактор.спросить(.восстановить)
        case .навсегда:     редактор.спросить(.навсегда)
        }
    }
}

// MARK: - Вопрос перед записью

/// Окно подтверждения (cabConfirm сайта) со сводкой: что, сколько, что пропустится.
struct ОкноВопросаМассовых: View {
    let вопрос: МассовыйРедактор.Вопрос
    let отмена: () -> Void
    let да: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: отмена)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                Image(systemName: вопрос.опасно ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(вопрос.опасно ? КраскаОбъявлений.плохоТекст : Theme.акцент)
                    .accessibilityHidden(true)
                Text(вопрос.заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                сводка
                кнопки
            }
            .padding(22)
            .frame(maxWidth: 400)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
            .padding(.horizontal, 22)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var сводка: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(вопрос.строки.enumerated()), id: \.offset) { пара in
                    Text(пара.element)
                        .font(пара.offset == 0 ? Font.subheadline.weight(.semibold) : Font.footnote)
                        .foregroundStyle(пара.offset == 0 ? Theme.текст : Theme.текстВторой)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private var кнопки: some View {
        VStack(spacing: 8) {
            Button(action: да) {
                Text(вопрос.кнопка)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(вопрос.опасно ? КраскаОбъявлений.красный : Theme.зелёный,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            Button(action: отмена) {
                Text(тМ("q_cancel"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                       style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
    }
}

// MARK: - Окно хода (advProgress)

struct ОкноХодаМассовых: View {
    let ход: МассовыйРедактор.Ход
    let закрыть: () -> Void

    private var доля: Double {
        guard ход.всего > 0 else { return 1 }
        return min(1, Double(ход.сделано) / Double(ход.всего))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                значок
                Text(ход.заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .padding(.top, 14)
                счёт
                ProgressView(value: доля)
                    .tint(Theme.зелёный2)
                    .animation(ДвижениеСайта.прогресс, value: ход.сделано)
                    .padding(.top, 14)
                if let итог = ход.итог {
                    Text(итог)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(ход.сбои.isEmpty ? КраскаОбъявлений.хорошоТекст : Theme.текст)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
                if !ход.сбои.isEmpty { сбои }
                if ход.итог != nil && !ход.сбои.isEmpty { кнопка }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
            .padding(.horizontal, 22)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private var значок: some View {
        Image(systemName: "pencil")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 52, height: 52)
            .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x1D9E5E)), Color(uiColor: Theme.hex(0x0F7A44))],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .accessibilityHidden(true)
    }

    private var счёт: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(String(min(ход.сделано, ход.всего)))
                .font(.largeTitle.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
            Text(тМ("pr_of") + " " + String(ход.всего))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var сбои: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(тМ("res_fail_list"))
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ход.сбои) { с in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(с.название.isEmpty ? "#" + с.id : с.название)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.текст)
                                .lineLimit(2)
                            Text(с.причина)
                                .font(.caption)
                                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxHeight: 180)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(КраскаОбъявлений.плохоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .padding(.top, 14)
    }

    private var кнопка: some View {
        Button(action: закрыть) {
            Text(тМ("done"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .padding(.top, 16)
    }
}

// MARK: - Части листов (.advsh)

/// Лист по высоте содержимого: шапка «заголовок + крестик», содержимое, мерило.
struct ТелоЛистаМассовых<Содержимое: View>: View {
    let заголовок: String
    let содержимое: Содержимое

    init(_ заголовок: String, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.содержимое = содержимое()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                содержимое
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 20)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.поверхность.ignoresSafeArea())
        .листПоВысоте()
    }

    private var шапка: some View {
        HStack(spacing: 10) {
            Text(заголовок)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Button {
                МассовыйРедактор.shared.лист = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.цвет(0x51665B, 0x90A499))
                    .frame(width: 30, height: 30)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(тМ("close"))
        }
        .padding(.bottom, 14)
    }
}

/// .advsh-lbl: мелко, жирно, заглавными, серым.
struct МеткаЛистаМассовых: View {
    let текст: String

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        Text(текст)
            .font(.caption2.weight(.heavy))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.текстВторой)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}

/// .advsh-b: обычная, .g — зелёная, .r — красная.
struct КнопкаЛистаМассовых: View {
    enum Вид { case обычная, зелёная, красная }
    let подпись: String
    var значок: String? = nil
    var вид: Вид = .обычная
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 6) {
                if let значок {
                    Image(systemName: значок)
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(подпись)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(цвет)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(кромка, lineWidth: 1.5)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
    }

    private var цвет: Color {
        switch вид {
        case .обычная: return Theme.текст
        case .зелёная: return Theme.поверхность
        case .красная: return КраскаОбъявлений.плохоТекст
        }
    }

    private var фон: Color {
        switch вид {
        case .обычная: return Theme.поверхность
        case .зелёная: return Theme.акцент
        case .красная: return КраскаОбъявлений.плохоФон
        }
    }

    private var кромка: Color {
        switch вид {
        case .обычная: return Theme.линия
        case .зелёная: return Theme.акцент
        case .красная: return КраскаОбъявлений.плохоТекст
        }
    }
}

/// .advsh-field: поле и зелёная кнопка «Задать» в одной рамке.
struct ПолеЛистаМассовых: View {
    let подсказка: String
    @Binding var текст: String
    var цифры = false
    let кнопка: String
    let нажать: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TextField(подсказка, text: $текст)
                .font(.subheadline)
                .keyboardType(цифры ? .numberPad : .default)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40)
            Button(action: нажать) {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                    Text(кнопка)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.поверхность)
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(Theme.акцент)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// Строка ошибки в листе (плашка экрана под листом не видна).
struct ОшибкаЛистаМассовых: View {
    let текст: String?

    var body: some View {
        if let текст {
            Text(текст)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
        }
    }
}

// MARK: - Какой лист

struct ЛистМассовых: View {
    let лист: МассовыйРедактор.Лист
    let про: Bool

    var body: some View {
        switch лист {
        case .цена:        ЛистЦеныМассовых()
        case .ещё:         ЛистЕщёМассовых(про: про)
        case .таблица:     ЛистТаблицыМассовых()
        case .расписание:  ЛистРасписанияМассовых()
        case .продвижение: ЛистПродвиженияМассовых()
        }
    }
}

// MARK: - «Цена» (advBulkPrice)

struct ЛистЦеныМассовых: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared
    @State private var значение = ""
    @State private var проценты = true
    @State private var ошибка: String? = nil

    init() {}

    var body: some View {
        ТелоЛистаМассовых(String(format: тМ("price_t"), редактор.выбрано.count)) {
            МеткаЛистаМассовых(тМ("price_how"))
            HStack(spacing: 8) {
                TextField("10", text: $значение)
                    .font(.subheadline)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                Picker(тМ("price_how"), selection: $проценты) {
                    Text(verbatim: "%").tag(true)
                    Text(verbatim: "₸").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            .padding(.bottom, 12)
            ОшибкаЛистаМассовых(текст: ошибка)
            HStack(spacing: 8) {
                КнопкаЛистаМассовых(подпись: тМ("price_down"), значок: "arrow.down", вид: .красная) { применить(-1) }
                КнопкаЛистаМассовых(подпись: тМ("price_up"), значок: "arrow.up", вид: .зелёная) { применить(1) }
            }
            .padding(.bottom, 12)
            Text(тМ("price_note"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// advBulkPriceApply: ±% или ±₸, округление до 10 ₸, не ниже 10; аренда без цены продажи — цена за сутки.
    private func применить(_ знак: Double) {
        let чистое = значение.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        let n = abs(Double(чистое) ?? 0)
        guard n > 0, n.isFinite, n < 1_000_000_000 else {
            ошибка = тМ("price_enter")
            return
        }
        ошибка = nil
        let проц = проценты
        let число = n == n.rounded() ? String(Int(n)) : String(n)
        let описание = String(format: тМ("price_sum"), (знак < 0 ? "−" : "+") + число + (проц ? " %" : " ₸"))
        редактор.применить(описание: описание, итог: тМ(знак < 0 ? "price_down_done" : "price_up_done"),
                           пропуск: тМ("price_skip")) { товар in
            let аренда = товар.аренда && товар.ценаАренды > 0 && товар.цена <= 0
            let база = аренда ? товар.ценаАренды : товар.цена
            guard база > 0 else { return nil }
            var новая = проц ? база * (1 + знак * n / 100) : база + знак * n
            новая = max(10, 10 * (новая / 10).rounded())
            guard новая.isFinite, новая < 1e13 else { return nil }
            let целое = Int(новая)
            if аренда { return ["rent_price_day": целое] }
            return ["price": целое]
        }
    }
}

// MARK: - «Ещё» (advBulkMore)

struct ЛистЕщёМассовых: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared
    /// IS_PRO: гарантия больше 7 дней — только у PRO (WR_FREE_MAX сайта).
    let про: Bool
    @State private var город = ""
    @State private var срок = ""
    @State private var гарантия = ""
    @State private var склад = ""
    @State private var раздел = ""
    @State private var тип = ""
    @State private var ошибка: String? = nil
    @State private var грузим = true

    init(про: Bool) {
        self.про = про
    }

    var body: some View {
        ТелоЛистаМассовых(String(format: тМ("more_t"), редактор.выбрано.count)) {
            ОшибкаЛистаМассовых(текст: ошибка)
            блокГорода
            блокСостоянияИОплаты
            блокДоставки
            блокГарантии
            блокСклада
            блокРаздела
            блокТипа
            КнопкаЛистаМассовых(подпись: String(format: тМ("trash_btn"), редактор.выбрано.count), значок: "trash",
                                вид: .красная) {
                редактор.спросить(.вКорзину)
            }
            .padding(.top, 4)
        }
        .task {
            await редактор.загрузитьСправочники()
            грузим = false
            if let у = редактор.уточнение { тип = у.текущий }
        }
    }

    private func секция<С: View>(_ метка: String, @ViewBuilder _ содержимое: () -> С) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            МеткаЛистаМассовых(метка)
            содержимое()
        }
        .padding(.bottom, 16)
    }

    private var сетка: [GridItem] { [GridItem(.adaptive(minimum: 104), spacing: 8)] }

    private func правка(_ описание: String, _ поля: [String: Any]) {
        ошибка = nil
        редактор.применить(описание: описание, итог: описание) { _ in поля }
    }

    // Город

    private var блокГорода: some View {
        секция(тМ("city_l")) {
            ПолеЛистаМассовых(подсказка: тМ("city_ph"), текст: $город, кнопка: тМ("set")) { задатьГород() }
            let подсказки = редактор.городИзСписка(город) == nil ? редактор.подсказкиГородов(город) : []
            if !подсказки.isEmpty {
                VStack(spacing: 0) {
                    ForEach(подсказки, id: \.self) { г in
                        Button {
                            город = г
                        } label: {
                            Text(г)
                                .font(.subheadline)
                                .foregroundStyle(Theme.текст)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if г != подсказки.last { Divider() }
                    }
                }
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .padding(.top, 6)
            }
        }
    }

    private func задатьГород() {
        let ввод = город.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ввод.isEmpty else {
            ошибка = тМ("city_enter")
            return
        }
        guard let найден = редактор.городИзСписка(ввод) else {
            ошибка = тМ(редактор.города.isEmpty && грузим ? "loading" : "city_pick")
            return
        }
        правка(String(format: тМ("city_sum"), найден), ["city": найден])
    }

    // Состояние и оплата

    private var блокСостоянияИОплаты: some View {
        VStack(alignment: .leading, spacing: 0) {
            секция(тМ("cond_l")) {
                LazyVGrid(columns: сетка, spacing: 8) {
                    КнопкаЛистаМассовых(подпись: тМ("cond_new"), значок: "sparkles") {
                        правка(тМ("cond_new_done"), ["condition": "new"])
                    }
                    КнопкаЛистаМассовых(подпись: тМ("cond_used"), значок: "tag") {
                        правка(тМ("cond_used_done"), ["condition": "used"])
                    }
                }
            }
            секция(тМ("pay_l")) {
                LazyVGrid(columns: сетка, spacing: 8) {
                    КнопкаЛистаМассовых(подпись: тМ("pay_inst"), значок: "creditcard") {
                        правка(тМ("pay_inst_done"), ["payment": ["installment": true]])
                    }
                    КнопкаЛистаМассовых(подпись: тМ("pay_credit"), значок: "creditcard") {
                        правка(тМ("pay_credit_done"), ["payment": ["credit": true]])
                    }
                    КнопкаЛистаМассовых(подпись: тМ("pay_off"), значок: "xmark") {
                        правка(тМ("pay_off_done"), ["payment": NSNull()])
                    }
                }
            }
        }
    }

    // Доставка

    private var блокДоставки: some View {
        секция(тМ("ship_l")) {
            LazyVGrid(columns: сетка, spacing: 8) {
                КнопкаЛистаМассовых(подпись: тМ("ship_free"), значок: "shippingbox") {
                    правка(тМ("ship_free_done"), ["ship": ["free": true]])
                }
                КнопкаЛистаМассовых(подпись: тМ("ship_paid"), значок: "xmark") {
                    правка(тМ("ship_paid_done"), ["ship": ["free": false]])
                }
            }
            .padding(.bottom, 8)
            ПолеЛистаМассовых(подсказка: тМ("ship_days_ph"), текст: $срок, кнопка: тМ("set")) {
                let дни = срок.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !дни.isEmpty else {
                    ошибка = тМ("ship_days_enter")
                    return
                }
                правка(String(format: тМ("ship_days_sum"), дни), ["ship": ["days": дни]])
            }
        }
    }

    // Гарантия

    private var блокГарантии: some View {
        секция(тМ("warr_l")) {
            ПолеЛистаМассовых(подсказка: тМ("warr_ph"), текст: $гарантия, цифры: true, кнопка: тМ("set")) {
                let сырое = гарантия.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !сырое.isEmpty else {
                    ошибка = тМ("warr_enter")
                    return
                }
                var дней = Int(сырое) ?? 0
                дней = дней <= 0 ? 0 : max(3, min(365, дней))
                if !про && дней > 7 { дней = 7 }
                let описание = дней > 0 ? String(format: тМ("warr_done"), дней) : тМ("warr_off")
                правка(описание, ["warranty_days": дней])
            }
        }
    }

    // Склад и опт

    private var блокСклада: some View {
        секция(тМ("stock_l")) {
            ПолеЛистаМассовых(подсказка: тМ("stock_ph"), текст: $склад, цифры: true, кнопка: тМ("set")) {
                let сырое = склад.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !сырое.isEmpty else {
                    ошибка = тМ("stock_enter")
                    return
                }
                let штук = max(0, Int(сырое) ?? 0)
                правка(String(format: тМ("stock_done"), штук), ["stock": штук])
            }
            .padding(.bottom, 8)
            КнопкаЛистаМассовых(подпись: тМ("ws_off"), значок: "xmark") {
                правка(тМ("ws_off_done"), ["wholesale": false])
            }
        }
    }

    // Раздел магазина

    @ViewBuilder
    private var блокРаздела: some View {
        if let разделы = редактор.разделыМагазина {
            секция(тМ("sec_l")) {
                HStack(spacing: 8) {
                    Picker(тМ("sec_l"), selection: $раздел) {
                        Text(тМ("sec_none")).tag("")
                        ForEach(разделы.filter { !$0.id.isEmpty }, id: \.id) { р in
                            Text(р.название).tag(р.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЛистаМассовых(подпись: тМ("sec_assign"), значок: "checkmark", вид: .зелёная) {
                        let имя = разделы.first { $0.id == раздел }?.название ?? ""
                        let описание = раздел.isEmpty ? тМ("sec_cleared") : String(format: тМ("sec_sum"), имя)
                        правка(описание, ["shop_section": раздел])
                    }
                    .fixedSize()
                }
            }
        }
    }

    // Уточнить тип

    @ViewBuilder
    private var блокТипа: some View {
        if let у = редактор.уточнение {
            секция(тМ("ct_refine")) {
                Text(у.путь)
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.bottom, 6)
                HStack(spacing: 8) {
                    Picker(тМ("ct_refine"), selection: $тип) {
                        ForEach(у.варианты, id: \.ключ) { в in
                            Text(в.подпись).tag(в.ключ)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЛистаМассовых(подпись: тМ("ct_refine_apply"), значок: "checkmark", вид: .зелёная) {
                        guard !тип.isEmpty else {
                            ошибка = тМ("ct_pick_type")
                            return
                        }
                        let имя = у.варианты.first { $0.ключ == тип }?.подпись ?? тип
                        правка(String(format: тМ("ct_sum"), имя), ["category": тип])
                    }
                    .fixedSize()
                }
                Text(тМ("ct_refine_note"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        } else if !грузим {
            секция(тМ("ct_refine")) {
                Text(тМ("ct_refine_hint"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text(тМ("loading"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - «Таблицей» (advTableOpen)

/// Поля таблицы _ADVT_F сайта.
enum ПолеТаблицыМассовых: String, CaseIterable, Hashable {
    case цена, состояние, город, склад, гарантия

    var подпись: String {
        switch self {
        case .цена:      return тМ("f_price")
        case .состояние: return тМ("f_cond")
        case .город:     return тМ("f_city")
        case .склад:     return тМ("f_stock")
        case .гарантия:  return тМ("f_warr")
        }
    }

    /// Ключ поля в mass_edit_items.
    var ключ: String {
        switch self {
        case .цена:      return "price"
        case .состояние: return "condition"
        case .город:     return "city"
        case .склад:     return "stock"
        case .гарантия:  return "warranty_days"
        }
    }

    var число: Bool { self == .цена || self == .склад || self == .гарантия }
}

/// Строка таблицы: значения полей строками, как у полей ввода сайта (_advTblVal).
struct СтрокаТаблицыМассовых: Identifiable, Equatable {
    let id: String
    let название: String
    let фото: String
    var значения: [ПолеТаблицыМассовых: String]

    init(_ товар: МоёОбъявление) {
        id = товар.id
        название = товар.название
        фото = товар.фото
        let цена = Int(exactly: товар.цена.rounded(.towardZero)) ?? 0
        значения = [.цена: String(цена), .состояние: товар.состояние == "new" ? "new" : "used", .город: товар.город,
                    .склад: String(товар.склад), .гарантия: String(товар.гарантия)]
    }

    func значение(_ поле: ПолеТаблицыМассовых) -> String { значения[поле] ?? "" }

    /// _advTblDiff: только изменённые поля; число — целое ≥ 0, иначе поле пропускается.
    func правки(_ было: СтрокаТаблицыМассовых) -> [String: Any]? {
        var итог: [String: Any] = [:]
        for поле in ПолеТаблицыМассовых.allCases {
            let сейчас = значение(поле).trimmingCharacters(in: .whitespacesAndNewlines)
            guard сейчас != было.значение(поле) else { continue }
            if поле.число {
                guard let n = Int(сейчас), n >= 0 else { continue }
                итог[поле.ключ] = n
            } else {
                итог[поле.ключ] = сейчас
            }
        }
        return итог.isEmpty ? nil : итог
    }
}

struct ЛистТаблицыМассовых: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared
    @State private var строки: [СтрокаТаблицыМассовых] = []
    @State private var снимок: [String: СтрокаТаблицыМассовых] = [:]
    @State private var полеВсем: ПолеТаблицыМассовых = .цена
    @State private var значениеВсем = ""
    @State private var сообщение: String? = nil

    init() {}

    private var изменено: Int {
        строки.filter { с in снимок[с.id].flatMap { с.правки($0) } != nil }.count
    }

    var body: some View {
        ТелоЛистаМассовых(String(format: тМ("tbl_t"), строки.count)) {
            всемСразу
            ForEach($строки) { $строка in
                строкаТаблицы($строка)
            }
            низ
        }
        .onAppear {
            guard строки.isEmpty else { return }
            let новые = редактор.выбранные.map { СтрокаТаблицыМассовых($0) }
            строки = новые
            var с: [String: СтрокаТаблицыМассовых] = [:]
            for строка in новые { с[строка.id] = строка }
            снимок = с
        }
    }

    /// .air-bulk: «Всем сразу» — поле, значение, «Применить всем».
    private var всемСразу: some View {
        VStack(alignment: .leading, spacing: 8) {
            МеткаЛистаМассовых(тМ("tbl_all"))
            HStack(spacing: 8) {
                Picker(тМ("tbl_all"), selection: $полеВсем) {
                    ForEach(ПолеТаблицыМассовых.allCases, id: \.self) { п in
                        Text(п.подпись).tag(п)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.текст)
                if полеВсем == .состояние {
                    Picker(тМ("f_cond"), selection: $значениеВсем) {
                        Text(тМ("cond_used")).tag("used")
                        Text(тМ("cond_new")).tag("new")
                    }
                    .pickerStyle(.segmented)
                } else {
                    TextField(тМ("tbl_val"), text: $значениеВсем)
                        .font(.subheadline)
                        .keyboardType(полеВсем.число ? .numberPad : .default)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm,
                                                                           style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1.5)
                        }
                }
            }
            КнопкаЛистаМассовых(подпись: тМ("tbl_apply_all"), значок: "square.and.pencil") { применитьВсем() }
            if let сообщение {
                Text(сообщение)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(КраскаОбъявлений.хорошоТекст)
            }
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .padding(.bottom, 12)
        .onChange(of: полеВсем) { _, новое in
            значениеВсем = новое == .состояние ? "used" : ""
        }
    }

    private func применитьВсем() {
        let значение = значениеВсем.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in строки.indices { строки[i].значения[полеВсем] = значение }
        сообщение = String(format: тМ("tbl_set"), полеВсем.подпись, строки.count)
    }

    private func строкаТаблицы(_ строка: Binding<СтрокаТаблицыМассовых>) -> some View {
        let изменена = снимок[строка.wrappedValue.id].flatMap { строка.wrappedValue.правки($0) } != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                КартинкаЛенты(Config.url(строка.wrappedValue.фото), пунктов: 40) {
                    Theme.мята
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
                .accessibilityHidden(true)
                Text(строка.wrappedValue.название)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(ПолеТаблицыМассовых.allCases, id: \.self) { поле in
                    ячейка(поле, строка)
                }
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(изменена ? Theme.акцент : Theme.линия, lineWidth: изменена ? 1.5 : 1)
        }
        .padding(.bottom, 8)
    }

    private func ячейка(_ поле: ПолеТаблицыМассовых, _ строка: Binding<СтрокаТаблицыМассовых>) -> some View {
        let привязка = Binding<String>(
            get: { строка.wrappedValue.значение(поле) },
            set: { строка.wrappedValue.значения[поле] = $0 }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(поле.подпись)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
            if поле == .состояние {
                Picker(поле.подпись, selection: привязка) {
                    Text(тМ("cond_used")).tag("used")
                    Text(тМ("cond_new")).tag("new")
                }
                .pickerStyle(.segmented)
            } else {
                TextField(поле.подпись, text: привязка)
                    .font(.subheadline)
                    .keyboardType(поле.число ? .numberPad : .default)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 8)
                    .frame(minHeight: 34)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs,
                                                                        style: .continuous))
            }
        }
    }

    /// .advt-foot: «Изменено строк: N» и «Сохранить».
    private var низ: some View {
        HStack(spacing: 10) {
            let n = изменено
            Text(n > 0 ? String(format: тМ("tbl_changed"), n) : тМ("tbl_none"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, alignment: .leading)
            КнопкаЛистаМассовых(подпись: тМ("tbl_save"), значок: "checkmark", вид: .зелёная) { сохранить() }
                .fixedSize()
        }
        .padding(.top, 6)
    }

    private func сохранить() {
        var правки: [String: [String: Any]] = [:]
        for строка in строки {
            guard let было = снимок[строка.id], let п = строка.правки(было) else { continue }
            правки[строка.id] = п
        }
        guard !правки.isEmpty else {
            сообщение = тМ("tbl_nochange")
            return
        }
        редактор.сохранитьТаблицу(правки)
    }
}

// MARK: - «По расписанию» (pubqOpen)

/// Дни очереди: неделя от сегодня по Алматы (_pqWeek), ключ YYYY-MM-DD.
struct ДеньОчередиМассовых: Hashable {
    let ключ: String
    let подпись: String

    static func неделя() -> [ДеньОчередиМассовых] {
        let пояс = TimeZone(identifier: "Asia/Almaty") ?? TimeZone.current
        let ключи = DateFormatter()
        ключи.locale = Locale(identifier: "en_US_POSIX")
        ключи.timeZone = пояс
        ключи.dateFormat = "yyyy-MM-dd"
        let подписи = DateFormatter()
        подписи.locale = МоиОбъявленияText.локаль
        подписи.timeZone = пояс
        подписи.setLocalizedDateFormatFromTemplate("EEEd")
        let сейчас = Date()
        var итог: [ДеньОчередиМассовых] = []
        for i in 0..<7 {
            let дата = сейчас.addingTimeInterval(Double(i) * 86_400)
            let подпись: String
            switch i {
            case 0:  подпись = тМ("pq_today")
            case 1:  подпись = тМ("pq_tomorrow")
            default: подпись = подписи.string(from: дата)
            }
            итог.append(ДеньОчередиМассовых(ключ: ключи.string(from: дата), подпись: подпись))
        }
        return итог
    }
}

struct ЛистРасписанияМассовых: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared
    @State private var с = ЛистРасписанияМассовых.время(9, 0)
    @State private var по = ЛистРасписанияМассовых.время(22, 0)
    @State private var поСколько = 5
    @State private var каждые = 10
    @State private var дни: [ДеньОчередиМассовых] = ДеньОчередиМассовых.неделя()
    @State private var отмечены: Set<String> = Set(ДеньОчередиМассовых.неделя().map { $0.ключ })
    @State private var ошибка: String? = nil

    init() {}

    private static func время(_ часы: Int, _ минуты: Int) -> Date {
        Calendar.current.date(bySettingHour: часы, minute: минуты, second: 0, of: Date()) ?? Date()
    }

    private static func строка(_ дата: Date) -> String {
        let к = Calendar.current.dateComponents([.hour, .minute], from: дата)
        return String(format: "%02d:%02d", к.hour ?? 0, к.minute ?? 0)
    }

    private var сколько: Int { редактор.дляРасписания.count }

    var body: some View {
        ТелоЛистаМассовых(тМ("pq_title")) {
            Text(String(сколько) + " " + МассовыйРедакторФормы.слово(сколько))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .padding(.bottom, 14)
            ОшибкаЛистаМассовых(текст: ошибка)
            часы
            блокДней
            блокПоСколько
            блокКакЧасто
            кнопки
        }
    }

    private var часы: some View {
        VStack(alignment: .leading, spacing: 0) {
            МеткаЛистаМассовых(тМ("pq_hours"))
            HStack(spacing: 8) {
                DatePicker(тМ("pq_hours"), selection: $с, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text(verbatim: "—")
                    .foregroundStyle(Theme.текстВторой)
                DatePicker(тМ("pq_hours"), selection: $по, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 16)
    }

    private var блокДней: some View {
        VStack(alignment: .leading, spacing: 0) {
            МеткаЛистаМассовых(тМ("pq_days"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                ForEach(дни, id: \.self) { день in
                    чип(день.подпись, вкл: отмечены.contains(день.ключ)) {
                        if отмечены.contains(день.ключ) {
                            if отмечены.count > 1 {
                                отмечены.remove(день.ключ)
                            } else {
                                ошибка = тМ("pq_one_day")
                            }
                        } else {
                            отмечены.insert(день.ключ)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    private var блокПоСколько: some View {
        VStack(alignment: .leading, spacing: 0) {
            МеткаЛистаМассовых(тМ("pq_batch"))
            HStack(spacing: 8) {
                шаг("minus", подпись: тМ("pq_less")) { поСколько = max(1, поСколько - 1) }
                Text(String(поСколько))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
                    .frame(minWidth: 44)
                шаг("plus", подпись: тМ("pq_more_a")) { поСколько = min(5, поСколько + 1) }
            }
        }
        .padding(.bottom, 16)
    }

    private var блокКакЧасто: some View {
        VStack(alignment: .leading, spacing: 0) {
            МеткаЛистаМассовых(тМ("pq_every"))
            HStack(spacing: 6) {
                ForEach([10, 30, 60], id: \.self) { минут in
                    чип(String(минут) + " " + тМ("pq_min"), вкл: каждые == минут) { каждые = минут }
                }
            }
        }
        .padding(.bottom, 18)
    }

    private var кнопки: some View {
        HStack(spacing: 8) {
            КнопкаЛистаМассовых(подпись: тМ("pq_cancel")) { редактор.лист = nil }
            КнопкаЛистаМассовых(подпись: тМ("pq_go"), значок: "clock", вид: .зелёная) { поставить() }
        }
    }

    private func чип(_ подпись: String, вкл: Bool, нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            Text(подпись)
                .font(.footnote.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(вкл ? Theme.поверхность : Theme.текст)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(вкл ? Theme.акцент : Theme.поверхность,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(вкл ? Theme.акцент : Theme.линия, lineWidth: 1.5)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }

    private func шаг(_ значок: String, подпись: String, нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            Image(systemName: значок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .frame(width: 40, height: 40)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }

    /// _pqRead: одинаковые часы — 09:00–22:00; дни — отмеченные по порядку.
    private func поставить() {
        var от = Self.строка(с)
        var до = Self.строка(по)
        if от == до {
            от = "09:00"
            до = "22:00"
        }
        let выбранные = дни.filter { отмечены.contains($0.ключ) }
        guard !выбранные.isEmpty else {
            ошибка = тМ("pq_one_day")
            return
        }
        ошибка = nil
        редактор.спроситьРасписание(с: от, по: до, каждые: каждые, поСколько: поСколько,
                                    дни: выбранные.map { $0.ключ }, подписиДней: выбранные.map { $0.подпись })
    }
}

/// Склонение «объявление / объявления / объявлений» (_pqPlural сайта).
enum МассовыйРедакторФормы {
    static func слово(_ n: Int) -> String {
        let r = n % 10
        let h = n % 100
        if r == 1 && h != 11 { return тМ("pq_w1") }
        if r >= 2 && r <= 4 && (h < 10 || h >= 20) { return тМ("pq_w2") }
        return тМ("pq_w5")
    }
}

// MARK: - «Продвинуть» — несколько объявлений (только App Store)

struct ЛистПродвиженияМассовых: View {
    @ObservedObject private var редактор = МассовыйРедактор.shared

    init() {}

    private var список: [МоёОбъявление] { редактор.выбранные.filter { $0.статус == "approved" } }

    var body: some View {
        ТелоЛистаМассовых(String(format: тМ("promo_t"), список.count)) {
            Text(тМ("promo_note"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            ForEach(список) { товар in
                HStack(spacing: 10) {
                    Text(товар.название.isEmpty ? "#" + товар.id : товар.название)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЛистаМассовых(подпись: тМ("b_promote"), значок: "arrow.up", вид: .зелёная) {
                        ЛистУслугиApple.показать(.продвижение, цель: товар.id)
                    }
                    .fixedSize()
                }
                .padding(.vertical, 6)
                Divider()
            }
        }
    }
}
