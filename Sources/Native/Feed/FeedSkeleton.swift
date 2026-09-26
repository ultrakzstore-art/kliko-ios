import Foundation
import SwiftUI

/**
 ЗАГОТОВКИ ЛЕНТЫ — ЭТАП 11 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Пока пустая лента грузится (первый запуск без ленты на диске, смена раздела, поиск), вместо колеса — шесть серых
 карточек той же сетки: видно, где появятся объявления, и экран не прыгает, когда они придут. Это сама ListingCard
 с выдуманным объявлением под .redacted(reason: .placeholder): тексты становятся серыми полосками, размеры совпадают
 сами, второй вёрстки карточки нет. Выдуманных текстов не видно ни глазами, ни VoiceOver'ом.

 Мерцание — прозрачностью по часам (TimelineView), а не повторяющейся анимацией: repeatForever, запущенная в onAppear
 внутри NavigationStack, подхватывает и сдвиг самой сетки, когда встаёт поле поиска, и карточки начинают «плавать».
 При «Уменьшении движения» мерцания нет. VoiceOver читает заготовки одной фразой «Загружаем объявления».
 Рубильник — Config.скелетЛенты.
 */
struct СкелетЛенты: View {
    let колонки: [GridItem]
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(колонки: [GridItem]) {
        self.колонки = колонки
    }

    var body: some View {
        Group {
            if безДвижения {
                сетка(0.8)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { контекст in
                    сетка(Self.яркость(контекст.date))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessText.т("loading"))
    }

    private func сетка(_ прозрачность: Double) -> some View {
        /* Зазор и поля — те же, что у сетки ленты (этап 49: у вида сайта 14 и 16), иначе карточки прыгнут при ответе. */
        LazyVGrid(columns: колонки, spacing: ListingCard.зазор) {
            ForEach(Self.объявления) { товар in
                ListingCard(товар: товар)
            }
        }
        .redacted(reason: .placeholder)
        .opacity(прозрачность)
        .padding(.horizontal, ListingCard.поле)
    }

    /// Прозрачность от 0,6 до 1 и обратно за 1,6 с — мягко, без вспышек.
    private static func яркость(_ сейчас: Date) -> Double {
        let фаза = сейчас.timeIntervalSinceReferenceDate * 2 * Double.pi / 1.6
        return 0.8 + 0.2 * cos(фаза)
    }

    /// Шесть объявлений-образцов. Тексты разной длины — чтобы полоски не выглядели одинаковыми; прочесть их нельзя:
    /// .redacted закрашивает их полосками, а VoiceOver слышит только «Загружаем объявления».
    private static let объявления: [Listing] = {
        let образцы: [(String, Double, String)] = [
            ("Kliko Kliko Kliko Kliko Kliko", 14_900_000, "Kliko Kliko"),
            ("Kliko Kliko Kliko", 450_000, "Kliko"),
            ("Kliko Kliko Kliko Kliko Kliko Kliko", 2_300_000, "Kliko Kliko"),
            ("Kliko Kliko", 85_000, "Kliko"),
            ("Kliko Kliko Kliko Kliko", 1_150_000, "Kliko Kliko"),
            ("Kliko Kliko Kliko Kliko Kliko", 38_000, "Kliko")
        ]
        var список: [Listing] = []
        for (номер, образец) in образцы.enumerated() {
            var товар = Listing(номер: "скелет-\(номер)")
            товар.title = образец.0
            товар.price = образец.1
            товар.city = образец.2
            список.append(товар)
        }
        return список
    }()
}
