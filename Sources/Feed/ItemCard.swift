import SwiftUI

struct ItemCard: View {
    let item: MarketItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: item.thumbURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .empty: Rectangle().fill(Theme.mint).overlay(ProgressView())
                    default: Rectangle().fill(Theme.mint)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.muted))
                    }
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()

                HStack(spacing: 6) {
                    if item.isTop == true { badge("ТОП", bg: Theme.green2) }
                    if item.isNew { badge("Новое", bg: Theme.green) }
                    if item.forRent == true { badge("Аренда", bg: Color(red:0.55,green:0.36,blue:0.72)) }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(item.priceText)
                    .font(.callout).fontWeight(.bold)
                    .foregroundStyle(Theme.green2)
                if let city = item.city, !city.isEmpty {
                    Text(city).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .padding(10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private func badge(_ text: String, bg: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.bold).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}
