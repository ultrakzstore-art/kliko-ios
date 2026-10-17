import Foundation
import UIKit
import UserNotifications
import Combine
import Security

/**
 «НОВИНКИ ДЛЯ МОЕГО» — ПОДПИСКА С ТЕЛЕФОНА БЕЗ ВХОДА И PUSH fit_new (пачка 83; docs/SERVER_NEW_FOR_MINE.md §3, §9,
 §10). Только при ключе fit_subs (РубильникиНовинок, по умолчанию выключен): без него нет ни переключателя, ни одного
 запроса.

 Создаётся только по явному «Сообщать о новом» на экране «Для вас» — никогда сама из «Моего»; окно разрешения push — в
 этот момент (и гостю: входа не нужно). Одна запись на телефон: случайный sid (32 hex из SecRandomCopyBytes — не
 identifierForVendor, не номер аккаунта и не токен; знает только телефон, после «Удалить всё «Моё»» — новый), токен
 push, значения стандартов — want, ровно тело подбора §2.1 без адресных параметров: fit_car, fit_phone, fit_laptop, size
 взрослых таблиц одежды и обуви, fit_std дома (кровать, цоколи, VESA), fit_level parts, cats; город, язык, пояс, push в
 сутки и тишина 22–9. Без имён и подписей вещей, без тела, веса, роста и детского.

 Запросы — POST /api/for_mine.php (sub_put, sub_get, sub_del), без куков и сессии; sid — только в теле. sub_put — при
 включении, при смене «Моего» (не чаще раза в час; чаще — уйдёт при следующем открытии), продление раз в 7 дней при
 открытии; без перемен тело не шлётся. sub_del — при выключении, «Удалить всё «Моё»» и выходе (МоёХранилище.стереть).
 «Что хранится на сервере» — sub_get (право на доступ).

 Состояние — файл foryou-watch.json в папке «Моего» (вне резервной копии, стирается с ней): sid, включено ли, последнее
 тело и когда ушло, исключённые группы («Не присылать для этого»).

 Push fit_new (НовинкиМоегоПуш): нажатие — экран «Для вас», номера ids первыми (НовинкиДляВас); действие категории
 FIT_NEW «Не присылать для этого» убирает группы g из want и шлёт sub_put — серверу больше ничего.
 */

// MARK: - Сеть

/// Запросы «Новинок»: своя сессия без куков и кэша — ответы не связываются ни с сессией сайта, ни с человеком.
enum СетьНовинокМоего {
    static let сессия: URLSession = {
        let к = URLSessionConfiguration.ephemeral
        к.httpShouldSetCookies = false
        к.httpCookieAcceptPolicy = .never
        к.httpCookieStorage = nil
        к.urlCache = nil
        к.requestCachePolicy = .reloadIgnoringLocalCacheData
        к.timeoutIntervalForRequest = 15
        return URLSession(configuration: к)
    }()

    /// Нужное из ответа api/for_mine.php.
    struct Ответ: Sendable {
        /// exp — до какого дня живёт запись.
        var до = ""
        /// dropped — что сервер не принял.
        var непринято: [String] = []
        /// want из sub_get — ровно то, что хранится.
        var хранится: [String: String] = [:]
        var город = ""
    }

    enum Итог: Sendable {
        case ok(Ответ)
        /// {"ok": false, "error": …}: bad_sid, bad_token, fit_empty, not_found, off, bad_json…
        case отказ(String)
        /// 404, 405, 410, 501, 3xx, не JSON, unsupported — до перезапуска не спрашиваем.
        case неПоддерживается
        /// Обрыв, таймаут, 5xx, 429 — повтор при следующем открытии.
        case сбой
    }

    /// POST /api/for_mine.php?action=<действие> телом JSON, без куков.
    static func отправить(_ действие: String, тело: Data) async -> Итог {
        guard let адрес = Config.url("/api/for_mine.php?action=" + действие) else { return .сбой }
        var запрос = URLRequest(url: адрес, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        запрос.httpBody = тело
        guard let пара = try? await сессия.data(for: запрос), let http = пара.1 as? HTTPURLResponse else { return .сбой }
        let код: Int = http.statusCode
        if код == 429 || код >= 500 { return .сбой }
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .неПоддерживается }
        guard let корень = (try? JSONSerialization.jsonObject(with: пара.0)) as? [String: Any] else {
            return .неПоддерживается
        }
        guard (корень["ok"] as? Bool) == true else {
            let ошибка: String = (корень["error"] as? String) ?? ""
            if ошибка == "unsupported" { return .неПоддерживается }
            return .отказ(ошибка)
        }
        var ответ = Ответ()
        ответ.до = (корень["exp"] as? String) ?? ""
        let выброшено: [Any] = (корень["dropped"] as? [Any]) ?? []
        ответ.непринято = выброшено.compactMap { (з: Any) -> String? in з as? String }
        if let want = корень["want"] as? [String: Any] {
            for (ключ, значение) in want { ответ.хранится[ключ] = "\(значение)" }
        }
        ответ.город = (корень["city"] as? String) ?? ""
        return .ok(ответ)
    }
}

// MARK: - Подписка

@MainActor
final class ПодпискаНовинокМоего: ObservableObject {
    static let shared = ПодпискаНовинокМоего()

    static let имяФайла = "foryou-watch.json"
    /// Правка «Моего» — не чаще раза в час; продление — раз в 7 дней.
    static let пауза: TimeInterval = 3600
    static let продление: TimeInterval = 7 * 24 * 3600

    /// Весть под переключателем.
    enum Весть: Equatable {
        case нет
        /// fit_empty — нечего сообщать.
        case неОчем
        /// Уведомления запрещены в Настройках.
        case выключеноВНастройках
        /// dropped не пуст.
        case частьНеПринята
        case сбой
    }

    /// want подписки и группы fit_std по порядку (номер g push → группа).
    struct ЖеланиеПодписки: Equatable {
        var want: [String: String] = [:]
        var группыStd: [String] = []
    }

    @Published private(set) var включено = false
    @Published private(set) var занято = false
    @Published private(set) var весть: Весть = .нет
    /// Сервер ответил off или «не поддерживается» — до перезапуска переключателя нет.
    @Published private(set) var выключеноСервером = false
    /// Ответ sub_get строками («Машина: pcd:5x114.3;…»); nil — окно не показано.
    @Published var хранится: [String]? = nil

    private struct Состояние: Codable, Equatable {
        var sid = ""
        var включено = false
        /// Последнее отправленное тело sub_put (JSON): без перемен не шлём.
        var тело = ""
        /// Когда ушёл последний удачный sub_put, с от 1970.
        var когда: Double = 0
        /// «Не присылать для этого»: car, phone, laptop, size, std:<группа>.
        var исключено: [String] = []
        /// fit_std последнего sub_put по порядку — номер g push → группа.
        var группыStd: [String] = []
    }

    private var состояние = Состояние()
    private var прочитано = false
    private var ждёмТокен: AnyCancellable? = nil
    private var отложено: Task<Void, Never>? = nil
    private var повторSid = false
    /// Растёт при выключить() и стереть(): ответ sub_put или окно разрешения, начатые до них, состояние не трогают.
    private var поколение = 0

    private init() {}

    /// Переключатель есть: ключ fit_subs включён и сервер не сказал «off».
    var доступна: Bool { РубильникиНовинок.подписка && !выключеноСервером }

    /// Файл состояния — один раз.
    func подготовить() {
        guard !прочитано else { return }
        прочитано = true
        if let данные = ФайлыМоего.прочитатьМалый(Self.имяФайла),
           let своё = try? JSONDecoder().decode(Состояние.self, from: данные) {
            состояние = своё
        }
        if включено != состояние.включено { включено = состояние.включено }
    }

    private func записать() {
        guard let данные = try? JSONEncoder().encode(состояние) else { return }
        ФайлыМоего.записатьМалый(Self.имяФайла, данные)
    }

    // MARK: Включить и выключить

    /// «Сообщать о новом» включили: окно разрешения push (в этот момент, и гостю), затем sub_put.
    func включить() {
        guard доступна, !занято else { return }
        подготовить()
        занято = true
        весть = .нет
        let своё: Int = поколение
        UNUserNotificationCenter.current().getNotificationSettings { настройки in
            let статус: UNAuthorizationStatus = настройки.authorizationStatus
            Task { @MainActor in ПодпискаНовинокМоего.shared.послеНастроек(статус, своё: своё) }
        }
    }

    private func послеНастроек(_ статус: UNAuthorizationStatus, своё: Int) {
        /* Пока спрашивали Настройки, подписку выключили или стёрли «Моё»: включать нечего, файл не трогаем. */
        guard своё == поколение else {
            занято = false
            return
        }
        switch статус {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            разрешено()
        case .notDetermined:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { да, _ in
                Task { @MainActor in
                    guard своё == ПодпискаНовинокМоего.shared.поколение else {
                        ПодпискаНовинокМоего.shared.занято = false
                        return
                    }
                    if да {
                        UIApplication.shared.registerForRemoteNotifications()
                        ПодпискаНовинокМоего.shared.разрешено()
                    } else {
                        ПодпискаНовинокМоего.shared.запрещено()
                    }
                }
            }
        default:
            запрещено()
        }
    }

    private func разрешено() {
        if состояние.sid.isEmpty { состояние.sid = Self.новыйSid() }
        состояние.включено = true
        включено = true
        занято = false
        записать()
        Task<Void, Never> { @MainActor in
            await ПодпискаНовинокМоего.shared.отправить(сразу: true)
        }
    }

    private func запрещено() {
        занято = false
        состояние.включено = false
        включено = false
        записать()
        весть = .выключеноВНастройках
    }

    /// Выключили: sub_del сразу; sid остаётся (это ключ записи), тело забыто.
    func выключить() {
        подготовить()
        поколение += 1
        let был: Bool = состояние.включено
        состояние.включено = false
        состояние.тело = ""
        состояние.когда = 0
        включено = false
        весть = .нет
        отложено?.cancel()
        отложено = nil
        ждёмТокен = nil
        записать()
        guard был, РубильникиНовинок.подписка, !состояние.sid.isEmpty else { return }
        let sid: String = состояние.sid
        Task<Void, Never> {
            await ПодпискаНовинокМоего.удалить(sid)
        }
    }

    // MARK: Когда слать

    /// Правка «Моего»: подписка включена — sub_put через паузу (живая правка листа — не на каждую букву).
    func моёСменилось() {
        guard РубильникиНовинок.подписка else { return }
        подготовить()
        guard состояние.включено else { return }
        отложено?.cancel()
        отложено = Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await ПодпискаНовинокМоего.shared.отправить(сразу: false)
        }
    }

    /// Открыли полку или экран: продлить раз в 7 дней; накопившуюся правку «Моего» — отправить, если прошёл час.
    func приОткрытии() {
        guard РубильникиНовинок.подписка else { return }
        подготовить()
        guard состояние.включено else { return }
        Task<Void, Never> { @MainActor in
            await ПодпискаНовинокМоего.shared.отправить(сразу: false)
        }
    }

    /**
     sub_put по нынешнему «Моему». сразу — включили или исключили группу: шлём, если тело другое или пора продлевать;
     иначе (правка «Моего», открытие) — ещё и не чаще раза в час. Нет токена push — ждём его.
     */
    func отправить(сразу: Bool) async {
        подготовить()
        guard состояние.включено, доступна else { return }
        guard let токен = WebBridge.shared.apnsToken, Self.годныйТокен(токен) else {
            /* Токена ещё нет — ждём первый; есть, но негодный — ждём другой (иначе ждали бы его же по кругу). */
            let естьНегодный: Bool = WebBridge.shared.apnsToken != nil
            ждатьТокен(новый: естьНегодный)
            return
        }
        let хранилище = МоёХранилище.shared
        хранилище.подготовить()
        let исключено: Set<String> = Set(состояние.исключено)
        let сборка: ЖеланиеПодписки = Self.желание(хранилище.запись, исключено: исключено)
        guard !сборка.want.isEmpty else {
            весть = .неОчем
            return
        }
        if состояние.sid.isEmpty { состояние.sid = Self.новыйSid() }
        var тело: [String: Any] = [
            "sid": состояние.sid,
            "token": токен,
            "env": Self.среда,
            "lang": ПримерочнаяText.язык,
            "tz": "Asia/Almaty",
            "want": сборка.want,
            "daily": РубильникиНовинок.вСутки,
            "quiet": [22, 9]
        ]
        let город: String = ГдеИскать.сохранённое().город
        if !город.isEmpty { тело["city"] = город }
        guard let данные = try? JSONSerialization.data(withJSONObject: тело, options: [.sortedKeys]) else { return }
        let строка: String = String(decoding: данные, as: UTF8.self)
        let прошло: Double = Date().timeIntervalSince1970 - состояние.когда
        if строка == состояние.тело && прошло < Self.продление { return }
        if !сразу && прошло < Self.пауза { return }
        let своё: Int = поколение
        let sid: String = состояние.sid
        let итог: СетьНовинокМоего.Итог = await СетьНовинокМоего.отправить("sub_put", тело: данные)
        guard своё == поколение, состояние.включено else {
            /* Пока шёл sub_put, подписку выключили или стёрли «Моё»: файл не трогаем (папка «Моего» могла уже уйти), а
               запись на сервере снимаем ещё раз — sub_del выключения мог дойти раньше этого sub_put. Включили снова тем
               же sid — запись нужна, её поставит новый sub_put. */
            let тотЖеSid: Bool = состояние.включено && состояние.sid == sid
            if case .ok = итог, РубильникиНовинок.подписка, !sid.isEmpty, !тотЖеSid {
                await ПодпискаНовинокМоего.удалить(sid)
            }
            return
        }
        принять(итог, тело: строка, группыStd: сборка.группыStd)
    }

    private func принять(_ итог: СетьНовинокМоего.Итог, тело: String, группыStd: [String]) {
        switch итог {
        case .ok(let ответ):
            состояние.тело = тело
            состояние.когда = Date().timeIntervalSince1970
            состояние.группыStd = группыStd
            записать()
            повторSid = false
            весть = ответ.непринято.isEmpty ? .нет : .частьНеПринята
        case .отказ(let ошибка):
            switch ошибка {
            case "bad_sid":
                /* sid не 32 hex — новый и повтор один раз. */
                guard !повторSid else {
                    весть = .сбой
                    return
                }
                повторSid = true
                состояние.sid = Self.новыйSid()
                состояние.тело = ""
                записать()
                Task<Void, Never> { @MainActor in
                    await ПодпискаНовинокМоего.shared.отправить(сразу: true)
                }
            case "bad_token":
                ждатьТокен(новый: true)
            case "fit_empty":
                весть = .неОчем
            default:
                /* off — ключ выключен на сервере; bad_json, слишком большое тело — прежний путь до перезапуска. */
                выключеноСервером = true
            }
        case .неПоддерживается:
            выключеноСервером = true
        case .сбой:
            весть = .сбой
        }
    }

    /// Ждать токен push (новый — другой, чем сейчас): пришёл — sub_put.
    private func ждатьТокен(новый: Bool) {
        guard ждёмТокен == nil else { return }
        let исток: AnyPublisher<String?, Never>
        if новый {
            исток = WebBridge.shared.$apnsToken.dropFirst().eraseToAnyPublisher()
        } else {
            исток = WebBridge.shared.$apnsToken.eraseToAnyPublisher()
        }
        ждёмТокен = исток
            .compactMap { (токен: String?) -> String? in токен }
            .first()
            .sink { (_: String) in
                Task { @MainActor in
                    ПодпискаНовинокМоего.shared.ждёмТокен = nil
                    await ПодпискаНовинокМоего.shared.отправить(сразу: true)
                }
            }
    }

    // MARK: Push и «Удалить всё»

    /// «Не присылать для этого» из push: группы g убрать из want и sub_put. std:<номер> — группа последнего sub_put.
    func неПрисылать(_ группы: [String]) async {
        подготовить()
        /* Подписки нет (выключили или стёрли «Моё») — исключать не из чего, файл не создаём. */
        guard состояние.включено else { return }
        var исключено: [String] = состояние.исключено
        for группа in группы {
            var ключ: String = группа
            if группа.hasPrefix("std:") {
                guard let номер = Int(группа.dropFirst(4)), состояние.группыStd.indices.contains(номер) else { continue }
                ключ = "std:" + состояние.группыStd[номер]
            } else if !["car", "phone", "laptop", "size"].contains(группа) {
                continue
            }
            if !исключено.contains(ключ) { исключено.append(ключ) }
        }
        guard исключено != состояние.исключено else { return }
        состояние.исключено = Array(исключено.suffix(40))
        записать()
        await отправить(сразу: true)
    }

    /// «Удалить всё «Моё»» и выход: sub_del сразу (если подписка была), всё забыть — следующий раз новый sid.
    func стереть() {
        /* Ключ выключен — запроса нет и файл не читаем (он уходит вместе с папкой «Моего»). */
        let можно: Bool = РубильникиНовинок.подписка
        if можно { подготовить() }
        поколение += 1
        let sid: String = состояние.sid
        let был: Bool = состояние.включено
        отложено?.cancel()
        отложено = nil
        ждёмТокен = nil
        состояние = Состояние()
        /* Прочитанным считаем пустое: папка стирается на очереди, прежний файл не должен вернуться в память. */
        прочитано = true
        повторSid = false
        включено = false
        весть = .нет
        хранится = nil
        guard можно, был, !sid.isEmpty else { return }
        Task<Void, Never> {
            await ПодпискаНовинокМоего.удалить(sid)
        }
    }

    /// «Что хранится на сервере»: sub_get — ровно то, что хранится; не найдено — подписки на сервере нет.
    func спросить() async {
        подготовить()
        let ничего: [String] = [НовинкиМоегоText.т("nm_watch_stored_none")]
        guard доступна, !состояние.sid.isEmpty else {
            хранится = ничего
            return
        }
        let тело: [String: String] = ["sid": состояние.sid]
        guard let данные = try? JSONSerialization.data(withJSONObject: тело) else { return }
        let итог: СетьНовинокМоего.Итог = await СетьНовинокМоего.отправить("sub_get", тело: данные)
        switch итог {
        case .ok(let ответ):
            хранится = Self.строки(ответ)
        case .отказ(let ошибка):
            if ошибка == "not_found" {
                хранится = ничего
            } else if ошибка == "off" {
                выключеноСервером = true
            } else {
                весть = .сбой
            }
        case .неПоддерживается:
            выключеноСервером = true
        case .сбой:
            весть = .сбой
        }
    }

    // MARK: Чистые функции

    nonisolated static func удалить(_ sid: String) async {
        let тело: [String: String] = ["sid": sid]
        guard let данные = try? JSONSerialization.data(withJSONObject: тело) else { return }
        _ = await СетьНовинокМоего.отправить("sub_del", тело: данные)
    }

    /// 32 hex из системного случайного (128 бит).
    nonisolated static func новыйSid() -> String {
        var байты: [UInt8] = [UInt8](repeating: 0, count: 16)
        let код: Int32 = SecRandomCopyBytes(kSecRandomDefault, байты.count, &байты)
        if код != errSecSuccess {
            var генератор = SystemRandomNumberGenerator()
            for номер in байты.indices { байты[номер] = UInt8.random(in: 0...255, using: &генератор) }
        }
        var итог = ""
        for байт in байты { итог += String(format: "%02x", байт) }
        return итог
    }

    /// Токен APNs: 64–200 hex.
    nonisolated static func годныйТокен(_ токен: String) -> Bool {
        (64...200).contains(токен.count) && токен.allSatisfy { (знак: Character) -> Bool in знак.isHexDigit }
    }

    private static var среда: String {
        #if DEBUG
        return "sandbox"
        #else
        return "prod"
        #endif
    }

    /// Значение части fit_std: только буквы, цифры, «.», «x», «-» — без разделителей запроса.
    private static func чисто(_ значение: String) -> String? {
        let допустимо: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let отобрано: String = String(значение.filter { (знак: Character) -> Bool in допустимо.contains(знак) })
        let итог: String = String(отобрано.prefix(24))
        return итог.isEmpty ? nil : итог
    }

    /**
     want (§3.2) — ровно тело подбора §2.1 без адресных параметров. Только значения: ни имён вещей, ни подписей; одежда и
     обувь — взрослые таблицы; бельё, кольца, тело, вес, рост и детское не уходят. Исключённое «Не присылать для этого» —
     мимо. Нечего слать — пусто.
     */
    static func желание(_ запись: ЗаписьМоего, исключено: Set<String>) -> ЖеланиеПодписки {
        let моё: ЗаписьМоего = ПодборДляВас.моёДляСверки(запись)
        var want: [String: String] = [:]
        if !исключено.contains("car"), let машина = моё.главнаяМашина,
           let посадка = ОтборСервераДляВас.значениеПосадки(машина) {
            want["fit_car"] = посадка
        }
        if !исключено.contains("phone"), let телефон = моё.телефон,
           let модель = ОтборСервераДляВас.slug(телефон.модель) {
            want["fit_phone"] = модель
        }
        if !исключено.contains("laptop"), let диагональ = СовместимостьМоего.диагональНоутбука(моё) {
            want["fit_laptop"] = String(format: "%.1f", диагональ)
        }
        if !исключено.contains("size") {
            let взрослые: [РазмерМоего] = моё.тело.размеры.filter { (р: РазмерМоего) -> Bool in
                р.вид.обувь || р.вид.одежда
            }
            if let размеры = ОтборСервераДляВас.размеры(взрослые) { want["size"] = размеры }
        }
        var группы: [String] = []
        let места: [String] = Set(моё.дом.кровати.compactMap { (к: КроватьМоего) -> String? in к.место }).sorted()
        for место in места {
            if let своё = чисто(место) { группы.append("bed_size.size:" + своё) }
        }
        for цоколь in моё.дом.цоколи.keys.sorted() {
            if let своё = чисто(цоколь) { группы.append("lamp_base.base:" + своё) }
        }
        let шаблоны: [String] = Set(моё.дом.экраны.compactMap { (э: ЭкранНаСтенеМоего) -> String? in э.vesa }).sorted()
        for шаблон in шаблоны {
            if let своё = чисто(шаблон) { группы.append("vesa.pattern:" + своё) }
        }
        var свои: [String] = []
        for группа in группы where !исключено.contains("std:" + группа) && !свои.contains(группа) {
            свои.append(группа)
            if свои.count >= 12 { break }
        }
        if !свои.isEmpty { want["fit_std"] = свои.joined(separator: "|") }
        guard !want.isEmpty else { return ЖеланиеПодписки() }
        want["fit_level"] = "parts"
        let запросы: [ЗапросПодбораМоего] = ПодборДляВас.запросы(моё, предел: 12)
        var разделы: [String] = []
        for запрос in запросы where !разделы.contains(запрос.раздел) { разделы.append(запрос.раздел) }
        if !разделы.isEmpty { want["cats"] = разделы.prefix(20).joined(separator: ",") }
        return ЖеланиеПодписки(want: want, группыStd: свои)
    }

    /// Ответ sub_get строками для окна: что за значение — подписью, само значение — как хранится.
    static func строки(_ ответ: СетьНовинокМоего.Ответ) -> [String] {
        let подписи: [String: String] = [
            "fit_car": "nm_st_car", "fit_phone": "nm_st_phone", "fit_laptop": "nm_st_laptop", "size": "nm_st_size",
            "fit_std": "nm_st_std"
        ]
        var итог: [String] = []
        for ключ in ответ.хранится.keys.sorted() {
            let значение: String = ответ.хранится[ключ] ?? ""
            let подпись: String = подписи[ключ].map { (к: String) -> String in НовинкиМоегоText.т(к) } ?? ключ
            итог.append(подпись + ": " + значение)
        }
        if !ответ.город.isEmpty { итог.append(НовинкиМоегоText.т("nm_st_city") + ": " + ответ.город) }
        if !ответ.до.isEmpty { итог.append(НовинкиМоегоText.ф("nm_watch_stored_exp", ответ.до)) }
        return итог.isEmpty ? [НовинкиМоегоText.т("nm_watch_stored_none")] : итог
    }
}

// MARK: - Push fit_new

/**
 Push «Новинки для моего» (§3.5): type fit_new, url /cabinet.php?go=foryou&new=1, ids — до 20 номеров (первыми среди
 загруженного «Для вас», отдельно не догружаются), g — найденные группы want. Категория FIT_NEW регистрируется вместе с
 KLIKO_MESSAGE (ОтветИзУведомления.зарегистрировать): два отдельных вызова set затирали бы друг друга.
 */
enum НовинкиМоегоПуш {
    static let категория = "FIT_NEW"
    static let действиеНеПрисылать = "kliko.fit.off"

    static func это(_ инфо: [AnyHashable: Any]) -> Bool {
        (инфо["type"] as? String) == "fit_new"
    }

    /// FIT_NEW: «Не присылать для этого» — без открытия приложения.
    static func категорияУведомлений() -> UNNotificationCategory {
        let действие = UNNotificationAction(identifier: действиеНеПрисылать, title: НовинкиМоегоText.т("nm_push_off"),
                                            options: [])
        return UNNotificationCategory(identifier: категория, actions: [действие], intentIdentifiers: [], options: [])
    }

    /// ids push — до 20 номеров объявлений (буквы, цифры, «-», «_»).
    static func номера(_ инфо: [AnyHashable: Any]) -> [String] {
        let сырые: [Any] = (инфо["ids"] as? [Any]) ?? []
        var итог: [String] = []
        for сырое in сырые.prefix(20) {
            let номер: String = "\(сырое)".trimmingCharacters(in: .whitespaces)
            guard номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else { continue }
            итог.append(номер)
        }
        return итог
    }

    /// g push — группы want: car, phone, laptop, size, std:<номер>.
    static func группы(_ инфо: [AnyHashable: Any]) -> [String] {
        let сырые: [Any] = (инфо["g"] as? [Any]) ?? []
        var итог: [String] = []
        for сырое in сырые.prefix(20) {
            let группа: String = "\(сырое)".trimmingCharacters(in: .whitespaces).lowercased()
            if !группа.isEmpty && группа.count <= 16 { итог.append(группа) }
        }
        return итог
    }

    /// Последний открытый push: его номера и когда. Холодный старт отдаёт одно нажатие дважды (launchOptions и
    /// didReceive, AppDelegate.swift), и на тяжёлом запуске между ними больше секунды защиты ПоверхВсего.показать.
    @MainActor private static var открытоКогда: (номера: [String], когда: Date)? = nil

    /// Нажатие на push: экран «Для вас», находки push — первыми. То же нажатие второй раз за 10 с — второго окна нет.
    @MainActor
    static func открыть(_ номераПуша: [String]) {
        guard Config.дляВас && Config.моё else { return }
        ПодборкаДляВас.shared.изПуша(номераПуша)
        let сейчас: Date = Date()
        if let было = открытоКогда, было.номера == номераПуша, сейчас.timeIntervalSince(было.когда) < 10 { return }
        открытоКогда = (номера: номераПуша, когда: сейчас)
        ОкноДляВас.открыть()
    }

    /// «Не присылать для этого»: наше действие — сделает в фоне и позовёт готово(); не наше — false.
    static func обработать(_ ответ: UNNotificationResponse, готово: @escaping () -> Void) -> Bool {
        guard ответ.actionIdentifier == действиеНеПрисылать else { return false }
        let найденные: [String] = группы(ответ.notification.request.content.userInfo)
        Task { @MainActor in
            await ПодпискаНовинокМоего.shared.неПрисылать(найденные)
            готово()
        }
        return true
    }
}
