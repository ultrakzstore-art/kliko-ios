import ActivityKit
import SwiftUI
import WidgetKit

/// Бренд-зелёный (зеркалит Theme.green2; в расширении Theme недоступен — задаём локально).
private let kGreen = Color(red: 0.10, green: 0.62, blue: 0.41)

/// Этапы курьера, которые плашка умеет рисовать. Ключи — из deal_live_courier() в inc/deal_live.php.
private let kCourierPhases: Set<String> = ["search", "to_seller", "at_seller", "to_buyer", "at_buyer", "delivered", "returning"]

@available(iOS 16.1, *)
struct DealLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DealActivityAttributes.self) { context in
            // ── Экран блокировки / баннер ──
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // ── Dynamic Island ──
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    KlikoLogo(size: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title)
                            .font(.caption2).foregroundStyle(.gray).lineLimit(1)
                        Text(context.state.statusText)
                            .font(.footnote).bold().foregroundStyle(.white).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if let phase = courierPhase(context.state) {
                            CourierRoute(phase: phase)
                            if let car = context.state.courier, !car.isEmpty {
                                Label(car, systemImage: "car.fill")
                                    .font(.caption2).foregroundStyle(.gray).lineLimit(1)
                            }
                        } else {
                            ProgressBar(step: context.state.stepIndex, total: context.state.stepsTotal)
                            if !context.state.etaText.isEmpty {
                                Text(context.state.etaText).font(.caption2).foregroundStyle(.gray)
                            }
                        }
                    }
                }
            } compactLeading: {
                KlikoLogo(size: 20)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                KlikoLogo(size: 20)
            }
            // Карточка сделок кабинета: параметр go (s= кабинет не читает).
            .widgetURL(URL(string: "https://kliko.kz/cabinet.php?go=deals"))
            .keylineTint(kGreen)
        }
    }
}

/// Этап курьера, если он есть и плашка его знает.
private func courierPhase(_ s: DealActivityAttributes.ContentState) -> String? {
    guard let p = s.phase, kCourierPhases.contains(p) else { return nil }
    return p
}

/// Время прибытия курьера, если оно известно.
private func arrival(_ s: DealActivityAttributes.ContentState) -> Date? {
    guard courierPhase(s) != nil, let t = s.etaAt, t > 0 else { return nil }
    return Date(timeIntervalSince1970: t)
}

// MARK: - Логотип
/// Логотип Kliko — та же картинка, что иконка приложения (WidgetSources/Assets.xcassets/KlikoLogo),
/// а не символ из системного набора (владелец 14.09.2026: «логотип как у приложения, а не дичь из свг»).
/// Плашка на экране блокировки должна узнаваться как Kliko с одного взгляда.
private struct KlikoLogo: View {
    let size: CGFloat
    var body: some View {
        Image("KlikoLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}

// MARK: - Экран блокировки
@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<DealActivityAttributes>

    var body: some View {
        let state = context.state
        let phase = courierPhase(state)
        HStack(alignment: .top, spacing: 12) {
            KlikoLogo(size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text(state.amountText)
                        .font(.subheadline.weight(.bold)).foregroundStyle(kGreen)
                }
                HStack(spacing: 6) {
                    Text(state.statusText)
                        .font(.footnote.weight(phase == nil ? .regular : .semibold))
                        .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let eta = arrival(state) {
                        Text(eta, style: .time)
                            .font(.footnote.weight(.bold)).foregroundStyle(kGreen).monospacedDigit()
                    }
                }
                if let phase {
                    CourierRoute(phase: phase)
                } else {
                    ProgressBar(step: state.stepIndex, total: state.stepsTotal)
                }
                HStack {
                    if phase != nil, let car = state.courier, !car.isEmpty {
                        Label(car, systemImage: "car.fill")
                            .font(.caption2).foregroundStyle(.gray).lineLimit(1)
                    } else {
                        Text(context.attributes.role == "seller" ? "Покупатель: \(state.counterpart)"
                                                                 : "Продавец: \(state.counterpart)")
                            .font(.caption2).foregroundStyle(.gray).lineLimit(1)
                    }
                    Spacer()
                    if let eta = arrival(state) {
                        Countdown(to: eta)
                    } else if !state.etaText.isEmpty {
                        Text(state.etaText).font(.caption2).foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Dynamic Island: время справа
@available(iOS 16.1, *)
private struct CompactTrailing: View {
    let state: DealActivityAttributes.ContentState
    var body: some View {
        if let eta = arrival(state) {
            Text(eta, style: .time)
                .font(.caption2).bold().foregroundStyle(kGreen).monospacedDigit()
        } else if state.stepsTotal > 0 {
            Text("\(state.stepIndex)/\(state.stepsTotal)")
                .font(.caption2).bold().foregroundStyle(kGreen)
        }
    }
}

@available(iOS 16.1, *)
private struct ExpandedTrailing: View {
    let state: DealActivityAttributes.ContentState
    var body: some View {
        if let eta = arrival(state) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(eta, style: .time)
                    .font(.caption).bold().foregroundStyle(kGreen).monospacedDigit()
                Countdown(to: eta)
            }
        } else {
            Text(state.amountText)
                .font(.caption).bold().foregroundStyle(.white)
        }
    }
}

/// Обратный отсчёт до прибытия. Системный таймер плашка крутит сама, без пушей.
/// Время уже прошло — не показываем ничего: «-3:10» читается как поломка.
private struct Countdown: View {
    let to: Date
    var body: some View {
        let now = Date()
        if to > now {
            Text(timerInterval: now...to, countsDown: true)
                .font(.caption2).foregroundStyle(.gray).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 64, alignment: .trailing)
        }
    }
}

// MARK: - Дорога курьера: продавец → покупатель, машина по этапу
private struct CourierRoute: View {
    let phase: String

    /// Где машина на дороге от продавца (0) до покупателя (1).
    private var progress: CGFloat {
        switch phase {
        case "search":    return 0.0
        case "to_seller": return 0.08
        case "at_seller": return 0.18
        case "to_buyer":  return 0.58
        case "at_buyer":  return 0.9
        case "delivered": return 1.0
        case "returning": return 0.4
        default:          return 0.0
        }
    }
    private var carSymbol: String {
        switch phase {
        case "search":    return "magnifyingglass"
        case "delivered": return "checkmark.circle.fill"
        case "returning": return "arrow.uturn.backward"
        default:          return "car.fill"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bag.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(progress >= 0.18 ? kGreen : Color.gray)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
                    Capsule().fill(kGreen).frame(width: max(4, w * progress), height: 4)
                    Image(systemName: carSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .offset(x: min(max(0, w * progress - 8), max(0, w - 16)))
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            Image(systemName: "house.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(phase == "delivered" ? kGreen : Color.gray)
        }
    }
}

// MARK: - Прогресс сделки (сегменты по шагам)
private struct ProgressBar: View {
    let step: Int
    let total: Int
    var body: some View {
        GeometryReader { geo in
            if total > 1 {
                let gap: CGFloat = 4
                let w = (geo.size.width - gap * CGFloat(total - 1)) / CGFloat(total)
                HStack(spacing: gap) {
                    ForEach(0..<total, id: \.self) { i in
                        Capsule()
                            .fill(i < step ? kGreen : Color.white.opacity(0.22))
                            .frame(width: max(w, 2), height: 4)
                    }
                }
            } else {
                Capsule().fill(Color.white.opacity(0.22)).frame(height: 4)
            }
        }
        .frame(height: 4)
    }
}
