import SwiftUI
import UIKit

/**
 ИЗБРАННОЕ ВМЕСТЕ С САЙТОМ — ЭТАП 35 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Витрина сайта (js/marketplace.min.js: favToggle, favInit, mkFavEnsure) держит избранное вошедшего на сервере и ходит за
 ним так — адрес от _MKB = "/" (_ULX_BASE пуст), куки веб-сессии, csrf полем JSON:
   · GET  favorites.php?action=list                      → {ok, ids[]} — избранное аккаунта;
   · POST favorites.php?action=add | remove  {id, csrf}  → {ok, ids[]} — полный список после нажатия;
   · POST favorites.php?action=merge         {ids, csrf} → {ok, ids[]} — один раз влить избранное устройства (флаг
     ulx_fav_migrated: ставится после удачного merge, а при пустом избранном — сразу, и дальше только list);
   · GET  api/listings.php?ids=<id,id,…>                 → {ok, items[]} — карточки номеров, которых нет на странице.
 Приложение делает то же самое. Куки — SiteSession.куки(), токен — SiteSession.состояние() (window._MKP_CSRF, запасной —
 window.KlikoCsrf), вошёл ли человек — там же (непустой KlikoUser.id, _MK_AUTH, __ULX_GUEST).

 ПРАВИЛА ЗАПИСИ. Запись на сайт — только по нажатию сердечка (FavoritesStore.переключить → нажали) и одно слияние; сами
 по себе ни add, ни remove не уходят, повторов нет. Нажатие меняет список на экране сразу, как у сайта; сайт отказал или
 нет связи — сердечко возвращается (снятая запись — на своё место) и внизу его текст ошибки. Все обращения к сайту идут
 по одному, в порядке нажатий (очередь): ответ одного не перебивает другое. Два нажатия на одно сердечко, пока первое
 ещё не ушло, гасят друг друга — на сайте ничего не меняется.

 КОГДА СВЕРЯЕМСЯ (list или merge и недостающие карточки): при открытии вкладки «Избранное» — не чаще раза в 10 с, при
 возврате в приложение, первой загрузке страницы и возврате со страницы сайта — раз в 60 с, «потяни — обновится» —
 сразу. Паузу считает только настоящий запрос к сайту: проверка «гость» ничего не стоит.

 ГОСТЬ — как на этапе 5: сердечко только на телефоне. Страница не ответила, вошёл ли человек (переходит или грузится):
 вошедшим его в этот запуск уже видели — нажатие уходит с его прежним токеном (у сессии он один на все страницы); не
 видели, а телефон уже сверялся с аккаунтом (флаг слияния; стирает его только выход, как у сайта — вместе с
 localStorage) — откатываем с «Ошибка сети»: записать некуда, а молча оставить значит потерять его при следующей сверке.

 Флаг слияния — один на телефон, а не на аккаунт, как у сайта: вошёл другой человек без выхода (сессия истекла) — его
 список с сайта заменит этот, а не вольётся в чужой аккаунт.
 */
enum ИзбранноеСайта {
    enum Итог: Equatable {
        /// ok: true — полный список номеров (ids); nil — ok пришёл, а списка нет или он не того вида.
        case список([String]?)
        /// need/error «auth» (и need_reg), 401/403 — показать вход.
        case нуженВход
        /// need/error «verify» (need_verification) — нужна верификация.
        case нужнаВерификация
        /// error «csrf» — токен страницы устарел.
        case защита
        /// Иной отказ: текст сайта для человека (ulxErr) или nil — тогда «Не удалось сохранить».
        case отказ(String?)
        case сеть
    }

    /// Карточки — пачками по 48, как страница ленты: длинный список номеров — не один бесконечный адрес.
    static let пачка = 48

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpAdditionalHeaders = ["Accept": "application/json"]
        c.timeoutIntervalForRequest = 15
        c.httpShouldSetCookies = false        // куки — из WebKit (SiteSession), своих не заводим
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData   // избранное — всегда свежее
        return URLSession(configuration: c)
    }()

    private static let кодыВхода: Set<String> = ["auth", "need_reg"]
    private static let кодыВерификации: Set<String> = ["verify", "need_verification", "need_verify"]

    /// GET favorites.php?action=list.
    static func список() async -> Итог {
        guard let адрес = ссылка("list") else { return .отказ(nil) }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        return await выполнить(запрос)
    }

    /// POST favorites.php?action=add|remove {id, csrf} — ровно тело favToggle сайта.
    static func изменить(_ id: String, добавить: Bool, csrf: String) async -> Итог {
        await отправить(добавить ? "add" : "remove", тело: ["id": id, "csrf": csrf])
    }

    /// POST favorites.php?action=merge {ids, csrf} — ровно тело favInit сайта.
    static func слить(_ номера: [String], csrf: String) async -> Итог {
        await отправить("merge", тело: ["ids": номера, "csrf": csrf])
    }

    /// GET api/listings.php?ids=<id,…> — mkFavEnsure сайта. Не пришло ответа — ошибка ListingsAPI, как у ленты.
    static func карточки(_ номера: [String]) async throws -> [Listing] {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/listings.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "ids", value: номера.joined(separator: ","))]
        guard let адрес = ч?.url else { throw ListingsAPI.Ошибка.разбор }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(for: запрос) } catch { throw ListingsAPI.Ошибка.сеть }
        if let http = ответ as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ListingsAPI.Ошибка.статус(http.statusCode)
        }
        return try ListingsAPI.разобрать(данные).items
    }

    // MARK: - Транспорт

    private static func ссылка(_ действие: String) -> URL? {
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("favorites.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "action", value: действие)]
        return ч?.url
    }

    private static func отправить(_ действие: String, тело: [String: Any]) async -> Итог {
        guard let адрес = ссылка(действие),
              let данные = try? JSONSerialization.data(withJSONObject: тело) else { return .отказ(nil) }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        /* Origin не подставляем (владелец: без поддельных Origin/Referer): favorites.php источник не проверяет. */
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.httpBody = данные
        return await выполнить(запрос)
    }

    private static func выполнить(_ запрос: URLRequest) async -> Итог {
        let данные: Data
        let ответ: URLResponse
        do { (данные, ответ) = try await сессия.data(for: запрос) } catch { return .сеть }
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        /* JSON разбираем и при 4xx: сайт объясняет отказ полями need/error, а не кодом. */
        guard let поля = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            return (код == 401 || код == 403) ? .нуженВход : .отказ(nil)
        }
        return разобрать(поля, код: код)
    }

    /**
     Ответ сайта → итог, по его же правилам: ok — список (ids целиком заменяет избранное, как _FAV = t.ids);
     need/error «auth» — вход, «verify» — верификация, «csrf» — защита; иначе error, если это текст для человека:
     ulxErr сайта считает короткий латинский код (/^[a-z][a-z0-9_]{1,14}$/) машинным и его не показывает.
     */
    static func разобрать(_ поля: [String: Any], код: Int) -> Итог {
        if да(поля["ok"]) { return .список(номера(поля["ids"])) }
        let нужно = строка(поля["need"]) ?? ""
        let ошибка = строка(поля["error"]) ?? ""
        let причины = Set([нужно, ошибка])
        if !причины.isDisjoint(with: кодыВхода) || да(поля["need_reg"]) || код == 401 || код == 403 {
            return .нуженВход
        }
        if !причины.isDisjoint(with: кодыВерификации) || да(поля["need_verification"]) {
            return .нужнаВерификация
        }
        if ошибка == "csrf" { return .защита }
        let машинный = ошибка.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil
        return .отказ(ошибка.isEmpty || машинный ? nil : ошибка)
    }

    /// ids — массив номеров (строкой или числом). PHP с дырами в ключах отдаёт массив объектом {"0":…,"2":…} — берём
    /// по порядку ключей. Повторы убираем. Не массив и не объект — nil: такой ответ список не меняет (сайт бы его
    /// обнулил — у нас лучше ничего, чем пусто).
    static func номера(_ значение: Any?) -> [String]? {
        let сырые: [Any]
        if let массив = значение as? [Any] {
            сырые = массив
        } else if let словарь = значение as? [String: Any] {
            let ключи = словарь.keys.sorted { (Int($0) ?? Int.max) < (Int($1) ?? Int.max) }
            сырые = ключи.compactMap { словарь[$0] }
        } else {
            return nil
        }
        var виденные = Set<String>()
        var итог: [String] = []
        for элемент in сырые {
            guard let номер = строка(элемент), виденные.insert(номер).inserted else { continue }
            итог.append(номер)
        }
        return итог
    }

    private static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
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

/// Избранное вошедшего — с сайтом: очередь обращений, сверка, откат и сообщение об ошибке (см. шапку файла).
@MainActor
final class СинхронИзбранного: ObservableObject {
    static let shared = СинхронИзбранного()

    /// Сообщение внизу экрана — как toast сайта.
    struct Сообщение: Equatable {
        let id = UUID()
        let текст: String
        /// Рядом «Войти» — сайт сказал «нужен вход» (mkToastAct сайта с кнопкой).
        let войти: Bool
    }

    @Published private(set) var сообщение: Сообщение?
    /// Идёт list или merge с карточками — пустое избранное показывает «Загружаем объявления», а не «пусто».
    @Published private(set) var загружаем = false
    /// Вошедший и уже сверенный со своим аккаунтом телефон — подпись «хранится в вашем аккаунте».
    @Published private(set) var связано = false

    private struct Изменение {
        let id: String
        let добавить: Bool
        /// Снятая запись — вернуть на место, если сайт откажет. У добавления — nil.
        let была: ИзбранноеЗапись?
    }

    private enum Работа {
        /// list или merge; пауза — сколько секунд после прошлой сверки её пропускать.
        case сверка(TimeInterval)
        case изменение(Изменение)

        /// Нажатие, если это оно, — для поиска по очереди.
        var нажатие: Изменение? {
            switch self {
            case .сверка: return nil
            case .изменение(let и): return и
            }
        }
    }

    private var очередь: [Работа] = []
    private var работаем = false
    /// Ждут, пока очередь опустеет, — «потяни — обновится».
    private var ждут: [CheckedContinuation<Void, Never>] = []
    /// Когда последний раз спрашивали сайт (list или merge). nil — в этот запуск ещё не спрашивали.
    private var последняяСверка: Date?
    /// Что страница сказала в последний раз: вошёл, гость или nil — ещё не знаем.
    private var последнийВход: Bool?
    /// Токен вошедшего, виденный в этот запуск (только в памяти): у сессии он один на все её страницы, и нажатие, пока
    /// страница под слоем переходит и не отвечает, уходит с ним, а не откатывается.
    private var последнийТокен: String?
    /// Номера, чьих карточек сайт не отдал (снято или удалено), — в этот запуск больше не просим.
    private var безКарточки: Set<String> = []
    /// Растёт при выходе: ответ, пришедший после него, — чужой, его не применяем.
    private var поколение = 0

    /// Флаг слияния — ulx_fav_migrated сайта. Стирается при выходе (стереть()).
    private static let ключСлияния = "kliko.fav.migrated"
    private var слито: Bool {
        get { UserDefaults.standard.bool(forKey: Self.ключСлияния) }
        set { UserDefaults.standard.set(newValue, forKey: Self.ключСлияния) }
    }

    private init() {
        связано = Config.избранноеССайтом && UserDefaults.standard.bool(forKey: Self.ключСлияния)
    }

    // MARK: - Снаружи

    /// Нажали сердечко — FavoritesStore.переключить уже поменял список на экране; `была` — снятая запись для отката.
    func нажали(_ id: String, добавить: Bool, была: ИзбранноеЗапись?) {
        guard Config.избранноеССайтом, Config.избранное else { return }
        /* Прошлое нажатие на это сердечко ещё не ушло — два нажатия гасят друг друга: на сайте всё как было, и на экране
           снова так же. */
        if let место = местоВОчереди(id) {
            очередь.remove(at: место)
            return
        }
        поставить(.изменение(Изменение(id: id, добавить: добавить, была: была)))
    }

    /// Сверить с сайтом, если с прошлого запроса прошло не меньше `пауза` секунд. Одна сверка в очереди — вторую не ставим.
    func сверить(пауза: TimeInterval) {
        guard Config.избранноеССайтом, Config.избранное else { return }
        let ужеЖдёт = очередь.contains { работа in работа.нажатие == nil }
        guard !ужеЖдёт else { return }
        поставить(.сверка(пауза))
    }

    /// «Потяни — обновится» во вкладке: сверить сейчас и дождаться конца.
    func обновить() async {
        guard Config.избранноеССайтом, Config.избранное else { return }
        последняяСверка = nil
        сверить(пауза: 0)
        guard работаем else { return }
        await withCheckedContinuation { (готово: CheckedContinuation<Void, Never>) in
            ждут.append(готово)
        }
    }

    /// Нажали «Войти» в сообщении — свой экран входа листом поверх вкладок (ОкнаПриложения); слоя окон нет — тот же
    /// экран поверх всего (ВходПоверх).
    func войти() {
        сообщение = nil
        let адрес = Config.страницаСайта("cabinet.php")
        if ОкнаПриложения.shared.показать(.вход, запасной: адрес) { return }
        ВходПоверх.показать()
    }

    /// Выход из аккаунта (WebContainer, bye=1): флаг слияния — как ulx_fav_migrated в стёртом localStorage сайта:
    /// следующий вошедший вольёт своё избранное с телефона. Очередь ушедшего не отправляем, его ответы не применяем.
    func стереть() {
        поколение += 1
        очередь.removeAll()
        безКарточки = []
        последняяСверка = nil
        последнийВход = nil
        последнийТокен = nil
        сообщение = nil
        UserDefaults.standard.removeObject(forKey: Self.ключСлияния)
        связано = false
    }

    // MARK: - Очередь

    private func местоВОчереди(_ id: String) -> Int? {
        очередь.firstIndex { работа in работа.нажатие?.id == id }
    }

    private func поставить(_ работа: Работа) {
        очередь.append(работа)
        guard !работаем else { return }
        работаем = true
        Task { await self.разобрать() }
    }

    private func разобрать() async {
        while !очередь.isEmpty {
            let работа = очередь.removeFirst()
            switch работа {
            case .сверка(let пауза):
                await сверитьССайтом(пауза)
            case .изменение(let изменение):
                await отправить(изменение)
            }
        }
        работаем = false
        let готовые = ждут
        ждут = []
        for готово in готовые { готово.resume() }
    }

    // MARK: - Сверка

    private func сверитьССайтом(_ пауза: TimeInterval) async {
        if let прошлая = последняяСверка, Date().timeIntervalSince(прошлая) < пауза { return }
        let взятое = поколение
        let страница = await SiteSession.состояние()
        guard взятое == поколение else { return }
        запомнитьВход(страница.вошёл)
        guard страница.вошёл == true else { return }
        if let токен = страница.csrf { последнийТокен = токен }
        последняяСверка = Date()
        загружаем = true
        defer { загружаем = false }

        let местные = FavoritesStore.shared.порядок
        let итог: ИзбранноеСайта.Итог
        if !слито && !местные.isEmpty {
            /* Один раз, как favInit сайта: избранное с телефона — в аккаунт. Не вышло — в следующую сверку. */
            guard let csrf = страница.csrf else { return }
            итог = await ИзбранноеСайта.слить(местные, csrf: csrf)
            guard взятое == поколение else { return }
            if case .список(_) = итог { слито = true }
        } else {
            слито = true                 // как сайт: пустому избранному вливать нечего — дальше только list
            итог = await ИзбранноеСайта.список()
            guard взятое == поколение else { return }
        }
        if итог == .нуженВход { запомнитьВход(false) } else { запомнитьВход(true) }
        guard case .список(let пришло) = итог, let список = пришло else { return }
        await принять(список, догрузить: true, взятое: взятое)
    }

    /**
     Список с сайта — в FavoritesStore. `догрузить` — сверка: карточки номеров, которых на телефоне нет, одним-двумя
     GET api/listings.php?ids=. После нажатия (ответ add/remove) — без запросов: новые с другого устройства придут
     следующей сверкой. Ещё не отправленные нажатия список не отменяет: на экране они уже есть.
     */
    private func принять(_ список: [String], догрузить: Bool, взятое: Int) async {
        let хранилище = FavoritesStore.shared
        var карточки: [Listing] = []
        if догрузить {
            let нет = список.filter { !хранилище.есть($0) && !безКарточки.contains($0) }
            if !нет.isEmpty {
                карточки = await загрузитьКарточки(Array(нет.prefix(FavoritesStore.предел)))
                guard взятое == поколение else { return }
            }
        }
        /* Пока шли запросы, могли нажать сердечко: такие нажатия ждут в очереди — список их не отменяет. */
        var итог = список
        for работа in очередь {
            guard let изменение = работа.нажатие else { continue }
            if изменение.добавить {
                if !итог.contains(изменение.id) { итог.insert(изменение.id, at: 0) }
            } else {
                итог.removeAll { $0 == изменение.id }
            }
        }
        хранилище.принятьССайта(итог, карточки: карточки)
    }

    /// Карточки пачками по 48, одна за другой. Нет связи — остальное в следующую сверку, без повторов.
    private func загрузитьКарточки(_ номера: [String]) async -> [Listing] {
        var итог: [Listing] = []
        var начало = 0
        while начало < номера.count {
            let конец = min(начало + ИзбранноеСайта.пачка, номера.count)
            let часть = Array(номера[начало..<конец])
            начало = конец
            guard let пришли = try? await ИзбранноеСайта.карточки(часть) else { break }
            итог.append(contentsOf: пришли)
            let есть = Set(пришли.map(\.id))
            for номер in часть where !есть.contains(номер) { безКарточки.insert(номер) }
        }
        return итог
    }

    // MARK: - Нажатие

    private func отправить(_ изменение: Изменение) async {
        let взятое = поколение
        let страница = await SiteSession.состояние()
        guard взятое == поколение else { return }
        запомнитьВход(страница.вошёл)
        let csrf: String
        switch страница.вошёл {
        case .some(false):
            return                                          // гость: избранное на телефоне, как на этапе 5
        case .none:
            /* Страница не ответила (переходит или грузится). Вошедшим его в этот запуск уже видели — его же токен: у
               сессии он один. Не видели, а телефон уже сверялся с аккаунтом — записать некуда: как обрыв связи. Иначе
               это избранное гостя на телефоне. */
            if последнийВход == true, let прежний = последнийТокен {
                csrf = прежний
            } else {
                if слито && последнийВход != false {
                    откатить(изменение)
                    показать(.сеть)
                }
                return
            }
        case .some(true):
            guard let токен = страница.csrf else {
                откатить(изменение)
                показать(.защита)
                return
            }
            последнийТокен = токен
            csrf = токен
        }
        let итог = await ИзбранноеСайта.изменить(изменение.id, добавить: изменение.добавить, csrf: csrf)
        guard взятое == поколение else { return }
        switch итог {
        case .список(let пришло):
            if слито {
                /* Как сайт: полный список ответа и есть избранное. */
                if let список = пришло { await принять(список, догрузить: false, взятое: взятое) }
            } else {
                /* До слияния список ответа ещё без избранного телефона — не берём, а сливаем (один раз). */
                сверить(пауза: 60)
            }
        case .нуженВход:
            запомнитьВход(false)
            откатить(изменение)
            показать(итог)
        case .нужнаВерификация, .защита, .отказ, .сеть:
            откатить(изменение)
            показать(итог)
        }
    }

    /// Сайт не записал — на экране снова как на сайте. Следующее нажатие на то же сердечко уже ждёт в очереди — значит,
    /// на экране уже то, что на сайте: его просто не отправляем.
    private func откатить(_ изменение: Изменение) {
        if let место = местоВОчереди(изменение.id) {
            очередь.remove(at: место)
            return
        }
        let хранилище = FavoritesStore.shared
        if изменение.добавить {
            хранилище.убрать(изменение.id)
        } else if let запись = изменение.была {
            хранилище.вернуть(запись)
        }
    }

    private func запомнитьВход(_ вошёл: Bool?) {
        guard let известно = вошёл else { return }
        последнийВход = известно
        if !известно { последнийТокен = nil }
        связано = известно && слито
    }

    /// Текст ошибки сайта внизу экрана: 2,2 с, как toast сайта; с «Войти» — 5 с, как mkToastAct.
    private func показать(_ итог: ИзбранноеСайта.Итог) {
        let текст: String
        var сКнопкой = false
        switch итог {
        case .список:
            return
        case .нуженВход:
            текст = FavoritesText.т("err_auth")
            сКнопкой = true
        case .нужнаВерификация:
            текст = FavoritesText.т("err_verify")
        case .защита:
            текст = FavoritesText.т("err_csrf")
        case .сеть:
            текст = FavoritesText.т("err_net")
        case .отказ(let сайта):
            текст = сайта ?? FavoritesText.т("err_save")
        }
        let новое = Сообщение(текст: текст, войти: сКнопкой)
        сообщение = новое
        UIAccessibility.post(notification: .announcement, argument: текст)
        let срок: UInt64 = сКнопкой ? 5_000_000_000 : 2_200_000_000
        Task {
            try? await Task.sleep(nanoseconds: срок)
            if self.сообщение?.id == новое.id { self.сообщение = nil }
        }
    }
}

// MARK: - Сообщение внизу экрана

/**
 Сообщение избранного — как .mk-toast сайта (css/marketplace.min.css): тёмная плашка var(--mk-ink) со светлым текстом
 var(--mk-surf), жирность 600, отступы 12 и 20 (--m-3, --m-5), скругление --r-ms, тень 0 8px 24px rgba(0,0,0,.22), по
 центру внизу. С кнопкой — .mk-toast-act: рамка 1.5 текущим цветом, высота от 36, жирный мелкий текст. Краски —
 динамические: в тёмной теме плашка светлая с тёмным текстом, как у сайта.
 */
struct ПлашкаИзбранного: View {
    let сообщение: СинхронИзбранного.Сообщение
    let войти: () -> Void

    init(сообщение: СинхронИзбранного.Сообщение, войти: @escaping () -> Void) {
        self.сообщение = сообщение
        self.войти = войти
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(сообщение.текст)
                .font(.system(.subheadline, weight: .semibold))
                .multilineTextAlignment(сообщение.войти ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if сообщение.войти {
                Button(action: войти) {
                    Text(FavoritesText.т("login"))
                        .font(.system(.footnote, weight: .bold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.поверхность, lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            }
        }
        .foregroundStyle(Theme.поверхность)
        .padding(.vertical, 12)
        .padding(.leading, 20)
        .padding(.trailing, сообщение.войти ? 8 : 20)
        .background(Theme.текст, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /**
     Этап 35: слой избранного вместе с сайтом над нативными экранами (RootWebView) — сообщение об ошибке записи внизу и
     сверка с сайтом при возврате в приложение, первой загрузке страницы и возврате со страницы сайта (вход там же).
     Рубильник выключен — ничего не делает. Обёрткой, как «Что нового» (СлойЧтоНового), а не ViewModifier.
     */
    @MainActor
    func избранноеССайтом() -> some View {
        СлойИзбранногоССайтом(self)
    }
}

struct СлойИзбранногоССайтом<Содержимое: View>: View {
    let содержимое: Содержимое
    @ObservedObject private var синхрон = СинхронИзбранного.shared
    @ObservedObject private var мост = WebBridge.shared
    @Environment(\.scenePhase) private var фаза

    init(_ содержимое: Содержимое) {
        self.содержимое = содержимое
    }

    var body: some View {
        if Config.избранноеССайтом && Config.избранное {
            содержимое
                .overlay(alignment: .bottom) { плашка }
                .onChange(of: фаза) { _, стала in
                    if стала == .active { синхрон.сверить(пауза: 60) }
                }
                .onChange(of: мост.isLoaded) { _, загружена in
                    if загружена { синхрон.сверить(пауза: 60) }
                }
                .onChange(of: мост.лентаВидна) { _, видна in
                    if видна { синхрон.сверить(пауза: 60) }
                }
        } else {
            содержимое
        }
    }

    /// Над нижней панелью сайта и пилюлей «Связаться» объявления — как .mk-toast.act сайта (72 px над низом). Слой стоит
    /// в RootWebView снаружи прозрачности нативных экранов, поэтому, пока на экране страница сайта, плашки нет.
    private var плашка: some View {
        ZStack(alignment: .bottom) {
            if let сообщение = синхрон.сообщение, мост.лентаВидна {
                ПлашкаИзбранного(сообщение: сообщение, войти: { синхрон.войти() })
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 88)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(сообщение.id)
            }
        }
        .animation(ДвижениеСайта.смена, value: синхрон.сообщение?.id)
    }
}
