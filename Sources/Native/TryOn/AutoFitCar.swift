import Foundation

/**
 «ПОДОЙДУТ ЛИ?» — МАШИНА ЧЕЛОВЕКА И СПРАВОЧНИК ПОСАДКИ (владелец 13.10.2026: «нужнее охват всего»).

 «Моя машина» — марка, модель и год из того же справочника, что у мастера авто подачи (/api/auto_models.php: марки
 группами ?brands=1, модели ?brand=; без сети — марки и модели из сборки, Seed/seed-auto.json, СтартовыеДанные).
 Запоминается на телефоне (UserDefaults, без входа) — следующее объявление шин или дисков сразу сверяется с ней.

 Параметры посадки машины (разболтовка, DIA, вылет, штатные диаметры и размеры шин):
   · есть справочник на сервере — GET /api/autofit.php?action=car&make=&model=&year= (docs/SERVER_AUTOFIT.md): ответ
     {ok, pcd, dia, et_min, et_max, rim_sizes[], tire_sizes[]} берём как есть и кладём в кэш на телефоне (30 дней);
   · нет справочника, нет этой машины или нет сети — человек вводит свои: штатный размер шин, PCD, DIA, ET (подсказка:
     наклейка в проёме двери водителя, инструкция, маркировка на старом диске). Тоже запоминаются.
 Запрос — простой GET без кук и без входа (справочник общий, ничего личного не уходит: только марка, модель, год).
 Сервер не умеет (404, 405, 410, 501, перенаправление, не JSON, unsupported) — до перезапуска не спрашиваем.
 */
extension Config {
    /// Спрашивать ли справочник посадки /api/autofit.php (docs/SERVER_AUTOFIT.md). false — параметры машины человек
    /// всегда вводит сам; сверка и калькулятор работают так же.
    static let справочникАвтоподбора = true
}

// MARK: - Машина и посадка

/// Машина человека: марка и модель — как в справочнике сайта, год — по желанию.
struct МашинаАвтоподбора: Codable, Equatable, Hashable, Sendable {
    var марка: String
    var модель: String
    var год: Int?

    init(марка: String, модель: String, год: Int?) {
        self.марка = марка
        self.модель = модель
        self.год = год
    }

    /// «Toyota Camry, 2018».
    var подпись: String {
        let имя = [марка, модель].filter { !$0.isEmpty }.joined(separator: " ")
        guard let год else { return имя }
        return имя + ", " + String(год)
    }

    /// Ключ кэша справочника.
    var ключ: String {
        марка.lowercased() + "|" + модель.lowercased() + "|" + (год.map { String($0) } ?? "")
    }
}

/// Параметры посадки колёс машины. Неизвестное — nil или пусто.
struct ПосадкаАвтоподбора: Codable, Equatable, Sendable {
    var разболтовка: РазболтовкаАвтоподбора? = nil
    var dia: Double? = nil
    var etMin: Double? = nil
    var etMax: Double? = nil
    /// Штатные диаметры дисков (rim_sizes).
    var диаметры: [Double] = []
    /// Штатные размеры шин (tire_sizes) — первый главный.
    var шины: [РазмерШиныАвтоподбора] = []
    /// Пределы ширины обода, J (rim_width_min / rim_width_max) — если справочник знает.
    var ширинаMin: Double? = nil
    var ширинаMax: Double? = nil
    /// Крепёж («M12x1.5») — только показать.
    var крепёж: String? = nil
    /// Ввёл человек, а не справочник.
    var свои = false

    init() {}

    var пустая: Bool {
        разболтовка == nil && dia == nil && etMin == nil && etMax == nil && диаметры.isEmpty && шины.isEmpty
    }

    /// Штатные диаметры по возрастанию: из справочника, а нет его — посадки штатных шин.
    var штатныеДиаметры: [Double] {
        let свои = диаметры.isEmpty ? шины.map(\.диаметр) : диаметры
        return Array(Set(свои)).sorted()
    }

    /// Разбор ответа справочника: поля прямо в ответе или в объекте car. Пусто — nil.
    static func изОтвета(_ j: [String: Any]) -> ПосадкаАвтоподбора? {
        let к = (j["car"] as? [String: Any]) ?? j
        var п = ПосадкаАвтоподбора()
        func число(_ значение: Any?) -> Double? {
            if let n = значение as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
            if let s = значение as? String { return ПарсерАвтоподбора.числоСоЗнаком(ПарсерАвтоподбора.нормально(s)) }
            return nil
        }
        if let строка = к["pcd"] as? String {
            п.разболтовка = РазболтовкаАвтоподбора.изВвода(строка)
        } else if let pcd = число(к["pcd"]), let болтов = число(к["bolts"] ?? к["holes"]),
                  (3...10).contains(болтов), /* до Int(): огромное число из ответа уронило бы приложение */
                  РазболтовкаАвтоподбора.годная(отверстий: Int(болтов), pcd: pcd) {
            п.разболтовка = РазболтовкаАвтоподбора(отверстий: Int(болтов), pcd: pcd)
        }
        if let dia = число(к["dia"]), (50...175).contains(dia) { п.dia = dia }
        let et = число(к["et"])
        if let низ = число(к["et_min"]) ?? et, (-65...80).contains(низ) { п.etMin = низ }
        if let верх = число(к["et_max"]) ?? et, (-65...80).contains(верх) { п.etMax = верх }
        п.диаметры = ((к["rim_sizes"] as? [Any]) ?? []).compactMap { число($0) }
            .filter { РазмерШиныАвтоподбора.диаметры.contains($0) }
        var шины: [РазмерШиныАвтоподбора] = []
        for запись in (к["tire_sizes"] as? [Any]) ?? [] {
            guard let строка = запись as? String, let размер = РазмерШиныАвтоподбора.изВвода(строка),
                  !шины.contains(размер) else { continue }
            шины.append(размер)
        }
        п.шины = шины
        if let низ = число(к["rim_width_min"]), (3.5...13).contains(низ) { п.ширинаMin = низ }
        if let верх = число(к["rim_width_max"]), (3.5...13).contains(верх) { п.ширинаMax = верх }
        let крепёж = ((к["bolt"] ?? к["thread"]) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !крепёж.isEmpty && крепёж.count <= 24 { п.крепёж = крепёж }
        return п.пустая ? nil : п
    }
}

// MARK: - Гараж: что запомнено на телефоне

/**
 Машина человека и её посадка — одно на приложение, на телефоне. Синглтон создаётся пустым и в init ни к кому не
 обращается; с диска читает подготовить() (зовёт окно при появлении).
 */
@MainActor
final class ГаражАвтоподбора: ObservableObject {
    static let shared = ГаражАвтоподбора()

    /// Почему справочник не дал параметры выбранной машины.
    enum МолчаниеАвтоподбора: Equatable {
        /// В справочнике нет этой машины или справочника нет вовсе.
        case нет
        /// Нет связи — можно попробовать позже.
        case сеть
    }

    @Published private(set) var машина: МашинаАвтоподбора? = nil
    @Published private(set) var посадка: ПосадкаАвтоподбора? = nil
    @Published private(set) var ищем = false
    @Published private(set) var молчание: МолчаниеАвтоподбора? = nil

    private var загружен = false
    private static let ключ = "kliko.autofit.garage"

    private init() {}

    private struct ЗаписьГаражаАвтоподбора: Codable {
        var машина: МашинаАвтоподбора?
        var посадка: ПосадкаАвтоподбора?
    }

    /// Прочитать запомненное (один раз).
    func подготовить() {
        guard !загружен else { return }
        загружен = true
        guard let данные = UserDefaults.standard.data(forKey: Self.ключ),
              let запись = try? JSONDecoder().decode(ЗаписьГаражаАвтоподбора.self, from: данные) else { return }
        машина = запись.машина
        посадка = запись.посадка.flatMap { $0.пустая ? nil : $0 }
    }

    private func сохранить() {
        let запись = ЗаписьГаражаАвтоподбора(машина: машина, посадка: посадка)
        if запись.машина == nil && запись.посадка == nil {
            UserDefaults.standard.removeObject(forKey: Self.ключ)
        } else if let данные = try? JSONEncoder().encode(запись) {
            UserDefaults.standard.set(данные, forKey: Self.ключ)
        }
    }

    /**
     Выбрана машина: запомнить и спросить справочник. true — параметры пришли (из кэша или с сервера); false — их надо
     ввести (молчание скажет почему). Прежние параметры другой машины забываются: к новой они не относятся.
     */
    func выбрать(_ новая: МашинаАвтоподбора) async -> Bool {
        подготовить()
        if машина != новая {
            машина = новая
            посадка = nil
        }
        молчание = nil
        сохранить()
        guard Config.справочникАвтоподбора else {
            молчание = .нет
            return false
        }
        ищем = true
        let итог = await СправочникАвтоподбора.посадка(новая)
        ищем = false
        guard машина == новая else { return false }
        switch итог {
        case .есть(let найденная):
            посадка = найденная
            сохранить()
            return true
        case .нет:
            молчание = .нет
        case .сеть:
            молчание = .сеть
        }
        return посадка != nil
    }

    /// Человек ввёл свои параметры (машина может быть и не выбрана).
    func сохранитьСвои(_ своя: ПосадкаАвтоподбора) {
        подготовить()
        var п = своя
        п.свои = true
        посадка = п.пустая ? nil : п
        молчание = nil
        сохранить()
    }

    /// Забыть машину и параметры.
    func забыть() {
        подготовить()
        машина = nil
        посадка = nil
        молчание = nil
        сохранить()
    }
}

// MARK: - Справочник

/**
 Справочник: посадка машины (/api/autofit.php, docs/SERVER_AUTOFIT.md), марки и модели (/api/auto_models.php — тот же,
 что у мастера авто подачи). Простые GET без кук: справочник общий, вход не нужен. Ответы посадки — в кэш на телефоне
 на 30 дней; «нет такой машины» — помним до перезапуска, «нет справочника» — тоже.
 */
@MainActor
enum СправочникАвтоподбора {
    enum ИтогСправочникаАвтоподбора {
        case есть(ПосадкаАвтоподбора)
        case нет
        case сеть
    }

    private enum ОтветСправочникаАвтоподбора {
        case json([String: Any])
        case нетСервера
        case сеть
    }

    /// Сервер ответил «не умею» — до перезапуска не спрашиваем.
    private static var нетСервера = false
    /// Машины, которых нет в справочнике, — до перезапуска.
    private static var нетМашин: Set<String> = []
    private static var марки: [ГруппаМарок] = []
    private static var модели: [String: [МодельАвто]] = [:]

    private static let ключКэша = "kliko.autofit.cars"
    private static let срокКэша: TimeInterval = 30 * 24 * 3600

    /// Без кук и без кэша на диске: справочник общий, своё хранение — ниже.
    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: c)
    }()

    // MARK: Посадка

    static func посадка(_ машина: МашинаАвтоподбора) async -> ИтогСправочникаАвтоподбора {
        if let своя = изКэша(машина) { return .есть(своя) }
        if нетСервера || нетМашин.contains(машина.ключ) { return .нет }
        var поля = [URLQueryItem(name: "action", value: "car"), URLQueryItem(name: "make", value: машина.марка),
                    URLQueryItem(name: "model", value: машина.модель),
                    URLQueryItem(name: "lang", value: ПримерочнаяText.язык)]
        if let год = машина.год { поля.append(URLQueryItem(name: "year", value: String(год))) }
        switch await получить("/api/autofit.php", поля) {
        case .json(let j):
            let ошибка = МоиОбъявленияAPI.строка(j["error"])
            if ошибка == "unsupported" || МоиОбъявленияAPI.строка(j["code"]) == "unsupported" {
                нетСервера = true
                return .нет
            }
            guard МоиОбъявленияAPI.да(j["ok"]), let найденная = ПосадкаАвтоподбора.изОтвета(j) else {
                нетМашин.insert(машина.ключ)
                return .нет
            }
            вКэш(машина, найденная)
            return .есть(найденная)
        case .нетСервера:
            нетСервера = true
            return .нет
        case .сеть:
            return .сеть
        }
    }

    private struct ЗаписьКэшаАвтоподбора: Codable {
        let когда: Double
        let посадка: ПосадкаАвтоподбора
    }

    private static func кэш() -> [String: ЗаписьКэшаАвтоподбора] {
        guard let данные = UserDefaults.standard.data(forKey: ключКэша),
              let записи = try? JSONDecoder().decode([String: ЗаписьКэшаАвтоподбора].self, from: данные) else { return [:] }
        return записи
    }

    private static func изКэша(_ машина: МашинаАвтоподбора) -> ПосадкаАвтоподбора? {
        guard let запись = кэш()[машина.ключ] else { return nil }
        guard Date().timeIntervalSince1970 - запись.когда < срокКэша else { return nil }
        return запись.посадка
    }

    /// Не больше 30 машин: старые уходят первыми.
    private static func вКэш(_ машина: МашинаАвтоподбора, _ посадка: ПосадкаАвтоподбора) {
        var записи = кэш()
        записи[машина.ключ] = ЗаписьКэшаАвтоподбора(когда: Date().timeIntervalSince1970, посадка: посадка)
        if записи.count > 30 {
            let лишние = записи.sorted { $0.value.когда < $1.value.когда }.prefix(записи.count - 30).map(\.key)
            for ключ in лишние { записи[ключ] = nil }
        }
        if let данные = try? JSONEncoder().encode(записи) {
            UserDefaults.standard.set(данные, forKey: ключКэша)
        }
    }

    // MARK: Марки и модели

    /// Марки из сборки — сразу, без сети.
    static func стартовыеМарки() -> [ГруппаМарок] {
        if !марки.isEmpty { return марки }
        return группы(СтартовыеДанные.объект("seed-auto") ?? [:])
    }

    /// Свежие марки сайта; не ответил — из сборки.
    static func свежиеМарки() async -> [ГруппаМарок] {
        if !марки.isEmpty { return марки }
        if case .json(let j) = await получить("/api/auto_models.php", [URLQueryItem(name: "brands", value: "1")]),
           МоиОбъявленияAPI.да(j["ok"]) {
            let свежие = группы(j)
            if !свежие.isEmpty {
                марки = свежие
                return свежие
            }
        }
        return стартовыеМарки()
    }

    /// {groups:[{region, brands:[{brand}]}]} → группы по порядку сайта.
    private static func группы(_ j: [String: Any]) -> [ГруппаМарок] {
        var итог: [ГруппаМарок] = []
        var были = Set<String>()
        for запись in (j["groups"] as? [Any]) ?? [] {
            guard let г = запись as? [String: Any] else { continue }
            var свои: [String] = []
            for марка in (г["brands"] as? [Any]) ?? [] {
                let имя = МоиОбъявленияAPI.строка((марка as? [String: Any])?["brand"])
                    .trimmingCharacters(in: .whitespaces)
                if !имя.isEmpty && !были.contains(имя) {
                    были.insert(имя)
                    свои.append(имя)
                }
            }
            guard !свои.isEmpty else { continue }
            let регион = МоиОбъявленияAPI.строка(г["region"]).trimmingCharacters(in: .whitespaces)
            let подпись = регион.isEmpty ? АвтоподборText.т("af_brands_other") : регион
            if let был = итог.firstIndex(where: { $0.регион == подпись }) {
                итог[был] = ГруппаМарок(регион: подпись, марки: итог[был].марки + свои)
            } else {
                итог.append(ГруппаМарок(регион: подпись, марки: свои))
            }
        }
        return итог
    }

    /// Модели марки: с сайта (с поколениями), без сети — из сборки (без поколений, в кэш не кладём).
    static func моделиМарки(_ марка: String) async -> [МодельАвто] {
        let чистая = марка.trimmingCharacters(in: .whitespaces)
        guard !чистая.isEmpty else { return [] }
        if let были = модели[чистая] { return были }
        if case .json(let j) = await получить("/api/auto_models.php", [URLQueryItem(name: "brand", value: чистая)]),
           МоиОбъявленияAPI.да(j["ok"]) {
            let список = ((j["models"] as? [Any]) ?? []).compactMap { запись -> МодельАвто? in
                guard let м = запись as? [String: Any] else { return nil }
                let имя = МоиОбъявленияAPI.строка(м["name"]).trimmingCharacters(in: .whitespaces)
                guard !имя.isEmpty else { return nil }
                let поколения = ((м["gens"] as? [Any]) ?? []).compactMap { п -> ПоколениеАвто? in
                    guard let г = п as? [String: Any] else { return nil }
                    let название = МоиОбъявленияAPI.строка(г["name"])
                    guard !название.isEmpty else { return nil }
                    return ПоколениеАвто(имя: название, с: МоиОбъявленияAPI.целое(г["from"]),
                                         по: МоиОбъявленияAPI.целое(г["to"]))
                }
                let кузов = ((м["body"] as? [Any]) ?? []).map { МоиОбъявленияAPI.строка($0) }.filter { !$0.isEmpty }
                return МодельАвто(имя: имя, поколения: поколения, кузов: кузов)
            }
            if !список.isEmpty {
                модели[чистая] = список
                return список
            }
        }
        return СтартовыеДанные.моделиМарки(чистая).map { МодельАвто(имя: $0.имя, поколения: [], кузов: $0.кузов) }
    }

    // MARK: Запрос

    /// GET от корня сайта. 404/405/410/501, перенаправление, не JSON — сервера нет; обрыв, 429 и 5xx — сеть.
    private static func получить(_ путь: String, _ поля: [URLQueryItem]) async -> ОтветСправочникаАвтоподбора {
        guard var ч = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false) else { return .нетСервера }
        ч.path = путь
        ч.queryItems = поля
        guard let адрес = ч.url else { return .нетСервера }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.cachePolicy = .reloadIgnoringLocalCacheData
        let пара: (Data, URLResponse)
        do {
            пара = try await сессия.data(for: запрос)
        } catch {
            return .сеть
        }
        guard let http = пара.1 as? HTTPURLResponse else { return .сеть }
        let код = http.statusCode
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
        /* 429 — сервер просит подождать: как обрыв, человек введёт параметры сам или повторит позже. */
        guard (200..<500).contains(код), код != 429 else { return .сеть }
        /* Перенаправление URLSession проходит сам — пришла чужая страница вместо JSON: сервера нет. */
        if let конечный = http.url, конечный.path != путь { return .нетСервера }
        guard let j = (try? JSONSerialization.jsonObject(with: пара.0)) as? [String: Any] else { return .нетСервера }
        return .json(j)
    }
}
