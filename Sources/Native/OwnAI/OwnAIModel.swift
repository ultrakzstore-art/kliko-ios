import Foundation
import SwiftUI

/**
 «СВОЙ ИИ» — СОСТОЯНИЕ И ЗАПРОСЫ (ответ ultra-site 08.10.2026; код сайта — inc/own_ai.php, inc/cabinet/own_ai.php,
 js/cabinet-settings.js cabOwnAi()).

 Человек подключает в кабинете ключ своего поставщика ИИ; с действующим Premium «Свой ИИ» функции Kliko AI в кабинете
 (recognize, подсказки ответов, ai_service, поиск по фото, shot_read, импорт, ai_resume …) идут через его ключ. На проде —
 за рубильником own_ai: пока own_ai.on не true, раздела в приложении нет вовсе.

 Запросы — все POST cabinet.php?action=<имя>, тело JSON с csrf, только сессией кабинета: тем же транспортом, что
 recognize (МоиОбъявленияAPI.отправить → КабинетСайта.вызвать, токен страницы и один повтор на «csrf»):
   own_ai_state · own_ai_connect {provider, key} · own_ai_models · own_ai_model {model} · own_ai_test ·
   own_ai_use {on} · own_ai_disconnect.
 own_ai_buy и own_ai_trial (кошелёк сайта) приложение не вызывает никогда: Premium в приложении — только товар App Store
 kz.kliko.app.ownai.month (ПродуктыApple, ВидУслугиApple.свойИИ). Отказ — {ok:false, code, error}: error уже готовый
 текст на языке человека, его и показываем. Кроме need_premium / code "premium" (в приложении сервер добавляет к ним
 app_store:true), gone и relink: тексты premium и gone у сайта общие (lang/<язык>.php) и могут звать купить Premium с
 баланса или взять пробный период — в приложении вместо них своя фраза (ОтказСвоегоИИ.фразаПриложения), Premium здесь —
 только App Store (3.1.1); relink — своя фраза «Подключите свой ИИ заново».
 own_ai_or_start {app:1} («Войти через OpenRouter», ultra-site 14.10.2026): сервер узнаёт человека по одноразовой метке
 state, а не по куке браузера, и возвращает kliko://own-ai?ok=1|0 — вход идёт эфемерным ASWebAuthenticationSession
 (OwnAIOpenRouter.swift). Кнопка — только при own_ai.login_app.

 🔴 КЛЮЧ. В приложении ключ живёт только в поле ввода экрана и в теле одного запроса own_ai_connect: ни UserDefaults, ни
 файлов, ни журнала; поле очищается сразу после нажатия «Подключить». Сервер отдаёт только tail — 4 последних знака.

 🔴 ЗАПУСК. Синглтон создаётся пустым и сам ни к кому не ходит; состояние грузится лениво (экран, строка настроек,
 карточка «Доступно», открытие подачи), а не в init — init чужих static let shared сюда не обращается и наоборот.
 */

/// Поставщик из own_ai.providers: id и подпись сервера (бренды не переводятся).
struct ПоставщикСвоегоИИ: Identifiable, Hashable {
    let id: String
    let подпись: String
}

/// own_ai.premium. Цены сайта (price, price_old) и пробный период в приложении не показываются.
struct ПремиумСвоегоИИ: Equatable {
    var действует = false
    var до = ""
    var осталосьДней = 0
    var пробный = false
    var закончился = false

    init() {}

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        действует = A.да(j["active"])
        до = A.строка(j["until"])
        осталосьДней = A.целое(j["left_days"])
        пробный = A.да(j["trial"])
        закончился = A.да(j["ended"])
    }
}

/// Объект own_ai ответа сервера. Все поля необязательные: сервер может добавить новые — лишнее не мешает.
struct СостояниеСвоегоИИ: Equatable {
    /// on — раздел включён; false — в приложении ничего не показываем.
    var вкл = false
    /// login — у сайта доступна «Войти через OpenRouter» (кнопка сайта; в приложении смотрим login_app).
    var входOpenRouter = false
    /// login_app — «Войти через OpenRouter» можно показать в приложении (own_ai_or_start {app:1}); старый сервер — false.
    var входПриложения = false
    /// connected — ключ сохранён на сервере.
    var подключён = false
    /// active — свой ИИ реально используется сейчас.
    var активен = false
    /// use — переключатель «Использовать свой ИИ».
    var использовать = false
    var поставщик = ""
    var подписьПоставщика = ""
    var модель = ""
    /// tail — 4 последних знака ключа; маску рисует клиент.
    var хвост = ""
    /// via — key | openrouter.
    var через = ""
    var когда = ""
    /// err / err_text — код и готовый текст последнего отказа.
    var ошибка = ""
    var текстОшибки = ""
    var поставщики: [ПоставщикСвоегоИИ] = []
    var премиум = ПремиумСвоегоИИ()
    /// places — где ещё можно включить свой ИИ (предложение договора, OwnAIPlaces.swift); старый сервер — пусто.
    var места: [МестоСвоегоИИ] = []

    init() {}

    /// nil — значение не объект (в ответах recognize и прочих own_ai — строка-код отказа, не состояние).
    init?(_ значение: Any?) {
        guard let j = значение as? [String: Any] else { return nil }
        typealias A = МоиОбъявленияAPI
        вкл = A.да(j["on"])
        входOpenRouter = A.да(j["login"])
        входПриложения = A.да(j["login_app"])
        подключён = A.да(j["connected"])
        активен = A.да(j["active"])
        использовать = A.да(j["use"])
        поставщик = A.строка(j["provider"])
        подписьПоставщика = A.строка(j["label"])
        модель = A.строка(j["model"])
        хвост = A.строка(j["tail"])
        через = A.строка(j["via"])
        когда = A.строка(j["at"])
        ошибка = A.строка(j["err"])
        текстОшибки = A.строка(j["err_text"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var список: [ПоставщикСвоегоИИ] = []
        for элемент in (j["providers"] as? [Any]) ?? [] {
            guard let п = элемент as? [String: Any] else { continue }
            let id = A.строка(п["id"])
            guard !id.isEmpty, !список.contains(where: { $0.id == id }) else { continue }
            let подпись = A.строка(п["label"])
            список.append(ПоставщикСвоегоИИ(id: id, подпись: подпись.isEmpty ? id : подпись))
        }
        поставщики = список
        if let п = j["premium"] as? [String: Any] { премиум = ПремиумСвоегоИИ(п) }
        места = МестоСвоегоИИ.список(j["places"])
    }

    /// «•••• abcd» — ключ целиком не показывается никогда.
    var маска: String {
        let чистый = String(хвост.suffix(4))
        return чистый.isEmpty ? "••••" : "•••• " + чистый
    }

    /// Подпись поставщика: label сервера, иначе из списка, иначе id.
    var имяПоставщика: String {
        if !подписьПоставщика.isEmpty { return подписьПоставщика }
        return поставщики.first(where: { $0.id == поставщик })?.подпись ?? поставщик
    }
}

// MARK: - Отказ своего ИИ в ИИ-функциях (§5 договора)

/**
 Отказ своего ИИ в ответе ИИ-функции — готовый текст сервера и код. Форматы по договору:
   · recognize: own_ai:"<код>" | own_ai_gone:true, текст в error (ai_down — отдельно, в подаче);
   · ai_service, ai_resume: error:"own_ai", own_ai:"<код>", текст в msg;
   · ai_style, photo_search, translate: own_ai:"<код>", текст в error; consult: own_ai:"<код>", текст в text;
   · ai_job_chunk: ai_msg.
 С 14.10.2026 (ultra-site, «Свой ИИ» во всех местах, пункт 2) вид один: {ok:false, own_ai:"<код>", error:"<фраза>"};
 shot_read — ещё off:true, kp_generate — ещё ai_unavailable и quota, consult — фраза и в text, ai_import и ai_job_chunk —
 own_ai рядом с ai_msg при ok:true. Коды: key, funds, rate, limit, day, model, down, empty, bad, gone (+ own_ai_gone),
 relink. Тихое error:"ai" подсказок ответа — это Kliko AI, не свой ИИ.
 Коды key, funds, model, gone, relink — ключ сломан, денег у поставщика нет, модели нет, свой ИИ пропал, ключ больше не
 читается: кроме «Настройки своего ИИ» предлагаем и «Выключить свой ИИ» (own_ai_use {on:false}) — функции вернутся на
 Kliko AI. day — суточный потолок (100 запросов, запросы с Bearer-токеном): ждать до завтра, выключать нечего.
 */
struct ОтказСвоегоИИ: Identifiable, Equatable {
    let id = UUID()
    let код: String
    let текст: String

    init(код: String, текст: String) {
        self.код = код
        self.текст = текст
    }

    var можноВыключить: Bool { ["key", "funds", "model", "gone", "relink"].contains(код) }

    /// nil — это не отказ своего ИИ (успех, сессия, лимит, Kliko AI выключен — как раньше).
    static func из(_ j: [String: Any]) -> ОтказСвоегоИИ? {
        typealias A = МоиОбъявленияAPI
        var код = ""
        if let строка = j["own_ai"] as? String {
            код = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let число = j["own_ai"] as? NSNumber, число.intValue != 0 {
            код = "bad"
        }
        if код.isEmpty && A.да(j["own_ai_gone"]) { код = "gone" }
        if код.isEmpty && A.строка(j["error"]) == "own_ai" { код = "bad" }
        if !код.isEmpty && A.да(j["need_premium"]) { код = "premium" }
        guard !код.isEmpty else { return nil }
        return ОтказСвоегоИИ(код: код, текст: фразаПриложения(код) ?? текстОтвета(j, код: код))
    }

    /// Своя фраза вместо текста сервера: premium и gone у сайта могут звать купить Premium с баланса, назвать цену или
    /// пробный период — в приложении этого быть не должно (3.1.1); relink — «Подключите свой ИИ заново» (ключ на сервере
    /// больше не читается, поможет только новое подключение). nil — текст сервера годится.
    static func фразаПриложения(_ код: String) -> String? {
        switch код {
        case "premium": return СвойИИText.т("oai_prem_need")
        case "gone": return СвойИИText.т("oai_gone")
        case "relink": return СвойИИВходText.т("oair_relink")
        default: return nil
        }
    }

    /// Готовый текст сервера: msg, error, text, ai_msg — первый человеческий (не машинный код вроде "own_ai").
    static func текстОтвета(_ j: [String: Any]) -> String {
        текстОтвета(j, код: "")
    }

    /// То же, но без текста сервера — запасная фраза по коду (day — «до завтра»), иначе общая.
    static func текстОтвета(_ j: [String: Any], код: String) -> String {
        for поле in ["msg", "error", "text", "ai_msg"] {
            let текст = МоиОбъявленияAPI.строка(j[поле]).trimmingCharacters(in: .whitespacesAndNewlines)
            if текст.isEmpty { continue }
            if текст.range(of: "^[a-z][a-z0-9_:]{1,24}$", options: .regularExpression) != nil { continue }
            return текст
        }
        if код == "day" { return СвойИИВходText.т("oair_day") }
        return СвойИИText.т("oai_fail")
    }
}

/// Признаки успешного ответа ИИ-функции по договору «Свой ИИ» — без состояния и без главной нити.
enum ОтветСвоегоИИ {
    /**
     own_ai_run — ответ собрал свой ИИ человека; к итогу — метка «через ваш ИИ». У recognize — "fast" | "deep" (§5);
     с 14.10.2026 (ultra-site, «Свой ИИ» во всех местах, пункт 1) — own_ai_run: 1 во всех успешных ответах consult,
     ai_replies, ai_replies_dm, ai_service, photo_search, shot_read, ai_style, ai_import, ai_job_chunk, kp_generate,
     ai_resume, translate и распознавания реквизитов. Отвечал Kliko AI — поля нет, метки нет; по последнему известному
     own_ai.active не гадаем.
     */
    static func своим(_ j: [String: Any]) -> Bool {
        if let n = j["own_ai_run"] as? NSNumber { return n.intValue != 0 }
        let значение = МоиОбъявленияAPI.строка(j["own_ai_run"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return !значение.isEmpty && значение != "0" && значение.lowercased() != "false"
    }

    /// «через ваш ИИ» — если ответ собрал свой ИИ, иначе nil. Для подписи итога строкой («Готово · через ваш ИИ»).
    static func подпись(_ j: [String: Any]) -> String? {
        своим(j) ? СвойИИText.т("oai_via") : nil
    }

    /// Текст итога с пометкой « · через ваш ИИ», когда ответ собрал свой ИИ; иначе текст как есть.
    static func сПометкой(_ текст: String, _ j: [String: Any]) -> String {
        guard let пометка = подпись(j) else { return текст }
        return текст.isEmpty ? пометка : текст + " · " + пометка
    }
}

// MARK: - Запросы

@MainActor
enum СвойИИAPI {
    enum Ответ {
        case готово([String: Any])
        /// error — готовый текст; code — код сервера; need_premium — нужен Premium.
        case отказ(текст: String, код: String, нуженПремиум: Bool)
        case нуженВход
        case сеть
    }

    /// POST cabinet.php?action=<действие> {csrf, …}. Объект own_ai из ответа сразу ложится в СвойИИМодель.
    static func выполнить(_ действие: String, _ тело: [String: Any] = [:]) async -> Ответ {
        typealias A = МоиОбъявленияAPI
        let модель = СвойИИМодель.shared
        let поколение = модель.поколениеСейчас
        let j: [String: Any]
        do {
            j = try await A.отправить("cabinet.php?action=" + действие, тело: тело)
        } catch {
            return .сеть
        }
        модель.принять(j, поколение: поколение)
        if A.да(j["ok"]) { return .готово(j) }
        if A.нетСессии(j) { return .нуженВход }
        let код = A.строка(j["code"])
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        /* Premium нужен — только need_premium:true или code "premium". app_store:true (режим app_no_digital у дверей
           own_ai_connect, own_ai_model, own_ai_place, own_ai_or_start) — лишь знак, что error без цены и оплаты: сам по
           себе он не «нужен Premium», иначе настоящая причина (code "place", неверный ключ) сменилась бы фразой о Premium. */
        let нуженПремиум = A.да(j["need_premium"]) || код == "premium"
        let текст: String
        if нуженПремиум {
            /* Текст сервера про Premium может назвать цену сайта, баланс или пробный период — своя фраза. */
            текст = СвойИИText.т("oai_prem_need")
        } else if let своя = ОтказСвоегоИИ.фразаПриложения(код) {
            текст = своя
        } else {
            текст = ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) ? СвойИИText.т("oai_fail") : ошибка
        }
        return .отказ(текст: текст, код: код, нуженПремиум: нуженПремиум)
    }
}

// MARK: - Модель

/// Последнее известное состояние own_ai — одно на приложение: экран, строка настроек, подача (own:1).
@MainActor
final class СвойИИМодель: ObservableObject {
    static let shared = СвойИИМодель()

    @Published private(set) var состояние: СостояниеСвоегоИИ? = nil
    /// Последний own_ai_state не дошёл (сеть, сервер без этого действия).
    @Published private(set) var неЗагрузилось = false

    private var когдаЗагружено: Date? = nil
    private var идёт: Task<Void, Never>? = nil
    private var поколение = 0
    /// Отказы, о которых уже сказали окном в этот запуск (живой поиск по фото, кадры съёмки — не засыпать окнами).
    private var сказано: Set<String> = []
    /// Итог входа через OpenRouter, пришедший мимо экрана (kliko://own-ai из Safari): экран «Свой ИИ» показывает его
    /// заметкой и забирает (взятьИтогВхода).
    @Published private(set) var итогВхода: ИтогВходаOpenRouter? = nil
    /// Сколько экранов «Свой ИИ» открыто: возврат из Safari не кладёт второй экран поверх первого.
    private(set) var открытоЭкранов = 0

    /// Пустой: ни запросов, ни обращений к другим синглтонам.
    private init() {}

    var поколениеСейчас: Int { поколение }

    /// own_ai.on — раздел есть.
    var вкл: Bool { состояние?.вкл == true }

    /// Свой ИИ реально используется — recognize шлёт own:1.
    var активен: Bool { вкл && состояние?.активен == true }

    /// Перечитать, если давно (5 мин) или ещё не читали. Зовут экраны с точкой входа и открытие подачи.
    func загрузитьЛениво() async {
        if let когда = когдаЗагружено, Date().timeIntervalSince(когда) < 300 { return }
        await обновить()
    }

    /// own_ai_state сейчас; уже идёт — дождаться того же.
    func обновить() async {
        if let идёт {
            await идёт.value
            return
        }
        let моё = поколение
        let задача = Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_state")
            guard моё == СвойИИМодель.shared.поколение else { return }
            switch ответ {
            case .готово, .отказ, .нуженВход:
                СвойИИМодель.shared.неЗагрузилось = false
            case .сеть:
                СвойИИМодель.shared.неЗагрузилось = true
            }
            СвойИИМодель.shared.когдаЗагружено = Date()
        }
        идёт = задача
        await задача.value
        идёт = nil
    }

    /// Объект own_ai из ответа. Ответ, пришедший после выхода из аккаунта (другое поколение), не принимается.
    func принять(_ j: [String: Any], поколение моё: Int) {
        guard моё == поколение, let новое = СостояниеСвоегоИИ(j["own_ai"]) else { return }
        if новое != состояние { состояние = новое }
        когдаЗагружено = Date()
    }

    /// own_ai_use {on:false} — «Выключить свой ИИ» из окна отказа. Текст итога для человека.
    func выключить() async -> String {
        switch await СвойИИAPI.выполнить("own_ai_use", ["on": false]) {
        case .готово:
            return СвойИИText.т("oai_use_off")
        case .отказ(let текст, _, _):
            return текст
        case .нуженВход:
            return СвойИИText.т("oai_need_login")
        case .сеть:
            return СвойИИText.т("oai_no_conn")
        }
    }

    /// Сказать об отказе окном один раз за запуск на код (живой поиск, кадры съёмки).
    func сказатьОдинРаз(_ отказ: ОтказСвоегоИИ) {
        guard !сказано.contains(отказ.код) else { return }
        сказано.insert(отказ.код)
        ОкноСвоегоИИ.показатьОтказ(отказ)
    }

    /// Итог входа через OpenRouter для экрана (открытого или того, что сейчас откроется).
    func сообщитьИтогВхода(_ итог: ИтогВходаOpenRouter) {
        итогВхода = итог
    }

    /// Забрать итог входа — показать один раз.
    func взятьИтогВхода() -> ИтогВходаOpenRouter? {
        guard let итог = итогВхода else { return nil }
        итогВхода = nil
        return итог
    }

    func экранПоявился() {
        открытоЭкранов += 1
    }

    func экранУшёл() {
        открытоЭкранов = max(0, открытоЭкранов - 1)
    }

    /// Выход из аккаунта: состояние ушедшего не показываем, ответ после выхода не примется.
    func стереть() {
        поколение += 1
        идёт?.cancel()
        идёт = nil
        состояние = nil
        неЗагрузилось = false
        когдаЗагружено = nil
        сказано = []
        итогВхода = nil
    }
}

// MARK: - Окна поверх любого экрана

@MainActor
enum ОкноСвоегоИИ {
    /// Экран «Свой ИИ» — из настроек кабинета, карточки «Доступно» и окна отказа.
    static func открыть() {
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранСвоегоИИ(закрыть: закрыть)
        }
    }

    /// Отказ своего ИИ: готовый текст сервера, «Настройки своего ИИ», для key/funds/model/gone — «Выключить свой ИИ».
    static func показатьОтказ(_ отказ: ОтказСвоегоИИ) {
        ПоверхВсего.показать(большой: false) { закрыть in
            ЛистОтказаСвоегоИИ(отказ: отказ, закрыть: закрыть)
        }
    }

    /// Из окна, которое само закрывается (алерт, лист), — экран после паузы.
    static func открытьПосле(_ задержка: UInt64 = 450_000_000) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: задержка)
            ОкноСвоегоИИ.открыть()
        }
    }
}
