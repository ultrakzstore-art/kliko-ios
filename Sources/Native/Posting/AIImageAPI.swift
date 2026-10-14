import Foundation
import UIKit

/**
 КАРТИНКА ПО ОПИСАНИЮ — ЗАПРОСЫ И ДАННЫЕ (ultra-site 14.10.2026, «Картинка для объявления по описанию», части 1 и 2;
 рубильник приложения Config.ииРедакторФото, AIImageConfig.swift; рубильник сервера photo_gen).

   · GET  cabinet.php?action=photo_gen_info&cat=<раздел>&lang=<ru|kz|en|ar> → {ok, on, can, cat, cat_ok, by, by_text,
     spends, left:{month, month_max, day, day_max, resets}, busy, last, cover_ok, shop, label, advice} и, если свой ИИ
     человека картинки не рисует, own_ai:"images", own_ai_text, kliko_ok. Рубильник выключен — {ok:false, off:true};
   · POST cabinet.php?action=photo_gen {csrf, cat, title, brand, series, color, desc, lang, atype, specs:[{k, v, l}]
     (до 4), item_id?, own:1?, kliko:1?, cover:1?} → {ok:true, run, url, thumb, ai_gen, cover, by, model, label, left}
     (own_ai_run:1 — рисовал свой ИИ). url — обычный адрес фото в /img/uploads: ставится в images как загруженное фото.
     Отказ — всегда ok:false и готовая фраза в error; рядом признак (off, unavailable, banned, ai_blocked, imp,
     only_text, need_cat, cat_off, slots_full, text_bad, text_link, rate_limited, busy, cap, ai_down, ai_off, letters,
     unsafe, own_ai) и, бывает, cover_ok, kliko_ok, left.
 Только текст: фото в генератор не уходят (запрос с картинкой сервер отклоняет only_text). Ответ идёт до пары минут;
 оборвалась связь — результат в last ответа info (опрашивает модель окна). Транспорт — как у действий кабинета
 (КабинетСайта.вызвать, путь /kz/<язык>/cabinet.php), токен — МоиОбъявленияAPI.токенСейчас, один повтор на «csrf».

 🔴 ТЕКСТЫ СЕРВЕРА. error — готовая фраза на языке человека: показывается как есть. Машинный код, пусто или вдруг
 слова о цене и покупке — своя фраза (цифровое в приложении — только App Store). Отказ «Своего ИИ» — фраза приложения.
 🔴 КАРТИНКИ. Только https на kliko.kz и поддоменах; качаются отдельной сессией без кук и без кэша на диске.
 */

// MARK: - Данные

/// left: остаток картинок. nil в полях — сервер не сказал.
struct ОстатокИИФото: Equatable {
    var месяц: Int? = nil
    var месяцМакс: Int? = nil
    var день: Int? = nil
    var деньМакс: Int? = nil

    /// left ответа; не объект — nil.
    init?(_ значение: Any?) {
        guard let j = значение as? [String: Any] else { return nil }
        typealias A = МоиОбъявленияAPI
        func число(_ ключ: String) -> Int? {
            guard let з = j[ключ], !(з is NSNull) else { return nil }
            return max(0, A.целое(з))
        }
        месяц = число("month")
        месяцМакс = число("month_max")
        день = число("day")
        деньМакс = число("day_max")
        if месяц == nil && день == nil { return nil }
    }
}

/// Готовая картинка: ответ photo_gen при ok:true или last из info. Без адреса — nil.
struct ИтогИИФото: Equatable {
    /// run — номер запуска.
    var запуск = ""
    /// url — адрес фото на сайте (/img/uploads/…), как у upload_photo.
    var адрес = ""
    var миниатюра = ""
    /// cover — обложка без рисунка (gen.model = "kliko-cover").
    var обложка = false
    /// by — kliko | own.
    var кто = ""
    /// label — готовая подпись метки от сервера; пусто — своя.
    var метка = ""
    /// own_ai_run — рисовал свой ИИ человека.
    var своимИИ = false

    init?(_ значение: Any?) {
        guard let j = значение as? [String: Any] else { return nil }
        typealias A = МоиОбъявленияAPI
        адрес = A.строка(j["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !адрес.isEmpty else { return nil }
        запуск = A.строка(j["run"]).trimmingCharacters(in: .whitespacesAndNewlines)
        миниатюра = A.строка(j["thumb"]).trimmingCharacters(in: .whitespacesAndNewlines)
        обложка = A.да(j["cover"])
        кто = A.строка(j["by"]).trimmingCharacters(in: .whitespacesAndNewlines)
        метка = ИИФотоAPI.текстСервера(A.строка(j["label"]), предел: 60)
        своимИИ = ОтветСвоегоИИ.своим(j) || кто == "own"
    }

    /// Вид плашки: обложка без рисунка или иллюстрация.
    var вид: String { обложка ? "cover" : "illustration" }

    /// Чем одна картинка отличается от другой: номер запуска, без него — адрес.
    var ключ: String { запуск.isEmpty ? адрес : запуск }
}

/// Ответ photo_gen_info. Поля необязательные: лишнее, что сервер добавит потом, не мешает.
struct СведенияИИФото: Equatable {
    /// Для какого раздела спрашивали (cat запроса).
    var раздел = ""
    /// ok и on — рубильник сервера включён.
    var вкл = false
    /// can — этому человеку сейчас можно.
    var можно = false
    /// cat_ok — раздел подходит; nil — сервер не сказал.
    var разделПодходит: Bool? = nil
    /// by — kliko | own | ""; by_text — кто нарисует, готовой фразой.
    var кто = ""
    var ктоТекст = ""
    /// spends — запуск тратит месячный остаток (тогда показываем left.month из left.month_max).
    var тратит = false
    var остаток: ОстатокИИФото? = nil
    /// busy — запуск уже идёт.
    var занят = false
    /// last — последняя готовая картинка.
    var последний: ИтогИИФото? = nil
    /// cover_ok — можно собрать обложку без рисунка.
    var обложкаМожно = false
    /// own_ai:"images" — свой ИИ человека картинки не рисует; own_ai_text — фраза сервера; kliko_ok — можно Kliko AI.
    var свойНеРисует = false
    var свойТекст = ""
    var klikoМожно = false

    init() {}

    init(_ j: [String: Any], раздел: String) {
        typealias A = МоиОбъявленияAPI
        self.раздел = раздел
        вкл = A.да(j["ok"]) && A.да(j["on"])
        можно = A.да(j["can"])
        if let з = j["cat_ok"], !(з is NSNull) { разделПодходит = A.да(з) }
        кто = A.строка(j["by"]).trimmingCharacters(in: .whitespacesAndNewlines)
        ктоТекст = ИИФотоAPI.текстСервера(A.строка(j["by_text"]), предел: 80)
        тратит = A.да(j["spends"])
        остаток = ОстатокИИФото(j["left"])
        занят = A.да(j["busy"])
        последний = ИтогИИФото(j["last"])
        обложкаМожно = A.да(j["cover_ok"])
        свойНеРисует = A.строка(j["own_ai"]) == "images"
        свойТекст = ИИФотоAPI.текстСервера(A.строка(j["own_ai_text"]), предел: 300)
        klikoМожно = A.да(j["kliko_ok"])
    }

    /// Остаток для шапки окна: только когда запуск тратит месячный остаток и сервер назвал оба числа.
    var строкаОстатка: (осталось: Int, всего: Int)? {
        guard тратит, let о = остаток, let осталось = о.месяц, let всего = о.месяцМакс, всего > 0 else { return nil }
        return (осталось, всего)
    }
}

/// Характеристика формы для specs запроса: k — поле, v — значение, l — подпись.
struct ХарактеристикаИИФото: Equatable, Hashable {
    let ключ: String
    let подпись: String
    let значение: String
}

/// Отказ запуска: признак сервера и готовый текст; рядом — что можно сделать дальше.
struct ОтказИИФото: Equatable {
    let код: String
    var текст: String
    /// cover_ok — «Собрать обложку без рисунка».
    var обложкаМожно = false
    /// own_ai:"images" и kliko_ok — «Нарисовать с Kliko AI».
    var klikoМожно = false
    /// Отказ своего ИИ (кроме «не рисует картинки») — кнопка «Свой ИИ».
    var свойИИ: ОтказСвоегоИИ? = nil

    init(код: String, текст: String) {
        self.код = код
        self.текст = текст
    }

    /// «Повторить» может помочь: ИИ занят или недоступен, сеть, сбой, частые запросы.
    var повторить: Bool { ["ai_down", "unavailable", "rate_limited", "net", "fail", "none"].contains(код) }
}

/// Тело photo_gen без csrf и lang.
struct ЗапросИИФото: Equatable {
    var раздел = ""
    var название = ""
    var марка = ""
    var серия = ""
    var цвет = ""
    var описание = ""
    /// atype — тип объявления формы (goods · services · rentgood · realty · "").
    var тип = ""
    var характеристики: [ХарактеристикаИИФото] = []
    /// item_id — правка опубликованного объявления.
    var объявление = ""
    var свой = false
    var kliko = false
    var обложка = false

    var тело: [String: Any] {
        var т: [String: Any] = [
            "cat": раздел, "title": название, "brand": марка, "series": серия, "color": цвет, "desc": описание,
            "atype": тип,
            "specs": характеристики.prefix(4).map { ["k": $0.ключ, "v": $0.значение, "l": $0.подпись] }
        ]
        if !объявление.isEmpty {
            if let номер = Int(объявление) { т["item_id"] = номер } else { т["item_id"] = объявление }
        }
        if свой && !kliko { т["own"] = 1 }
        if kliko { т["kliko"] = 1 }
        if обложка { т["cover"] = 1 }
        return т
    }
}

// MARK: - Запросы

@MainActor
enum ИИФотоAPI {
    enum Ответ {
        case готово(ИтогИИФото, ОстатокИИФото?)
        case отказ(ОтказИИФото)
        case нуженВход
        /// Рубильник сервера выключен (off) — кнопки нет, окно — «скоро».
        case выключено
        /// Двери нет (404, перенаправление, не JSON) — до перезапуска не спрашиваем.
        case нетСервера
        /// Связь оборвалась (или шлюз не дождался) — запуск мог дойти: результат ищем в last.
        case сеть
        /// Нет токена и прочее — «Не получилось».
        case сбой
    }

    enum ИтогСведений {
        case есть(СведенияИИФото)
        case выключено
        case гость
        case нетСервера
        case сеть
    }

    private static var язык: String { ИИФотоText.языкСервера }

    /// Раздел в адресе: слаг латиницей; прочее — кодируется.
    private static func закодировать(_ строка: String) -> String {
        var можно = CharacterSet.alphanumerics
        можно.insert(charactersIn: "-_")
        return строка.addingPercentEncoding(withAllowedCharacters: можно) ?? ""
    }

    /// GET photo_gen_info. 404/405/410/501, перенаправление, не JSON — двери нет; 5xx и обрыв — сеть (спросим позже).
    static func сведения(раздел: String) async -> ИтогСведений {
        typealias A = МоиОбъявленияAPI
        let хвост = "cabinet.php?action=photo_gen_info&cat=" + закодировать(раздел) + "&lang=" + язык
        let ответ: КабинетСайта.Ответ
        do {
            ответ = try await КабинетСайта.вызвать(хвост)
        } catch {
            return .сеть
        }
        let код = ответ.код
        if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
        guard код > 0, код < 500 else { return .сеть }
        guard let j = ответ.json else { return .нетСервера }
        if A.да(j["ok"]) { return .есть(СведенияИИФото(j, раздел: раздел)) }
        if A.нетСессии(j) { return .гость }
        /* off и любой другой отказ — пока «выключено»: кнопки нет, спросим снова не раньше чем через минуту. */
        return .выключено
    }

    /**
     POST photo_gen. «csrf» — свежая страница и один повтор (как загрузка фото подачи). Повторов при сбое сети нет:
     запуск мог дойти — модель окна ждёт его в last ответа info.
     */
    static func создать(_ з: ЗапросИИФото) async -> Ответ {
        typealias A = МоиОбъявленияAPI
        var повторили = false
        while true {
            let ответ: КабинетСайта.Ответ
            do {
                let токен = try await A.токенСейчас()
                if токен.isEmpty { return .нуженВход }
                var тело = з.тело
                тело["csrf"] = токен
                тело["lang"] = язык
                ответ = try await КабинетСайта.вызвать("cabinet.php?action=photo_gen", метод: "POST", тело: тело)
            } catch let сбой as КабинетСайта.Сбой where сбой == .сеть {
                return .сеть
            } catch {
                return .сбой
            }
            let код = ответ.код
            if [404, 405, 410, 501].contains(код) || (300..<400).contains(код) { return .нетСервера }
            guard let j = ответ.json else {
                /* 502–504 и обрыв без тела: шлюз мог не дождаться долгого ответа — картинка, возможно, в last. */
                return код >= 500 || код == 0 ? .сеть : .нетСервера
            }
            if A.строка(j["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            if A.да(j["ok"]) {
                guard let итог = ИтогИИФото(j) else { return .сбой }
                return .готово(итог, ОстатокИИФото(j["left"]))
            }
            return разобратьОтказ(j)
        }
    }

    /// Признаки отказа по порядку договора; первый найденный — код.
    private static let признаки = ["unavailable", "banned", "ai_blocked", "imp", "only_text", "need_cat", "cat_off",
                                   "slots_full", "text_bad", "text_link", "rate_limited", "busy", "ai_down", "ai_off",
                                   "letters", "unsafe"]

    /// {ok:false, error, …} → что показать. Вход, рубильник, свой ИИ — отдельно.
    static func разобратьОтказ(_ j: [String: Any]) -> Ответ {
        typealias A = МоиОбъявленияAPI
        let т = ИИФотоText.т
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if ошибка == "auth" || A.нетСессии(j) { return .нуженВход }
        if A.да(j["off"]) { return .выключено }
        let свой = A.строка(j["own_ai"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var код = признаки.first(where: { A.да(j[$0]) }) ?? ""
        if код.isEmpty && !A.строка(j["cap"]).isEmpty { код = "cap" }
        if код.isEmpty && !свой.isEmpty { код = свой == "images" ? "own_images" : "own_ai" }
        if код.isEmpty { код = КабинетСайта.машинныйКод(ошибка) ? ошибка : "fail" }
        let годный = текстСервера(ошибка, предел: 400)
        let запасной: String
        switch код {
        case "cap": запасной = т("aim_err_cap")
        case "slots_full": запасной = т("aim_err_slots")
        case "busy": запасной = т("aim_err_busy")
        default: запасной = т("aim_err_fail")
        }
        var отказ = ОтказИИФото(код: код, текст: годный.isEmpty ? запасной : годный)
        отказ.обложкаМожно = A.да(j["cover_ok"])
        отказ.klikoМожно = свой == "images" && A.да(j["kliko_ok"])
        if свой != "images", let своего = ОтказСвоегоИИ.из(j) {
            /* Фраза приложения: текст сервера про свой ИИ может звать купить Premium (3.1.1). */
            отказ.свойИИ = своего
            отказ.текст = своего.текст
        }
        return .отказ(отказ)
    }

    /**
     Готовая фраза сервера для человека: обрезана по пределу; машинный код, пусто или слова о цене и покупке — "" (тогда
     своя фраза). Без главной нити — её зовут разборы данных.
     */
    nonisolated static func текстСервера(_ строка: String, предел: Int) -> String {
        /* Куски, которых в тексте сервера для приложения не бывает: цена, валюта, покупка и оплата (4 языка). */
        let словаПокупки = ["₸", "тенге", "теңге", "kzt", "купит", "купи", "оплат", "пополн", "buy ", "purchase",
                            "top up", "сатып ал", "төле", "اشتر", "ادفع", "شراء"]
        let чистая = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистая.isEmpty, !КабинетСайта.машинныйКодБезГлавной(чистая) else { return "" }
        let строчная = чистая.lowercased()
        if словаПокупки.contains(where: { строчная.contains($0) }) { return "" }
        return String(чистая.prefix(предел))
    }
}

// MARK: - Картинки: адрес и скачивание

/// Работа с картинками без главной нити.
enum КартинкиИИФото {
    /// Без кук и без кэша на диске: картинке до взятия в объявление чужие не нужны.
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

    /// Готовая картинка запуска: сначала полный кадр, не вышло — миниатюра; две попытки на каждый.
    static func скачатьИтог(_ итог: ИтогИИФото) async -> Data? {
        for строка in [итог.адрес, итог.миниатюра] {
            guard let адрес = адрес(строка) else { continue }
            for попытка in 0..<2 {
                if попытка > 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
                if let данные = await скачать(адрес) { return данные }
            }
        }
        return nil
    }
}

// MARK: - Можно ли

/**
 Что сервер сказал в photo_gen_info — одно на приложение, для раздела формы. Спрашивает лениво: вход на шаге «Фото»
 (раздел сменился — заново), окно чата; не чаще раза в 5 минут на тот же раздел, после сбоя сети — раз в минуту, после
 входа и выхода и после переключения «Своего ИИ» — заново. Двери нет — до перезапуска не спрашиваем. Синглтон создаётся
 пустым и в init ни к кому не обращается.
 */
@MainActor
final class ГотовностьИИФото: ObservableObject {
    static let shared = ГотовностьИИФото()

    @Published private(set) var сведения: СведенияИИФото? = nil
    @Published private(set) var нетСервера = false

    private var когда: Date? = nil
    private var дляСессии = -1
    /// Раздел последнего ответа (или попытки).
    private var раздел = ""
    /// Раздел, о котором спросили последним (вход на шаге «Фото»): ответы о прежних разделах не ставятся.
    private var заказан = ""
    private var идёт: Task<Void, Never>? = nil
    private var идётРаздел = ""
    /// «Свой ИИ» был включён, когда спрашивали: by и by_text — про это состояние.
    private var свойПриСведениях = false

    private init() {}

    /**
     Кнопка «Нет фото? Создать иллюстрацию»: рубильник приложения, сведения именно для этого раздела, сервер сказал on
     и can, а cat_ok — не false.
     */
    func доступно(раздел: String) -> Bool {
        guard Config.ииРедакторФото, !нетСервера, !раздел.isEmpty, let с = сведения, с.раздел == раздел else {
            return false
        }
        return с.вкл && с.можно && с.разделПодходит != false
    }

    /// Сведения есть и не устарели: «Свой ИИ» с тех пор не переключали (by, by_text — для согласия).
    var сведенияСвежие: Bool {
        сведения != nil && свойПриСведениях == СвойИИМодель.shared.активен
    }

    /**
     Из body входа на шаге «Фото»: раздел формы сменился — спросить в отдельной задаче (в этом проходе ничего не
     публикуется). Тот же раздел — ничего.
     */
    func спроситьДля(_ раздел: String) {
        guard Config.ииРедакторФото, !нетСервера, !раздел.isEmpty, раздел != заказан else { return }
        заказан = раздел
        Task { @MainActor in await ГотовностьИИФото.shared.проверить(раздел: раздел) }
    }

    /// раздел nil — последний, о котором спрашивали; заново — без оглядки на время (окно чата, после входа).
    func проверить(раздел: String? = nil, заново: Bool = false) async {
        let нужный = раздел ?? (заказан.isEmpty ? self.раздел : заказан)
        guard Config.ииРедакторФото, !нетСервера, !нужный.isEmpty else { return }
        /* смена растёт при любой смене человека: сведения у каждого свои (can, left, by). */
        let сессия = СессияПриложения.shared.смена
        let свой = СвойИИМодель.shared.активен
        if !заново, let когда, нужный == self.раздел {
            let прошло = Date().timeIntervalSince(когда)
            if сведения != nil && дляСессии == сессия && прошло < 300 && свойПриСведениях == свой { return }
            if прошло < 60 && дляСессии == сессия { return }
        }
        if let идёт, идётРаздел == нужный {
            await идёт.value
            return
        }
        let задача = Task { @MainActor in
            let итог = await ИИФотоAPI.сведения(раздел: нужный)
            ГотовностьИИФото.shared.принять(итог, раздел: нужный, сессия: сессия, свой: свой)
        }
        идёт = задача
        идётРаздел = нужный
        await задача.value
        if идётРаздел == нужный {
            идёт = nil
            идётРаздел = ""
        }
    }

    /// Ответ info (и опрос окна чата): ставится, только если это ответ о разделе, который нужен сейчас.
    func принять(_ итог: ИИФотоAPI.ИтогСведений, раздел нужный: String, сессия: Int, свой: Bool) {
        guard заказан.isEmpty || заказан == нужный else { return }
        когда = Date()
        раздел = нужный
        дляСессии = сессия
        switch итог {
        case .есть(let новые):
            свойПриСведениях = свой
            if сведения != новые { сведения = новые }
        case .выключено, .гость:
            if сведения != nil { сведения = nil }
        case .нетСервера:
            отметитьНетСервера()
        case .сеть:
            /* Прежние сведения о другом разделе не годятся; о том же — пусть живут до следующего ответа. */
            if сведения?.раздел != нужный && сведения != nil { сведения = nil }
        }
    }

    /// Человек вошёл или вышел из окна чата: сведения прежнего человека не годятся — спросить заново.
    func устарели() {
        когда = nil
        дляСессии = -1
    }

    /// Двери нет — кнопок нет до перезапуска.
    func отметитьНетСервера() {
        нетСервера = true
        сведения = nil
    }

    /// Сервер выключил рубильник посреди работы — кнопка уходит; спросим снова не раньше чем через минуту.
    func отметитьВыключено() {
        когда = Date()
        if сведения != nil { сведения = nil }
    }

    /// left из ответа запуска — остаток в шапке окна.
    func остаток(_ новый: ОстатокИИФото?) {
        guard let новый, var с = сведения else { return }
        с.остаток = новый
        if с != сведения { сведения = с }
    }

    /// Свежая картинка запуска — last сведений, чтобы опрос после обрыва связи не принял её за новую.
    func последний(_ итог: ИтогИИФото) {
        guard var с = сведения else { return }
        с.последний = итог
        if с != сведения { сведения = с }
    }
}
