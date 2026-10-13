import SwiftUI
import UIKit

/**
 ИИ-СТУДИЯ ФОТО ПОДАЧИ — ВХОДЫ (владелец 13.10.2026: «свой редактор фото для техники через ИИ»).

 Готовые части для шага «Фото» (PostingSteps.swift: ШагФото и ПлиткаФотоВид) — сам шаг их ставит:
   · ПунктСтудииФото — «Студия» (со значком искр) в меню плитки фото;
   · ЗначокСтудииПлитки — круглая кнопка с искрами в углу плитки (как «✕» в другом углу);
   · ПлашкаСтудииФото — «Сделать как в каталоге — ✨ Студия» над фото для разделов техники (электроника, телефоны,
     компьютеры, бытовая техника): один раз на подачу — закрыл или воспользовался студией, больше не появится;
   · студияФотоПодачи(модель:плитка:) — полноэкранная студия для выбранной плитки.
 Студия доступна для плитки, которая уже обработана и не грузится сейчас (ПодачаМодель.студияДоступна).
 */

/// Пункт меню плитки фото — открыть студию.
struct ПунктСтудииФото: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(СтудияФотоText.т("st_menu"), systemImage: "sparkles", action: действие)
    }
}

/// Кнопка с искрами в углу плитки фото (26 × 26, как «✕» плитки).
struct ЗначокСтудииПлитки: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
                .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(СтудияФотоText.т("st_open"))
    }
}

/**
 Плашка над фото техники: значок искр в зелёном круге, «Сделать как в каталоге», под ним — что будет; справа —
 «✨ Студия», в углу — «✕». По плашке пробегает мягкий блик (при «Уменьшении движения» — нет).
 */
struct ПлашкаСтудииФото: View {
    @ObservedObject var модель: ПодачаМодель
    let открыть: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var скрыта = false
    @State private var блик = false

    init(модель: ПодачаМодель, открыть: @escaping (UUID) -> Void) {
        self.модель = модель
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { СтудияФотоText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        if !скрыта, let плитка = модель.плиткаДляПлашкиСтудии {
            карточка(плитка.id)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func карточка(_ id: UUID) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return ZStack(alignment: .topTrailing) {
            Button {
                ОткликСайта.выбор()
                открыть(id)
            } label: {
                содержимое
                    .padding(.vertical, 12)
                    .padding(.leading, 12)
                    .padding(.trailing, 34)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(фон, in: форма)
                    .overlay { отблеск.clipShape(форма) }
                    .overlay { форма.strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.28), lineWidth: 1) }
                    .contentShape(форма)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            Button {
                ОригиналыСтудииФото.shared.закрытьПлашку(модель)
                withAnimation(ДвижениеСайта.уход) { скрыта = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 22, height: 22)
                    .background(КраскаПодачи.карточка.opacity(0.8), in: Circle())
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("st_hide"))
        }
        .onAppear {
            guard !тихо else { return }
            блик = true
        }
    }

    private var содержимое: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("st_banner_t"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(т("st_banner_s"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Text("✨ " + т("st_banner_btn"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Theme.зелёный, in: Capsule())
        }
    }

    private var фон: LinearGradient {
        LinearGradient(colors: [КраскаПодачи.хорошоФон, КраскаПодачи.карточка], startPoint: .topLeading,
                       endPoint: .bottomTrailing)
    }

    private static let бегБлика = Animation.easeInOut(duration: 1.6).delay(1.4).repeatForever(autoreverses: false)

    /// Блик: светлая косая полоса раз в три секунды проходит слева направо.
    private var отблеск: some View {
        GeometryReader { г in
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.35), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 70)
                .rotationEffect(.degrees(18))
                .offset(x: блик ? г.size.width + 80 : -150)
                .animation(блик ? Self.бегБлика : nil, value: блик)
        }
        .opacity(тихо ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Плитка, открытая в студии (fullScreenCover(item:) нужен Identifiable).
struct ВыборСтудииФото: Identifiable, Equatable {
    let id: UUID
}

/// Показ студии поверх шага: плитка не nil — студия открыта; «✕», «Готово» или «Вернуть» — снова nil.
struct ПоказСтудииФото: ViewModifier {
    let модель: ПодачаМодель
    @Binding var плитка: UUID?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: выбор) { выбранная in
                ЭкранСтудииФото(подача: модель, плитка: выбранная.id, закрыть: { плитка = nil })
            }
    }

    private var выбор: Binding<ВыборСтудииФото?> {
        Binding(get: { плитка.map { ВыборСтудииФото(id: $0) } },
                set: { плитка = $0?.id })
    }
}

extension View {
    /// Полноэкранная ИИ-студия для плитки фото подачи; `плитка` — id открытой плитки или nil.
    func студияФотоПодачи(модель: ПодачаМодель, плитка: Binding<UUID?>) -> some View {
        modifier(ПоказСтудииФото(модель: модель, плитка: плитка))
    }
}
