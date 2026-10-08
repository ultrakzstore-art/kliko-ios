import SwiftUI

/**
 ОФЛАЙН-РЕЖИМ — ОБЩИЕ ЧАСТИ ЭКРАНОВ (владелец 08.10.2026).

 ПлашкаБезСети — «Нет сети — показана сохранённая версия» над экраном, где показана копия с диска (избранное, «Мои
 объявления», «Мои сделки», карточка сделки, «Чат» и переписки). Краска — --tint-warn кабинета (ИнбоксКраска.внимание…),
 как полоса «Подключитесь, чтобы ответить лично». Карточкой — над списком; полосой во всю ширину — под шапкой переписки.

 ОблакоВОчереди — своё сообщение из очереди исходящих (OutboxQueue.swift): облако моей стороны, бледнее обычного, под
 ним часики «Ждёт отправки»; не ушло — красное «Не отправлено — нажмите, чтобы повторить». Долгое нажатие — «Повторить»
 и «Удалить».
 */
struct ПлашкаБезСети: View {
    /// Когда легла копия — «Сохранено 3 часа назад» второй строкой; nil — без неё.
    let когда: Date?
    /// Полосой во всю ширину (под шапкой переписки), а не карточкой.
    let полоса: Bool

    init(когда: Date? = nil, полоса: Bool = false) {
        self.когда = когда
        self.полоса = полоса
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(OfflineText.т("offline_copy"))
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let когда {
                    Text(String(format: OfflineText.т("saved_ago"), OfflineText.когда(когда)))
                        .font(.system(size: 12))
                        .opacity(0.85)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ИнбоксКраска.вниманиеТекст)
        .padding(.horizontal, полоса ? 14 : 12)
        .padding(.vertical, полоса ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { фон }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var фон: some View {
        if полоса {
            ИнбоксКраска.вниманиеФон
                .overlay(alignment: .bottom) { ИнбоксКраска.вниманиеКромка.frame(height: 1) }
        } else {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .fill(ИнбоксКраска.вниманиеФон)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(ИнбоксКраска.вниманиеКромка, lineWidth: 1)
                }
        }
    }
}

struct ОблакоВОчереди: View {
    let сообщение: ИсходящееСообщение
    /// Краска своего облака этого чата: переписка кабинета — --kc-acc, чат объявления — пузырь витрины.
    let цвет: Color
    let повторить: () -> Void
    let удалить: () -> Void

    init(сообщение: ИсходящееСообщение, цвет: Color = ИнбоксКраска.облакоМоё, повторить: @escaping () -> Void,
         удалить: @escaping () -> Void) {
        self.сообщение = сообщение
        self.цвет = цвет
        self.повторить = повторить
        self.удалить = удалить
    }

    private var неУшло: Bool { сообщение.состояние == .неУшло }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                Text(сообщение.текст)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(цвет.opacity(сообщение.состояние == .ушло ? 1 : 0.6), in: форма)
                    .overlay {
                        if неУшло {
                            форма.stroke(ИнбоксКраска.плохоКромка, lineWidth: 1.5)
                        }
                    }
                статус
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if неУшло { повторить() } }
        .contextMenu {
            if неУшло {
                Button {
                    повторить()
                } label: {
                    Label(OfflineText.т("q_retry"), systemImage: "arrow.clockwise")
                }
            }
            if сообщение.состояние != .уходит && сообщение.состояние != .ушло {
                Button(role: .destructive) {
                    удалить()
                } label: {
                    Label(OfflineText.т("q_delete"), systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OfflineText.т("q_you") + ": " + сообщение.текст + ". " + подпись)
        .accessibilityAddTraits(неУшло ? AccessibilityTraits.isButton : AccessibilityTraits())
        .accessibilityAction {
            if неУшло { повторить() }
        }
    }

    private var статус: some View {
        HStack(spacing: 4) {
            Image(systemName: значок)
                .font(.system(size: 10, weight: .semibold))
            Text(подпись)
                .font(.system(size: 11, weight: неУшло ? .semibold : .regular))
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(неУшло ? ИнбоксКраска.плохоТекст : Theme.текстВторой)
        .padding(.horizontal, 4)
    }

    private var значок: String {
        switch сообщение.состояние {
        case .ждёт: return "clock"
        case .уходит: return "arrow.up.circle"
        case .ушло: return "checkmark"
        case .неУшло: return "exclamationmark.circle.fill"
        }
    }

    private var подпись: String {
        switch сообщение.состояние {
        case .ждёт: return OfflineText.т("q_wait")
        case .уходит: return OfflineText.т("q_sending")
        case .ушло: return OfflineText.т("q_sent")
        case .неУшло:
            let причина = (сообщение.причина ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return причина.isEmpty ? OfflineText.т("q_failed") : причина + " — " + OfflineText.т("q_tap_retry")
        }
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14,
                               bottomTrailingRadius: 5, topTrailingRadius: 14, style: .continuous)
    }
}
