import SwiftUI
import UIKit

/**
 ПЛАТНЫЕ УСЛУГИ И БИЗНЕС — ДАННЫЕ, ЗАПРОСЫ, МОДЕЛЬ. ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Карта кабинета §3.3, §6.6, §6.9.2, §6.9.4, §8.10; код — js/cabinet.min.js (openPromote, promoBase / promoDisc,
 upgSlotsPaneHTML, upgComboPaneHTML, upgAiPaneHTML, renderSlotBanner, showProOffer / pxdRender, clubOpen / _clubRender,
 showFounder / _founderPartner, splitCard / splitSubmit, openReqWizard / _rwLookup / _rwSave) и докачанный модуль
 js/cabinet-business.min.js (b2bLoadOrders / _b2bRow). Транспорт — КабинетСайта (этап 40): fetch изнутри страницы сайта.

 Откуда что:
   · страница кабинета (JSON-API у этого нет, §0.7): PROMO_CFG, AI_PACKS, AI_DISC, AI_FREE, COMBO_PACKS, window.CAB_AI,
     FREE_SLOTS, IS_VERIFIED, IS_SHOP, IS_PRO, PRO_* (статус, тарифы, уровни функций), let CAB_SPLIT, let
     CAB_IS_VERIFIED, const CAB_COMPANY (реквизиты и шаблон счёта). Сверено по снимку user/kz_ru_cabinet.php.html;
   · только чтение: GET cabinet.php?action=promo_quote&preset=<key> (серверная цена пакета ТОП — карта §3.8 советует
     показывать её, где она есть), GET my_items (slots: тарифы слотов и их скидка), GET ai_scan_credits, GET ref_stats
     (клуб основателей), POST company_lookup_bin {csrf, bin} (реестр по БИН), POST b2b_orders_list {csrf} (заказы B2B);
   · запись без денег, только по нажатию, каждая за своим рубильником: save_company {csrf, company, invoice_tpl}
     (Config.реквизитыКомпании) и split_submit {csrf} (Config.заявкаМагазина). Тела — как у сайта.

 🔴 ДЕНЬГИ (Config.цифровыеПокупки = false, правило App Store 3.1.1): promote_item / promote_bulk, buy_slots, buy_combo,
 buy_pro / buy_pro_card, buy_ai_package, start_trial, ai_scan_pay здесь НЕ ВЫЗЫВАЮТСЯ вовсе — ни при выключенном, ни при
 включённом рубильнике: пока владелец не решил вопрос In-App Purchase, покупка — страница кабинета сайта. Единственная
 запись за этим рубильником — промокод (redeem_coupon, окно клуба): денег он не списывает, но сайт прячет его вместе с
 покупками (klkAppNoDigital), поэтому и здесь он только при включённом рубильнике.

 Всё личное — в памяти модели; выход стирает (ВыходНачисто), ответ, пришедший после выхода, не примется (поколение).
 */

// MARK: - Значения страницы кабинета

/// Пакет ТОП из PROMO_CFG.packages: {key, label, top_days, bumps, price}.
struct ПакетПродвижения: Equatable, Identifiable {
    let id: String
    let подпись: String
    let днейТоп: Int
    let поднятий: Int
    let цена: Int
}

/// AI_PACKS[week|month|quarter]: {days, price, label}.
struct ПакетИИ: Equatable, Identifiable {
    let id: String
    let дней: Int
    let цена: Int
}

/// COMBO_PACKS[start|active|max]: {slots, ai_days, price, label}.
struct КомбоПакет: Equatable, Identifiable {
    let id: String
    let слотов: Int
    let днейИИ: Int
    let цена: Int
    let подпись: String
}

/// PRO_TIERS[]: {level, key, name, price}.
struct ТарифПРО: Equatable, Identifiable {
    let уровень: Int
    let название: String
    let цена: Int
    var id: Int { уровень }
}

/// window.CAB_AI — квота Kliko AI и её подписи (сервер присылает их сам, на языке страницы).
struct КвотаИИБизнеса: Equatable {
    var показ = false
    var платно = false
    var бесплатно = false
    var лимит = 0
    var осталось = 0
    var верифицирован = false
    var подпись = ""
    var безлимит = ""
    var осталосьСлово = ""
    var бесплатноЗаголовок = ""
    var бесплатноПодпись = ""
}

/// CAB_COMPANY — то, что мастер реквизитов показывает и отправляет (_rw, _rwSave), и шаблон счёта (tpl).
struct РеквизитыКомпании: Equatable {
    var название = ""
    var бин = ""
    var руководитель = ""
    var адрес = ""
    var банк = ""
    var бик = ""
    var иик = ""
    var кбе = ""
    var типСчёта = ""
    var телефон = ""
    var шаблон = ""

    /// _splitReqsOk сайта: название, БИН из 12 цифр и ИИК.
    var заполнены: Bool {
        let цифры = бин.filter { $0.isASCII && $0.isNumber }
        return !название.trimmingCharacters(in: .whitespaces).isEmpty && цифры.count == 12
            && !иик.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Всё, что платные услуги и бизнес берут со страницы кабинета.
struct СтраницаБизнеса: Equatable {
    var uid = ""
    var пакеты: [ПакетПродвижения] = []
    var скидкаПродвижения = 0
    var ценаДняТоп = 0
    var пакетыИИ: [ПакетИИ] = []
    var скидкаИИ = 0
    var иИБесплатно = false
    var комбо: [КомбоПакет] = []
    var квота = КвотаИИБизнеса()
    var бесплатныхСлотов = 5
    var верифицирован = false
    var магазин = false
    var pro = false
    var proАктивен = false
    var proПробный = false
    var proДо = ""
    var proДнейОсталось: Int? = nil
    var proЦена = 0
    var proБесплатно = false
    var тарифыПРО: [ТарифПРО] = []
    var уровеньПРО = 0
    var уровеньПокупки = 1
    var минУровни: [String: Int] = [:]
    var слотыПРО: [Int: Int] = [:]
    var днейИИПРО: [Int: Int] = [:]
    var бесплатныхСлотовПРО = 10
    var безлимитСлотов = 10000
    var статусМагазина = "none"
    var причинаОтказа = ""
    var верифицированМагазин = false
    var реквизиты = РеквизитыКомпании()

    /// proHasClient сайта: PRO_TIER_CUR ≥ PRO_FEATURE_MIN[функция] (нет в списке — 1).
    func естьФункция(_ ключ: String) -> Bool {
        уровеньПРО >= (минУровни[ключ] ?? 1)
    }

    /// promoDisc сайта: цена со скидкой PROMO_CFG.discount_pct, округлённая до десятков.
    func соСкидкойПродвижения(_ цена: Int) -> Int {
        guard скидкаПродвижения > 0 else { return цена }
        let сырая = Double(цена) * Double(100 - скидкаПродвижения) / 100 / 10
        return max(0, 10 * Int(сырая.rounded()))
    }

    /// AI_DISC у пакетов Kliko AI, комбо и PRO — Math.round(price*(100-AI_DISC)/100), без округления до десятков.
    func соСкидкойИИ(_ цена: Int) -> Int {
        guard скидкаИИ > 0 else { return цена }
        return Int((Double(цена) * Double(100 - скидкаИИ) / 100).rounded())
    }

    /// Разбор HTML страницы кабинета. nonisolated — зовётся вне главного потока.
    static func разобрать(_ html: String) -> СтраницаБизнеса {
        var с = СтраницаБизнеса()
        let байты = Array(html.utf8)
        if let промо = РазборJSON.после("const PROMO_CFG", в: байты) {
            с.пакеты = промо["packages"]?.элементы.map { п -> ПакетПродвижения in
                ПакетПродвижения(id: п["key"]?.текст ?? "", подпись: п["label"]?.текст ?? "",
                                 днейТоп: Int(п["top_days"]?.значение ?? 0), поднятий: Int(п["bumps"]?.значение ?? 0),
                                 цена: Int(п["price"]?.значение ?? 0))
            }.filter { !$0.id.isEmpty } ?? []
            с.скидкаПродвижения = Int(промо["discount_pct"]?.значение ?? 0)
            с.ценаДняТоп = Int(промо["top_day_price"]?.значение ?? 0)
        }
        if let ии = РазборJSON.после("const AI_PACKS", в: байты) {
            /* Порядок — ["week","month","quarter"].filter(e=>AI_PACKS[e]), как у сайта. */
            let порядок: [String] = ["week", "month", "quarter"]
            с.пакетыИИ = порядок.compactMap { ключ -> ПакетИИ? in
                guard let п = ии[ключ] else { return nil }
                return ПакетИИ(id: ключ, дней: Int(п["days"]?.значение ?? 0), цена: Int(п["price"]?.значение ?? 0))
            }
        }
        if let комбо = РазборJSON.после("const COMBO_PACKS", в: байты) {
            let порядок: [String] = ["start", "active", "max"]
            с.комбо = порядок.compactMap { ключ -> КомбоПакет? in
                guard let п = комбо[ключ] else { return nil }
                return КомбоПакет(id: ключ, слотов: Int(п["slots"]?.значение ?? 0), днейИИ: Int(п["ai_days"]?.значение ?? 0),
                                  цена: Int(п["price"]?.значение ?? 0), подпись: п["label"]?.текст ?? "")
            }
        }
        if let ии = РазборJSON.после("window.CAB_AI", в: байты) {
            с.квота = разобратьКвоту(ии)
        }
        с.скидкаИИ = Int(найти(#"const AI_DISC\s*=\s*(\d+)"#, в: html) ?? "") ?? 0
        с.иИБесплатно = найти(#"const AI_FREE\s*=\s*(true|false)"#, в: html) == "true"
        с.бесплатныхСлотов = Int(найти(#"const FREE_SLOTS\s*=\s*(\d+)"#, в: html) ?? "") ?? 5
        с.верифицирован = найти(#"const IS_VERIFIED\s*=\s*(true|false)"#, в: html) == "true"
        с.магазин = найти(#"const IS_SHOP\s*=\s*(true|false)"#, в: html) == "true"
        с.pro = найти(#"const IS_PRO\s*=\s*(true|false)"#, в: html) == "true"
        разобратьПРО(html, байты: байты, в: &с)
        if let сплит = РазборJSON.после("let CAB_SPLIT", в: байты) {
            let статус = сплит["status"]?.текст ?? ""
            с.статусМагазина = статус.isEmpty ? "none" : статус
            с.причинаОтказа = сплит["reason"]?.текст ?? ""
        }
        с.верифицированМагазин = найти(#"let CAB_IS_VERIFIED\s*=\s*(true|false)"#, в: html) == "true"
        if let к = РазборJSON.после("const CAB_COMPANY", в: байты) {
            с.реквизиты = разобратьРеквизиты(к)
        }
        return с
    }

    private static func разобратьКвоту(_ ии: ДанныеJSON) -> КвотаИИБизнеса {
        var к = КвотаИИБизнеса()
        к.показ = ии["show"]?.да ?? false
        к.платно = ии["paid"]?.да ?? false
        к.бесплатно = ии["free"]?.да ?? false
        к.лимит = Int(ии["limit"]?.значение ?? 0)
        к.осталось = Int(ии["rem"]?.значение ?? 0)
        к.верифицирован = ии["verified"]?.да ?? false
        к.подпись = ии["t"]?.текст ?? ""
        к.безлимит = ии["unlimited"]?.текст ?? ""
        к.осталосьСлово = ии["left"]?.текст ?? ""
        к.бесплатноЗаголовок = ии["free_t"]?.текст ?? ""
        к.бесплатноПодпись = ии["free_s"]?.текст ?? ""
        return к
    }

    private static func разобратьПРО(_ html: String, байты: [UInt8], в с: inout СтраницаБизнеса) {
        с.proАктивен = найти(#"const PRO_ACTIVE\s*=\s*(true|false)"#, в: html) == "true"
        с.proПробный = найти(#"const PRO_IS_TRIAL\s*=\s*(true|false)"#, в: html) == "true"
        с.proДо = найти(#"const PRO_UNTIL\s*=\s*"([^"]*)""#, в: html) ?? ""
        с.proДнейОсталось = Int(найти(#"const PRO_DAYS_LEFT\s*=\s*(-?\d+)"#, в: html) ?? "")
        с.proЦена = Int(найти(#"const PRO_PRICE\s*=\s*(\d+)"#, в: html) ?? "") ?? 0
        с.proБесплатно = найти(#"const PRO_FREE\s*=\s*(true|false)"#, в: html) == "true"
        с.уровеньПРО = Int(найти(#"const PRO_TIER_CUR\s*=\s*(\d+)"#, в: html) ?? "") ?? 0
        с.уровеньПокупки = Int(найти(#"const PRO_BUY_TIER\s*=\s*(\d+)"#, в: html) ?? "") ?? 1
        с.бесплатныхСлотовПРО = Int(найти(#"const PRO_FREE_SLOTS\s*=\s*(\d+)"#, в: html) ?? "") ?? 10
        с.безлимитСлотов = Int(найти(#"const PRO_SLOTS_UNLIM\s*=\s*(\d+)"#, в: html) ?? "") ?? 10000
        if let тарифы = РазборJSON.после("const PRO_TIERS", в: байты) {
            с.тарифыПРО = тарифы.элементы.map { т -> ТарифПРО in
                ТарифПРО(уровень: Int(т["level"]?.значение ?? 0), название: т["name"]?.текст ?? "",
                         цена: Int(т["price"]?.значение ?? 0))
            }.filter { $0.уровень > 0 }.sorted { $0.уровень < $1.уровень }
        }
        /* Нет PRO_TIERS — как у сайта: [{level:1, name:"PRO", price:PRO_PRICE}]. */
        if с.тарифыПРО.isEmpty {
            с.тарифыПРО = [ТарифПРО(уровень: 1, название: "PRO", цена: с.proЦена)]
        }
        if let мин = РазборJSON.после("const PRO_FEATURE_MIN", в: байты) {
            for (ключ, значение) in мин.пары {
                с.минУровни[ключ] = Int(значение.значение)
            }
        }
        /* PRO_SLOTS и PRO_AI_DAYS — объекты JS с числовыми ключами ({1:40,2:95}), не JSON: читаем пары сами. */
        с.слотыПРО = пары(найти(#"const PRO_SLOTS\s*=\s*\{([^}]*)\}"#, в: html) ?? "")
        с.днейИИПРО = пары(найти(#"const PRO_AI_DAYS\s*=\s*\{([^}]*)\}"#, в: html) ?? "")
    }

    private static func разобратьРеквизиты(_ к: ДанныеJSON) -> РеквизитыКомпании {
        var р = РеквизитыКомпании()
        р.название = к["name"]?.текст ?? ""
        р.бин = к["bin"]?.текст ?? ""
        р.руководитель = к["director"]?.текст ?? ""
        р.адрес = к["addr"]?.текст ?? ""
        р.банк = к["bank"]?.текст ?? ""
        р.бик = к["bik"]?.текст ?? ""
        /* e.iik||e.iban — как _splitReqsOk сайта. */
        let иик = к["iik"]?.текст ?? ""
        р.иик = иик.isEmpty ? (к["iban"]?.текст ?? "") : иик
        р.кбе = к["kbe"]?.текст ?? ""
        р.типСчёта = к["acc_type"]?.текст ?? ""
        р.телефон = к["phone"]?.текст ?? ""
        р.шаблон = к["tpl"]?.текст ?? ""
        return р
    }

    /// «1:40,2:95,3:190» → [1: 40, 2: 95, 3: 190].
    private static func пары(_ текст: String) -> [Int: Int] {
        var итог: [Int: Int] = [:]
        for кусок in текст.split(separator: ",") {
            let части = кусок.split(separator: ":")
            guard части.count == 2,
                  let ключ = Int(части[0].trimmingCharacters(in: .whitespaces)),
                  let значение = Int(части[1].trimmingCharacters(in: .whitespaces)) else { continue }
            итог[ключ] = значение
        }
        return итог
    }

    private static func найти(_ шаблон: String, в тексте: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: []) else { return nil }
        let весь = NSRange(тексте.startIndex..<тексте.endIndex, in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь),
              совпадение.numberOfRanges > 1,
              let диапазон = Range(совпадение.range(at: 1), in: тексте) else { return nil }
        return String(тексте[диапазон])
    }
}

// MARK: - Ответы API

/// promo_quote: {ok, enough, preset, label, price, balance, need}.
struct КотировкаТопа: Equatable {
    let хватает: Bool
    let подпись: String
    let цена: Int
    let баланс: Int
    let нехватка: Int
}

/// Тариф слотов из my_items → slots.tiers[{price, slots}].
struct ТарифСлотов: Equatable, Identifiable {
    let слотов: Int
    let цена: Int
    var id: Int { слотов }
}

/// slots ответа my_items для «Слоты объявлений» (upgSlotsPaneHTML).
struct СлотыТарифа: Equatable {
    var лимит = 0
    var занято = 0
    var бесплатно = 0
    var скидка = 0
    var тарифы: [ТарифСлотов] = []

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        лимит = A.целое(j["limit"])
        занято = A.целое(j["used"])
        бесплатно = A.целое(j["free"])
        скидка = A.целое(j["discount_pct"])
        let сырые: [Any] = (j["tiers"] as? [Any]) ?? []
        тарифы = сырые.compactMap { запись -> ТарифСлотов? in
            guard let т = запись as? [String: Any] else { return nil }
            return ТарифСлотов(слотов: A.целое(т["slots"]), цена: A.целое(т["price"]))
        }
    }

    /// Цена тарифа со скидкой slots.discount_pct — как в upgSlotsPaneHTML (до десятков).
    func соСкидкой(_ цена: Int) -> Int {
        guard скидка > 0 else { return цена }
        let сырая = Double(цена) * Double(100 - скидка) / 100 / 10
        return max(0, 10 * Int(сырая.rounded()))
    }
}

/// Партнёрская программа из ref_stats.stats.partner (_founderPartner сайта; ключи — по-русски, как шлёт сервер).
struct ПартнёрКлуба: Equatable {
    let ставка: Double
    let текущий: Int
    let приведено: Int
    let накоплено: Int
    let выплачено: Int
    let порог: Int
}

/// ref_stats.stats (_clubRender сайта).
struct КлубОснователей: Equatable {
    let ссылка: String
    let номер: Int
    let ступень: String
    let скидка: Double
    let база: Double
    let бонус: Double
    let потолок: Double
    let шаг: Double
    let друзей: Int
    let акцииИдут: Bool
    let партнёр: ПартнёрКлуба?

    init(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        ссылка = A.строка(j["link"])
        номер = A.целое(j["member_no"])
        ступень = A.строка(j["tier"])
        скидка = A.число(j["discount_pct"])
        база = A.число(j["base_pct"])
        бонус = A.число(j["bonus_pct"])
        /* +e.cap_pct||90 */
        let потолокСервера = A.число(j["cap_pct"])
        потолок = потолокСервера != 0 ? потолокСервера : 90
        шаг = A.число(j["step_pct"])
        друзей = A.целое(j["invited"])
        /* !1!==e.promos_on — выключено, только если сервер прислал именно false. */
        if let n = j["promos_on"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() {
            акцииИдут = n.boolValue
        } else {
            акцииИдут = true
        }
        if let п = j["partner"] as? [String: Any] {
            партнёр = ПартнёрКлуба(ставка: A.число(п["ставка"]), текущий: A.целое(п["текущий"]),
                                   приведено: A.целое(п["приведено"]), накоплено: A.целое(п["накоплено"]),
                                   выплачено: A.целое(п["выплачено"]), порог: A.целое(п["порог"]))
        } else {
            партнёр = nil
        }
    }

    /// _clubFmt: до сотых, целое — без дроби, иначе с запятой.
    static func процент(_ x: Double) -> String {
        let округлено = (x * 100).rounded() / 100
        if округлено == округлено.rounded() && abs(округлено) < 1e12 { return String(Int(округлено)) }
        return String(округлено).replacingOccurrences(of: ".", with: ",")
    }
}

/// Заказ B2B (b2b_orders_list → as_seller[] / as_buyer[], _b2bRow модуля business).
struct ЗаказB2B: Equatable, Identifiable {
    let id: String
    let номер: String
    let статус: String
    /// Роль: я продавец (as_seller) — контрагент покупатель; иначе поставщик.
    let продаю: Bool
    let контрагент: String
    let гость: Bool
    let телефон: String
    let почта: String
    let сумма: Int
    let позиции: [(String, Int)]
    let до: String
    /// _b2bKind: goods · services · mixed — у услуг после оплаты сразу «Завершить», без «Отгрузить» (этап 50).
    let вид: String

    static func == (a: ЗаказB2B, b: ЗаказB2B) -> Bool {
        a.id == b.id && a.статус == b.статус && a.сумма == b.сумма && a.до == b.до
    }

    init(_ j: [String: Any], продаю роль: Bool) {
        typealias A = МоиОбъявленияAPI
        id = A.строка(j["id"])
        номер = A.строка(j["no"])
        let с = A.строка(j["status"])
        статус = с.isEmpty ? "new" : с
        продаю = роль
        let покупатель = (j["buyer"] as? [String: Any]) ?? [:]
        let продавец = (j["seller"] as? [String: Any]) ?? [:]
        контрагент = A.строка(роль ? покупатель["name"] : продавец["name"])
        гость = роль && A.да(j["guest"])
        телефон = A.строка(покупатель["phone"])
        почта = A.строка(покупатель["email"])
        сумма = КошелёкAPI.тенге(j["total"])
        let сырые: [Any] = (j["items"] as? [Any]) ?? []
        позиции = сырые.compactMap { запись -> (String, Int)? in
            guard let п = запись as? [String: Any] else { return nil }
            return (A.строка(п["name"]), A.целое(п["qty"]))
        }
        до = A.строка(j["valid_until"])
        let к = A.строка(j["kind"])
        вид = (к == "services" || к == "mixed") ? к : "goods"
    }
}

// MARK: - Модель

@MainActor
final class БизнесМодель: ObservableObject {
    static let shared = БизнесМодель()

    enum Загрузка: Equatable {
        case нет
        case идёт
        case готово
        case нуженВход
        case ошибка(String)
    }

    @Published private(set) var страница: СтраницаБизнеса? = nil
    @Published private(set) var загрузка: Загрузка = .нет
    @Published private(set) var котировки: [String: КотировкаТопа] = [:]
    /// Ключи пакетов, по которым promo_quote не ответил: у такого — текст сайта «Не удалось проверить баланс…».
    @Published private(set) var котировкиБезОтвета: Set<String> = []
    @Published private(set) var слоты: СлотыТарифа? = nil
    @Published private(set) var запусков: Int? = nil
    @Published private(set) var клуб: КлубОснователей? = nil
    @Published private(set) var клубЗагрузка: Загрузка = .нет
    @Published private(set) var заказыПродаю: [ЗаказB2B]? = nil
    @Published private(set) var заказыПокупаю: [ЗаказB2B]? = nil
    /// Короткое сообщение внизу экрана (toast сайта).
    @Published private(set) var плашка: String? = nil

    private var поколение = 0

    private init() {}

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    // MARK: Страница кабинета

    /// Страница кабинета: значения для всех трёх экранов. Разбор — вне главного потока.
    func загрузитьСтраницу() async {
        let моё = поколение
        if страница == nil { загрузка = .идёт }
        do {
            let ответ = try await КабинетСайта.страницаКабинета()
            guard моё == поколение else { return }
            if ответ.состояние.вошёл == false {
                сбросить()
                загрузка = .нуженВход
                return
            }
            МоиОбъявленияAPI.запомнитьТокен(ответ.состояние.csrf)
            let html = ответ.html
            var готовая = await Task.detached(priority: .userInitiated) { () -> СтраницаБизнеса in
                СтраницаБизнеса.разобрать(html)
            }.value
            готовая.uid = ответ.состояние.uid
            guard моё == поколение else { return }
            /* Вошёл другой человек — чужие реквизиты, заказы и клуб не показываем ни секунды. */
            if let была = страница, !была.uid.isEmpty, была.uid != готовая.uid {
                сбросить()
            }
            страница = готовая
            загрузка = .готово
        } catch {
            guard моё == поколение else { return }
            let текст = (error as? КабинетСайта.Сбой) == .сеть ? т("no_conn") : т("err_generic")
            if страница == nil { загрузка = .ошибка(текст) } else { показать(текст) }
        }
    }

    // MARK: Платные услуги — только чтение

    /// promo_quote по каждому пакету, slots из my_items и ai_scan_credits. Ничего не покупает.
    func загрузитьУслуги() async {
        await загрузитьСтраницу()
        guard let с = страница else { return }
        let моё = поколение
        typealias A = МоиОбъявленияAPI
        for пакет in с.пакеты where пакет.id.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            let j = try? await МоиОбъявленияAPI.получить("cabinet.php?action=promo_quote&preset=" + пакет.id)
            guard моё == поколение else { return }
            if let j, A.да(j["ok"]) {
                котировки[пакет.id] = КотировкаТопа(хватает: A.да(j["enough"]),
                                                    подпись: A.строка(j["label"]).isEmpty ? пакет.подпись : A.строка(j["label"]),
                                                    цена: КошелёкAPI.тенге(j["price"]),
                                                    баланс: КошелёкAPI.тенге(j["balance"]),
                                                    нехватка: КошелёкAPI.тенге(j["need"]))
                котировкиБезОтвета.remove(пакет.id)
            } else {
                котировкиБезОтвета.insert(пакет.id)
            }
        }
        if let j = try? await МоиОбъявленияAPI.получить("cabinet.php?action=my_items"),
           МоиОбъявленияAPI.да(j["ok"]), let сырые = j["slots"] as? [String: Any] {
            guard моё == поколение else { return }
            слоты = СлотыТарифа(сырые)
        }
        if let j = try? await МоиОбъявленияAPI.получить("cabinet.php?action=ai_scan_credits"),
           МоиОбъявленияAPI.да(j["ok"]) {
            guard моё == поколение else { return }
            запусков = МоиОбъявленияAPI.целое(j["credits"])
        }
    }

    // MARK: Клуб основателей — только чтение

    func загрузитьКлуб() async {
        let моё = поколение
        if клуб == nil { клубЗагрузка = .идёт }
        do {
            guard let j = try await МоиОбъявленияAPI.получить("cabinet.php?action=ref_stats") else {
                throw КабинетСайта.Сбой.приложение
            }
            guard моё == поколение else { return }
            if МоиОбъявленияAPI.да(j["ok"]), let статы = j["stats"] as? [String: Any] {
                клуб = КлубОснователей(статы)
                клубЗагрузка = .готово
            } else if МоиОбъявленияAPI.нетСессии(j) {
                клуб = nil
                клубЗагрузка = .нуженВход
            } else if клуб == nil {
                клубЗагрузка = .ошибка(т("club_load_failed"))
            }
        } catch {
            guard моё == поколение else { return }
            if клуб == nil { клубЗагрузка = .ошибка(т("no_conn")) }
        }
    }

    /**
     Промокод (clubApplyPromo → redeem_coupon {csrf, code}). 🔴 Только при Config.цифровыеПокупки: сайт прячет его вместе
     с покупками (klkAppNoDigital). Денег не списывает — поэтому обычная запись с одним повтором на «csrf».
     Возвращает ответ сервера целиком (окно результата разбирает причины used / expired / limit / notfound).
     */
    func применитьПромокод(_ код: String) async -> [String: Any] {
        guard Config.цифровыеПокупки else { return ["ok": false, "error": т("no_digital")] }
        do {
            return try await МоиОбъявленияAPI.отправить("cabinet.php?action=redeem_coupon", тело: ["code": код])
        } catch {
            return ["ok": false, "error": т("no_conn")]
        }
    }

    // MARK: Компания — чтение

    /// b2b_orders_list {csrf} → as_seller[], as_buyer[] (b2bLoadOrders модуля business). Сбой — как у сайта, молча.
    func загрузитьЗаказы() async {
        let моё = поколение
        guard let j = try? await МоиОбъявленияAPI.отправить("cabinet.php?action=b2b_orders_list", тело: [:]),
              МоиОбъявленияAPI.да(j["ok"]) else { return }
        guard моё == поколение else { return }
        let продаю: [Any] = (j["as_seller"] as? [Any]) ?? []
        let покупаю: [Any] = (j["as_buyer"] as? [Any]) ?? []
        заказыПродаю = продаю.compactMap { запись -> ЗаказB2B? in
            guard let з = запись as? [String: Any] else { return nil }
            return ЗаказB2B(з, продаю: true)
        }
        заказыПокупаю = покупаю.compactMap { запись -> ЗаказB2B? in
            guard let з = запись as? [String: Any] else { return nil }
            return ЗаказB2B(з, продаю: false)
        }
    }

    /// Итог поиска по БИН (_rwLookup): найдено — поля из реестра; нет — текст сайта.
    enum ИтогБИН {
        case найдено(название: String, руководитель: String, адрес: String)
        case ненайдено(String)
    }

    /// company_lookup_bin {csrf, bin} — только чтение реестра, по нажатию «Найти».
    func найтиПоБИН(_ бин: String) async -> ИтогБИН {
        do {
            let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=company_lookup_bin", тело: ["bin": бин])
            typealias A = МоиОбъявленияAPI
            guard A.да(j["ok"]) else {
                let ошибка = A.строка(j["error"])
                return .ненайдено(ошибка.isEmpty ? т("rw_manual") : ошибка)
            }
            guard A.да(j["found"]) else { return .ненайдено(т("cmp_bin_none")) }
            return .найдено(название: A.строка(j["name"]), руководитель: A.строка(j["director"]),
                            адрес: A.строка(j["addr"]))
        } catch {
            return .ненайдено(т("rw_manual"))
        }
    }

    // MARK: Компания — запись (по нажатию, каждая за своим рубильником)

    /**
     _rwSave сайта: save_company {csrf, company: {name, bin, director, addr, bank, bik, iik, kbe, acc_type}, invoice_tpl}.
     acc_type и invoice_tpl — прежние из CAB_COMPANY (мастер их не меняет). nil — сохранено; иначе текст ошибки сайта.
     */
    func сохранитьРеквизиты(_ р: РеквизитыКомпании) async -> String? {
        guard Config.реквизитыКомпании else { return т("err_generic") }
        let прежние = страница?.реквизиты ?? РеквизитыКомпании()
        let компания: [String: Any] = [
            "name": р.название, "bin": р.бин, "director": р.руководитель, "addr": р.адрес, "bank": р.банк,
            "bik": р.бик, "iik": р.иик, "kbe": прежние.кбе, "acc_type": прежние.типСчёта
        ]
        do {
            let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=save_company",
                                                        тело: ["company": компания, "invoice_tpl": прежние.шаблон])
            guard МоиОбъявленияAPI.да(j["ok"]) else {
                let ошибка = МоиОбъявленияAPI.строка(j["error"])
                return ошибка.isEmpty ? т("err_generic") : ошибка
            }
            /* Object.assign(CAB_COMPANY, t) — то же у себя. */
            var новые = прежние
            новые.название = р.название
            новые.бин = р.бин
            новые.руководитель = р.руководитель
            новые.адрес = р.адрес
            новые.банк = р.банк
            новые.бик = р.бик
            новые.иик = р.иик
            страница?.реквизиты = новые
            показать(т("cmp_saved"))
            return nil
        } catch {
            return т("no_conn")
        }
    }

    /// Итог заявки «Стать магазином» (splitSubmit сайта).
    enum ИтогЗаявкиМагазина {
        case отправлена
        case нужнаВерификация(String)
        case нужныРеквизиты(String)
        case ошибка(String)
    }

    /// split_submit {csrf}. Только по нажатию «Стать магазином» и подтверждению.
    func податьЗаявкуМагазина() async -> ИтогЗаявкиМагазина {
        guard Config.заявкаМагазина else { return .ошибка(т("err_generic")) }
        do {
            let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=split_submit", тело: [:])
            typealias A = МоиОбъявленияAPI
            let ошибка = A.строка(j["error"])
            if A.да(j["ok"]) {
                let статус = A.строка(j["status"])
                страница?.статусМагазина = статус.isEmpty ? "pending" : статус
                страница?.причинаОтказа = ""
                показать(т("split_submitted"))
                return .отправлена
            }
            if A.да(j["need_verify"]) { return .нужнаВерификация(ошибка.isEmpty ? т("split_need_verify") : ошибка) }
            if A.да(j["need_reqs"]) { return .нужныРеквизиты(ошибка.isEmpty ? т("split_need_reqs") : ошибка) }
            return .ошибка(ошибка.isEmpty ? т("err_generic") : ошибка)
        } catch {
            return .ошибка(т("no_conn"))
        }
    }

    // MARK: Плашка

    /// toast сайта: на 2,8 с внизу экрана и вслух для VoiceOver.
    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard self.плашка == текст else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.плашка = nil }
        }
    }

    // MARK: Выход

    private func сбросить() {
        страница = nil
        котировки = [:]
        котировкиБезОтвета = []
        слоты = nil
        запусков = nil
        клуб = nil
        клубЗагрузка = .нет
        заказыПродаю = nil
        заказыПокупаю = nil
    }

    /// ВыходНачисто: реквизиты, статус PRO, клуб и заказы ушедшего; ответ, пришедший после, не примется.
    func стереть() {
        поколение += 1
        сбросить()
        загрузка = .нет
        плашка = nil
    }
}
