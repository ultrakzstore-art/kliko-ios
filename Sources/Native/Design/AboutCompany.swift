import SwiftUI

/**
 «О компании» профиля (упрощение для новичка): подвал сайта (ПодвалСайта — реквизиты, адрес, оплата картами, 3-D Secure,
 ссылки на справку и документы) больше не висит внизу главной, а открывается отсюда тем же содержимым.
 */
struct ЭкранОКомпании: View {
    let открыть: (URL) -> Void

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    /// Фон подвала — --hero-1 сайта, и под ним, чтобы прокрутка не открывала светлую подложку.
    private static let фон = Color(uiColor: Theme.hex(0x0E2A1C))

    var body: some View {
        ScrollView {
            ПодвалСайта(открыть: открыть)
                .padding(.top, 12)
        }
        .background(Self.фон.ignoresSafeArea())
        .navigationTitle(HomeText.т("about_co"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/**
 «Язык приложения» профиля — тот же выбор, что был у пилюли «тема │ язык» шапки главной (ЯзыкПриложения): RU «Рус»,
 KZ «Қаз», EN «Eng», AR «عربي», у текущего галочка. Нужен и гостю: язык аккаунта (настройка «Язык») — только вошедшему.
 */
struct СтрокаЯзыкаПриложения: View {
    @ObservedObject private var язык = ЯзыкПриложения.shared

    init() {}

    var body: some View {
        Menu {
            ForEach(ЯзыкПриложения.варианты) { вариант in
                Button {
                    язык.выбрать(вариант)
                } label: {
                    if вариант.код == язык.код {
                        Label(вариант.метка + "  " + вариант.имя, systemImage: "checkmark")
                    } else {
                        Text(вариант.метка + "  " + вариант.имя)
                    }
                }
            }
        } label: {
            HStack {
                ПодписьСтрокиКабинета(HomeText.т("app_lang"), значок: "globe")
                Spacer(minLength: 8)
                Text(язык.текущий.имя)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(язык.текущий.имя)
    }
}
