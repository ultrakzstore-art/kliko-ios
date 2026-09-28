import SwiftUI
import UIKit

/**
 ПОДАЧА — ШАПКИ, СТАРТ «ЧТО РАЗМЕЩАЕТЕ?», ГОСТЬ, ОКНА «KLIKO AI РАСПОЗНАЁТ» И ИТОГА ПОДАЧИ (этап 42, по CSS кабинета).

 Шапка шагов — градиентная .ehero #add-screen (прокручивается вместе со страницей), у старта — .rw2-hd с «+» или «‹»,
 у загрузки, ошибки и гостя — простая строка с «✕». Окно распознавания — #airec-modal с «Заполнить вручную»
 (airecManual), окно итога — _modOver сайта; длинный текст сервера прокручивается, кнопки всегда видны.
 */

// MARK: - Простая шапка

/// Строка «Новое объявление» и «✕» — у загрузки, ошибки и гостя (своей шапки у них на сайте нет).
struct ШапкаПодачи: View {
    let правка: Bool
    let закрыть: () -> Void

    init(правка: Bool, закрыть: @escaping () -> Void) {
        self.правка = правка
        self.закрыть = закрыть
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ПодачаText.т(правка ? "edit_title" : "form_title_new"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            КнопкаЗакрытьПодачи(действие: закрыть)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(КраскаПодачи.карточка)
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }
}

/// «✕» .rw2-x: 34×34, скругление 10, на --surf2.
struct КнопкаЗакрытьПодачи: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .frame(width: 34, height: 34)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ПодачаText.т("close"))
    }
}

// MARK: - Градиентная шапка шагов (.ehero)

/// #add-screen .ehero: градиент 135° --g2 → --g, скругление 14, блик в углу, «Новое объявление», подзаголовок,
/// справа круглая кнопка (на сайте «?», здесь «✕») и плашка «Черновик» (в правке — «Опубликовано»).
struct ГеройПодачи: View {
    let правка: Bool
    let закрыть: () -> Void

    init(правка: Bool, закрыть: @escaping () -> Void) {
        self.правка = правка
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Тёмная тема и правка — затемнение linear-gradient(rgba(6,10,14,.44), rgba(6,10,14,.52)).
    private var затемнение: Color {
        if правка { return Color(uiColor: Theme.hex(0x060A0E, 0.48)) }
        return Theme.цвет(светлый: Theme.hex(0x060A0E, 0), тёмный: Theme.hex(0x060A0E, 0.48))
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(т(правка ? "edit_title" : "form_title_new"))
                    .font(.system(size: 19, weight: .heavy))
                    .kerning(-0.3)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(т(правка ? "edit_sub" : "form_hero_sub"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(action: закрыть) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.2), in: Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("close"))
                плашка
            }
            .fixedSize()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .topLeading, endPoint: .bottomTrailing)
                затемнение
                Circle()
                    .fill(RadialGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: 63))
                    .frame(width: 180, height: 180)
                    .offset(x: 50, y: -50)
            }
            .clipShape(форма)
        }
        .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.35)), radius: 8, y: 10)
        .padding(.horizontal, -2)
        .padding(.bottom, 2)
    }

    /// .estatus: точка --acc-rgb2 с кольцом 30 %, 11/700 белым на белом 20 %.
    private var плашка: some View {
        let точка = Color(uiColor: Theme.hex(0x34C997))
        return HStack(spacing: 6) {
            Circle()
                .fill(точка)
                .frame(width: 6, height: 6)
                .background(Circle().fill(точка.opacity(0.3)).frame(width: 12, height: 12))
                .accessibilityHidden(true)
            Text(т(правка ? "edit_pill" : "draft"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.2), in: Capsule())
    }
}

// MARK: - Стартовый экран «Что размещаете?»

/// Высота содержимого стартового экрана подачи (для растяжки плиток на высоких телефонах).
struct ВысотаСодержимогоСтартаПодачиКлюч: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Высота сетки плиток стартового экрана подачи.
struct ВысотаСеткиСтартаПодачиКлюч: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct СтартПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let работа: () -> Void
    let перенос: () -> Void
    let закрыть: () -> Void

    init(модель: ПодачаМодель, работа: @escaping () -> Void, перенос: @escaping () -> Void,
         закрыть: @escaping () -> Void) {
        self.модель = модель
        self.работа = работа
        self.перенос = перенос
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Плитка: ключ, заголовок, подпись, значок.
    private struct Плитка: Identifiable {
        let id: String
        let заголовок: String
        let подпись: String
        let значок: String
    }

    /// Высота окна прокрутки под шапкой.
    @State private var высотаОкна: CGFloat = 0
    /// Высота содержимого и одного ряда плиток без растяжки (замер минус текущая добавка).
    @State private var естСодержимое: CGFloat = 0
    @State private var естРяд: CGFloat = 0

    /// Сколько прибавить к высоте каждого ряда плиток, чтобы экран был заполнен без пустоты снизу:
    /// не больше 40 % ряда (плитка до 1,4 ×); не влезает (iPhone SE) — ноль и прокрутка.
    private var добавка: CGFloat {
        let рядов = CGFloat((плитки.count + 1) / 2)
        guard рядов > 0, естРяд > 1, естСодержимое > 1, высотаОкна > 1 else { return 0 }
        let свободно: CGFloat = высотаОкна - естСодержимое
        let наРяд: CGFloat = max(0, свободно / рядов)
        return min(наРяд, естРяд * 0.4).rounded(.down)
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            GeometryReader { окно in
                прокрутка
                    .onAppear { высотаОкна = окно.size.height }
                    .onChange(of: окно.size.height) { _, новое in высотаОкна = новое }
            }
        }
    }

    /// Замер содержимого без растяжки: из высоты вычитается текущая добавка всех рядов.
    private func замеритьСодержимое(_ высота: CGFloat) {
        let рядов = CGFloat((плитки.count + 1) / 2)
        let ест: CGFloat = высота - рядов * добавка
        if abs(ест - естСодержимое) > 0.5 { естСодержимое = ест }
    }

    private func замеритьСетку(_ высота: CGFloat) {
        let рядов = CGFloat((плитки.count + 1) / 2)
        guard рядов > 0 else { return }
        let промежутки: CGFloat = (рядов - 1) * 10
        let ряд: CGFloat = (высота - рядов * добавка - промежутки) / рядов
        if abs(ряд - естРяд) > 0.5 { естРяд = ряд }
    }

    private var прокрутка: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(вопрос)
                        .font(.system(size: 16, weight: .heavy))
                        .kerning(-0.2)
                        .foregroundStyle(КраскаПодачи.текст)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(подсказка)
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    сетка
                        .background(
                            GeometryReader { г in
                                Color.clear.preference(key: ВысотаСеткиСтартаПодачиКлюч.self, value: г.size.height)
                            }
                        )
                        .padding(.top, 14)
                    if модель.старт == .аренда { срокАренды }
                    if модель.старт == .корень { переносСсылкой }
                }
                .padding(EdgeInsets(top: 16, leading: 20, bottom: 20, trailing: 20))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { г in
                        Color.clear.preference(key: ВысотаСодержимогоСтартаПодачиКлюч.self, value: г.size.height)
                    }
                )
            }
            .background(КраскаПодачи.поле)
            .onPreferenceChange(ВысотаСодержимогоСтартаПодачиКлюч.self) { новое in замеритьСодержимое(новое) }
            .onPreferenceChange(ВысотаСеткиСтартаПодачиКлюч.self) { новое in замеритьСетку(новое) }
    }

    // MARK: Шапка .rw2-hd

    private var шапка: some View {
        HStack(spacing: 12) {
            if модель.старт == .корень {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .shadow(color: Color(uiColor: Theme.hex(0x34C997, 0.4)), radius: 6, y: 6)
                    .accessibilityHidden(true)
            } else {
                Button { назад() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .frame(width: 34, height: 34)
                        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("back"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(т("form_title_new"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Text(подзаголовок)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            КнопкаЗакрытьПодачи(действие: закрыть)
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(КраскаПодачи.карточка)
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }

    /// #as-sub: на корне «Выберите, что размещаете», ниже — имя раздела.
    private var подзаголовок: String {
        switch модель.старт {
        case .корень: return т("as_sub")
        case .товар: return т("as_goods")
        case .одежда: return т("as_clothing")
        case .животные: return т("as_animals")
        case .аренда: return т("as_rentgood")
        case .сделка, .видНедвижимости: return т("as_realty")
        case .транспорт: return т("as_auto")
        }
    }

    // MARK: Плитки .rw2-tiles

    /// Сетка 2 × 1fr: плитки одного ряда — одной высоты, как у CSS grid.
    private var сетка: some View {
        let все = плитки
        let рядов = (все.count + 1) / 2
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<рядов, id: \.self) { р in
                GridRow {
                    плитка(все[р * 2])
                    if р * 2 + 1 < все.count {
                        плитка(все[р * 2 + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private func плитка(_ п: Плитка) -> some View {
        Button {
            нажата(п.id)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: п.значок)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(КраскаПодачи.акцентТекст)
                    .frame(width: 24, height: 24)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text(п.заголовок)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !п.подпись.isEmpty {
                    Text(п.подпись)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            /* Добавка поровну сверху и снизу: значок и текст остаются по центру плитки. */
            .padding(.vertical, 16 + добавка / 2)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .accessibilityElement(children: .combine)
    }

    // MARK: «Или сразу укажите срок» (_ASTART_RENT)

    private var срокАренды: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("as_rent_lbl").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.66)
                .foregroundStyle(КраскаПодачи.текст.opacity(0.58))
            HStack(spacing: 8) {
                чипСрока(т("as_rent_day"), период: "day")
                чипСрока(т("as_rent_month"), период: "month")
            }
        }
        .padding(.top, 16)
    }

    /// .rw2-chip: сразу форма без раздела с этим сроком (_asRentGo('', период)).
    private func чипСрока(_ подпись: String, период: String) -> some View {
        Button {
            модель.применитьСтарт(тип: "rentgood", раздел: "", плитка: т("as_rentgood"), подсказка: "", период: период,
                                  подпись: т("as_rentgood_s"))
        } label: {
            Text(подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 46)
                .background(КраскаПодачи.карточка, in: Capsule())
                .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    // MARK: Перенос по ссылке (.li-entry)

    private var переносСсылкой: some View {
        Button(action: перенос) {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("li_entry_t"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(т("li_entry_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }

    // MARK: Тексты и плитки

    private var вопрос: String {
        switch модель.старт {
        case .корень: return т("as_root_q")
        case .товар: return т("as_goods_q")
        case .одежда: return т("as_cloth_q")
        case .животные: return т("as_anim_q")
        case .аренда: return т("as_rent_q")
        case .сделка: return т("as_rl_deal_q")
        case .видНедвижимости: return т("as_rl_kind_q")
        case .транспорт: return т("as_auto_q")
        }
    }

    private var подсказка: String {
        switch модель.старт {
        case .корень: return т("as_root_s")
        case .товар: return т("as_goods_s")
        case .одежда: return т("as_cloth_s")
        case .животные: return т("as_anim_s")
        case .аренда: return т("as_rent_s")
        case .сделка: return т("as_rl_deal_s")
        case .видНедвижимости: return т("as_rl_kind_s")
        case .транспорт: return т("as_auto_s")
        }
    }

    /// _ASTART, _ASTART_GOODS, _ASTART_CLOTH, _ASTART_ANIMALS, _ASTART_RENT, _ASTART_REALTY, _ASTART_AUTO сайта.
    private var плитки: [Плитка] {
        switch модель.старт {
        case .корень:
            return [
                Плитка(id: "clothing", заголовок: т("as_clothing"), подпись: т("as_clothing_s"), значок: "tshirt"),
                Плитка(id: "animals", заголовок: т("as_animals"), подпись: т("as_animals_s"), значок: "pawprint"),
                Плитка(id: "goods", заголовок: т("as_goods"), подпись: т("as_goods_sub"), значок: "shippingbox"),
                Плитка(id: "realty", заголовок: т("as_realty"), подпись: т("as_realty_s"), значок: "house"),
                Плитка(id: "auto", заголовок: т("as_auto"), подпись: т("as_auto_sub"), значок: "car"),
                Плитка(id: "services", заголовок: т("as_services"), подпись: т("as_services_s"), значок: "wrench.and.screwdriver"),
                Плитка(id: "jobs", заголовок: т("as_jobs"), подпись: т("as_jobs_s"), значок: "briefcase"),
                Плитка(id: "rentgood", заголовок: т("as_rentgood"), подпись: т("as_rentgood_s"), значок: "arrow.triangle.2.circlepath")
            ]
        case .товар:
            return [
                Плитка(id: "smartphones|phone", заголовок: т("g_phone"), подпись: т("g_phone_s"), значок: "iphone"),
                Плитка(id: "laptops|laptop", заголовок: т("g_laptop"), подпись: т("g_laptop_s"), значок: "laptopcomputer"),
                Плитка(id: "appliances|appliance", заголовок: т("g_appl"), подпись: т("g_appl_s"), значок: "washer"),
                Плитка(id: "tv-audio|appliance", заголовок: т("g_tv"), подпись: т("g_tv_s"), значок: "tv"),
                Плитка(id: "furniture|furniture", заголовок: т("g_furn"), подпись: т("g_furn_s"), значок: "sofa"),
                Плитка(id: "|other", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .одежда:
            return [
                Плитка(id: "womens-clothing|clothes", заголовок: т("c_women"), подпись: т("c_women_s"), значок: "tshirt"),
                Плитка(id: "mens-clothing|clothes", заголовок: т("c_men"), подпись: т("c_men_s"), значок: "tshirt"),
                Плитка(id: "kids-clothing|clothes", заголовок: т("c_kids"), подпись: т("c_kids_s"), значок: "figure.and.child.holdinghands"),
                Плитка(id: "shoes|shoes", заголовок: т("c_shoes"), подпись: т("c_shoes_s"), значок: "shoeprints.fill"),
                Плитка(id: "bags-accessories|clothes", заголовок: т("c_bags"), подпись: т("c_bags_s"), значок: "bag"),
                Плитка(id: "jewelry|other", заголовок: т("c_jewel"), подпись: т("c_jewel_s"), значок: "sparkles")
            ]
        case .животные:
            return [
                Плитка(id: "dogs|", заголовок: т("a_dogs"), подпись: т("a_dogs_s"), значок: "pawprint"),
                Плитка(id: "cats|", заголовок: т("a_cats"), подпись: т("a_cats_s"), значок: "cat"),
                Плитка(id: "birds|", заголовок: т("a_birds"), подпись: т("a_birds_s"), значок: "bird"),
                Плитка(id: "livestock|", заголовок: т("a_stock"), подпись: т("a_stock_s"), значок: "hare"),
                Плитка(id: "rodents|", заголовок: т("a_rod"), подпись: т("a_rod_s"), значок: "hare"),
                Плитка(id: "fish-aquariums|", заголовок: т("a_fish"), подпись: т("a_fish_s"), значок: "fish"),
                Плитка(id: "pet-food-care|", заголовок: т("a_food"), подпись: т("a_food_s"), значок: "takeoutbag.and.cup.and.straw"),
                Плитка(id: "animals|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "pawprint")
            ]
        case .аренда:
            return [
                Плитка(id: "power-tools|", заголовок: т("r_tools"), подпись: т("r_tools_s"), значок: "hammer"),
                Плитка(id: "electronics|", заголовок: т("r_tech"), подпись: т("r_tech_s"), значок: "camera"),
                Плитка(id: "sport|", заголовок: т("r_sport"), подпись: т("r_sport_s"), значок: "figure.hiking"),
                Плитка(id: "home-garden|", заголовок: т("r_home"), подпись: т("r_home_s"), значок: "leaf"),
                Плитка(id: "|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .сделка:
            return [
                Плитка(id: "sale", заголовок: т("as_rl_sale"), подпись: "", значок: "house"),
                Плитка(id: "rent", заголовок: т("as_rl_rent"), подпись: "", значок: "key")
            ]
        case .видНедвижимости:
            return [
                Плитка(id: "apartment|apartments", заголовок: т("rl_flat"), подпись: т("rl_flat_s"), значок: "building.2"),
                Плитка(id: "house|houses", заголовок: т("rl_house"), подпись: т("rl_house_s"), значок: "house"),
                Плитка(id: "commercial|commercial-realty", заголовок: т("rl_office"), подпись: т("rl_office_s"), значок: "building"),
                Плитка(id: "land|land", заголовок: т("rl_land"), подпись: т("rl_land_s"), значок: "map")
            ]
        case .транспорт:
            return [
                Плитка(id: "cars", заголовок: т("t_cars"), подпись: т("t_cars_s"), значок: "car"),
                Плитка(id: "motorcycles", заголовок: т("t_moto"), подпись: т("t_moto_s"), значок: "bicycle"),
                Плитка(id: "trucks-special", заголовок: т("t_truck"), подпись: т("t_truck_s"), значок: "truck.box"),
                Плитка(id: "auto-parts", заголовок: т("t_parts"), подпись: т("t_parts_s"), значок: "gearshape.2"),
                Плитка(id: "water-transport", заголовок: т("t_water"), подпись: т("t_water_s"), значок: "sailboat")
            ]
        }
    }

    /// ADD_HINTS сайта: подсказка Kliko AI по чипу — идёт на сервер как есть (по-русски, её читает модель).
    private static let подсказки: [String: String] = [
        "phone": "Это смартфон/мобильный телефон", "laptop": "Это ноутбук", "clothes": "Это одежда",
        "shoes": "Это обувь", "furniture": "Это мебель", "appliance": "Это бытовая техника"
    ]

    private func нажата(_ id: String) {
        let подпись = подписьПлитки(id)
        let под = подзаголовокПлитки(id)
        switch модель.старт {
        case .корень:
            if id == "jobs" {
                /* Мастер «Работы» шлёт в /api/jobs.php свой набор полей (jobWizOpen) — свой мастер МастерРезюме
                   (cabinet?add=jobs перехватывают НативныеОкна). */
                работа()
                return
            }
            модель.выбратьПлитку(id)
        case .товар, .одежда:
            let части = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let раздел = части.first ?? ""
            let чип = части.count > 1 ? части[1] : ""
            модель.применитьСтарт(тип: "goods", раздел: раздел, плитка: подпись, подсказка: Self.подсказки[чип] ?? "",
                                  подпись: под)
        case .животные:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "goods", раздел: раздел, плитка: подпись, подсказка: "", подпись: под)
        case .аренда:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "rentgood", раздел: раздел, плитка: подпись, подсказка: "", период: nil,
                                  подпись: под)
        case .сделка:
            модель.старт = .видНедвижимости(id)
        case .видНедвижимости(let сделка):
            let части = id.split(separator: "|").map(String.init)
            guard части.count == 2 else { return }
            модель.применитьНедвижимость(сделка: сделка, вид: части[0], раздел: части[1])
        case .транспорт:
            /* _asAutoGo: ADD_TYPE="" — тип «транспорт» без отдельного значения; уточнение кузова — на шаге «Данные». */
            модель.применитьСтарт(тип: "", раздел: id, плитка: подпись, подсказка: "", подпись: под)
        }
    }

    private func подписьПлитки(_ id: String) -> String {
        плитки.first(where: { $0.id == id })?.заголовок ?? ""
    }

    private func подзаголовокПлитки(_ id: String) -> String {
        плитки.first(where: { $0.id == id })?.подпись ?? ""
    }

    private func назад() {
        switch модель.старт {
        case .видНедвижимости:
            модель.старт = .сделка
        default:
            модель.старт = .корень
        }
    }
}

// MARK: - Гость (#guest-add-card)

/// Тизер «Новое объявление» для гостя: зона фото и «Заполнить вручную» — любое нажатие ведёт ко входу.
struct ГостьПодачи: View {
    let войти: () -> Void

    init(войти: @escaping () -> Void) {
        self.войти = войти
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Карточка по центру экрана: на высоком телефоне без пустоты снизу, на маленьком — прокрутка.
    var body: some View {
        GeometryReader { окно in
            ScrollView {
                карточка
                    .padding(14)
                    .frame(minHeight: окно.size.height)
            }
        }
    }

    private var карточка: some View {
            КарточкаПодачи {
                VStack(alignment: .leading, spacing: 0) {
                    Text(т("guest_t"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(т("guest_s"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    Button(action: войти) {
                        VStack(spacing: 8) {
                            Image(systemName: "camera")
                                .font(.system(size: 32, weight: .regular))
                                .foregroundStyle(Theme.текстВторой)
                                .accessibilityHidden(true)
                            Text(т("guest_tap"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(КраскаПодачи.текст)
                                .multilineTextAlignment(.center)
                            Text(String(format: т("form_photo_hint"), 5))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    Button(action: войти) {
                        Label(т("form_manual"), systemImage: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1.5)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            }
    }
}

// MARK: - Окно «Kliko AI распознаёт товар» (#airec-modal)

struct ОкноРаспознавания: View {
    let шаг: Int
    let отмена: () -> Void

    init(шаг: Int, отмена: @escaping () -> Void) {
        self.шаг = шаг
        self.отмена = отмена
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    private static let тёмныйЗелёный = Color(uiColor: Theme.hex(0x1D7D4A))
    private static let глубокийЗелёный = Color(uiColor: Theme.hex(0x0F5132))

    var body: some View {
        ZStack {
            Color(red: 8 / 255, green: 20 / 255, blue: 14 / 255).opacity(0.72).ignoresSafeArea()
            VStack(spacing: 0) {
                верх
                низ
            }
            .frame(maxWidth: 350)
            .background(КраскаПодачи.карточка)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 40, y: 30)
            .padding(20)
        }
    }

    /// .airec-top: градиент, «шар» с искрами, заголовок и подзаголовок.
    private var верх: some View {
        VStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 70, height: 70)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(т(шаг >= 4 ? "airec_done_t" : "airec_t_light"))
                .font(.system(size: 19, weight: .heavy))
                .kerning(-0.3)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
            Text(т(шаг >= 4 ? "airec_done_l" : "airec_s_light"))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.цвет(0x1D7D4A, 0x34C997), Theme.цвет(0x0F5132, 0x22A05B)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .combine)
    }

    /// .airec-body: полоса хода, четыре шага, «Заполнить вручную».
    private var низ: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { г in
                ZStack(alignment: .leading) {
                    Capsule().fill(КраскаПодачи.хорошоФон)
                    Capsule()
                        .fill(LinearGradient(colors: [Self.тёмныйЗелёный, Self.глубокийЗелёный], startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: г.size.width * CGFloat(min(max(шаг, 0), 4)) / 4)
                }
            }
            .frame(height: 8)
            .animation(ДвижениеСайта.шаг, value: шаг)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(1...4, id: \.self) { номер in
                    строка(номер)
                }
            }
            .padding(.top, 20)
            Button(action: отмена) {
                Text(т("form_manual"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(24)
    }

    private func строка(_ номер: Int) -> some View {
        let готов = номер < шаг || шаг >= 4
        let идёт = номер == шаг && шаг < 4
        return HStack(spacing: 12) {
            ZStack {
                if готов {
                    Circle().fill(Color(uiColor: Theme.hex(0x0F9D58)))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                } else if идёт {
                    Circle()
                        .fill(Color(uiColor: Theme.hex(0x34C997, 0.12)))
                        .frame(width: 34, height: 34)
                    Circle().fill(КраскаПодачи.хорошоФон)
                    Text(String(номер))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.цвет(0x0F5132, 0x5CD39A))
                } else {
                    Circle().fill(КраскаПодачи.поле)
                    Text(String(номер))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            Text(т("airec_l" + String(номер)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(готов || идёт ? КраскаПодачи.текст : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if идёт {
                SiteSpinner(размер: 16, толщина: 2)
            }
        }
    }
}

// MARK: - Окно итога подачи (_modOver, §2.5.2)

struct ОкноИтогаПодачи: View {
    enum Действие { case готово, верификация }

    let итог: ИтогПодачи
    let заголовок: String
    let действие: (Действие) -> Void

    init(итог: ИтогПодачи, заголовок: String, действие: @escaping (Действие) -> Void) {
        self.итог = итог
        self.заголовок = заголовок
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            /* Длинная причина от сервера на iPhone SE — карточка прокручивается, кнопки не уходят за край. */
            ViewThatFits(in: .vertical) {
                карточка
                ScrollView {
                    карточка
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(20)
        }
    }

    private var отказ: Bool {
        switch итог {
        case .отклонено, .запрещено: return true
        default: return false
        }
    }

    private var карточка: some View {
        VStack(spacing: 0) {
            Image(systemName: значок)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(цвет)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(заглавие)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(текст)
                .font(.system(size: 14))
                .lineSpacing(отказ ? 4 : 7)
                .foregroundStyle(отказ ? КраскаПодачи.плохоТекст : КраскаПодачи.текст)
                .multilineTextAlignment(отказ ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: отказ ? .leading : .center)
                .background(отказ ? Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255).opacity(0.08) : КраскаПодачи.поле,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.top, 12)
            VStack(spacing: 10) {
                кнопки
            }
            .padding(.top, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: 400)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 30, y: 20)
    }

    @ViewBuilder
    private var кнопки: some View {
        switch итог {
        case .опубликовано(let id):
            if let ссылка = Config.url("/marketplace.php?item=" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)),
               !id.isEmpty {
                ShareLink(item: ссылка, subject: Text(заголовок), message: Text(заголовок)) {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(Theme.акцент)
            }
            КнопкаПодачи(т("mod_ok")) { действие(.готово) }
        case .ждётВерификации:
            КнопкаПодачи(т("held_verify_go")) { действие(.верификация) }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .неактивные(_, let верификация):
            /* «Расширить слоты» — окно покупки App Store, только при Config.цифровыеПокупки; иначе кнопки нет. */
            if верификация {
                КнопкаПодачи(т("verify_plus5")) { действие(.верификация) }
                if Config.цифровыеПокупки {
                    КнопкаПодачиВторая(т("limit_more")) { ЛистУслугиApple.показать(.слоты) }
                }
                КнопкаПодачиВторая(т("later")) { действие(.готово) }
            } else if Config.цифровыеПокупки {
                КнопкаПокупкиApple(подпись: т("slots_more"), значок: "square.stack.3d.up") { ЛистУслугиApple.показать(.слоты) }
                КнопкаПодачиВторая(т("later")) { действие(.готово) }
            } else {
                КнопкаПодачи(т("mod_ok")) { действие(.готово) }
            }
        case .лимит:
            if Config.цифровыеПокупки {
                КнопкаПокупкиApple(подпись: т("limit_more"), значок: "square.stack.3d.up") { ЛистУслугиApple.показать(.слоты) }
                КнопкаПодачиВторая(т("later")) { действие(.готово) }
            } else {
                КнопкаПодачи(т("mod_ok")) { действие(.готово) }
            }
        case .наПроверке, .отклонено, .сохраненоИИ, .запрещено:
            КнопкаПодачи(т("mod_ok")) { действие(.готово) }
        }
    }

    private var значок: String {
        switch итог {
        case .опубликовано: return "checkmark.circle"
        case .наПроверке, .ждётВерификации: return "clock"
        case .отклонено, .запрещено: return "xmark.circle"
        case .сохраненоИИ: return "doc.text"
        case .неактивные, .лимит: return "square.stack.3d.up"
        }
    }

    private var цвет: Color {
        switch итог {
        case .опубликовано, .наПроверке, .ждётВерификации: return КраскаПодачи.акцентТекст
        case .отклонено, .запрещено: return КраскаПодачи.плохоТекст
        case .сохраненоИИ, .неактивные, .лимит: return Theme.текстВторой
        }
    }

    private var заглавие: String {
        switch итог {
        case .опубликовано: return т("published")
        case .наПроверке: return т("mod_wait_t")
        case .отклонено: return т("mod_rej_t")
        case .сохраненоИИ: return т("mod_saved_t")
        case .ждётВерификации: return т("held_pub_t")
        case .неактивные: return т("held_t")
        case .лимит: return т("limit_t")
        case .запрещено(let з, _): return з
        }
    }

    private var текст: String {
        switch итог {
        case .опубликовано: return т("published_s")
        case .наПроверке: return т("mod_wait_b") + "\n" + т("mod_wait_b2") + " — " + т("mod_wait_b3")
        case .отклонено(let причина): return причина
        case .сохраненоИИ(let часы):
            let блок = [т("mod_blk_b"), часы.isEmpty ? "24" : часы, т("mod_h")].joined(separator: " ")
            return блок + "\n" + т("mod_blk_b2")
        case .ждётВерификации(let ошибка): return ошибка.isEmpty ? т("held_pub_m") : т("held_pub_m") + "\n\n" + ошибка
        case .неактивные(let т1, _): return т1
        case .лимит(let т1): return т1
        case .запрещено(_, let т1): return т1
        }
    }
}
