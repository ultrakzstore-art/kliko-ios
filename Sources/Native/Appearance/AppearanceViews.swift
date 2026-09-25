import SwiftUI

/// Раздел «Оформление» в кабинете (этап 15): тема приложения — выбором из меню. Меню, а не сегменты: при крупном
/// «Размере текста» сегменты обрезают подписи, а строка меню растёт вместе с текстом.
struct РазделОформления: View {
    @ObservedObject private var выбор = ВыборТемы.shared

    var body: some View {
        Section {
            Picker(selection: $выбор.тема) {
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
