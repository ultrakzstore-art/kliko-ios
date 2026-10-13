import Foundation
import UIKit

/**
 ИИ-ФОТО — ЗАПРОСЫ И ДАННЫЕ (договор docs/SERVER_AI_IMAGE.md; рубильник Config.ииРедакторФото, AIImageConfig.swift).

   · GET  /api/ai_image.php?action=info&lang= → {ok, on, auth, modes, ai, ai_text, own, left, limit, text_left,
     text_limit, prompt_max, max_illustrations, edited_is_real, types} — есть ли генератор, что можно и кто обработает;
   · POST action=start {csrf, lang, mode, thread, prompt, preset, category, cond, photo, photo_url, base_image, want, own}
     → {ok, job, thread, left?, text_left?, eta?} | {ok:false, code, error};
   · POST action=status {csrf, job, lang} → {state, progress, stage, caption, image, image_id, image_kind, draft,
     changed, note, own_ai_run, left, text_left} (failed — с code и error);
   · POST action=history {csrf, thread, lang} → {turns, draft, accepted, expires};
   · POST action=accept {csrf, lang, image_id, photo, thumb, poster} → {ok, url, thumb, ai} — как upload_photo;
   · POST action=accept_draft {csrf, thread, lang} → {ok, draft_id, fields, unsure, highlights};
   · POST action=delete {csrf, thread} → {ok}.
 Транспорт — как у остальных действий кабинета: КабинетСайта.вызвать изнутри страницы сайта (её куки, настоящие
 Origin/Referer), токен страницы (МоиОбъявленияAPI.токенСейчас) и один повтор на «csrf», пути от корня. Код ответа
 смотрим сами: 404/405/410/501, перенаправление и не JSON — «сервер не умеет» и посреди диалога.

 🔴 ТЕКСТЫ СЕРВЕРА. error, caption, note — готовые, на языке человека: показываются как есть; машинный код — своя фраза.
 limit — всегда своя фраза: текст сервера может звать купить пакет на сайте (цифровое в приложении — только App Store).
 🔴 КАРТИНКИ. Только https на kliko.kz и поддоменах; качаются отдельной сессией без кук и без кэша на диске. Фото вещи
 для правки рисуется заново (EXIF и место съёмки не уходят), длинная сторона ≤ 1280.
 */

// MARK: - Виды объявлений и правила

/// Что можно для вида объявления (types[…] в info). Нет ключа — умолчания приложения (те же, что в примере договора).
struct ПравилаВидаИИФото: Equatable {
    var черновик = true
    var иллюстрация = true
    var правка = true
    /// require_real_photo: при иллюстрации нужно хотя бы одно настоящее фото.
    var нужноНастоящее = false

    /// Ключи видов договора по порядку.
    static let все = ["goods_new", "goods_used", "rentgood", "services", "transport", "realty", "jobs"]

    static func умолчание(_ вид: String) -> ПравилаВидаИИФото {
        switch вид {
        case "goods_used", "rentgood":
            return ПравилаВидаИИФото(черновик: true, иллюстрация: true, правка: true, нужноНастоящее: true)
        case "transport":
            return ПравилаВидаИИФото(черновик: true, иллюстрация: false, правка: true, нужноНастоящее: true)
        case "realty":
            return ПравилаВидаИИФото(черновик: false, иллюстрация: false, правка: false, нужноНастоящее: true)
        case "jobs":
            return ПравилаВидаИИФото(черновик: false, иллюстрация: false, правка: false, нужноНастоящее: false)
        default:
            return ПравилаВидаИИФото(черновик: true, иллюстрация: true, правка: true, нужноНастоящее: false)
        }
    }
}

// MARK: - Ответы

/// Ответ action=info. Поля необязательные: лишнее, что сервер добавит потом, не мешает.
struct СведенияИИФото: Equatable {
    /// on — генератор включён. Нет поля при ok:true — включён.
    var вкл = false
    /// auth — запрос с сессией вошедшего; гостю кнопки есть, окно сначала просит войти.
    var вошёл = false
    /// modes — какие режимы включены; нет поля — оба.
    var режимЧерновик = true
    var режимПравка = true
    /// ai — кто обработает фото и нарисует картинки; ai_text — кто пишет текст черновика (нет — тот же ai).
    var ии = ""
    var ииТекста = ""
    /// own — хоть одна часть пойдёт через «Свой ИИ» человека.
    var свойИИ = false
    /// left / limit — картинки на сегодня; text_left / text_limit — ходы только с текстом. nil — сервер не сказал.
    var осталось: Int? = nil
    var лимит: Int? = nil
    var текстОсталось: Int? = nil
    var текстЛимит: Int? = nil
    /// prompt_max — предел сообщения человека.
    var пределТекста = 500
    /// max_illustrations — иллюстраций ИИ в одном объявлении.
    var иллюстрацийМакс = 1
    /// edited_is_real — фото с правкой ИИ считается настоящим для require_real_photo.
    var правкаНастоящая = true
    var виды: [String: ПравилаВидаИИФото] = [:]

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        вкл = j["on"] == nil || A.да(j["on"])
        вошёл = j["auth"] == nil || A.да(j["auth"])
        if let режимы = j["modes"] as? [Any] {
            let список = Set(режимы.map { A.строка($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            режимЧерновик = список.contains("draft")
            режимПравка = список.contains("edit")
        }
        ии = A.строка(j["ai"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let текста = A.строка(j["ai_text"]).trimmingCharacters(in: .whitespacesAndNewlines)
        ииТекста = текста.isEmpty ? ии : текста
        свойИИ = A.да(j["own"])
        if j["left"] != nil { осталось = max(0, A.целое(j["left"])) }
        if j["limit"] != nil { лимит = max(0, A.целое(j["limit"])) }
        if j["text_left"] != nil { текстОсталось = max(0, A.целое(j["text_left"])) }
        if j["text_limit"] != nil { текстЛимит = max(0, A.целое(j["text_limit"])) }
        let предел = A.целое(j["prompt_max"])
        if предел > 0 { пределТекста = min(предел, 2000) }
        if j["max_illustrations"] != nil { иллюстрацийМакс = max(0, A.целое(j["max_illustrations"])) }
        if j["edited_is_real"] != nil { правкаНастоящая = A.да(j["edited_is_real"]) }
        if let виды = j["types"] as? [String: Any] {
            for (ключ, значение) in виды {
                guard let з = значение as? [String: Any] else { continue }
                var п = ПравилаВидаИИФото.умолчание(ключ)
                if з["draft"] != nil { п.черновик = A.да(з["draft"]) }
                if з["illustration"] != nil { п.иллюстрация = A.да(з["illustration"]) }
                if з["edit"] != nil { п.правка = A.да(з["edit"]) }
                if з["require_real_photo"] != nil { п.нужноНастоящее = A.да(з["require_real_photo"]) }
                self.виды[ключ] = п
            }
        }
    }

    func правила(_ вид: String) -> ПравилаВидаИИФото { виды[вид] ?? ПравилаВидаИИФото.умолчание(вид) }

    /// «Объявление по названию» есть, если режим включён и черновик можно хоть у одного вида (вид до ответа ИИ не известен).
    var черновикГдеНибудь: Bool {
        режимЧерновик && ПравилаВидаИИФото.все.contains { правила($0).черновик }
    }
}

/// Характеристика черновика: слот схемы раздела (cpu, gpu, ram, storage, year), подпись на языке человека и значение.
struct ХарактеристикаИИФото: Equatable, Hashable {
    let ключ: String
    let подпись: String
    let значение: String
}

/// Подсказка цены черновика (в тенге). рынок — по похожим объявлениям Kliko, иначе оценка ИИ.
struct ЦенаИИФото: Equatable {
    let низ: Int
    let середина: Int
    let верх: Int
    let рынок: Bool
}

/// draft из status и history — весь черновик диалога. Пустой (ни названия, ни описания, ни характеристик) — nil.
struct ЧерновикИИФото: Equatable {
    var название = ""
    var марка = ""
    var раздел = ""
    var состояние = ""
    var описание = ""
    var характеристики: [ХарактеристикаИИФото] = []
    var неуверенные: Set<String> = []
    var главное: [String] = []
    var цена: ЦенаИИФото? = nil

    init?(_ значение: Any?) {
        typealias A = МоиОбъявленияAPI
        guard let j = значение as? [String: Any] else { return nil }
        func чисто(_ поле: String) -> String { A.строка(j[поле]).trimmingCharacters(in: .whitespacesAndNewlines) }
        название = String(чисто("title").prefix(ПределыПодачи.название))
        марка = String(чисто("brand").prefix(ПределыПодачи.короткое))
        раздел = чисто("category")
        let сост = чисто("cond")
        состояние = ["new", "used"].contains(сост) ? сост : ""
        описание = String(чисто("description").prefix(3000))
        for элемент in (j["specs"] as? [Any]) ?? [] {
            guard let с = элемент as? [String: Any] else { continue }
            let ключ = A.строка(с["k"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let знач = A.строка(с["value"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ключ.isEmpty, !знач.isEmpty else { continue }
            var подпись = A.строка(с["label"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if подпись.isEmpty { подпись = ключ }
            характеристики.append(ХарактеристикаИИФото(ключ: ключ, подпись: подпись,
                                                       значение: String(знач.prefix(ПределыПодачи.короткое))))
        }
        неуверенные = Set(((j["unsure"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty })
        главное = Self.отобратьГлавное(j["highlights"])
        if let ц = j["price_hint"] as? [String: Any] {
            let середина = max(0, A.целое(ц["mid"]))
            let низ = max(0, A.целое(ц["low"]))
            let верх = max(0, A.целое(ц["high"]))
            if середина > 0 || низ > 0 || верх > 0 {
                цена = ЦенаИИФото(низ: низ, середина: середина > 0 ? середина : (низ + верх) / 2, верх: верх,
                                  рынок: A.строка(ц["src"]) == "market")
            }
        }
        if название.isEmpty && описание.isEmpty && характеристики.isEmpty { return nil }
    }

    /**
     highlights — 3–5 строк для постера, не длиннее 28 знаков. Сервер обещает без цен, контактов, «оригинал», «скидка»,
     гарантии и «новый»; телефон проверяет ещё раз — постер собирается здесь, и за его слова отвечает приложение
     (правило владельца: на картинке нет обманных надписей — цен, «оригинал», «гарантия»).
     */
    static func отобратьГлавное(_ значение: Any?) -> [String] {
        var итог: [String] = []
        for элемент in (значение as? [Any]) ?? [] {
            let строка = МоиОбъявленияAPI.строка(элемент).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !строка.isEmpty, годноДляПостера(строка) else { continue }
            итог.append(String(строка.prefix(28)))
            if итог.count == 5 { break }
        }
        return итог
    }

    /// Куски, которых на постере не бывает: цена и валюта, «оригинал», скидка, гарантия, ссылки и контакты (4 языка).
    private static let запретныеПостера = ["₸", "тенге", "теңге", "тг.", " тг", "kzt", "оригинал", "original", "түпнұсқа",
                                           "скидк", "discount", "жеңілдік", "гарант", "кепілдік", "кепілді", "warrant",
                                           "guarantee", "http", "www.", "@", "+7", "8 7", "خصم", "أصلي", "ضمان", "كفالة"]

    /// Телефон или длинное число цены: 7 и больше цифр подряд, с пробелами, дефисами, скобками и точками между ними.
    private static let телефонПостера = try? NSRegularExpression(pattern: "\\+?\\d(?:[\\s\\-().]*\\d){6,}")

    /// Цена с валютой — с первой цифры («450 000 тг», «1.500.000₸»): обрезка названия убирает и само число.
    private static let ценаПостера = try? NSRegularExpression(
        pattern: "\\d[\\d\\s.]*(?:₸|тг|тенге|теңге|kzt|tg)", options: [.caseInsensitive])

    /// «Новый» — состояние этого экземпляра, а не надпись на картинку (как «новый» в §12 договора), отдельным словом.
    private static let новыйПостера = try? NSRegularExpression(
        pattern: "\\b(?:brand new|new|нов(?:ый|ая|ое|ые|ого|ую)|жаңа|جديد|جديدة)\\b", options: [.caseInsensitive])

    /// Начало первого запретного куска в строке; nil — строка годится для постера. сНовым — ещё и «новый» (у строк
    /// главного; в названии нет: «New Balance» — марка).
    static func началоЗапретного(_ строка: String, сНовым: Bool = true) -> String.Index? {
        var первое: String.Index? = nil
        for кусок in запретныеПостера {
            if let r = строка.range(of: кусок, options: [.caseInsensitive]), первое.map({ r.lowerBound < $0 }) ?? true {
                первое = r.lowerBound
            }
        }
        let вся = NSRange(строка.startIndex..., in: строка)
        for выражение in [телефонПостера, ценаПостера, сНовым ? новыйПостера : nil].compactMap({ $0 }) {
            if let найдено = выражение.firstMatch(in: строка, range: вся), let r = Range(найдено.range, in: строка),
               первое.map({ r.lowerBound < $0 }) ?? true {
                первое = r.lowerBound
            }
        }
        return первое
    }

    static func годноДляПостера(_ строка: String) -> Bool { началоЗапретного(строка) == nil }

    /// Название на постер: всё до первого запретного куска («iPhone 15 Pro оригинал, 450 000 тг» → «iPhone 15 Pro»).
    static func названиеДляПостера(_ строка: String) -> String {
        var итог = строка
        if let начало = началоЗапретного(строка, сНовым: false) { итог = String(строка[..<начало]) }
        let хвост = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:–—-|/(+"))
        return итог.trimmingCharacters(in: хвост)
    }
}

/// Ответ action=status.
struct ХодИИФото {
    enum Состояние: String {
        case queued, working, done, failed
    }

    var состояние: Состояние = .working
    /// progress 0…100 (не убывает на сервере; телефон тоже не даёт ему убывать).
    var прогресс = 0
    /// stage: text · image · check.
    var этап = ""
    /// caption — короткий ответ ИИ, простой текст, ≤ 300 знаков.
    var подпись = ""
    var картинка: URL? = nil
    var картинкаID = ""
    /// image_kind: illustration · edited.
    var вид = ""
    var черновик: ЧерновикИИФото? = nil
    var изменено: [String] = []
    var заметка = ""
    var своимИИ = false
    var осталось: Int? = nil
    var текстОсталось: Int? = nil

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        func чисто(_ поле: String) -> String { A.строка(j[поле]).trimmingCharacters(in: .whitespacesAndNewlines) }
        состояние = Состояние(rawValue: чисто("state")) ?? .working
        прогресс = min(100, max(0, A.целое(j["progress"])))
        этап = чисто("stage")
        подпись = Self.текст(чисто("caption"), предел: 300)
        картинка = КартинкиИИФото.адрес(A.строка(j["image"]))
        картинкаID = чисто("image_id")
        вид = чисто("image_kind")
        черновик = ЧерновикИИФото(j["draft"])
        изменено = ((j["changed"] as? [Any]) ?? []).map { A.строка($0) }
        заметка = Self.текст(чисто("note"), предел: 300)
        своимИИ = ОтветСвоегоИИ.своим(j)
        if j["left"] != nil { осталось = max(0, A.целое(j["left"])) }
        if j["text_left"] != nil { текстОсталось = max(0, A.целое(j["text_left"])) }
    }

    /// Текст сервера для человека: машинный код — не текст. Разбор без главной нити — правило nonisolated (InboxAPI).
    static func текст(_ строка: String, предел: Int) -> String {
        guard !строка.isEmpty, !КабинетСайта.машинныйКодБезГлавной(строка) else { return "" }
        return String(строка.prefix(предел))
    }
}

/// Окно запрета товара — те же тексты, что при загрузке фото подачи (ПодачаМодель.окноЗапрета).
struct ЗапретИИФото: Equatable, Identifiable {
    let заголовок: String
    let текст: String

    var id: String { заголовок + "|" + текст }
}

/// Отказ хода, принятия или удаления: код сервера и готовый текст. Отказ своего ИИ — ещё и окно «Свой ИИ».
struct ОтказИИФото: Equatable {
    let код: String
    let текст: String
    var свойИИ: ОтказСвоегоИИ? = nil
    var запрет: ЗапретИИФото? = nil

    init(код: String, текст: String, свойИИ: ОтказСвоегоИИ? = nil, запрет: ЗапретИИФото? = nil) {
        self.код = код
        self.текст = текст
        self.свойИИ = свойИИ
        self.запрет = запрет
    }

    /// «Повторить» может помочь: ИИ занят, сеть, сбой. Отказ модерации, лимит, выключенный режим — нет.
    var повторить: Bool { ["ai_down", "net", "fail"].contains(код) }
    /// «Другое фото»: сервер не принял фото вещи.
    var другоеФото: Bool { код == "bad_photo" || код == "need_photo" }
    /// Диалога больше нет — «Начать заново».
    var заново: Bool { код == "gone" }
}

/// Тело action=start без csrf и lang.
struct ЗапросХодаИИФото: Equatable {
    var режим = "draft"
    var диалог = ""
    var текст = ""
    var пресет = ""
    var раздел = ""
    var состояние = ""
    /// data:image/jpeg;base64,… — только в правке, когда фото ещё не уходило в этот диалог.
    var фото = ""
    /// photo_url — адрес плитки подачи (/img/uploads/…), из которой взято фото: сервер сверит его с реестром ИИ-фото
    /// (иллюстрацию не правит, у правки берёт чистый исходник). Только вместе с фото; фото из галереи — пусто.
    var ссылкаФото = ""
    var основа = ""
    var нужно: [String] = []
    var свой = false

    /// Сколько ждать хода: с картинкой — 90 с, только текст — 45 с.
    var предел: TimeInterval {
        режим == "draft" && нужно == ["text"] ? 45 : 90
    }
}

// MARK: - Запросы

@MainActor
enum ИИФотоAPI {
    enum Ответ {
        case готово([String: Any])
        case отказ(ОтказИИФото)
        case нуженВход
        /// Сервер не умеет (404, перенаправление, не JSON, unsupported) — «ИИ-фото скоро заработает».
        case нетСервера
        case сеть
        /// Нет токена, 5xx и прочее — «Не получилось».
        case сбой
    }

    enum ИтогСведений {
        case есть(СведенияИИФото)
        case нетСервера
        case сеть
    }

    private static let путь = "/api/ai_image.php?action="

    private static var язык: String { ИИФотоText.язык }

    /// GET info. 404/405/410/501, перенаправление, не JSON, unsupported — сервера нет; 5xx и обрыв — сеть (спросим позже).
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
        guard код > 0, код < 500 else { return .сеть }
        guard let j = ответ.json else { return .нетСервера }
        if A.строка(j["error"]) == "unsupported" || A.строка(j["code"]) == "unsupported" { return .нетСервера }
        if A.да(j["ok"]) { return .есть(СведенияИИФото(j)) }
        if A.нетСессии(j) || A.строка(j["code"]) == "auth" {
            /* Гостю сервер может не отвечать сведениями — генератор есть, но сначала вход. */
            var гость = СведенияИИФото()
            гость.вкл = true
            гость.вошёл = false
            return .есть(гость)
        }
        return .нетСервера
    }

    /// POST start — ход диалога.
    static func начать(_ з: ЗапросХодаИИФото) async -> Ответ {
        var тело: [String: Any] = ["lang": язык, "mode": з.режим, "thread": з.диалог, "prompt": з.текст,
                                   "preset": з.пресет, "category": з.раздел, "cond": з.состояние, "photo": з.фото,
                                   "base_image": з.основа]
        if !з.нужно.isEmpty { тело["want"] = з.нужно }
        if !з.фото.isEmpty && !з.ссылкаФото.isEmpty { тело["photo_url"] = з.ссылкаФото }
        if з.свой { тело["own"] = 1 }
        return await выполнить("start", тело)
    }

    /// POST status. failed приходит с ok:true — его разбирает модель (разобратьОтказ).
    static func ход(_ задача: String) async -> Ответ {
        await выполнить("status", ["job": задача, "lang": язык])
    }

    /// POST history — диалог целиком (после «Продолжить» черновика подачи).
    static func история(_ диалог: String) async -> Ответ {
        await выполнить("history", ["thread": диалог, "lang": язык])
    }

    /// POST accept — картинку (или постер из неё) в объявление; фото и миниатюра готовятся тем же путём, что все фото.
    static func взять(картинка: String, фото: String, миниатюра: String, постер: Bool) async -> Ответ {
        await выполнить("accept", ["lang": язык, "image_id": картинка, "photo": фото, "thumb": миниатюра,
                                   "poster": постер])
    }

    /// POST accept_draft — черновик в форму подачи (поля — как у recognize).
    static func взятьЧерновик(_ диалог: String) async -> Ответ {
        await выполнить("accept_draft", ["thread": диалог, "lang": язык])
    }

    /// POST delete — диалог с сервера. true — удалён (или его уже нет).
    static func удалить(_ диалог: String) async -> Bool {
        switch await выполнить("delete", ["thread": диалог]) {
        case .готово:
            return true
        case .отказ(let отказ):
            return отказ.код == "gone"
        case .нуженВход, .нетСервера, .сеть, .сбой:
            return false
        }
    }

    /**
     POST {csrf, …} тем же путём, что действия кабинета; «csrf» — свежая страница и один повтор (как загрузка фото
     подачи). Повторов при сбое сети нет: запись могла дойти.
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
            if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
            guard let j = ответ.json else { return код >= 500 || код == 0 ? .сбой : .нетСервера }
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
     {ok:false, code, error} у start/accept/accept_draft/delete, {state:"failed", code, error} у status → что показать.
     Запрет товара — те же поля, что у upload_photo (prohibited…), и то же окно. own_ai — как §5 договора «Свой ИИ».
     */
    static func разобратьОтказ(_ j: [String: Any]) -> Ответ {
        typealias A = МоиОбъявленияAPI
        let т = ИИФотоText.т
        let код = A.строка(j["code"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let машинная = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка)
        if код == "unsupported" || ошибка == "unsupported" { return .нетСервера }
        if код == "auth" || A.нетСессии(j) { return .нуженВход }
        if A.да(j["prohibited"]) {
            let окно = ПодачаМодель.окноЗапрета(j)
            return .отказ(ОтказИИФото(код: код.isEmpty ? "bad_prompt" : код, текст: машинная ? окно.текст : ошибка,
                                      запрет: ЗапретИИФото(заголовок: окно.заголовок, текст: окно.текст)))
        }
        if let своего = ОтказСвоегоИИ.из(j) {
            return .отказ(ОтказИИФото(код: "own_ai", текст: своего.текст, свойИИ: своего))
        }
        if код == "own_ai" {
            let своего = ОтказСвоегоИИ(код: "bad", текст: ОтказСвоегоИИ.текстОтвета(j))
            return .отказ(ОтказИИФото(код: код, текст: своего.текст, свойИИ: своего))
        }
        let итоговый = код.isEmpty && КабинетСайта.машинныйКод(ошибка) ? ошибка : код
        let текст: String
        switch итоговый {
        case "limit":
            switch A.строка(j["scope"]) {
            case "text": текст = т("aim_limit_text")
            case "thread": текст = т("aim_limit_thread")
            default: текст = т("aim_limit_image")
            }
        case "gone":
            текст = т("aim_gone")
        case "need_photo":
            текст = т("aim_need_photo")
        default:
            текст = машинная ? т("aim_err_fail") : ошибка
        }
        return .отказ(ОтказИИФото(код: итоговый, текст: текст))
    }
}

// MARK: - Картинки: адрес, скачивание, фото для правки, пометка, постер

/// Работа с картинками без главной нити — её зовут из Task.detached. На входе и выходе — Data, строки и UIImage.
enum КартинкиИИФото {
    struct ГотовоеДляПравки: Sendable {
        /// «data:image/jpeg;base64,…» для start.
        let адрес: String
        /// Тот же JPEG — показать в чате и для шторки «До / После».
        let jpeg: Data
    }

    /// Без кук и без кэша на диске: картинки диалога живут сутки и чужим не нужны.
    private static let сессия = URLSession(configuration: .ephemeral)

    /// Адрес картинки сервера: https на kliko.kz или поддомене; путь от корня — от https://kliko.kz. Иначе nil.
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

    /// Картинка по адресу: 200 и непустое тело — данные; иначе nil.
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

    /// Фото плитки подачи: файл на телефоне (ещё не загружен) или по адресу сервера (как это делает студия).
    static func данныеПлитки(_ плитка: ПлиткаФото) async -> Data? {
        if let картинка = плитка.картинка, !картинка.isEmpty { return картинка }
        guard let адрес = Config.url(плитка.url) else { return nil }
        var запрос = URLRequest(url: адрес)
        запрос.timeoutInterval = 30
        guard let пара = try? await сессия.data(for: запрос) else { return nil }
        if let http = пара.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return пара.0.isEmpty ? nil : пара.0
    }

    /// Фото вещи для правки: длинная сторона ≤ 1280, белая подложка, JPEG 0,82; рисуется заново — без EXIF и места.
    static func фотоДляПравки(_ данные: Data) -> ГотовоеДляПравки? {
        guard let снимок = UIImage(data: данные) else { return nil }
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard min(w, h) >= 256 else { return nil }
        guard let ужатое = ОбработкаФото.ужать(снимок, сторона: 1280),
              let jpeg = ужатое.jpegData(compressionQuality: 0.82) else { return nil }
        let адрес = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        guard адрес.count > 120 else { return nil }
        return ГотовоеДляПравки(адрес: адрес, jpeg: jpeg)
    }

    /**
     Картинка в объявление: вшитая пометка («Иллюстрация ИИ» / «Изменено ИИ») сверху по центру — там, где знак Kliko не
     встаёт никогда (его места — углы и края), потом тот же путь, что у всех фото подачи: 1280 px, знак Kliko, JPEG,
     миниатюра 420 (ОбработкаФото.подготовить).
     */
    static func дляПодачи(_ картинка: UIImage, надпись: String) -> ГотовоеФото? {
        ОбработкаФото.подготовить(пометить(картинка, надпись: надпись))
    }

    /// Маленькая тёмная капсула с надписью сверху по центру; ширина — не больше 40 % кадра (между местами знака Kliko).
    static func пометить(_ картинка: UIImage, надпись: String) -> UIImage {
        let ширина = картинка.size.width * картинка.scale
        let высота = картинка.size.height * картинка.scale
        let меньшая = min(ширина, высота)
        guard меньшая > 0, !надпись.isEmpty else { return картинка }
        let текст = "✦ " + надпись
        var кегль = max(12, (0.026 * меньшая).rounded())
        var атрибуты: [NSAttributedString.Key: Any] = [:]
        var размерТекста = CGSize.zero
        for _ in 0..<6 {
            атрибуты = [.font: UIFont.systemFont(ofSize: кегль, weight: .semibold), .foregroundColor: UIColor.white]
            размерТекста = (текст as NSString).size(withAttributes: атрибуты)
            if размерТекста.width + кегль * 1.6 <= ширина * 0.4 { break }
            кегль = max(9, (кегль * 0.85).rounded())
        }
        let капсула = CGSize(width: размерТекста.width + кегль * 1.6, height: размерТекста.height + кегль * 0.7)
        let отступ = max(8, (0.03 * меньшая).rounded())
        let рамка = CGRect(x: ((ширина - капсула.width) / 2).rounded(), y: отступ, width: капсула.width,
                           height: капсула.height)
        let размер = CGSize(width: ширина, height: высота)
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        return UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            UIColor.white.setFill()
            холст.fill(CGRect(origin: .zero, size: размер))
            картинка.draw(in: CGRect(origin: .zero, size: размер))
            let форма = UIBezierPath(roundedRect: рамка, cornerRadius: капсула.height / 2)
            UIColor(white: 0, alpha: 0.58).setFill()
            форма.fill()
            UIColor(white: 1, alpha: 0.35).setStroke()
            форма.lineWidth = max(1, (кегль * 0.08).rounded())
            форма.stroke()
            (текст as NSString).draw(at: CGPoint(x: рамка.minX + кегль * 0.8, y: рамка.minY + кегль * 0.35),
                                     withAttributes: атрибуты)
        }
    }

    /**
     Постер-оформление (договор §9.5) — по шаблону телефона, без ИИ: квадрат 1080, картинка во весь кадр, снизу
     затемнение, название (до двух строк) и 3–5 главных строк бейджами. Без цены, контактов, «оригинал» и «скидка»
     (ЧерновикИИФото.главное). справаНалево — арабский: бейджи и название от правого края.
     */
    static func постер(_ картинка: UIImage, название: String, пункты: [String], справаНалево: Bool) -> UIImage? {
        let сторона: CGFloat = 1080
        let поля: CGFloat = 60
        let размер = CGSize(width: сторона, height: сторона)
        let w = картинка.size.width * картинка.scale
        let h = картинка.size.height * картинка.scale
        guard w > 0, h > 0 else { return nil }
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let шрифтБейджа = UIFont.systemFont(ofSize: 34, weight: .semibold)
        let атрибутыБейджа: [NSAttributedString.Key: Any] = [.font: шрифтБейджа, .foregroundColor: UIColor.white]
        let ширинаТекста = сторона - поля * 2
        /* Бейджи — рядами; рядов не больше трёх, длинное не влезает — пропускаем. */
        var бейджи: [(текст: String, рамка: CGRect)] = []
        var x: CGFloat = 0
        var ряд = 0
        let высотаБейджа: CGFloat = 62
        let зазор: CGFloat = 14
        for пункт in пункты.prefix(5) {
            let текст = "✓ " + пункт
            let ширина = min(ширинаТекста, (текст as NSString).size(withAttributes: атрибутыБейджа).width + 44)
            if x > 0 && x + ширина > ширинаТекста {
                ряд += 1
                x = 0
            }
            if ряд > 2 { break }
            бейджи.append((текст, CGRect(x: x, y: CGFloat(ряд) * (высотаБейджа + зазор), width: ширина,
                                         height: высотаБейджа)))
            x += ширина + зазор
        }
        let высотаБейджей: CGFloat = бейджи.isEmpty ? 0 : (бейджи.map { $0.рамка.maxY }.max() ?? 0)
        let верхБейджей = сторона - поля - высотаБейджей
        let абзац = NSMutableParagraphStyle()
        абзац.alignment = справаНалево ? .right : .left
        абзац.lineBreakMode = .byTruncatingTail
        let тень = NSShadow()
        тень.shadowColor = UIColor(white: 0, alpha: 0.5)
        тень.shadowBlurRadius = 12
        тень.shadowOffset = CGSize(width: 0, height: 3)
        let атрибутыНазвания: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 60, weight: .heavy), .foregroundColor: UIColor.white,
            .paragraphStyle: абзац, .shadow: тень
        ]
        let строкаНазвания = UIFont.systemFont(ofSize: 60, weight: .heavy).lineHeight
        let измерено = (название as NSString).boundingRect(with: CGSize(width: ширинаТекста, height: строкаНазвания * 2 + 4),
                                                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                                           attributes: атрибутыНазвания, context: nil)
        let высотаНазвания = min(ceil(измерено.height), строкаНазвания * 2 + 4)
        let верхНазвания = верхБейджей - (бейджи.isEmpty ? 0 : 28) - высотаНазвания
        return UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            let кон = холст.cgContext
            UIColor(red: 0.03, green: 0.07, blue: 0.05, alpha: 1).setFill()
            кон.fill(CGRect(origin: .zero, size: размер))
            let k = max(сторона / w, сторона / h)
            картинка.draw(in: CGRect(x: (сторона - w * k) / 2, y: (сторона - h * k) / 2, width: w * k, height: h * k))
            let цвета = [UIColor(red: 0.02, green: 0.08, blue: 0.05, alpha: 0).cgColor,
                         UIColor(red: 0.02, green: 0.08, blue: 0.05, alpha: 0.9).cgColor] as CFArray
            if let градиент = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: цвета, locations: [0, 1]) {
                кон.drawLinearGradient(градиент, start: CGPoint(x: 0, y: max(0, верхНазвания - 220)),
                                     end: CGPoint(x: 0, y: сторона), options: [.drawsAfterEndLocation])
            }
            /* Зелёная черта над названием — фирменный акцент Kliko. */
            let черта = CGRect(x: справаНалево ? сторона - поля - 96 : поля, y: верхНазвания - 26, width: 96, height: 10)
            UIColor(red: 0.36, green: 0.83, blue: 0.60, alpha: 1).setFill()
            UIBezierPath(roundedRect: черта, cornerRadius: 5).fill()
            (название as NSString).draw(with: CGRect(x: поля, y: верхНазвания, width: ширинаТекста, height: высотаНазвания),
                                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                        attributes: атрибутыНазвания, context: nil)
            for бейдж in бейджи {
                var рамка = бейдж.рамка
                рамка.origin.x = справаНалево ? сторона - поля - рамка.maxX : поля + рамка.minX
                рамка.origin.y += верхБейджей
                let форма = UIBezierPath(roundedRect: рамка, cornerRadius: высотаБейджа / 2)
                UIColor(white: 1, alpha: 0.16).setFill()
                форма.fill()
                UIColor(white: 1, alpha: 0.38).setStroke()
                форма.lineWidth = 2
                форма.stroke()
                let размерТекста = (бейдж.текст as NSString).size(withAttributes: атрибутыБейджа)
                let место = CGRect(x: рамка.minX + 22, y: рамка.midY - размерТекста.height / 2,
                                   width: рамка.width - 44, height: размерТекста.height)
                (бейдж.текст as NSString).draw(with: место, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                               attributes: атрибутыБейджа, context: nil)
            }
        }
    }
}

// MARK: - Есть ли генератор

/**
 Что сервер сказал в info — одно на приложение. Спрашивает лениво: при открытии подачи (выбор способа, шаг «Фото») и
 окна чата; не чаще раза в 10 минут, после сбоя сети — раз в минуту, после входа и выхода и после переключения «Своего
 ИИ» — заново. Сервер не умеет — до перезапуска не спрашиваем. Синглтон создаётся пустым и в init ни к кому не
 обращается.
 */
@MainActor
final class ГотовностьИИФото: ObservableObject {
    static let shared = ГотовностьИИФото()

    @Published private(set) var сведения: СведенияИИФото? = nil
    @Published private(set) var нетСервера = false

    private var когда: Date? = nil
    private var дляСессии = -1
    private var идёт: Task<Void, Never>? = nil
    /// «Свой ИИ» был включён, когда спрашивали info: сведения own, ai и ai_text — про это состояние.
    private var свойПриСведениях = false

    private init() {}

    private var включено: Bool {
        guard Config.ииРедакторФото, !нетСервера, let с = сведения else { return false }
        return с.вкл
    }

    /// «Объявление по названию»: рубильник, сервер сказал on, режим draft включён хоть у одного вида.
    var черновикДоступен: Bool {
        guard включено, let с = сведения else { return false }
        return с.черновикГдеНибудь
    }

    /// «Правка ИИ» для вида объявления (nil — вид ещё не известен: решит сервер, not_allowed).
    /// Сведения есть и не устарели: «Свой ИИ» с тех пор не переключали (own, ai, ai_text — для согласия).
    var сведенияСвежие: Bool {
        сведения != nil && свойПриСведениях == СвойИИМодель.shared.активен
    }

    func правкаДоступна(вид: String?) -> Bool {
        guard включено, let с = сведения, с.режимПравка else { return false }
        guard let вид else { return true }
        return с.правила(вид).правка
    }

    func проверить() async {
        guard Config.ииРедакторФото, !нетСервера else { return }
        /* смена растёт при любой смене человека: сведения у каждого свои (auth, left, own). */
        let сессия = СессияПриложения.shared.смена
        let свой = СвойИИМодель.shared.активен
        if let когда {
            let прошло = Date().timeIntervalSince(когда)
            if сведения != nil && дляСессии == сессия && прошло < 600 && свойПриСведениях == свой { return }
            if сведения == nil && прошло < 60 { return }
        }
        if let идёт {
            await идёт.value
            return
        }
        let задача = Task { @MainActor in
            let итог = await ИИФотоAPI.сведения()
            let готовность = ГотовностьИИФото.shared
            готовность.когда = Date()
            switch итог {
            case .есть(let новые):
                готовность.дляСессии = сессия
                готовность.свойПриСведениях = свой
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

    /// Человек только что вошёл из окна чата: сведения гостя (auth:false) больше не годятся — спросить заново.
    func устарели() {
        когда = nil
        дляСессии = -1
    }

    /// Сервер ответил «не умею» — кнопок нет до перезапуска.
    func отметитьНетСервера() {
        нетСервера = true
        сведения = nil
    }

    /// left и text_left из ответа start или status — «Осталось ИИ-картинок сегодня».
    func остаток(картинок: Int?, текста: Int?) {
        guard var с = сведения else { return }
        if let картинок { с.осталось = max(0, картинок) }
        if let текста { с.текстОсталось = max(0, текста) }
        if с != сведения { сведения = с }
    }
}
