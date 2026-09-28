import SwiftUI
import MapKit

/**
 СТРАНИЦА ОБЪЯВЛЕНИЯ АВТО И НЕДВИЖИМОСТИ КАК НА САЙТЕ (владелец 26.09.2026, TestFlight: «авто и недвижимость чуть
 другое отображение внутри, как на сайте»).

 Образец — mkOpenModal в js/marketplace.min.js. Своего шаблона у авто и жилья там нет: страница та же, но часть блоков
 появляется только у них, и характеристики у жилья строятся иначе. Вид берётся так же, как у сайта, — mkCheckKind:
 корень раздела «realty» — жильё; «transport» — авто, кроме самокатов, запчастей и водного транспорта (e-scooters,
 auto-parts, water-transport). Прочие разделы остаются на общей странице (SiteListing.swift) без изменений.

 Порядок блоков — как у сайта на телефоне (колонки .mk-mcol-a…e по order):
   · под «… — на что смотреть» — кнопка проверки mkCheckCTA: «Проверка автомобиля» / «Проверка недвижимости» с
     состоянием по auto_check / realty_check (зелёная — чисто, красная — ограничения, тёмная — ещё не проверено);
     нажатие — отчёт mkCheckReport (для прошедших верификацию; прочим — замок, как у сайта);
   · у жилья — «Схема помещения» mkRealtyPlan (realty.plan), нажатие — на весь экран с увеличением;
   · «Описание» с характеристиками mkSpecs(t, true): у жилья — поля realty в порядке MK_REALTY_ORDER с подписями
     MK_REALTY_LBL («Комнат: 3», «Площадь: 75 м²», «Этаж: 5/9», «Ремонт: Евроремонт», признаки одной подписью —
     «Мебель и техника»); у авто — specs[] с подписями и значениями SPEC_LBL_MAP/SPEC_VAL_MAP и значком у каждой
     (_capIco: год — календарь, пробег — спидометр, двигатель — молния, коробка — руль, топливо — капля);
   · «Способы оплаты» mkPayBlock (payment: рассрочка/кредит) — расчёт платежа в месяц по срокам, как у сайта;
     🔴 только расчёт: «Оформить покупку» ведёт в оплату, а деньги в приложении выключены (Config.деньгиСделок);
   · «Расположение» mkLocationBlock — у сайта оно у всех разделов, поэтому живёт отдельно: SiteListingLocation.swift.

 Цены «за м²» и «млн» на странице объявления сайт не пишет (mkPriceHTML(t, true) — полное число через fmt), поэтому
 и здесь их нет.
 */

// MARK: - Вид страницы (mkCheckKind)

enum ВидСтраницыОбъявления: Hashable {
    case авто, жильё
}

/// Тексты этого файла.
private func тВида(_ ключ: String) -> String { ListingKindsText.т(ключ) }

extension Listing {
    /// Авто, жильё или nil — общая страница.
    var видСтраницы: ВидСтраницыОбъявления? {
        switch корень {
        case "realty":
            return .жильё
        case "transport":
            return РазделыСайта.внутри(категория, ["e-scooters", "auto-parts", "water-transport"]) ? nil : .авто
        default:
            return nil
        }
    }
}

// MARK: - Поля ответа, нужные только этим блокам

/// Разбирается из того же ответа api/listings.php, что и Listing, — терпимо: чего нет или не того вида — пусто.
struct ПоляСтраницыВида: Hashable, Decodable {
    var проверкаАвто: ОтчётПроверкиОбъявления?
    var проверкаЖилья: ОтчётПроверкиОбъявления?
    /// vin и kadastr самого объявления (n.vin || n.auto_check.vin у сайта).
    var vin: String?
    var кадастр: String?
    var оплата: ОплатаОбъявления?
    var широта: Double?
    var долгота: Double?
    /// address — улица и дом.
    var адрес: String?
    /// district — название района, если это не код («esil»).
    var район: String?
    /// year — «2019 · Астана» под названием в отчёте проверки.
    var год: String?
    /// ship_scope — куда продавец отправляет: «all» (пусто), «city» — только по своему городу, «regions» — только в
    /// свои области (ship_regions, ключи MK_GEO). Строка регионов отправки — mkShipRegionsLine (SiteListingDelivery.swift).
    var отправкаКуда: String?
    var регионыОтправки: [String] = []
    /// ship_carrier — транспортная компания, выбранная продавцом: в списке ТК она первая, с меткой «выбор продавца».
    var перевозчик: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: КлючПоля.self)
        проверкаАвто = try? c.decode(ОтчётПроверкиОбъявления.self, forKey: КлючПоля("auto_check"))
        проверкаЖилья = try? c.decode(ОтчётПроверкиОбъявления.self, forKey: КлючПоля("realty_check"))
        vin = ПоляСтраницыВида.строка(c, "vin")
        кадастр = ПоляСтраницыВида.строка(c, "kadastr")
        оплата = try? c.decode(ОплатаОбъявления.self, forKey: КлючПоля("payment"))
        широта = ПоляСтраницыВида.число(c, "lat").flatMap { $0 != 0 ? $0 : nil }
        долгота = ПоляСтраницыВида.число(c, "lon").flatMap { $0 != 0 ? $0 : nil }
        адрес = ПоляСтраницыВида.строка(c, "address")
        if let р = ПоляСтраницыВида.строка(c, "district"),
           р.range(of: "^[a-z0-9-]+$", options: [.regularExpression, .caseInsensitive]) == nil {
            район = р
        }
        год = ПоляСтраницыВида.строка(c, "year")
        отправкаКуда = ПоляСтраницыВида.строка(c, "ship_scope")
        регионыОтправки = ПоляСтраницыВида.строки(c, "ship_regions")
        перевозчик = ПоляСтраницыВида.строка(c, "ship_carrier")
    }

    static func строка(_ c: KeyedDecodingContainer<КлючПоля>, _ k: String) -> String? {
        var значение: String?
        if let s = try? c.decode(String.self, forKey: КлючПоля(k)) {
            значение = s
        } else if let i = try? c.decode(Int.self, forKey: КлючПоля(k)) {
            значение = String(i)
        }
        guard let s = значение?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func число(_ c: KeyedDecodingContainer<КлючПоля>, _ k: String) -> Double? {
        if let d = try? c.decode(Double.self, forKey: КлючПоля(k)) { return d.isFinite ? d : nil }
        if let s = try? c.decode(String.self, forKey: КлючПоля(k)) {
            return Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }

    /// Да, нет или не пришло (null — «на проверке» у сайта): true/false, 1/0, "1"/"0".
    static func даНет(_ c: KeyedDecodingContainer<КлючПоля>, _ k: String) -> Bool? {
        if let b = try? c.decode(Bool.self, forKey: КлючПоля(k)) { return b }
        if let i = try? c.decode(Int.self, forKey: КлючПоля(k)) { return i != 0 }
        if let s = try? c.decode(String.self, forKey: КлючПоля(k)) {
            if s == "1" || s.lowercased() == "true" { return true }
            if s == "0" || s.lowercased() == "false" { return false }
        }
        return nil
    }

    static func строки(_ c: KeyedDecodingContainer<КлючПоля>, _ k: String) -> [String] {
        ((try? c.decode([String].self, forKey: КлючПоля(k))) ?? []).filter { !$0.isEmpty }
    }
}

struct КлючПоля: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// auto_check / realty_check: {vin|kadastr, is_rent, decode:{valid, maker, year, region, kadastr}, rk:{status, …},
/// brand_match, year_match, checked_at}.
struct ОтчётПроверкиОбъявления: Hashable, Decodable {
    var действителен = false
    /// rk.status: «clean», «issues»; иначе — «manual» (на проверке).
    var статусРК = "manual"
    var аренда = false
    var vin: String?
    var кадастр: String?
    var марка: String?
    var годДекода: String?
    var регион: String?
    var кадастрДекода: String?
    var маркаСовпала: Bool?
    var годСовпал: Bool?
    var залог: Bool?
    var розыск: Bool?
    var ограничения: Bool?
    var обременения: Bool?
    var арест: Bool?
    var собственникСовпал: Bool?
    var проверено: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: КлючПоля.self)
        vin = ПоляСтраницыВида.строка(c, "vin")
        кадастр = ПоляСтраницыВида.строка(c, "kadastr")
        аренда = ПоляСтраницыВида.даНет(c, "is_rent") ?? false
        маркаСовпала = ПоляСтраницыВида.даНет(c, "brand_match")
        годСовпал = ПоляСтраницыВида.даНет(c, "year_match")
        проверено = ПоляСтраницыВида.строка(c, "checked_at")
        if let д = try? c.nestedContainer(keyedBy: КлючПоля.self, forKey: КлючПоля("decode")) {
            действителен = ПоляСтраницыВида.даНет(д, "valid") ?? false
            марка = ПоляСтраницыВида.строка(д, "maker")
            годДекода = ПоляСтраницыВида.строка(д, "year")
            регион = ПоляСтраницыВида.строка(д, "region")
            кадастрДекода = ПоляСтраницыВида.строка(д, "kadastr")
        }
        if let р = try? c.nestedContainer(keyedBy: КлючПоля.self, forKey: КлючПоля("rk")) {
            if let статус = ПоляСтраницыВида.строка(р, "status") { статусРК = статус }
            залог = ПоляСтраницыВида.даНет(р, "pledge")
            розыск = ПоляСтраницыВида.даНет(р, "wanted")
            ограничения = ПоляСтраницыВида.даНет(р, "restrictions")
            обременения = ПоляСтраницыВида.даНет(р, "encumbrance")
            арест = ПоляСтраницыВида.даНет(р, "arrest")
            собственникСовпал = ПоляСтраницыВида.даНет(р, "owner_ok")
        }
    }
}

/// payment: {installment, credit, credit_rate, installment_commission, installment_mode, installment_banks, credit_banks}.
struct ОплатаОбъявления: Hashable, Decodable {
    var рассрочка = false
    var кредит = false
    /// credit_rate, % годовых; нет — 25, как у сайта.
    var ставка: Double = 25
    /// installment_commission, % сверху цены (mkInstComm: не меньше нуля).
    var комиссия: Double = 0
    /// installment_mode: «notary» — без банка, у нотариуса.
    var нотариус = false
    var банкиРассрочки: [String] = []
    var банкиКредита: [String] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: КлючПоля.self)
        рассрочка = ПоляСтраницыВида.даНет(c, "installment") ?? false
        кредит = ПоляСтраницыВида.даНет(c, "credit") ?? false
        if let r = ПоляСтраницыВида.число(c, "credit_rate"), r > 0 { ставка = r }
        комиссия = max(0, ПоляСтраницыВида.число(c, "installment_commission") ?? 0)
        нотариус = ПоляСтраницыВида.строка(c, "installment_mode") == "notary"
        банкиРассрочки = ПоляСтраницыВида.строки(c, "installment_banks")
        банкиКредита = ПоляСтраницыВида.строки(c, "credit_banks")
    }

    /// MK_BANKS сайта.
    static func банки(_ коды: [String]) -> String {
        let имена = ["kaspi": "Kaspi", "halyk": "Halyk", "freedom": "Freedom", "forte": "ForteBank", "jusan": "Jusan",
                     "eurasian": "Eurasian"]
        return коды.map { имена[$0] ?? $0 }.joined(separator: ", ")
    }

    /// mkPayCalc: с процентом — аннуитет, без — поровну; до десятков тенге.
    static func вМесяц(_ сумма: Double, ставка: Double, месяцев: Int) -> Int {
        guard месяцев > 0 else { return 0 }
        let n = Double(месяцев)
        let вМесяцСтавка = ставка / 100 / 12
        let платёж: Double
        if вМесяцСтавка <= 0 {
            платёж = сумма / n
        } else {
            let делитель = 1 - pow(1 + вМесяцСтавка, -n)
            платёж = делитель > 0 ? сумма * вМесяцСтавка / делитель : сумма / n
        }
        guard платёж.isFinite, платёж < 1e15 else { return 0 }
        return Int((платёж / 10).rounded()) * 10
    }

    /// «5» или «1.5» — число, как его печатает JS.
    static func процент(_ x: Double) -> String {
        x == x.rounded() && abs(x) < 1e12 ? String(Int(x)) : String(x)
    }
}

// MARK: - Текст описания на экране

extension Listing {
    /**
     Описание как пишет его сайт (.mk-mdesc — текст как есть, шрифт страницы), только значки-квадратики в тексте — «▫», «▪»,
     «◻», «⬜», «☐» и соседние геометрические фигуры, которыми продавцы делают списки, — рисуются знаком шрифта, а не
     эмодзи. Без этого iOS берёт для них Apple Color Emoji, и список выходит серыми пустыми квадратами (владелец
     26.09.2026, TestFlight). U+FE0E после знака просит у системы текстовый вид; эмодзи-вариант (U+FE0F) у этих знаков
     заменяется тем же. Прочие эмодзи (✅, 🔥, 📦) не трогаем.
     */
    var описаниеДляЭкрана: String? {
        guard let текст = описание else { return nil }
        var итог = String.UnicodeScalarView()
        var ждёмВариант = false
        for знак in текст.unicodeScalars {
            if ждёмВариант {
                ждёмВариант = false
                if знак.value == 0xFE0F || знак.value == 0xFE0E {
                    итог.append(Self.текстовыйВид)
                    continue
                }
                итог.append(Self.текстовыйВид)
            }
            итог.append(знак)
            if Self.квадратик(знак) { ждёмВариант = true }
        }
        if ждёмВариант { итог.append(Self.текстовыйВид) }
        return String(итог)
    }

    private static let текстовыйВид = Unicode.Scalar(UInt32(0xFE0E)) ?? " "

    /// Геометрические фигуры (U+25A0–U+25FF), большие квадраты (U+2B1B–U+2B1E) и «☐☑☒».
    private static func квадратик(_ знак: Unicode.Scalar) -> Bool {
        let v = знак.value
        return (0x25A0...0x25FF).contains(v) || (0x2B1B...0x2B1E).contains(v) || (0x2610...0x2612).contains(v)
    }
}

// MARK: - Характеристики страницы (mkSpecs(t, true), mkRealtySpecs)

struct ПунктХарактеристикиВида: Hashable {
    let текст: String
    /// SF Symbol — у specs[] сайт рисует значок (emoji-svg), у полей жилья значков нет.
    let значок: String?
}

extension Listing {
    /// MK_REALTY_ORDER.
    private static let порядокПолейСтраницы = ["rooms", "area", "land_area", "floor", "floors", "term", "renovation",
                                               "building", "bathroom", "year_built", "land_use", "docs", "mortgage_ok",
                                               "utilities", "furniture", "parking", "kids", "pets", "owner"]
    /// Поля-признаки: «да» — одна подпись.
    private static let признакиПолейСтраницы: Set<String> = ["mortgage_ok", "utilities", "furniture", "parking", "kids",
                                                             "pets"]
    /// Значения со словом (MK_REALTY_VAL) — тексты DesignText «r_<значение>».
    private static let словаПолейСтраницы: Set<String> = ["studio", "none", "cosmetic", "euro", "design", "brick",
                                                          "panel", "monolith", "block", "separate", "combined", "two",
                                                          "private", "share", "mortgage", "other", "long", "daily",
                                                          "owner", "agent", "ijs", "garden", "farm", "commercial"]
    /// SPEC_LBL_MAP.
    private static let подписиХарактеристик: [String: String] = [
        "Коробка": "fac_gearbox", "Топливо": "fac_fuel", "Пробег": "spec_mileage", "Год": "fac_year_short",
        "Год выпуска": "spec_year", "Двигатель": "fac_engine", "Площадь": "fac_area", "Комнаты": "fac_rooms",
        "Размер": "fac_size", "Цвет": "fac_color", "Материал": "fac_material", "Участок": "fac_plot"
    ]
    /// SPEC_VAL_MAP.
    private static let значенияХарактеристик: [String: String] = [
        "Автомат": "fac_auto", "Механика": "fac_manual", "Робот": "fac_robot", "Вариатор": "fac_cvt",
        "Бензин": "fac_petrol", "Дизель": "fac_diesel", "Газ": "fac_gas", "Гибрид": "fac_hybrid",
        "Электро": "fac_electric", "Встроенная": "gpu_integrated", "Дискретная": "gpu_discrete", "Новый": "cond_new",
        "Б/У": "cond_used", "Студия": "fac_studio"
    ]

    /// Характеристики в «Описании» страницы авто и жилья: поля жилья, если есть realty.kind, иначе specs.
    var характеристикиВида: [ПунктХарактеристикиВида] {
        if жильё["kind"] != nil {
            let поля = пунктыЖильяСтраницы
            if !поля.isEmpty { return поля }
        }
        return пунктыХарактеристикСтраницы
    }

    private var пунктыЖильяСтраницы: [ПунктХарактеристикиВида] {
        var итог: [ПунктХарактеристикиВида] = []
        for ключ in Self.порядокПолейСтраницы {
            guard let значение = жильё[ключ] else { continue }
            if ключ == "floors" && жильё["floor"] != nil { continue }
            let подпись = тВида("re_" + ключ)
            if Self.признакиПолейСтраницы.contains(ключ) {
                if значение == "1" { итог.append(ПунктХарактеристикиВида(текст: подпись, значок: nil)) }
                continue
            }
            var текст = значение
            if ключ == "floor", let всего = жильё["floors"] {
                текст = значение + "/" + всего
            } else if Self.словаПолейСтраницы.contains(значение) {
                текст = DesignText.т("r_" + значение)
            } else if ключ == "area" {
                текст = значение + " " + DesignText.т("m2")
            } else if ключ == "land_area" {
                текст = значение + " " + DesignText.т("sot")
            }
            итог.append(ПунктХарактеристикиВида(текст: подпись + ": " + текст, значок: nil))
        }
        return итог
    }

    private var пунктыХарактеристикСтраницы: [ПунктХарактеристикиВида] {
        let источник: [ПунктКарточки]
        if характеристикиКарточки.isEmpty {
            источник = характеристики.map { ПунктКарточки(ключ: $0.ключ, значение: $0.значение, образец: false) }
        } else {
            источник = характеристикиКарточки
        }
        var итог: [ПунктХарактеристикиВида] = []
        for пункт in источник {
            let значение = Self.значениеСайта(пункт.значение)
            let значок = Self.значокХарактеристики(пункт.ключ)
            if пункт.образец {
                /* Образец цвета: у сайта — кружки и значение без подписи. */
                if !значение.isEmpty { итог.append(ПунктХарактеристикиВида(текст: значение, значок: значок)) }
                continue
            }
            if Self.пустоеЗначение(значение) { continue }
            let подпись = Self.подписьСайта(пункт.ключ)
            let текст = подпись.isEmpty ? значение : подпись + ": " + значение
            итог.append(ПунктХарактеристикиВида(текст: текст, значок: значок))
        }
        return итог
    }

    /// mkSpecL: подпись из словаря — целиком или до «,» / «(».
    private static func подписьСайта(_ подпись: String) -> String {
        if let ключ = подписиХарактеристик[подпись] { return тВида(ключ) }
        let первая = подпись.split(whereSeparator: { $0 == "," || $0 == "(" }).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? подпись
        if let ключ = подписиХарактеристик[первая] { return тВида(ключ) }
        return подпись
    }

    /// mkSpecV.
    private static func значениеСайта(_ значение: String) -> String {
        let з = значение.trimmingCharacters(in: .whitespaces)
        if let ключ = значенияХарактеристик[з] { return тВида(ключ) }
        return з
    }

    /// mkSpecBlank.
    private static func пустоеЗначение(_ з: String) -> Bool {
        if з.isEmpty { return true }
        if з.range(of: "^0+([.,]0+)?$", options: .regularExpression) != nil { return true }
        let пустые: Set<String> = ["-", "—", "–", "n/a", "na", "null", "undefined", "нет", "нет данных", "не указано",
                                   "не задано"]
        return пустые.contains(з.lowercased())
    }

    /// _capIco сайта — значок по подписи.
    private static func значокХарактеристики(_ подпись: String) -> String {
        let п = подпись.lowercased()
        let правила: [(String, String)] = [
            ("год|year", "calendar"),
            ("пробег|mileage|км", "speedometer"),
            ("двигат|объ[её]м|engine", "bolt"),
            ("коробк|трансмис|привод", "steeringwheel"),
            ("топлив|fuel|бензин|дизел", "drop"),
            ("процессор|cpu", "cpu"),
            ("озу|память|ram", "memorychip"),
            ("накопит|ssd|hdd|диск", "internaldrive"),
            ("экран|диагон|display", "tv"),
            ("видео|gpu|график", "bolt"),
            ("размер|size", "tag"),
            ("комнат|rooms", "door.left.hand.closed"),
            ("площад|area", "square.grid.2x2"),
            ("этаж|floor", "house"),
            ("участ|сот", "map"),
            ("ремонт|отделк", "wrench.and.screwdriver"),
            ("санузел|ванн", "drop"),
            ("парковк|гараж", "car"),
            ("срок|аренд", "clock"),
            ("ипотек|документ", "checkmark"),
            ("дом|здани", "shippingbox")
        ]
        for (образец, значок) in правила where п.range(of: образец, options: .regularExpression) != nil {
            return значок
        }
        return "tag"
    }
}

// MARK: - Блоки страницы по порядку сайта

/// Кнопка проверки и схема помещения — между советом и «Описанием» (.mk-mcol-c сайта).
struct БлокиВидаДоОписания: View {
    let товар: Listing
    let вид: ВидСтраницыОбъявления

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            КнопкаПроверкиСайта(товар: товар, вид: вид)
            if вид == .жильё, let план = товар.жильё["plan"], let адрес = Config.url(план) {
                СхемаПомещенияСайта(адрес: адрес)
            }
        }
    }
}

// MARK: - Кнопка проверки (.mkcta)

private enum ТонПроверки {
    case чисто, внимание, нейтрально
}

private enum КраскиПроверки {
    static let чистоФон = Theme.цвет(0xE9F7EF, 0x122A1E)
    static let чистоРамка = Theme.цвет(0xA7E0C0, 0x1F5A3F)
    static let чистоТекст = Theme.цвет(0x0F7A44, 0x5CD39A)
    static let вниманиеФон = Theme.цвет(0xFEF2F2, 0x2C1414)
    static let вниманиеРамка = Theme.цвет(0xFECACA, 0x5A2626)
    static let вниманиеТекст = Theme.цвет(0xB91C1C, 0xFF9D9D)
    static let тёмныйНачало = Color(uiColor: Theme.hex(0x1D2B24))
    static let тёмныйКонец = Color(uiColor: Theme.hex(0x121B16))
    static let тёмныйТекст = Color(uiColor: Theme.hex(0xE6F1EA))
    static let тёмныйРамка = Color.white.opacity(0.12)
    static let кольцоЧисто = Color(uiColor: Theme.hex(0x1A9E5E))
    static let кольцоВнимание = Color(uiColor: Theme.hex(0xD9901A))
}

struct КнопкаПроверкиСайта: View {
    let товар: Listing
    let вид: ВидСтраницыОбъявления
    @State private var отчёт = false

    private var проверка: ОтчётПроверкиОбъявления? {
        вид == .авто ? товар.поляВида.проверкаАвто : товар.поляВида.проверкаЖилья
    }

    private var действителен: Bool { проверка?.действителен ?? false }

    /// mkCheckCTA: строка под заголовком и цвет кнопки.
    private var состояние: (текст: String, тон: ТонПроверки) {
        guard let п = проверка, п.действителен else { return (тВида("chk_by_rk"), .нейтрально) }
        switch п.статусРК {
        case "clean":
            if вид == .авто { return (тВида("chk_auto_clean"), .чисто) }
            let аренда = п.аренда || товар.forRent
            return (тВида(аренда ? "chk_owner_ok" : "chk_no_liens"), .чисто)
        case "issues":
            return (тВида("chk_issues"), .внимание)
        default:
            let первая = тВида(вид == .авто ? "chk_vin_ok" : "chk_cadastre_ok")
            return (первая + " · " + тВида("chk_rk_pending"), .нейтрально)
        }
    }

    var body: some View {
        let с = состояние
        let цвет = цветТекста(с.тон)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        Button { отчёт = true } label: {
            HStack(spacing: 10) {
                Image(systemName: вид == .авто ? "car" : "house")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(цвет.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(тВида(вид == .авто ? "chk_auto_title" : "chk_realty_title"))
                        .font(.system(size: 15, weight: .heavy))
                        .lineLimit(1)
                    Text(с.текст)
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.78)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text(тВида(действителен ? "chk_open" : "chk_check"))
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 10, weight: .heavy))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 12, weight: .heavy))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(цвет.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(цвет)
            .padding(14)
            .background { фон(с.тон, форма: форма) }
            .overlay { форма.strokeBorder(рамка(с.тон), lineWidth: 1.5) }
            .contentShape(форма)
        }
        .buttonStyle(.plain)
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
        .sheet(isPresented: $отчёт) {
            ЛистПроверкиСайта(товар: товар, вид: вид, проверка: проверка)
        }
    }

    private func цветТекста(_ тон: ТонПроверки) -> Color {
        switch тон {
        case .чисто: return КраскиПроверки.чистоТекст
        case .внимание: return КраскиПроверки.вниманиеТекст
        case .нейтрально: return КраскиПроверки.тёмныйТекст
        }
    }

    private func рамка(_ тон: ТонПроверки) -> Color {
        switch тон {
        case .чисто: return КраскиПроверки.чистоРамка
        case .внимание: return КраскиПроверки.вниманиеРамка
        case .нейтрально: return КраскиПроверки.тёмныйРамка
        }
    }

    @ViewBuilder
    private func фон(_ тон: ТонПроверки, форма: RoundedRectangle) -> some View {
        switch тон {
        case .чисто:
            форма.fill(КраскиПроверки.чистоФон)
        case .внимание:
            форма.fill(КраскиПроверки.вниманиеФон)
        case .нейтрально:
            форма.fill(LinearGradient(colors: [КраскиПроверки.тёмныйНачало, КраскиПроверки.тёмныйКонец],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
}

// MARK: - Отчёт проверки (mkCheckReport)

struct ЛистПроверкиСайта: View {
    let товар: Listing
    let вид: ВидСтраницыОбъявления
    let проверка: ОтчётПроверкиОбъявления?
    @Environment(\.dismiss) private var закрыть
    @ObservedObject private var сессия = СессияПриложения.shared

    private var аренда: Bool {
        вид == .жильё && ((проверка?.аренда ?? false) || товар.forRent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                шапка
                карточкаОбъявления
                if !сессия.продавецПодтверждён {
                    ЗамокОтчёта(вид: вид) {
                        закрыть()
                        /* Как mkChkVerify сайта — cabinet.php?go=verify; eGov открывается своим окном (ОкноEgov). */
                        if let адрес = Config.страницаСайта("cabinet.php?go=verify"), !ОкноEgov.перехватить(адрес) {
                            WebBridge.shared.pendingURL = адрес
                        }
                    }
                } else if let п = проверка, п.действителен {
                    ПолныйОтчётПроверки(вид: вид, проверка: п, аренда: аренда)
                } else {
                    ПустойОтчёт {
                        /* Лист стоит над нативной карточкой этого объявления — к ней и возвращаемся, а не на страницу
                           сайта (владелец: всё нативно). */
                        закрыть()
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var шапка: some View {
        HStack(spacing: 12) {
            Image(systemName: вид == .авто ? "car" : "house")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 42, height: 42)
                .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(тВида(вид == .авто ? "chk_auto_title" : "chk_realty_title"))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(тВида(вид == .авто ? "chk_auto_hs" : "chk_realty_hs"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 8)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 32, height: 32)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ListingPageText.т("close"))
        }
    }

    /// .mkchk-item: название, «год · город», VIN (последние пять знаков) или кадастр.
    private var карточкаОбъявления: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(товар.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            let подпись = [товар.поляВида.год ?? "", товар.city].filter { !$0.isEmpty }.joined(separator: " · ")
            if !подпись.isEmpty {
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            Text(номер)
                .font(.system(size: 12, weight: .semibold).monospaced())
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private var номер: String {
        if вид == .авто {
            guard let v = товар.поляВида.vin ?? проверка?.vin else { return тВида("chk_vin_none") }
            let скрытый = v.count > 5 ? "····" + String(v.suffix(5)) : v
            return String(format: тВида("chk_vin"), скрытый)
        }
        guard let к = товар.поляВида.кадастр ?? проверка?.кадастр else { return тВида("chk_kad_none") }
        return String(format: тВида("chk_kad"), к)
    }
}

/// _mkChkLock: отчёт — только прошедшим верификацию.
private struct ЗамокОтчёта: View {
    let вид: ВидСтраницыОбъявления
    let пройти: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 48, height: 48)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            Text(тВида("chk_lock_t"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
            Text(тВида("chk_lock_b"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: пройти) {
                Text(тВида("chk_lock_btn"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
    }
}

/// _mkChkEmpty: проверки ещё нет — запросить её можно на странице объявления сайта.
private struct ПустойОтчёт: View {
    let запросить: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 48, height: 48)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            Text(тВида("chk_empty_t"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
            Text(тВида("chk_empty_b"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: запросить) {
                Text(тВида("chk_request"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// Пометка строки отчёта: чисто, внимание или «на проверке».
private enum ПометкаОтчёта {
    case чисто, внимание, ждём

    var цвет: Color {
        switch self {
        case .чисто: return КраскиПроверки.чистоТекст
        case .внимание: return КраскиПроверки.вниманиеТекст
        case .ждём: return Theme.текстВторой
        }
    }

    var значок: String {
        switch self {
        case .чисто: return "checkmark"
        case .внимание: return "exclamationmark.triangle"
        case .ждём: return "clock"
        }
    }
}

/// _mkChkFull: оценка с кольцом и источники.
private struct ПолныйОтчётПроверки: View {
    let вид: ВидСтраницыОбъявления
    let проверка: ОтчётПроверкиОбъявления
    let аренда: Bool

    /// _mkChkVerdict.
    private var вывод: (баллы: Int, заголовок: String, подпись: String, чисто: Bool) {
        let статус = проверка.статусРК
        if вид == .авто {
            if !проверка.действителен { return (20, тВида("chk_vin_unrec"), тВида("chk_check_num"), false) }
            var баллы = 50
            if проверка.маркаСовпала != false { баллы += 20 }
            if проверка.годСовпал != false { баллы += 15 }
            if статус == "issues" { return (min(баллы, 35), тВида("chk_has_limits"), тВида("chk_rk_found"), false) }
            if статус == "clean" {
                return (min(баллы + 15, 100), тВида("chk_clean_short"), тВида("chk_clean_vin_sub"), true)
            }
            return (min(баллы, 80), тВида("chk_vin_ok"), тВида("chk_vin_pending_sub"), true)
        }
        if !проверка.действителен { return (20, тВида("chk_kad_unrec"), "", false) }
        if статус == "issues" {
            return (35, тВида("chk_has_limits"), тВида(аренда ? "chk_realty_issue_rent" : "chk_realty_issue_sale"), false)
        }
        if статус == "clean" {
            return (92, тВида("chk_clean_ready"), тВида(аренда ? "chk_owner_ok_sub" : "chk_no_liens"), true)
        }
        return (58, тВида("chk_cadastre_ok"), тВида("chk_kad_pending_sub"), true)
    }

    private var пометкаРК: (String, ПометкаОтчёта) {
        switch проверка.статусРК {
        case "clean": return (тВида("chk_clean_short"), .чисто)
        case "issues": return (тВида("chk_limits"), .внимание)
        default: return (тВида("chk_pending"), .ждём)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            оценка
            if вид == .авто {
                РазделОтчёта(знак: тВида("chk_b_car"), заголовок: тВида("chk_car_data"), подпись: тВида("chk_vin_decode"),
                             флаг: (тВида("chk_vin_valid"), .чисто)) {
                    СтрокаСведений(подпись: тВида("chk_brand"), значение: проверка.марка ?? "—",
                                   внимание: проверка.маркаСовпала == false)
                    СтрокаСведений(подпись: тВида("chk_year"), значение: проверка.годДекода ?? "—",
                                   внимание: проверка.годСовпал == false)
                    СтрокаСведений(подпись: тВида("chk_country"), значение: проверка.регион ?? "—", внимание: false)
                }
                РазделОтчёта(знак: тВида("chk_b_rk"), заголовок: тВида("chk_rk_bases"), подпись: тВида("chk_auto_hs"),
                             флаг: пометкаРК) {
                    СтрокаСостояния(подпись: тВида("chk_pledge"), значение: проверка.залог, хорошоКогдаДа: false)
                    СтрокаСостояния(подпись: тВида("chk_wanted"), значение: проверка.розыск, хорошоКогдаДа: false)
                    СтрокаСостояния(подпись: тВида("chk_restrictions"), значение: проверка.ограничения, хорошоКогдаДа: false)
                }
            } else {
                РазделОтчёта(знак: тВида("chk_b_rn"), заголовок: тВида("chk_realty_reg"), подпись: тВида("chk_realty_hs"),
                             флаг: пометкаРК) {
                    СтрокаСостояния(подпись: тВида("chk_encumbrance"), значение: проверка.обременения, хорошоКогдаДа: false)
                    СтрокаСостояния(подпись: тВида("chk_arrest"), значение: проверка.арест, хорошоКогдаДа: false)
                    СтрокаСостояния(подпись: тВида("chk_owner"), значение: проверка.собственникСовпал, хорошоКогдаДа: true,
                                    пояснение: тВида(аренда ? "chk_owner_match_rent" : "chk_owner_match_sale"))
                }
                РазделОтчёта(знак: тВида("chk_b_k"), заголовок: тВида("chk_kadastr"),
                             подпись: проверка.кадастрДекода ?? "", флаг: (тВида("chk_correct"), .чисто)) {
                    СтрокаСведений(подпись: тВида("chk_region"), значение: проверка.регион ?? "—", внимание: false)
                    СтрокаСведений(подпись: тВида("chk_ad_type"), значение: тВида(аренда ? "chk_rent" : "chk_sale"),
                                   внимание: false)
                }
            }
            Text(подвал)
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var оценка: some View {
        let в = вывод
        let цвет = в.чисто ? КраскиПроверки.кольцоЧисто : КраскиПроверки.кольцоВнимание
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(цвет.opacity(0.18), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(в.баллы) / 100)
                    .stroke(цвет, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(в.баллы))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(в.заголовок)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if !в.подпись.isEmpty {
                    Text(в.подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(цвет.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// «Источник: проверка платформы · 26.09.2026. Справочная информация…».
    private var подвал: String {
        var строка = тВида("chk_source")
        if let когда = проверка.проверено {
            let части = когда.prefix(10).split(separator: "-").map(String.init)
            if части.count == 3 {
                let дата = [части[2], части[1], части[0]].joined(separator: ".")
                строка += " · " + дата
            }
        }
        return строка + ". " + тВида("chk_disclaimer")
    }
}

/// .mkchk-src: знак источника, заголовок, флаг и строки.
private struct РазделОтчёта<Строки: View>: View {
    let знак: String
    let заголовок: String
    let подпись: String
    let флаг: (String, ПометкаОтчёта)
    @ViewBuilder let строки: () -> Строки

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(знак)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 32, height: 32)
                    .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    if !подпись.isEmpty {
                        Text(подпись)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                Spacer(minLength: 6)
                Text(флаг.0)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(флаг.1.цвет)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(флаг.1.цвет.opacity(0.12), in: Capsule())
            }
            .padding(.bottom, 6)
            строки()
        }
        .padding(12)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// _mkInfoRow: подпись и значение; не совпало с объявлением — оранжевым.
private struct СтрокаСведений: View {
    let подпись: String
    let значение: String
    let внимание: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(внимание ? КраскиПроверки.кольцоВнимание : Theme.текстВторой)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(внимание ? КраскиПроверки.кольцоВнимание : Theme.текст)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

/// _mkStatRow: нет ответа — «На проверке»; иначе «Есть/Нет» или «Подтверждён/Не подтверждён».
private struct СтрокаСостояния: View {
    let подпись: String
    let значение: Bool?
    /// Для «Собственник» хорошо, когда да; для залога и ареста — когда нет.
    let хорошоКогдаДа: Bool
    var пояснение: String? = nil

    private var итог: (текст: String, пометка: ПометкаОтчёта) {
        guard let з = значение else { return (тВида("chk_pending"), .ждём) }
        let хорошо = хорошоКогдаДа ? з : !з
        let текст: String
        if хорошоКогдаДа {
            текст = тВида(з ? "chk_confirmed" : "chk_unconfirmed")
        } else {
            текст = тВида(з ? "chk_has" : "chk_none")
        }
        return (текст, хорошо ? .чисто : .внимание)
    }

    var body: some View {
        let и = итог
        HStack(spacing: 10) {
            Image(systemName: и.пометка.значок)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(и.пометка.цвет)
                .frame(width: 22, height: 22)
                .background(и.пометка.цвет.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                if let пояснение, и.пометка == .чисто, хорошоКогдаДа {
                    Text(пояснение)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 8)
            Text(и.текст)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(и.пометка.цвет)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(и.пометка.цвет.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Схема помещения (mkRealtyPlan)

struct СхемаПомещенияСайта: View {
    let адрес: URL
    @State private var наВесьЭкран = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.split.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .accessibilityHidden(true)
                Text(тВида("rplan_t"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            Button { наВесьЭкран = true } label: {
                HStack(spacing: 12) {
                    AsyncImage(url: адрес) { фаза in
                        if case .success(let картинка) = фаза {
                            картинка.resizable().scaledToFill()
                        } else {
                            Color.white
                        }
                    }
                    .frame(width: 84, height: 62)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                    Text(тВида("rplan_open"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 30, height: 30)
                        .background(Theme.поверхность, in: Circle())
                        .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                        .accessibilityHidden(true)
                }
                .padding(8)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(тВида("rplan_t"))
            .accessibilityHint(тВида("rplan_open"))
        }
        .fullScreenCover(isPresented: $наВесьЭкран) {
            ФотоНаВесьЭкран(адреса: [адрес], начало: 0)
        }
    }
}

// MARK: - Описание с характеристиками вида (mkSpecs(t, true))

/// Как БлокОписанияСайта, но характеристики — по правилам вида: поля жилья или specs со значками.
struct БлокОписанияВида: View {
    let характеристики: [ПунктХарактеристикиВида]
    let описание: String?
    let добавлено: String?
    let просмотры: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ПодзаголовокСайта(значок: "info.circle", текст: ListingPageText.т("desc"))
            if !характеристики.isEmpty {
                ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                    ForEach(характеристики, id: \.self) { пункт in
                        ФишкаХарактеристикиВида(пункт: пункт)
                    }
                }
            }
            if let текст = описание {
                Text(текст)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.текст)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if добавлено != nil || (просмотры ?? 0) > 0 {
                HStack(spacing: 16) {
                    if let когда = добавлено {
                        Label(String(format: ListingPageText.т("added"), когда), systemImage: "clock")
                    }
                    if let п = просмотры, п > 0 {
                        Label(String(п), systemImage: "eye")
                            .accessibilityLabel(String(format: ListingPageText.т("views"), п))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .labelStyle(МеткаСайта())
            }
        }
    }
}

/// .mk-mspec: значок зелёным 13 pt и «подпись: значение».
private struct ФишкаХарактеристикиВида: View {
    let пункт: ПунктХарактеристикиВида

    var body: some View {
        HStack(spacing: 6) {
            if let значок = пункт.значок {
                Image(systemName: значок)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .accessibilityHidden(true)
            }
            Text(пункт.текст)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.поверхность2, in: Capsule())
    }
}

// MARK: - Способы оплаты (mkPayBlock) — только расчёт

struct СпособыОплатыСайта: View {
    let товар: Listing
    let оплата: ОплатаОбъявления
    /// «inst» или «cred» — открытая вкладка, как .mk-paytab.sel.
    @State private var выбрано = "inst"
    @State private var срокРассрочки = 12
    @State private var срокКредита = 24

    private static let срокиРассрочки = [3, 6, 9, 12, 24]
    private static let срокиКредита = [6, 12, 24, 36, 48, 60]
    private static let цветКредита = Theme.цвет(0x1D4ED8, 0x7FB2FF)

    /// Явный init: блок создаёт страница из другого файла, а private @State прячет готовый.
    init(товар: Listing, оплата: ОплатаОбъявления) {
        self.товар = товар
        self.оплата = оплата
    }

    private var цена: Double { товар.price ?? 0 }
    private var обе: Bool { оплата.рассрочка && оплата.кредит }
    /// Какая панель видна: при двух — выбранная вкладка, при одной — она.
    private var рассрочкаНаЭкране: Bool { оплата.рассрочка && (!оплата.кредит || выбрано == "inst") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ПодзаголовокСайта(значок: "creditcard", текст: тВида("pay_methods"))
            if обе {
                вкладки
            }
            if рассрочкаНаЭкране {
                панельРассрочки
            } else {
                панельКредита
            }
        }
    }

    private var вкладки: some View {
        HStack(spacing: 0) {
            вкладка("inst", тВида("installment"), цвет: Theme.зелёный2)
            вкладка("cred", тВида("credit"), цвет: Self.цветКредита)
        }
        .padding(4)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func вкладка(_ ключ: String, _ текст: String, цвет: Color) -> some View {
        let выбрана = выбрано == ключ
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { выбрано = ключ }
        } label: {
            Text(текст)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(выбрана ? цвет : Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if выбрана {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(Theme.поверхность)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    // MARK: Рассрочка (mkPayRow("inst", …))

    private var панельРассрочки: some View {
        let сумма = (цена * (1 + оплата.комиссия / 100)).rounded()
        let заголовок = оплата.комиссия > 0
            ? String(format: тВида("inst_plus"), ОплатаОбъявления.процент(оплата.комиссия))
            : тВида("installment")
        return СтрокаОплаты(рассрочка: true, заголовок: заголовок, подпись: подписьРассрочки,
                            вМесяц: ОплатаОбъявления.вМесяц(сумма, ставка: 0, месяцев: срокРассрочки),
                            от: false, сроки: Self.срокиРассрочки, срок: $срокРассрочки,
                            цвет: Theme.зелёный2)
    }

    /// mkInstSub: «Комиссия рассрочки 5%» или «Рассрочка», дальше банки или «без банка (нотариус)».
    private var подписьРассрочки: String {
        let начало = оплата.комиссия > 0
            ? String(format: тВида("inst_comm"), ОплатаОбъявления.процент(оплата.комиссия))
            : тВида("installment")
        if оплата.нотариус { return начало + " · " + тВида("no_bank_notary") }
        let банки = ОплатаОбъявления.банки(оплата.банкиРассрочки)
        return банки.isEmpty ? начало : начало + " · " + банки
    }

    // MARK: Кредит (mkPayRow("cred", …))

    private var панельКредита: some View {
        let заголовок = String(format: тВида("cred_rate"), ОплатаОбъявления.процент(оплата.ставка))
        return СтрокаОплаты(рассрочка: false, заголовок: заголовок,
                            подпись: ОплатаОбъявления.банки(оплата.банкиКредита),
                            вМесяц: ОплатаОбъявления.вМесяц(цена, ставка: оплата.ставка, месяцев: срокКредита),
                            от: оплата.ставка > 0, сроки: Self.срокиКредита, срок: $срокКредита,
                            цвет: Self.цветКредита)
    }
}

/// .mk-payopt2: значок, заголовок с банками, «от 123 450 ₸ × 12 мес» и сроки в полосе.
private struct СтрокаОплаты: View {
    let рассрочка: Bool
    let заголовок: String
    let подпись: String
    let вМесяц: Int
    let от: Bool
    let сроки: [Int]
    @Binding var срок: Int
    let цвет: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: рассрочка ? "wallet.pass" : "building.columns")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(цвет)
                    .frame(width: 38, height: 38)
                    .background(цвет.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    if !подпись.isEmpty {
                        Text(подпись)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(суммаСтрокой)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("× \(срок) " + тВида("mon"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                ForEach(сроки, id: \.self) { месяцев in
                    кнопкаСрока(месяцев)
                }
            }
            .padding(4)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
    }

    private var суммаСтрокой: String {
        let сумма = ListingCard.тенге(Double(вМесяц))
        return от ? тВида("from") + " " + сумма : сумма
    }

    private func кнопкаСрока(_ месяцев: Int) -> some View {
        let выбран = срок == месяцев
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { срок = месяцев }
        } label: {
            Text(String(месяцев))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(выбран ? цвет : Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if выбран {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(Theme.поверхность)
                            .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(месяцев) " + тВида("mon"))
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Расположение (mkLocationBlock)

// Блок «Расположение» с картой, маршрутом и курьером — у всех разделов, в SiteListingLocation.swift.
