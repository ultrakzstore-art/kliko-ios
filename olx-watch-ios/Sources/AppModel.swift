import BackgroundTasks
import Foundation
import Observation
import Security
import UIKit
import UserNotifications

/// Состояние и сборщик. Всё работает в самом телефоне: поиск — раз в 30 секунд, турбо — раз
/// в 10 секунд, пока приложение открыто; в фоне — поиск, когда iOS разрешит (раз в 15+ минут).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let refreshTaskId = "kz.kliko.olxwatch.refresh"
    static let processingTaskId = "kz.kliko.olxwatch.processing"

    /// Скорость: как часто спрашивать OLX. Чаще — быстрее ловим, но выше риск, что OLX
    /// ограничит запросы с телефона (тогда сработает пауза).
    enum Speed: String, CaseIterable, Identifiable {
        case normal, fast, max
        var id: String { rawValue }
        var title: String {
            switch self {
            case .normal: return "Обычная — поиск 30 с, турбо 10 с"
            case .fast: return "Быстрая — поиск 15 с, турбо 5 с"
            case .max: return "Максимум — поиск 10 с, турбо 3 с"
            }
        }
        var poll: TimeInterval { self == .normal ? 30 : self == .fast ? 15 : 10 }
        var turbo: TimeInterval { self == .normal ? 10 : self == .fast ? 5 : 3 }
    }

    var speed: Speed = Speed(rawValue: UserDefaults.standard.string(forKey: "speed") ?? "") ?? .fast {
        didSet { UserDefaults.standard.set(speed.rawValue, forKey: "speed") }
    }
    private static let turboWindow = 8
    private static let missGiveUp = 12
    /// «Новое» — подано не раньше, чем столько минут назад (настройка; по умолчанию 1).
    static let freshnessChoices = [1, 5, 15, 30, 60]
    var freshnessMinutes: Int = {
        let v = UserDefaults.standard.integer(forKey: "freshness_min")
        return v > 0 ? v : 1
    }() {
        didSet { UserDefaults.standard.set(freshnessMinutes, forKey: "freshness_min") }
    }

    /// Всё сохраняемое. Не наблюдается напрямую: пометки «номер уже видели», граница турбо и
    /// счётчики меняются по нескольку раз в секунду, и каждая такая мелочь перерисовывала бы
    /// ленту целиком. Экрану отдаём отдельные части — и только когда они правда изменились.
    @ObservationIgnored private(set) var state = Persisted()
    private(set) var ads: [Ad] = []
    private(set) var allAds: [Ad] = []
    private(set) var subs: [Sub] = []
    private(set) var stats = Stats()
    private(set) var frontier = 0
    private(set) var turboOn = true
    /// Живое состояние связи с OLX — для индикатора в настройках.
    private(set) var health = Health()
    var error: String?
    var highlightedAdId: Int?
    private(set) var blockedUntil: Date?
    private(set) var running = false

    private var loop: Task<Void, Never>?
    private var lastTurbo = Date.distantPast
    private var lastAnchor = Date.distantPast
    private var backoff: TimeInterval = 0
    private var misses: [Int: Int] = [:]
    private var seenSet = Set<Int>()
    private var busy = false

    private(set) var pushStatus = ""

    init() {
        // Кэш для фото: пролистанное не грузится заново.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 300 << 20)
        load()
    }

    /// Переносит изменившиеся части state в наблюдаемые свойства (только если изменились).
    func publish() {
        if ads != state.ads { ads = state.ads }
        let all = state.all ?? []
        if allAds != all { allAds = all }
        if subs != state.subs { subs = state.subs }
        if stats != state.stats { stats = state.stats }
        if frontier != state.frontier { frontier = state.frontier }
        if turboOn != state.turbo { turboOn = state.turbo }
    }

    // MARK: — жизненный цикл

    func start() {
        guard loop == nil else { return }
        running = true
        lastAnchor = .distantPast   // открыли приложение — сразу смотрим, где сейчас OLX
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                self?.publish()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        running = false
        saveNow()
        scheduleBackgroundRefresh()
    }

    private func tick() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if let until = blockedUntil, until > Date() { return }
        // Где сейчас OLX: при открытии — сразу, дальше с частотой поиска.
        if Date().timeIntervalSince(lastAnchor) >= speed.poll {
            lastAnchor = Date()
            await anchor()
        }
        // Сначала поиск: он переставляет «последний номер» на самые свежие объявления, и турбо
        // после долгой паузы не бредёт по вчерашним номерам.
        for sub in state.subs where !sub.paused {
            if let last = sub.lastPoll, Date().timeIntervalSince(last) < speed.poll { continue }
            if let until = blockedUntil, until > Date() { break }
            await poll(sub.id)
        }
        if state.turbo, Date().timeIntervalSince(lastTurbo) >= speed.turbo {
            lastTurbo = Date()
            await turbo()
        }
    }

    /// Проверить все поиски сейчас (кнопка и фоновое обновление).
    func pollAll() async {
        for sub in state.subs where !sub.paused { await poll(sub.id) }
        publish()
    }

    // MARK: — поиск

    private func poll(_ id: Int) async {
        guard let found = state.subs.first(where: { $0.id == id }) else { return }
        if found.site != .olx { return await pollSite(found) }
        let url = found.url
        let frontierBefore = state.frontier
        let ads: [Ad]
        do {
            ads = try await OLX.search(url)
            ok()
            state.stats.searchOk += 1
        } catch {
            state.stats.searchErr += 1
            fail(error)
            updateSub(id) { $0.lastPoll = Date(); $0.error = error.localizedDescription }
            save()
            return
        }
        for ad in ads { bumpFrontier(ad.id) }
        guard let index = state.subs.firstIndex(where: { $0.id == id }) else { return }
        var sub = state.subs[index]
        sub.lastPoll = Date()
        sub.error = ads.isEmpty ? "Поиск ничего не вернул" : ""
        learn(&sub, from: ads.filter { !$0.promoted })

        // Первый проход — только запоминаем выдачу, чтобы не засыпать старьём.
        if !sub.ready {
            ads.forEach { remember($0.id) }
            sub.ready = true
            state.subs[index] = sub
            save()
            return
        }
        state.subs[index] = sub

        for var ad in ads where !seenSet.contains(ad.id) {
            remember(ad.id)
            if isStale(ad, frontier: frontierBefore) { continue }
            if let full = try? await OLX.offer(ad.id) { ad.merge(full) }
            // Дата подачи часто есть только в карточке — проверяем ещё раз, уже с ней.
            if isStale(ad, frontier: frontierBefore) { continue }
            ad.via = "search"
            ad.subIds = [id]
            ad.foundAt = Date()
            recordAll(ad)
            add(ad, subs: [sub])
        }
        save()
    }

    /// Kolesa, Krisha, Kaspi: новое — номер больше самого большого, что поиск уже видел.
    /// Подробности (фото, цена, описание) — из карточки, только для нового.
    private func pollSite(_ found: Sub) async {
        let site = found.site
        let ads: [Ad]
        do {
            ads = try await site.search(found.url)
            ok()
            state.stats.searchOk += 1
        } catch {
            state.stats.searchErr += 1
            fail(error)
            updateSub(found.id) { $0.lastPoll = Date(); $0.error = error.localizedDescription }
            save()
            return
        }
        guard let index = state.subs.firstIndex(where: { $0.id == found.id }) else { return }
        var sub = state.subs[index]
        sub.lastPoll = Date()
        sub.error = ads.isEmpty ? "Поиск ничего не вернул — проверьте ссылку" : ""
        let top = ads.map(\.id).max() ?? 0
        // Первый проход — только запоминаем выдачу.
        if !sub.ready {
            ads.forEach { remember($0.id) }
            sub.ready = true
            sub.watermark = top
            state.subs[index] = sub
            save()
            return
        }
        let mark = sub.watermark ?? top
        sub.watermark = max(mark, top)
        state.subs[index] = sub
        for var ad in ads.sorted(by: { $0.id < $1.id }) where ad.id > mark && !seenSet.contains(ad.id) {
            remember(ad.id)
            if let full = try? await site.detail(ad) { ad.merge(full) }
            // Дата подачи есть не у всех карточек; есть и старше часа — это не новое.
            if let created = ad.createdAt, Date().timeIntervalSince(created) > TimeInterval(max(freshnessMinutes, 60) * 60) { continue }
            ad.source = site.rawValue
            ad.via = "search"
            ad.subIds = [sub.id]
            ad.foundAt = Date()
            recordAll(ad)
            add(ad, subs: [sub])
        }
        save()
    }

    /// Новое — это подано меньше часа назад. Старое, которое подняли или продвинули, всплывает
    /// наверх выдачи — его отсекаем по дате подачи, а если даты нет — по номеру: у поднятого
    /// старья он сильно меньше самых свежих номеров.
    private func isStale(_ ad: Ad, frontier: Int) -> Bool {
        if let created = ad.createdAt { return Date().timeIntervalSince(created) > TimeInterval(freshnessMinutes * 60) }
        return frontier > 0 && ad.id < frontier - 5_000
    }

    private func learn(_ sub: inout Sub, from ads: [Ad]) {
        for ad in ads {
            if let cat = ad.categoryId, !sub.learnedCategories.contains(cat) { sub.learnedCategories.append(cat) }
            if !ad.city.isEmpty, !sub.learnedCities.contains(ad.city), sub.learnedCities.count < 50 { sub.learnedCities.append(ad.city) }
            sub.learnedTotal += 1
        }
    }

    // MARK: — турбо: следующие номера напрямую, раньше поиска

    /// Самые свежие объявления всей доски: турбо перескакивает к ним, а не бредёт от номера,
    /// на котором приложение закрыли (после часа паузы это тысячи номеров, и всё старше
    /// минуты отбрасывается — лента стояла пустой). Свежее из них сразу идёт в ленту.
    private func anchor() async {
        let ads: [Ad]
        do {
            ads = try await OLX.latest()
            ok()
        } catch {
            fail(error)
            return
        }
        guard let top = ads.map(\.id).max() else { return }
        if top > state.frontier + Self.turboWindow * 3 {
            state.frontier = top - Self.turboWindow   // прыжок; последние номера турбо ещё проверит
        }
        let ready = state.subs.filter { !$0.paused && $0.ready && $0.site == .olx }
        for var ad in ads.sorted(by: { $0.id < $1.id }) where !seenSet.contains(ad.id) && !ad.promoted {
            if isStale(ad, frontier: 0) { continue }
            remember(ad.id)
            let hit = ready.filter { OLX.matches($0, ad) }
            ad.via = "search"
            ad.subIds = hit.map(\.id)
            ad.foundAt = Date()
            recordAll(ad)
            if !hit.isEmpty { add(ad, subs: hit) }
        }
        publish()
    }

    private func turbo() async {
        let ready = state.subs.filter { !$0.paused && $0.ready && $0.site == .olx }
        guard state.frontier > 0 else { return }
        var ids: [Int] = []
        var n = state.frontier + 1
        while ids.count < Self.turboWindow && n <= state.frontier + Self.turboWindow * 5 {
            if (misses[n] ?? 0) < Self.missGiveUp && !seenSet.contains(n) { ids.append(n) }
            n += 1
        }
        // Все номера прохода — одновременно: быстрее ловим и не ждём каждый ответ по очереди.
        let results = await withTaskGroup(of: (Int, Result<Ad?, Error>).self) { group in
            for id in ids {
                group.addTask {
                    do { return (id, .success(try await OLX.offer(id))) } catch { return (id, .failure(error)) }
                }
            }
            var out: [(Int, Result<Ad?, Error>)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        for (id, result) in results {
            let offer: Ad?
            switch result {
            case .success(let o):
                offer = o
                ok()
                state.stats.turboProbes += 1
            case .failure(let error):
                fail(error)
                continue
            }
            guard var ad = offer else { misses[id, default: 0] += 1; continue }
            misses[id] = nil
            bumpFrontier(id)
            state.stats.turboFound += 1
            state.stats.lastTurboHit = Date()
            guard !seenSet.contains(id) else { continue }
            remember(id)
            if isStale(ad, frontier: 0) { continue }   // после долгой паузы — не вчерашнее
            let hit = ready.filter { OLX.matches($0, ad) }
            ad.via = "turbo"
            ad.subIds = hit.map(\.id)
            ad.foundAt = Date()
            recordAll(ad)                 // «Все новые» — любое пойманное объявление
            guard !hit.isEmpty else { continue }
            add(ad, subs: hit)            // «По запросам» и уведомление — только подходящее
        }
        misses = misses.filter { $0.key > state.frontier - 500 }
        save()
    }

    // MARK: — найденное

    private func add(_ ad: Ad, subs: [Sub]) {
        state.ads.insert(ad, at: 0)
        if state.ads.count > 500 { state.ads.removeLast(state.ads.count - 500) }
        for s in subs { updateSub(s.id) { $0.sent += 1 } }
        notify(ad, subs: subs)
    }

    private func notify(_ ad: Ad, subs: [Sub]) {
        let content = UNMutableNotificationContent()
        content.title = (ad.early ? "⚡ " : "") + (ad.title.isEmpty ? "Объявление" : ad.title)
        content.subtitle = [ad.priceText, ad.city].filter { !$0.isEmpty }.joined(separator: " · ")
        content.body = subs.map(\.name).joined(separator: ", ")
        content.sound = .default
        content.threadIdentifier = "sub-\(subs.first?.id ?? 0)"
        content.userInfo = ["ad_id": ad.id, "url": ad.link?.absoluteString ?? ""]
        let req = UNNotificationRequest(identifier: "ad-\(ad.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    private func recordAll(_ ad: Ad) {
        var list = state.all ?? []
        guard !list.contains(where: { $0.id == ad.id }) else { return }
        list.insert(ad, at: 0)
        if list.count > 300 { list.removeLast(list.count - 300) }
        state.all = list
    }

    private func remember(_ id: Int) {
        guard seenSet.insert(id).inserted else { return }
        state.seen.append(id)
        if state.seen.count > 5_000 {
            let drop = state.seen.prefix(state.seen.count - 5_000)
            drop.forEach { seenSet.remove($0) }
            state.seen.removeFirst(drop.count)
        }
    }

    private func bumpFrontier(_ id: Int) {
        if id > state.frontier { state.frontier = id }
    }

    // Бережём себя: на 403/429 — пауза, каждый раз вдвое дольше, до 15 минут.
    private static func isBlocked(_ error: Error) -> Bool {
        if let f = error as? OLX.Failure, case .blocked(_) = f { return true }
        return false
    }

    private func fail(_ error: Error) {
        health.lastFailure = Date()
        health.lastError = error.localizedDescription
        if let f = error as? OLX.Failure {
            switch f {
            case .blocked(let code), .http(let code): health.lastCode = code
            case .badURL: break
            }
        }
        if Self.isBlocked(error) {
            backoff = min(900, max(60, backoff * 2))
            blockedUntil = Date().addingTimeInterval(backoff)
        }
        self.error = error.localizedDescription
    }

    private func ok() {
        health.lastSuccess = Date()
        health.lastCode = 200
        backoff = 0
        error = nil
    }

    /// «Проверить связь сейчас»: один запрос к OLX, код ответа и время.
    func checkConnection() async -> String {
        let url = state.subs.first?.url ?? "\(OLX.base)/d/elektronika/"
        let started = Date()
        do {
            let ads = try await OLX.search(url)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            ok()
            health.lastLatencyMs = ms
            return "OLX отвечает: 200 за \(ms) мс, в выдаче \(ads.count) объявлений"
        } catch {
            fail(error)
            return "OLX не ответил: \(error.localizedDescription)"
        }
    }

    /// Рубрика для подписи в карточке: из поиска, который поймал объявление, иначе — из карточки
    /// OLX, иначе — из поиска, который уже видел такую рубрику.
    func categoryText(for ad: Ad) -> String? {
        for sub in subs where ad.subIds.contains(sub.id) {
            if let label = sub.categoryLabel, !label.isEmpty { return label }
        }
        if let c = ad.category, !c.isEmpty { return c }
        if let cat = ad.categoryId,
           let sub = subs.first(where: { $0.learnedCategories.contains(cat) && !($0.categoryLabel ?? "").isEmpty }) {
            return sub.categoryLabel
        }
        return nil
    }

    // MARK: — поиски

    func addSub(url: String, name: String, categoryLabel: String? = nil) async -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let site = Site.of(url: trimmed) else {
            error = "Нужна ссылка на поиск с olx.kz, kolesa.kz, krisha.kz или Kaspi Объявлений."
            return false
        }
        if site.isAdURL(trimmed) {
            error = "Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком."
            return false
        }
        do { _ = try site.newestFirst(trimmed) } catch {
            self.error = error.localizedDescription
            return false
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        var sub = Sub(id: state.nextSubId, name: String((title.isEmpty ? Self.nameFromURL(trimmed) : title).prefix(60)), url: trimmed)
        sub.categoryLabel = categoryLabel
        sub.source = site == .olx ? nil : site.rawValue
        state.nextSubId += 1
        state.subs.append(sub)
        error = nil
        save()
        publish()
        await poll(sub.id)   // первый проход сразу
        return true
    }

    func togglePause(_ sub: Sub) {
        updateSub(sub.id) { $0.paused.toggle() }
        save()
        publish()
    }

    func delete(_ sub: Sub) {
        state.subs.removeAll { $0.id == sub.id }
        save()
        publish()
    }

    func setTurbo(_ on: Bool) {
        state.turbo = on
        save()
        publish()
    }

    func clearFeed() {
        state.ads.removeAll()
        state.all = []
        save()
        publish()
    }

    private func updateSub(_ id: Int, _ change: (inout Sub) -> Void) {
        guard let i = state.subs.firstIndex(where: { $0.id == id }) else { return }
        change(&state.subs[i])
    }

    static func nameFromURL(_ url: String) -> String {
        let path = URLComponents(string: url)?.path.removingPercentEncoding ?? ""
        let parts = path.split(separator: "/").map(String.init).filter { !["d", "kk", "list"].contains($0) }
        if let q = parts.first(where: { $0.hasPrefix("q-") }) { return q.dropFirst(2).replacingOccurrences(of: "-", with: " ") }
        return parts.suffix(2).joined(separator: " / ").isEmpty ? "Поиск" : parts.suffix(2).joined(separator: " / ")
    }

    // MARK: — уведомления и фон

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        UIApplication.shared.registerForRemoteNotifications()   // токен — для тихих пушей-будильников
    }

    // MARK: — будильник через APNs
    //
    // iOS не даёт приложению работать в фоне. Свой сервер (wake.php по cron) раз в
    // несколько минут шлёт тихий пуш — iPhone ненадолго будит приложение, и оно само проверяет
    // OLX с телефона. Сервер к OLX не ходит. Настройка необязательна.

    static let defaultPushEndpoint = ""
    var pushEndpoint: String = UserDefaults.standard.string(forKey: "push_endpoint") ?? AppModel.defaultPushEndpoint
    var pushKey: String = Keychain.read("push_key") ?? ""
    private var deviceToken: String? = UserDefaults.standard.string(forKey: "device_token")

    var pushConfigured: Bool { !pushKey.isEmpty }

    func didReceiveDeviceToken(_ data: Data) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: "device_token")
        await registerDevice()
    }

    func connectPushServer(endpoint: String, key: String) async {
        let e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: e), url.scheme == "https" else { pushStatus = "Адрес должен начинаться с https://"; return }
        pushEndpoint = e
        pushKey = k
        UserDefaults.standard.set(e, forKey: "push_endpoint")
        Keychain.write("push_key", k)
        pushStatus = "Подключаю…"
        await requestNotifications()
        await registerDevice()
    }

    private func registerDevice() async {
        guard pushConfigured, let url = URL(string: pushEndpoint) else { return }
        guard let token = deviceToken else { pushStatus = "Жду токен пушей от iPhone — разрешите уведомления"; return }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "a", value: "device")]
        guard let target = c?.url else { return }
        var req = URLRequest(url: target, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("Bearer \(pushKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token])
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            pushStatus = (200..<300).contains(code) ? "Подключено: сервер будит приложение тихими пушами"
                : code == 401 ? "Сервер не принял ключ" : "Сервер ответил \(code)"
        } catch {
            pushStatus = "Нет связи с сервером: \(error.localizedDescription)"
        }
    }

    /// Тихий пуш от сервера: короткая проверка — поиски и один проход турбо.
    func handleWakePush() async -> Bool {
        let before = state.ads.count
        await pollAll()
        await anchor()
        await turbo()
        publish()
        saveNow()
        return state.ads.count > before
    }

    /// Просим iOS будить нас как можно чаще. Когда именно — решает система: по тому, как часто
    /// приложением пользуются, заряду и сети. Обычно — раз в 15–60 минут, ночью на зарядке — дольше.
    func scheduleBackgroundRefresh() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        // Вторая, «долгая» задача: iOS даёт ей больше времени (обычно на зарядке и в Wi-Fi).
        let processing = BGProcessingTaskRequest(identifier: Self.processingTaskId)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        try? BGTaskScheduler.shared.submit(processing)
    }

    /// Фоновая работа от iOS: поиски и проход турбо, новые — уведомлением.
    func handleBackgroundTask(_ task: BGTask) {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await self.pollAll()
            await self.anchor()
            await self.turbo()
            self.publish()
            self.saveNow()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    // MARK: — хранение

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let saved = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        state = saved
        seenSet = Set(saved.seen)
        publish()
    }

    /// Сохранение — не чаще раза в 3 секунды и не в главном потоке: кодирование всей ленты
    /// после каждой проверки подвешивало интерфейс.
    private var saveTask: Task<Void, Never>?

    func save() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            let snapshot = self.state
            self.saveTask = nil
            let url = Self.fileURL
            await Task.detached(priority: .utility) {
                guard let data = try? JSONEncoder().encode(snapshot) else { return }
                try? data.write(to: url, options: .atomic)
            }.value
        }
    }

    /// Сразу и целиком — при уходе в фон и в конце фоновой задачи, когда ждать нельзя.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

/// Ключ сервера пушей — в Связке ключей, а не в настройках приложения.
enum Keychain {
    private static let service = "kz.kliko.olxwatch"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
