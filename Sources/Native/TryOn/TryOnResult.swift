import SwiftUI
import UIKit

/**
 ПРИМЕРОЧНАЯ — ШАГ 3 «ИТОГ» (владелец 13.10.2026).

 Шторка «Вы / В вещи»: результат и фото человека лежат друг на друге (сервер отдаёт тот же кадр и пропорции,
 docs/SERVER_TRYON.md §4), слева от ручки — вы, справа — в вещи. При появлении шторка сама проезжает справа налево и
 встаёт посередине — человек сразу видит себя в вещи; дальше тянет ручку пальцем. VoiceOver — регулируемый элемент
 (смахнуть вверх/вниз — шторка на 10 %). Ниже: пометка, что картинка от ИИ, «Сохранить в Фото», «Поделиться», «Ещё
 раз» и «Удалить фото» (с вопросом). Прокрутки нет — палец на шторке не спорит с ней.
 */
struct ШагИтогаПримерочной: View {
    @ObservedObject var модель: МодельПримерочной
    let закрыть: () -> Void
    @State private var вопросУдалить = false

    init(модель: МодельПримерочной, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: т("to_title"), закрыть: закрыть)
            if let итог = модель.итог {
                ШторкаПримерочной(до: модель.фотоЧеловека, после: итог)
                    .frame(maxWidth: 520, maxHeight: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .layoutPriority(1)
            } else {
                Spacer(minLength: 0)
            }
            Text(т("to_result_note"))
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 10)
            действия
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(т("to_delete_q"), isPresented: $вопросУдалить, titleVisibility: .visible) {
            Button(т("to_delete_yes"), role: .destructive) { модель.удалить() }
            Button(т("to_cancel"), role: .cancel) {}
        }
    }

    private var действия: some View {
        VStack(spacing: 10) {
            ЗелёнаяКнопкаФото(заголовок: т("to_save"), значок: "square.and.arrow.down") {
                модель.сохранить()
            }
            .disabled(модель.сохраняем)
            .opacity(модель.сохраняем ? 0.6 : 1)
            HStack(spacing: 10) {
                малаяКнопка(т("to_share"), значок: "square.and.arrow.up") { модель.поделиться() }
                малаяКнопка(т("to_again"), значок: "arrow.counterclockwise") { модель.ещёРаз() }
            }
            Button {
                вопросУдалить = true
            } label: {
                Label(т("to_delete"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(uiColor: Theme.hex(0xF87171)))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
            .disabled(модель.удаляем)
        }
    }

    private func малаяКнопка(_ заголовок: String, значок: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото())
    }
}

// MARK: - Шторка «Вы / В вещи»

/// Два кадра друг на друге: слева от ручки — фото человека (до), справа — результат (после). Пропорции — результата.
struct ШторкаПримерочной: View {
    let до: UIImage?
    let после: UIImage
    @State private var доля: CGFloat = 1
    @State private var показана = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(до: UIImage?, после: UIImage) {
        self.до = до
        self.после = после
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// Ширина к высоте результата; странные числа — в разумных пределах.
    private var пропорция: CGFloat {
        let размер = после.size
        guard размер.width > 0, размер.height > 0 else { return 0.75 }
        return max(0.4, min(1.6, размер.width / размер.height))
    }

    var body: some View {
        GeometryReader { место in
            let ш = место.size.width
            let в = место.size.height
            ZStack(alignment: .topLeading) {
                Image(uiImage: после)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ш, height: в)
                    .clipped()
                if let до {
                    Image(uiImage: до)
                        .resizable()
                        .scaledToFill()
                        .frame(width: ш, height: в)
                        .clipped()
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: ш * доля)
                        }
                }
                метки(ширина: ш)
                ручка(высота: в)
                    .offset(x: ш * доля - 22)
            }
            .frame(width: ш, height: в)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { жест in
                        guard ш > 0 else { return }
                        доля = min(1, max(0, жест.location.x / ш))
                    }
            )
        }
        .aspectRatio(пропорция, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Theme.зелёныйЯркий.opacity(0.18), radius: 24, x: 0, y: 8)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("to_compare_a11y"))
        .accessibilityValue(String(format: т("to_compare_value"), Int((доля * 100).rounded())))
        .accessibilityHint(т("to_compare_hint"))
        .accessibilityAdjustableAction { куда in
            switch куда {
            case .increment:
                доля = min(1, доля + 0.1)
            case .decrement:
                доля = max(0, доля - 0.1)
            @unknown default:
                break
            }
        }
        .onAppear { открыть() }
    }

    /// «Вы» слева вверху, «В вещи» справа вверху; метка гаснет, когда её половину закрыла шторка.
    private func метки(ширина: CGFloat) -> some View {
        HStack {
            метка(т("to_you"))
                .opacity(доля > 0.18 ? 1 : 0)
            Spacer(minLength: 8)
            метка(т("to_in_item"))
                .opacity(доля < 0.82 ? 1 : 0)
        }
        .padding(12)
        .frame(width: ширина)
        .animation(ДвижениеСайта.выбор, value: доля > 0.18)
        .animation(ДвижениеСайта.выбор, value: доля < 0.82)
        .allowsHitTesting(false)
    }

    private func метка(_ текст: String) -> some View {
        Text(текст)
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.5), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
    }

    /// Белая черта во всю высоту и круглая ручка со стрелками посередине. Ширина места — 44 (палец).
    private func ручка(высота: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: высота)
                .shadow(color: Color.black.opacity(0.45), radius: 4)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.панельСвязиКонец)
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
                .overlay { Circle().strokeBorder(Theme.зелёныйЯркий, lineWidth: 2) }
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 3)
                .scaleEffect(показана ? 1 : 0.6)
        }
        .frame(width: 44, height: высота)
        .allowsHitTesting(false)
    }

    /// Шторка сама проезжает справа налево (виден результат целиком) и встаёт посередине.
    private func открыть() {
        guard !показана else { return }
        guard !тихо else {
            доля = 0.5
            показана = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeInOut(duration: 0.9)) { доля = 0 }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { показана = true }
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { доля = 0.5 }
        }
    }
}
