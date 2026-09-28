import SwiftUI
import UIKit

/**
 РАБОТА: ВАКАНСИИ И РЕЗЮМЕ — СВОИ ЭКРАНЫ ВМЕСТО /?cat=jobs САЙТА (владелец 26.09.2026: «всё приложение нативное»).

 Раньше плитка «Работа», «Все ›» ряда вакансий и карточка вакансии на главной открывали раздел сайта /?cat=jobs
 (#vac=<номер>) — приложение целиком уходило на WKWebView. Теперь — свой список и своя карточка, как у сайта:
   · список — /api/listings.php?cat=jobs&jkind=vacancy|resume (_mkApiQS: jkind, jemp — занятость; город и регион —
     тем же выбором места, что лента; sort=new), строки как mxJobRow: «★ ТОП», название, зарплата («от …», «… – …»
     или «Зарплата не указана»), компания, описание в две строки, «город · занятость · дата»;
   · вверху — «Вакансии» / «Резюме» (mkJobsKind) и чипы занятости (mkJobsEmp: нажатая ещё раз — снять);
   · карточка — _mkJobSheet: GET /api/jobs.php?action=get&id= → {ok, job}; нет — «Объявление больше недоступно»;
     название, зарплата, компания (у резюме — имя), «город · занятость», описание (у резюме — about) и
     «Откликнуться» (у резюме — «Написать»);
   · отклик — mkJobRespond: POST /api/jobs.php?action=respond {csrf: _MKP_CSRF, job_id} → ok — «Отклик отправлен — ответ
     придёт в сообщения»; error «auth» — вход (свой экран поверх), «self» — «Это ваше объявление», иначе «Не удалось
     отправить отклик»; обрыв — «Нет связи».
 Подача вакансии и резюме (мастер модуля jobs кабинета) — свой мастер МастерРезюме (НативныеОкна, cabinet?add=jobs).
 */
struct ВакансияСайта: Identifiable, Hashable {
    let id: String
    let название: String
    let зарплатаОт: Int
    let зарплатаДо: Int
    let занятость: String
    let компания: String
    let описание: String
    let город: String
    let топ: Bool
    let резюме: Bool
    let создано: String

    init?(_ j: [String: Any]) {
        func с(_ ключ: String) -> String {
            if let s = j[ключ] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = j[ключ] as? NSNumber { return n.stringValue }
            return ""
        }
        func ц(_ ключ: String) -> Int {
            if let n = j[ключ] as? NSNumber { return max(0, n.intValue) }
            if let s = j[ключ] as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite,
               abs(d) < 1e12 { return max(0, Int(d)) }
            return 0
        }
        func да(_ ключ: String) -> Bool {
            if let b = j[ключ] as? Bool { return b }
            if let n = j[ключ] as? NSNumber { return n.intValue != 0 }
            if let s = j[ключ] as? String { return s == "1" || s == "true" }
            return false
        }
        let номер = с("id")
        guard !номер.isEmpty else { return nil }
        id = номер
        резюме = с("kind") == "resume"
        название = с("title")
        зарплатаОт = ц("salary_min")
        зарплатаДо = ц("salary_max")
        занятость = с("employment")
        /* _mkJobSheet: у вакансии — company и description, у резюме — name и about. */
        компания = резюме ? с("name") : с("company")
        let полное = резюме ? с("about") : с("description")
        описание = полное.isEmpty ? с("about") : полное
        город = с("city")
        топ = да("_top") || да("top") || да("is_top")
        создано = с("created_at")
    }

    /// «150 000 – 250 000 ₸», «от 200 000 ₸», «до 300 000 ₸»; не указана — nil.
    var зарплата: String? {
        if зарплатаОт > 0 && зарплатаДо > зарплатаОт {
            let от = DesignText.число(зарплатаОт)
            let до = DesignText.число(зарплатаДо)
            return от + " – " + до + "\u{00A0}₸"
        }
        if зарплатаОт > 0 { return String(format: DesignText.т("sal_from"), DesignText.число(зарплатаОт) + "\u{00A0}₸") }
        if зарплатаДо > 0 { return String(format: DesignText.т("sal_to"), DesignText.число(зарплатаДо) + "\u{00A0}₸") }
        return nil
    }

    var занятостьТекст: String {
        ["full", "part", "shift", "remote", "internship"].contains(занятость) ? DesignText.т("emp_" + занятость) : ""
    }

    /// «Астана · Полная занятость».
    var подпись: String {
        [город, занятостьТекст].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum ВакансииAPI {
    enum Отклик {
        case отправлен
        case нуженВход
        case свой
        case отказ
        case сеть
    }

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 20
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession)
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    /// Страница списка: nil — нет связи или ответ не тот.
    static func список(резюме: Bool, занятость: String, запрос: String, страница: Int) async
        -> (вакансии: [ВакансияСайта], ещё: Bool)? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)
        var поля = [URLQueryItem(name: "sort", value: "new"),
                    URLQueryItem(name: "page", value: String(страница)),
                    URLQueryItem(name: "per", value: "30"),
                    URLQueryItem(name: "cat", value: "jobs"),
                    URLQueryItem(name: "jkind", value: резюме ? "resume" : "vacancy")]
        if !занятость.isEmpty { поля.append(URLQueryItem(name: "jemp", value: занятость)) }
        let q = запрос.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { поля.append(URLQueryItem(name: "q", value: q)) }
        поля.append(contentsOf: ГдеИскать.сохранённое().параметры)
        ч?.queryItems = поля
        guard let адрес = ч?.url, let j = await получить(адрес) else { return nil }
        let записи = (j["items"] as? [Any]) ?? []
        let вакансии = записи.compactMap { ($0 as? [String: Any]).flatMap(ВакансияСайта.init) }
        let ещё: Bool
        if let b = j["has_more"] as? Bool {
            ещё = b
        } else if let n = j["has_more"] as? NSNumber {
            ещё = n.intValue != 0
        } else {
            ещё = записи.count >= 30
        }
        return (вакансии, ещё)
    }

    /// mkJobOpen: GET /api/jobs.php?action=get&id= → {ok, job}. nil — нет такой или нет связи.
    static func одна(_ id: String) async -> ВакансияСайта? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/jobs.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: "get"), URLQueryItem(name: "id", value: id)]
        guard let адрес = ч?.url, let j = await получить(адрес) else { return nil }
        guard (j["ok"] as? Bool) == true || (j["ok"] as? NSNumber)?.intValue == 1,
              let запись = j["job"] as? [String: Any] else { return nil }
        return ВакансияСайта(запись)
    }

    /// mkJobRespond: POST /api/jobs.php?action=respond {csrf, job_id}.
    static func откликнуться(_ id: String) async -> Отклик {
        let страница = await SiteSession.состояние()
        if страница.вошёл == false { return .нуженВход }
        guard let csrf = await SiteSession.csrf() ?? страница.csrf else { return .сеть }
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/jobs.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: "respond")]
        guard let адрес = ч?.url,
              let тело = try? JSONSerialization.data(withJSONObject: ["csrf": csrf, "job_id": id]) else { return .отказ }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.setValue(Config.apiBase.absoluteString, forHTTPHeaderField: "Origin")
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        запрос.httpBody = тело
        guard let пришло = try? await сессия.data(for: запрос) else { return .сеть }
        guard let j = (try? JSONSerialization.jsonObject(with: пришло.0)) as? [String: Any] else {
            let код = (пришло.1 as? HTTPURLResponse)?.statusCode ?? 200
            return (код == 401 || код == 403) ? .нуженВход : .отказ
        }
        if (j["ok"] as? Bool) == true || (j["ok"] as? NSNumber)?.intValue == 1 { return .отправлен }
        let ошибка = (j["error"] as? String) ?? ""
        if ошибка == "auth" || (j["need"] as? String) == "auth" { return .нуженВход }
        if ошибка == "self" { return .свой }
        return .отказ
    }

    private static func получить(_ адрес: URL) async -> [String: Any]? {
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (поле, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: поле) }
        guard let пришло = try? await сессия.data(for: запрос) else { return nil }
        if let http = пришло.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return (try? JSONSerialization.jsonObject(with: пришло.0)) as? [String: Any]
    }
}

// MARK: - Окно

@MainActor
enum ОкноВакансий {
    /// Список вакансий (номер nil) или сразу карточка вакансии — поверх текущего экрана. Запасной путь — раздел сайта.
    static func открыть(_ номер: String?) {
        let запасной = запасной(номер)
        if let номер, !номер.isEmpty {
            ПоверхВсего.показать(большой: false, неВышло: {
                if let запасной { WebBridge.shared.pendingURL = запасной }
            }) { закрыть in
                ЛистВакансии(номер: номер, заготовка: nil, закрыть: закрыть)
            }
        } else {
            ПоверхВсего.показать(неВышло: {
                if let запасной { WebBridge.shared.pendingURL = запасной }
            }) { закрыть in
                ЭкранВакансий(закрыть: закрыть)
            }
        }
    }

    private static func запасной(_ номер: String?) -> URL? {
        var хвост = "?cat=jobs"
        if let номер, !номер.isEmpty {
            хвост += "#vac=" + (номер.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? номер)
        }
        return Config.страницаСайта(хвост)
    }
}

// MARK: - Список

struct ЭкранВакансий: View {
    let закрыть: () -> Void

    @State private var резюме = false
    @State private var занятость = ""
    @State private var запрос = ""
    @State private var вакансии: [ВакансияСайта] = []
    @State private var страница = 1
    @State private var ещё = false
    @State private var грузим = false
    @State private var ошибка = false
    @State private var выбранная: ВакансияСайта? = nil
    @State private var поколение = 0

    private static let виды = ["full", "part", "shift", "remote", "internship"]

    private func т(_ ключ: String) -> String { ВакансииText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $резюме) {
                        Text(т("vac")).tag(false)
                        Text(т("res")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    чипы
                    содержимое
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .searchable(text: $запрос, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(т("search")))
            .onSubmit(of: .search) { заново() }
            .refreshable { await загрузить(заново: true) }
            .navigationTitle(т("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
        .sheet(item: $выбранная) { вакансия in
            ЛистВакансии(номер: вакансия.id, заготовка: вакансия, закрыть: { выбранная = nil })
        }
        .task { if вакансии.isEmpty { await загрузить(заново: true) } }
        .onChange(of: резюме) { _, _ in заново() }
        .onChange(of: занятость) { _, _ in заново() }
        .onChange(of: запрос) { _, новое in
            if новое.isEmpty { заново() }
        }
    }

    /// Чипы занятости (mkJobsEmp): нажатая ещё раз — снять.
    private var чипы: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.виды, id: \.self) { вид in
                    let вкл = занятость == вид
                    Button {
                        занятость = вкл ? "" : вид
                    } label: {
                        Text(DesignText.т("emp_" + вид))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(вкл ? Color.white : Theme.текст)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(вкл ? Theme.зелёный2 : Theme.поверхность, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(вкл ? Color.clear : Theme.линия, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(вкл ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if вакансии.isEmpty && грузим {
            HStack(spacing: 10) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else if вакансии.isEmpty && ошибка {
            VStack(spacing: 10) {
                Text(т("fail"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Button(т("retry")) { заново() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.зелёный)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        } else if вакансии.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "briefcase")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(т("empty"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.текст)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            ForEach(вакансии) { вакансия in
                Button {
                    выбранная = вакансия
                } label: {
                    СтрокаВакансии(вакансия: вакансия)
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                .onAppear {
                    if вакансия.id == вакансии.last?.id && ещё && !грузим {
                        Task { @MainActor in await загрузить(заново: false) }
                    }
                }
            }
            if грузим {
                SiteSpinner()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
        }
    }

    private func заново() {
        Task { @MainActor in await загрузить(заново: true) }
    }

    private func загрузить(заново: Bool) async {
        if заново {
            поколение += 1
            страница = 1
            ещё = false
        } else {
            guard ещё, !грузим else { return }
        }
        let моё = поколение
        let номер = заново ? 1 : страница + 1
        грузим = true
        ошибка = false
        let пришло = await ВакансииAPI.список(резюме: резюме, занятость: занятость, запрос: запрос, страница: номер)
        guard моё == поколение else { return }
        грузим = false
        guard let пришло else {
            ошибка = true
            return
        }
        if заново {
            вакансии = пришло.вакансии
        } else {
            let были = Set(вакансии.map(\.id))
            вакансии.append(contentsOf: пришло.вакансии.filter { !были.contains($0.id) })
        }
        страница = номер
        ещё = пришло.ещё && !пришло.вакансии.isEmpty
    }
}

/// mxJobRow: «★ ТОП», название, зарплата, компания, описание, «город · занятость · дата».
private struct СтрокаВакансии: View {
    let вакансия: ВакансияСайта

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        let зарплата = вакансия.зарплата
        return VStack(alignment: .leading, spacing: 5) {
            if вакансия.топ { МеткаТопГлавной() }
            Text(вакансия.название)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(зарплата ?? DesignText.т("sal_none"))
                .font(.system(size: зарплата == nil ? 14 : 16, weight: зарплата == nil ? .semibold : .heavy))
                .foregroundStyle(зарплата == nil ? Theme.текстВторой : Theme.текст)
            if !вакансия.компания.isEmpty {
                Text(вакансия.компания)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
            }
            if !вакансия.описание.isEmpty {
                Text(вакансия.описание.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Text(подвал)
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(вакансия.топ ? Theme.топФон : Theme.поверхность, in: форма)
        .overlay {
            форма.strokeBorder(вакансия.топ ? Theme.топРамка : Theme.линия, lineWidth: 1)
        }
        .теньКарточкиСайта()
        .contentShape(форма)
        .accessibilityElement(children: .combine)
    }

    private var подвал: String {
        var части = [вакансия.город, вакансия.занятостьТекст]
        if !вакансия.создано.isEmpty { части.append(Listing.датаСайта(вакансия.создано)) }
        return части.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Карточка вакансии (_mkJobSheet)

struct ЛистВакансии: View {
    let номер: String
    let закрыть: () -> Void

    @State private var вакансия: ВакансияСайта?
    @State private var нет = false
    @State private var шлём = false
    @State private var сообщение: String? = nil

    init(номер: String, заготовка: ВакансияСайта?, закрыть: @escaping () -> Void) {
        self.номер = номер
        self.закрыть = закрыть
        _вакансия = State(initialValue: заготовка)
    }

    private func т(_ ключ: String) -> String { ВакансииText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let вакансия {
                        карточка(вакансия)
                    } else if нет {
                        Text(т("gone"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else {
                        SiteSpinner()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(16)
            }
            .background(Theme.поверхность.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let вакансия { низ(вакансия) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: номер) { await загрузить() }
    }

    private func карточка(_ в: ВакансияСайта) -> some View {
        let зарплата = в.зарплата
        return VStack(alignment: .leading, spacing: 8) {
            if в.топ { МеткаТопГлавной() }
            Text(в.название)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(зарплата ?? DesignText.т("sal_none"))
                .font(.system(size: зарплата == nil ? 15 : 19, weight: зарплата == nil ? .semibold : .heavy))
                .foregroundStyle(зарплата == nil ? Theme.текстВторой : Theme.зелёный2)
            if !в.компания.isEmpty {
                Label(в.компания, systemImage: в.резюме ? "person" : "building.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            if !в.подпись.isEmpty {
                Label(в.подпись, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !в.описание.isEmpty {
                Divider().padding(.vertical, 4)
                Text(в.описание)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let сообщение {
                Text(сообщение)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// .jb-ft: «Откликнуться» (у резюме — «Написать») на всю ширину.
    private func низ(_ в: ВакансияСайта) -> some View {
        Button {
            откликнуться(в)
        } label: {
            HStack(spacing: 8) {
                if шлём { SiteSpinner.белый }
                Text(т(в.резюме ? "write" : "apply"))
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(шлём)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.поверхность)
    }

    private func загрузить() async {
        if let свежая = await ВакансииAPI.одна(номер) {
            вакансия = свежая
        } else if вакансия == nil {
            нет = true
        }
    }

    private func откликнуться(_ в: ВакансияСайта) {
        guard !шлём else { return }
        шлём = true
        сообщение = nil
        Task { @MainActor in
            let итог = await ВакансииAPI.откликнуться(в.id)
            шлём = false
            switch итог {
            case .отправлен:
                сообщение = т("sent")
                UIAccessibility.post(notification: .announcement, argument: т("sent"))
            case .нуженВход:
                сообщение = т("need_login")
                ВходПоверх.показать()
            case .свой:
                сообщение = т("self")
            case .отказ:
                сообщение = т("fail_resp")
            case .сеть:
                сообщение = т("no_net")
            }
        }
    }
}

/// Тексты раздела «Работа». Русские — сайта (jobs_vac, jobs_res, jobs_apply, jobs_write, jobs_sent, jobs_self,
/// jobs_fail, jobs_gone, need_login, no_net); «Работа», «Поиск по вакансиям», «Загружаем…» и «Пока пусто» — свои.
enum ВакансииText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "title": "Работа", "vac": "Вакансии", "res": "Резюме", "search": "Должность или компания",
            "loading": "Загружаем…", "fail": "Не удалось загрузить", "retry": "Повторить", "empty": "Пока ничего нет",
            "close": "Закрыть", "apply": "Откликнуться", "write": "Написать",
            "sent": "Отклик отправлен — ответ придёт в сообщения", "self": "Это ваше объявление",
            "fail_resp": "Не удалось отправить отклик", "gone": "Объявление больше недоступно",
            "need_login": "Войдите, чтобы откликнуться", "no_net": "Нет связи"
        ],
        "kk": [
            "title": "Жұмыс", "vac": "Бос орындар", "res": "Түйіндеме", "search": "Лауазым немесе компания",
            "loading": "Жүктелуде…", "fail": "Жүктеу мүмкін болмады", "retry": "Қайталау", "empty": "Әзірге ештеңе жоқ",
            "close": "Жабу", "apply": "Өтініш беру", "write": "Жазу",
            "sent": "Өтініш жіберілді — жауап хабарламаларға келеді", "self": "Бұл сіздің хабарландыруыңыз",
            "fail_resp": "Өтінішті жіберу мүмкін болмады", "gone": "Хабарландыру енді қолжетімсіз",
            "need_login": "Өтініш беру үшін кіріңіз", "no_net": "Байланыс жоқ"
        ],
        "en": [
            "title": "Jobs", "vac": "Vacancies", "res": "Résumés", "search": "Position or company",
            "loading": "Loading…", "fail": "Couldn't load", "retry": "Retry", "empty": "Nothing here yet",
            "close": "Close", "apply": "Apply", "write": "Message",
            "sent": "Application sent — the reply will arrive in your messages", "self": "This is your own listing",
            "fail_resp": "Couldn't send the application", "gone": "This listing is no longer available",
            "need_login": "Sign in to apply", "no_net": "No connection"
        ],
        "ar": [
            "title": "وظائف", "vac": "الوظائف الشاغرة", "res": "السير الذاتية", "search": "المسمى الوظيفي أو الشركة",
            "loading": "جارٍ التحميل…", "fail": "تعذّر التحميل", "retry": "إعادة المحاولة", "empty": "لا شيء بعد",
            "close": "إغلاق", "apply": "تقدّم", "write": "مراسلة",
            "sent": "تم إرسال طلبك — سيصل الرد إلى رسائلك", "self": "هذا إعلانك",
            "fail_resp": "تعذّر إرسال الطلب", "gone": "الإعلان لم يعد متاحًا",
            "need_login": "سجّل الدخول للتقدّم", "no_net": "لا يوجد اتصال"
        ]
    ]
}
