import SwiftUI
import UIKit

/**
 ВИТРИНА ПРОДАВЦА — СВОЙ ЭКРАН ВМЕСТО seller.php (владелец 26.09.2026: «всё приложение нативное, ровное и стильное»).

 Раньше «Профиль продавца», «Все товары продавца», «Профиль» в отзывах, строка подписки на продавца и профиль в
 настройках открывали страницу сайта — приложение целиком уходило на WKWebView. Теперь — свой экран поверх того, где
 нажали (ПоверхВсего: из листа продавца, карточки сделки, чата), в краске сайта:
   · шапка: полоса цвета магазина (shop_accent, .mk-cbrand сайта; нет — зелёный градиент шапки), аватар или буква,
     имя, «Проверенный продавец», звёзды и оценка, «N сделок · N подписчиков · На Kliko с …»;
   · «Подписаться на продавца» (этап 36) — не на своей витрине;
   · объявления — карточки витрины (ListingCard, mkVitCardHTML) в той же сетке, что лента; нажатие — своя карточка
     объявления в стеке витрины, сердце и «Поделиться» — как в ленте;
   · отзывы — сводка seller_reviews.php (оценка, распределение) и три последних; «Все отзывы» — лист этапа 37.
 Данные — ВитринаПродавцаAPI (StorefrontAPI.swift).
 */
@MainActor
enum ОкноПродавца {
    /// Открыть витрину продавца поверх текущего экрана. Номер негодный — false: вызывающий идёт своим путём.
    @discardableResult
    static func открыть(id: String, имя: String = "") -> Bool {
        let номер = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ВитринаПродавцаAPI.годный(номер) else { return false }
        ПоверхВсего.показать { закрыть in
            ЭкранВитриныПродавца(продавецID: номер, имя: имя, закрыть: закрыть)
        }
        return true
    }

    /// Номер продавца из адреса страницы продавца сайта: /seller.php?id=, /kz/<язык>/seller.php?id=, /seller?id=.
    nonisolated static func номер(из адрес: URL) -> String? {
        guard let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: false) else { return nil }
        if let хост = части.host?.lowercased(), хост != "kliko.kz" && хост != "www.kliko.kz" { return nil }
        guard части.path.range(of: "^(/[a-z]{2}/[a-z]{2})?/seller(\\.php)?/?$", options: .regularExpression) != nil,
              (части.fragment ?? "").isEmpty else { return nil }
        let номер = (части.queryItems ?? []).first(where: { $0.name == "id" })?.value ?? ""
        return ВитринаПродавцаAPI.годный(номер) ? номер : nil
    }

    /// Для корневого «открыть»: страница продавца — своя витрина, true; иначе false. Ссылка по нику (/s/<ник>,
    /// seller.php?u=<ник>) — тоже витрина: номер узнаётся по нику (у сайта ?u= главнее ?id=).
    static func перехватить(_ адрес: URL) -> Bool {
        if let ник = ник(из: адрес) { return открыть(ник: ник) }
        guard let номер = номер(из: адрес) else { return false }
        return открыть(id: номер)
    }

    /**
     Ник витрины из короткой ссылки магазина: /s/<ник> (.htaccess сайта: → seller.php?u=<ник>) и /seller.php?u=<ник>, с
     /kz/<язык> впереди или без. Нормализация — store_handle_norm сайта: строчные, только a-z, 0-9 и «-», без «-» по краям.
     */
    nonisolated static func ник(из адрес: URL) -> String? {
        guard let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: false) else { return nil }
        if let хост = части.host?.lowercased(), хост != "kliko.kz" && хост != "www.kliko.kz" { return nil }
        guard (части.fragment ?? "").isEmpty else { return nil }
        let путь = части.path
        var сырой = ""
        if путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/s/[A-Za-z0-9-]+/?$", options: .regularExpression) != nil {
            сырой = путь.split(separator: "/").last.map(String.init) ?? ""
        } else if путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/seller(\\.php)?/?$", options: .regularExpression) != nil {
            сырой = (части.queryItems ?? []).first(where: { $0.name == "u" })?.value ?? ""
        } else {
            return nil
        }
        let допустимые = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let чистый = String(сырой.lowercased().filter { допустимые.contains($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !чистый.isEmpty, чистый.count <= 40 else { return nil }
        return чистый
    }

    /// Витрина по нику: пока номер ищется — «Загружаем витрину…», не нашёлся — «Продавец не найден» (своим экраном).
    @discardableResult
    static func открыть(ник: String) -> Bool {
        ПоверхВсего.показать { закрыть in
            ЭкранВитриныПоНику(ник: ник, закрыть: закрыть)
        }
        return true
    }
}

/// Короткая ссылка магазина (/s/<ник>): номер продавца по нику, затем обычная витрина; нет такого — «Продавец не найден».
struct ЭкранВитриныПоНику: View {
    let ник: String
    let закрыть: () -> Void

    @State private var итог: ВитринаПродавцаAPI.ПоискПоНику? = nil
    @State private var попытка = 0

    private func т(_ ключ: String) -> String { StorefrontText.т(ключ) }

    private var найденный: String? {
        if case .найден(let номер)? = итог { return номер }
        return nil
    }

    var body: some View {
        if let номер = найденный {
            ЭкранВитриныПродавца(продавецID: номер, имя: "", закрыть: закрыть)
        } else {
            NavigationStack {
                ожидание
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.фонСтраницы.ignoresSafeArea())
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Theme.поверхность, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(т("close")) { закрыть() }
                        }
                    }
            }
            .tint(Theme.акцент)
            .task(id: попытка) { await найти() }
        }
    }

    @ViewBuilder
    private var ожидание: some View {
        switch итог {
        case .нетПродавца?:
            ПустоСайта(значок: "person.crop.circle.badge.questionmark", заголовок: т("nf_title"),
                       подпись: т("nf_sub"), кнопка: т("close"), действие: { закрыть() })
        case .нетСвязи?:
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("no_conn"), кнопка: т("retry"),
                       действие: { попытка += 1 })
        default:
            HStack(spacing: 10) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    private func найти() async {
        итог = nil
        let пришло = await ВитринаПродавцаAPI.номерПоНику(ник)
        guard !Task.isCancelled else { return }
        итог = пришло
    }
}

struct ЭкранВитриныПродавца: View {
    let продавецID: String
    let имя: String
    let закрыть: () -> Void

    enum Состояние: Equatable {
        case загрузка
        case ошибка
        case готово
    }

    @ObservedObject private var подписки = СинхронПодписок.shared
    @ObservedObject private var действия = ДействияСПродавцом.shared
    @State private var витрина: ВитринаПродавца
    @State private var состояние: Состояние = .загрузка
    @State private var сводка: ОтзывыПродавца.Сводка? = nil
    @State private var путь = NavigationPath()
    @State private var отзывыОткрыты = false
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(продавецID: String, имя: String, закрыть: @escaping () -> Void) {
        self.продавецID = продавецID
        self.имя = имя
        self.закрыть = закрыть
        _витрина = State(initialValue: ВитринаПродавца(id: продавецID, имя: имя))
    }

    private func т(_ ключ: String) -> String { StorefrontText.т(ключ) }

    private var свой: Bool { подписки.мой == продавецID || действия.мой == продавецID }

    private var показИмени: String {
        let и = витрина.имя.isEmpty ? имя : витрина.имя
        return и.isEmpty ? т("seller") : и
    }

    var body: some View {
        NavigationStack(path: $путь) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ШапкаВитрины(витрина: витрина, имя: показИмени, сводка: сводка, подписчики: подписчики)
                    if Config.подпискиССайтом && !свой {
                        КнопкаПодпискиНаПродавца(продавецID: продавецID, имя: показИмени)
                    }
                    содержимое
                }
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .refreshable { await загрузить(заново: true) }
            // имя уже крупно в шапке — в полосе окна не повторяем
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.поверхность, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
                if let адрес = ВитринаПродавцаAPI.адрес(продавецID) {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: адрес) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(т("share"))
                    }
                }
            }
            .navigationDestination(for: Listing.self) { товар in
                ListingDetailView(товар: товар, открыть: открытьАдрес)
            }
            .чатМаршруты(открыть: открытьАдрес)
        }
        .environment(\.открытьОбъявлениеВСтеке, { товар in путь.append(товар) })   // долгое нажатие на карточку
        .tint(Theme.акцент)
        .overlay(alignment: .bottom) {
            ПлашкиВЛистеПродавца(закрытьЛист: {})
        }
        .sheet(isPresented: $отзывыОткрыты) {
            ЛистОтзывовПродавца(продавецID: продавецID, имя: показИмени, свой: свой, профиль: false)
        }
        .task(id: продавецID) { await загрузить(заново: false) }
    }

    /// Свежее число с сайта (subs.php), пока его нет — seller_followers объявлений.
    private var подписчики: Int? {
        if Config.подпискиССайтом, let свежее = подписки.подписчиков(продавецID) { return свежее }
        return витрина.подписчиков
    }

    @ViewBuilder
    private var содержимое: some View {
        switch состояние {
        case .загрузка:
            HStack(spacing: 10) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        case .ошибка:
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("fail"), кнопка: т("retry"),
                       действие: { Task { @MainActor in await загрузить(заново: true) } })
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
        case .готово:
            блокОбъявлений
            блокОтзывов
        }
    }

    // MARK: - Объявления

    private var блокОбъявлений: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокБлокаВитрины(текст: т("listings"), число: витрина.товары.count)
                .padding(.horizontal, 16)
            if витрина.товары.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                    Text(т("empty"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(т("empty_sub"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
            } else {
                LazyVGrid(columns: ListingCard.сетка(размерТекста), spacing: ListingCard.зазор) {
                    ForEach(витрина.товары) { товар in
                        NavigationLink(value: товар) { ListingCard(товар: товар) }
                            .buttonStyle(.plain)
                            .сердечкоИзбранного(товар)
                            .поделитьсяНаКарточке(товар)
                            .менюКарточкиОбъявления(товар)
                    }
                }
                .padding(.horizontal, ListingCard.поле)
                if !витрина.полныйСписок {
                    Text(т("more_goods"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Отзывы

    @ViewBuilder
    private var блокОтзывов: some View {
        if Config.продавецОтзывы {
            VStack(alignment: .leading, spacing: 10) {
                ЗаголовокБлокаВитрины(текст: т("reviews"), число: сводка?.отзывов)
                if let сводка, сводка.отзывов > 0 || !сводка.отзывы.isEmpty {
                    ИтогОценок(сводка: сводка, фон: Theme.поверхность)
                    ForEach(сводка.отзывы.prefix(3)) { отзыв in
                        СтрокаОтзыва(отзыв: отзыв, фон: Theme.поверхность)
                    }
                    Button {
                        отзывыОткрыты = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(т("all_reviews"))
                            Image(systemName: "chevron.forward")
                                .font(.system(size: 12, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                } else {
                    Text(т("no_reviews"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Загрузка и переходы

    private func загрузить(заново: Bool) async {
        if !заново, состояние == .готово { return }
        if витрина.товары.isEmpty { состояние = .загрузка }
        if Config.подпискиССайтом { подписки.узнать(продавца: продавецID) }
        if Config.жалобы { действия.узнать(продавца: продавецID) }
        let пришло = await ВитринаПродавцаAPI.загрузить(продавецID, имя: имя)
        if let пришло {
            витрина = пришло
            состояние = .готово
        } else if витрина.товары.isEmpty {
            состояние = .ошибка
        }
        if Config.продавецОтзывы, let сводкаОтзывов = await действия.загрузитьОтзывы(продавецID) {
            сводка = сводкаОтзывов
        }
    }

    /// Ссылка сайта из карточки объявления внутри витрины: витрина закрывается, адрес идёт путём корня приложения.
    private func открытьАдрес(_ адрес: URL) {
        if let номер = ОкноПродавца.номер(из: адрес), номер == продавецID {
            путь = NavigationPath()
            return
        }
        закрыть()
        ПоверхВсего.открытьАдрес(адрес)
    }
}

// MARK: - Шапка

/// Шапка витрины: полоса цвета магазина, аватар 72, имя, «Проверенный продавец», звёзды и статистика.
private struct ШапкаВитрины: View {
    let витрина: ВитринаПродавца
    let имя: String
    let сводка: ОтзывыПродавца.Сводка?
    let подписчики: Int?

    private func т(_ ключ: String) -> String { StorefrontText.т(ключ) }

    private var буква: String {
        String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    /// Цвет магазина или зелёный шапки сайта.
    private var краска: Color {
        if let акцент = витрина.акцент { return Color(uiColor: Theme.hex(акцент)) }
        return Theme.шапкаВерх
    }

    private var оценка: Double? {
        if let сводка, сводка.отзывов > 0 { return сводка.оценка }
        return витрина.рейтинг
    }

    private var отзывов: Int {
        if let сводка { return сводка.отзывов }
        return витрина.отзывов ?? 0
    }

    private var сделок: Int {
        if let сводка, сводка.сделок > 0 { return сводка.сделок }
        return витрина.сделок ?? 0
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            полоса
            VStack(alignment: .leading, spacing: 8) {
                аватар
                    .offset(y: -36)
                    .padding(.bottom, -36)
                HStack(spacing: 8) {
                    Text(имя)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if витрина.акцент != nil {
                        Text(т("shop"))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(краска, in: Capsule())
                    }
                }
                if витрина.проверен {
                    Label(т("verified"), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.проверен)
                }
                строкаОценки
                статистика
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Theme.поверхность, in: форма)
        .clipShape(форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .padding(.horizontal, 16)
    }

    private var полоса: some View {
        LinearGradient(colors: [краска, краска.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 76)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "storefront")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.16))
                    .padding(12)
                    .accessibilityHidden(true)
            }
    }

    private var аватар: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return форма
            .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: 72, height: 72)
            .overlay {
                Text(буква.isEmpty ? "?" : буква)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
            .overlay {
                if let адрес = витрина.аватар {
                    КартинкаЛенты(адрес, пунктов: 72) { Color.clear }
                        .frame(width: 72, height: 72)
                        .clipShape(форма)
                }
            }
            .overlay {
                форма.strokeBorder(Theme.поверхность, lineWidth: 3)
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var строкаОценки: some View {
        if let оценка, оценка > 0 {
            let полных = Int(min(5, max(0, оценка)).rounded())
            let звёзды = String(repeating: "★", count: полных) + String(repeating: "☆", count: 5 - полных)
            HStack(spacing: 6) {
                Text(звёзды)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.звезда)
                Text(String(format: "%.1f", оценка))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if отзывов > 0 {
                    Text("· " + ListingPageText.число(отзывов, "reviews"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: SellerText.т("rating_of"), полных) + ", "
                                + ListingPageText.число(отзывов, "reviews"))
        } else {
            Text(т("new_seller"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// Плашки «N сделок», «N подписчиков», «На Kliko с …».
    private var статистика: some View {
        var пункты: [(String, String)] = []
        if сделок > 0 { пункты.append(("handshake", ListingPageText.число(сделок, "deals"))) }
        if let подписчики, подписчики > 0 { пункты.append(("person.2", SubsText.подписчики(подписчики))) }
        if let с = витрина.с, !с.isEmpty {
            let год = String(с.prefix(4))
            пункты.append(("calendar", String(format: т("since"), год)))
        }
        return ПотокПлашекВитрины(пункты: пункты)
    }
}

/// Плашки статистики в строку с переносом.
private struct ПотокПлашекВитрины: View {
    let пункты: [(String, String)]

    var body: some View {
        if !пункты.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { плашки }
                VStack(alignment: .leading, spacing: 6) { плашки }
            }
        }
    }

    @ViewBuilder
    private var плашки: some View {
        ForEach(Array(пункты.enumerated()), id: \.offset) { пара in
            Label(пара.element.1, systemImage: пара.element.0)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстПункта)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Theme.фонПункта, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1)
                }
        }
    }
}

/// «Объявления · 12» — заголовок блока витрины.
private struct ЗаголовокБлокаВитрины: View {
    let текст: String
    let число: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(текст)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            if let число, число > 0 {
                Text(String(число))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 0)
        }
    }
}
