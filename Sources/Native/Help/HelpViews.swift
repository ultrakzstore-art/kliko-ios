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

 Последняя удачная страница лежит в Caches — без сети показывается она с пометкой. Страница, из которой статью вынуть не
 удалось (собрана скриптом), — честно «открывается только на сайте» и кнопка сайта.
 */

/// Статическая страница сайта: слаг и якорь.
struct СтраницаСайта: Hashable, Identifiable {
    let слаг: String
    var якорь: String?

    var id: String { слаг + "#" + (якорь ?? "") }

    /// Страницы подвала сайта (home.html: /kz/ru/help, oplata, tarify, soglashenie, oferta, privacy).
    static let известные: Set<String> = ["help", "soglashenie", "oferta", "privacy", "oplata", "tarify"]

    var заголовок: String { СправкаText.т("p_" + слаг) }

    /// /kz/<язык телефона>/<слаг> — страница на языке приложения, даже если ссылка была на /kz/ru/.
    var адрес: URL? { Config.страницаСайта(слаг) }

    var адресСЯкорем: URL? {
        guard let якорь, !якорь.isEmpty else { return адрес }
        return Config.страницаСайта(слаг + "#" + якорь)
    }

    /// https://kliko.kz/kz/ru/help#safe, /soglashenie.php, /kz/kz/privacy → страница; прочее — nil.
    static func из(_ адрес: URL) -> СтраницаСайта? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        let лишние = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        guard лишние.isEmpty else { return nil }
        let путь = части.path.lowercased()
        guard путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/[a-z]+(\\.php)?/?$", options: .regularExpression) != nil else {
            return nil
        }
        var слаг = путь.split(separator: "/").last.map(String.init) ?? ""
        if слаг.hasSuffix(".php") { слаг = String(слаг.dropLast(4)) }
        guard известные.contains(слаг) else { return nil }
        let якорь = (части.fragment ?? "").trimmingCharacters(in: .whitespaces)
        return СтраницаСайта(слаг: слаг, якорь: якорь.isEmpty ? nil : якорь)
    }
}

// MARK: - Загрузка

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

    /// Разобранные за этот запуск — второй раз не качаем.
    private static var память: [String: СтатьяСайта] = [:]

    init(страница: СтраницаСайта) {
        self.страница = страница
    }

    func загрузить(заново: Bool = false) async {
        guard let адрес = страница.адрес else {
            состояние = .ошибка
            return
        }
        let ключ = адрес.absoluteString
        if !заново, let готовая = Self.память[ключ] {
            состояние = .готово(готовая, изКопии: false)
            return
        }
        if case .готово = состояние {} else { состояние = .идёт }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20)
        запрос.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (данные, ответ) = try await URLSession.shared.data(for: запрос)
            let код = (ответ as? HTTPURLResponse)?.statusCode ?? 0
            guard код == 200, !данные.isEmpty else { throw URLError(.badServerResponse) }
            let html = String(decoding: данные, as: UTF8.self)
            let статья = await Self.разобрать(html, адрес: адрес)
            guard статья.годится else {
                состояние = .пусто
                return
            }
            Self.память[ключ] = статья
            Self.сохранить(данные, ключ: ключ)
            состояние = .готово(статья, изКопии: false)
        } catch {
            if let копия = Self.копия(ключ: ключ) {
                let html = String(decoding: копия, as: UTF8.self)
                let статья = await Self.разобрать(html, адрес: адрес)
                if статья.годится {
                    состояние = .готово(статья, изКопии: true)
                    return
                }
            }
            состояние = .ошибка
        }
    }

    private static func разобрать(_ html: String, адрес: URL) async -> СтатьяСайта {
        await Task.detached(priority: .userInitiated) { () -> СтатьяСайта in
            РазборСтатьи.разобрать(html, адрес: адрес)
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
    /// Куда прокрутить (якорь из адреса или из ссылки на этой же странице).
    @State private var прокрутить: Int? = nil
    @State private var раскрытые: Set<Int> = []

    init(страница: СтраницаСайта, перейти: @escaping (СтраницаСайта) -> Void, открыть: @escaping (URL) -> Void,
         написать: @escaping () -> Void) {
        self.страница = страница
        self.перейти = перейти
        self.открыть = открыть
        self.написать = написать
        _загрузка = StateObject(wrappedValue: ЗагрузкаСтатьи(страница: страница))
    }

    private func т(_ ключ: String) -> String { СправкаText.т(ключ) }

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(страница.заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .task { await загрузка.загрузить() }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch загрузка.состояние {
        case .идёт:
            VStack(spacing: 12) {
                ProgressView()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ошибка:
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("fail_t"), подпись: т("fail_s"), кнопка: т("retry"),
                       действие: { Task { await загрузка.загрузить(заново: true) } },
                       вторая: т("on_site"), второеДействие: { наСайт() })
        case .пусто:
            ПустоСайта(значок: "doc.text", заголовок: т("empty_t"), кнопка: т("on_site"), действие: { наСайт() })
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
                    if страница.слаг == "tarify" && !Config.цифровыеПокупки {
                        ЗаметкаБизнеса(т("no_digital"), тон: .серый, значок: "lock")
                    }
                    if статья.разделы.count >= 3 {
                        оглавление(статья)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(статья.блоки) { блок in
                            БлокСтатьиВид(блок: блок, раскрытые: $раскрытые)
                                .id(блок.id)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.поверхность,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                    if страница.слаг == "help" {
                        поддержка
                    }
                }
                .padding(12)
            }
            .refreshable { await загрузка.загрузить(заново: true) }
            .environment(\.openURL, OpenURLAction { адрес in обработать(адрес, статья: статья) })
            .onAppear {
                if let якорь = страница.якорь, let цель = статья.блок(якоря: якорь) {
                    раскрыть(цель, статья: статья)
                    прокрутить = цель
                }
            }
            .onChange(of: прокрутить) { _, цель in
                guard let цель else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation(.easeInOut(duration: 0.3)) { прокрутка.scrollTo(цель, anchor: .top) }
                    прокрутить = nil
                }
            }
        }
    }

    /// Оглавление: разделы второго уровня кнопками-чипами.
    private func оглавление(_ статья: СтатьяСайта) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("toc"))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(статья.разделы) { раздел in
                        Button {
                            прокрутить = раздел.id
                        } label: {
                            Text(раздел.простой)
                                .font(.system(size: 13, weight: .semibold))
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
            }
        }
    }

    private var поддержка: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("support_s"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            КнопкаБизнеса(подпись: т("support"), второстепенная: true) { написать() }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    // MARK: Ссылки

    private func обработать(_ адрес: URL, статья: СтатьяСайта) -> OpenURLAction.Result {
        let схема = адрес.scheme?.lowercased() ?? ""
        if схема == "mailto" || схема == "tel" || схема == "sms" { return .systemAction }
        if let другая = СтраницаСайта.из(адрес) {
            if другая.слаг == страница.слаг {
                if let якорь = другая.якорь, let цель = статья.блок(якоря: якорь) {
                    раскрыть(цель, статья: статья)
                    прокрутить = цель
                }
                return .handled
            }
            перейти(другая)
            return .handled
        }
        if Config.deepLink(адрес.absoluteURL) != nil {
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

    private func наСайт() {
        if let адрес = страница.адресСЯкорем { открыть(адрес) }
    }
}

// MARK: - Блок статьи

struct БлокСтатьиВид: View {
    let блок: БлокСтатьи
    @Binding var раскрытые: Set<Int>

    var body: some View {
        switch блок.вид {
        case .заголовок(let уровень):
            Text(блок.текст)
                .font(шрифтЗаголовка(уровень))
                .foregroundStyle(Theme.текст)
                .padding(.top, уровень <= 2 ? 8 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case .абзац:
            Text(блок.текст)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        case .пункт(let маркер, let уровень):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(маркер)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(minWidth: 14, alignment: .trailing)
                    .accessibilityHidden(маркер == "•" || маркер == "◦")
                Text(блок.текст)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(max(0, уровень - 1)) * 18)
        case .цитата:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.акцент)
                    .frame(width: 3)
                    .accessibilityHidden(true)
                Text(блок.текст)
                    .font(.system(size: 15))
                    .italic()
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .разделитель:
            Divider()
                .overlay(Theme.линия)
                .padding(.vertical, 4)
        case .вопрос(let ответ):
            ВопросСтатьи(блок: блок, ответ: ответ, раскрытые: $раскрытые)
        }
    }

    private func шрифтЗаголовка(_ уровень: Int) -> Font {
        switch уровень {
        case 1: return .system(size: 24, weight: .heavy)
        case 2: return .system(size: 19, weight: .heavy)
        case 3: return .system(size: 16, weight: .bold)
        default: return .system(size: 15, weight: .bold)
        }
    }
}

/// <details>/<summary>: вопрос строкой, ответ раскрывается.
struct ВопросСтатьи: View {
    let блок: БлокСтатьи
    let ответ: [БлокСтатьи]
    @Binding var раскрытые: Set<Int>

    private var открыт: Bool { раскрытые.contains(блок.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if открыт { раскрытые.remove(блок.id) } else { раскрытые.insert(блок.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(блок.текст)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .rotationEffect(.degrees(открыт ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(СправкаText.т("a11y_faq"))
            .accessibilityAddTraits(открыт ? [.isSelected] : [])
            if открыт {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ответ) { часть in
                        БлокСтатьиВид(блок: часть, раскрытые: $раскрытые)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }
}
