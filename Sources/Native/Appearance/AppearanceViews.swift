import SwiftUI

/// Раздел «Оформление» в кабинете (этап 15): тема приложения — сегментами «Авто / Светлая / Тёмная», как .cabset-theme
/// настроек сайта (cabThemeSegHTML). Чтобы при крупном «Размере текста» подписи не обрезались, размер текста у сегментов
/// ограничен, а подпись может ужаться.
struct РазделОформления: View {
    @ObservedObject private var выбор = ВыборТемы.shared
    /// Этап 46 (владелец 26.09.2026): человек выбрал тему в меню — кабинет отдаёт её и в аккаунт сайта (ui_prefs), как
    /// переключатель темы в настройках сайта. Только на выбор человека, а не на любую смену темы: иначе тема, пришедшая
    /// из мастера «Начало работы», ушла бы на сервер дважды.
    let выбрано: ((ТемаОформления) -> Void)?

    init(выбрано: ((ТемаОформления) -> Void)? = nil) {
        self.выбрано = выбрано
    }

    private var тема: Binding<ТемаОформления> {
        Binding(get: { выбор.тема }, set: { новая in
            guard новая != выбор.тема else { return }
            выбор.тема = новая
            выбрано?(новая)
        })
    }

    var body: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(ТемаОформления.allCases) { вариант in
                    сегмент(вариант)
                }
            }
            .padding(4)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(AppearanceText.т("theme"))
        } header: {
            ЗаголовокГруппыКабинета(AppearanceText.т("title"))
        } footer: {
            Text(AppearanceText.т("footer"))
        }
    }

    /// .cabset-thb: значок над подписью 12/700; выбранный — карточка с кольцом 1px и тенью, значок --acc-on.
    private func сегмент(_ вариант: ТемаОформления) -> some View {
        let вкл = выбор.тема == вариант
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { тема.wrappedValue = вариант }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: вариант.значок)
                    .font(.system(size: 16))
                    .foregroundStyle(вкл ? Theme.акцент : Theme.текстВторой)
                    .scaleEffect(вкл ? 1.07 : 1)
                    .accessibilityHidden(true)
                Text(вариант.название)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(вкл ? Theme.текст : Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background {
                if вкл {
                    форма.fill(Theme.поверхность)
                        .shadow(color: Color.black.opacity(0.15), radius: 5, y: 3)
                        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
                }
            }
            .contentShape(форма)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }
}
