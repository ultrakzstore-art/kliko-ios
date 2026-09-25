import SwiftUI
import UIKit

/**
 УДОБСТВО ЧАТА — ЭТАП 17 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующие этапы»).

 Детали переписки (ChatThreadView), которые без приложения-мессенджера кажутся мелочью, а без них переписка раздражает:
   · кнопка «вниз» — когда переписка прокручена вверх; пришли новые, пока человек читает старое, — не дёргаем экран,
     а ставим на кнопку число новых;
   · «Копировать» в меню текстового сообщения (долгое нажатие) и тем же действием для VoiceOver;
   · «потяни — обновится» — один внеочередной опрос dm.php poll, сверх обычного раза в три секунды.
 Черновики — ЧерновикиЧата (ChatDrafts.swift). Рубильник — Config.удобныйЧат.
 */

extension ЧатСообщение {
    /// Что можно скопировать: только текст. Фото и голосовое в пузыре — подпись приложения («📷 Фото»), а не слова
    /// собеседника.
    var копируемое: Bool {
        тип == "text" && !текст.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Буфер обмена для сообщений.
@MainActor
enum ЧатБуфер {
    static func скопировать(_ текст: String) {
        UIPasteboard.general.string = текст
        /* Системной плашки «Скопировано» у iOS нет: зрячий видит, что меню закрылось, а VoiceOver скажем словами. */
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: ChatComfortText.т("copied"))
        }
    }
}

/// Круглая кнопка «к последним сообщениям» над правым нижним углом переписки; число — сколько новых пришло ниже.
struct КнопкаВнизЧата: View {
    let новых: Int
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Config.дизайнКакНаСайте ? Theme.акцент : Theme.green2)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
                .overlay {
                    /* Этап 31: в виде сайта — кромка цвета линии сайта, в тёмной теме она заметнее системной. */
                    Circle().strokeBorder(Config.дизайнКакНаСайте ? Theme.линия : Color(.separator), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.15), radius: 6, y: 2)
                .overlay(alignment: .top) {
                    if новых > 0 {
                        Text(verbatim: новых > 99 ? "99+" : String(новых))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Config.дизайнКакНаСайте ? Theme.непрочитано : Theme.green, in: Capsule())
                            .offset(y: -10)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подписьДляГолоса)
    }

    private var подписьДляГолоса: String {
        let вниз = ChatComfortText.т("down")
        guard новых > 0 else { return вниз }
        return вниз + ", " + String(format: ChatComfortText.т("new_below"), новых)
    }
}

/// «Потяни — обновится» у переписки — только при включённом рубильнике; выключенный — ScrollView как был.
struct ОбновлениеПереписки: ViewModifier {
    let модель: ChatThreadModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if Config.удобныйЧат {
            content.refreshable { await модель.обновить() }
        } else {
            content
        }
    }
}

/// «Копировать» для VoiceOver: пузырь читается одной фразой (children: .ignore), и меню долгого нажатия внутри него
/// VoiceOver не видит — даём то же действие всему сообщению. nil — сообщение не текстовое, действия нет.
struct КопироватьДляГолоса: ViewModifier {
    let текст: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let текст {
            content.accessibilityAction(named: Text(ChatComfortText.т("copy"))) {
                ЧатБуфер.скопировать(текст)
            }
        } else {
            content
        }
    }
}
