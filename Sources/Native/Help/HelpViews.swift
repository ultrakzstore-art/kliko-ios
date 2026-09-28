import SwiftUI
import UIKit

/**
 СПРАВОЧНЫЙ ЦЕНТР И СТАТИЧЕСКИЕ СТРАНИЦЫ САЙТА — СВОИМ ЭКРАНОМ (этап 50).

 Было: «Справочный центр» во вкладке «Кабинет», ссылки подвала (помощь, как работает гарант, PRO, правила, тарифы,
 соглашение, оферта, политика, оплата) открывали страницу сайта — всё приложение уходило на WKWebView под слоем.
 Стало: та же страница сайта качается (URLSession, без куки — страницы публичные), из неё вынимается статья
 (РазборСтатьи) и показывается своими блоками в оформлении приложения, светлом и тёмном: заголовки, абзацы, списки,
 вопросы-ответы раскрывашками, ссылки. Ссылка на другую такую страницу открывается здесь же, следующим экраном; якорь
 (#safe) — прокруткой; почта и телефон — системой; прочие адреса сайта — как обычно (окно закрывается, адрес идёт
 своим путём: нативный экран или сайт).

 Последняя удачная страница лежит в Caches по адресу с языком и открывается сразу, а свежая качается следом
 (ЗагрузкаСтатьи); без сети — копия с пометкой. Страница, из которой статью вынуть не удалось (собрана скриптом), —
 честно «открывается только на сайте» и кнопка сайта. Своих текстов справки у приложения нет: «Частые вопросы» и «Как
 работает Гарант» окна «Категории» — это help#faq и help#safe этой же страницы.

 Экран: первый h1 — заголовком над статьёй (если не повторяет шапку), разделы h2 — отдельными карточками (HelpBlocks),
 оглавление чипами, у справки — поиск по вопросам и тексту (ответ найденного вопроса раскрыт) и строка поддержки.
 Статьи справки (/help/<раздел>, help?topic=…) — тем же экраном. «Тарифы» — без цен, кнопок и ссылок покупки и без
 «Открыть на сайте» (правило App Store 3.1.1): только описание и «Эта возможность недоступна в приложении.».
 */

/// Статическая страница сайта: слаг, запрос (только у справки) и якорь.
struct СтраницаСайта: Hashable, Identifiable {
    /// help, soglashenie, … или статья справки «help/<раздел>».
    let слаг: String
    var якорь: String?
    /// Параметры адреса статьи справки (help?topic=…) без меток utm_; у прочих страниц — nil.
    var запрос: String? = nil

    var id: String { слаг + "?" + (запрос ?? "") + "#" + (якорь ?? "") }

    /// Страницы подвала сайта (home.html: /kz/ru/help, oplata, tarify, soglashenie, oferta, privacy).
    static let известные: Set<String> = ["help", "soglashenie", "oferta", "privacy", "oplata", "tarify"]

    /// Корень страницы: у статьи справки «help/<раздел>» — help.
    var корень: String { слаг.split(separator: "/").first.map(String.init) ?? слаг }

    /// Справка и её статьи — с поиском и строкой поддержки.
    var справка: Bool { корень == "help" }

    /// «Тарифы» — только описание, без цен и покупок (правило App Store 3.1.1).
    var тарифы: Bool { корень == "tarify" }

    /// Название, как в подвале сайта. У статьи справки своего нет — «Справочный центр» до загрузки.
    var заголовок: String { СправкаText.т("p_" + корень) }

    /// Своё ли это название (страница подвала) или у статьи лучше взять её h1.
    var названаПодвалом: Bool { слаг == корень && запрос == nil }

    private var хвост: String {
        guard let запрос, !запрос.isEmpty else { return слаг }
        return слаг + "?" + запрос
    }

    /// /kz/<язык телефона>/<слаг> — страница на языке приложения, даже если ссылка была на /kz/ru/.
    var адрес: URL? { Config.страницаСайта(хвост) }

    var адресСЯкорем: URL? {
        guard let якорь, !якорь.isEmpty else { return адрес }
        return Config.страницаСайта(хвост + "#" + якорь)
    }

    /**
     https://kliko.kz/kz/ru/help#safe, /soglashenie.php, /kz/kz/privacy, /kz/ru/help/safe, /help.php?topic=pay →
     страница; прочее — nil. Лишние параметры у страниц подвала (?print=1, ?utm_…) не мешают — страница та же; у
     справки они — выбор статьи и идут с адресом.
     */
    static func из(_ адрес: URL) -> СтраницаСайта? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        var сегменты = части.path.lowercased().split(separator: "/").map(String.init)
        /* /kz/ru/… — регион и язык впереди. */
        if сегменты.count >= 2, сегменты[0].count == 2, сегменты[1].count == 2,
           сегменты[0].allSatisfy({ $0.isASCII && $0.isLetter }), сегменты[1].allSatisfy({ $0.isASCII && $0.isLetter }) {
            сегменты.removeFirst(2)
        }
        guard var первый = сегменты.first else { return nil }
        if первый.hasSuffix(".php") { первый = String(первый.dropLast(4)) }
        guard известные.contains(первый) else { return nil }
        var слаг = первый
        if сегменты.count > 1 {
            /* Вложенные адреса — только статьи справки: /help/<раздел>[/<статья>]. */
            let вложенные = Array(сегменты.dropFirst())
            let годные = вложенные.allSatisfy { часть in
                !часть.isEmpty && часть.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
            }
            guard первый == "help", вложенные.count <= 2, годные else { return nil }
            слаг = первый + "/" + вложенные.joined(separator: "/")
        }
        var запрос: String? = nil
        if первый == "help" {
            let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
            if !параметры.isEmpty {
                var чистые = URLComponents()
                чистые.queryItems = параметры
                запрос = чистые.percentEncodedQuery
            }
        }
        let якорь = (части.fragment ?? "").trimmingCharacters(in: .whitespaces)
        return СтраницаСайта(слаг: слаг, якорь: якорь.isEmpty ? nil : якорь, запрос: запрос)
    }

    /// Та же страница (без учёта якоря).
    func таЖе(_ другая: СтраницаСайта) -> Bool {
        слаг == другая.слаг && (запрос ?? "") == (другая.запрос ?? "")
    }
}

extension СтатьяСайта {
    /**
     Куда прокрутить по якорю адреса. Сначала — элемент с таким id/name. Якорь «частых вопросов» (faq), которого на
     странице нет, — к первому вопросу-ответу (<details>) страницы, а если над ним заголовок — к заголовку: у сайта
     раздел вопросов может называться как угодно, а ссылка приложения остаётся одной.
     */
    func цель(якоря якорь: String) -> Int? {
        if let точная = блок(якоря: якорь) { return точная }
        let вопросы: Set<String> = ["faq", "faqs", "voprosy", "questions"]
        guard вопросы.contains(якорь.lowercased()) else { return nil }
        guard let номер = блоки.firstIndex(where: { блок in
            if case .вопрос = блок.вид { return true }
            return false
        }) else { return nil }
        if номер > 0, case .заголовок = блоки[номер - 1].вид {
            return блоки[номер - 1].id
        }
        return блоки[номер].id
    }
}

// MARK: - Загрузка

/**
 Загрузка статьи: «сначала своё, потом свежее» (stale-while-revalidate), отдельно для каждого языка — ключ копии и
 памяти — полный адрес /kz/<язык>/<слаг>.
   · Есть разобранная за этот запуск или копия на диске — показывается сразу, без крутилки.
   · Следом, в фоне, страница качается заново; изменилась — статья на экране тихо заменяется, копия на диске
     обновляется. Не чаще раза в «свежести» за запуск (потянуть вниз — всегда заново).
   · Сети нет: показана копия — пометка «сохранённая копия»; копии нет — встроенная заглушка с «Повторить»
     (текстов справки в приложении нет — их правит команда сайта).
 */
@MainActor
final class ЗагрузкаСтатьи: ObservableObject {
    enum Состояние {
        case идёт
        case готово(СтатьяСайта, изКопии: Bool)
        case пусто
        case ошибка
    }

    @Published private(set) var состояние: Состояние = .идёт

    let страница: СтраницаСайта

    /// Разобранная статья и сырая страница, из которой она вышла.
    private struct Запомненная {
        let статья: СтатьяСайта
        let данные: Data
    }

    /// Разобранные за этот запуск (по адресу с языком).
    private static var память: [String: Запомненная] = [:]
    /// Когда адрес последний раз удачно сверен с сайтом за этот запуск.
    private static var сверено: [String: Date] = [:]
    /// Сколько секунд страница считается свежей и не качается заново (кроме «потянуть вниз»).
    private static let свежесть: TimeInterval = 300

    init(страница: СтраницаСайта) {
        self.страница = страница
    }

    /// Заранее положить страницу в память и на диск (окно «Категории», кабинет): открытие справки — мгновенное.
    static func прогреть(_ страница: СтраницаСайта) async {
        let загрузка = ЗагрузкаСтатьи(страница: страница)
        await загрузка.загрузить()
    }

    func загрузить(заново: Bool = false) async {
        guard let адрес = страница.адрес else {
            состояние = .ошибка
            return
        }
        let ключ = адрес.absoluteString

        /* 1. Сразу — своё: память этого запуска или копия на диске. */
        var показана: Data? = nil
        if case .готово = состояние {
            показана = Self.память[ключ]?.данные
        }
        if показана == nil, let запомненная = Self.память[ключ] {
            состояние = .готово(запомненная.статья, изКопии: false)
            показана = запомненная.данные
        }
        if показана == nil, let копия = Self.копия(ключ: ключ) {
            let статья = await Self.разобрать(String(decoding: копия, as: UTF8.self), адрес: адрес, тарифы: страница.тарифы)
            if статья.годится {
                Self.память[ключ] = Запомненная(статья: статья, данные: копия)
                состояние = .готово(статья, изКопии: false)
                показана = копия
            }
        }

        /* 2. Свежее с сайта — если давно не сверяли или просят заново. */
        if !заново, показана != nil, let когда = Self.сверено[ключ], Date().timeIntervalSince(когда) < Self.свежесть {
            return
        }
        if показана == nil { состояние = .идёт }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        запрос.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (данные, ответ) = try await URLSession.shared.data(for: запрос)
            let код = (ответ as? HTTPURLResponse)?.statusCode ?? 0
            guard код == 200, !данные.isEmpty else { throw URLError(.badServerResponse) }
            Self.сверено[ключ] = Date()
            if let показана, показана == данные {
                /* Не изменилась — статья на экране та же; снять пометку «копия», если была. */
                if case .готово(let статья, let изКопии) = состояние, изКопии {
                    состояние = .готово(статья, изКопии: false)
                }
                return
            }
            let статья = await Self.разобрать(String(decoding: данные, as: UTF8.self), адрес: адрес, тарифы: страница.тарифы)
            guard статья.годится else {
                /* Страница собрана скриптом: без копии — «только на сайте»; с копией — оставить копию. */
                if показана == nil { состояние = .пусто }
                return
            }
            Self.память[ключ] = Запомненная(статья: статья, данные: данные)
            Self.сохранить(данные, ключ: ключ)
            состояние = .готово(статья, изКопии: false)
        } catch {
            if case .готово(let статья, _) = состояние {
                состояние = .готово(статья, изКопии: true)
            } else {
                состояние = .ошибка
            }
        }
    }

    /// Разбор — не на главном потоке. «Тарифы» — сразу без цен и покупок: ни в памяти, ни на экране их нет.
    private static func разобрать(_ html: String, адрес: URL, тарифы: Bool) async -> СтатьяСайта {
        await Task.detached(priority: .userInitiated) { () -> СтатьяСайта in
            let статья = РазборСтатьи.разобрать(html, адрес: адрес)
            return тарифы ? РазборСтатьи.безПокупок(статья) : статья
        }.value
    }

    // MARK: Копия на диске

    private static func файл(_ ключ: String) -> URL? {
        guard let папка = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        var имя = ""
        for знак in ключ.unicodeScalars {
            let годен = знак.isASCII && (знак.properties.isAlphabetic || знак.properties.numericType != nil)
            имя.unicodeScalars.append(годен ? знак : "_")
        }
        return папка.appendingPathComponent("kliko-pages", isDirectory: true).appendingPathComponent(имя + ".html")
    }

    private static func сохранить(_ данные: Data, ключ: String) {
        guard let файл = файл(ключ) else { return }
        try? FileManager.default.createDirectory(at: файл.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? данные.write(to: файл, options: .atomic)
    }

    private static func копия(ключ: String) -> Data? {
        guard let файл = файл(ключ) else { return nil }
        return try? Data(contentsOf: файл)
    }
}

// MARK: - Окно со стопкой страниц

/// Корень окна: первая страница и следующие по ссылкам — своим стеком.
struct ОкноСтраницСайта: View {
    let первая: СтраницаСайта
    /// Адрес не из этих страниц — окно закрывается, адрес идёт своим путём.
    let открыть: (URL) -> Void
    /// «Написать в поддержку» — своя форма обращения (ЛистОбращения) после закрытия окна.
    let написать: () -> Void
    let закрыть: () -> Void

    @State private var путь: [СтраницаСайта] = []

    init(первая: СтраницаСайта, открыть: @escaping (URL) -> Void, написать: @escaping () -> Void,
         закрыть: @escaping () -> Void) {
        self.первая = первая
        self.открыть = открыть
        self.написать = написать
        self.закрыть = закрыть
    }

    var body: some View {
        NavigationStack(path: $путь) {
            экран(первая)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(СправкаText.т("close")) { закрыть() }
                    }
                }
                .navigationDestination(for: СтраницаСайта.self) { страница in
                    экран(страница)
                }
        }
        .tint(Theme.акцент)
        /* Окно поднимает UIKit: направление письма (арабский — справа налево) ставим сами, как корень слоя. */
        .оформлениеСайта(языка: ЯзыкПриложения.shared.код)
    }

    private func экран(_ страница: СтраницаСайта) -> some View {
        ЭкранСтраницыСайта(страница: страница, перейти: { следующая in путь.append(следующая) },
                           открыть: открыть, написать: написать)
    }
}

// MARK: - Экран статьи

struct ЭкранСтраницыСайта: View {
    let страница: СтраницаСайта
    let перейти: (СтраницаСайта) -> Void
    let открыть: (URL) -> Void
    let написать: () -> Void

    @StateObject private var загрузка: ЗагрузкаСтатьи
    /// Куда прокрутить (якорь из адреса, оглавление или ссылка на этой же странице).
    @State private var прокрутить: Int? = nil
    @State private var раскрытые: Set<Int> = []
    /// Якорь адреса и <details open> уже учтены (при обновлении статьи не прыгаем заново).
    @State private var начатоС: Bool = false
    @State private var поиск = ""
    /// Размеры, растущие с Dynamic Type вместе с текстом статьи (HelpBlocks): h1 не мельче абзацев.
    @ScaledMetric(relativeTo: .title) private var размерH1: CGFloat = 24
    @ScaledMetric(relativeTo: .footnote) private var размерЧипа: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var размерТекста: CGFloat = 15

    init(страница: СтраницаСайта, перейти: @escaping (СтраницаСайта) -> Void, открыть: @escaping (URL) -> Void,
         написать: @escaping () -> Void) {
        self.страница = страница
        self.перейти = перейти
        self.открыть = открыть
        self.написать = написать
        _загрузка = StateObject(wrappedValue: ЗагрузкаСтатьи(страница: страница))
    }

    private func т(_ ключ: String) -> String { СправкаText.т(ключ) }

    private var запросПоиска: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if страница.справка {
            оформленное
                .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text(т("search")))
        } else {
            оформленное
        }
    }

    private var оформленное: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(заголовокЭкрана)
            .navigationBarTitleDisplayMode(.inline)
            .task { await загрузка.загрузить() }
    }

    /// Название в шапке: страница подвала — как в подвале; статья справки — её h1, когда загрузилась.
    private var заголовокЭкрана: String {
        guard !страница.названаПодвалом, case .готово(let статья, _) = загрузка.состояние else {
            return страница.заголовок
        }
        let своё = статья.заголовок.trimmingCharacters(in: .whitespacesAndNewlines)
        return своё.isEmpty || своё.count > 60 ? страница.заголовок : своё
    }

    @ViewBuilder
    private var содержимое: some View {
        switch загрузка.состояние {
        case .идёт:
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ошибка:
            /* Кнопки «на сайт» нет: адрес этой страницы снова открыл бы это же окно. */
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("fail_t"), подпись: т("fail_s"),
                       кнопка: т("retry"), действие: { Task { await загрузка.загрузить(заново: true) } })
        case .пусто:
            if страница.тарифы {
                ПустоСайта(значок: "lock", заголовок: страница.заголовок, подпись: т("no_digital"))
            } else {
                ПустоСайта(значок: "doc.text", заголовок: т("empty_t"), кнопка: т("retry"),
                           действие: { Task { await загрузка.загрузить(заново: true) } })
            }
        case .готово(let статья, let изКопии):
            статьяВид(статья, изКопии: изКопии)
        }
    }

    private func статьяВид(_ статья: СтатьяСайта, изКопии: Bool) -> some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if изКопии {
                        ЗаметкаБизнеса(т("cached"), тон: .предупреждение, значок: "wifi.slash")
                    }
                    if страница.тарифы {
                        ЗаметкаБизнеса(т("no_digital"), тон: .серый, значок: "lock")
                    }
                    if запросПоиска.isEmpty {
                        статьяЦеликом(статья)
                    } else {
                        найденноеВид(статья)
                    }
                    if страница.справка {
                        поддержка
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
                /* На iPad строка не тянется во всю ширину — читать как на сайте. */
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await загрузка.загрузить(заново: true) }
            .environment(\.openURL, OpenURLAction { адрес in обработать(адрес, статья: статья) })
            .onAppear { начать(статья) }
            .onChange(of: прокрутить) { _, цель in
                guard let цель else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(цель, anchor: .top) }
                    прокрутить = nil
                }
            }
            .onChange(of: поиск) { _, _ in
                раскрытьНайденное(статья)
            }
        }
    }

    @ViewBuilder
    private func статьяЦеликом(_ статья: СтатьяСайта) -> some View {
        if let первый = статья.первыйЗаголовок, показатьЗаголовок(первый.простой) {
            Text(первый.текст)
                .font(.system(size: размерH1, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
                .id(первый.id)
        }
        if статья.разделы.count >= 3 && !статья.естьКарточки {
            оглавление(статья)
        }
        ForEach(статья.части) { часть in
            if часть.плитки {
                РядПлитокСтатьи(блоки: часть.блоки)
            } else {
                КарточкаСтатьи(блоки: часть.блоки, раскрытые: $раскрытые)
            }
        }
    }

    /// h1 над карточками — если он не повторяет название в шапке.
    private func показатьЗаголовок(_ текст: String) -> Bool {
        let свой = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !свой.isEmpty else { return false }
        return свой.compare(заголовокЭкрана, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    }

    /// Оглавление: разделы кнопками-чипами. Лента прокручивается от края до края экрана, чипы — с полями 16, как у
    /// ленты сайта: первый стоит вровень с карточками, последний не упирается в край.
    private func оглавление(_ статья: СтатьяСайта) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("toc"))
                .font(.system(size: размерЧипа, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(статья.разделы) { раздел in
                        Button {
                            прокрутить = раздел.id
                        } label: {
                            Text(раздел.простой)
                                .font(.system(size: размерЧипа, weight: .semibold))
                                .lineLimit(1)
                                .foregroundStyle(Theme.текстПункта)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Theme.фонПункта, in: Capsule())
                                .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
            /* Поля экрана — 16: лента выходит за них, чтобы чипы уезжали под край, а не обрезались посреди. */
            .padding(.horizontal, -16)
        }
    }

    // MARK: Поиск по справке

    /// Блоки, где встречается запрос (вопрос — вместе с ответом), по порядку статьи.
    private func найденное(_ статья: СтатьяСайта) -> [БлокСтатьи] {
        let запрос = запросПоиска
        guard !запрос.isEmpty else { return [] }
        var итог: [БлокСтатьи] = []
        for блок in статья.блоки {
            switch блок.вид {
            case .заголовок, .разделитель, .картинка:
                continue
            default:
                break
            }
            if блок.весьТекст.localizedStandardContains(запрос) {
                итог.append(блок)
            }
        }
        return итог
    }

    @ViewBuilder
    private func найденноеВид(_ статья: СтатьяСайта) -> some View {
        let найдено = найденное(статья)
        if найдено.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(т("nothing_t"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(т("nothing_s"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else {
            КарточкаСтатьи(блоки: найдено, раскрытые: $раскрытые)
        }
    }

    /// Найденные вопросы — раскрыты: ответ виден сразу.
    private func раскрытьНайденное(_ статья: СтатьяСайта) {
        for блок in найденное(статья) {
            if case .вопрос = блок.вид { раскрытые.insert(блок.id) }
        }
    }

    // MARK: Поддержка

    private var поддержка: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 36, height: 36)
                    .background(Theme.мята, in: Circle())
                    .accessibilityHidden(true)
                Text(т("support_s"))
                    .font(.system(size: размерТекста))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            КнопкаБизнеса(подпись: т("support"), второстепенная: true) { написать() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    // MARK: Якорь и ссылки

    /// Первый показ статьи: раскрыть <details open> и прокрутить к якорю адреса.
    private func начать(_ статья: СтатьяСайта) {
        guard !начатоС else { return }
        начатоС = true
        for блок in статья.блоки {
            if case .вопрос(_, let открыт) = блок.вид, открыт { раскрытые.insert(блок.id) }
        }
        if let якорь = страница.якорь, let цель = статья.цель(якоря: якорь) {
            раскрыть(цель, статья: статья)
            прокрутить = цель
        }
    }

    private func обработать(_ адрес: URL, статья: СтатьяСайта) -> OpenURLAction.Result {
        let схема = адрес.scheme?.lowercased() ?? ""
        if схема == "mailto" || схема == "tel" || схема == "sms" { return .systemAction }
        /* Оплата услуг сайта из приложения не открывается (правило App Store 3.1.1). */
        if РазборСтатьи.оплата(адрес) { return .handled }
        if let другая = СтраницаСайта.из(адрес) {
            if другая.таЖе(страница) {
                if let якорь = другая.якорь, let цель = статья.цель(якоря: якорь) {
                    поиск = ""
                    раскрыть(цель, статья: статья)
                    прокрутить = цель
                }
                return .handled
            }
            перейти(другая)
            return .handled
        }
        if Config.deepLink(адрес.absoluteURL) != nil {
            /* Прочие адреса сайта — окно закрывается, адрес идёт общим путём (свой экран или сайт). */
            if страница.тарифы { return .handled }
            открыть(адрес.absoluteURL)
            return .handled
        }
        return .systemAction
    }

    /// Якорь внутри вопроса — вопрос раскрыть.
    private func раскрыть(_ цель: Int, статья: СтатьяСайта) {
        for блок in статья.блоки where блок.id == цель {
            if case .вопрос = блок.вид { раскрытые.insert(цель) }
        }
    }
}
