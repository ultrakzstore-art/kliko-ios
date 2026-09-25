import SwiftUI

/**
 ВКЛАДКА «ИЗБРАННОЕ» (этап 5): сетка сохранённых теми же карточками, что в ленте. Стек навигации и маршруты
 (карточка, чат) — снаружи: во вкладке их ставит NativeTabsView, а без нижних вкладок экран открывается в стеке
 ленты, где они уже есть, — двойная регистрация одного маршрута в одном стеке SwiftUI не любит.

 Обновить с сервера нечего: список живёт на телефоне (FavoritesStore). Цена освежается, когда карточку открывают.
 */
struct FavoritesView: View {
    @ObservedObject private var избранное = FavoritesStore.shared
    /// Открыть страницу сайта в веб-обёртке.
    let открыть: (URL) -> Void
    /// «Перейти в ленту» на пустом экране — переключить вкладку. nil — кнопки нет (экран открыт из самой ленты).
    let вЛенту: (() -> Void)?

    /// Крупный текст для доступности — сетка в одну колонку, как в ленте (этап 11, ListingCard.сетка).
    @Environment(\.dynamicTypeSize) private var размерТекста

    var body: some View {
        Group {
            if избранное.товары.isEmpty {
                ContentUnavailableView {
                    Label(FavoritesText.т("empty"), systemImage: "heart")
                } description: {
                    Text(FavoritesText.т("empty_sub"))
                } actions: {
                    if let назад = вЛенту {
                        Button(FavoritesText.т("to_feed"), action: назад)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.green)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: 12) {
                            ForEach(избранное.товары) { товар in
                                карточка(товар)
                            }
                        }
                        .padding(.horizontal, 12)
                        Text(FavoritesText.т("local"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .animation(.easeInOut(duration: 0.2), value: избранное.номера)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(FavoritesText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func карточка(_ товар: Listing) -> some View {
        /* Как в ленте: карточка нативная или, при выключенном рубильнике этапа 2, страница сайта. */
        Group {
            if Config.нативнаяКарточка {
                NavigationLink(value: товар) { ListingCard(товар: товар) }
            } else {
                Button { if let u = товар.адрес { открыть(u) } } label: { ListingCard(товар: товар) }
            }
        }
        .buttonStyle(.plain)
        .сердечкоИзбранного(товар)
    }
}

/**
 СЕРДЕЧКО: на карточке — кружок в правом верхнем углу фото, в карточке объявления — кнопка в шапке.

 Нажатие сохраняет или убирает сразу, без подтверждений: вернуть — то же одно нажатие.
 */
struct КнопкаИзбранного: View {
    enum Место { case карточка, шапка }

    let товар: Listing
    var место: Место = .карточка
    @ObservedObject private var избранное = FavoritesStore.shared

    private var сохранено: Bool { избранное.есть(товар.id) }

    var body: some View {
        Group {
            if место == .карточка {
                Button { избранное.переключить(товар) } label: {
                    сердце
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(сохранено ? Color.red : Color.primary)
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)                     // палец попадает в 44 pt, а кружок остаётся маленьким
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button { избранное.переключить(товар) } label: { сердце }
                    .tint(сохранено ? Color.red : Theme.green)
            }
        }
        .accessibilityLabel(FavoritesText.т(сохранено ? "remove" : "add"))
        .sensoryFeedback(.selection, trigger: сохранено)
    }

    private var сердце: some View {
        Image(systemName: сохранено ? "heart.fill" : "heart")
            .symbolEffect(.bounce, value: сохранено)
    }
}

/// Куда ведёт навигация избранного в чужом стеке.
enum ИзбранноеЦель: Hashable {
    /// Экран избранного — из шапки ленты, когда нижних вкладок нет (Config.нижниеВкладки = false).
    case список
}

extension View {
    /**
     Сердечко поверх карточки в сетке (лента, избранное).

     🔴 РЯДОМ СО ССЫЛКОЙ, А НЕ ВНУТРИ НЕЁ. Кнопка внутри подписи NavigationLink — часть ссылки: VoiceOver читает
     карточку одним элементом и до сердечка не доходит, а нажатие рискует открыть объявление. Поэтому сердечко —
     слой над карточкой: его 44 pt ловят нажатие, всё остальное по-прежнему ведёт в объявление.
     */
    func сердечкоИзбранного(_ товар: Listing) -> some View {
        overlay(alignment: .topTrailing) {
            if Config.избранное { КнопкаИзбранного(товар: товар) }
        }
    }

    /// Экран избранного в стеке ленты — вход из её шапки, когда нижних вкладок нет.
    func избранноеМаршруты(открыть: @escaping (URL) -> Void) -> some View {
        navigationDestination(for: ИзбранноеЦель.self) { _ in
            FavoritesView(открыть: открыть, вЛенту: nil)
        }
    }
}
