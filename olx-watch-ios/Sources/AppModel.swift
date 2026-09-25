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
            case .normal: return "Обычная — вся доска раз в 5 с"
            case .fast: return "Быстрая — вся доска раз в 3 с"
            case .max: return "Максимум — вся доска раз в 1,5 с"
            }
        }
        /// Как часто смотреть самые свежие объявления всей доски — главный источник новых.
        var board: TimeInterval { self == .normal ? 5 : self == .fast ? 3 : 1.5 }
        var poll: TimeInterval { self == .normal ? 30 : self == .fast ? 15 : 10 }
        var turbo: TimeInterval { self == .normal ? 10 : self == .fast ? 5 : 2 }
    }

    var speed: Speed = Speed(rawValue: UserDefaults.standard.string(forKey: "speed") ?? "") ?? .max {
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
    /// Пропуски: номера у края ленты, которых в ленте нет, — обычно объявления на проверке
    /// (номер выдан при подаче, в ленту попадёт после проверки). Перепроверяем до 3 часов:
    /// модерация бывает и через час — объявление всё равно придёт, как только OLX его покажет.
    private var gaps: [Int: (added: Date, checked: Date)] = [:]
    private static let gapWindow = 200
    private static let gapsPerPass = 6
    private static let gapLife: TimeInterval = 3 * 3600

    /// Свежие пропуски — каждый проход, старше 10 минут — раз в 30 с, старше часа — раз в 2 мин.
    private static func gapDue(_ g: (added: Date, checked: Date), _ now: Date) -> Bool {
        let age = now.timeIntervalSince(g.added)
        let every: TimeInterval = age < 600 ? 0 : age < 3600 ? 30 : 120
        return now.timeIntervalSince(g.checked) >= every
    }
    private var seenSet = Set<Int>()
    @ObservationIgnored private var subSeenSet = Set<String>()
    @ObservationIgnored private var traceLog: [Int: [String]] = [:]
    @ObservationIgnored private var traceOrder: [Int] = []
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
                try? await Task.sleep(for: .milliseconds(500))
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
        let olxBlocked = siteBlocked(.olx)
        // Лента всей доски: при открытии — сразу, дальше раз в 1,5–5 с. Отсюда приходит большая
        // часть нового; турбо добирает номера за её краем и объявления на модерации; поиски —
        // то, что по признакам не подошло (рубрика ещё не выучена и т.п.).
        if !olxBlocked, Date().timeIntervalSince(lastAnchor) >= speed.board {
            lastAnchor = Date()
            await anchor()
        }
        // Поиски — по одному за проход (самый давно проверенный): лента и турбо не ждут, пока
        // пройдут все поиски подряд.
        let now = Date()
        let due = state.subs.filter { sub in
            !sub.paused && !siteBlocked(sub.site) && (sub.lastPoll.map { now.timeIntervalSince($0) >= speed.poll } ?? true)
        }
        if let next = due.min(by: { ($0.lastPoll ?? .distantPast) < ($1.lastPoll ?? .distantPast) }) {
            await poll(next.id)
        }
        if state.turbo, !siteBlocked(.olx), Date().timeIntervalSince(lastTurbo) >= speed.turbo {
            lastTurbo = Date()
            await turbo()
        }
        if !siteBlocked(.kaspi), Date().timeIntervalSince(lastShowcase) >= 3 {
            lastShowcase = Date()
            await kaspiShowcase()
        }
        if state.turbo, !siteBlocked(.kaspi), Date().timeIntervalSince(lastKaspiTurbo) >= 3 {
            lastKaspiTurbo = Date()
            await kaspiTurbo()
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
        let prevPoll = found.lastPoll
        var list: [Ad]
        do {
            list = try await OLX.search(url)
            ok()
            state.stats.searchOk += 1
        } catch {
            state.stats.searchErr += 1
            fail(error)
            updateSub(id) { $0.lastPoll = Date(); $0.error = error.localizedDescription }
            save()
            return
        }
        // Первый проход — 3 страницы: запоминаем, что уже есть, и учим рубрики и город поиска.
        // Потом — если вся первая страница новая для поиска (приложение было закрыто или рубрика
        // очень живая), дочитываем ещё до 2 страниц: уехавшее со страницы 1 не теряется.
        let firstPass = !found.ready
        let regular = list.filter { !$0.promoted }
        let allNew = regular.count >= 20 && !regular.contains(where: { subSeenSet.contains(Self.sk(id, $0.id)) })
        if firstPass || allNew {
            for page in 2...3 {
                guard let more = try? await OLX.search(url, page: page) else { break }
                let fresh = more.filter { a in !list.contains { $0.id == a.id } }
                if fresh.isEmpty { break }
                list += fresh
                if !firstPass, fresh.contains(where: { subSeenSet.contains(Self.sk(id, $0.id)) }) { break }
            }
        }
        for ad in list { bumpFrontier(ad.id) }
        guard let index = state.subs.firstIndex(where: { $0.id == id }) else { return }
        var sub = state.subs[index]
        sub.lastPoll = Date()
        sub.error = list.isEmpty ? "Поиск ничего не вернул" : ""
        learn(&sub, from: list.filter { !$0.promoted })

        if firstPass {
            for ad in list { markSub(id, ad.id) }
            sub.ready = true
            state.subs[index] = sub
            save()
            return
        }
        state.subs[index] = sub

        // Окно новизны: не меньше 30 минут, а если поиск не проверялся дольше (приложение было
        // закрыто) — всё время с прошлой проверки, иначе поданное за это время терялось бы.
        let window = prevPoll.map { min(24 * 3600, Date().timeIntervalSince($0) + 120) }
        for var ad in list where !subSeenSet.contains(Self.sk(id, ad.id)) {
            markSub(id, ad.id)
            if isStale(ad, frontier: frontierBefore, window: window) {
                trace(ad.id, "поиск «\(sub.name)»: подано давно — пропуск")
                continue
            }
            if let full = try? await OLX.offer(ad.id) { ad.merge(full) }
            if isStale(ad, frontier: frontierBefore, window: window) {
                trace(ad.id, "поиск «\(sub.name)»: подано давно — пропуск")
                continue
            }
            ad.via = "search"
            ad.foundAt = Date()
            if !seenSet.contains(ad.id) {
                remember(ad.id)
                recordAll(ad)
            }
            deliver(ad, to: [sub])
            trace(ad.id, "поиск «\(sub.name)»: пришло")
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
            ok(site: site)
            state.stats.searchOk += 1
        } catch {
            state.stats.searchErr += 1
            fail(error, site: site)
            updateSub(found.id) { $0.lastPoll = Date(); $0.error = error.localizedDescription }
            save()
            return
        }
        guard let index = state.subs.firstIndex(where: { $0.id == found.id }) else { return }
        var sub = state.subs[index]
        sub.lastPoll = Date()
        sub.error = ads.isEmpty ? "Поиск ничего не вернул — проверьте ссылку" : ""
        let top = ads.map(\.id).max() ?? 0
        if site == .kaspi, top > 0 { bumpKaspi(top - site.idOffset) }
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
        for var ad in ads.sorted(by: { $0.id < $1.id }) where (ad.anyOrder == true || ad.id > mark) && !seenSet.contains(ad.id) {
            remember(ad.id)
            if ad.seedOnly == true { continue }   // Kaspi: город впервые — только запоминаем
            if let full = try? await site.detail(ad) { ad.merge(full) }
            // Дата подачи есть не у всех карточек; есть и старше часа — это не новое.
            if let created = ad.createdAt, Date().timeIntervalSince(created) > TimeInterval(max(freshnessMinutes, 60) * 60) { continue }
            // Kaspi: платные (поднятые) стоят сверху и при «Самых новых» — это старьё.
            if site == .kaspi, kaspiOld(ad) { trace(ad.id, "Kaspi: платное / поднятое старое — пропуск"); continue }
            // Krisha «только от хозяев»: пропускаем только с подписью «Хозяин недвижимости».
            if site == .krisha, sub.url.range(of: #"das(%5B|\[)who(%5D|\])=1"#, options: [.regularExpression, .caseInsensitive]) != nil,
               ad.owner != true { continue }
            // Kolesa «только от хозяев»: отсеиваем автосалоны и дилеров.
            if site == .kolesa, sub.ownersOnly == true, ad.owner == false { continue }
            ad.source = site.rawValue
            ad.via = "search"
            ad.subIds = [sub.id]
            ad.foundAt = Date()
            recordAll(ad)
            deliver(ad, to: [sub])
        }
        save()
    }

    /// Старьё — поданное давно (поднятое, продвинутое). Окно: не меньше 30 минут для обычных
    /// объявлений (вышедшее с модерации позже соседей подано давно, но для всех оно новое) и не
    /// меньше времени с прошлой проверки (после паузы). Продвигаемые (Топ) — строго по настройке.
    /// Даты нет — по номеру: у поднятого старья он сильно меньше самых свежих.
    private func isStale(_ ad: Ad, frontier: Int, window: TimeInterval? = nil) -> Bool {
        let base = TimeInterval((ad.promoted ? freshnessMinutes : max(freshnessMinutes, 30)) * 60)
        let limit = ad.promoted ? base : max(base, window ?? 0)
        if let created = ad.createdAt { return Date().timeIntervalSince(created) > limit }
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
    /// на котором приложение закрыли. Каждое сверяем со всеми поисками — не подошло поиску
    /// сейчас, проверим снова на следующем проходе (и его сам поиск ещё может принести).
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
        let now = Date()
        let window = state.lastBoardOK.map { min(24 * 3600, now.timeIntervalSince($0) + 120) }
        state.lastBoardOK = now
        let onBoard = Set(ads.map(\.id))
        for id in max(1, top - Self.gapWindow)...top where !onBoard.contains(id) && !seenSet.contains(id) && gaps[id] == nil {
            gaps[id] = (now, .distantPast)
        }
        gaps = gaps.filter { now.timeIntervalSince($0.value.added) < Self.gapLife && !seenSet.contains($0.key) }
        if top > state.frontier + Self.turboWindow * 3 {
            state.frontier = top - Self.turboWindow   // прыжок; последние номера турбо ещё проверит
        }
        let ready = state.subs.filter { !$0.paused && $0.ready && $0.site == .olx }
        for var ad in ads.sorted(by: { $0.id < $1.id }) where !ad.promoted {
            // Был пропуском (на модерации) и только сейчас появился в ленте — новое, даже если подано час назад.
            let wasGap = gaps.removeValue(forKey: ad.id) != nil
            if isStale(ad, frontier: 0, window: wasGap ? max(window ?? 0, Self.gapLife) : window) { continue }
            ad.via = "search"
            ad.foundAt = now
            if !seenSet.contains(ad.id) {
                remember(ad.id)
                recordAll(ad)
                trace(ad.id, "лента: увидели\(ad.onReview ? " (на модерации)" : "")")
            }
            deliverMatching(ad, subs: ready, from: "лента")
        }
        publish()
    }

    /// Разослать объявление поискам, которым оно подходит и которым его ещё не присылали.
    /// Не подошло — не помечаем: подойдёт позже (поиск выучит рубрику) или его принесёт поиск.
    private func deliverMatching(_ ad: Ad, subs: [Sub], from source: String) {
        var hit: [Sub] = []
        for s in subs where !subSeenSet.contains(Self.sk(s.id, ad.id)) {
            if let reason = OLX.mismatch(s, ad) {
                trace(ad.id, "\(source) → «\(s.name)»: не подошло — \(reason)")
            } else {
                hit.append(s)
            }
        }
        guard !hit.isEmpty else { return }
        for s in hit { markSub(s.id, ad.id) }
        deliver(ad, to: hit)
        trace(ad.id, "\(source): пришло в «\(hit.map(\.name).joined(separator: "», «"))»")
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
        // И пропуски ниже края ленты (обычно — на модерации): давно не проверенные первыми.
        let now = Date()
        let gapIds = gaps.filter { Self.gapDue($0.value, now) }.sorted { $0.value.checked != $1.value.checked ? $0.value.checked < $1.value.checked : $0.key > $1.key }.prefix(Self.gapsPerPass).map { $0.key }
        for id in gapIds { gaps[id]?.checked = now }
        ids += gapIds.filter { !ids.contains($0) }
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
        // 403 на все номера прохода — это не скрытые объявления, а OLX закрыл доступ: пауза.
        let all403 = results.count >= 5 && results.allSatisfy {
            if case .failure(let e) = $0.1, let f = e as? OLX.Failure, case .blocked(403) = f { return true }
            return false
        }
        if all403, case .failure(let e) = results[0].1 {
            fail(e)
            return
        }
        var failed = false
        for (id, result) in results {
            let offer: Ad?
            switch result {
            case .success(let o):
                offer = o
                ok()
                state.stats.turboProbes += 1
            case .failure(let error):
                // 403 по одному номеру — не блокировка (лента и поиски при этом отвечают): так OLX,
                // похоже, отвечает на скрытые объявления — на модерации, удалённые. Паузу не
                // включаем, только считаем. Пауза — если OLX ограничил ленту или поиск (или 429).
                if let f = error as? OLX.Failure, case .blocked(403) = f {
                    state.stats.hiddenProbes = (state.stats.hiddenProbes ?? 0) + 1
                    misses[id, default: 0] += 1
                    trace(id, "по номеру: OLX ответил 403 — объявление скрыто")
                } else if !failed {
                    failed = true
                    fail(error)
                }
                continue
            }
            guard var ad = offer else { misses[id, default: 0] += 1; continue }
            misses[id] = nil
            let wasGap = gaps.removeValue(forKey: id) != nil
            bumpFrontier(id)
            state.stats.turboFound += 1
            state.stats.lastTurboHit = Date()
            if isStale(ad, frontier: 0, window: wasGap ? Self.gapLife : nil) {
                remember(id)
                trace(id, "по номеру: подано давно — пропуск")
                continue
            }
            ad.via = "turbo"
            ad.foundAt = Date()
            if !seenSet.contains(id) {
                remember(id)
                recordAll(ad)                 // «Все новые» — любое пойманное объявление
                trace(id, "по номеру: нашли\(ad.onReview ? " — на модерации" : "")")
            }
            deliverMatching(ad, subs: ready, from: "по номеру")
        }
        misses = misses.filter { $0.key > state.frontier - 500 }
        save()
    }

    // MARK: — найденное

    /// В «По запросам» и уведомление. Уже есть (другой поиск прислал) — только добавляем поиск,
    /// второго уведомления нет.
    private func deliver(_ ad: Ad, to subs: [Sub]) {
        if let i = state.ads.firstIndex(where: { $0.id == ad.id }) {
            let newIds = subs.map(\.id).filter { !state.ads[i].subIds.contains($0) }
            guard !newIds.isEmpty else { return }
            state.ads[i].subIds += newIds
            for sid in newIds { updateSub(sid) { $0.sent += 1 } }
            return
        }
        var item = ad
        item.subIds = subs.map(\.id)
        state.ads.insert(item, at: 0)
        if state.ads.count > 500 { state.ads.removeLast(state.ads.count - 500) }
        for s in subs { updateSub(s.id) { $0.sent += 1 } }
        notify(item, subs: subs)
    }

    // MARK: — что какому поиску решено, и «почему не пришло»

    private static func sk(_ subId: Int, _ adId: Int) -> String { "\(subId):\(adId)" }

    private func markSub(_ subId: Int, _ adId: Int) {
        let k = Self.sk(subId, adId)
        guard subSeenSet.insert(k).inserted else { return }
        if state.subSeen == nil { state.subSeen = [] }
        state.subSeen?.append(k)
        if let c = state.subSeen?.count, c > 32_000 {
            let drop = Array(state.subSeen!.prefix(c - 30_000))
            drop.forEach { subSeenSet.remove($0) }
            state.subSeen!.removeFirst(drop.count)
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Короткая история по номеру: где видели, кому подошло, почему нет. Последние 4000 номеров.
    private func trace(_ id: Int, _ line: String) {
        var lines = traceLog[id] ?? []
        if lines.last?.hasSuffix(line) == true { return }
        if traceLog[id] == nil {
            traceOrder.append(id)
            if traceOrder.count > 4_000 { traceLog[traceOrder.removeFirst()] = nil }
        }
        lines.append("\(Self.clock.string(from: Date())) \(line)")
        if lines.count > 8 { lines.removeFirst(lines.count - 8) }
        traceLog[id] = lines
    }

    /// «Почему не пришло?» — по номеру объявления.
    func why(_ id: Int) -> String {
        var out: [String] = []
        if let ad = state.ads.first(where: { $0.id == id }) {
            let names = state.subs.filter { ad.subIds.contains($0.id) }.map(\.name)
            out.append("✅ Пришло в «По запросам»\(names.isEmpty ? "" : ": «" + names.joined(separator: "», «") + "»").")
        } else if (state.all ?? []).contains(where: { $0.id == id }) {
            out.append("Есть во «Все новые», но ни к одному поиску не подошло.")
        }
        if let lines = traceLog[id] { out += lines }
        if let g = gaps[id] {
            out.append("Сейчас в очереди перепроверки с \(Self.clock.string(from: g.added)) — его нет в ленте OLX (обычно это модерация).")
        }
        if let m = misses[id] { out.append("По номеру OLX ответил «нет такого» \(m) раз.") }
        if out.isEmpty {
            if seenSet.contains(id) {
                out.append("Номер видели, но подробностей уже нет (давно или до перезапуска приложения).")
            } else if id > state.frontier {
                out.append("До этого номера приложение ещё не дошло — он новее последнего известного (\(state.frontier)).")
            } else {
                out.append("Приложение этот номер не видело: ни в ленте, ни в поисках, ни по номеру. Так бывает, если объявление было на модерации и OLX по номеру его не отдавал, или приложение было закрыто.")
            }
        }
        return out.joined(separator: "\n")
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

    /// Пауза Kolesa / Krisha / Kaspi — своя: OLX ограничил — остальные работают, и их удачный
    /// ответ не сбрасывает паузу OLX (и наоборот).
    // Турбо Kaspi: номера объявлений сквозные; граница — самый большой номер из выдачи Kaspi.
    @ObservationIgnored private var kaspiFrontier = UserDefaults.standard.integer(forKey: "kaspi_frontier")
    @ObservationIgnored private var kaspiMisses: [Int: Int] = [:]
    @ObservationIgnored private var kaspiJump = 0
    @ObservationIgnored private var lastKaspiTurbo = Date.distantPast

    private func bumpKaspi(_ n: Int) {
        guard n > kaspiFrontier else { return }
        kaspiFrontier = n
        UserDefaults.standard.set(n, forKey: "kaspi_frontier")
    }

    /// Следующие 3 номера за границей и один подальше (+5…+20 по кругу — чтобы снятые номера не
    /// держали на месте), плюс недавние промахи. Подошло поиску по рубрике, городу, словам — сразу.
    // Витрина Kaspi — как лента всей доски у OLX: главная Kaspi и главная одного города по кругу.
    @ObservationIgnored private var showPages: [String] = Site.kaspiCitySlugs
    @ObservationIgnored private var showNext = 0
    @ObservationIgnored private var showRootDead = false
    @ObservationIgnored private var showSeeded = Set<String>()
    @ObservationIgnored private var showSeen = Set<Int>()
    @ObservationIgnored private var lastShowcase = Date.distantPast

    /// Что было на витрине при запуске — только запоминаем; появившееся потом — открываем карточку
    /// и сверяем со всеми поисками Kaspi. Самый большой номер витрины — край для турбо Kaspi.
    private func kaspiShowcase() async {
        let subs = state.subs.filter { !$0.paused && $0.ready && $0.site == .kaspi }
        guard !subs.isEmpty else { return }
        var pages: [String] = showRootDead ? [] : [""]
        if !showPages.isEmpty { pages.append(showPages[showNext % showPages.count]) }
        showNext += 1
        for page in pages {
            let found: [Ad]?
            do {
                found = try await Site.kaspiShowcase(city: page)
                ok(site: .kaspi)
            } catch {
                fail(error, site: .kaspi)
                if siteBlocked(.kaspi) { break }
                continue
            }
            guard let ads = found else {
                if page.isEmpty { showRootDead = true } else { showPages.removeAll { $0 == page } }
                continue
            }
            if let top = ads.map(\.id).max() { bumpKaspi(top - Site.kaspi.idOffset) }
            let seed = !showSeeded.contains(page)
            showSeeded.insert(page)
            for a in ads where !showSeen.contains(a.id) {
                showSeen.insert(a.id)
                if seed || seenSet.contains(a.id) { continue }
                var ad = a
                if let full = try? await Site.kaspi.detail(a) { ad.merge(full) }
                // Поднятое / платное старое тоже всплывает наверх витрины.
                if kaspiOld(ad) { trace(ad.id, "витрина Kaspi: поднятое старое — пропуск"); continue }
                var hit: [Sub] = []
                for s in subs {
                    if let why = Site.kaspiMismatch(s, ad) {
                        trace(ad.id, "витрина Kaspi → «\(s.name)»: не подошло — \(why)")
                    } else {
                        hit.append(s)
                    }
                }
                guard !hit.isEmpty else { continue }
                remember(ad.id)
                ad.via = "search"
                ad.foundAt = Date()
                recordAll(ad)
                deliver(ad, to: hit)
                trace(ad.id, "витрина Kaspi: пришло в «\(hit.map(\.name).joined(separator: "», «"))»")
            }
        }
        if showSeen.count > 20_000, let top = showSeen.max() { showSeen = showSeen.filter { $0 > top - 100_000 } }
        save()
    }

    /// Kaspi: старьё — подано больше 3 ч назад (точное время из dateCreate), а без даты — номер
    /// сильно ниже самого нового известного (запас — на вышедшие с модерации позже соседей).
    private func kaspiOld(_ ad: Ad) -> Bool {
        if let created = ad.createdAt { return Date().timeIntervalSince(created) > 3 * 3600 }
        return kaspiFrontier > 0 && ad.id - Site.kaspi.idOffset < kaspiFrontier - 500
    }

    @ObservationIgnored private var kaspiSynced = false
    @ObservationIgnored private var kaspiStep = 16
    @ObservationIgnored private var kaspiHi = 0
    @ObservationIgnored private var kaspiLastTick = Date.distantPast

    /// Номер n или сразу за ним (снятые дают дырки по 1–2): первый существующий или 0.
    private func kaspiExists(_ n: Int) async throws -> Int {
        for id in n...(n + 2) {
            if try await Site.kaspiById(id) != nil { return id }
        }
        return 0
    }

    /// Сначала — найти самый последний номер Kaspi: граница из выдачи может отставать на тысячи,
    /// и турбо слало бы подряд всё старое. Пока ищем — ничего не шлём: шаг вперёд удваиваем,
    /// где объявлений уже нет — делим пополам.
    private func kaspiSync() async throws {
        var lo = kaspiFrontier
        for _ in 0..<4 {
            if kaspiHi == 0 {
                var hit = try await kaspiExists(lo + kaspiStep)
                if hit == 0 { hit = try await kaspiExists(lo + kaspiStep * 4) }   // дырка — смотрим дальше
                if hit > 0 { lo = hit; kaspiStep = min(kaspiStep * 2, 20_000); continue }
                kaspiHi = lo + kaspiStep
            }
            if kaspiHi - lo <= 3 {
                for id in (lo + 1)...(kaspiHi + 3) {
                    if try await Site.kaspiById(id) != nil { lo = id }
                }
                kaspiSynced = true
                kaspiHi = 0
                kaspiStep = 16
                break
            }
            let mid = (lo + kaspiHi) / 2
            let hit = try await kaspiExists(mid)
            if hit > 0 { lo = hit } else { kaspiHi = mid }
        }
        kaspiFrontier = lo
        UserDefaults.standard.set(lo, forKey: "kaspi_frontier")
    }

    private func kaspiTurbo() async {
        let subs = state.subs.filter { !$0.paused && $0.ready && $0.site == .kaspi }
        guard !subs.isEmpty, kaspiFrontier > 0 else { return }
        // Приложение было закрыто дольше 5 минут — край ищем заново (пропущенное принесёт выдача).
        if Date().timeIntervalSince(kaspiLastTick) > 300 { kaspiSynced = false }
        kaspiLastTick = Date()
        if !kaspiSynced {
            do { try await kaspiSync(); ok(site: .kaspi) } catch { fail(error, site: .kaspi) }
            return
        }
        var ids = (1...3).map { kaspiFrontier + $0 }
        kaspiJump = kaspiJump % 16 + 1
        ids.append(kaspiFrontier + 4 + kaspiJump)
        for (n, c) in kaspiMisses where n < kaspiFrontier && n > kaspiFrontier - 50 && c < 30 && ids.count < 5 { ids.append(n) }
        for n in ids {
            let found: Ad?
            do {
                found = try await Site.kaspiById(n)
                ok(site: .kaspi)
            } catch {
                fail(error, site: .kaspi)
                if siteBlocked(.kaspi) { break }
                continue
            }
            guard var ad = found else { kaspiMisses[n, default: 0] += 1; continue }
            kaspiMisses[n] = nil
            bumpKaspi(n)
            guard !seenSet.contains(ad.id) else { continue }
            var hit: [Sub] = []
            for s in subs {
                if let why = Site.kaspiMismatch(s, ad) {
                    trace(ad.id, "Kaspi по номеру → «\(s.name)»: не подошло — \(why)")
                } else {
                    hit.append(s)
                }
            }
            guard !hit.isEmpty else { continue }   // не понятно — его принесёт обход выдачи
            remember(ad.id)
            ad.via = "turbo"
            ad.foundAt = Date()
            recordAll(ad)
            deliver(ad, to: hit)
            trace(ad.id, "Kaspi по номеру: пришло в «\(hit.map(\.name).joined(separator: "», «"))»")
        }
        kaspiMisses = kaspiMisses.filter { $0.key > kaspiFrontier - 200 }
        save()
    }

    @ObservationIgnored private var siteBlock: [Site: (until: Date, backoff: TimeInterval)] = [:]

    private func siteBlocked(_ site: Site) -> Bool {
        if site == .olx { return blockedUntil.map { $0 > Date() } ?? false }
        return (siteBlock[site]?.until ?? .distantPast) > Date()
    }

    private func fail(_ error: Error, site: Site = .olx) {
        if site != .olx {
            if Self.isBlocked(error) {
                let b = min(900, max(60, (siteBlock[site]?.backoff ?? 0) * 2))
                siteBlock[site] = (Date().addingTimeInterval(b), b)
            }
            self.error = "\(site.title): \(error.localizedDescription)"
            return
        }
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

    private func ok(site: Site = .olx) {
        if site != .olx { siteBlock[site] = nil; return }
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

    func addSub(url: String, name: String, categoryLabel: String? = nil, ownersOnly: Bool = false) async -> Bool {
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
        if site == .kolesa, ownersOnly { sub.ownersOnly = true }
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
        let parts = path.split(separator: "/").map(String.init).filter { !["d", "kk", "ru", "rus", "list"].contains($0) }
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
        subSeenSet = Set(saved.subSeen ?? [])
        // Обновились с версии без «что какому поиску решено»: уже присланное — помечаем.
        if saved.subSeen == nil {
            for ad in saved.ads { for sid in ad.subIds { markSub(sid, ad.id) } }
        }
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
