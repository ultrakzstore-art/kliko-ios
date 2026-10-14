import SwiftUI
import UIKit

/**
 БОЛЬШАЯ КНОПКА «ПРОДАТЬ» В НИЖНЕЙ ПАНЕЛИ (владелец 14.10.2026: «когда нажимаю камеру — сделай камеру на главном экране,
 где боттом бар, побольше, чтобы интереснее выглядел»).

 Было: зелёный круг 36 pt внутри капсулы панели — мелко и сухо. Стало — как у сайта (приподнятая зелёная круглая кнопка
 камеры с кромкой цвета панели), только крупнее: круг 58 pt выступает над капсулой на 24 pt (чуть больше трети — ниже
 он лёг бы на подпись), вокруг него — кромка 3,5 pt цвета панели (круг «врезан» в капсулу, а верх кромки продолжает её
 край), внутри — зелёный градиент Theme.кнопкаКамерыКонец → Начало (на iOS 26 поверх него ещё зелёное «жидкое
 стекло»), значок камеры 23 pt и белый кружок «+» в углу — сразу понятно, что это «создать». Подпись «Продать» — под
 кругом, внутри капсулы, на одной линии с подписями соседних пунктов (то же место значка 22 pt и тот же отступ 3 pt).

 Подача: раз в ~4 с от круга расходится и гаснет мягкое кольцо (ОреолКнопкиПродать — отдельный маленький вид: меняет
 только масштаб и прозрачность своего слоя, между волнами кадров нет), при первом показе за запуск по кругу один раз
 пробегает блик (БликКнопкиПродать), нажатие — пружинка и средний толчок (.impact medium). «Уменьшение движения» и
 лёгкий режим (РежимУстройства) — ни ореола, ни блика; в лёгком режиме и стекла на iOS 26 нет, тени короче.

 Где стоит: в ряду панели — пустое место ширины кнопки (МестоКнопкиПродать) с якорем рамки; сама кнопка встаёт на это
 место слоем поверх стеклянной капсулы (кнопкаПродатьПоверх). Так выступающий круг не зависит от того, обрезает ли
 стекло своё содержимое, и край капсулы не ложится поверх круга, а пункты и их ширины — прежние. Место под панелью у
 корней вкладок (НижняяПанельСайта.высота) — рамка 64 pt и выступ круга: плашки, панель сравнения и пилюля «Связаться»
 над панелью встают над кругом, он их не закрывает. Зона нажатия — всё место в ряду (68 × 58 pt) и круг над ним;
 соседних пунктов она не касается.
 */
struct КнопкаПродатьПанели: View {
    /// Ширина места в ряду панели: круг с кромкой (65 pt) и зазор по бокам — зона нажатия шире 60 pt.
    static let ширина: CGFloat = 68
    /// Зелёный круг.
    static let круг: CGFloat = 58
    /// Кромка цвета панели вокруг круга.
    static let кромка: CGFloat = 3.5
    /// Круг вместе с кромкой.
    static var снаружи: CGFloat { круг + кромка * 2 }
    /// Центр круга от верха капсулы: низ круга — на 34 pt, над подписью «Продать» (её строка начинается с 35 pt).
    static let центр: CGFloat = 5
    /// Насколько круг с кромкой выступает над капсулой (27,5 pt) — на столько дальше уезжает спрятанная панель.
    static var выступ: CGFloat { снаружи / 2 - центр }

    let действие: () -> Void
    /// Панель уехала при прокрутке — ореол не дышит.
    let спрятана: Bool

    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @Environment(\.colorScheme) private var схема
    /// Лёгкий режим (DeviceMode.swift): без ореола, блика и стекла, тени короче.
    @ObservedObject private var режим = РежимУстройства.shared
    /// Средний толчок под пальцем — по счётчику нажатий.
    @State private var нажатий = 0

    init(действие: @escaping () -> Void, спрятана: Bool) {
        self.действие = действие
        self.спрятана = спрятана
    }

    var body: some View {
        Button {
            нажатий += 1
            действие()
        } label: {
            ярлык
        }
        .buttonStyle(НажатиеКнопкиПродать(якорь: UnitPoint(x: 0.5, y: Self.центр / НижняяПанельСайта.высотаКапсулы)))
        .sensoryFeedback(.impact(weight: .medium), trigger: нажатий)
        .accessibilityLabel(DesignText.т("sell"))
        .accessibilityHint(Config.нативнаяПодача ? КнопкаПродатьText.т("hint") : DesignText.т("on_site"))
        /* Слой поверх капсулы идёт в дереве после ряда — VoiceOver читает «Продать» третьей, как она стоит
           (у пунктов ряда порядок 5, 4, 2, 1 — НижняяПанельСайта.порядокПункта). */
        .accessibilitySortPriority(3)
        /* Подписи панели не растут с размером текста — при крупном тексте долгое нажатие покажет крупную подпись. */
        .accessibilityShowsLargeContentViewer {
            Label(DesignText.т("sell"), systemImage: "camera.fill")
        }
    }

    /// Ореол и блик — только когда можно двигаться: без «Уменьшения движения» и не в лёгком режиме.
    private var живой: Bool {
        !безДвижения && !режим.лёгкий
    }

    private var тёмная: Bool {
        схема == .dark
    }

    /// Место в ряду: подпись — как у соседних пунктов (место значка 22 pt, отступ 3 pt, рамка 48 pt по центру капсулы),
    /// круг — фоном сверху, со сдвигом вверх за край капсулы. Подпись рисуется поверх кромки круга.
    private var ярлык: some View {
        VStack(spacing: 3) {
            Color.clear
                .frame(height: 22)
            Text(DesignText.т("sell"))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(width: Self.ширина, height: НижняяПанельСайта.высотаКапсулы - 10)
        .frame(height: НижняяПанельСайта.высотаКапсулы)
        .contentShape(Rectangle())
        .background(alignment: .top) {
            круг
                .offset(y: Self.центр - Self.снаружи / 2)
        }
    }

    private var круг: some View {
        ZStack {
            if живой && !спрятана {
                ОреолКнопкиПродать(размер: Self.снаружи)
            }
            кромкаКруга
            зелёныйКруг
                .overlay {
                    if живой {
                        БликКнопкиПродать(размер: Self.круг)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    плюс
                }
        }
        .frame(width: Self.снаружи, height: Self.снаружи)
    }

    /// Кромка цвета панели: круг «врезан» в капсулу; верх кромки продолжает край капсулы и гаснет к её линии.
    private var кромкаКруга: some View {
        Circle()
            .fill(Theme.панель)
            .overlay {
                Circle()
                    .strokeBorder(Theme.панельКромка.opacity(тёмная ? 0.6 : 0.4), lineWidth: 0.8)
                    .mask {
                        LinearGradient(colors: [Color.black, Color.clear], startPoint: .top,
                                       endPoint: UnitPoint(x: 0.5, y: 0.42))
                    }
            }
            .shadow(color: Color.black.opacity(тёмная ? 0.4 : 0.1), radius: режим.лёгкий ? 3 : 8, x: 0, y: -2)
            .frame(width: Self.снаружи, height: Self.снаружи)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var зелёныйКруг: some View {
        if #available(iOS 26.0, *) {
            if режим.лёгкий {
                плоскийКруг
            } else {
                стеклянныйКруг
            }
        } else {
            плоскийКруг
        }
    }

    private var значок: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 23, weight: .semibold))
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.18), radius: 1.5, x: 0, y: 1)
            .frame(width: Self.круг, height: Self.круг)
    }

    /// iOS 17–25 и лёгкий режим: градиент, мягкий блик слева сверху и светлый край — объём без стекла.
    private var плоскийКруг: some View {
        значок
            .background {
                ZStack {
                    Circle()
                        .fill(Self.градиент)
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.26), Color.white.opacity(0)],
                                             center: UnitPoint(x: 0.32, y: 0.2), startRadius: 0,
                                             endRadius: Self.круг * 0.55))
                    Circle()
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.08)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: 1)
                }
            }
            .shadow(color: Theme.кнопкаКамерыНачало.opacity(0.45), radius: режим.лёгкий ? 4 : 10, x: 0, y: 4)
    }

    /// iOS 26: зелёное «жидкое стекло» с откликом на касание поверх того же градиента — зелёный сочный на любом фоне.
    @available(iOS 26.0, *)
    private var стеклянныйКруг: some View {
        значок
            .glassEffect(.regular.tint(Theme.кнопкаКамерыНачало).interactive(), in: Circle())
            .background(Self.градиент, in: Circle())
            .shadow(color: Theme.кнопкаКамерыНачало.opacity(0.45), radius: 10, x: 0, y: 4)
    }

    /// Белый кружок «+» в углу круга — «создать»: центр на краю круга под 45°, вокруг — кромка цвета панели.
    private var плюс: some View {
        Image(systemName: "plus")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.меткаНовое)
            .frame(width: 18, height: 18)
            .background(Color.white, in: Circle())
            .padding(2)
            .background(Theme.панель, in: Circle())
            .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
            .padding(.top, -2.5)
            .padding(.trailing, -2.5)
            .accessibilityHidden(true)
    }

    /// Кнопка камеры сайта: linear-gradient(135deg, …) от светлого зелёного к тёмному.
    private static let градиент = LinearGradient(colors: [Theme.кнопкаКамерыКонец, Theme.кнопкаКамерыНачало],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Нажатие «Продать»: круг сжимается к своему центру (не к середине места в ряду), отпустили — пружинка обратно.
/// При «Уменьшении движения» — то же лёгкое сжатие, что у пунктов панели, без пружины.
private struct НажатиеКнопкиПродать: ButtonStyle {
    let якорь: UnitPoint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1, anchor: якорь)
            .animation(configuration.isPressed ? ДвижениеСайта.нажатие
                                               : (ДвижениеСайта.пружинкаПродать ?? ДвижениеСайта.нажатие),
                       value: configuration.isPressed)
    }
}

/**
 «Дыхание» кнопки «Продать»: кольцо выходит из-под кромки, расходится до 1,42 и гаснет за 1,6 с, потом пауза — волна
 раз в ~4 с. В покое кольцо того же размера, что круг с кромкой, и спрятано под ней — сброс между волнами не виден.
 Меняются только масштаб и прозрачность этого слоя; панель и круг не пересчитываются.
 */
private struct ОреолКнопкиПродать: View {
    let размер: CGFloat
    @State private var волна = false

    var body: some View {
        Circle()
            .fill(Theme.кнопкаКамерыКонец.opacity(0.16))
            .overlay {
                Circle()
                    .strokeBorder(Theme.кнопкаКамерыКонец.opacity(0.6), lineWidth: 2)
            }
            .frame(width: размер, height: размер)
            .scaleEffect(волна ? 1.42 : 1)
            .opacity(волна ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task { await дышать() }
    }

    /// Первая волна — после блика; дальше раз в 4 с, пока кнопка на экране (ушла — задача отменяется сама).
    @MainActor
    private func дышать() async {
        try? await Task.sleep(for: .seconds(1.6))
        while !Task.isCancelled {
            волна = false
            /* Сброс и новая волна — в разных кадрах, иначе SwiftUI сольёт их в одно изменение без движения. */
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
            withAnimation(ДвижениеСайта.ореолПродать) { волна = true }
            try? await Task.sleep(for: .seconds(4))
        }
    }
}

/**
 Блик по кругу «Продать»: светлая полоса один раз пробегает наискосок при первом показе панели за запуск. При запуске
 панель закрыта загрузочным экраном (SitePreloader), пока у ленты нет первых данных (ЗаставкаЗапуска), но не дольше
 8 с, — блик ждёт его ухода, иначе пробежал бы под ним.
 */
private struct БликКнопкиПродать: View {
    let размер: CGFloat
    @State private var прошёл = false
    @ObservedObject private var заставка = ЗаставкаЗапуска.shared
    /// Блик уже пробегал за этот запуск — у следующих копий панели (экран категорий, возврат панели) его нет.
    private static var был = false

    var body: some View {
        LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55), Color.white.opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
            .frame(width: размер * 0.38, height: размер * 1.6)
            .rotationEffect(.degrees(20))
            .offset(x: (прошёл ? 1.1 : -1.1) * размер)
            .frame(width: размер, height: размер)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: заставка.данныеЕсть) { await пробежать() }
    }

    /// Пришли первые данные — задача начинается заново (прежняя, ждавшая 8 с, отменяется) и блик бежит, когда
    /// загрузочный экран растает.
    @MainActor
    private func пробежать() async {
        guard !Self.был else { return }
        if заставка.данныеЕсть {
            try? await Task.sleep(for: .milliseconds(900))
        } else {
            try? await Task.sleep(for: .seconds(8))
        }
        if Task.isCancelled || Self.был { return }
        Self.был = true
        withAnimation(ДвижениеСайта.бликПродать) { прошёл = true }
    }
}

// MARK: - Место в ряду панели

/// Место кнопки «Продать» в ряду панели: якорь его рамки — по нему кнопка встаёт слоем поверх капсулы.
struct КлючМестаКнопкиПродать: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Пустое место кнопки «Продать» в ряду панели (ширина кнопки, высота капсулы) — для VoiceOver его нет.
struct МестоКнопкиПродать: View {
    var body: some View {
        Color.clear
            .frame(width: КнопкаПродатьПанели.ширина, height: НижняяПанельСайта.высотаКапсулы)
            .anchorPreference(key: КлючМестаКнопкиПродать.self, value: .bounds) { $0 }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Кнопка «Продать» слоем поверх капсулы панели — ровно на МестоКнопкиПродать; без действия кнопки нет.
    func кнопкаПродатьПоверх(_ действие: (() -> Void)?, спрятана: Bool) -> some View {
        overlayPreferenceValue(КлючМестаКнопкиПродать.self) { место in
            GeometryReader { рамка in
                if let место, let действие {
                    КнопкаПродатьПанели(действие: действие, спрятана: спрятана)
                        .frame(width: рамка[место].width, height: рамка[место].height)
                        .position(x: рамка[место].midX, y: рамка[место].midY)
                }
            }
        }
    }
}

// MARK: - Движение кнопки

extension ДвижениеСайта {
    /// «Продать» отпустили — пружинка обратно; при «Уменьшении движения» — nil (возврат без пружины).
    static var пружинкаПродать: Animation? { мягко(.spring(response: 0.34, dampingFraction: 0.5)) }
    /// Волна ореола «Продать»: расходится и гаснет за 1,6 с.
    static var ореолПродать: Animation? { мягко(.easeOut(duration: 1.6)) }
    /// Блик по кругу «Продать» при первом показе.
    static var бликПродать: Animation? { мягко(.easeInOut(duration: 0.9)) }
}
