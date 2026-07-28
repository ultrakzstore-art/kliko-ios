import ActivityKit
import SwiftUI
import WidgetKit

/// Бренд-зелёный (зеркалит Theme.green2; в расширении Theme недоступен — задаём локально).
private let kGreen = Color(red: 0.10, green: 0.62, blue: 0.41)
private let kGreenDeep = Color(red: 0.06, green: 0.32, blue: 0.20)

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
                    brandIcon.padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.amountText)
                        .font(.caption).bold().foregroundStyle(.white)
                        .padding(.trailing, 4)
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
                        ProgressBar(step: context.state.stepIndex, total: context.state.stepsTotal)
                        if !context.state.etaText.isEmpty {
                            Text(context.state.etaText).font(.caption2).foregroundStyle(.gray)
                        }
                    }
                }
            } compactLeading: {
                brandIcon
            } compactTrailing: {
                if context.state.stepsTotal > 0 {
                    Text("\(context.state.stepIndex)/\(context.state.stepsTotal)")
                        .font(.caption2).bold().foregroundStyle(kGreen)
                }
            } minimal: {
                brandIcon
            }
            .widgetURL(URL(string: "https://kliko.kz/cabinet.php?s=deals"))
            .keylineTint(kGreen)
        }
    }

    private var brandIcon: some View {
        Image(systemName: "shield.lefthalf.filled")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(kGreen)
    }
}

// MARK: - Экран блокировки
@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<DealActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [kGreen, kGreenDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                    Text(context.state.amountText)
                        .font(.subheadline.weight(.bold)).foregroundStyle(kGreen)
                }
                Text(context.state.statusText)
                    .font(.footnote).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                ProgressBar(step: context.state.stepIndex, total: context.state.stepsTotal)
                HStack {
                    Text(context.attributes.role == "seller" ? "Покупатель: \(context.state.counterpart)"
                                                             : "Продавец: \(context.state.counterpart)")
                        .font(.caption2).foregroundStyle(.gray).lineLimit(1)
                    Spacer()
                    if !context.state.etaText.isEmpty {
                        Text(context.state.etaText).font(.caption2).foregroundStyle(.gray)
                    }
                }
            }
        }
        .padding(14)
    }
}

// MARK: - Прогресс сделки (сегменты по шагам)
@available(iOS 16.1, *)
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
