import Foundation

/**
 3D-ОБЗОР — ФАЙЛЫ МОДЕЛЕЙ И РАКУРСОВ НА ДИСКЕ (Listing3DModel.swift).

 USDZ модели (до десятков мегабайт) и PNG ракурсов качаются своей сессией — эфемерной, без кук, без общего кэша
 URLSession и без подставных заголовков: файлы лежат на kliko.kz открыто, вход для них не нужен. Скачанное ложится в
 Caches/kliko-3d-v1 (система может стереть — это копия, не данные) под именем «хэш адреса + расширение»: RealityKit и
 AR Quick Look узнают USDZ по расширению. Расширение задаёт тот, кто просит файл (модель — всегда "usdz"), а не путь
 адреса: адрес без «.usdz» в пути (CDN, скрипт выдачи) иначе лёг бы «.bin» и не открылся бы. Открыли то же объявление
 снова — файл с диска, без сети. Этим же кэшем качает модель продавец в подаче (Model3DPreview.swift).

 Предел — 200 МБ на всё: после каждой записи самые давние файлы (по времени последнего открытия) уходят, пока не
 влезем; только что скачанный не трогаем. Один файл — не больше 150 МБ: больше — отказ, а не забитый телефон. Ответ не
 200, пустой или «USDZ», который не zip, — ошибка, на диск не попадает.

 Отмена — честная: ушли с экрана (задача .task отменилась) — загрузка обрывается сразу (URLSessionDownloadTask.cancel),
 недокачанное не остаётся. Прогресс — доля 0…1 из Content-Length, не чаще раза на целый процент (наблюдатель зовётся на
 каждый кусок данных); сервер длину не сказал — прогресса нет, экран крутит колесо без процентов. Свой предел файла
 меньше общего (лёгкий режим в «Поместится ли?») — больший файл не качается и с диска не отдаётся.
 */
actor КэшОбъёма {
    static let shared = КэшОбъёма()

    /// Предел папки, байт.
    static let предел: Int64 = 200 * 1024 * 1024
    /// Предел одного файла, байт.
    static let пределФайла: Int64 = 150 * 1024 * 1024

    enum Ошибка: Error {
        case сеть
        case статус(Int)
        case пусто
        case великоват
        case неТотФайл
        case диск
    }

    init() {}

    /// Своя сессия: без кук, без кэша URLSession на диске (свой кэш — папка ниже), долгие файлы — до 5 минут.
    private static let сессия: URLSession = {
        let настройка = URLSessionConfiguration.ephemeral
        настройка.httpShouldSetCookies = false
        настройка.httpCookieStorage = nil
        настройка.urlCache = nil
        настройка.requestCachePolicy = .reloadIgnoringLocalCacheData
        настройка.timeoutIntervalForRequest = 30
        настройка.timeoutIntervalForResource = 300
        настройка.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: настройка)
    }()

    /// Папка кэша; версия в имени — сменится формат, старое просто не найдётся.
    private static var папка: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("kliko-3d-v1", isDirectory: true)
    }

    /**
     Локальный файл по адресу: с диска, если уже есть, иначе скачать. file:// — он же, как есть (подача показывает свои
     ракурсы до отправки). прогресс — доля 0…1 с любой очереди; nil-доли не бывает: длины нет — просто не зовётся.
     расширение — тип файла от вызывающего ("usdz" у модели: имя на диске «.usdz» и проверка zip всегда); nil — по пути
     адреса. предел — свой предел файла, байт (не больше общего пределФайла); больше — Ошибка.великоват.
     */
    func файл(_ адрес: URL, прогресс: (@Sendable (Double) -> Void)?, расширение: String? = nil,
              предел: Int64? = nil) async throws -> URL {
        if адрес.isFileURL { return адрес }
        guard let папка = Self.папка else { throw Ошибка.диск }
        let цель = папка.appendingPathComponent(Self.имя(адрес, расширение: расширение))
        let лимит = min(предел ?? Self.пределФайла, Self.пределФайла)
        let диск = FileManager.default
        if диск.fileExists(atPath: цель.path) {
            let размер = (try? диск.attributesOfItem(atPath: цель.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard размер <= лимит else { throw Ошибка.великоват }
            /* Отметить открытие: старые уходят первыми, а не те, что смотрят чаще. */
            try? диск.setAttributes([.modificationDate: Date()], ofItemAtPath: цель.path)
            return цель
        }
        do {
            try диск.createDirectory(at: папка, withIntermediateDirectories: true)
        } catch {
            throw Ошибка.диск
        }
        try Task.checkCancellation()
        try await Self.скачать(адрес, в: цель, usdz: цель.pathExtension == "usdz", предел: лимит, прогресс: прогресс)
        подрезать(кроме: цель)
        return цель
    }

    /// Файл есть на диске — без сети (значок, решение «показывать ли сразу»).
    func естьНаДиске(_ адрес: URL, расширение: String? = nil) -> Bool {
        if адрес.isFileURL { return true }
        guard let папка = Self.папка else { return false }
        let имя = Self.имя(адрес, расширение: расширение)
        return FileManager.default.fileExists(atPath: папка.appendingPathComponent(имя).path)
    }

    /// Файл оказался негодным (RealityKit не открыл) — убрать, чтобы «Повторить» скачал заново. расширение — то же,
    /// с каким его просили (файл).
    func забыть(_ адрес: URL, расширение: String? = nil) {
        guard !адрес.isFileURL, let папка = Self.папка else { return }
        try? FileManager.default.removeItem(at: папка.appendingPathComponent(Self.имя(адрес, расширение: расширение)))
    }

    /// Всё стереть (выход из аккаунта и прочее, если понадобится).
    func стереть() {
        guard let папка = Self.папка else { return }
        try? FileManager.default.removeItem(at: папка)
    }

    // MARK: Имя файла

    /// FNV-1a 64 от адреса (одинаковый между запусками, Hasher — нет) и расширение из белого списка: заданное
    /// вызывающим, иначе из пути адреса.
    private static func имя(_ адрес: URL, расширение заданное: String?) -> String {
        var х: UInt64 = 0xcbf29ce484222325
        for байт in адрес.absoluteString.utf8 {
            х ^= UInt64(байт)
            х = х &* 0x100000001b3
        }
        let расширение = (заданное ?? адрес.pathExtension).lowercased()
        let своё = ["usdz", "glb", "png", "jpg", "jpeg", "webp", "heic"].contains(расширение) ? расширение : "bin"
        return String(х, radix: 16) + "." + своё
    }

    // MARK: Предел

    /// Самые давние — вон, пока папка больше предела; `кроме` (только что скачанный) не трогаем.
    private func подрезать(кроме: URL) {
        guard let папка = Self.папка else { return }
        let диск = FileManager.default
        let ключи: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let файлы = try? диск.contentsOfDirectory(at: папка, includingPropertiesForKeys: ключи,
                                                       options: [.skipsHiddenFiles]) else { return }
        var записи: [(адрес: URL, когда: Date, размер: Int64)] = []
        var всего: Int64 = 0
        for файл in файлы {
            let свойства = try? файл.resourceValues(forKeys: Set(ключи))
            let размер = Int64(свойства?.totalFileAllocatedSize ?? свойства?.fileSize ?? 0)
            всего += размер
            записи.append((файл, свойства?.contentModificationDate ?? .distantPast, размер))
        }
        guard всего > Self.предел else { return }
        let цель = кроме.standardizedFileURL.path
        for запись in записи.sorted(by: { $0.когда < $1.когда }) {
            if всего <= Self.предел { break }
            if запись.адрес.standardizedFileURL.path == цель { continue }
            if (try? диск.removeItem(at: запись.адрес)) != nil { всего -= запись.размер }
        }
    }

    // MARK: Загрузка

    /**
     Скачать во временный файл сессии и сразу (в обработчике — потом его нет) перенести на место. Отмена задачи Swift —
     отмена загрузки; ответ не 200, пусто, больше предела, «USDZ» не zip — ошибка, на месте ничего не остаётся.
     */
    private static func скачать(_ адрес: URL, в цель: URL, usdz: Bool, предел: Int64,
                                прогресс: (@Sendable (Double) -> Void)?) async throws {
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.timeoutInterval = 30
        let ящик = ЯщикЗагрузкиОбъёма()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (продолжить: CheckedContinuation<Void, Error>) in
                let задача = сессия.downloadTask(with: запрос) { временный, ответ, ошибка in
                    ящик.закончить()
                    if ошибка != nil {
                        if ящик.отменено {
                            продолжить.resume(throwing: CancellationError())
                        } else {
                            продолжить.resume(throwing: Ошибка.сеть)
                        }
                        return
                    }
                    guard let временный, let http = ответ as? HTTPURLResponse else {
                        продолжить.resume(throwing: Ошибка.сеть)
                        return
                    }
                    guard http.statusCode == 200 else {
                        продолжить.resume(throwing: Ошибка.статус(http.statusCode))
                        return
                    }
                    do {
                        try Self.положить(временный, в: цель, usdz: usdz, предел: предел)
                        продолжить.resume()
                    } catch {
                        продолжить.resume(throwing: error)
                    }
                }
                ящик.поставить(задача, предел: предел, прогресс: прогресс)
            }
        } onCancel: {
            ящик.отменить()
        }
    }

    /// Проверить скачанное и перенести на место: сначала рядом под своим именем, потом заменой — второй загрузчик того же
    /// адреса не увидит полфайла.
    private static func положить(_ временный: URL, в цель: URL, usdz: Bool, предел: Int64) throws {
        let диск = FileManager.default
        let размер = (try? диск.attributesOfItem(atPath: временный.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard размер > 0 else { throw Ошибка.пусто }
        guard размер <= предел else { throw Ошибка.великоват }
        if usdz {
            /* USDZ — zip без сжатия: первые байты «PK\u{3}\u{4}». Страница ошибки с кодом 200 сюда не пройдёт. */
            guard let ручка = try? FileHandle(forReadingFrom: временный) else { throw Ошибка.диск }
            let начало = (try? ручка.read(upToCount: 4)) ?? Data()
            try? ручка.close()
            guard начало == Data([0x50, 0x4B, 0x03, 0x04]) else { throw Ошибка.неТотФайл }
        }
        let рядом = цель.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + "." + цель.pathExtension)
        do {
            try диск.moveItem(at: временный, to: рядом)
        } catch {
            throw Ошибка.диск
        }
        do {
            if диск.fileExists(atPath: цель.path) {
                _ = try диск.replaceItemAt(цель, withItemAt: рядом)
            } else {
                try диск.moveItem(at: рядом, to: цель)
            }
        } catch {
            try? диск.removeItem(at: рядом)
            /* Пока переносили, тот же файл положил другой загрузчик — он годный, берём его. */
            if !диск.fileExists(atPath: цель.path) { throw Ошибка.диск }
        }
    }
}

/**
 Задача загрузки, её прогресс и отмена — под замком: отмена задачи Swift может прийти раньше, чем задача URLSession
 создана (тогда она отменяется сразу при постановке), и с любой очереди.
 */
final class ЯщикЗагрузкиОбъёма: @unchecked Sendable {
    private let замок = NSLock()
    private var задача: URLSessionDownloadTask?
    private var наблюдение: NSKeyValueObservation?
    private var _отменено = false
    /// Последний отданный целый процент: наблюдатель зовётся на каждый кусок данных, экрану хватит сотни раз.
    private var последнийПроцент = -1

    var отменено: Bool {
        замок.lock()
        defer { замок.unlock() }
        return _отменено
    }

    func поставить(_ новая: URLSessionDownloadTask, предел: Int64, прогресс: (@Sendable (Double) -> Void)?) {
        замок.lock()
        if _отменено {
            замок.unlock()
            новая.resume()
            новая.cancel()
            return
        }
        задача = новая
        наблюдение = новая.progress.observe(\.fractionCompleted, options: [.new]) { [weak self, weak новая] ход, _ in
            guard let self, let новая else { return }
            /* Больше предела — оборвать сразу, не докачивая. */
            if новая.countOfBytesReceived > предел || новая.countOfBytesExpectedToReceive > предел {
                новая.cancel()
                return
            }
            guard let прогресс, новая.countOfBytesExpectedToReceive > 0 else { return }
            let доля = min(1, max(0, ход.fractionCompleted))
            guard self.новыйПроцент(Int(доля * 100)) else { return }
            прогресс(доля)
        }
        замок.unlock()
        новая.resume()
    }

    /// true — процент сменился (его стоит отдать экрану); с любой очереди.
    private func новыйПроцент(_ процент: Int) -> Bool {
        замок.lock()
        defer { замок.unlock() }
        guard процент != последнийПроцент else { return false }
        последнийПроцент = процент
        return true
    }

    func отменить() {
        замок.lock()
        _отменено = true
        let была = задача
        замок.unlock()
        была?.cancel()
    }

    /// Загрузка кончилась (как угодно) — наблюдение больше не нужно.
    func закончить() {
        замок.lock()
        let было = наблюдение
        наблюдение = nil
        задача = nil
        замок.unlock()
        было?.invalidate()
    }
}
