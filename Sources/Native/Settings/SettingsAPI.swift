import Foundation

/**
 НАСТРОЙКИ И ПРОФИЛЬ — ДАННЫЕ И ЗАПРОСЫ, ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Всё по карте кабинета (§1.4–§1.5, §6.2, §8.8): API «профиль» у сайта нет — сервер печатает профиль и все настройки в
 страницу кабинета (CAB_USER, CAB_PREF_*, LANG_OPTS, PAY_CFG, __UIP_ACC, карточка hero), поэтому они читаются из той же
 страницы, которую вкладка «Кабинет» и так качает (КабинетСайта.страницаКабинета, этап 45): второй раз её не качаем.
 Разбор сверен со снимком (site/user/kz_ru_cabinet.php.html).

 Запись — только по нажатию, тела — как у js/cabinet.min.js, транспорт — fetch изнутри страницы сайта (этап 40) через
 МоиОбъявленияAPI.отправить: токен с той же страницы, на «csrf» — свежая страница и один повтор (денег здесь нет, §8.8):
   · change_password {old, new, new2} · change_phone {phone} · set_contacts {wa_off, tg}
   · /cabinet.php?action=set_phone_policy {policy} — от корня, без /kz/<язык>, как у сайта (_ULX_BASE)
   · set_avatar {url} после upload_photo (три попытки и миниатюра — КабинетСайта.загрузитьФото, этап 42)
   · save_pref_chat {ai} · save_pref_cats {cats} · save_pref_geo {region, district, city, address, lat, lon, recv}
     + save_pref_ship {ship_scope, ship_regions} · save_pref_hours {mode, from, to} · save_pref_redact {on}
     · save_pref_escrow {off} · save_pref_pay {…} · save_pref_reserve {reserve_hold_min} · apply_pref_field {field}
   · save_pref_lang {lang} · save_onboard {state}
   · sec_devices (чтение, но POST с токеном — так у сайта) · sec_end {which} · sec_set {one_session | egov_login}
   · /api/ui_prefs.php {csrf, prefs} — prefs ЦЕЛИКОМ (__UIP_ACC с одним изменённым полем), иначе сервер сотрёт остальные.
 🔴 Не здесь, а страницей сайта: удаление аккаунта (account_delete_*), выключение eGov-входа (нужен шаг eGov otp_step_*),
 сама верификация (kyc.php, ?go=verify) — §8.8 и §8.11.
 */

/// Пара «ключ — подпись» в порядке сайта (phoneOpts, PAY_CFG.banks, GEO_KZ).
struct ПараНастройки: Hashable, Identifiable {
    let ключ: String
    let подпись: String
    var id: String { ключ }
}

/// LANG_OPTS: {c, n, u} — код, короткое имя («Рус»), адрес этой страницы на языке.
struct ЯзыкСайта: Hashable, Identifiable {
    let код: String
    let имя: String
    let адрес: String
    var id: String { код }
}

/// CAB_PREF_PAY — «Рассрочка и кредит» по умолчанию (_payPref сайта с его значениями по умолчанию).
struct НастройкиОплаты {
    var рассрочка = false
    var режим = "bank"
    var наценка = 10
    var банкиРассрочки: [String] = []
    var кредит = false
    var ставка = 25
    var банкиКредита: [String] = []
    var ссылки: [String: String] = [:]
}

/// PAY_CFG — справочник банков и их доменов, пределы ползунков.
struct СправочникОплаты {
    var банки: [ПараНастройки] = []
    var домены: [String: [String]] = [:]
    var наценкаОт = 5
    var наценкаДо = 30
    var ставкаОт = 10
    var ставкаДо = 50
}

/// Что страница кабинета знает о вошедшем и его настройках (§1.5.1, §6.0.5).
struct ПрофильКабинета {
    // CAB_USER и карточка hero
    var uid = ""
    var имя = ""
    /// CAB_USER.phone — канон номера; hero-phone data-real — как его показывает шапка («+7 778 000 83 72»).
    var телефон = ""
    var телефонПоказ = ""
    var скрытНомер = false
    var политика = "all"
    var варианты: [ПараНастройки] = []
    var неУвидели = 0
    /// CAB_PW_SELF: свой пароль уже задан — окно «Сменить пароль» (со старым), иначе «Установить свой пароль».
    var парольСвой = false
    var whatsAppВыкл = false
    var telegram = ""
    /// CAB_USER.tgOn — канал Telegram включён: поле юзернейма показывается.
    var telegramВкл = false
    var верифицирован = false
    /// #ver-rejected-banner на странице (рисует сервер неверифицированным; INFERRED в карте §1.5.1).
    var проверкаОтклонена = false
    /// const BIO_ON — KYC через eGov включён.
    var eGovВкл = true
    /// #hero-av-img src — путь «/img/uploads/…»; пусто — буква имени.
    var аватар = ""
    /// .hero-fol — «1 подписчик», как напечатал сервер (со склонением на языке страницы).
    var подписчики = ""
    /// const SELLER_URL — публичная витрина магазина; пусто — строки «Профиль» нет (как у сайта).
    var витрина = ""

    // CAB_PREF_*
    var категории: [String] = []
    var регион = ""
    var район = ""
    var город = ""
    var адрес = ""
    var широта: Double? = nil
    var долгота: Double? = nil
    var адресПолучения = false
    /// CAB_PREF_GEO.door — квартира, подъезд, этаж, домофон адреса получения (если сервер их хранит).
    var дверьАдреса: ДверьСделки? = nil
    var отправка = "all"
    var регионыОтправки: [String] = []
    /// CAB_PREF_HOURS.mode: «247», «range» или пусто («Не указывать»).
    var часы = ""
    var часыС = "09:00"
    var часыДо = "18:00"
    var чатИИ = false
    var бронь = 60
    var скрыватьДанные = false
    var гарантВыкл = false
    var минимумГаранта = 0
    var оплата = НастройкиОплаты()
    var справочникОплаты = СправочникОплаты()

    // Приложение
    var язык = "ru"
    var языки: [ЯзыкСайта] = []
    var мастерНужен = false
    var новоеСоглашение = false
    /// window.__UIP_ACC — оформление аккаунта JSON-текстом (объект целиком; nil — в аккаунте пусто или null).
    var оформление: String? = nil
    var оформлениеВкл = false
    var адресОформления = "/api/ui_prefs.php"

    // Файлы справочников (разделы для «Моих категорий», регионы для «Региона и адреса»)
    var путьРазделов = "/js/cats-ru.js"
    var путьСправочников = "/js/cab-refs.js"

    /// Тема аккаунта (__UIP_ACC.theme): auto | light | dark.
    var темаАккаунта: String {
        guard let текст = оформление, let данные = текст.data(using: .utf8),
              let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return "" }
        return (объект["theme"] as? String) ?? ""
    }

    // MARK: - Разбор страницы (чистая функция — зовётся вне главного потока: страница весит сотни килобайт)

    static func разобрать(_ html: String) -> ПрофильКабинета {
        var п = ПрофильКабинета()
        let байты = Array(html.utf8)
        if let начало = html.range(of: "const CAB_USER = {") {
            var хвост = String(html[начало.upperBound...].prefix(6000))
            if let конец = хвост.range(of: "};") { хвост = String(хвост[..<конец.upperBound]) }
            п.разобратьПользователя(хвост)
        }
        if let путь = найти(#"id="hero-av-img"\s+src="([^"]+)""#, в: html) { п.аватар = путь }
        if let номер = найти(#"id="hero-phone"\s+data-real="([^"]*)""#, в: html) { п.телефонПоказ = номер }
        if let фол = найти(#"<div class="hero-fol">([\s\S]{0,1200}?)</div>"#, в: html) {
            п.подписчики = безТегов(фол)
        }
        п.проверкаОтклонена = html.contains("id=\"ver-rejected-banner\"")
        if let витрина = найти(#"const SELLER_URL\s*=\s*("(?:[^"\\]|\\.)*")"#, в: html) { п.витрина = строкаJSON(витрина) }
        if let да = найти(#"let CAB_IS_VERIFIED\s*=\s*(true|false)"#, в: html), да == "true" { п.верифицирован = true }
        if let bio = найти(#"const BIO_ON\s*=\s*(true|false)"#, в: html) { п.eGovВкл = bio == "true" }
        п.новоеСоглашение = найти(#"window\.__TERMS_RENEW\s*=\s*(true|false)"#, в: html) == "true"
        п.разобратьНастройки(html, байты)
        п.разобратьПриложение(html, байты)
        return п
    }

    /// CAB_USER — объектный литерал JS с комментариями и ключами без кавычек: читаем по полю.
    private mutating func разобратьПользователя(_ блок: String) {
        let строка = #"("(?:[^"\\]|\\.)*")"#
        if let v = Self.найти(#"\bid:\s*"# + строка, в: блок) { uid = Self.строкаJSON(v) }
        if let v = Self.найти(#"\bname:\s*"# + строка, в: блок) {
            имя = Self.строкаJSON(v).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let v = Self.найти(#"\bphone:\s*"# + строка, в: блок) { телефон = Self.строкаJSON(v) }
        скрытНомер = Self.найти(#"\bhidePhone:\s*(true|false)"#, в: блок) == "true"
        if let v = Self.найти(#"\bphonePolicy:\s*"# + строка, в: блок) { политика = Self.строкаJSON(v) }
        if let opts = РазборJSON.после("phoneOpts:", в: Array(блок.utf8)) {
            варианты = opts.пары.map { ПараНастройки(ключ: $0.0, подпись: $0.1.текст) }.filter { !$0.ключ.isEmpty }
        }
        неУвидели = Int(Self.найти(#"\bphoneBlocked:\s*(\d+)"#, в: блок) ?? "") ?? 0
        парольСвой = Self.найти(#"\bpwSelfSet:\s*(true|false)"#, в: блок) == "true"
        whatsAppВыкл = Self.найти(#"\bwaOff:\s*(true|false)"#, в: блок) == "true"
        if let v = Self.найти(#"\btgUser:\s*"# + строка, в: блок) { telegram = Self.строкаJSON(v) }
        telegramВкл = Self.найти(#"\btgOn:\s*(true|false)"#, в: блок) == "true"
        верифицирован = Self.найти(#"\bverified:\s*(true|false)"#, в: блок) == "true"
    }

    private mutating func разобратьНастройки(_ html: String, _ байты: [UInt8]) {
        if let cats = РазборJSON.после("let CAB_PREF_CATS =", в: байты) {
            категории = cats.элементы.map { $0.текст }.filter { !$0.isEmpty }
        }
        if let гео = РазборJSON.после("let CAB_PREF_GEO =", в: байты) {
            регион = гео["region"]?.текст ?? ""
            район = гео["district"]?.текст ?? ""
            город = гео["city"]?.текст ?? ""
            адрес = гео["address"]?.текст ?? ""
            широта = Self.число(гео["lat"])
            долгота = Self.число(гео["lon"])
            адресПолучения = гео["recv"]?.да ?? false
            дверьАдреса = ДверьСделки.изПрофиля(гео["door"])
        }
        if let ship = РазборJSON.после("let CAB_PREF_SHIP =", в: байты) {
            let scope = ship["ship_scope"]?.текст ?? "all"
            отправка = (scope == "regions" || scope == "city") ? scope : "all"
            регионыОтправки = (ship["ship_regions"]?.элементы ?? []).map { $0.текст }.filter { !$0.isEmpty }
        }
        if let pay = РазборJSON.после("let CAB_PREF_PAY =", в: байты) {
            оплата = Self.разобратьОплату(pay)
        }
        if let h = РазборJSON.после("let CAB_PREF_HOURS =", в: байты) {
            часы = h["mode"]?.текст ?? ""
            let с = h["from"]?.текст ?? ""
            let до = h["to"]?.текст ?? ""
            if !с.isEmpty { часыС = с }
            if !до.isEmpty { часыДо = до }
        }
        if let чат = РазборJSON.после("let CAB_PREF_CHAT =", в: байты) {
            чатИИ = чат["ai"]?.да ?? false
        }
        /* cabPrefReserve: не число или не из барабана 15…120 с шагом 5 — 60. */
        let минуты = Int(Self.найти(#"let CAB_PREF_RESERVE\s*=\s*(\d+)"#, в: html) ?? "") ?? 60
        бронь = (минуты >= 15 && минуты <= 120 && минуты % 5 == 0) ? минуты : 60
        скрыватьДанные = Self.найти(#"let CAB_PREF_REDACT\s*=\s*(true|false)"#, в: html) == "true"
        гарантВыкл = Self.найти(#"let CAB_PREF_ESCROW_OFF\s*=\s*(true|false)"#, в: html) == "true"
        минимумГаранта = Int(Self.найти(#"MK_ESCROW_MIN\s*=\s*(\d+)"#, в: html) ?? "") ?? 0
        if let cfg = РазборJSON.после("const PAY_CFG =", в: байты) {
            var с = СправочникОплаты()
            с.банки = (cfg["banks"]?.пары ?? []).map { ПараНастройки(ключ: $0.0, подпись: $0.1.текст) }
            for (банк, список) in cfg["domains"]?.пары ?? [] {
                с.домены[банк] = список.элементы.map { $0.текст.lowercased() }.filter { !$0.isEmpty }
            }
            с.наценкаОт = Int(cfg["comm_min"]?.значение ?? 5)
            с.наценкаДо = max(с.наценкаОт, Int(cfg["comm_max"]?.значение ?? 30))
            с.ставкаОт = Int(cfg["rate_min"]?.значение ?? 10)
            с.ставкаДо = max(с.ставкаОт, Int(cfg["rate_max"]?.значение ?? 50))
            справочникОплаты = с
        }
    }

    private mutating func разобратьПриложение(_ html: String, _ байты: [UInt8]) {
        if let код = Self.найти(#"const APP_LANG_CUR\s*=\s*"([a-z]{2})""#, в: html) { язык = код }
        if let opts = РазборJSON.после("const LANG_OPTS =", в: байты) {
            языки = opts.элементы.map { о -> ЯзыкСайта in
                ЯзыкСайта(код: о["c"]?.текст ?? "", имя: о["n"]?.текст ?? "", адрес: о["u"]?.текст ?? "")
            }.filter { !$0.код.isEmpty }
        }
        мастерНужен = Self.найти(#"let CAB_ONBOARD_DUE\s*=\s*(true|false)"#, в: html) == "true"
        оформлениеВкл = Self.найти(#"window\.__UIP_ON\s*=\s*(true|false)"#, в: html) == "true"
        if let литерал = Self.найти(#"window\.__UIP_URL\s*=\s*("(?:[^"\\]|\\.)*")"#, в: html) {
            let путь = Self.строкаJSON(литерал)
            if путь.hasPrefix("/") { адресОформления = путь }
        }
        if let acc = РазборJSON.после("window.__UIP_ACC=", в: байты), case .объект = acc,
           let данные = try? JSONSerialization.data(withJSONObject: Self.значение(acc)),
           let текст = String(data: данные, encoding: .utf8) {
            оформление = текст
        }
        if let путь = Self.найти(#"src="(/js/cats-[a-z]+\.js[^"]*)""#, в: html) { путьРазделов = путь }
        if let путь = Self.найти(#"src="(/js/cab-refs\.js[^"]*)""#, в: html) { путьСправочников = путь }
    }

    private static func разобратьОплату(_ pay: ДанныеJSON) -> НастройкиОплаты {
        var о = НастройкиОплаты()
        о.рассрочка = pay["installment"]?.да ?? false
        о.режим = (pay["installment_mode"]?.текст ?? "") == "notary" ? "notary" : "bank"
        let наценка = Int(pay["installment_commission"]?.значение ?? 0)
        о.наценка = наценка > 0 ? наценка : 10
        о.банкиРассрочки = (pay["installment_banks"]?.элементы ?? []).map { $0.текст }.filter { !$0.isEmpty }
        о.кредит = pay["credit"]?.да ?? false
        let ставка = Int(pay["credit_rate"]?.значение ?? 0)
        о.ставка = ставка > 0 ? ставка : 25
        о.банкиКредита = (pay["credit_banks"]?.элементы ?? []).map { $0.текст }.filter { !$0.isEmpty }
        for (банк, ссылка) in pay["links"]?.пары ?? [] where !ссылка.текст.isEmpty {
            о.ссылки[банк] = ссылка.текст
        }
        return о
    }

    // MARK: - Мелочи разбора

    /// ДанныеJSON → значение для JSONSerialization (объект целиком — для /api/ui_prefs.php).
    static func значение(_ д: ДанныеJSON) -> Any {
        switch д {
        case .объект(let пары):
            var словарь: [String: Any] = [:]
            for (ключ, v) in пары { словарь[ключ] = значение(v) }
            return словарь
        case .массив(let м):
            return м.map { значение($0) }
        case .строка(let с):
            return с
        case .число(let ч):
            if ч.isFinite && ч == ч.rounded() && abs(ч) < 1e15 { return NSNumber(value: Int64(ч)) }
            return NSNumber(value: ч)
        case .логика(let л):
            return NSNumber(value: л)
        case .пусто:
            return NSNull()
        }
    }

    private static func число(_ д: ДанныеJSON?) -> Double? {
        guard let д else { return nil }
        switch д {
        case .число(let ч): return ч.isFinite ? ч : nil
        case .строка(let с): return Double(с.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// Текст без тегов и лишних пробелов («<svg…></svg><b>1</b> подписчик» → «1 подписчик»).
    private static func безТегов(_ html: String) -> String {
        let без = html.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        let сущности = без.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        let сжато = сущности.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return сжато.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Первая группа первого совпадения.
    static func найти(_ шаблон: String, в тексте: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: []) else { return nil }
        let весь = NSRange(тексте.startIndex..<тексте.endIndex, in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь),
              совпадение.numberOfRanges > 1,
              let диапазон = Range(совпадение.range(at: 1), in: тексте) else { return nil }
        return String(тексте[диапазон])
    }

    /// Строковый литерал JS/JSON в кавычках → строка.
    static func строкаJSON(_ литерал: String) -> String {
        guard let данные = ("[" + литерал + "]").data(using: .utf8),
              let массив = (try? JSONSerialization.jsonObject(with: данные)) as? [Any],
              let первая = массив.first as? String else { return "" }
        return первая
    }
}

// MARK: - Запросы

@MainActor
enum НастройкиAPI {
    typealias A = МоиОбъявленияAPI

    /// POST JSON с csrf (МоиОбъявленияAPI.отправить: токен со страницы, на «csrf» — один повтор).
    static func отправить(_ хвост: String, _ тело: [String: Any], отКорня: Bool = false) async throws -> [String: Any] {
        try await A.отправить(хвост, тело: тело, отКорня: отКорня)
    }

    /// ulxErr сайта: текст сервера, если это не машинный код; auth — «войдите заново»; иначе «Ошибка».
    static func ошибка(_ j: [String: Any]) -> String {
        if A.нетСессии(j) { return НастройкиText.т("auth") }
        let текст = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if текст.isEmpty || КабинетСайта.машинныйКод(текст) { return НастройкиText.т("err_generic") }
        return текст
    }

    /// Сбой транспорта — «Нет соединения», как у сайта (err_no_conn).
    static func сбой(_ ошибка: Error) -> String {
        НастройкиText.т("err_no_conn")
    }

    /**
     avatarUpload сайта: uploadImageSmart (три попытки upload_photo и миниатюра, этап 42) → set_avatar {url: url || thumb}.
     Итог — ответ set_avatar с добавленным «_url» (что стало аватаром), или ответ загрузки, если она не удалась.
     */
    static func сменитьАватар(картинка: Data, миниатюра: Data) async throws -> [String: Any] {
        let основное = ОбработкаФото.dataURL(картинка)
        let мини = миниатюра.isEmpty ? "" : ОбработкаФото.dataURL(миниатюра)
        var загрузка: [String: Any] = [:]
        var повторили = false
        while true {
            let токен = try await A.токенСейчас()
            if токен.isEmpty { return ["ok": false, "error": "auth"] }
            загрузка = try await КабинетСайта.загрузитьФото(картинка: основное, миниатюра: мини, токен: токен).json
            if A.строка(загрузка["error"]) == "csrf" && !повторили {
                повторили = true
                A.забыть()
                continue
            }
            break
        }
        let url = A.строка(загрузка["url"])
        let адрес = url.isEmpty ? A.строка(загрузка["thumb"]) : url
        guard A.да(загрузка["ok"]), !адрес.isEmpty else { return загрузка }
        var ответ = try await отправить("cabinet.php?action=set_avatar", ["url": адрес])
        ответ["_url"] = адрес
        return ответ
    }

    /**
     /api/ui_prefs.php {csrf, prefs} — prefs целиком: __UIP_ACC страницы с одним изменённым полем (карта §8.8, «Риски»).
     Уходит, только если __UIP_ON и в аккаунте уже есть объект оформления: иначе у нас нет остальных полей, и отправка
     стёрла бы чужие настройки. Итог — новый объект JSON-текстом или nil (не ушло / сервер не принял).
     */
    static func сохранитьОформление(поле: String, значение: Any, профиль: ПрофильКабинета) async -> String? {
        guard профиль.оформлениеВкл, let текст = профиль.оформление, let данные = текст.data(using: .utf8),
              var prefs = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return nil }
        prefs[поле] = значение
        guard let j = try? await отправить(профиль.адресОформления, ["prefs": prefs], отКорня: true),
              A.да(j["ok"]),
              let новые = try? JSONSerialization.data(withJSONObject: prefs),
              let новыйТекст = String(data: новые, encoding: .utf8) else { return nil }
        return новыйТекст
    }

    /// Проверка ссылки на оплату (_cabPayLinkOk): nil — пусто; true — https на домене банка или его поддомене.
    nonisolated static func ссылкаГодна(_ банк: String, _ ссылка: String, домены: [String: [String]]) -> Bool? {
        let t = ссылка.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.range(of: "[\\s<>\"'`\\\\]", options: .regularExpression) != nil { return false }
        guard let хост = ПрофильКабинета.найти(#"^(?i:https)://([^/?#]+)(?:[/?#]|$)"#, в: t) else { return false }
        var h = хост.lowercased()
        if h.contains("@") || h.contains(":") { return false }
        if h.hasSuffix(".") { h = String(h.dropLast()) }
        for домен in домены[банк] ?? [] where h == домен || h.hasSuffix("." + домен) { return true }
        return false
    }
}
