import SwiftUI

/// Раздел «Оформление» в кабинете (этап 15): тема приложения — выбором из меню. Меню, а не сегменты: при крупном
/// «Размере текста» сегменты обрезают подписи, а строка меню растёт вместе с текстом.
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
            Picker(selection: тема) {
                ForEach(ТемаОформления.allCases) { вариант in
                    Label(вариант.название, systemImage: вариант.значок)
                        .tag(вариант)
                }
            } label: {
                Label {
                    Text(AppearanceText.т("theme"))
                } icon: {
                    Image(systemName: "paintbrush").foregroundStyle(Theme.green2)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.green2)
        } header: {
            Text(AppearanceText.т("title"))
        } footer: {
            Text(AppearanceText.т("footer"))
        }
    }
}
