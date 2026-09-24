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

    private static let pollInterval: TimeInterval = 30
    private static let turboInterval: TimeInterval = 10
    private static let turboWindow = 5
    private static let missGiveUp = 12
    private static let freshness: TimeInterval = 3600   // «Топ» бывает старым — такое не новое

    private(set) var state = Persisted()
    var error: String?
    var highlightedAdId: Int?
    private(set) var blockedUntil: Date?
    private(set) var running = false

    private var loop: Task<Void, Never>?
    private var lastTurbo = Date.distantPast
    private var backoff: TimeInterval = 0
    private var misses: [Int: Int] = [:]
    private var seenSet = Set<Int>()
    private var busy = false

    var ads: [Ad] { state.ads }
    var subs: [Sub] { state.subs }
    var allAds: [Ad] { state.all ?? [] }
    private(set) var pushStatus = ""

    init() {
        load()
    }

    // MARK: — жизненный цикл

    func start() {
        guard loop == nil else { return }
        running = true
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        running = false
        save()
        scheduleBackgroundRefresh()
    }

    private func tick() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        if let until = blockedUntil, until > Date() { return }
        if state.turbo, Date().timeIntervalSince(lastTurbo) >= Self.turboInterval {
            lastTurbo = Date()
            await turbo()
        }
        for sub in state.subs where !sub.paused {
            if let last = sub.lastPoll, Date().timeIntervalSince(last) < Self.pollInterval { continue }
            if let until = blockedUntil, until > Date() { break }
            await poll(sub.id)
        }
    }

    /// Проверить все поиски сейчас (кнопка и фоновое обновление).
    func pollAll() async {
        for sub in state.subs where !sub.paused { await poll(sub.id) }
    }

    // MARK: — поиск

    private func poll(_ id: Int) async {
        guard let url = state.subs.first(where: { $0.id == id })?.url else { return }
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
            if let created = ad.createdAt, Date().timeIntervalSince(created) > Self.freshness { continue }
            if let full = try? await OLX.offer(ad.id) { ad.merge(full) }
            ad.via = "search"
            ad.subIds = [id]
            ad.foundAt = Date()
            recordAll(ad)
            add(ad, subs: [sub])
        }
        save()
    }

    private func learn(_ sub: inout Sub, from ads: [Ad]) {
        for ad in ads {
            if let cat = ad.categoryId, !sub.learnedCategories.contains(cat) { sub.learnedCategories.append(cat) }
            if !ad.city.isEmpty, !sub.learnedCities.contains(ad.city), sub.learnedCities.count < 50 { sub.learnedCities.append(ad.city) }
            sub.learnedTotal += 1
        }
    }

    // MARK: — турбо: следующие номера напрямую, раньше поиска

    private func turbo() async {
        let ready = state.subs.filter { !$0.paused && $0.ready }
        guard state.frontier > 0 else { return }
        var ids: [Int] = []
        var n = state.frontier + 1
        while ids.count < Self.turboWindow && n <= state.frontier + Self.turboWindow * 5 {
            if (misses[n] ?? 0) < Self.missGiveUp && !seenSet.contains(n) { ids.append(n) }
            n += 1
        }
        for id in ids {
            if let until = blockedUntil, until > Date() { break }
            let offer: Ad?
            do {
                offer = try await OLX.offer(id)
                ok()
                state.stats.turboProbes += 1
            } catch {
                fail(error)
                if Self.isBlocked(error) { break }
                continue
            }
            guard var ad = offer else { misses[id, default: 0] += 1; continue }
            misses[id] = nil
            bumpFrontier(id)
            state.stats.turboFound += 1
            state.stats.lastTurboHit = Date()
            guard !seenSet.contains(id) else { continue }
            remember(id)
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
        content.title = (ad.early ? "⚡ " : "") + (ad.title.isEmpty ? "Объявление \(ad.id)" : ad.title)
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
        if state.seen.count > 20_000 {
            let drop = state.seen.prefix(state.seen.count - 20_000)
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
        if Self.isBlocked(error) {
            backoff = min(900, max(60, backoff * 2))
            blockedUntil = Date().addingTimeInterval(backoff)
        }
        self.error = error.localizedDescription
    }

    private func ok() {
        backoff = 0
        error = nil
    }

    // MARK: — поиски

    func addSub(url: String, name: String) async -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if OLX.adId(fromURL: trimmed) != nil {
            error = "Это ссылка на одно объявление. Нужна ссылка на поиск — страница со списком."
            return false
        }
        do { _ = try OLX.newestFirst(trimmed) } catch {
            self.error = error.localizedDescription
            return false
        }
        let title = name.trimmingCharacters(in: .whitespaces)
        let sub = Sub(id: state.nextSubId, name: String((title.isEmpty ? Self.nameFromURL(trimmed) : title).prefix(60)), url: trimmed)
        state.nextSubId += 1
        state.subs.append(sub)
        error = nil
        save()
        await poll(sub.id)   // первый проход сразу
        return true
    }

    func togglePause(_ sub: Sub) {
        updateSub(sub.id) { $0.paused.toggle() }
        save()
    }

    func delete(_ sub: Sub) {
        state.subs.removeAll { $0.id == sub.id }
        save()
    }

    func setTurbo(_ on: Bool) {
        state.turbo = on
        save()
    }

    func clearFeed() {
        state.ads.removeAll()
        state.all = []
        save()
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
    // iOS не даёт приложению работать в фоне. Сервер на kliko.kz (wake.php по cron) раз в
    // несколько минут шлёт тихий пуш — iPhone ненадолго будит приложение, и оно само проверяет
    // OLX с телефона. Сервер к OLX не ходит. Настройка необязательна.

    static let defaultPushEndpoint = "https://kliko.kz/olx-watch/api.php"
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
        await turbo()
        save()
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
            await self.turbo()
            self.save()
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
    }

    func save() {
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
