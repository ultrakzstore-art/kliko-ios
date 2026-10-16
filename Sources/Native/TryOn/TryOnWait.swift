import SwiftUI
import UIKit

/**
 ПРИМЕРОЧНАЯ — ШАГ 2 «ПРИМЕРЯЕМ…» (владелец: «мощная анимированная подача», «летает»).

 Сцена: фото человека слева и фото вещи справа разлетелись и сходятся к центру — вещь ложится на человека; по фото
 человека бежит светлая линия сканера, за ними дышит зелёное свечение, над ними мерцают искры. Ниже — крупные проценты
 (цифры перекатываются), подпись этапа сменяется по ходу («Снимаем мерки…», «Подбираем посадку…», «Кладём свет…»,
 «Последние штрихи…»; в очереди — «Ждём очереди…»), полоса с бегущим бликом и «Отменить». Всё движение — одна
 TimelineView от времени появления: сходятся плавно (кубическое замедление), плывут по синусу. При «Уменьшении
 движения» шкала стоит: карточки сразу вместе, без линии и блика.
 */
struct ШагОжиданияПримерочной: View {
    @ObservedObject var модель: МодельПримерочной
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var начало = Date()

    init(модель: МодельПримерочной) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    /// Лёгкий режим (слабое железо, энергосбережение, перегрев) — сцена стоит, как при «Уменьшении движения».
    @ObservedObject private var режим = РежимУстройства.shared

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            сцена
                .frame(maxWidth: 460)
                .frame(height: 320)
                .accessibilityHidden(true)
            Text(модель.вид.заголовокОжидания)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .padding(.top, 18)
                .accessibilityAddTraits(.isHeader)
            проценты
                .padding(.top, 2)
            этап
                .padding(.top, 2)
            ПолосаПримерочной(доля: CGFloat(модель.прогресс) / 100, тихо: тихо)
                .frame(maxWidth: 320)
                .padding(.top, 14)
                .padding(.horizontal, 40)
                .accessibilityHidden(true)
            Text(т("to_wait_sub"))
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
                .padding(.horizontal, 36)
            Spacer(minLength: 16)
            Button(т("to_cancel")) { модель.отменить() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .onAppear { начало = Date() }
    }

    // MARK: Проценты и этап

    private var проценты: some View {
        Text(String(модель.прогресс) + "%")
            .font(.system(size: 48, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(LinearGradient(colors: [Color.white, Theme.шапкаМята], startPoint: .top,
                                            endPoint: .bottom))
            .contentTransition(.numericText())
            .animation(ДвижениеСайта.прогресс, value: модель.прогресс)
            .accessibilityLabel(String(format: т("to_progress_a11y"), модель.прогресс))
    }

    private var ключЭтапа: String {
        if модель.вОчереди && модель.прогресс < 5 { return "to_stage_queue" }
        switch модель.прогресс {
        case ..<30: return "to_stage_1"
        case ..<60: return "to_stage_2"
        case ..<88: return "to_stage_3"
        default: return "to_stage_4"
        }
    }

    /// Подпись этапа въезжает снизу и уходит прозрачностью.
    private var этап: some View {
        ZStack {
            Text(т(ключЭтапа))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .id(ключЭтапа)
                .transition(тихо ? AnyTransition.opacity
                                 : AnyTransition.asymmetric(insertion: AnyTransition.move(edge: .bottom)
                                                                .combined(with: AnyTransition.opacity),
                                                            removal: AnyTransition.opacity))
        }
        .frame(height: 22)
        .clipped()
        .animation(ДвижениеСайта.смена, value: ключЭтапа)
    }

    // MARK: Сцена

    private var сцена: some View {
        /* 30 кадров в секунду, а не частота экрана (на ProMotion — 120): плавание, пульс и сканер на глаз те же, а
           пересчётов сцены вчетверо меньше, пока идёт примерка. */
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: тихо)) { шкала in
            let t = тихо ? 10 : шкала.date.timeIntervalSince(начало)
            GeometryReader { место in
                кадр(t: t, размер: место.size)
            }
        }
    }

    /// Кубическое замедление: быстро в начале, мягко у цели.
    private static func плавно(_ x: Double) -> CGFloat {
        let ч = min(1, max(0, x))
        return CGFloat(1 - pow(1 - ч, 3))
    }

    private func кадр(t: Double, размер: CGSize) -> some View {
        let ширина = min(размер.width, 460)
        let ширинаЧеловека: CGFloat = ширина * 0.46
        let человек = CGSize(width: ширинаЧеловека, height: min(размер.height * 0.94, ширинаЧеловека * 4 / 3))
        let вещь = CGSize(width: ширина * 0.32, height: ширина * 0.32)
        let c = Self.плавно((t - 0.15) / 1.3)
        let плыть = CGFloat(sin(t * 1.6)) * 4
        let скан = CGFloat(t.truncatingRemainder(dividingBy: 2.2) / 2.2)
        let пульс = CGFloat(sin(t * 2.2))
        let хЧеловека: CGFloat = -ширина * (0.27 * (1 - c) + 0.07 * c)
        let хВещи: CGFloat = ширина * (0.3 * (1 - c) + 0.15 * c)
        let уВещи: CGFloat = человек.height * (0.3 - 0.1 * c) - плыть * c
        let уголЧеловека: Double = -10 + 7 * Double(c)
        let уголВещи: Double = 16 - 9 * Double(c)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.зелёныйЯркий.opacity(0.5), Color.clear], center: .center,
                                     startRadius: 4, endRadius: ширина * 0.5))
                .frame(width: ширина, height: ширина)
                .scaleEffect(1 + 0.05 * пульс)
                .opacity(0.35 + 0.55 * Double(c))
            карточкаЧеловека(размер: человек, скан: скан)
                .rotationEffect(.degrees(уголЧеловека))
                .offset(x: хЧеловека, y: плыть * c)
            карточкаВещи(размер: вещь)
                .scaleEffect(1 - 0.1 * c)
                .rotationEffect(.degrees(уголВещи))
                .offset(x: хВещи, y: уВещи)
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.шапкаМята)
                .shadow(color: Theme.зелёныйЯркий, radius: 10)
                .scaleEffect(0.9 + 0.15 * пульс)
                .offset(x: ширина * 0.1, y: -человек.height * 0.46)
                .opacity(Double(c))
        }
        .frame(width: размер.width, height: размер.height)
    }

    /// Фото человека с бегущей линией сканера (без движения — без линии).
    private func карточкаЧеловека(размер: CGSize, скан: CGFloat) -> some View {
        ZStack(alignment: .top) {
            if let фото = модель.фотоЧеловека {
                Image(uiImage: фото)
                    .resizable()
                    .scaledToFill()
                    .frame(width: размер.width, height: размер.height)
                    .clipped()
            } else {
                Color.white.opacity(0.08)
            }
            if !тихо {
                LinearGradient(colors: [Theme.зелёныйЯркий.opacity(0), Theme.зелёныйЯркий.opacity(0.35),
                                        Color.white.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 46)
                    .offset(y: скан * (размер.height + 46) - 46)
            }
        }
        .frame(width: размер.width, height: размер.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
        }
        .shadow(color: Color.black.opacity(0.5), radius: 16, x: 0, y: 8)
    }

    private func карточкаВещи(размер: CGSize) -> some View {
        ZStack {
            Color.white
            if let вещь = модель.фотоВещи {
                Image(uiImage: вещь)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.панельСвязиНачало)
            }
        }
        .frame(width: размер.width, height: размер.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2.5)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Полоса хода

/// Полоса хода примерки: тёмная дорожка, зелёная заливка по доле и бегущий по заливке блик.
struct ПолосаПримерочной: View {
    let доля: CGFloat
    let тихо: Bool

    init(доля: CGFloat, тихо: Bool) {
        self.доля = доля
        self.тихо = тихо
    }

    var body: some View {
        GeometryReader { место in
            let ширина = место.size.width * min(1, max(0.02, доля))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.зелёныйЯркий, Theme.шапкаМята],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: ширина)
                    .overlay {
                        if !тихо {
                            /* 30 кадров в секунду и одним слоем (drawingGroup): блик и так обрезан по полосе. */
                            TimelineView(.animation(minimumInterval: 1.0 / 30)) { шкала in
                                let t = шкала.date.timeIntervalSinceReferenceDate
                                let фаза = CGFloat(t.truncatingRemainder(dividingBy: 1.4) / 1.4)
                                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.55),
                                                        Color.white.opacity(0)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 44)
                                    .offset(x: фаза * (ширина + 44) - 44)
                                    .frame(width: ширина, alignment: .leading)
                                    .drawingGroup()
                            }
                            .clipShape(Capsule())
                        }
                    }
                    .animation(ДвижениеСайта.прогресс, value: доля)
            }
        }
        .frame(height: 8)
        .environment(\.layoutDirection, .leftToRight)
    }
}
