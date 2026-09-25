import SwiftUI
import UIKit

/**
 «ВЫ СМОТРЕЛИ» — полоса над разделами ленты (этап 6): маленькие карточки, фото и цена, листаются вбок.

 Ведёт туда же, куда сетка ленты: в нативную карточку или, при выключенной Config.нативнаяКарточка, на страницу
 сайта. Маршрут карточки ставит стек ленты (NativeFeedView), здесь только ссылки.
 */
struct ПолосаНедавних: View {
    let товары: [Listing]
    /// Открыть страницу сайта в веб-обёртке.
    let открыть: (URL) -> Void
    let очистить: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(RecentText.т("viewed"))
                    .font(.headline)
                Spacer()
                Button(RecentText.т("clear"), action: очистить)
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.green2)
                    .accessibilityLabel(RecentText.т("clear_viewed"))
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(товары) { товар in
                        Group {
                            if Config.нативнаяКарточка {
                                NavigationLink(value: товар) { МаленькаяКарточка(товар: товар) }
                            } else {
                                Button { if let u = товар.адрес { открыть(u) } } label: { МаленькаяКарточка(товар: товар) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }
}

/// Карточка полосы «Вы смотрели»: фото, цена и строка названия.
private struct МаленькаяКарточка: View {
    let товар: Listing

    private static let ширина: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color(.tertiarySystemGroupedBackground)
                .frame(width: Self.ширина, height: Self.ширина * 3 / 4)
                .overlay {
                    AsyncImage(url: товар.обложка) { фаза in
                        if case .success(let картинка) = фаза {
                            картинка.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(ListingCard.цена(товар))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(товар.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Self.ширина, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)          // этап 11: одной фразой, как карточка ленты; фото — украшение
    }
}

/// Клавиатура поиска.
enum КлавиатураПоиска {
    /// Убрать клавиатуру, как это делает кнопка «Найти»: поиск остаётся открытым с текстом, подсказки уходят и
    /// видна выдача. Своего способа снять фокус с поля .searchable в iOS 17 у SwiftUI нет.
    @MainActor static func спрятать() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
