import Foundation
import BackgroundTasks
import UserNotifications

/**
 ФОНОВАЯ ПРОВЕРКА СОХРАНЁННЫХ ПОИСКОВ — ЭТАП 12 (владелец 25.09.2026: «давай следующие этапы»).

 Задание BGAppRefreshTask «kz.kliko.app.saved-search»: регистрируется в AppDelegate до конца запуска, ставится в
 расписание при уходе в фон (SceneDelegate) и заново при каждом запуске — не раньше чем через час. Когда именно
 приложение проснётся, решает iOS: по заряду, сети и тому, как часто человек его открывает. Обещать «каждый час»
 нельзя, поэтому и в кабинете написано «не чаще раза в час».

 Проверка берёт первую страницу той же GET /api/listings.php (q=, cat=, per=24) по каждому поиску, сравнивает номера
 с теми, что поиск уже видел (SavedSearchStore.отметитьПроверку), и присылает ОДНО локальное уведомление на все
 поиски — только если уведомления разрешены. Нажатие ведёт через роутер ссылок этапа 8 в ленту с этим поиском.
 Новых адресов на сайте нет.

 🔴 «НОВОЕ» — ЗНАЧИТ НЕ ВИДЕННОЕ ЭТИМ ПОИСКОМ, А НЕ ТОЛЬКО ЧТО ПОДАННОЕ. Лента API сортирована «рекомендациями»
 (sort=reco — другой сортировки приложение не знает), и первая страница между проверками перетасовывается. Поэтому
 помним до 200 номеров на поиск, а не одну страницу: старое, вернувшееся наверх, новым не считается.

 🔴 КУКИ ВЕБ-СЕССИИ — ИЗ WEBKIT, С ПРЕДЕЛОМ ПО ВРЕМЕНИ. Город и вход живут в куках (ListingsAPI), а хранилище WebKit
 в фоне может не ответить вовсе: приложение поднято системой, страницы может не быть. Ждём его не дольше 5 с; не
 дождались — идём без куков, и тогда выдача — лента сайта по умолчанию (город из сессии в неё не попадёт).
 */
enum ПроверкаПоисков {
    static let идентификатор = "kz.kliko.app.saved-search"
    /// Не раньше чем через столько после ухода в фон или прошлой проверки.
    static let интервал: TimeInterval = 60 * 60
    /// Метка своего уведомления в userInfo: по ней AppDelegate отличает его от пушей сайта, которые ведут по "url".
    static let метка = "kliko_local"
    static let меткаПоиска = "saved_search"
    /// Одно уведомление на все поиски: новое заменяет прежнее, а не копится стопкой в Центре уведомлений.
    static let номерУведомления = "kz.kliko.app.saved-search.news"
    /// Запросов к ленте разом: двадцать поисков — не двадцать одновременных соединений.
    private static let одновременно = 4
    /// Сколько ждать куки у WebKit, секунд.
    private static let ждатьКуки: UInt64 = 5

    // MARK: - Расписание

    /**
     Обработчик задания — строго до конца запуска (AppDelegate, didFinishLaunching): iOS требует его для каждого
     идентификатора из BGTaskSchedulerPermittedIdentifiers (project.yml), иначе фоновый запуск роняет приложение.
     Регистрируем и при выключенном рубильнике: задание, поставленное прежней сборкой, всё равно придёт — тогда просто
     закрываем его, а расписание снимаем сразу.
     */
    static func зарегистрировать() {
        _ = BGTaskScheduler.shared.register(forTaskWithIdentifier: идентификатор, using: nil) { задание in
            guard Config.сохранённыеПоиски, let обновление = задание as? BGAppRefreshTask else {
                задание.setTaskCompleted(success: true)
                return
            }
            ПроверкаПоисков.выполнить(обновление)
        }
        if !Config.сохранённыеПоиски {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: идентификатор)
        }
    }

    /// Следующая проверка — не раньше чем через час. Та же заявка заменяет прежнюю. Сохранённых поисков нет или
    /// рубильник выключен — расписание снимаем: будить приложение незачем.
    @MainActor
    static func запланировать() {
        guard Config.сохранённыеПоиски, !SavedSearchStore.shared.поиски.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: идентификатор)
            return
        }
        let заявка = BGAppRefreshTaskRequest(identifier: идентификатор)
        заявка.earliestBeginDate = Date(timeIntervalSinceNow: интервал)
        do {
            try BGTaskScheduler.shared.submit(заявка)
        } catch {
            // Симулятор, выключенное «Обновление контента» или лимит заявок — проверки просто не будет; кабинет
            // об «Обновлении контента» предупреждает сам.
        }
    }

    /// Выход из аккаунта (SavedSearchStore.стереть): ни расписания, ни уведомления о поисках ушедшего.
    static func отменить() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: идентификатор)
        let центр = UNUserNotificationCenter.current()
        центр.removePendingNotificationRequests(withIdentifiers: [номерУведомления])
        центр.removeDeliveredNotifications(withIdentifiers: [номерУведомления])
    }

    /// Первое сохранение — спросить разрешение на уведомления, если человек ещё не отвечал: без него проверка молчит.
    static func попроситьРазрешение() async {
        guard await ДанныеТелефона.статусУведомлений() == .notDetermined else { return }
        await ДанныеТелефона.попроситьУведомления()
    }

    // MARK: - Задание

    /**
     Один фоновый запуск. Следующий ставим сразу, до работы: время может кончиться раньше, чем она закончится, — и
     ещё раз после, чтобы час считался от конца проверки. Время вышло (expirationHandler) — отменяем работу и
     закрываем задание неудачей; закрыть его ровно один раз помогает РазовоеЗавершение.
     */
    private static func выполнить(_ задание: BGAppRefreshTask) {
        let итог = РазовоеЗавершение(задание)
        let работа = Task { @MainActor in
            ПроверкаПоисков.запланировать()
            let успех = await ПроверкаПоисков.проверить()
            ПроверкаПоисков.запланировать()
            итог.завершить(успех)
        }
        задание.expirationHandler = {
            работа.cancel()
            итог.завершить(false)
        }
    }

    /// Одна проверка. true — отработала, даже если нового нет; false — сеть подвела во всех поисках или время вышло.
    @MainActor
    static func проверить() async -> Bool {
        let снимок = SavedSearchStore.shared.поиски
        guard Config.сохранённыеПоиски, !снимок.isEmpty else { return true }
        /* Уведомления запрещены — сообщить некому: сеть и батарею не тратим. Номера не трогаем, и после разрешения
           первая проверка расскажет обо всём, что появилось с прошлой (в пределах первой страницы). */
        guard await уведомленияРазрешены() else { return true }

        let куки = await кукиНеДольше(ждатьКуки)
        let выдачи = await загрузитьВсе(снимок, куки: куки)
        /* Время вышло — номера не отмечаем: иначе новые, о которых так и не сказали, стали бы виденными. */
        guard !Task.isCancelled, !выдачи.isEmpty else { return false }

        let новых = SavedSearchStore.shared.отметитьПроверку(выдачи)
        await СохранённыеПоискиФайл.дождаться()
        /* Поиски, которые ещё в списке (удалённый за время проверки — уже нет), где новых больше, — первыми. */
        let сНовыми = SavedSearchStore.shared.поиски
            .compactMap { п -> (СохранённыйПоиск, Int)? in
                guard let сколько = новых[п.id], сколько > 0 else { return nil }
                return (п, сколько)
            }
            .sorted { $0.1 > $1.1 }
        guard !сНовыми.isEmpty, !Task.isCancelled else { return true }
        await уведомить(сНовыми)
        return true
    }

    // MARK: - Запросы

    /// Первая страница каждого поиска, не больше четырёх запросов разом. Ответ — номера объявлений по номеру поиска;
    /// поиск, чей запрос не прошёл, в ответ не попадает, и его номера остаются прежними.
    private static func загрузитьВсе(_ список: [СохранённыйПоиск], куки: [String: String]) async -> [String: [String]] {
        await withTaskGroup(of: ОтветПроверки.self, returning: [String: [String]].self) { группа in
            var итог: [String: [String]] = [:]
            var следующий = 0
            let разом = min(одновременно, список.count)
            while следующий < разом {
                let поиск = список[следующий]
                группа.addTask { await ПроверкаПоисков.первая(поиск, куки: куки) }
                следующий += 1
            }
            while let ответ = await группа.next() {
                if let номера = ответ.номера { итог[ответ.id] = номера }
                if следующий < список.count && !Task.isCancelled {
                    let поиск = список[следующий]
                    группа.addTask { await ПроверкаПоисков.первая(поиск, куки: куки) }
                    следующий += 1
                }
            }
            return итог
        }
    }

    /// Первая страница выдачи одного поиска — тот же запрос, что у ленты (ListingsAPI), с куками, взятыми заранее.
    private static func первая(_ поиск: СохранённыйПоиск, куки: [String: String]) async -> ОтветПроверки {
        var з = ListingsAPI.Запрос()
        з.q = поиск.искомое.текст
        з.cat = поиск.искомое.раздел
        do {
            let ответ = try await ListingsAPI.загрузить(з, куки: куки)
            return ОтветПроверки(id: поиск.id, номера: ответ.страница.items.map(\.id))
        } catch {
            return ОтветПроверки(id: поиск.id, номера: nil)
        }
    }

    /// Куки веб-сессии у WebKit (SiteSession.куки, главная нить) — не дольше `секунд`; не дождались — пусто, и
    /// запросы идут без куков (см. шапку файла). Кто ответил первым, тот и отдаёт: РазовыйОтвет не даст ответить дважды.
    private static func кукиНеДольше(_ секунд: UInt64) async -> [String: String] {
        await withCheckedContinuation { (продолжение: CheckedContinuation<[String: String], Never>) in
            let ответ = РазовыйОтвет(продолжение)
            Task { @MainActor in
                let куки = await SiteSession.куки()
                ответ.отдать(куки)
            }
            Task {
                try? await Task.sleep(nanoseconds: секунд * 1_000_000_000)
                ответ.отдать([:])
            }
        }
    }

    // MARK: - Уведомление

    private static func уведомленияРазрешены() async -> Bool {
        switch await ДанныеТелефона.статусУведомлений() {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined:               return false
        @unknown default:                           return false
        }
    }

    /// Одно уведомление на все поиски: заголовок — поиск, где новых больше, в тексте — сколько, и ещё до трёх
    /// поисков с числами. Нажатие открывает первый.
    @MainActor
    private static func уведомить(_ сНовыми: [(СохранённыйПоиск, Int)]) async {
        guard let первый = сНовыми.first else { return }
        let главный = первый.0
        let содержимое = UNMutableNotificationContent()
        содержимое.title = String(format: SavedSearchText.т("notif_title"), главный.название)
        var текст = String(format: SavedSearchText.т("notif_count"), первый.1)
        let прочие = сНовыми.dropFirst().prefix(3).map { пара in
            String(format: SavedSearchText.т("notif_item"), пара.0.название, пара.1)
        }
        if !прочие.isEmpty {
            var список = прочие.joined(separator: ", ")
            if сНовыми.count > 4 { список += ", …" }
            текст += "\n" + String(format: SavedSearchText.т("notif_more"), список)
        }
        содержимое.body = текст
        содержимое.sound = .default
        содержимое.threadIdentifier = идентификатор
        содержимое.userInfo = [метка: меткаПоиска, "q": главный.искомое.текст, "cat": главный.искомое.раздел]
        let запрос = UNNotificationRequest(identifier: номерУведомления, content: содержимое, trigger: nil)
        await withCheckedContinuation { (готово: CheckedContinuation<Void, Never>) in
            UNUserNotificationCenter.current().add(запрос) { _ in готово.resume() }
        }
    }

    // MARK: - Нажатие

    /// Нажатие на уведомление (AppDelegate): поиск, о котором оно. nil — уведомление не наше, а пуш сайта.
    static func искомое(из info: [AnyHashable: Any]) -> ИскомоеЛенты? {
        guard (info[метка] as? String) == меткаПоиска else { return nil }
        let текст = String(((info["q"] as? String) ?? "").prefix(200))
        let раздел = String(((info["cat"] as? String) ?? "").prefix(60))
        return ИскомоеЛенты(текст: текст, раздел: раздел)
    }

    /// Лента с этим поиском — через роутер ссылок этапа 8, как быстрое действие «Поиск». Вкладок нет (лента сайта
    /// вместо нашей) — главная сайта с её поиском, адреса поиска на сайте приложение не знает.
    @MainActor
    static func открыть(_ искомое: ИскомоеЛенты) {
        WebBridge.shared.открытьЭкран(.найти(искомое), запасной: Config.apiBase)
    }
}

/// Ответ проверки одного поиска: номера первой страницы; nil — запрос не прошёл.
private struct ОтветПроверки: Sendable {
    let id: String
    let номера: [String]?
}

/// Закрыть фоновое задание ровно один раз: работа и expirationHandler приходят с разных нитей и могут столкнуться.
private final class РазовоеЗавершение: @unchecked Sendable {
    private let защёлка = NSLock()
    private var закрыто = false
    private let задание: BGTask

    init(_ задание: BGTask) {
        self.задание = задание
    }

    func завершить(_ успех: Bool) {
        защёлка.lock()
        let первый = !закрыто
        закрыто = true
        защёлка.unlock()
        if первый { задание.setTaskCompleted(success: успех) }
    }
}

/// Ответить ожидающему ровно один раз — кто первым: WebKit с куками или таймер с пустыми.
private final class РазовыйОтвет: @unchecked Sendable {
    private let защёлка = NSLock()
    private var продолжение: CheckedContinuation<[String: String], Never>?

    init(_ продолжение: CheckedContinuation<[String: String], Never>) {
        self.продолжение = продолжение
    }

    func отдать(_ куки: [String: String]) {
        защёлка.lock()
        let ждущее = продолжение
        продолжение = nil
        защёлка.unlock()
        ждущее?.resume(returning: куки)
    }
}
