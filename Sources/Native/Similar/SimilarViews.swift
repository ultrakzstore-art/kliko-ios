import SwiftUI

/**
 ПОЛОСА «ПОХОЖИЕ ОБЪЯВЛЕНИЯ» внизу карточки (этап 7): карточки листаются вбок, пока идёт запрос — заготовки.

 Карточка похожего — NavigationLink(value: Listing): следующая карточка ложится в тот же стек. Маршрут для Listing
 ставят стек ленты (NativeFeedView) и стек вкладки «Избранное» (NativeTabsView), и ListingDetailView открывается
 только из них. Сердечко — слоем над ссылкой, как в сетке ленты (сердечкоИзбранного).
 */
struct ПолосаПохожих: View {
    let состояние: Похожие.Состояние

    var body: some View {
        switch состояние {
        case .нет:
            EmptyView()
        case .грузим:
            рамка {
                ForEach(0..<4, id: \.self) { _ in ЗаготовкаПохожего() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SimilarText.т("loading"))
        case .готово(_, let товары):
            if !товары.isEmpty {
                рамка {
                    ForEach(товары) { товар in
                        NavigationLink(value: товар) { КарточкаПохожего(товар: товар) }
                            .buttonStyle(.plain)
                            .сердечкоИзбранного(товар)
                    }
                }
            }
        }
    }

    /// Заголовок и карточки от края до края экрана: полоса стоит вне отступов карточки объявления.
    private func рамка<Карточки: View>(@ViewBuilder _ карточки: () -> Карточки) -> some View {
        let содержимое = карточки()
        return VStack(alignment: .leading, spacing: 10) {
            Text(SimilarText.т("title"))
                .font(.headline)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    содержимое
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 20)
    }
}

/// Карточка похожего: фото, цена, название в две строки, город.
private struct КарточкаПохожего: View {
    let товар: Listing

    static let ширина: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(.tertiarySystemGroupedBackground)
                .frame(width: Self.ширина, height: Self.ширина * 3 / 4)
                .overlay {
                    AsyncImage(url: товар.обложка) { фаза in
                        if case .success(let картинка) = фаза {
                            картинка.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(товар.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                if !товар.city.isEmpty {
                    Text(товар.city)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: Self.ширина, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)          // этап 11: одной фразой, как карточка ленты; фото — украшение
    }
}

/// Заготовка на время запроса — того же размера, что карточка, чтобы полоса не прыгала, когда придут настоящие.
private struct ЗаготовкаПохожего: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: КарточкаПохожего.ширина, height: КарточкаПохожего.ширина * 3 / 4)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(Color(.tertiarySystemFill)).frame(width: 84, height: 13)
                Capsule().fill(Color(.quaternarySystemFill)).frame(width: 124, height: 10)
                Capsule().fill(Color(.quaternarySystemFill)).frame(width: 70, height: 10)
            }
            .padding(.horizontal, 9)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: КарточкаПохожего.ширина, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
