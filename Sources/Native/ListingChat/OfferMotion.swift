import SwiftUI

/**
 ДВИЖЕНИЕ ТОРГА (владелец 07.10.2026: «на сайте была анимация при торге — сделай так же»; уточнение: «в торге был смайлик —
 грустный или весёлый»).

 Что у сайта (js/marketplace.js, css/marketplace.css, css/chat.css):
 • окно .mk-offer-sheet: подложка гаснет и проявляется за .25s, карточка .mk-offer-card выезжает снизу translateY(100%) → 0
   за .3s cubic-bezier(.2,.8,.2,1), уходит за 280 мс (mkOfferOpen / mkOfferClose) — у листа iOS это делает сам лист;
 • регулятор: значок «−N%», кромка бегунка и градиент кнопки отправки живут одним цветом --od-c (_mkOfferColor:
   зелёный → золото → красный по (скидка / 35)^1,6), кнопка — transition .15s, нажатие — scale(.98); подсказка «Потяните
   ползунок…» исчезает, как только тронули; цена, «экономия …» и «вы заплатите …» пересчитываются на каждом шаге;
 • ошибка выбора — встряска @keyframes mkVarShake: 0 → −5px (25 %) → +5px (75 %) → 0 за .4s;
 • новое на экране — @keyframes mkIn (translateY(8px), прозрачность, .24s ease) и mkSlide (translateY(60px), .3s);
 • при prefers-reduced-motion переписка .kc замирает: animation и transition — none.

 Смайлика в офлайн-копии сайта (29.09.2026) нет — ни в js, ни в css, ни в переводах; он сделан по слову владельца и
 по смыслу цвета сайта: «цвет = вероятность согласия» (комментарий к _mkOfferColor). Те же три точки — зелёный весёлый,
 золотой задумчивый, красный грустный; рот выгибается плавно вместе с ползунком, на смене настроения смайлик подпрыгивает.

 «Уменьшение движения» — без полёта и встряски: новое только проявляется, смайлик меняет лицо сразу. Лёгкий режим
 (РежимУстройства) — короче и проще: короткое проявление со сдвигом на 12, без пульса и встряски; вибрация остаётся.
 */
enum ДвижениеТорга {
    /// Новая карточка торга в переписке: пружина вместо mkSlide (.3s) — «прилетает» с полёта, а не всплывает.
    static let прилёт = Animation.spring(response: 0.42, dampingFraction: 0.76)
    /// Лёгкий режим — короткое проявление (mkIn .24s ease, чуть быстрее).
    static let прилётЛёгкий = Animation.easeOut(duration: 0.18)
    /// «Уменьшение движения» — только проявление.
    static let проявление = Animation.easeOut(duration: 0.2)
    /// Цвет скидки — transition .15s у .mk-offer-send.
    static let цвет = Animation.easeOut(duration: 0.15)
    /// Лицо смайлика следует за ползунком.
    static let лицо = Animation.spring(response: 0.3, dampingFraction: 0.72)
}

/// Чем закончился шаг торга: ждёт ответа, договорились, отказ или тихо погасло (заменено, отозвано, использовано).
enum ИсходТорга: Equatable {
    case ждёт
    case хорошо
    case плохо
    case тихо
}

// MARK: - Смайлик настроения продавца

/**
 Смайлик над ценой в окне «Предложить цену»: круг цвета скидки (_mkOfferColor), белые глаза и рот. Рот выгибается от
 улыбки (0 %) до грусти (−35 %) по той же кривой (скидка / 35)^1,6, что и цвет; на смене настроения — подпрыгивание.
 */
struct СмайликТорга: View {
    /// Скидка, 0…35.
    let скидка: Int
    let цвет: Color
    var размер: CGFloat = 38

    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @ObservedObject private var режим = РежимУстройства.shared

    /// 0 — весёлый, 1 — задумчивый, 2 — грустный.
    static func настроение(_ скидка: Int) -> Int {
        let e = доля(скидка)
        if e < 0.2 { return 0 }
        if e < 0.55 { return 1 }
        return 2
    }

    /// (скидка / 35)^1,6 — как у цвета.
    static func доля(_ скидка: Int) -> Double {
        pow(max(0, min(1, Double(скидка) / Double(ЛистПредложенияЦены.предел))), 1.6)
    }

    /// Ключ подписи под смайликом.
    static func подпись(_ скидка: Int) -> String {
        switch настроение(скидка) {
        case 0: return ListingChatText.т("mood_good")
        case 1: return ListingChatText.т("mood_mid")
        default: return ListingChatText.т("mood_bad")
        }
    }

    /// 1 — улыбка, −1 — грусть.
    private var изгиб: Double { 1 - 2 * Self.доля(скидка) }

    private var тихо: Bool { безДвижения || режим.лёгкий }

    var body: some View {
        лицо
            .animation(безДвижения ? nil : (режим.лёгкий ? Animation.easeOut(duration: 0.12) : ДвижениеТорга.лицо), value: скидка)
            .keyframeAnimator(initialValue: ПрыжокСмайлика(), trigger: Self.настроение(скидка)) { содержимое, шаг in
                содержимое
                    .scaleEffect(тихо ? 1 : шаг.масштаб)
                    .offset(y: тихо ? 0 : шаг.подъём)
                    .rotationEffect(.degrees(тихо ? 0 : шаг.наклон))
            } keyframes: { _ in
                KeyframeTrack(\.масштаб) {
                    CubicKeyframe(1.16, duration: 0.12)
                    CubicKeyframe(0.95, duration: 0.12)
                    CubicKeyframe(1, duration: 0.16)
                }
                KeyframeTrack(\.подъём) {
                    CubicKeyframe(-5, duration: 0.12)
                    CubicKeyframe(0, duration: 0.18)
                }
                KeyframeTrack(\.наклон) {
                    CubicKeyframe(-7, duration: 0.1)
                    CubicKeyframe(6, duration: 0.12)
                    CubicKeyframe(0, duration: 0.14)
                }
            }
            .frame(width: размер, height: размер)
            .accessibilityHidden(true)
    }

    private var лицо: some View {
        let s = размер
        return ZStack {
            Circle()
                .fill(цвет)
                .shadow(color: цвет.opacity(0.35), radius: 4, x: 0, y: 2)
            /* Глаза: у весёлого чуть прищурены (ниже), у грустного — круглые. */
            HStack(spacing: s * 0.2) {
                Capsule().fill(Color.white)
                Capsule().fill(Color.white)
            }
            .frame(width: s * 0.36, height: s * (0.13 + 0.05 * (1 - max(0, изгиб))))
            .offset(y: -s * 0.1)
            ФормаРтаСмайлика(изгиб: изгиб)
                .stroke(Color.white, style: StrokeStyle(lineWidth: max(2, s * 0.07), lineCap: .round))
                .frame(width: s, height: s)
        }
        .frame(width: s, height: s)
    }
}

/// Шаг прыжка смайлика (keyframeAnimator).
struct ПрыжокСмайлика {
    var масштаб: CGFloat = 1
    var подъём: CGFloat = 0
    var наклон: Double = 0
}

/// Рот: дуга от 30 % до 70 % ширины; изгиб 1 — улыбка вниз, −1 — грусть вверх. Анимируется плавно (animatableData).
struct ФормаРтаСмайлика: Shape {
    var изгиб: Double

    var animatableData: Double {
        get { изгиб }
        set { изгиб = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let y = rect.minY + h * (0.62 + 0.06 * max(0, -изгиб))
        var путь = Path()
        путь.move(to: CGPoint(x: rect.minX + w * 0.3, y: y))
        путь.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.7, y: y),
                          control: CGPoint(x: rect.minX + w * 0.5, y: y + h * 0.2 * изгиб))
        return путь
    }
}

// MARK: - Новая карточка торга в переписке

/**
 Карточка торга, пришедшая уже при открытом чате (своё предложение, встречная цена, «принято» / «отказ»), — прилетает:
 своё — снизу справа (оттуда, где было окно предложения), ответ продавца — слева с лёгким разворотом («перекидывание»),
 строка «принято» — снизу. Отказ после прилёта встряхивается (mkVarShake). Вибрация — по смыслу: договорились —
 «успех», отказ — «предупреждение», встречная — толчок, своё — лёгкий толчок.
 Карточки, что были в переписке при открытии, стоят на месте.
 */
struct ПоявлениеТорга: ViewModifier {
    enum Откуда {
        case справа
        case слева
        case снизу
    }

    let свежая: Bool
    let откуда: Откуда
    let исход: ИсходТорга
    let сыграно: () -> Void

    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @ObservedObject private var режим = РежимУстройства.shared
    @State private var видна: Bool
    @State private var толчок = 0
    @State private var встряска = 0

    init(свежая: Bool, откуда: Откуда, исход: ИсходТорга, сыграно: @escaping () -> Void) {
        self.свежая = свежая
        self.откуда = откуда
        self.исход = исход
        self.сыграно = сыграно
        _видна = State(initialValue: !свежая)
    }

    private var сдвиг: CGSize {
        if видна || безДвижения { return .zero }
        if режим.лёгкий { return CGSize(width: 0, height: 12) }
        switch откуда {
        case .справа: return CGSize(width: 36, height: 70)
        case .слева: return CGSize(width: -44, height: 10)
        case .снизу: return CGSize(width: 0, height: 24)
        }
    }

    private var масштаб: CGFloat {
        if видна || безДвижения || режим.лёгкий { return 1 }
        return 0.9
    }

    private var разворот: Double {
        if видна || безДвижения || режим.лёгкий { return 0 }
        return откуда == .слева ? 18 : 0
    }

    private var якорь: UnitPoint {
        switch откуда {
        case .справа: return .bottomTrailing
        case .слева: return .leading
        case .снизу: return .bottom
        }
    }

    private var анимация: Animation {
        if безДвижения { return ДвижениеТорга.проявление }
        return режим.лёгкий ? ДвижениеТорга.прилётЛёгкий : ДвижениеТорга.прилёт
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(разворот), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.6)
            .scaleEffect(масштаб, anchor: якорь)
            .offset(сдвиг)
            .opacity(видна ? 1 : 0)
            .встряскаТорга(встряска, можно: !безДвижения && !режим.лёгкий)
            .sensoryFeedback(trigger: толчок) { _, _ in
                switch исход {
                case .хорошо: return SensoryFeedback.success
                case .плохо: return SensoryFeedback.warning
                case .ждёт:
                    return откуда == .справа ? SensoryFeedback.impact(weight: .light)
                        : SensoryFeedback.impact(weight: .medium)
                case .тихо: return nil
                }
            }
            .onAppear {
                guard !видна else { return }
                сыграно()
                withAnimation(анимация) { видна = true }
                толчок += 1
                if исход == .плохо {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        встряска += 1
                    }
                }
            }
    }
}

// MARK: - Ответ на уже стоящей карточке

/**
 Карточка уже на экране, и её исход сменился (продавец принял, встречная принята, покупатель отказался): договорились —
 пульс (1 → 1,04 → 1) и «успех», отказ — встряска mkVarShake и «предупреждение». Смена содержимого — плавно (.22s).
 */
struct ОтветТорга: ViewModifier {
    let исход: ИсходТорга

    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @ObservedObject private var режим = РежимУстройства.shared
    @State private var пульс = 0
    @State private var встряска = 0

    private var тихо: Bool { безДвижения || режим.лёгкий }

    func body(content: Content) -> some View {
        content
            .animation(безДвижения ? nil : ДвижениеСайта.смена, value: исход)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: пульс) { содержимое, масштаб in
                содержимое.scaleEffect(тихо ? 1 : масштаб)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.04, duration: 0.14)
                    CubicKeyframe(0.99, duration: 0.14)
                    CubicKeyframe(1, duration: 0.16)
                }
            }
            .встряскаТорга(встряска, можно: !тихо)
            .sensoryFeedback(trigger: исход) { было, стало in
                guard было != стало else { return nil }
                switch стало {
                case .хорошо: return SensoryFeedback.success
                case .плохо: return SensoryFeedback.warning
                case .ждёт, .тихо: return nil
                }
            }
            .onChange(of: исход) { было, стало in
                guard было != стало else { return }
                if стало == .хорошо { пульс += 1 }
                if стало == .плохо { встряска += 1 }
            }
    }
}

// MARK: - Встряска mkVarShake

private struct ВстряскаТорга: ViewModifier {
    let повод: Int
    let можно: Bool

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: CGFloat(0), trigger: повод) { содержимое, сдвиг in
                содержимое.offset(x: можно ? сдвиг : 0)
            } keyframes: { _ in
                /* 0 → −5 (25 %) → +5 (75 %) → 0 за .4s. */
                KeyframeTrack {
                    LinearKeyframe(-5, duration: 0.1)
                    LinearKeyframe(5, duration: 0.2)
                    LinearKeyframe(0, duration: 0.1)
                }
            }
    }
}

extension View {
    /// Встряска mkVarShake сайта, когда меняется `повод`; можно == false — стоит на месте.
    func встряскаТорга(_ повод: Int, можно: Bool = true) -> some View {
        modifier(ВстряскаТорга(повод: повод, можно: можно))
    }

    /// Новая карточка торга в переписке прилетает (ПоявлениеТорга).
    func появлениеТорга(свежая: Bool, откуда: ПоявлениеТорга.Откуда, исход: ИсходТорга,
                        сыграно: @escaping () -> Void) -> some View {
        modifier(ПоявлениеТорга(свежая: свежая, откуда: откуда, исход: исход, сыграно: сыграно))
    }

    /// Исход карточки торга сменился на глазах — пульс или встряска (ОтветТорга).
    func ответТорга(_ исход: ИсходТорга) -> some View {
        modifier(ОтветТорга(исход: исход))
    }
}
