import Foundation
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ЗАПРОСЫ И ДАННЫЕ (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ — 5 разных фото, и ИИ
 сам собрал 3D любой вещи или авто»; раньше — «чтобы по-настоящему по камере показывал объект в примерке»).

 Продавец обходит вещь или машину и снимает 5 ракурсов: спереди, 45° спереди-слева, сбоку, 45° сзади-слева, сзади. Каждый
 кадр вырезается на телефоне общим движком студии (ВырезкаПредмета, PhotoStudioEngine.swift) и уходит на сервер; ИИ на
 сервере собирает по ним 3D-модель (image-to-3D по нескольким ракурсам). Даже без модели ракурсы остаются у объявления —
 покупатель листает их пальцем как поворот (360°-обзор). Договор — docs/SERVER_3D.md:
   · GET  /api/model3d.php?action=info&lang= → {ok, on, auth, build, ai, left, limit, kinds, sections, max_px, originals};
   · POST action=upload_angle {csrf, lang, draft_id, kind, index, view, image, cut[, photo]} → {ok, url};
   · POST action=start {csrf, lang, draft_id, kind, angles[5][, dims][, hint]} → {ok, job, left?, eta?};
   · POST action=status {csrf, job, lang} → {ok, state, progress, stage, usdz, glb, poster, w_cm, h_cm, d_cm};
   · POST action=attach {csrf, lang, draft_id, listing_id} → {ok} — ракурсы и модель черновика переходят к объявлению;
   · POST action=delete {csrf, job | draft_id | listing_id} → {ok}.
 Транспорт — как у ИИ-фото и примерочной: КабинетСайта.вызвать (страница сайта или нативная сессия с теми же куками и
 настоящими Origin/Referer), токен страницы и один повтор на «csrf», пути от корня. Подставных заголовков нет.

 🔴 УПРАВЛЯЕТ СЕРВЕР. Config.обзор3D = false — ни кнопки, ни запросов. Включён — кнопка «3D-обзор · 5 фото» в шаге «Фото»
 только после info с on:true, когда раздел объявления — в sections (или в своём списке приложения). build:false —
 ракурсы снимаются и уходят (360°), а сборки ИИ нет. Сервер не умеет (404, перенаправление, не JSON, unsupported) —
 кнопки нет до перезапуска; on:false — до следующего info (не чаще раза в 10 минут).
 🔴 АДРЕСА. Только https на kliko.kz и поддоменах (ХодПримерочной.адрес); файл модели качается отдельной сессией
 общего кэша моделей в Caches (КэшОбъёма; Model3DPreview.swift).
 🔴 ЦИФРОВОЕ. Ни цен, ни покупки на сайте: на limit — своя фраза приложения (цифровое — только App Store).
 */
extension Config {
    /// 3D-обзор в подаче: 5 ракурсов с вырезкой на телефоне и сборка 3D-модели ИИ на сервере. Включён, но управляет
    /// СЕРВЕР: кнопки нет, пока /api/model3d.php?action=info не ответит on:true (docs/SERVER_3D.md). false — ни кнопки,
    /// ни запросов. Камера уже объяснена в project.yml (фото для объявления).
    static let обзор3D = true
}

// MARK: - Вид и ракурсы

/// Что снимают: вещь (обход вокруг стола или пола) или машину (обход вокруг машины). kind в запросах.
enum ВидОбзора3DПодачи: String, Equatable, Sendable {
    case вещь = "item"
    case машина = "car"
}

/// Пять ракурсов обхода — по порядку съёмки. Углы — вид сверху, от лица вещи против часовой стрелки (обход влево).
enum РакурсОбзора3DПодачи: Int, CaseIterable, Identifiable, Sendable {
    case спереди = 0
    case спередиСлева = 1
    case сбоку = 2
    case сзадиСлева = 3
    case сзади = 4

    var id: Int { rawValue }

    static let всего = 5

    /// view в upload_angle и в имени файла.
    var ключ: String {
        switch self {
        case .спереди: return "front"
        case .спередиСлева: return "front_left"
        case .сбоку: return "left"
        case .сзадиСлева: return "back_left"
        case .сзади: return "back"
        }
    }

    /// Угол обхода, градусы: 0 — спереди, 180 — сзади.
    var угол: Double { Double(rawValue) * 45 }

    /// Номер шага для человека: 1…5.
    var номер: Int { rawValue + 1 }

    /// Ключ подписи ракурса (Обзор3DПодачиText).
    var ключТекста: String { "m3_view_" + ключ }

    var следующий: РакурсОбзора3DПодачи? { РакурсОбзора3DПодачи(rawValue: rawValue + 1) }
}

// MARK: - Разделы

/**
 Где кнопка «3D-обзор», пока сервер не прислал свой список (sections в info, по видам). Ключи — дерева сайта
 (РазделыСайта). Сначала проверяется машина, потом вещь. Плоское и живое (ковры, одежда на вешалке, продукты, животные,
 недвижимость, услуги) — не по умолчанию: сервер может включить его, назвав ветку в sections.
 */
enum РазделыОбзора3DПодачи {
    /// Обход вокруг машины: легковые, мото, спецтехника, лодки, трактора.
    static let веткиМашины: Set<String> = ["cars", "motorcycles", "trucks-special", "water-transport", "farm-tractors"]
    /// Самокаты лежат в мото, но снимаются как вещь.
    static let кромеМашины: Set<String> = ["e-scooters"]
    /// Вещи: техника и электроника, мебель, свет, посуда и декор, инструмент, обувь, сумки, украшения и часы, детское
    /// (игрушки, коляски, мебель), спорт, инструменты музыки и коллекции, запчасти и диски, техника красоты, духи, очки.
    static let веткиВещи: Set<String> = [
        "electronics", "furniture", "appliances", "lighting", "kitchenware", "decor-items", "tools", "power-tools",
        "garden-tools", "lawn-mowers", "shoes", "bags-accessories", "jewelry", "toys", "strollers-carseats",
        "kids-furniture", "kids-sports", "school-backpacks", "sport", "musical-instruments", "antiques",
        "model-making", "handmade", "auto-parts", "beauty-appliances", "beauty-perfume", "beauty-optics",
        "pet-accessories", "farm-tools", "bee-hives", "e-scooters"
    ]
    /// Внутри веток вещей — то, что вокруг не обходят: спортпит и масла.
    static let кромеВещи: Set<String> = ["sports-nutrition", "auto-oils"]

    /// Вид съёмки для раздела объявления; nil — кнопки нет. свои — sections сервера по видам (пусто — список приложения).
    static func вид(_ раздел: String, сведения: СведенияОбзора3DПодачи?) -> ВидОбзора3DПодачи? {
        let чистый = раздел.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return nil }
        if подходит(чистый, свои: сведения?.разделыВида(.машина) ?? [], ветки: веткиМашины, кроме: кромеМашины) {
            return .машина
        }
        if подходит(чистый, свои: сведения?.разделыВида(.вещь) ?? [], ветки: веткиВещи, кроме: кромеВещи) {
            return .вещь
        }
        return nil
    }

    /// Список сервера заменяет свой целиком (исключения приложения на него не действуют: сервер назвал — значит, можно).
    private static func подходит(_ раздел: String, свои: Set<String>, ветки: Set<String>, кроме: Set<String>) -> Bool {
        if !свои.isEmpty { return РазделыСайта.внутри(раздел, свои) }
        return РазделыСайта.внутри(раздел, ветки) && !РазделыСайта.внутри(раздел, кроме)
    }
}

// MARK: - Ответы

/// Ответ action=info. Поля необязательные: лишнее, что сервер добавит потом, не мешает.
struct СведенияОбзора3DПодачи: Equatable {
    /// on — 3D-обзор включён на сервере. Только явное on:true: нет поля — выключен (кнопкой управляет сервер).
    var вкл = false
    /// auth — запрос с сессией вошедшего.
    var вошёл = false
    /// build — ИИ собирает модель. false — только ракурсы (360°). Нет поля — как on.
    var сборка = false
    /// ai — кто соберёт модель: «Kliko AI · Tripo», «Kliko AI · Meshy»… Его называет согласие перед первой сборкой.
    var ии = ""
    /// left / limit — сколько сборок осталось сегодня и сколько всего; nil — сервер не сказал.
    var осталось: Int? = nil
    var лимит: Int? = nil
    /// kinds — какие виды сервер принимает: item, car. Нет поля — оба.
    var виды: Set<String> = [ВидОбзора3DПодачи.вещь.rawValue, ВидОбзора3DПодачи.машина.rawValue]
    /// sections по видам: {"item": [...], "car": [...]}; нет вида — список приложения.
    var разделыВидов: [String: Set<String>] = [:]
    /// max_px — длинная сторона ракурса; по умолчанию 1280, от 640 до 2048.
    var сторона = 1280
    /// originals — сервер берёт и исходный JPEG ракурса (photo в upload_angle): помогает текстуре модели.
    var исходники = false

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        вкл = A.да(j["on"])
        вошёл = j["auth"] == nil || A.да(j["auth"])
        сборка = j["build"] == nil ? вкл : A.да(j["build"])
        ии = A.строка(j["ai"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if j["left"] != nil { осталось = max(0, A.целое(j["left"])) }
        if j["limit"] != nil { лимит = max(0, A.целое(j["limit"])) }
        let пикселей = A.целое(j["max_px"])
        if пикселей > 0 { сторона = min(2048, max(640, пикселей)) }
        исходники = A.да(j["originals"])
        if let перечень = j["kinds"] as? [Any] {
            виды = Set(перечень.map { A.строка($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
        }
        if let объект = j["sections"] as? [String: Any] {
            for (вид, значение) in объект {
                let ключВида = вид.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !ключВида.isEmpty else { continue }
                var список: Set<String> = []
                for элемент in (значение as? [Any]) ?? [] {
                    let ключ = A.строка(элемент).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ключ.isEmpty { список.insert(ключ) }
                }
                разделыВидов[ключВида] = список
            }
        }
    }

    func умеет(_ вид: ВидОбзора3DПодачи) -> Bool { виды.contains(вид.rawValue) }

    func разделыВида(_ вид: ВидОбзора3DПодачи) -> Set<String> { разделыВидов[вид.rawValue] ?? [] }

    /// Сборку ИИ можно начать: сервер собирает и лимит не исчерпан (left:0 — нет).
    var сборкаВозможна: Bool { сборка && осталось != 0 }
}

/// Ответ action=status.
struct ХодОбзора3DПодачи: Equatable {
    enum Состояние: String {
        case queued, working, done, failed
    }

    var состояние: Состояние = .working
    /// progress 0…100.
    var прогресс = 0
    /// stage — машинный этап (queue, mesh, texture, convert); подпись — своя (Обзор3DПодачиText).
    var этап = ""
    /// Файлы модели при done — только https на kliko.kz и поддоменах.
    var usdz: URL? = nil
    var glb: URL? = nil
    var постер: URL? = nil

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        состояние = Состояние(rawValue: A.строка(j["state"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? .working
        прогресс = min(100, max(0, A.целое(j["progress"])))
        этап = A.строка(j["stage"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        /* Файлы — в корне ответа или в объекте model3d того же вида, что у api/listings.php. */
        let модель = (j["model3d"] as? [String: Any]) ?? j
        usdz = ХодПримерочной.адрес(A.строка(модель["usdz"]))
        glb = ХодПримерочной.адрес(A.строка(модель["glb"]))
        постер = ХодПримерочной.адрес(A.строка(модель["poster"]))
    }
}

/// Отказ: код сервера и готовый текст.
struct ОтказОбзора3DПодачи: Equatable {
    let код: String
    let текст: String
    /// Номер ракурса из bad_photo.index (0…4) — какой кадр переснять; сервер не прислал — nil.
    let ракурс: Int?

    init(код: String, текст: String, ракурс: Int? = nil) {
        self.код = код
        self.текст = текст
        self.ракурс = ракурс
    }

    /// «Переснять» поможет: сервер не принял ракурс (не та вещь, люди, темно).
    var переснять: Bool { код == "bad_photo" }

    /// «Повторить» может помочь: ИИ занят, сеть, сбой. Лимит, запрет, плохое фото — нет.
    var повторить: Bool { !["limit", "not_allowed", "bad_photo", "gone", "need_angles"].contains(код) }
}

// MARK: - Запросы

@MainActor
enum Обзор3DПодачиAPI {
    enum Ответ {
        case готово([String: Any])
        case отказ(ОтказОбзора3DПодачи)
        case нуженВход
        /// Сервер не умеет (404/405/410/501, unsupported) — «3D-обзор скоро заработает».
        case нетСервера
        case сеть
        /// Нет токена, 5xx, не JSON (портал Wi-Fi, страница защиты сайта), перенаправление и прочее — «Не получилось».
        case сбой
    }

    enum ИтогСведений {
        case есть(СведенияОбзора3DПодачи)
        case нетСервера
        case сеть
    }

    private static let путь = "/api/model3d.php?action="

    private static var язык: String { Обзор3DПодачиText.язык }

    /// GET info. 404/405/410/501, перенаправление, не JSON, unsupported — сервера нет; 5xx, 429 и 403 (лимит запросов,
    /// защита сайта), ok:false без unsupported, обрыв — сеть: временное, спросим через 10 минут.
    static func сведения() async -> ИтогСведений {
        typealias A = МоиОбъявленияAPI
        let ответ: КабинетСайта.Ответ
        do {
            ответ = try await КабинетСайта.вызвать(путь + "info&lang=" + язык, отКорня: true)
        } catch {
            return .сеть
        }
        let код = ответ.код
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
        guard код > 0, код < 500, код != 429, код != 403 else { return .сеть }
        guard let j = ответ.json else { return .нетСервера }
        if A.строка(j["error"]) == "unsupported" || A.строка(j["code"]) == "unsupported" { return .нетСервера }
        if A.да(j["ok"]) { return .есть(СведенияОбзора3DПодачи(j)) }
        if A.нетСессии(j) || A.строка(j["code"]) == "auth" {
            /* Сервер не ответил гостю сведениями — on:true он не сказал: у гостя кнопки нет (подача и так просит вход). */
            var гость = СведенияОбзора3DПодачи()
            гость.вошёл = false
            return .есть(гость)
        }
        if j["ok"] != nil { return .сеть }
        return .нетСервера
    }

    /**
     POST upload_angle — один ракурс черновика. картинка — data URL: PNG с прозрачностью (вырезан) или JPEG (вырезать не
     вышло, cut:false — фон уберёт сервер). исходник — JPEG без вырезки, только если info сказал originals:true.
     */
    static func загрузитьРакурс(черновик: String, вид: ВидОбзора3DПодачи, ракурс: РакурсОбзора3DПодачи,
                                картинка: String, вырезан: Bool, исходник: String?) async -> Ответ {
        var тело: [String: Any] = ["lang": язык, "draft_id": черновик, "kind": вид.rawValue, "index": ракурс.rawValue,
                                   "view": ракурс.ключ, "image": картинка, "cut": вырезан]
        if let исходник, !исходник.isEmpty { тело["photo"] = исходник }
        return await выполнить("upload_angle", тело)
    }

    /// POST start — собрать модель по 5 ракурсам. ракурсы — адреса из upload_angle по порядку обхода. габариты — Ш×В×Г
    /// вещи в см (масштаб модели), если продавец их указал. подсказка — раздел, название, марка и модель (у машины).
    static func начать(черновик: String, вид: ВидОбзора3DПодачи, ракурсы: [String],
                       габариты: (ширина: Int, высота: Int, глубина: Int)?, подсказка: [String: String]) async -> Ответ {
        var тело: [String: Any] = ["lang": язык, "draft_id": черновик, "kind": вид.rawValue, "angles": ракурсы]
        if let г = габариты { тело["dims"] = ["w": г.ширина, "h": г.высота, "d": г.глубина] }
        let чистая = подсказка.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !чистая.isEmpty { тело["hint"] = чистая }
        return await выполнить("start", тело)
    }

    /// POST status. failed приходит с ok:true — его разбирает хранилище (разобратьОтказ).
    static func ход(_ задача: String) async -> Ответ {
        await выполнить("status", ["job": задача, "lang": язык])
    }

    /// POST attach — ракурсы и модель черновика переходят к объявлению (после публикации или «Сохранить в объявление» в
    /// правке). Модель ещё собирается — сервер привяжет её, когда соберёт.
    static func привязать(черновик: String, объявление: String) async -> Ответ {
        await выполнить("attach", ["lang": язык, "draft_id": черновик, "listing_id": объявление])
    }

    /// POST delete: задача (сборка и её модель), весь черновик (ракурсы и модель) или 3D-обзор объявления. true — удалено
    /// (или его уже нет).
    static func удалить(задача: String = "", черновик: String = "", объявление: String = "") async -> Bool {
        var тело: [String: Any] = ["lang": язык]
        if !задача.isEmpty { тело["job"] = задача }
        if !черновик.isEmpty { тело["draft_id"] = черновик }
        if !объявление.isEmpty { тело["listing_id"] = объявление }
        guard тело.count > 1 else { return true }
        switch await выполнить("delete", тело) {
        case .готово:
            return true
        case .отказ(let отказ):
            return отказ.код == "gone"
        case .нуженВход, .нетСервера, .сеть, .сбой:
            return false
        }
    }

    /**
     POST {csrf, …} тем же путём, что действия кабинета; «csrf» — свежая страница и один повтор (как у ИИ-фото). Повторов
     при сбое сети нет: запись могла дойти.
     */
    private static func выполнить(_ действие: String, _ тело: [String: Any]) async -> Ответ {
        typealias A = МоиОбъявленияAPI
        var повторили = false
        while true {
            let ответ: КабинетСайта.Ответ
            do {
                let токен = try await A.токенСейчас()
                if токен.isEmpty { return .нуженВход }
                var полное = тело
                полное["csrf"] = токен
                ответ = try await КабинетСайта.вызвать(путь + действие, метод: "POST", тело: полное, отКорня: true)
            } catch let сбой as КабинетСайта.Сбой where сбой == .сеть {
                return .сеть
            } catch {
                return .сбой
            }
            let код = ответ.код
            if [404, 405, 410, 501].contains(код) { return .нетСервера }
            if код == 413 {
                /* Тело больше предела сервера (раздел 0 договора): не «нет сервера», а «ракурс слишком большой». */
                return .отказ(ОтказОбзора3DПодачи(код: "too_big", текст: Обзор3DПодачиText.т("m3_err_big")))
            }
            /* info уже сказал on:true — дальше не JSON (портал Wi-Fi в ТЦ с кодом 200, 403 от защиты сайта на тело в
               3 МБ, 400 от nginx) и перенаправление — сбой, а не «сервера нет»: «нет сервера» выключил бы 3D-обзор до
               перезапуска. «Нет сервера» у действий — только 404/405/410/501 и явный unsupported. */
            guard !(300..<400).contains(код), let j = ответ.json else { return .сбой }
            if A.строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            if A.да(j["ok"]) { return .готово(j) }
            return разобратьОтказ(j)
        }
    }

    /**
     {ok:false, code, error} у действий, {state:"failed", code, error} у status → что показать. error — готовый текст на
     языке человека; машинный код — своя фраза. limit — всегда своя фраза: текст сервера может звать купить пакет на
     сайте (цифровое в приложении — только App Store, 3.1.1).
     */
    static func разобратьОтказ(_ j: [String: Any]) -> Ответ {
        typealias A = МоиОбъявленияAPI
        let т = Обзор3DПодачиText.т
        let код = A.строка(j["code"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let машинная = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка)
        if код == "unsupported" || ошибка == "unsupported" { return .нетСервера }
        if код == "auth" || A.нетСессии(j) { return .нуженВход }
        let итоговый = код.isEmpty && КабинетСайта.машинныйКод(ошибка) ? ошибка : код
        let текст: String
        switch итоговый {
        case "limit":
            текст = т("m3_limit")
        case "gone":
            текст = т("m3_gone")
        case "need_angles":
            текст = машинная ? т("m3_need_angles") : ошибка
        default:
            текст = машинная ? т("m3_err_fail") : ошибка
        }
        /* bad_photo.index (отчёт сервера 1.12, раздел 8) — номер ракурса: тот кадр помечается «переснимите». */
        var ракурс: Int?
        if итоговый == "bad_photo", let значение = j["index"], !(значение is NSNull) {
            let номер = A.целое(значение)
            if РакурсОбзора3DПодачи(rawValue: номер) != nil { ракурс = номер }
        }
        return .отказ(ОтказОбзора3DПодачи(код: итоговый.isEmpty ? "fail" : итоговый, текст: текст, ракурс: ракурс))
    }
}

// MARK: - Есть ли 3D-обзор

/**
 Что сервер сказал в info — одно на приложение. Спрашивает лениво: шаг «Фото» подачи и окно съёмки; не чаще раза в 10
 минут (и после сбоя сети тоже), после входа и выхода — заново. Сервер не умеет — до перезапуска не спрашиваем. Синглтон
 создаётся пустым и в init ни к кому не обращается.
 */
@MainActor
final class ГотовностьОбзора3DПодачи: ObservableObject {
    static let shared = ГотовностьОбзора3DПодачи()

    @Published private(set) var сведения: СведенияОбзора3DПодачи? = nil
    @Published private(set) var нетСервера = false

    private var когда: Date? = nil
    private var дляСессии = -1
    private var идёт: Task<Void, Never>? = nil

    private init() {}

    /// Вид съёмки для раздела, если кнопка «3D-обзор» сейчас есть: рубильник, сервер сказал on:true, раздел вида и вид
    /// в kinds. nil — кнопки нет.
    func вид(для раздел: String) -> ВидОбзора3DПодачи? {
        guard Config.обзор3D, !нетСервера, let с = сведения, с.вкл,
              let вид = РазделыОбзора3DПодачи.вид(раздел, сведения: с), с.умеет(вид) else { return nil }
        return вид
    }

    /// Сборка ИИ сейчас возможна (build и лимит). Ракурсы снимаются и без неё.
    var сборкаВозможна: Bool {
        guard Config.обзор3D, !нетСервера, let с = сведения, с.вкл else { return false }
        return с.сборкаВозможна
    }

    func проверить() async {
        guard Config.обзор3D, !нетСервера else { return }
        /* смена растёт при любой смене человека (вход, выход, другой аккаунт): сведения у каждого свои (auth, left). */
        let сессия = СессияПриложения.shared.смена
        if дляСессии != сессия && сведения != nil { сведения = nil }
        if let когда, дляСессии == сессия, Date().timeIntervalSince(когда) < 600 { return }
        if let идёт {
            await идёт.value
            return
        }
        let задача = Task { @MainActor in
            let итог = await Обзор3DПодачиAPI.сведения()
            let готовность = ГотовностьОбзора3DПодачи.shared
            готовность.когда = Date()
            готовность.дляСессии = сессия
            switch итог {
            case .есть(let новые):
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

    /// Человек вошёл или сменился: прежние сведения не годятся — спросить заново.
    func устарели() {
        когда = nil
        дляСессии = -1
    }

    /// Сервер ответил «не умею» — кнопки нет до перезапуска.
    func отметитьНетСервера() {
        нетСервера = true
        сведения = nil
    }

    /// left из ответа start — «Осталось сборок сегодня».
    func осталось(_ число: Int) {
        guard var с = сведения else { return }
        с.осталось = max(0, число)
        if с != сведения { сведения = с }
    }
}
