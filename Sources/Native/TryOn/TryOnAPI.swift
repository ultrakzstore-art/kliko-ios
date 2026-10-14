import Foundation
import UIKit
import ImageIO
import Photos
import Vision

/**
 ИИ-ПРИМЕРОЧНАЯ — ЗАПРОСЫ И ДАННЫЕ (владелец 13.10.2026: «примерочная для одежды» → «нужнее охват всего»).

 Три вида ИИ-примерки (kind, ВидИИПримерки в TryOnHub.swift): «Примерить на себя» у одежды — человек снимает себя, и ИИ
 рисует его в этой вещи (person); «На свою машину» у дисков — фото машины сбоку, ИИ меняет колёса (car); «В моей
 комнате» у мебели — фото комнаты, ИИ ставит в неё вещь (room). Рисует Kliko AI (или «Свой ИИ», если его поставщик
 умеет изображения) на сервере ultra-site по договору docs/SERVER_TRYON.md:
   · GET  /api/tryon.php?action=info → {ok, on, auth, ai, own, left, limit, kinds, sections} — есть ли примерочная,
     каких видов, где она и кто обработает фото (его называет согласие перед первой отправкой, App Review 5.1.2(i));
   · POST action=start {csrf, listing_id, kind, photo, photo_index, own, lang[, item_cutout, item_box]} → {ok, job} |
     {ok:false, code, error}; item_cutout — вещь с фото photo_index, уже без фона (вырезка ИИ-студии на телефоне),
     item_box — где она на том фото; оба необязательны (ФотоПримерочной.вырезка, docs/SERVER_TRYON.md, раздел 2а);
   · POST action=status {csrf, job, lang} → {ok, state: queued|working|done|failed, progress, image, error};
   · POST action=delete {csrf, job} → {ok}.
 Транспорт — как у остальных действий кабинета: МоиОбъявленияAPI.отправить (fetch изнутри страницы сайта под слоем, её
 куки и настоящие Origin/Referer, токен страницы и один повтор на «csrf»), пути от корня. Пробу info — сам
 КабинетСайта.вызвать: по коду ответа видно, есть ли такая страница на сервере вообще.

 🔴 УПРАВЛЯЕТ СЕРВЕР. Config.примерочная = false — ни кнопок ИИ, ни запросов. Включён — кнопки ИИ только после
 ответа info с on:true (и вида в kinds); info — не чаще раза в 10 минут. Сервер не умеет (404, перенаправление, не JSON,
 «unsupported») — кнопок ИИ нет до перезапуска; on:false — нет до следующего info; сервер перестал понимать посреди
 примерки — «Примерочная скоро заработает». Способы на телефоне (живая, габариты, авто) от этого не зависят.

 🔴 ФОТО ЧЕЛОВЕКА, МАШИНЫ, КОМНАТЫ. Уходит один раз, в теле start: перерисованным (без EXIF и места съёмки), не больше
 1280 px. На телефоне не пишется ни в файлы, ни в кэш; результат качается эфемерной сессией — без кук и без кэша на диске.
 Окно закрыли — delete на сервер сразу, не дожидаясь суток.
 */
extension Config {
    /// ИИ-примерочная: «Примерить на себя», «На свою машину», «В моей комнате». Включена, но управляет СЕРВЕР: кнопок
    /// нет, пока /api/tryon.php?action=info не ответит on:true (docs/SERVER_TRYON.md); нет адреса или 404 — кнопок нет.
    /// false — ни кнопок ИИ, ни запросов. Тексты разрешений в project.yml (App Review 5.1.1(ii)) о примерке уже говорят:
    /// камера — «примерить вещь на себя или посмотреть, поместится ли она в комнате», Фото — «результат примерки».
    static let примерочная = true

    /// item_cutout в start ИИ-примерки: вещь с фото объявления, вырезанная на телефоне той же вырезкой, что ИИ-студия
    /// подачи (ВырезкаПредмета), и её место на фото (item_box). Поле необязательное (docs/SERVER_TRYON.md, раздел 2а):
    /// сервер может взять её вместо своего удаления фона, сверив с фото объявления, или пропустить. Шлётся только
    /// когда info ответил cutout:true (СведенияПримерочной.вырезка): сервер принял договор и поднял предел тела start.
    /// false — start уходит без неё, как раньше.
    static let вырезкаВещиИИ = true
}

// MARK: - Разделы

/// Где кнопки ИИ, пока сервер не прислал свой список (sections в info, по видам). Ключи — дерева сайта (РазделыСайта).
enum РазделыПримерочной {
    /// «Примерить на себя»: одежда, обувь, сумки и аксессуары, украшения и часы — весь корень «clothing».
    static let ветки: Set<String> = ["clothing"]
    /// Кроме детской одежды и детской обуви (kids-shoes лежит в clothing → shoes): фото детей — особые данные, а модели
    /// изображений правку фото несовершеннолетних не берут. И кроме кошельков: на себе их не примерить — сервер ответил
    /// бы not_clothes уже после съёмки. Вернуть их может только сервер — назвав в sections саму ветку (не «clothing»).
    static let кромеВеток: Set<String> = ["kids-clothing", "kids-shoes", "wallets"]
    /// «На свою машину»: шины и диски (что это диски, а не одни шины, проверяет ПризнакиДисков).
    static let веткиМашины: Set<String> = ["tires-wheels"]
    /// «В моей комнате»: мебель (и детская), телевизоры, ковры, шторы, декор, люстры и светильники.
    static let веткиКомнаты: Set<String> = ["furniture", "kids-furniture", "tv", "carpets", "curtains", "decor-items",
                                            "chandeliers", "lamps"]
    /// Кроме садовой мебели: её ставят во двор, не в комнату.
    static let кромеКомнаты: Set<String> = ["outdoor-furniture"]

    /// Одежда (вид «человек») — как раньше.
    static func подходит(_ раздел: String?, свои: Set<String> = []) -> Bool {
        подходит(раздел, вид: .человек, свои: свои)
    }

    /// Раздел объявления (лист дерева) или его предок — в списке вида. свои — sections сервера для этого вида; пусто —
    /// список приложения.
    static func подходит(_ раздел: String?, вид: ВидИИПримерки, свои: Set<String> = []) -> Bool {
        guard let раздел, !раздел.isEmpty else { return false }
        if !свои.isEmpty {
            guard РазделыСайта.внутри(раздел, свои) else { return false }
            /* Исключения приложения действуют и на список сервера: ["clothing"] не включает детское и кошельки,
               ["furniture"] — садовую мебель. Вернуть ветку сервер может, только назвав её саму или раздел внутри неё. */
            let кроме = исключения(вид)
            return !РазделыСайта.внутри(раздел, кроме) || названаВнутри(раздел, свои: свои, кроме: кроме)
        }
        switch вид {
        case .человек:
            return РазделыСайта.внутри(раздел, ветки) && !РазделыСайта.внутри(раздел, кромеВеток)
        case .машина:
            return РазделыСайта.внутри(раздел, веткиМашины)
        case .комната:
            return РазделыСайта.внутри(раздел, веткиКомнаты) && !РазделыСайта.внутри(раздел, кромеКомнаты)
        }
    }

    /// Исключённые ветки вида.
    private static func исключения(_ вид: ВидИИПримерки) -> Set<String> {
        switch вид {
        case .человек: return кромеВеток
        case .машина: return []
        case .комната: return кромеКомнаты
        }
    }

    /// Сервер сам назвал исключённую ветку или раздел внутри неё — на пути от раздела вверх (kids-shoes, а не shoes).
    private static func названаВнутри(_ раздел: String, свои: Set<String>, кроме: Set<String>) -> Bool {
        var текущий: String? = раздел
        var шаги = 0
        while let т = текущий, шаги < 25 {
            if свои.contains(т) && РазделыСайта.внутри(т, кроме) { return true }
            текущий = РазделыСайта.родитель(т)
            шаги += 1
        }
        return false
    }
}

// MARK: - Ответы

/// Ответ action=info. Поля необязательные: лишнее, что сервер добавит потом, не мешает.
struct СведенияПримерочной: Equatable {
    /// on — примерочная включена на сервере. Только явное on:true: нет поля — выключена (кнопками ИИ управляет сервер).
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
    /// sections для одежды (вид person) — ключи разделов сайта с кнопкой; пусто — список приложения (РазделыПримерочной).
    var разделы: Set<String> = []
    /// sections по видам: {"person": [...], "car": [...], "room": [...]}; нет вида — список приложения.
    var разделыВидов: [String: Set<String>] = [:]
    /// kinds — какие виды умеет сервер. Нет поля — person и виды из sections-объекта (старый сервер — только одежда).
    var виды: Set<String> = [ВидИИПримерки.человек.rawValue]
    /// cutout — сервер принимает item_cutout и item_box в start (и тело start до 4–6 МБ, docs/SERVER_TRYON.md, раздел
    /// 2а). Только явное cutout:true: нет поля — поля не шлём (большое тело старый сервер мог бы отбить 413).
    var вырезка = false

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        вкл = A.да(j["on"])
        вошёл = j["auth"] == nil || A.да(j["auth"])
        ии = A.строка(j["ai"]).trimmingCharacters(in: .whitespacesAndNewlines)
        свойИИ = A.да(j["own"])
        вырезка = A.да(j["cutout"])
        if j["left"] != nil { осталось = max(0, A.целое(j["left"])) }
        if j["limit"] != nil { лимит = max(0, A.целое(j["limit"])) }
        func ключи(_ значение: Any?) -> Set<String> {
            var список: Set<String> = []
            for элемент in (значение as? [Any]) ?? [] {
                let ключ = A.строка(элемент).trimmingCharacters(in: .whitespacesAndNewlines)
                if !ключ.isEmpty { список.insert(ключ) }
            }
            return список
        }
        /* sections — массив (старый договор: только одежда) или объект по видам. */
        var списки: [String: Set<String>] = [:]
        if let массив = j["sections"] as? [Any] {
            списки[ВидИИПримерки.человек.rawValue] = ключи(массив)
        } else if let объект = j["sections"] as? [String: Any] {
            for (вид, значение) in объект {
                let ключВида = вид.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !ключВида.isEmpty { списки[ключВида] = ключи(значение) }
            }
        }
        разделыВидов = списки
        разделы = списки[ВидИИПримерки.человек.rawValue] ?? []
        if let перечень = j["kinds"] as? [Any] {
            виды = Set(перечень.map { A.строка($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
        } else {
            виды = Set([ВидИИПримерки.человек.rawValue]).union(списки.keys)
        }
    }

    /// Сервер умеет этот вид.
    func умеет(_ вид: ВидИИПримерки) -> Bool { виды.contains(вид.rawValue) }

    /// sections сервера для вида; пусто — список приложения.
    func разделыВида(_ вид: ВидИИПримерки) -> Set<String> {
        разделыВидов[вид.rawValue] ?? []
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

    /// GET info. 404/405/410/501, перенаправление, не JSON, unsupported — сервера нет; 5xx, 429 и 403 (лимит запросов,
    /// защита сайта), ok:false без unsupported и auth, обрыв — сеть: временное, спросим через 10 минут.
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
        guard код > 0, код < 500, код != 429, код != 403 else { return .сеть }
        guard let j = ответ.json else { return .нетСервера }
        if A.строка(j["error"]) == "unsupported" || A.строка(j["code"]) == "unsupported" { return .нетСервера }
        if A.да(j["ok"]) { return .есть(СведенияПримерочной(j)) }
        if A.нетСессии(j) {
            /* Сервер не ответил гостю сведениями — on:true он не сказал, значит, кнопок ИИ у гостя нет (договор: гостю —
               тот же ответ с auth:false). После входа info спросим заново. */
            var гость = СведенияПримерочной()
            гость.вкл = false
            гость.вошёл = false
            return .есть(гость)
        }
        /* ok:false с другой ошибкой («rate», временный сбой) — страница есть, она просто сейчас не ответила. */
        if j["ok"] != nil { return .сеть }
        return .нетСервера
    }

    /// POST start. own — у человека включён «Свой ИИ» (как own:1 у recognize); решает сервер. kind — что рисовать:
    /// person (человек в вещи), car (машина с дисками), room (комната с вещью). вырезка — item_cutout и item_box: вещь
    /// с фото номерФото без фона; nil — полей нет (не вышла, на фото человек, рубильник).
    static func начать(товар: String, фото: String, номерФото: Int, свой: Bool,
                       вид: ВидИИПримерки = .человек, вырезка: ФотоПримерочной.Вырезка? = nil) async -> Ответ {
        var тело: [String: Any] = ["listing_id": товар, "kind": вид.rawValue, "photo": фото, "photo_index": номерФото,
                                   "lang": ПримерочнаяText.язык]
        if свой { тело["own"] = 1 }
        if Config.вырезкаВещиИИ, let вырезка {
            тело["item_cutout"] = вырезка.адрес
            тело["item_box"] = вырезка.рамка
        }
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
        /// Vision нашёл человека (у машины и комнаты — людей); nil — не знаем (не мешаем отправке).
        let человек: Bool?
    }

    enum ИтогСохранения: Sendable {
        case готово
        case нетДоступа
        case сбой
    }

    /// item_cutout и item_box для start (docs/SERVER_TRYON.md, раздел 2а).
    struct Вырезка: Sendable {
        /// «data:image/png;base64,…»: вещь без фона (прозрачность), обрезана по ней с полем 3 %, сторона ≤ 1024 px.
        let адрес: String
        /// Где вырезка лежит на фото объявления (повёрнутом прямо): x, y, ширина, высота — доли, начало сверху слева.
        let рамка: [Double]
    }

    /// Предел строки item_cutout (байты data URL): вместе с фото (до ~1 МБ в base64) тело start остаётся меньше 4 МБ.
    private static let пределВырезки = 1_400_000

    /// Без кук и без кэша на диске: результат — фото человека, ему нечего делать в URLCache.
    private static let сессия = URLSession(configuration: .ephemeral)

    /**
     Фото вещи из объявления → item_cutout: та же вырезка, что у ИИ-студии подачи (ВырезкаПредмета, поле 3 %), PNG с
     прозрачностью. Не больше пределВырезки: крупнее — ужимается до трёх раз по 0,75. nil — рубильник выключен, на фото
     лицо (вещь на человеке: вырезался бы человек, а не вещь), предмет не отделился, задачу отменили. Не на главной
     нити — её зовут из Task.detached.
     */
    static func вырезка(_ фото: UIImage) -> Вырезка? {
        guard Config.вырезкаВещиИИ, let кадр = ВырезкаЖивойПримерки.кадр(фото), !Task.isCancelled,
              !ВырезкаЖивойПримерки.естьЛицо(кадр), !Task.isCancelled,
              let вырезанное = ВырезкаПредмета.вырезатьСРамкой(кадр, поле: 0.03) else { return nil }
        let ш = вырезанное.размер.width
        let в = вырезанное.размер.height
        guard ш > 0, в > 0 else { return nil }
        func доля(_ значение: CGFloat, _ из: CGFloat) -> Double { (Double(значение / из) * 10_000).rounded() / 10_000 }
        let р = вырезанное.рамка
        let рамка = [доля(р.minX, ш), доля(р.minY, в), доля(р.width, ш), доля(р.height, в)]
        var картинка = вырезанное.картинка
        for _ in 0..<4 {
            guard !Task.isCancelled, let png = UIImage(cgImage: картинка).pngData() else { return nil }
            let адрес = "data:image/png;base64," + png.base64EncodedString()
            if адрес.utf8.count <= пределВырезки { return Вырезка(адрес: адрес, рамка: рамка) }
            guard let меньше = ужать(картинка, доля: 0.75) else { return nil }
            картинка = меньше
        }
        return nil
    }

    /// Картинка с прозрачностью, меньше в `доля` раз по каждой стороне.
    private static func ужать(_ картинка: CGImage, доля: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(картинка.width) * доля).rounded()))
        let h = max(1, Int((CGFloat(картинка.height) * доля).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.interpolationQuality = .high
        к.draw(картинка, in: CGRect(x: 0, y: 0, width: w, height: h))
        return к.makeImage()
    }

    /// Снимок или файл галереи → длинная сторона ≤ 1280, белая подложка, JPEG 0,82. Рисуется заново: поворот учтён,
    /// EXIF и место съёмки не уходят. Слишком маленькое или битое — nil. вид — кого искать Vision: человека во весь рост
    /// (одежда) или любых людей и лица (машина, комната — там их быть не должно).
    static func подготовить(_ данные: Data, вид: ВидИИПримерки = .человек) -> Готовое? {
        /* Уменьшаем уже при чтении (ImageIO): фото 24–48 Мп из галереи не разворачивается в полный битмап на сотни МБ
           ради 1280 px. Поворот из EXIF учтён; маленькое фото не растягивается. */
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, чтение) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: 1280] as CFDictionary
        guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры) else { return nil }
        return подготовить(UIImage(cgImage: кадр), вид: вид)
    }

    static func подготовить(_ снимок: UIImage, вид: ВидИИПримерки = .человек) -> Готовое? {
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
        let люди = вид.безЛюдей ? естьЛюди(готовый) : естьЧеловек(готовый)
        return Готовое(адрес: адрес, jpeg: jpeg, человек: люди)
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

    /// Люди в кадре машины или комнаты: хоть верх тела или лицо. Только подсказка «лучше без людей» — решает сервер
    /// (размоет или откажет). Лица не распознаются — только «есть ли».
    static func естьЛюди(_ картинка: UIImage) -> Bool? {
        guard let кадр = картинка.cgImage else { return nil }
        let тела = VNDetectHumanRectanglesRequest()
        тела.upperBodyOnly = true
        let лица = VNDetectFaceRectanglesRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([тела, лица])
        } catch {
            return nil
        }
        return !(тела.results ?? []).isEmpty || !(лица.results ?? []).isEmpty
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
 Что сервер сказал в info — одно на приложение. Спрашивает лениво: кнопки на странице объявления, у которого может быть
 способ ИИ, и окно примерочной; не чаще раза в 10 минут (и после сбоя сети тоже), после входа и выхода — заново. Сервер
 не умеет — до перезапуска не спрашиваем. Синглтон создаётся пустым и в init ни к кому не обращается.
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
        можно(товар, вид: .человек)
    }

    /// Кнопка ИИ этого вида у объявления сейчас: рубильник, сервер сказал on:true и умеет вид, раздел вида, есть фото.
    func можно(_ товар: Listing, вид: ВидИИПримерки) -> Bool {
        guard Config.примерочная, !нетСервера, let с = сведения, с.вкл, с.умеет(вид),
              !товар.фотоАдреса.isEmpty else { return false }
        return РазделыПримерочной.подходит(товар.категория, вид: вид, свои: с.разделыВида(вид))
    }

    /// Может ли кнопка этого вида появиться — без сети: рубильник, сервер не отказал, раздел вида (по sections сервера,
    /// если они уже известны), есть фото. По нему решается, ставить ли кнопки и спрашивать ли info.
    func возможно(_ товар: Listing, вид: ВидИИПримерки) -> Bool {
        guard Config.примерочная, !нетСервера, !товар.фотоАдреса.isEmpty else { return false }
        return РазделыПримерочной.подходит(товар.категория, вид: вид, свои: сведения?.разделыВида(вид) ?? [])
    }

    func проверить() async {
        guard Config.примерочная, !нетСервера else { return }
        /* смена растёт при любой смене человека (вход, выход, другой аккаунт): сведения у каждого свои (auth, left). */
        let сессия = СессияПриложения.shared.смена
        if дляСессии != сессия && сведения != nil {
            /* Сменился человек: сведения прежнего (on, auth, left) ему не годятся — до нового ответа кнопок ИИ нет. */
            сведения = nil
        }
        /* Не чаще раза в 10 минут для того же человека — и после ответа, и после сбоя сети (info не дёргаем с каждой
           страницы объявления). Сменился человек — спрашиваем сразу. */
        if let когда, дляСессии == сессия, Date().timeIntervalSince(когда) < 600 { return }
        if let идёт {
            await идёт.value
            return
        }
        let задача = Task { @MainActor in
            let итог = await ПримерочнаяAPI.сведения()
            let готовность = ГотовностьПримерочной.shared
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
