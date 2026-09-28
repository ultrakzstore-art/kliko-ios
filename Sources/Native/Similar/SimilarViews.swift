import SwiftUI

/**
 ПОЛОСА «ПОХОЖИЕ ОБЪЯВЛЕНИЯ» внизу карточки (этап 7): карточки листаются вбок, пока идёт запрос — заготовки.

 Карточка похожего — NavigationLink(value: Listing): следующая карточка ложится в тот же стек. Маршрут для Listing
 ставят стек ленты (NativeFeedView) и стек вкладки «Избранное» (NativeTabsView), и ListingDetailView открывается
 только из них. Сердечко — слоем над ссылкой, как в сетке ленты (сердечкоИзбранного).
 */
struct ПолосаПохожих: View {
    let состояние: Похожие.Состояние
    /// Заголовок полосы. Этап 28: у страницы как на сайте — «Похожие объявления» или «Ещё в этой категории» (у услуг,
    /// _similarBlock сайта). nil — прежний «Похожие».
    var заголовок: String? = nil

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
    @ViewBuilder
    private func рамка<Карточки: View>(@ViewBuilder _ карточки: () -> Карточки) -> some View {
        if Config.дизайнКакНаСайте {
            рамкаСайта(карточки)
        } else {
            рамкаПрежняя(карточки)
        }
    }

    /// .mk-msimilar: линия сверху (над ней с внешним отступом страницы — около 20, как margin-top сайта), под ней 16,
    /// заголовок .mk-msim-h 15 px/800 и 12 до ряда; ряд .mk-msim-row — зазор 12, снизу 8. Заголовок и карточки — по
    /// одной линии с остальной страницей (20).
    private func рамкаСайта<Карточки: View>(@ViewBuilder _ карточки: () -> Карточки) -> some View {
        let содержимое = карточки()
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Text(заголовок ?? SimilarText.т("title"))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                /* Высоту ряда держат сами карточки: у всех одинаковые строки (две строки названия, строка цены). */
                LazyHStack(alignment: .top, spacing: 12) {
                    содержимое
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .padding(.top, 10)
        }
        .padding(.bottom, 4)
    }

    private func рамкаПрежняя<Карточки: View>(@ViewBuilder _ карточки: () -> Карточки) -> some View {
        let содержимое = карточки()
        return VStack(alignment: .leading, spacing: 8) {
            Text(заголовок ?? SimilarText.т("title"))
                .font(Font.headline)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    содержимое
                }
                .padding(.horizontal, 16)
                /* Владелец 25.09.2026, проверка на телефоне, сборка 33: прокрутка обрезала тень карточек прямо по их
                   низу. Место под тень — внутри прокрутки; снаружи отступы меньше на столько же, ряд той же высоты. */
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

/// Карточка похожего: фото, цена, название в две строки, город. В виде сайта — .mk-simc (_simCard): 132 pt с рамкой,
/// фото 1:1, сначала название, под ним цена; города нет.
private struct КарточкаПохожего: View {
    let товар: Listing

    static let ширина: CGFloat = 150

    private var сайт: Bool { Config.дизайнКакНаСайте }

    var body: some View {
        if сайт {
            КарточкаПохожегоСайта(товар: товар)
        } else {
            прежняя
        }
    }

    private var прежняя: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color(.tertiarySystemGroupedBackground)
                .frame(width: Self.ширина, height: Self.ширина * 3 / 4)
                .overlay {
                    /* Проверка на телефоне, сборка 33: КартинкаЛенты вместо AsyncImage (FeedImages.swift). */
                    КартинкаЛенты(товар.обложка, пунктов: Self.ширина) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(товар.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                /* Владелец 26.09.2026: карточки полосы одной высоты — строка города держит место и без города. */
                Text(товар.city.isEmpty ? " " : товар.city)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .frame(width: Self.ширина, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)          // этап 11: одной фразой, как карточка ленты; фото — украшение
    }
}

/// .mk-simc сайта: 132 px вместе с рамкой 1 px --mk-line, скругление 14, без тени; фото .mk-simc-img 1:1 на
/// color-mix(--mk-line 40 %); название .mk-simc-t 12 px, строка 1,3, две строки (поля 8 10 2); цена .mk-simc-p
/// 13 px/800 (поля 0 10 10). У услуг цены нет — строка всё равно держит место: ряд flex у сайта тянет карточки до
/// одной высоты. Цены нет у товара — «Договорная».
private struct КарточкаПохожегоСайта: View {
    let товар: Listing

    static let ширина: CGFloat = 132
    private static let внутри: CGFloat = ширина - 2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.линия.opacity(0.4)
                .frame(width: Self.внутри, height: Self.внутри)
                .overlay {
                    КартинкаЛенты(товар.обложка, пунктов: Self.внутри) {
                        Color.clear
                    }
                }
                .clipped()
            Text(товар.title)
                .font(.system(size: 12))
                .lineSpacing(1.5)
                .foregroundStyle(Theme.текст)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
            Text(цена ?? " ")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(цена == nil ? 0 : 1)
                .accessibilityHidden(цена == nil)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(width: Self.внутри, alignment: .leading)
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md - 1, style: .continuous))
        .padding(1)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)
    }

    /// _simCard: услуга — без цены, цена больше нуля — сумма, иначе «Договорная».
    private var цена: String? {
        if товар.услуга { return nil }
        if let p = товар.price, p > 0 { return ListingCard.тенге(p) }
        return ВитринаТекст.т("negotiable")
    }
}

/// Заготовка на время запроса — того же размера, что карточка, чтобы полоса не прыгала, когда придут настоящие.
private struct ЗаготовкаПохожего: View {
    var body: some View {
        if Config.дизайнКакНаСайте {
            сайт
        } else {
            прежняя
        }
    }

    /// Размер .mk-simc: фото 1:1 и две строки названия с ценой — серыми полосами на линии сайта.
    private var сайт: some View {
        let внутри = КарточкаПохожегоСайта.ширина - 2
        return VStack(alignment: .leading, spacing: 0) {
            Theme.линия.opacity(0.4)
                .frame(width: внутри, height: внутри)
            VStack(alignment: .leading, spacing: 5) {
                Capsule().fill(Theme.линия).frame(width: 100, height: 10)
                Capsule().fill(Theme.линия).frame(width: 70, height: 10)
                Capsule().fill(Theme.линия).frame(width: 60, height: 12)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 10)
            .padding(.top, 11)
            .padding(.bottom, 12)
        }
        .frame(width: внутри, alignment: .leading)
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md - 1, style: .continuous))
        .padding(1)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var прежняя: some View {
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}
