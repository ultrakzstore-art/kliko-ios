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

    /// Этап 20: режим «Сравнить» — нажатие на карточку отмечает её, а не открывает.
    @State private var сравниваем = false
    /// Отмеченные для сравнения номера — в порядке нажатий: так же встанут и колонки.
    @State private var отмеченные: [String] = []
    /// Нажали четвёртую — сказать, что больше трёх нельзя.
    @State private var упёрлись = false
    @State private var показатьСравнение = false

    /// Сравнение объявлений — от двух до трёх.
    private static let сравнитьОт = 2
    private static let сравнитьДо = 3

    var body: some View {
        Group {
            if избранное.товары.isEmpty && Config.дизайнКакНаСайте {
                /* Этап 30: пустое избранное — экраном в краске сайта. */
                ПустоСайта(значок: "heart", заголовок: FavoritesText.т("empty"), подпись: FavoritesText.т("empty_sub"),
                           кнопка: вЛенту == nil ? nil : FavoritesText.т("to_feed"), действие: вЛенту)
            } else if избранное.товары.isEmpty {
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
                        /* Этап 30: заголовок ряда, как «• Раздел N» главной сайта: точка-сердце и число. */
                        if Config.дизайнКакНаСайте { заголовокСайта }
                        LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: 12) {
                            ForEach(избранное.товары) { товар in
                                карточка(товар)
                            }
                        }
                        .padding(.horizontal, 12)
                        Text(FavoritesText.т("local"))
                            .font(.caption)
                            .foregroundStyle(Config.дизайнКакНаСайте ? Theme.текстВторой : Color.secondary)
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
        .background(Config.дизайнКакНаСайте ? Theme.фонСтраницы : Color(.systemGroupedBackground))
        .navigationTitle(FavoritesText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        /* Этап 30: панель в краске сайта — поверхность и жирный заголовок. */
        .toolbar {
            if Config.дизайнКакНаСайте {
                ToolbarItem(placement: .principal) {
                    Text(FavoritesText.т("title"))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .toolbarBackground(Config.дизайнКакНаСайте ? Visibility.visible : Visibility.automatic, for: .navigationBar)
        .toolbarBackground(Config.дизайнКакНаСайте ? AnyShapeStyle(Theme.поверхность) : AnyShapeStyle(Material.bar),
                           for: .navigationBar)
        /* Этап 20: «Сравнить» — когда есть что сравнивать. */
        .toolbar {
            if Config.сравнение && (сравниваем || избранное.товары.count >= Self.сравнитьОт) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CompareText.т(сравниваем ? "done" : "compare")) { переключитьСравнение() }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if сравниваем { панельСравнения }
        }
        .navigationDestination(isPresented: $показатьСравнение) {
            /* Владелец 25.09.2026, проверка на телефоне, сборка 33: этот экран кладётся без пути стека — отмечаемся,
               чтобы нижняя панель сайта над ним спряталась, как над перепиской и объявлением. */
            ЭкранСравнения(товары: отмеченныеТовары)
                .отметкаПоверхСайта()
        }
        /* Сердечко сняли (здесь же, в карточке, в кабинете) — из отмеченных тоже; сравнивать стало нечего — из режима. */
        .onChange(of: избранное.номера) { _, номера in
            отмеченные.removeAll { !номера.contains($0) }
            if номера.count < Self.сравнитьОт && сравниваем { переключитьСравнение() }
        }
    }

    /// Этап 30: «♥ Избранное 3» — как заголовок ряда «Рекомендуем» главной сайта (точка краской, жирное название, число).
    private var заголовокСайта: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.сердце)
                .accessibilityHidden(true)
            Text(FavoritesText.т("title"))
                .font(.system(.title3, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(DesignText.число(избранное.товары.count))
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func карточка(_ товар: Listing) -> some View {
        if сравниваем {
            /* Этап 20: в режиме сравнения карточка — переключатель; сердечка нет, чтобы не снять его по ошибке. */
            Button { отметить(товар.id) } label: { ListingCard(товар: товар) }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) { ЗначокВыбора(выбрана: отмеченные.contains(товар.id)) }
                .выбраннаяКарточка(отмеченные.contains(товар.id))
                .accessibilityHint(CompareText.т("select_hint"))
        } else {
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

    // MARK: - Сравнение (этап 20)

    /// Отмеченные объявления в порядке нажатий — снимки избранного.
    private var отмеченныеТовары: [Listing] {
        отмеченные.compactMap { номер in избранное.товары.first { $0.id == номер } }
    }

    private var можноСравнить: Bool {
        отмеченные.count >= Self.сравнитьОт && отмеченные.count <= Self.сравнитьДо
    }

    private func переключитьСравнение() {
        сравниваем.toggle()
        отмеченные = []
        упёрлись = false
    }

    /// Нажатие в режиме сравнения: отметить или снять. Четвёртую не отмечаем — говорим, что больше трёх нельзя.
    private func отметить(_ номер: String) {
        if let место = отмеченные.firstIndex(of: номер) {
            отмеченные.remove(at: место)
            упёрлись = false
        } else if отмеченные.count < Self.сравнитьДо {
            отмеченные.append(номер)
            упёрлись = false
        } else {
            упёрлись = true
        }
    }

    private var подписьВыбора: String {
        if упёрлись { return CompareText.т("max") }
        if отмеченные.count < Self.сравнитьОт { return CompareText.т("pick") }
        return String(format: CompareText.т("picked"), отмеченные.count)
    }

    private var панельСравнения: some View {
        VStack(spacing: 8) {
            Text(подписьВыбора)
                .font(.footnote)
                .foregroundStyle(упёрлись ? Color.red : Color.secondary)
            Button { показатьСравнение = true } label: {
                Label(CompareText.т("show"), systemImage: "tablecells")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Theme.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!можноСравнить)
            .opacity(можноСравнить ? 1 : 0.45)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.regularMaterial)
    }
}

/**
 СЕРДЕЧКО: на карточке — кружок в правом верхнем углу фото, в карточке объявления — кнопка в шапке.

 Нажатие сохраняет или убирает сразу, без подтверждений: вернуть — то же одно нажатие.
 */
struct КнопкаИзбранного: View {
    /// Этап 28: .фото — тёмный квадрат над фото страницы объявления как на сайте (.mk-mhead .mk-mfav).
    enum Место { case карточка, шапка, фото }

    let товар: Listing
    var место: Место = .карточка
    @ObservedObject private var избранное = FavoritesStore.shared

    private var сохранено: Bool { избранное.есть(товар.id) }

    var body: some View {
        Group {
            if место == .карточка {
                Button { избранное.переключить(товар) } label: {
                    if Config.дизайнКакНаСайте {
                        /* Этап 26: .mk-fav сайта — кружок 32 pt из поверхности 82 % с размытием, сердце серое, в
                           избранном — залитое #e0245e; 8 pt от угла фото. */
                        сердце
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(сохранено ? Theme.сердце : Theme.текстВторой)
                            .frame(width: 32, height: 32)
                            /* Проверка на телефоне, сборка 33 («лента подвисает»): без .ultraThinMaterial — размытие
                               фона под кружком пересчитывалось каждый кадр прокрутки на каждой карточке, а под
                               поверхностью 82 % его почти не было видно. Поверхность 90 % — тот же вид. */
                            .background(Theme.поверхность.opacity(0.9), in: Circle())
                            .padding(8)
                            .contentShape(Rectangle())
                    } else {
                        сердце
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(сохранено ? Color.red : Color.primary)
                            .frame(width: 32, height: 32)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)                     // палец попадает в 44 pt, а кружок остаётся маленьким
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
            } else if место == .фото {
                Button { избранное.переключить(товар) } label: {
                    сердце
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(сохранено ? Theme.сердце : Color.white)
                        .фонКнопкиНадФото()
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
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
