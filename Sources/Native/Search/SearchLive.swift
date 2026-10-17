import SwiftUI

/**
 ЖИВЫЕ ТОВАРЫ В ПОДСКАЗКАХ ПОИСКА И ИИ-ПОИСК (владелец 17.10.2026: «ИИ поиск надо усовершенствовать — чтобы человек
 прям в поисковике видел рекомендации и нашёл то, что искал за счёт ИИ»; на план — «задание + живые товары в
 подсказках, все 4 порядка»). Задание сайту — docs/SERVER_AI_SEARCH.md.

 Пока набирают запрос, под строкой запроса — до 5 настоящих объявлений: фото, название, цена, город; касание — сразу
 объявление, «Показать все N» — выдача. Два источника:
   · search_live (в сборке включён) — нынешняя лента: api/listings.php?q=<запрос>&per=5 с городом ленты, без новых
     дверей на сервере;
   · ai_search (в сборке выключен, включит сервер, когда выложит порядки 1–4) — api/search_suggest.php: товары, «Вы имели
     в виду», чипы разбора Kliko AI («до 200 000 ₸», «Алматы»), причина под ценой (why), «Ничего точно — вот близкое»
     (relaxed); нажатия — в api/search_event.php (без входа, случайный номер установки). Не ответила дверь — лента.
 Ждём 220 мс после последней буквы, прежний запрос отменяется; ответы помнятся (до 40 запросов) — стирание буквы
 возвращает список сразу. Подсказки сайта (разделы, бренды, «Вы искали») — как были, товары — отдельной секцией.
 */
extension Config {
    static let живыеТоварыПоискаВСборке = true
    static var живыеТоварыПоиска: Bool { НастройкиСервера.вклВыкл("search_live", сборка: живыеТоварыПоискаВСборке) }
    static let умныйПоискВСборке = false
    static var умныйПоиск: Bool { НастройкиСервера.вклВыкл("ai_search", сборка: умныйПоискВСборке) }
}

/// Чип разбора запроса Kliko AI (порядок 2): подпись и параметр ленты, который он означает.
struct ЧипИИПоиска: Hashable, Identifiable {
    let подпись: String
    let параметр: String
    let значение: String
    var id: String { параметр + "=" + значение }
}

/// Что показать под строкой запроса.
struct ЖивыеТоварыПоиска: Equatable {
    var товары: [Listing] = []
    /// Сколько всего нашлось; nil — сервер не сказал.
    var всего: Int? = nil
    /// «Вы имели в виду» (did_you_mean).
    var вместо: String? = nil
    var чипы: [ЧипИИПоиска] = []
    /// Почему подошло (items[].why) — по номеру объявления.
    var почему: [String: String] = [:]
    /// Точного нет — сервер ослабил условия (relaxed): показываем близкое с пометкой.
    var ослаблено = false

    var пусто: Bool { товары.isEmpty && вместо == nil && чипы.isEmpty }
}

@MainActor
final class ЖивыеПодсказкиПоиска: ObservableObject {
    @Published private(set) var итог = ЖивыеТоварыПоиска()
    /// Для какого запроса итог (чтобы не показывать товары прежнего под новым запросом).
    @Published private(set) var запрос = ""
    @Published private(set) var грузим = false

    private var задача: Task<Void, Never>?
    private var память: [String: ЖивыеТоварыПоиска] = [:]
    private var порядокПамяти: [String] = []

    static let сколько = 5
    private static let пауза: UInt64 = 220_000_000

    /// Новый текст поля. Короче двух букв или всё выключено — пусто.
    func искать(_ текст: String) {
        let q: String = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        задача?.cancel()
        guard q.count >= 2, Config.живыеТоварыПоиска || Config.умныйПоиск else {
            if !итог.пусто || !запрос.isEmpty {
                итог = ЖивыеТоварыПоиска()
                запрос = ""
            }
            грузим = false
            return
        }
        if let есть = память[q.lowercased()] {
            итог = есть
            запрос = q
            грузим = false
            return
        }
        грузим = true
        задача = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.пауза)
            guard !Task.isCancelled else { return }
            let пришло: ЖивыеТоварыПоиска? = await Self.загрузить(q)
            guard !Task.isCancelled, let self else { return }
            self.грузим = false
            guard let пришло else { return }
            self.запомнить(q.lowercased(), пришло)
            self.итог = пришло
            self.запрос = q
        }
    }

    private func запомнить(_ ключ: String, _ значение: ЖивыеТоварыПоиска) {
        if память[ключ] == nil { порядокПамяти.append(ключ) }
        память[ключ] = значение
        if порядокПамяти.count > 40 {
            let старый = порядокПамяти.removeFirst()
            память[старый] = nil
        }
    }

    /// Сначала новая дверь (ai_search), не ответила — лента (search_live).
    private static func загрузить(_ q: String) async -> ЖивыеТоварыПоиска? {
        if Config.умныйПоиск, let умные = await ДверьПодсказокПоиска.загрузить(q) { return умные }
        guard Config.живыеТоварыПоиска else { return nil }
        var з = ListingsAPI.Запрос()
        з.q = q
        з.per = сколько
        guard let ответ = try? await ListingsAPI.загрузить(з) else { return nil }
        var итог = ЖивыеТоварыПоиска()
        итог.товары = Array(ответ.страница.items.prefix(сколько))
        итог.всего = ответ.страница.total
        return итог
    }
}

/// api/search_suggest.php (docs/SERVER_AI_SEARCH.md §1–3). nil — двери нет, не JSON или ok не пришёл.
enum ДверьПодсказокПоиска {
    static func загрузить(_ q: String) async -> ЖивыеТоварыПоиска? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/search_suggest.php"),
                              resolvingAgainstBaseURL: false)
        var поля: [URLQueryItem] = [URLQueryItem(name: "q", value: q),
                                     URLQueryItem(name: "lang", value: DesignText.язык),
                                     URLQueryItem(name: "limit", value: String(ЖивыеПодсказкиПоиска.сколько))]
        поля.append(contentsOf: ГдеИскать.сохранённое().параметры)
        ч?.queryItems = поля
        guard let адрес = ч?.url else { return nil }
        var запрос = URLRequest(url: адрес, timeoutInterval: 6)
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let пришло = try? await URLSession.shared.data(for: запрос) else { return nil }
        if let http = пришло.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        guard let корень = (try? JSONSerialization.jsonObject(with: пришло.0)) as? [String: Any] else { return nil }
        let ок: Bool = (корень["ok"] as? Bool) ?? ((корень["ok"] as? NSNumber)?.boolValue ?? false)
        guard ок else { return nil }
        return разобрать(корень)
    }

    static func разобрать(_ корень: [String: Any]) -> ЖивыеТоварыПоиска {
        var итог = ЖивыеТоварыПоиска()
        let записи: [[String: Any]] = (корень["items"] as? [[String: Any]]) ?? []
        if !записи.isEmpty, let данные = try? JSONSerialization.data(withJSONObject: ["items": записи]),
           let страница = try? ListingsAPI.разобрать(данные) {
            итог.товары = Array(страница.items.prefix(ЖивыеПодсказкиПоиска.сколько))
        }
        for запись in записи {
            guard let номер = строка(запись["id"]), let почему = строка(запись["why"]) else { continue }
            итог.почему[номер] = почему
        }
        итог.всего = (корень["total"] as? NSNumber)?.intValue
        итог.вместо = строка(корень["did_you_mean"])
        let чипы: [[String: Any]] = (корень["chips"] as? [[String: Any]]) ?? []
        итог.чипы = чипы.compactMap { чип in
            guard let подпись = строка(чип["label"]) else { return nil }
            return ЧипИИПоиска(подпись: подпись, параметр: строка(чип["param"]) ?? "", значение: строка(чип["value"]) ?? "")
        }
        if let ослаблено = корень["relaxed"] as? [Any], !ослаблено.isEmpty { итог.ослаблено = true }
        return итог
    }

    private static func строка(_ значение: Any?) -> String? {
        if let s = значение as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let n = значение as? NSNumber { return n.stringValue }
        return nil
    }
}

/// api/search_event.php (порядок 4): что нажали в подсказках и что искали — только с ai_search, без входа и имени.
enum СобытияПоиска {
    enum Вид: String {
        case товар = "suggest_item", запрос = "suggest_query", чип = "chip", вместо = "did_you_mean", найти = "submit"
    }

    private static let ключНомера = "kliko.search.sid"

    /// Случайный номер установки — не аккаунт и не устройство: стирается вместе с приложением.
    private static var номер: String {
        if let есть = UserDefaults.standard.string(forKey: ключНомера) { return есть }
        let новый = UUID().uuidString
        UserDefaults.standard.set(новый, forKey: ключНомера)
        return новый
    }

    static func отметить(_ вид: Вид, запрос: String, объявление: String? = nil, место: Int? = nil) {
        guard Config.умныйПоиск else { return }
        var тело: [String: Any] = ["sid": номер, "q": запрос, "kind": вид.rawValue]
        if let объявление { тело["id"] = объявление }
        if let место { тело["pos"] = место }
        guard let данные = try? JSONSerialization.data(withJSONObject: тело) else { return }
        var з = URLRequest(url: Config.apiBase.appendingPathComponent("api/search_event.php"), timeoutInterval: 8)
        з.httpMethod = "POST"
        з.httpShouldHandleCookies = false
        з.setValue("application/json", forHTTPHeaderField: "Content-Type")
        з.httpBody = данные
        let готовый: URLRequest = з
        Task.detached(priority: .utility) { _ = try? await URLSession.shared.data(for: готовый) }
    }
}

// MARK: - Вид

/// Секция под строкой запроса: «Вы имели в виду», «Kliko AI понял», объявления и «Показать все».
struct СекцияЖивыхТоваров: View {
    let итог: ЖивыеТоварыПоиска
    let грузим: Bool
    let запрос: String
    let открыть: (Listing, Int) -> Void
    let найти: () -> Void
    let вместо: (String) -> Void

    private func т(_ ключ: String) -> String { ЖивойПоискText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let исправление = итог.вместо {
                Button { вместо(исправление) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.акцент)
                            .accessibilityHidden(true)
                        Text(т("ls_dym"))
                            .foregroundStyle(Theme.текстВторой)
                        Text(исправление)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.акцент)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !итог.чипы.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(т("ls_ai"))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Theme.текстВторой)
                    ПереносСтрок(промежуток: 6, междуСтрок: 6) {
                        ForEach(итог.чипы) { чип in
                            Text(чип.подпись)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.акцент)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 28)
                                .background(Theme.поверхность2, in: Capsule())
                                .overlay { Capsule().strokeBorder(Theme.линия, lineWidth: 1) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }
            if !итог.товары.isEmpty {
                заголовок
                if итог.ослаблено {
                    Text(т("ls_relaxed"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
                ForEach(Array(итог.товары.enumerated()), id: \.element.id) { место, товар in
                    СтрокаЖивогоТовара(товар: товар, почему: итог.почему[товар.id]) { открыть(товар, место) }
                }
                Button(action: найти) {
                    HStack(spacing: 6) {
                        Text(показатьВсе)
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.зелёный2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if грузим {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(т("ls_loading"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
            }
        }
    }

    private var заголовок: some View {
        HStack {
            Text(т("ls_items").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }

    private var показатьВсе: String {
        if let всего = итог.всего, всего > итог.товары.count {
            return String(format: т("ls_all_n"), всего)
        }
        return т("ls_all")
    }
}

/// Строка товара: фото 52 pt, название в две строки, цена и город; причина Kliko AI — зелёным под ценой.
private struct СтрокаЖивогоТовара: View {
    let товар: Listing
    let почему: String?
    let открыть: () -> Void

    var body: some View {
        Button(action: открыть) {
            HStack(alignment: .top, spacing: 12) {
                КартинкаЛенты(товар.фотоАдреса.first, пунктов: 52) {
                    Theme.поверхность2
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(товар.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(ListingCard.цена(товар))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        if !товар.city.isEmpty {
                            Text("· " + товар.city)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.текстВторой)
                                .lineLimit(1)
                        }
                    }
                    if let почему {
                        Text(почему)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.акцент)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum ЖивойПоискText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "ls_items": "Объявления", "ls_all": "Показать все", "ls_all_n": "Показать все %d",
        "ls_loading": "Ищем объявления…", "ls_dym": "Вы имели в виду:", "ls_ai": "KLIKO AI ПОНЯЛ",
        "ls_relaxed": "Точно таких нет — вот близкое", "ls_ai_line": "Kliko AI понял:"
    ]

    private static let kk: [String: String] = [
        "ls_items": "Хабарландырулар", "ls_all": "Барлығын көрсету", "ls_all_n": "Барлығын көрсету: %d",
        "ls_loading": "Хабарландырулар ізделуде…", "ls_dym": "Мүмкін, сіз мұны іздедіңіз:", "ls_ai": "KLIKO AI ТҮСІНДІ",
        "ls_relaxed": "Дәл осындай жоқ — міне, ұқсастары", "ls_ai_line": "Kliko AI түсінді:"
    ]

    private static let en: [String: String] = [
        "ls_items": "Listings", "ls_all": "Show all", "ls_all_n": "Show all %d",
        "ls_loading": "Looking for listings…", "ls_dym": "Did you mean:", "ls_ai": "KLIKO AI UNDERSTOOD",
        "ls_relaxed": "No exact matches — here is something close", "ls_ai_line": "Kliko AI understood:"
    ]

    private static let ar: [String: String] = [
        "ls_items": "الإعلانات", "ls_all": "عرض الكل", "ls_all_n": "عرض الكل (%d)",
        "ls_loading": "نبحث عن إعلانات…", "ls_dym": "هل تقصد:", "ls_ai": "فهم KLIKO AI",
        "ls_relaxed": "لا تطابق تام — إليك الأقرب", "ls_ai_line": "فهم Kliko AI:"
    ]
}
