import SwiftUI
import UIKit

/**
 «ПОМЕСТИТСЯ ЛИ?» — РЕЖИМ «ВЕЩЬ»: ПЛАШКА НАД ЗАТВОРОМ (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ»). Модель —
 ВещьГабаритов (FitBoxItem.swift); ставит плашку ЭкранГабаритов (FitBoxScreen.swift) в низ окна в режиме «Вещь».

 Что сейчас на полу: «Загружаем 3D-модель…» / «Вырезаем вещь с фото…» (с колесом), «3D-модель ИИ», «Фото вещи в
 реальном размере» или «Вещь с фото не вырезалась — показана коробка»; под ней — честная пометка («3D-модель создана ИИ
 по фото — детали могут отличаться»). Окно всегда тёмное — цвета под камеру; шрифты — по «Размеру текста» (при крупном —
 до трёх строк с ужатием, чтобы затвор не уходил за экран); при «Уменьшении движения» колесо стоит; справа налево ряд
 разворачивается сам. Для VoiceOver — один элемент: подпись и пометка.
 */
struct ПлашкаВещиГабаритов: View {
    @ObservedObject var вещь: ВещьГабаритов
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.dynamicTypeSize) private var размерТекста

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var крупно: Bool { размерТекста.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                значок
                    .accessibilityHidden(true)
                Text(вещь.подпись)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(крупно ? 3 : nil)
                    .minimumScaleFactor(крупно ? 0.7 : 1)
                    .fixedSize(horizontal: false, vertical: !крупно)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(кайма.opacity(0.55), lineWidth: 1)
            }
            if let пометка = вещь.пометка {
                Text(пометка)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(крупно ? 2 : nil)
                    .minimumScaleFactor(крупно ? 0.7 : 1)
                    .shadow(color: Color.black.opacity(0.6), radius: 3)
            }
        }
        .frame(maxWidth: 520)
        .accessibilityElement(children: .combine)
        .animation(ДвижениеСайта.смена, value: вещь.состояние)
    }

    @ViewBuilder
    private var значок: some View {
        if вещь.грузится {
            SiteSpinner(размер: 16, толщина: 2, дорожка: Color.white.opacity(0.25), верх: Theme.шапкаМята, стоит: тихо)
        } else {
            Image(systemName: вещь.значок)
                .font(.footnote.weight(.bold))
                .foregroundStyle(кайма)
        }
    }

    /// Мятная — вещь стоит или готовится; янтарная — не вышло (стоит коробка).
    private var кайма: Color {
        вещь.состояние == .нет ? Color(uiColor: ЛинейкаГабаритов.янтарь) : Theme.шапкаМята
    }
}
