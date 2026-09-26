import SwiftUI

/**
 СРАВНЕНИЕ ОБЪЯВЛЕНИЙ — ЭТАП 20 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «следующие этапы»).

 Во вкладке «Избранное» кнопка «Сравнить» включает выбор: нажатие на карточку отмечает её (от двух до трёх), внизу —
 «Показать сравнение». Экран сравнения — колонка на объявление: фото и название, цена, старая цена, город, новое или
 б/у, гарантия и дальше все характеристики, какие есть хоть у одного (объединение ключей), с «—» там, где их нет.
 Колонки не помещаются — экран листается вбок.

 🔴 БЕЗ ЗАПРОСОВ. Данные — снимок избранного (цена, обложка, город: FavoritesStore) и, если на телефоне есть полная
 копия карточки (ListingDetailCache, этап 13), — её гарантия и характеристики. Три запроса ?id= разом ради таблицы не
 делаем: у объявления без копии характеристик просто нет, и под таблицей сказано, как их получить, — открыть его.
 Цена — всегда из снимка избранного: её освежают открытая карточка и фоновая проверка цены (этап 21).

 На телефон экран ничего не пишет; выбор живёт, пока открыт экран избранного.
 */
struct ЭкранСравнения: View {
    /// Снимки избранного в порядке выбора.
    let товары: [Listing]
    /// Полные копии с телефона по номеру (этап 13); нет копии — нет и записи.
    @State private var полные: [String: Listing] = [:]

    static let ширинаПодписи: CGFloat = 112
    static let ширинаКолонки: CGFloat = 150
    /// Нет значения у объявления.
    static let нет = "—"

    init(товары: [Listing]) {
        self.товары = товары
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Color.clear
                            .frame(width: Self.ширинаПодписи, height: 1)
                            .accessibilityHidden(true)
                        ForEach(колонки) { товар in
                            шапкаКолонки(товар)
                        }
                    }
                    ForEach(строки) { строка in
                        Divider()
                        GridRow {
                            Text(строка.подпись)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(width: Self.ширинаПодписи, alignment: .leading)
                            ForEach(Array(строка.значения.enumerated()), id: \.offset) { пара in
                                Text(пара.element)
                                    .font(строка.главная ? Font.subheadline.weight(.heavy) : Font.subheadline)
                                    .foregroundStyle(пара.element == Self.нет ? Color.secondary : Color.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: Self.ширинаКолонки, alignment: .leading)
                            }
                        }
                    }
                }
                Text(CompareText.т("note"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: ширинаТаблицы, alignment: .leading)
            }
            .padding(16)
        }
        .background(Color(.systemBackground))
        .navigationTitle(CompareText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await прочитатьКопии() }
    }

    // MARK: - Колонки и строки

    /// Колонки: копия с телефона, если есть, но цена, обложка, название и город — из снимка избранного (см. шапку).
    private var колонки: [Listing] {
        товары.map { снимок in Self.слить(снимок, полные[снимок.id]) }
    }

    private var ширинаТаблицы: CGFloat {
        Self.ширинаПодписи + CGFloat(товары.count) * (Self.ширинаКолонки + 12)
    }

    static func слить(_ снимок: Listing, _ полный: Listing?) -> Listing {
        guard var итог = полный else { return снимок }
        итог.price = снимок.price
        итог.oldPrice = снимок.oldPrice
        итог.negotiable = снимок.negotiable
        итог.forRent = снимок.forRent
        итог.rentPriceDay = снимок.rentPriceDay
        if !снимок.title.isEmpty { итог.title = снимок.title }
        if снимок.thumb != nil { итог.thumb = снимок.thumb }
        if !снимок.city.isEmpty { итог.city = снимок.city }
        return итог
    }

    /// Строки таблицы: постоянные, затем объединение ключей характеристик в порядке первой встречи.
    private var строки: [СтрокаСравнения] {
        let все = колонки
        var итог: [СтрокаСравнения] = [
            СтрокаСравнения(id: "price", подпись: CompareText.т("price"),
                            значения: все.map { ListingCard.цена($0) }, главная: true),
            СтрокаСравнения(id: "old_price", подпись: CompareText.т("old_price"),
                            значения: все.map { Self.стараяЦена($0) }),
            СтрокаСравнения(id: "city", подпись: CompareText.т("city"),
                            значения: все.map { $0.city.isEmpty ? Self.нет : $0.city }),
            СтрокаСравнения(id: "condition", подпись: CompareText.т("condition"),
                            значения: все.map { FeedText.т($0.isNew ? "new" : "used") }),
            СтрокаСравнения(id: "warranty", подпись: CompareText.т("warranty"),
                            значения: все.map { товар in
                                товар.гарантияДней.map { String(format: CompareText.т("days"), $0) } ?? Self.нет
                            })
        ]
        var ключи: [String] = []
        for товар in все {
            for х in товар.характеристики where !ключи.contains(х.ключ) { ключи.append(х.ключ) }
        }
        for ключ in ключи {
            let значения = все.map { товар in
                товар.характеристики.first(where: { $0.ключ == ключ })?.значение ?? Self.нет
            }
            итог.append(СтрокаСравнения(id: "spec:" + ключ, подпись: ключ, значения: значения))
        }
        return итог
    }

    /// Старая цена — только если она выше нынешней, как в карточке (ListingDetailView.шапка).
    static func стараяЦена(_ товар: Listing) -> String {
        guard let старая = товар.oldPrice, let цена = товар.price, старая > цена else { return нет }
        return ListingCard.тенге(старая)
    }

    /// Шапка колонки: фото и название; нажатие открывает объявление в том же стеке.
    @ViewBuilder
    private func шапкаКолонки(_ товар: Listing) -> some View {
        if Config.нативнаяКарточка {
            NavigationLink(value: товар) { содержимоеШапки(товар) }
                .buttonStyle(.plain)
        } else {
            содержимоеШапки(товар)
        }
    }

    private func содержимоеШапки(_ товар: Listing) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color(.tertiarySystemGroupedBackground)
                .frame(width: Self.ширинаКолонки, height: Self.ширинаКолонки * 3 / 4)
                .overlay {
                    AsyncImage(url: товар.обложка) { фаза in
                        if case .success(let картинка) = фаза {
                            картинка.resizable().scaledToFill()
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 22))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            Text(товар.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.ширинаКолонки, alignment: .leading)
    }

    // MARK: - Копии с телефона

    /// Полные карточки с диска (этап 13) — по одной, без сети. Рубильник копий выключен — только снимки.
    private func прочитатьКопии() async {
        guard Config.карточкиБезСети else { return }
        var найдено: [String: Listing] = [:]
        for товар in товары {
            if let копия = await ListingDetailCache.прочитать(товар.id), копия.товар.id == товар.id {
                найдено[товар.id] = копия.товар
            }
        }
        guard !Task.isCancelled else { return }
        полные = найдено
    }
}

/// Строка таблицы сравнения: подпись и значение для каждой колонки по порядку.
struct СтрокаСравнения: Identifiable {
    let id: String
    let подпись: String
    let значения: [String]
    /// Цена — жирнее прочих.
    var главная = false
}

/// Кружок выбора на карточке избранного в режиме «Сравнить». Нажатия не ловит — их ловит сама карточка.
struct ЗначокВыбора: View {
    let выбрана: Bool

    var body: some View {
        Image(systemName: выбрана ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(выбрана ? Theme.green2 : Color.secondary)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: Circle())
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
