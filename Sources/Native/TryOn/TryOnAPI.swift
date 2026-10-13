import Foundation
import UIKit
import Photos
import Vision

/**
 ПРИМЕРОЧНАЯ ОДЕЖДЫ — ЗАПРОСЫ И ДАННЫЕ (владелец 13.10.2026: «примерочная для одежды»).

 «Примерить на себя» на странице объявления одежды: человек снимает себя, а Kliko AI (или «Свой ИИ», если его поставщик
 умеет изображения) рисует его в этой вещи. Рисует сервер ultra-site по договору docs/SERVER_TRYON.md:
   · GET  /api/tryon.php?action=info → {ok, on, auth, ai, own, left, limit, sections} — есть ли примерочная, где она
     и кто обработает фото (его называет согласие перед первой отправкой, App Review 5.1.2(i));
   · POST action=start {csrf, listing_id, photo, photo_index, own, lang} → {ok, job} | {ok:false, code, error};
   · POST action=status {csrf, job, lang} → {ok, state: queued|working|done|failed, progress, image, error};
   · POST action=delete {csrf, job} → {ok}.
 Транспорт — как у остальных действий кабинета: МоиОбъявленияAPI.отправить (fetch изнутри страницы сайта под слоем, её
 куки и настоящие Origin/Referer, токен страницы и один повтор на «csrf»), пути от корня. Пробу info — сам
 КабинетСайта.вызвать: по коду ответа видно, есть ли такая страница на сервере вообще.

 🔴 ЧЕСТНЫЙ ОТКАТ. Config.примерочная = false — ни кнопки, ни запросов. Включён, а сервер не умеет (404, перенаправление,
 не JSON, «unsupported», on:false) — кнопки нет до перезапуска; сервер перестал понимать посреди примерки — «Примерочная
 скоро заработает».

 🔴 ФОТО ЧЕЛОВЕКА. Уходит один раз, в теле start: перерисованным (без EXIF и места съёмки), не больше 1280 px. На телефоне
 не пишется ни в файлы, ни в кэш; результат качается эфемерной сессией — без кук и без кэша на диске. Окно закрыли —
 delete на сервер сразу, не дожидаясь суток.
 */
extension Config {
    /// Примерочная одежды: «Примерить на себя» на странице объявления одежды. Выключена, пока сервер не научится
    /// /api/tryon.php (docs/SERVER_TRYON.md). false — ни кнопки, ни запросов.
    /// 🔴 ВКЛЮЧАЯ — тем же коммитом дописать в project.yml тексты разрешений (App Review 5.1.1(ii)): в
    /// NSCameraUsageDescription — «…или сфотографировать себя, чтобы примерить одежду из объявления», в
    /// NSPhotoLibraryAddUsageDescription — «…или сохранить результат примерки». Сейчас они о примерочной молчат.
    static let примерочная = false
}

// MARK: - Разделы

/// Где кнопка, пока сервер не прислал свой список (sections в info). Ключи — дерева сайта (РазделыСайта).
enum РазделыПримерочной {
    /// Одежда, обувь, сумки и аксессуары, украшения и часы — весь корень «clothing».
    static let ветки: Set<String> = ["clothing"]
    /// Кроме детской одежды и детской обуви (kids-shoes лежит в clothing → shoes): фото детей — особые данные, а модели
    /// изображений правку фото несовершеннолетних не берут. И кроме кошельков: на себе их не примерить — сервер ответил
    /// бы not_clothes уже после съёмки. Вернуть их может только сервер — списком sections.
    static let кромеВеток: Set<String> = ["kids-clothing", "kids-shoes", "wallets"]

    /// Раздел объявления (лист дерева) или его предок — в списке. свои — sections сервера; пусто — список приложения.
    static func подходит(_ раздел: String?, свои: Set<String> = []) -> Bool {
        guard let раздел, !раздел.isEmpty else { return false }
        if !свои.isEmpty { return РазделыСайта.внутри(раздел, свои) }
        return РазделыСайта.внутри(раздел, ветки) && !РазделыСайта.внутри(раздел, кромеВеток)
    }
}

// MARK: - Ответы

/// Ответ action=info. Поля необязательные: лишнее, что сервер добавит потом, не мешает.
struct СведенияПримерочной: Equatable {
    /// on — примерочная включена на сервере. Нет поля при ok:true — включена.
    var вкл = false
    /// auth — запрос с сессией вошедшего; гостю кнопка есть, окно сначала просит войти.
    var вошёл = false
    /// ai — кто обработает фото: «Kliko AI · Google Gemini», «OpenAI»… Его называет согласие.
    var ии = ""
    /// own — фото пойдёт через «Свой ИИ» человека.
    var свойИИ = false
    /// left / limit — сколько примерок осталось сегодня и сколько всего; nil — сервер не сказал.
    var осталось: Int? = nil
    var лимит: Int? = nil
    /// sections — ключи разделов сайта с кнопкой; пусто — список приложения (РазделыПримерочной).
    var разделы: Set<String> = []

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        вкл = j["on"] == nil || A.да(j["on"])
        вошёл = j["auth"] == nil || A.да(j["auth"])
        ии = A.строка(j["ai"]).trimmingCharacters(in: .whitespacesAndNewlines)
        свойИИ = A.да(j["own"])
        if j["left"] != nil { осталось = max(0, A.целое(j["left"])) }
        if j["limit"] != nil { лимит = max(0, A.целое(j["limit"])) }
        var список: Set<String> = []
        for элемент in (j["sections"] as? [Any]) ?? [] {
            let ключ = A.строка(элемент).trimmingCharacters(in: .whitespacesAndNewlines)
            if !ключ.isEmpty { список.insert(ключ) }
        }
        разделы = список
    }
}

/// Ответ action=status.
struct ХодПримерочной: Equatable {
    enum Состояние: String {
        case queued, working, done, failed
    }

    var состояние: Состояние = .working
    /// progress 0…100.
    var прогресс = 0
    /// image при done — только https на kliko.kz и его поддоменах (адрес(_:)).
    var картинка: URL? = nil

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        состояние = Состояние(rawValue: A.строка(j["state"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? .working
        прогресс = min(100, max(0, A.целое(j["progress"])))
        картинка = Self.адрес(A.строка(j["image"]))
    }

    /// Адрес результата: https на kliko.kz или его поддомене; путь от корня — от https://kliko.kz. Чужой хост — nil:
    /// фото человека с чужого адреса не качаем.
    static func адрес(_ строка: String) -> URL? {
        let чистая = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистая.isEmpty else { return nil }
        let адрес: URL?
        if чистая.hasPrefix("/") && !чистая.hasPrefix("//") {
            адрес = URL(string: чистая, relativeTo: Config.apiBase)?.absoluteURL
        } else {
            адрес = URL(string: чистая)
        }
        guard let адрес, адрес.scheme?.lowercased() == "https", let хост = адрес.host?.lowercased() else { return nil }
        guard хост == "kliko.kz" || хост.hasSuffix(".kliko.kz") else { return nil }
        return адрес
    }
}

/// Отказ примерочной: код сервера и готовый текст. Отказ своего ИИ — ещё и окно «Свой ИИ».
struct ОтказПримерочной: Equatable {
    let код: String
    let текст: String
    var свойИИ: ОтказСвоегоИИ? = nil

    init(код: String, текст: String, свойИИ: ОтказСвоегоИИ? = nil) {
        self.код = код
        self.текст = текст
        self.свойИИ = свойИИ
    }

    /// «Переснять» поможет: сервер не принял фото человека.
    var переснять: Bool { код == "bad_photo" }

    /// «Повторить» может помочь: ИИ занят, сеть, сбой. Лимит, не та вещь, плохое фото — нет.
    var повторить: Bool { !["limit", "not_clothes", "bad_photo", "gone"].contains(код) }
}

// MARK: - Запросы

@MainActor
enum ПримерочнаяAPI {
    enum Ответ {
        case готово([String: Any])
        case отказ(ОтказПримерочной)
        case нуженВход
        /// Сервер не умеет (unsupported) — «Примерочная скоро заработает».
        case нетСервера
        case сеть
        /// Ответ не JSON, нет токена и прочее — «Не получилось».
        case сбой
    }

    enum ИтогСведений {
        case есть(СведенияПримерочной)
        case нетСервера
        case сеть
    }

    private static let путь = "/api/tryon.php?action="

    /// GET info. 404/405/410/501, перенаправление, не JSON, unsupported — сервера нет; 5xx и обрыв — сеть (спросим позже).
    static func сведения() async -> ИтогСведений {
        typealias A = МоиОбъявленияAPI
        let ответ: КабинетСайта.Ответ
        do {
            ответ = try await КабинетСайта.вызвать(путь + "info&lang=" + ПримерочнаяText.язык, отКорня: true)
        } catch {
            return .сеть
        }
        let код = ответ.код
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
        guard код > 0, код < 500 else { return .сеть }
        guard let j = ответ.json else { return .нетСервера }
        if A.строка(j["error"]) == "unsupported" || A.строка(j["code"]) == "unsupported" { return .нетСервера }
        if A.да(j["ok"]) { return .есть(СведенияПримерочной(j)) }
        if A.нетСессии(j) {
            /* Сервер не отвечает гостю сведениями — примерочная есть, но сначала вход. */
            var гость = СведенияПримерочной()
            гость.вкл = true
            гость.вошёл = false
            return .есть(гость)
        }
        return .нетСервера
    }

    /// POST start. own — у человека включён «Свой ИИ» (как own:1 у recognize); решает сервер.
    static func начать(товар: String, фото: String, номерФото: Int, свой: Bool) async -> Ответ {
        var тело: [String: Any] = ["listing_id": товар, "photo": фото, "photo_index": номерФото,
                                   "lang": ПримерочнаяText.язык]
        if свой { тело["own"] = 1 }
        return await выполнить("start", тело)
    }

    /// POST status. failed приходит с ok:true — его разбирает модель (разобратьОтказ).
    static func ход(_ задача: String) async -> Ответ {
        await выполнить("status", ["job": задача, "lang": ПримерочнаяText.язык])
    }

    /// POST delete: фото человека и результат с сервера. true — удалено (или такой примерки уже нет).
    static func удалить(_ задача: String) async -> Bool {
        switch await выполнить("delete", ["job": задача]) {
        case .готово:
            return true
        case .отказ(let отказ):
            return отказ.код == "gone"
        case .нуженВход, .нетСервера, .сеть, .сбой:
            return false
        }
    }

    /// POST {csrf, …} тем же путём, что действия кабинета. Повторов при сбое сети нет: запись могла дойти.
    private static func выполнить(_ действие: String, _ тело: [String: Any]) async -> Ответ {
        typealias A = МоиОбъявленияAPI
        let j: [String: Any]
        do {
            j = try await A.отправить(путь + действие, тело: тело, отКорня: true)
        } catch let сбой as КабинетСайта.Сбой where сбой == .сеть {
            return .сеть
        } catch {
            return .сбой
        }
        if A.да(j["ok"]) { return .готово(j) }
        return разобратьОтказ(j)
    }

    /**
     {ok:false, code, error} у start и delete, {state:"failed", code, error} у status → что показать. error — готовый текст
     на языке человека; машинный код — своё «Не получилось». limit — своя фраза: текст сервера может звать купить пакет на
     сайте (цифровое в приложении — только App Store, 3.1.1). own_ai — как §5 договора «Свой ИИ» (ОтказСвоегоИИ.из).
     */
    static func разобратьОтказ(_ j: [String: Any]) -> Ответ {
        typealias A = МоиОбъявленияAPI
        let код = A.строка(j["code"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if код == "unsupported" || ошибка == "unsupported" { return .нетСервера }
        if код == "auth" || A.нетСессии(j) { return .нуженВход }
        if let своего = ОтказСвоегоИИ.из(j) {
            return .отказ(ОтказПримерочной(код: "own_ai", текст: своего.текст, свойИИ: своего))
        }
        if код == "own_ai" {
            let своего = ОтказСвоегоИИ(код: "bad", текст: ОтказСвоегоИИ.текстОтвета(j))
            return .отказ(ОтказПримерочной(код: код, текст: своего.текст, свойИИ: своего))
        }
        let итоговый = код.isEmpty && КабинетСайта.машинныйКод(ошибка) ? ошибка : код
        let текст: String
        switch итоговый {
        case "limit":
            текст = ПримерочнаяText.т("to_limit")
        case "gone":
            текст = ПримерочнаяText.т("to_gone")
        default:
            текст = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? ПримерочнаяText.т("to_err_fail") : ошибка
        }
        return .отказ(ОтказПримерочной(код: итоговый, текст: текст))
    }
}

// MARK: - Фото: подготовка, результат, Фото iPhone

/// Работа с картинками без главной нити — её зовут из Task.detached. На входе и выходе — Data и строки.
enum ФотоПримерочной {
    struct Готовое: Sendable {
        /// «data:image/jpeg;base64,…» для start.
        let адрес: String
        /// Тот же JPEG — показать на экране.
        let jpeg: Data
        /// Vision нашёл человека; nil — не знаем (не мешаем отправке).
        let человек: Bool?
    }

    enum ИтогСохранения: Sendable {
        case готово
        case нетДоступа
        case сбой
    }

    /// Без кук и без кэша на диске: результат — фото человека, ему нечего делать в URLCache.
    private static let сессия = URLSession(configuration: .ephemeral)

    /// Снимок или файл галереи → длинная сторона ≤ 1280, белая подложка, JPEG 0,82. Рисуется заново: поворот учтён,
    /// EXIF и место съёмки не уходят. Слишком маленькое или битое — nil.
    static func подготовить(_ данные: Data) -> Готовое? {
        guard let снимок = UIImage(data: данные) else { return nil }
        return подготовить(снимок)
    }

    static func подготовить(_ снимок: UIImage) -> Готовое? {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard w >= 64, h >= 64 else { return nil }
        let k = min(1, 1280 / max(w, h))
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let готовый = UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            UIColor.white.setFill()
            холст.fill(CGRect(origin: .zero, size: размер))
            снимок.draw(in: CGRect(origin: .zero, size: размер))
        }
        guard let jpeg = готовый.jpegData(compressionQuality: 0.82) else { return nil }
        let адрес = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        guard адрес.count > 120 else { return nil }
        return Готовое(адрес: адрес, jpeg: jpeg, человек: естьЧеловек(готовый))
    }

    /// Человек в кадре (VNDetectHumanRectanglesRequest во весь рост). Только подсказка «лучше переснять» — решает сервер.
    static func естьЧеловек(_ картинка: UIImage) -> Bool? {
        guard let кадр = картинка.cgImage else { return nil }
        let запрос = VNDetectHumanRectanglesRequest()
        запрос.upperBodyOnly = false
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return nil
        }
        return !(запрос.results ?? []).isEmpty
    }

    /// Результат по адресу из status: 200 и непустое тело — данные; иначе nil.
    static func скачать(_ адрес: URL) async -> Data? {
        var запрос = URLRequest(url: адрес)
        запрос.timeoutInterval = 30
        запрос.cachePolicy = .reloadIgnoringLocalCacheData
        запрос.httpShouldHandleCookies = false
        guard let пара = try? await сессия.data(for: запрос) else { return nil }
        let (данные, ответ) = пара
        guard let http = ответ as? HTTPURLResponse, http.statusCode == 200, !данные.isEmpty else { return nil }
        return данные
    }

    /// В Фото iPhone: доступ только на добавление (NSPhotoLibraryAddUsageDescription), файл — как пришёл с сервера.
    static func вФото(_ данные: Data) async -> ИтогСохранения {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return .нетДоступа }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: данные, options: nil)
            }
            return .готово
        } catch {
            return .сбой
        }
    }
}

// MARK: - Есть ли примерочная

/**
 Что сервер сказал в info — одно на приложение. Спрашивает лениво: кнопка на странице одежды и окно примерочной; не чаще
 раза в 10 минут, после сбоя сети — раз в минуту, после входа и выхода — заново. Сервер не умеет — до перезапуска не
 спрашиваем. Синглтон создаётся пустым и в init ни к кому не обращается.
 */
@MainActor
final class ГотовностьПримерочной: ObservableObject {
    static let shared = ГотовностьПримерочной()

    @Published private(set) var сведения: СведенияПримерочной? = nil
    @Published private(set) var нетСервера = false

    private var когда: Date? = nil
    private var дляСессии = -1
    private var идёт: Task<Void, Never>? = nil

    private init() {}

    /// Кнопка «Примерить на себя» у этого объявления: рубильник, сервер сказал on, раздел одежды, есть фото.
    func можно(_ товар: Listing) -> Bool {
        guard Config.примерочная, !нетСервера, let с = сведения, с.вкл, !товар.фотоАдреса.isEmpty else { return false }
        return РазделыПримерочной.подходит(товар.категория, свои: с.разделы)
    }

    func проверить() async {
        guard Config.примерочная, !нетСервера else { return }
        /* смена растёт при любой смене человека (вход, выход, другой аккаунт): сведения у каждого свои (auth, left). */
        let сессия = СессияПриложения.shared.смена
        if let когда {
            let прошло = Date().timeIntervalSince(когда)
            if сведения != nil && дляСессии == сессия && прошло < 600 { return }
            if сведения == nil && прошло < 60 { return }
        }
        if let идёт {
            await идёт.value
            return
        }
        let задача = Task { @MainActor in
            let итог = await ПримерочнаяAPI.сведения()
            let готовность = ГотовностьПримерочной.shared
            готовность.когда = Date()
            switch итог {
            case .есть(let новые):
                готовность.дляСессии = сессия
                if готовность.сведения != новые { готовность.сведения = новые }
            case .нетСервера:
                готовность.отметитьНетСервера()
            case .сеть:
                break
            }
        }
        идёт = задача
        await задача.value
        идёт = nil
    }

    /// Человек только что вошёл из окна примерочной: сведения гостя (auth:false) больше не годятся — спросить заново.
    func устарели() {
        когда = nil
        дляСессии = -1
    }

    /// Сервер ответил «не умею» — кнопки нет до перезапуска.
    func отметитьНетСервера() {
        нетСервера = true
        сведения = nil
    }

    /// left из ответа start — «Осталось примерок сегодня».
    func осталось(_ число: Int) {
        guard var с = сведения else { return }
        с.осталось = max(0, число)
        if с != сведения { сведения = с }
    }
}
