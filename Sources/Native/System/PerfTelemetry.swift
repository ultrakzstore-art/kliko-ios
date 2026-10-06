import Foundation
import UIKit
import MetricKit
import Network
import CoreTelephony

/**
 ЗАМЕРЫ СКОРОСТИ (владелец 06.10.2026: «знать, кто где — у кого тормозит»).

 ЧТО СОБИРАЕТСЯ — только скорость и сбои, без персональных данных:
 • MetricKit раз в сутки (MXMetricPayload): время до первого кадра при запуске и при возврате, зависания (hang),
   рывки прокрутки (scrollHitchTimeRatio), пик памяти, время на экране и процессора, сколько раз система закрыла
   приложение (память, сторож, сбой). Сбои (MXDiagnosticPayload): число падений, зависаний, перегрузок процессора и
   диска; у первого падения — тип исключения, сигнал и причина завершения (текст системы).
 • Свои замеры: холодный запуск до первой ленты (cold_feed) и до ухода заставки (cold_splash), первая страница выдачи
   (feed_page), следующие страницы (feed_more), ошибка ленты (feed_err), открытие объявления (listing_open).
 • У каждого замера: тип сети (NWPathMonitor: wifi, cell-4g/5g/3g, +exp — дорогая, +low — экономия трафика), лёгкий
   режим и почему (DeviceMode.swift), город, ВЫБРАННЫЙ в шапке (не координаты), время с точностью до минуты.
 • У пачки: случайный номер установки (UUID, только для этих замеров — не связан с аккаунтом, телефоном и рекламой),
   модель (utsname.machine, «iPhone11,8»), память в ГБ, версия iOS, версия и сборка приложения.

 КАК УХОДИТ. POST JSON на api/app_perf.php без куков — при уходе в фон (не чаще раза в час) и при запуске, если с
 прошлой отправки прошли сутки. До 200 замеров за раз, очередь на телефоне — не больше 400, одного вида — не больше
 60 в сутки. Рубильник — Config.телеметрияСкорости (ключ perf_telemetry в админке): выключен — не копится и не уходит.
 */
struct ЗамерСкорости: Codable, Sendable {
    /// Вид замера: cold_feed, feed_page, listing_open, mx_day, mx_diag…
    var k: String
    /// Главное значение, мс.
    var ms: Int?
    /// Прочие числа.
    var n: [String: Double]?
    /// Прочие строки.
    var s: [String: String]?
    var net: String = ""
    var lite: String = ""
    var city: String = ""
    /// Unix-время с точностью до минуты.
    var t: Int = 0
}

/// Тип сети сейчас: NWPathMonitor на своей очереди, читается из любого потока под замком.
final class СетьДляЗамеров: @unchecked Sendable {
    static let shared = СетьДляЗамеров()

    private let замок = NSLock()
    private var тип = "unknown"
    private var запущен = false
    private let монитор = NWPathMonitor()
    private let очередьМонитора = DispatchQueue(label: "kz.kliko.perf.net", qos: .utility)
    private let телефония = CTTelephonyNetworkInfo()

    private init() {}

    func запустить() {
        замок.lock()
        let уже = запущен
        запущен = true
        замок.unlock()
        guard !уже else { return }
        монитор.pathUpdateHandler = { [weak self] путь in self?.обновить(путь) }
        монитор.start(queue: очередьМонитора)
    }

    var сейчас: String {
        замок.lock()
        defer { замок.unlock() }
        return тип
    }

    private func обновить(_ путь: NWPath) {
        var т: String
        if путь.status != .satisfied {
            т = "none"
        } else if путь.usesInterfaceType(.wifi) {
            т = "wifi"
        } else if путь.usesInterfaceType(.cellular) {
            т = "cell" + поколение()
        } else if путь.usesInterfaceType(.wiredEthernet) {
            т = "wired"
        } else {
            т = "other"
        }
        if путь.isExpensive && !т.hasPrefix("cell") { т += "+exp" }      // Wi-Fi от телефона (режим модема)
        if путь.isConstrained { т += "+low" }                            // «Экономия данных»
        замок.lock()
        тип = т
        замок.unlock()
    }

    /// Поколение мобильной сети по SIM, через которую идут данные.
    private func поколение() -> String {
        let все = телефония.serviceCurrentRadioAccessTechnology ?? [:]
        let своя = телефония.dataServiceIdentifier.flatMap { все[$0] } ?? все.values.first
        guard let техника = своя else { return "" }
        switch техника {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: return "-5g"
        case CTRadioAccessTechnologyLTE: return "-4g"
        case CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyGPRS: return "-2g"
        default: return "-3g"
        }
    }
}

/// Подписчик MetricKit: отчёты приходят раз в сутки на фоновой очереди — разбираем там же, складываем на главной.
final class ПодписчикMetricKit: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        let замеры = payloads.map { Self.замер($0) }
        Task { @MainActor in ЗамерыСкорости.добавить(замеры, сразуНаДиск: true) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let замеры = payloads.map { Self.замер($0) }
        Task { @MainActor in ЗамерыСкорости.добавить(замеры, сразуНаДиск: true) }
    }

    private static func замер(_ п: MXMetricPayload) -> ЗамерСкорости {
        var n: [String: Double] = [:]
        if let запуск = п.applicationLaunchMetrics {
            if let г = гистограмма(запуск.histogrammedTimeToFirstDraw) {
                n["launch_ms"] = г.медиана
                n["launch_p90"] = г.п90
                n["launches"] = Double(г.всего)
            }
            if let г = гистограмма(запуск.histogrammedApplicationResumeTime) {
                n["resume_ms"] = г.медиана
                n["resume_p90"] = г.п90
            }
        }
        if let отклик = п.applicationResponsivenessMetrics,
           let г = гистограмма(отклик.histogrammedApplicationHangTime) {
            n["hang_ms"] = г.медиана
            n["hang_p90"] = г.п90
            n["hangs"] = Double(г.всего)
        }
        if let анимация = п.animationMetrics {
            n["hitch"] = анимация.scrollHitchTimeRatio.value          // мс рывков на секунду прокрутки
        }
        if let память = п.memoryMetrics {
            n["mem_peak_mb"] = память.peakMemoryUsage.converted(to: .megabytes).value.rounded()
        }
        if let время = п.applicationTimeMetrics {
            n["fg_s"] = время.cumulativeForegroundTime.converted(to: .seconds).value.rounded()
        }
        if let цп = п.cpuMetrics {
            n["cpu_s"] = цп.cumulativeCPUTime.converted(to: .seconds).value.rounded()
        }
        if let выходы = п.applicationExitMetrics {
            let наЭкране = выходы.foregroundExitData
            n["exit_mem"] = Double(наЭкране.cumulativeMemoryResourceLimitExitCount)
            n["exit_watchdog"] = Double(наЭкране.cumulativeAppWatchdogExitCount)
            n["exit_abnormal"] = Double(наЭкране.cumulativeAbnormalExitCount)
            n["exit_badaccess"] = Double(наЭкране.cumulativeBadAccessExitCount)
            n["bg_exit_mem"] = Double(выходы.backgroundExitData.cumulativeMemoryPressureExitCount)
        }
        var s: [String: String] = ["ver": String(п.latestApplicationVersion.prefix(20))]
        if let мета = п.metaData { s["os"] = String(мета.osVersion.prefix(40)) }
        return ЗамерСкорости(k: "mx_day", ms: n["launch_ms"].map { Int($0) }, n: n, s: s, net: "-",
                             t: Int(п.timeStampBegin.timeIntervalSince1970 / 60) * 60)
    }

    private static func замер(_ п: MXDiagnosticPayload) -> ЗамерСкорости {
        var n: [String: Double] = [:]
        var s: [String: String] = [:]
        let падения = п.crashDiagnostics ?? []
        n["crash"] = Double(падения.count)
        if let первое = падения.first {
            if let тип = первое.exceptionType { s["exc"] = тип.stringValue }
            if let сигнал = первое.signal { s["sig"] = сигнал.stringValue }
            if let причина = первое.terminationReason { s["why"] = String(причина.prefix(160)) }
            s["ver"] = String(первое.metaData.applicationBuildVersion.prefix(20))
            s["os"] = String(первое.metaData.osVersion.prefix(40))
        }
        let зависания = п.hangDiagnostics ?? []
        n["hang"] = Double(зависания.count)
        if let дольше = зависания.map({ $0.hangDuration.converted(to: .milliseconds).value }).max() {
            n["hang_max_ms"] = дольше.rounded()
        }
        n["cpu_exc"] = Double(п.cpuExceptionDiagnostics?.count ?? 0)
        n["disk_exc"] = Double(п.diskWriteExceptionDiagnostics?.count ?? 0)
        n["launch_slow"] = Double(п.appLaunchDiagnostics?.count ?? 0)
        return ЗамерСкорости(k: "mx_diag", ms: nil, n: n, s: s, net: "-",
                             t: Int(п.timeStampBegin.timeIntervalSince1970 / 60) * 60)
    }

    /// Медиана, 90-й перцентиль (по серединам корзин, мс) и число случаев. Пустая гистограмма — nil.
    private static func гистограмма(_ г: MXHistogram<UnitDuration>) -> (медиана: Double, п90: Double, всего: Int)? {
        var корзины: [(середина: Double, сколько: Int)] = []
        for case let корзина as MXHistogramBucket<UnitDuration> in г.bucketEnumerator {
            let от = корзина.bucketStart.converted(to: .milliseconds).value
            let до = корзина.bucketEnd.converted(to: .milliseconds).value
            корзины.append((середина: (от + до) / 2, сколько: корзина.bucketCount))
        }
        корзины.sort { $0.середина < $1.середина }
        let всего = корзины.reduce(0) { $0 + $1.сколько }
        guard всего > 0 else { return nil }
        func доля(_ д: Double) -> Double {
            let нужно = Int((Double(всего) * д).rounded(.up))
            var накоплено = 0
            for корзина in корзины {
                накоплено += корзина.сколько
                if накоплено >= нужно { return корзина.середина.rounded() }
            }
            return (корзины.last?.середина ?? 0).rounded()
        }
        return (медиана: доля(0.5), п90: доля(0.9), всего: всего)
    }
}

@MainActor
enum ЗамерыСкорости {
    /// Очередь замеров на телефоне — не больше стольких (старые уходят первыми).
    private static let пределОчереди = 400
    /// В одной отправке — не больше стольких.
    private static let вПачке = 200
    /// Одного вида — не больше стольких в сутки: длинная лента не забьёт очередь подгрузками страниц.
    private static let вДеньНаВид = 60
    private static let ключНомера = "kliko.perf.installId"
    private static let ключОтправки = "kliko.perf.lastSent"

    private static var очередь: [ЗамерСкорости] = []
    private static var заДень: [String: Int] = [:]
    private static var деньСчёта = 0
    private static var подписчик: ПодписчикMetricKit?
    private static var началоПроцесса = Date()
    private static var предзапуск = false
    /// Холодный запуск ещё не прерван уходом в фон: замеры cold_* честные.
    private static var холодныйИдёт = true
    private static var лентаОтмечена = false
    private static var заставкаОтмечена = false
    private static var отправляем = false
    private static var фоноваяЗадача: UIBackgroundTaskIdentifier = .invalid

    private static let файл: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("kliko-perf.json")

    private static let сессия: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }()

    // MARK: - Запуск

    /// Из AppDelegate.didFinishLaunching: начало процесса, тип сети, подписка MetricKit, очередь с диска.
    static func запустить() {
        /* Предзапуск iOS (ActivePrewarm) поднимает процесс заранее, до нажатия на иконку, — тогда считаем от этой точки. */
        предзапуск = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
        if !предзапуск, let старт = стартПроцесса(), Date().timeIntervalSince(старт) < 30 {
            началоПроцесса = старт
        } else {
            началоПроцесса = Date()
        }
        /* Запуск в фоне (проверка поисков, пуш) — до экрана может пройти сколько угодно: cold_* в такой раз не считаем. */
        if UIApplication.shared.applicationState == .background { холодныйИдёт = false }
        СетьДляЗамеров.shared.запустить()
        let п = ПодписчикMetricKit()
        подписчик = п
        MXMetricManager.shared.add(п)
        if let файл {
            Task {
                let сДиска = await Task.detached(priority: .utility) { () -> [ЗамерСкорости] in
                    guard let данные = try? Data(contentsOf: файл) else { return [] }
                    return (try? JSONDecoder().decode([ЗамерСкорости].self, from: данные)) ?? []
                }.value
                guard !сДиска.isEmpty else { return }
                очередь = Array((сДиска + очередь).suffix(пределОчереди))
            }
        }
    }

    /// Начало процесса по ядру (kinfo_proc.p_starttime) — включает время до main.
    nonisolated private static func стартПроцесса() -> Date? {
        var сведения = kinfo_proc()
        var размер = MemoryLayout<kinfo_proc>.stride
        var запрос: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&запрос, u_int(запрос.count), &сведения, &размер, nil, 0) == 0 else { return nil }
        let старт = сведения.kp_proc.p_un.__p_starttime
        guard старт.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(старт.tv_sec) + TimeInterval(старт.tv_usec) / 1_000_000)
    }

    // MARK: - Свои замеры

    /// Первая карточка ленты на экране после холодного запуска.
    static func лентаПоказана(сДиска: Bool) {
        guard !лентаОтмечена else { return }
        лентаОтмечена = true
        отметитьХолодный("cold_feed", s: ["src": сДиска ? "disk" : "net"])
    }

    /// Заставка ушла после холодного запуска.
    static func заставкаУшла() {
        guard !заставкаОтмечена else { return }
        заставкаОтмечена = true
        отметитьХолодный("cold_splash", s: [:])
    }

    private static func отметитьХолодный(_ вид: String, s: [String: String]) {
        guard холодныйИдёт else { return }
        let мс = Int(Date().timeIntervalSince(началоПроцесса) * 1000)
        guard мс > 0, мс < 120_000 else { return }
        var строки = s
        строки["pre"] = предзапуск ? "1" : "0"
        отметить(вид, ms: мс, s: строки)
    }

    /// Миллисекунды с момента `начало` — для замеров ниже.
    static func мс(с начало: Date) -> Int { max(0, Int(Date().timeIntervalSince(начало) * 1000)) }

    /// Замер в очередь. Рубильник выключен — ничего не делает.
    static func отметить(_ вид: String, ms: Int? = nil, n: [String: Double]? = nil, s: [String: String]? = nil) {
        добавить([ЗамерСкорости(k: вид, ms: ms, n: n, s: s)], сразуНаДиск: false)
    }

    /// Замеры в очередь: сеть, лёгкий режим, город и время — сейчас. MetricKit — сразу на диск (приходит раз в сутки).
    static func добавить(_ замеры: [ЗамерСкорости], сразуНаДиск: Bool) {
        guard Config.телеметрияСкорости else { return }
        let сегодня = Int(Date().timeIntervalSince1970 / 86_400)
        if сегодня != деньСчёта {
            деньСчёта = сегодня
            заДень = [:]
        }
        let сеть = СетьДляЗамеров.shared.сейчас
        let лёгкий = РежимУстройства.shared.причина
        let где = город()
        let минута = Int(Date().timeIntervalSince1970 / 60) * 60
        for замер in замеры {
            let было = заДень[замер.k, default: 0]
            guard было < вДеньНаВид else { continue }
            заДень[замер.k] = было + 1
            var з = замер
            if з.net.isEmpty { з.net = сеть }
            з.lite = лёгкий
            з.city = где
            if з.t == 0 { з.t = минута }
            очередь.append(з)
        }
        if очередь.count > пределОчереди { очередь.removeFirst(очередь.count - пределОчереди) }
        if сразуНаДиск { сохранить() }
    }

    /// Город, выбранный в шапке (не координаты): название, «r:<регион>» или «all» — по всей стране.
    private static func город() -> String {
        guard Config.выборГорода else { return "" }
        let где = ВыборГорода.shared.гдеЛенты
        if !где.город.isEmpty { return String(где.город.prefix(40)) }
        if !где.регион.isEmpty { return "r:" + String(где.регион.prefix(30)) }
        return "all"
    }

    // MARK: - Жизненный цикл и отправка

    /// Приложение стало активным: прошли сутки с прошлой отправки — отправить.
    static func приАктивности() {
        отправить(еслиПрошло: 86_400)
    }

    /// Уход в фон: холодный запуск закончен; очередь — на диск и, если прошёл час, на сервер.
    static func вФон() {
        холодныйИдёт = false
        лентаОтмечена = true
        заставкаОтмечена = true
        сохранить()
        отправить(еслиПрошло: 3_600)
    }

    private static func отправить(еслиПрошло секунд: TimeInterval) {
        guard Config.телеметрияСкорости, !отправляем, !очередь.isEmpty else { return }
        let последняя = UserDefaults.standard.double(forKey: ключОтправки)
        let сейчас = Date().timeIntervalSince1970
        guard сейчас - последняя >= секунд else { return }
        let пачка = Array(очередь.prefix(вПачке))
        let сведения = Bundle.main.infoDictionary
        let тело: Data
        do {
            тело = try JSONEncoder().encode(Пачка(v: 1, ev: пачка, iid: номерУстановки(), model: ЖелезоУстройства.модель,
                                                  mem: ЖелезоУстройства.памятьГБ, ios: UIDevice.current.systemVersion,
                                                  app: (сведения?["CFBundleShortVersionString"] as? String) ?? "",
                                                  build: (сведения?["CFBundleVersion"] as? String) ?? ""))
        } catch {
            return
        }
        var запрос = URLRequest(url: Config.apiBase.appendingPathComponent("api/app_perf.php"))
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.httpBody = тело
        let готовый = запрос
        отправляем = true
        начатьФон()
        Task {
            let ответ = try? await сессия.data(for: готовый)
            let удачно = (ответ?.1 as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            /* 4xx — сервер пачку не примет и повтором (тело кривое или эндпоинта нет): не копим её вечно. */
            let отказ = (ответ?.1 as? HTTPURLResponse).map { (400..<500).contains($0.statusCode) && $0.statusCode != 429 } ?? false
            if удачно || отказ {
                очередь.removeFirst(min(пачка.count, очередь.count))
                UserDefaults.standard.set(сейчас, forKey: ключОтправки)
                сохранить()
            }
            отправляем = false
            закончитьФон()
        }
    }

    /// Несколько секунд в фоне, чтобы запрос успел уйти.
    private static func начатьФон() {
        guard фоноваяЗадача == .invalid else { return }
        фоноваяЗадача = UIApplication.shared.beginBackgroundTask(withName: "kliko.perf") {
            MainActor.assumeIsolated { ЗамерыСкорости.закончитьФон() }
        }
    }

    private static func закончитьФон() {
        guard фоноваяЗадача != .invalid else { return }
        UIApplication.shared.endBackgroundTask(фоноваяЗадача)
        фоноваяЗадача = .invalid
    }

    /// Очередь на диск — не на главной очереди.
    private static func сохранить() {
        guard let файл else { return }
        let копия = очередь
        Task.detached(priority: .utility) {
            if копия.isEmpty {
                try? FileManager.default.removeItem(at: файл)
                return
            }
            guard let данные = try? JSONEncoder().encode(копия) else { return }
            try? данные.write(to: файл, options: .atomic)
        }
    }

    /// Случайный номер установки — только для замеров скорости. Не связан с аккаунтом, телефоном и рекламой.
    private static func номерУстановки() -> String {
        if let есть = UserDefaults.standard.string(forKey: ключНомера), !есть.isEmpty { return есть }
        let новый = UUID().uuidString.lowercased()
        UserDefaults.standard.set(новый, forKey: ключНомера)
        return новый
    }

    /// Тело POST: сведения об устройстве один раз на пачку.
    private struct Пачка: Encodable {
        let v: Int
        let ev: [ЗамерСкорости]
        let iid: String
        let model: String
        let mem: Int
        let ios: String
        let app: String
        let build: String
    }
}
