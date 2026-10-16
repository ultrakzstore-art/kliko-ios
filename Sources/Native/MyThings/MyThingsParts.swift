import SwiftUI
import UIKit

/**
 «МОЁ» — ОБЩИЕ ЧАСТИ ЭКРАНОВ (владелец: «удобно для глаз, ровная схема везде, мощная анимированная подача, летает на
 всех девайсах»).

 Вид — как у кабинета: поверхность сайта, радиус md, тень карточки сайта (теньКарточкиСайта), нажатие сайта 98 %,
 шапка — зелёный градиент шапки главной с мятным акцентом. Здесь:
   · ПрофильМоего — три профиля: значок, краска, название, цель стека;
   · КольцоМоего — кольцо прогресса: дорастает пружиной один раз при показе, дальше — ДвижениеСайта.прогресс,
     процент сменяется перекатом (numericText);
   · ШапкаМоего — общий прогресс крупным кольцом, «Моё», капсула-замок и один проход блика за запуск;
   · КарточкаПрофиляМоего — ровно 96 pt: значок, название, сводка, чип следующего шага, кольцо;
   · ПоявлениеМоего — каскад хаба (подъём 12 → 0, проявление, 0,97 → 1), один раз на показ экрана;
   · ПереходМоего — в стеке кабинета через переходКабинета (без дублей), в окне поверх — NavigationLink;
   · ЧипМоего, ПолеЧислаМоего, КарточкаМоегоКабинета — в MyThingsControls.swift.
 «Уменьшение движения» и лёгкий режим (РежимУстройства): без полёта, блика и пульса — значения встают сразу. Шрифты
 карточек фиксированные, как у плиток кабинета (высота не меняется), а поля и тексты экранов растут с «Размером текста».
 */

// MARK: - Профили

enum ПрофильМоего: Int, CaseIterable, Identifiable {
    case гараж
    case устройства
    case тело

    var id: Int { rawValue }

    var значок: String {
        switch self {
        case .гараж: return "car.side"
        case .устройства: return "iphone.gen3"
        case .тело: return "figure.stand"
        }
    }

    var цвет: Color {
        switch self {
        case .гараж: return Theme.акцент
        case .устройства: return Theme.цвет(0x1677C9, 0x5AB0F5)
        case .тело: return Theme.оранжевый
        }
    }

    var название: String {
        switch self {
        case .гараж: return МоёText.т("my_garage")
        case .устройства: return МоёText.т("my_devices")
        case .тело: return МоёText.т("my_body")
        }
    }

    /// Подпись пустого профиля.
    var пусто: String {
        switch self {
        case .гараж: return МоёText.т("my_garage_empty")
        case .устройства: return МоёText.т("my_devices_empty")
        case .тело: return МоёText.т("my_body_empty")
        }
    }

    var цель: КабинетЦель {
        switch self {
        case .гараж: return .мойГараж
        case .устройства: return .моиУстройства
        case .тело: return .моиМерки
        }
    }

    func прогресс(_ запись: ЗаписьМоего) -> ПрогрессМоего {
        switch self {
        case .гараж: return запись.прогрессГаража
        case .устройства: return запись.прогрессУстройств
        case .тело: return запись.прогрессТела
        }
    }
}

// MARK: - Кольцо

/// Кольцо прогресса: дорожка и дуга от верха по часовой; внутри — процент (по желанию).
struct КольцоМоего: View {
    let доля: Double
    var размер: CGFloat
    var толщина: CGFloat
    var номер: Int
    var цвет: Color
    var дорожка: Color
    var цветТекста: Color
    var процент: Bool
    var шрифт: CGFloat
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var показано: Double = 0
    @State private var начато = false

    init(доля: Double, размер: CGFloat = 36, толщина: CGFloat = 4, номер: Int = 0, цвет: Color = Theme.акцент,
         дорожка: Color = Theme.линия, цветТекста: Color = Theme.текст, процент: Bool = true, шрифт: CGFloat = 10) {
        self.доля = доля
        self.размер = размер
        self.толщина = толщина
        self.номер = номер
        self.цвет = цвет
        self.дорожка = дорожка
        self.цветТекста = цветТекста
        self.процент = процент
        self.шрифт = шрифт
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    var body: some View {
        ZStack {
            Circle()
                .stroke(дорожка, lineWidth: толщина)
            Circle()
                .trim(from: 0, to: min(1, max(0, показано)))
                .stroke(цвет, style: StrokeStyle(lineWidth: толщина, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if процент {
                Text(показано, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: шрифт, weight: .heavy).monospacedDigit())
                    .foregroundStyle(цветТекста)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: показано))
                    .padding(толщина + 1)
            }
        }
        .frame(width: размер, height: размер)
        .accessibilityHidden(true)
        .onAppear {
            guard !начато else { return }
            начато = true
            if тихо {
                показано = доля
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15 + 0.05 * Double(номер))) {
                    показано = доля
                }
            }
        }
        .onChange(of: доля) { _, новая in
            withAnimation(тихо ? nil : ДвижениеСайта.прогресс) { показано = новая }
        }
    }
}

/// Процент словами для текстов («76 %» по правилам языка телефона).
enum ПроцентМоего {
    static func текст(_ доля: Double) -> String {
        min(1, max(0, доля)).formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK: - Значок профиля

/// Значок 20 pt в цветном квадрате 44 (радиус 12): краска профиля на её же 14 %.
struct ЗначокПрофиляМоего: View {
    let значок: String
    let цвет: Color
    var фон: Color?
    var размер: CGFloat

    init(значок: String, цвет: Color, фон: Color? = nil, размер: CGFloat = 44) {
        self.значок = значок
        self.цвет = цвет
        self.фон = фон
        self.размер = размер
    }

    var body: some View {
        Image(systemName: значок)
            .font(.system(size: размер * 0.45, weight: .semibold))
            .foregroundStyle(цвет)
            .frame(width: размер, height: размер)
            .background(фон ?? цвет.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Карточка профиля

/// Карточка профиля хаба: ровно 96 pt — значок, название 16/heavy, сводка 13 серым (до двух строк), чип следующего
/// шага, справа кольцо 36 pt. Для VoiceOver — один элемент: «название, заполнено N, следующий шаг».
struct КарточкаПрофиляМоего: View {
    let профиль: ПрофильМоего
    let сводка: String
    let прогресс: ПрогрессМоего
    let номер: Int

    init(профиль: ПрофильМоего, сводка: String, прогресс: ПрогрессМоего, номер: Int) {
        self.профиль = профиль
        self.сводка = сводка
        self.прогресс = прогресс
        self.номер = номер
    }

    private var текстШага: String {
        прогресс.шаг.map { МоёText.т($0) } ?? МоёText.т("my_all_set")
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        HStack(spacing: 12) {
            ЗначокПрофиляМоего(значок: профиль.значок, цвет: профиль.цвет)
            VStack(alignment: .leading, spacing: 3) {
                Text(профиль.название)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(сводка)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
                чипШага
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            КольцоМоего(доля: прогресс.доля, размер: 36, толщина: 4, номер: номер + 1, цвет: профиль.цвет)
            СтрелкаСтрокиКабинета()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        .contentShape(форма)
        .animation(ДвижениеСайта.смена, value: прогресс.шаг)
        .animation(ДвижениеСайта.смена, value: сводка)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(профиль.название + ". " + String(format: МоёText.т("my_ready"), ПроцентМоего.текст(прогресс.доля))
                            + ". " + текстШага)
        .accessibilityAddTraits(.isButton)
    }

    /// «＋ Снимите машину сбоку»; всё заполнено — «✓ Всё заполнено». Смена — проявлением и лёгким сжатием.
    private var чипШага: some View {
        HStack(spacing: 4) {
            Image(systemName: прогресс.шаг == nil ? "checkmark" : "plus")
                .font(.system(size: 9, weight: .heavy))
            Text(текстШага)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(Theme.акцент)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.оттенокАкцента, in: Capsule())
        .id(прогресс.шаг ?? "done")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - Шапка хаба

/// Один проход блика по шапке хаба за запуск.
@MainActor
enum ПодачаМоего {
    static var бликСыгран = false
}

/// Шапка хаба: градиент шапки главной, крупное кольцо общего прогресса, «Моё», подпись и капсула-замок «Только на
/// этом телефоне». Дошло до 100 % — печать подпрыгивает и «успех» под пальцем, один раз.
struct ШапкаМоего: View {
    let доля: Double
    let всё: Bool
    @State private var прыжки = 0

    init(доля: Double, всё: Bool) {
        self.доля = доля
        self.всё = всё
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.шапка, style: .continuous)
        HStack(alignment: .center, spacing: 16) {
            КольцоМоего(доля: доля, размер: 76, толщина: 7, цвет: Theme.шапкаМята, дорожка: Color.white.opacity(0.15),
                        цветТекста: Color.white, шрифт: 18)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(МоёText.т("my_title"))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .accessibilityAddTraits(.isHeader)
                    if всё {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.шапкаМята)
                            .symbolEffect(.bounce, value: прыжки)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityLabel(МоёText.т("my_all_set"))
                    }
                }
                Text(МоёText.т("my_sub"))
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                замок
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .clipShape(форма)
        }
        .overlay {
            БликМоего()
                .clipShape(форма)
        }
        .animation(ДвижениеСайта.смена, value: всё)
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(format: МоёText.т("my_ready"), ПроцентМоего.текст(доля)))
        .onChange(of: всё) { было, стало in
            guard стало && !было else { return }
            // «Уменьшение движения» и лёгкий режим — печать не прыгает, как и остальное «Моё».
            if !(ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий) { прыжки += 1 }
            ОткликСайта.успех()
        }
    }

    private var замок: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .bold))
                .accessibilityHidden(true)
            Text(МоёText.т("my_local_short"))
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.шапкаМятаТекст)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.шапкаМята, in: Capsule())
    }
}

/// Блик по шапке хаба: полоса белого 22 % под 18°, один проход за запуск; при «Уменьшении движения» и в лёгком режиме
/// его нет. В арабском идёт справа налево.
struct БликМоего: View {
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var идёт: Bool
    @State private var сдвиг: CGFloat = -1

    init() {
        _идёт = State(initialValue: !ПодачаМоего.бликСыгран)
    }

    var body: some View {
        if идёт && !безДвижения && !режим.лёгкий && !ДвижениеСайта.тихо {
            GeometryReader { место in
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.22), Color.white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: место.size.width * 0.45, height: место.size.height * 1.6)
                    .rotationEffect(.degrees(18))
                    .position(x: место.size.width / 2 + сдвиг * место.size.width * 1.2, y: место.size.height / 2)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .flipsForRightToLeftLayoutDirection(true)
            .onAppear {
                guard сдвиг < 1 else { return }
                ПодачаМоего.бликСыгран = true
                withAnimation(ДвижениеСайта.мягко(.easeInOut(duration: 0.9).delay(0.35))) { сдвиг = 1 }
            }
        }
    }
}

// MARK: - Каскад появления

/// Шаг каскада хаба: подъём 12 → 0, проявление, 0,97 → 1 от верха; spring(0.5, 0.86), задержка 0,05 · номер. Один раз
/// на показ экрана (своё @State): возврат с экрана профиля не повторяет.
@MainActor
struct ПоявлениеМоего: ViewModifier {
    let номер: Int
    @State private var видно: Bool

    init(номер: Int) {
        self.номер = номер
        _видно = State(initialValue: ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий)
    }

    func body(content: Content) -> some View {
        content
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 12)
            .scaleEffect(видно ? 1 : 0.97, anchor: .top)
            .onAppear {
                guard !видно else { return }
                let пружина = Animation.spring(response: 0.5, dampingFraction: 0.86).delay(0.05 * Double(номер))
                withAnimation(ДвижениеСайта.мягко(пружина)) { видно = true }
            }
    }
}

extension View {
    /// Шаг каскада хаба «Моё»: шапка 0, карточки 1–3, низ 4.
    @MainActor
    func появлениеМоего(_ номер: Int) -> some View {
        modifier(ПоявлениеМоего(номер: номер))
    }

    /// Карточка экранов «Моего»: поверхность сайта, радиус md, тень карточки, поля 16.
    func карточкаМоего(поля: CGFloat = 16) -> some View {
        self
            .padding(поля)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .теньКарточкиСайта(радиус: Theme.Радиус.md)
    }

    /// Над клавиатурой — «Готово»: поле теряет фокус и само принимает набранное.
    func клавиатураМоего() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(МоёText.т("my_done")) {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil,
                                                    for: nil)
                }
            }
        }
    }
}

// MARK: - Переход

/// Переход на экран «Моего»: в стеке кабинета — переходКабинета (без дублей, как СсылкаКабинета), в окне поверх —
/// NavigationLink(value:). Своей стрелки нет — её рисует метка.
struct ПереходМоего<Метка: View>: View {
    let цель: КабинетЦель
    @ViewBuilder let метка: () -> Метка
    @Environment(\.переходКабинета) private var перейти

    init(цель: КабинетЦель, @ViewBuilder метка: @escaping () -> Метка) {
        self.цель = цель
        self.метка = метка
    }

    var body: some View {
        if let перейти {
            Button {
                перейти(цель)
            } label: {
                метка()
            }
            .buttonStyle(НажатиеСайта())
        } else {
            NavigationLink(value: цель) {
                метка()
            }
            .buttonStyle(НажатиеСайта())
        }
    }
}

// MARK: - Заголовок раздела

/// «ПАРАМЕТРЫ КОЛЁС»: значок и подпись прописными акцентом — заголовок карточки.
struct ЗаголовокМоего: View {
    let текст: String
    let значок: String

    init(_ текст: String, значок: String) {
        self.текст = текст
        self.значок = значок
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.акцент)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
