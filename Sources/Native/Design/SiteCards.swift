import Foundation
import SwiftUI
import UIKit

/**
 КАРТОЧКИ ВИТРИНЫ КАК НА САЙТЕ — ЭТАП 49 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Правила и вид — из кода сайта, а не на глаз:
   · цена — mkPriceHTML(t, false) и fmtCard (js/marketplace.min.js): от миллиона «14,5 млн ₸», «ТОРГ» мелко, старая цена
     зачёркнута, аренда «/сут», «/М»; нет цены, аренды и «договорной» — строки цены нет вовсе (_mkVitHasPrice);
   · карточки рядов «Рекомендуем» и VIP — владелец 26.09.2026 («стили съехали — одинаковые должны быть, разница только
     оплаченная или не оплаченная»): та же карточка витрины, что в ленте (ListingCard), а не mhCardFor по виду раздела;
     КарточкаГлавной ниже осталась только для превью подачи; вакансии — своя карточка (mhCardJob);
   · карточка ленты — mkVitCardHTML (скин «vitrina», по умолчанию у сайта): метка состояния (mkCond), «Резерв», «★ ТОП»,
     точки фото, цена, название, строка характеристик (mkCapSpecs) и знак доверия (mkVitTrust) с городом внизу.
 Картинки — только через КартинкиЛенты (FeedImages.swift), тени — заливкой подложки, как у прежних карточек (сборка 33).
 */

// MARK: - Цена (mkPriceHTML(t, false), fmtCard)

/// Цена карточки как у сайта. nil у `для(_:)` — строки цены нет.
struct ЦенаКарточкиСайта: Hashable {
    enum Вид: Hashable { case сумма, договорная }

    let вид: Вид
    /// «14,5 млн ₸», «5 000 ₸» или «Договорная».
    let основная: String
    /// Аренда: «/сут» или «/М».
    let единица: String?
    /// Старая цена выше нынешней: она зачёркнута, а нынешняя красная (.mk-price-drop).
    let старая: String?
    /// price_negotiable при цене — «ТОРГ» (.mk-price-torg).
    let торг: Bool

    /// mkPriceHTML(t, false) при _mkVitHasPrice: цена, аренда с суточной ценой или «договорная»; иначе nil.
    /// `режимАренды` — лента в режиме «Аренда» (mkSt.intent == "rent"): у сдаваемого — цена аренды «N ₸/сут» или «/М», а
    /// без неё — «Аренда · Договорная», как первая ветка mkPriceHTML.
    static func для(_ т: Listing, режимАренды: Bool = false) -> ЦенаКарточкиСайта? {
        let цена = т.price ?? 0
        let день = т.rentPriceDay ?? 0
        let аренда = т.forRent && день > 0
        guard цена > 0 || аренда || т.negotiable else { return nil }
        if режимАренды && т.forRent {
            if день > 0 {
                let единица = "/" + ListingPageText.т(т.периодАренды == "month" ? "unit_month" : "unit_day")
                return ЦенаКарточкиСайта(вид: .сумма, основная: сумма(день), единица: единица, старая: nil, торг: false)
            }
            let подпись = ВитринаТекст.т("rent") + " · " + ВитринаТекст.т("negotiable")
            return ЦенаКарточкиСайта(вид: .договорная, основная: подпись, единица: nil, старая: nil, торг: false)
        }
        if аренда && (т.negotiable || цена <= 0) {
            let единица = "/" + ListingPageText.т(т.периодАренды == "month" ? "unit_month" : "unit_day")
            return ЦенаКарточкиСайта(вид: .сумма, основная: сумма(день), единица: единица, старая: nil, торг: false)
        }
        if т.negotiable && цена <= 0 {
            return ЦенаКарточкиСайта(вид: .договорная, основная: ListingPageText.т("negotiable"), единица: nil,
                                     старая: nil, торг: false)
        }
        if let было = т.oldPrice, было > цена {
            return ЦенаКарточкиСайта(вид: .сумма, основная: сумма(цена), единица: nil, старая: сумма(было),
                                     торг: т.negotiable)
        }
        return ЦенаКарточкиСайта(вид: .сумма, основная: сумма(цена), единица: nil, старая: nil, торг: т.negotiable)
    }

    /// fmtCard: от миллиона — десятые доли миллиона с запятой («14,5 млн»), меньше — с разрядами («476 250»).
    static func коротко(_ n: Double) -> String {
        if n >= 1_000_000 {
            let десятые = (n / 100_000).rounded() / 10
            return (дробное.string(from: NSNumber(value: десятые)) ?? String(десятые)) + "\u{00A0}" + DesignText.т("mln")
        }
        return целое.string(from: NSNumber(value: n.rounded())) ?? String(Int(n))
    }

    /// «14,5 млн ₸».
    static func сумма(_ n: Double) -> String {
        (коротко(n) + "\u{00A0}₸").слеваНаправо
    }

    /// Полная сумма — mkMoney сайта («476 250 ₸»): у «Вы смотрели».
    static func полная(_ n: Double) -> String {
        ((целое.string(from: NSNumber(value: n.rounded())) ?? String(Int(n))) + "\u{00A0}₸").слеваНаправо
    }

    /// Как toLocaleString("ru-RU") сайта: разряды неразрывным пробелом, дробь запятой.
    private static let дробное: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"
        ф.decimalSeparator = ","
        ф.minimumFractionDigits = 0
        ф.maximumFractionDigits = 1
        return ф
    }()

    private static let целое: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"
        ф.maximumFractionDigits = 0
        return ф
    }()

    /**
     Одна строка цены: у главной (.mh-pr) — сумма 16 px, «/сут», старая и «ТОРГ» мелко и серым, «Договорная» 14 px цветом
     текста; у ленты (.mk-vc-price) — сумма 19 px, подписи 0,6 от неё, «ТОРГ» зелёным. Зелёный — --mk-green2 сайта: в
     тёмной теме это --acc-on (Theme.акцент). `краска` — фирменный цвет магазина (.mk-cbrand .mk-price-v): им сумма.
     */
    func текст(кегль: CGFloat, главная: Bool, краска: Color? = nil) -> Text {
        switch вид {
        case .договорная:
            /* Владелец: «Договорная» не курсивом и не крупным зелёным — как .vx-pr .mk-price-neg: мельче суммы, жирно,
               цветом текста. */
            return Text(основная)
                .font(.system(size: главная ? кегль * 14 / 16 : кегль * 0.75, weight: .bold))
                .foregroundColor(Theme.текст)
        case .сумма:
            let мелкий = главная ? кегль * 11 / 16 : кегль * 0.62
            var итог = Text(основная)
                .font(.system(size: кегль, weight: .heavy))
                .foregroundColor(краска ?? (старая != nil ? Theme.ценаСкидка : Theme.текст))
            if let единица {
                итог = итог + Text(единица)
                    .font(.system(size: мелкий, weight: .bold))
                    .foregroundColor(Theme.текстВторой)
            }
            if let старая {
                итог = итог + Text(" ")
                    .font(.system(size: мелкий)) + Text(старая)
                    .font(.system(size: мелкий, weight: главная ? .semibold : .bold))
                    .foregroundColor(Theme.текстВторой)
                    .strikethrough(true, color: Theme.ценаСкидка)
            }
            if торг {
                итог = итог + Text("  " + ListingPageText.т("torg").uppercased())
                    .font(.system(size: главная ? мелкий : кегль * 0.6, weight: .bold))
                    .foregroundColor(главная ? Theme.текстВторой : Theme.акцент)
            }
            return итог
        }
    }
}

// MARK: - Правила карточек (mhCardCar, mhCardFlat, _mhSpecs, mkCapSpecs, mkVitTrust)

/// Вид карточки ряда главной — mhCardFor сайта.
enum ВидКарточкиГлавной: Hashable {
    case авто, жильё, техника, услуга, товар

    /// Ряд раздела: его ключ решает вид (животные и «Товары» — как товар).
    init(ряда ключ: String) {
        switch ключ {
        case "transport": self = .авто
        case "realty": self = .жильё
        case "electronics": self = .техника
        case "services": self = .услуга
        default: self = .товар
        }
    }

    /// mhKindOf — VIP: по корню раздела самого объявления.
    init(товара т: Listing) {
        self.init(ряда: т.корень)
    }
}

/// Знак доверия внизу карточки ленты (mkVitTrust): текст и щит — у «Гаранта», у прочих галочка; в режиме сделок eds —
/// «Подпись eGov» со значком подписи.
struct ЗнакДоверияКарточки: Hashable {
    let текст: String
    let щит: Bool
    /// Режим MK_DEAL_MODE = "eds": у объявления есть «Сделка с подписью eGov» — значок подписи вместо щита.
    var подписьEGov: Bool = false
}

extension Listing {
    /// Строка из одних цифр ASCII — /^\d+$/ сайта.
    fileprivate static func цифры(_ строка: String) -> Bool {
        !строка.isEmpty && строка.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// parseFloat сайта: число в начале строки («75.5 м²» → 75,5); не число — nil.
    static func числоВНачале(_ строка: String) -> Double? {
        var цифры = ""
        var точка = false
        for знак in строка.trimmingCharacters(in: .whitespaces) {
            if знак.isASCII && знак.isNumber {
                цифры.append(знак)
            } else if знак == "." && !точка && !цифры.isEmpty {
                точка = true
                цифры.append(знак)
            } else {
                break
            }
        }
        /* Длиннее 15 знаков — не площадь и не этаж; и Int(Double) у вызывающих на таком числе упал бы. */
        guard цифры.count <= 15 else { return nil }
        return Double(цифры)
    }

    /// fmt(): разряды пробелом, дробь запятой — «75,5».
    static func дробь(_ n: Double) -> String {
        форматДробиКарточки.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static let форматДробиКарточки: NumberFormatter = {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"
        ф.decimalSeparator = ","
        ф.maximumFractionDigits = 3
        return ф
    }()

    /// «2019 г. · 120 000 км · 3.5 л · АКПП» — mhCardCar: только у легковых (раздел под «cars»).
    var строкаАвтоГлавной: String {
        guard РазделыСайта.внутри(категория, ["cars"]) else { return "" }
        var части: [String] = []
        let год = (годСтрокой ?? "").trimmingCharacters(in: .whitespaces)
        if год.count == 4 && Self.цифры(год) && !title.contains(год) {
            let г = DesignText.т("y")
            части.append(г.isEmpty ? год : год + " " + г)
        }
        if let пробег = Int(String((ramСтрокой ?? "").filter { $0.isASCII && $0.isNumber })), пробег > 0 {
            части.append(DesignText.число(пробег) + " " + DesignText.т("km"))
        }
        var объём = (storageСтрокой ?? "").trimmingCharacters(in: .whitespaces)
        if let запятая = объём.range(of: ",") { объём.replaceSubrange(запятая, with: ".") }
        if объём.range(of: "^\\d{1,2}(\\.\\d)?$", options: .regularExpression) != nil, (Double(объём) ?? 0) > 0 {
            части.append(объём + " " + DesignText.т("l"))
        }
        let коробка = (cpuСтрокой ?? "").trimmingCharacters(in: .whitespaces)
        if !коробка.isEmpty && коробка.count < 14 { части.append(коробка) }
        return части.joined(separator: " · ")
    }

    /// «3-комн. · 75 м² · 5/9 эт.» — mhCardFlat; название уже с площадью («… 570 м² …») — пусто.
    var строкаЖильяГлавной: String {
        if title.range(of: "м²|m²|кв\\.?\\s?м", options: [.regularExpression, .caseInsensitive]) != nil { return "" }
        var части: [String] = []
        let комнаты = жильё["rooms"] ?? ""
        if Self.цифры(комнаты) {
            части.append(String(format: DesignText.т("rooms"), комнаты))
        } else if комнаты == "studio" {
            части.append(DesignText.т("studio"))
        }
        if let площадь = Self.числоВНачале(жильё["area"] ?? ""), площадь > 0 {
            части.append(Self.дробь(площадь) + " " + DesignText.т("m2"))
        }
        let этаж = Int(Self.числоВНачале(жильё["floor"] ?? "") ?? 0)
        let этажей = Int(Self.числоВНачале(жильё["floors"] ?? "") ?? 0)
        if этаж > 0 {
            части.append((этажей > 0 ? "\(этаж)/\(этажей)" : String(этаж)) + " " + DesignText.т("fl"))
        }
        return части.joined(separator: " · ")
    }

    /// Подвал карточки жилья: район (без «(…)») и город — «Есильский район · Астана».
    var подвалЖильяГлавной: String {
        var части: [String] = []
        if let район = районНазвание, !район.contains("(") { части.append(район) }
        if !city.isEmpty { части.append(city) }
        return части.joined(separator: " · ")
    }

    /// «512 ГБ» из «512GB», «1 ТБ» из «1TB» — _mhVol.
    static func объёмПамяти(_ строка: String) -> String {
        let чистая = строка.trimmingCharacters(in: .whitespaces)
        guard let совпадение = чистая.range(of: "^(\\d+(?:[.,]\\d+)?)\\s*(gb|гб|tb|тб)$",
                                            options: [.regularExpression, .caseInsensitive]) else { return чистая }
        let найдено = String(чистая[совпадение])
        var число = ""
        for знак in найдено {
            if (знак.isASCII && знак.isNumber) || знак == "." || знак == "," { число.append(знак) } else { break }
        }
        let тера = найдено.lowercased().hasSuffix("tb") || найдено.lowercased().hasSuffix("тб")
        return число.replacingOccurrences(of: ".", with: ",") + " " + DesignText.т(тера ? "tb" : "gb")
    }

    /// _mxSpecVal: число с единицей из подписи («Площадь, м²» → «570 м²»), число без неё — «подпись: число».
    fileprivate static func значениеХарактеристики(_ подпись: String, _ значение: String) -> String {
        let з = значение.trimmingCharacters(in: .whitespaces)
        if з.isEmpty || з == "—" || з == "-" { return "" }
        let п = подпись.trimmingCharacters(in: .whitespaces)
        guard з.range(of: "^[\\d.,]+$", options: .regularExpression) != nil else { return з }
        if let единица = п.range(of: ",\\s*([^,\\s]{1,6})$", options: .regularExpression) {
            let хвост = п[единица].drop { $0 == "," || $0 == " " }
            return з + " " + хвост
        }
        return п.isEmpty ? з : п + ": " + з
    }

    /// Характеристики карточки техники главной — _mhSpecs(t, 3): specs без образцов цвета; нет их у электроники —
    /// процессор, память, накопитель, видеокарта.
    var строкаТехникиГлавной: String {
        var части: [String] = []
        for пункт in характеристикиКарточки where !пункт.образец && части.count < 3 {
            let значение = Self.значениеХарактеристики(пункт.ключ, Self.объёмПамяти(пункт.значение))
            if !значение.isEmpty { части.append(значение) }
        }
        if части.isEmpty && ВидКарточкиГлавной(товара: self) == .техника {
            let поля: [(String?, Bool)] = [(cpuСтрокой, false), (ramСтрокой, true), (storageСтрокой, false), (gpuСтрокой, false)]
            for (поле, гигабайты) in поля where части.count < 3 {
                let з = (поле ?? "").trimmingCharacters(in: .whitespaces)
                guard !з.isEmpty, з != "—", з != "-" else { continue }
                части.append(гигабайты && Self.цифры(з) ? з + " " + DesignText.т("gb") : Self.объёмПамяти(з))
            }
        }
        return части.joined(separator: " · ")
    }

    /// «★ 4,8  12 отзывов» у карточки услуги — оценка и отзывы продавца, только если есть и то и другое.
    var оценкаУслугиГлавной: (оценка: String, отзывы: String)? {
        guard let оценка = рейтингПродавца, оценка > 0, let отзывы = отзывыПродавца, отзывы > 0 else { return nil }
        let строка = String(format: "%.1f", оценка).replacingOccurrences(of: ".", with: ",")
        return (строка, ListingPageText.число(отзывы, "reviews"))
    }

    /// Порядок полей жилья в чипах ленты — MK_REALTY_ORDER сайта.
    private static let порядокЖилья = ["rooms", "area", "land_area", "floor", "floors", "term", "renovation", "building",
                                      "bathroom", "year_built", "land_use", "docs", "mortgage_ok", "utilities",
                                      "furniture", "parking", "kids", "pets", "owner"]
    /// Поля-признаки: «да» у них — подпись поля (MK_REALTY_LBL).
    private static let признакиЖилья: Set<String> = ["mortgage_ok", "utilities", "furniture", "parking", "kids", "pets"]
    /// Значения со словом (MK_REALTY_VAL) — ключи текстов «r_<значение>».
    private static let словаЖилья: Set<String> = ["studio", "none", "cosmetic", "euro", "design", "brick", "panel",
                                                  "monolith", "block", "separate", "combined", "two", "private", "share",
                                                  "mortgage", "other", "long", "daily", "owner", "agent", "ijs",
                                                  "garden", "farm", "commercial"]

    /// Строка характеристик карточки ленты — mkCapSpecs(t, 3): поля жилья, иначе первые четыре specs (без образцов
    /// цвета, значения — значениеСтрокиЛенты), иначе у электроники процессор, видеокарта, память и накопитель. До трёх,
    /// через «·». По вертикалям (набор specs даёт сервер, build_card_specs): авто — год · пробег · объём (коробка,
    /// если чего-то нет); жильё — комнаты · площадь · этаж/этажность; электроника — справочник e_specs (память, экран…);
    /// одежда — размер; дом и сад — материал · цвет · размер; животные — вид · порода · возраст; услуги — пусто.
    var строкаХарактеристикЛенты: String {
        var части: [String] = []
        if жильё["kind"] != nil {
            for ключ in Self.порядокЖилья where части.count < 3 {
                guard let значение = жильё[ключ] else { continue }
                if ключ == "floors" && жильё["floor"] != nil { continue }
                if Self.признакиЖилья.contains(ключ) {
                    if значение == "1" { части.append(DesignText.т("rl_" + ключ)) }
                    continue
                }
                if ключ == "floor", let всего = жильё["floors"] {
                    части.append(значение + "/" + всего)
                } else if Self.словаЖилья.contains(значение) {
                    части.append(DesignText.т("r_" + значение))
                } else {
                    let единица: String
                    switch ключ {
                    case "area": единица = DesignText.т("m2")
                    case "land_area": единица = DesignText.т("sot")
                    case "rooms": единица = DesignText.т("rooms_chip")
                    default: единица = ""
                    }
                    части.append(единица.isEmpty ? значение : значение + " " + единица)
                }
            }
            if !части.isEmpty { return части.joined(separator: " · ") }
        }
        if !характеристикиКарточки.isEmpty {
            for пункт in характеристикиКарточки.prefix(4) where !пункт.образец && части.count < 3 {
                let значение = пункт.значение.trimmingCharacters(in: .whitespaces)
                let пусто = значение.isEmpty || значение.range(of: "^0+([.,]0+)?$", options: .regularExpression) != nil
                    || ["-", "—", "–", "n/a", "na", "null", "undefined", "нет", "нет данных", "не указано", "не задано"]
                        .contains(значение.lowercased())
                if пусто { continue }
                части.append(Self.значениеСтрокиЛенты(пункт.ключ, значение))
            }
        } else if корень == "electronics" {
            let ram = (ramСтрокой ?? "").trimmingCharacters(in: .whitespaces)
            for значение in [cpuСтрокой ?? "", gpuСтрокой ?? "", ram.isEmpty ? "" : ram + " " + DesignText.т("gb_ram"),
                             storageСтрокой ?? ""] where части.count < 3 {
                let з = значение.trimmingCharacters(in: .whitespaces)
                if !з.isEmpty { части.append(з) }
            }
        }
        return части.joined(separator: " · ")
    }

    /// SPEC_VAL_MAP сайта (mkSpecV): коробка, топливо, видеокарта, состояние — сервер кладёт их по-русски, показ на
    /// языке приложения.
    private static let словаХарактеристик: [String: String] = [
        "Автомат": "sv_auto", "Механика": "sv_manual", "Робот": "sv_robot", "Вариатор": "sv_cvt",
        "Бензин": "sv_petrol", "Дизель": "sv_diesel", "Газ": "sv_gas", "Гибрид": "sv_hybrid", "Электро": "sv_electric",
        "Встроенная": "sv_gpu_int", "Дискретная": "sv_gpu_disc", "Новый": "sv_new", "Б/У": "sv_used", "Студия": "sv_studio"
    ]
    /// Подпись «Пробег» (sp_run) на всех языках сервера: сервер переводит подписи на язык смотрящего.
    private static let подписиПробега: Set<String> = ["Пробег", "Жүрісі", "Mileage", "المسافة المقطوعة"]

    /// Значение в строке характеристик ленты: пробег — с разрядами и «км» («120 000 км»), слово справочника — на языке
    /// приложения («Automatic»), число с единицей в подписи («Двигатель, л», «Площадь, м²») — с ней («2.0 л»), как
    /// _mxSpecVal сайта; прочее — как пришло («2019», «Лабрадор»).
    static func значениеСтрокиЛенты(_ подпись: String, _ сырое: String) -> String {
        let з = сырое.trimmingCharacters(in: .whitespaces)
        let п = подпись.trimmingCharacters(in: .whitespaces)
        if подписиПробега.contains(п) {
            let сплошь = з.filter { !$0.isWhitespace }
            if сплошь.count <= 9, Self.цифры(сплошь), let n = Int(сплошь) {
                return DesignText.число(n) + " " + DesignText.т("km")
            }
            return з + " " + DesignText.т("km")
        }
        if let ключ = словаХарактеристик[з] { return DesignText.т(ключ) }
        if з.range(of: "^[\\d.,]+$", options: .regularExpression) != nil,
           let единица = п.range(of: ",\\s*([^,\\s]{1,6})$", options: .regularExpression) {
            let хвост = п[единица].drop { $0 == "," || $0 == " " }
            return з + " " + хвост
        }
        return з
    }

    /// mkVitTrust: проверки VIN, кадастра и IMEI, гарантия, «Мастер проверен» у проверенного исполнителя услуг,
    /// «Безопасно» со щитом у проверенного продавца — кроме «без гаранта», цены ниже MK_ESCROW_MIN (20 000 ₸, home.html)
    /// и паузы гаранта. В режиме сделок eds вместо «Безопасно» — «Подпись eGov» у объявлений со «Сделкой с подписью eGov».
    var знакДоверияЛенты: ЗнакДоверияКарточки? {
        if Config.проверкиПоБазам {
            if проверкаАвто { return ЗнакДоверияКарточки(текст: DesignText.т("t_vin"), щит: false) }
            if проверкаЖилья { return ЗнакДоверияКарточки(текст: DesignText.т("t_cad"), щит: false) }
            if проверкаУстройства { return ЗнакДоверияКарточки(текст: DesignText.т("t_imei"), щит: false) }
        }
        if гарантияОтмечена, let дни = гарантияДней, дни > 0 {
            return ЗнакДоверияКарточки(текст: String(format: DesignText.т("t_warranty"), Listing.срокГарантии(дни)),
                                       щит: false)
        }
        guard продавецПроверен else { return nil }
        if услуга { return ЗнакДоверияКарточки(текст: DesignText.т("t_master"), щит: false) }
        /* Режим сделок eds (MK_DEAL_MODE): гаранта нет, и щит «Безопасно» обещал бы то, чего на странице объявления не будет.
           Знак — только там, где там будет «Сделка с подписью eGov» (T сайта: СделкаEDSОбъявления.подходит). */
        if РежимСделокСайта.edsСейчас {
            guard СделкаEDSОбъявления.подходит(self) else { return nil }
            return ЗнакДоверияКарточки(текст: DesignText.т("t_eds"), щит: false, подписьEGov: true)
        }
        let цена = price ?? 0
        let аренда = forRent && (rentPriceDay ?? 0) > 0 && (negotiable || цена <= 0)
        if безГаранта || (цена > 0 && цена < 20_000 && !аренда) { return nil }
        /* Упрощение для новичка: щит «Безопасно» (не путать с «Гарантия 6 мес») — только пока гарант не на паузе. */
        if ПаузаГаранта.наПаузеСейчас { return nil }
        return ЗнакДоверияКарточки(текст: DesignText.т("t_escrow"), щит: true)
    }

    /// Подвал карточки ленты справа: город, без него — когда добавлено (mkDate(created_at, true)).
    var местоЛенты: String {
        if !city.isEmpty { return city }
        guard let создано else { return "" }
        return Listing.датаСайта(создано, коротко: true)
    }

    /// .mk-cbrand: фирменный цвет магазина (shop_accent «#RRGGBB») — полоса сверху карточки и цена; слишком светлый
    /// (яркость по WCAG выше 0,6) притемнён на 40 %, как _mkSafeAccent. Цвета нет — nil.
    var краскаМагазинаЛенты: Color? {
        guard let v = акцентМагазина else { return nil }
        func канал(_ x: UInt32) -> Double {
            let c = Double(x) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = (v >> 16) & 0xFF
        let g = (v >> 8) & 0xFF
        let b = v & 0xFF
        let яркость = 0.2126 * канал(r) + 0.7152 * канал(g) + 0.0722 * канал(b)
        let доля = яркость > 0.6 ? 0.6 : 1.0
        return Color(red: (Double(r) * доля).rounded() / 255, green: (Double(g) * доля).rounded() / 255,
                     blue: (Double(b) * доля).rounded() / 255)
    }
}

/**
 Фото карточки во всю ширину ячейки: высота = ширина × доля, какую бы высоту ни предложили. Владелец 28.09.2026,
 TestFlight («фото разъехались»): у .aspectRatio(.fit) в карточке, растянутой на высоту ряда, VStack делил высоту
 пополам между фото и телом (у тела maxHeight: .infinity) — фото по этой высоте сужалось, справа оставалась полоса,
 а сердце, «Поделиться» и точки уезжали от картинки. Здесь высота жёсткая — ужимается только тело.
 */
struct ФотоНаШиринуКарточки: Layout {
    /// Высота к ширине: 3/4 у ленты (4:3), 1 у квадрата.
    let доля: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var ширина: CGFloat = proposal.width ?? 180
        if !ширина.isFinite { ширина = 180 }
        return CGSize(width: ширина, height: ширина * доля)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for вид in subviews {
            вид.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}

extension View {
    /// Во всю предложенную ширину, высота — ширина × доля (ФотоНаШиринуКарточки).
    func наШиринуКарточки(_ доля: CGFloat) -> some View {
        ФотоНаШиринуКарточки(доля: доля) { self }
    }

    /**
     Строка карточки ровно в одну строку шрифта `шрифт` (владелец 26.09.2026: «размеры объявлений одинаковые должны
     быть»): высоту задаёт невидимый пробел этим шрифтом во всю ширину, а сама строка лежит поверх него слева. Цена
     «Договорная» курсивом помельче, значок оценки или щит «Гаранта» выше текста — высота строки та же, и карточки ряда
     не расходятся на пару точек, как у сайта с его line-height.
     */
    func вСтрокуКарточки(_ шрифт: Font) -> some View {
        Text(" ")
            .font(шрифт)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { self }
    }

    /**
     Карточка в ячейке сетки тянется на высоту ряда — как grid с align-items: stretch у сайта: LazyVGrid ставит ячейки
     ряда по самой высокой, и короткая карточка дотягивает подложку до неё, а не кончается выше соседки. В ленте из
     одних строк (без предложенной высоты) это её собственная высота — ничего не меняется.
     */
    func вВысотуРядаСетки() -> some View {
        frame(maxHeight: .infinity, alignment: .top)
    }

    /**
     «Поделиться» на карточке ленты — .mk-cshare сайта (этап 49): кружок 32 pt из поверхности 82 % под сердцем (46 pt от
     верха, 8 от края), стрелка из квадрата серым. Нажатие — системный лист: ссылка на объявление и ««Название» — цена»,
     как текст mkShare. Слой над карточкой, а не внутри ссылки — как сердечкоИзбранного. Не вид сайта — ничего.
     */
    func поделитьсяНаКарточке(_ товар: Listing) -> some View {
        overlay(alignment: .topTrailing) {
            if Config.дизайнКакНаСайте, товар.адрес != nil {
                Button { ЛистПоделитьсяСайта.показать(товар) } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 32, height: 32)
                        .background(Theme.поверхность.opacity(0.82), in: Circle())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.85))
                .padding(.top, 40)
                .accessibilityLabel(FeedText.т("share"))
            }
        }
    }
}

extension Listing {
    /// ««Название» — 14 500 000 ₸» (без цены — «Договорная»), как r у mkShare сайта.
    var текстОтправкиКарточки: String {
        let цена = price ?? 0
        let сумма = цена > 0 ? ЦенаКарточкиСайта.полная(цена) : ListingPageText.т("negotiable")
        return "«" + title + "» — " + сумма
    }
}

// MARK: - Мелкие части

/// «★ ТОП» карточек главной (.mh-top): 24 pt, золото 135°, белые заглавные 10 pt.
struct МеткаТопГлавной: View {
    init() {}

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .bold))
            Text(FeedText.т("top").uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(LinearGradient(colors: [Theme.топНачало, Theme.топКонец], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .shadow(.drop(color: Color(red: 176 / 255, green: 132 / 255, blue: 24 / 255).opacity(0.5),
                                      radius: 4, x: 0, y: 3)),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Пока ряды грузятся — .mh-sk (полоса 40 % ширины, 22 pt) и пять карточек 3:4 (.mh-skc) шириной карточки ряда, как у
/// сайта до ответа.
struct СкелетРядовГлавной: View {
    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { место in
                МерцаниеСайта(радиус: Theme.Радиус.xxs)
                    .frame(width: место.size.width * 0.4, height: 22)
            }
            .frame(height: 22)
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { _ in
                        МерцаниеСайта(радиус: Theme.Радиус.md)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .containerRelativeFrame(.horizontal) { длина, _ in ШиринаКарточкиРяда.для(длина) }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollDisabled(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessText.т("loading"))
    }
}

// MARK: - Карточка ряда главной (.mh-c)

/**
 Карточка ряда «Рекомендуем» и VIP — mhCardFor сайта. Фото 1:1 на подложке, «★ ТОП» слева сверху, сердце справа
 (слоем снаружи, сердечкоИзбранного). Тело — по виду раздела:
   авто — цена, название в строку, «год · пробег · объём · коробка», город;
   жильё — цена, «комнаты · площадь · этаж», название, район и город;
   техника — подраздел краской ряда, название, три характеристики, цена, «состояние · город»;
   услуги — название, ★ оценка и отзывы, продавец, цена, город;
   товары и животные — цена, название, «когда · город».
 У VIP цена всегда первой строкой (.mh-vipg .mh-pr { order: -1 }), рамка золотая у всех. Строки держат своё место и
 пустыми, чтобы карточки одного ряда были одной высоты, как в сетке сайта.
 */
struct КарточкаГлавной: View {
    let товар: Listing
    let вид: ВидКарточкиГлавной
    let вип: Bool
    /// Краска ряда (--vc) — у подписи подраздела техники; у VIP — краска бренда.
    let краска: UInt32
    /// Название подраздела (_mxKind) — только у техники; nil — строка пустая.
    let подраздел: String?
    @Environment(\.colorScheme) private var схема
    @ScaledMetric(relativeTo: .subheadline) private var сотня: CGFloat = 100

    init(товар: Listing, вид: ВидКарточкиГлавной, вип: Bool = false, краска: UInt32 = 0x0F5132, подраздел: String? = nil) {
        self.товар = товар
        self.вид = вид
        self.вип = вип
        self.краска = краска
        self.подраздел = подраздел
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            фото
            тело
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .вВысотуРядаСетки()             // VIP-сетка: карточки разных разделов в ряду — одной высоты
        .background(фон)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            if золотая {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.топРамка, lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .теньКарточкиСайта()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)
    }

    private var золотая: Bool { товар.isTop || вип }

    private func кегль(_ пикселей: CGFloat) -> CGFloat { пикселей * сотня / 100 }

    private var фото: some View {
        Theme.поверхность2
            .наШиринуКарточки(1)          // квадрат ровно во всю ширину — VStack не ужмёт его ради тела
            .overlay {
                КартинкаЛенты(товар.обложка, пунктов: 240) {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.текстВторой.opacity(0.5))
                }
            }
            .clipped()
            .overlay(alignment: .topLeading) {
                if товар.isTop {
                    МеткаТопГлавной()
                        .padding(8)
                }
            }
    }

    @ViewBuilder
    private var фон: some View {
        if золотая {
            LinearGradient(stops: [Gradient.Stop(color: Theme.топФон, location: 0),
                                   Gradient.Stop(color: Theme.поверхность, location: 0.55)],
                           startPoint: .top, endPoint: .bottom)
        } else {
            Theme.поверхность
        }
    }

    private var цена: ЦенаКарточкиСайта? { ЦенаКарточкиСайта.для(товар) }

    @ViewBuilder
    private var тело: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch вид {
            case .авто:
                строкаЦены
                название(строк: 1)
                характеристики(товар.строкаАвтоГлавной, жирно: false, строк: 2)
                пустоВместоЦены
                подвал(товар.city)
            case .жильё:
                строкаЦены
                характеристики(товар.строкаЖильяГлавной, жирно: true, строк: 1)
                название(строк: 2)
                пустоВместоЦены
                подвал(товар.подвалЖильяГлавной)
            case .техника:
                if вип { строкаЦены }
                Text(подраздел ?? " ")
                    .font(.system(size: кегль(11), weight: .bold))
                    .foregroundStyle(Color(uiColor: Theme.смесь(Theme.hex(краска),
                                                                схема == .dark ? UIColor.white : Theme.hex(0x13211B),
                                                                схема == .dark ? 0.55 : 0.82)))
                    .lineLimit(1)
                название(строк: 2)
                характеристики(товар.строкаТехникиГлавной, жирно: false, строк: 2)
                if !вип { строкаЦены }
                пустоВместоЦены
                подвал([товар.меткаСостояния?.текст ?? "", товар.city].filter { !$0.isEmpty }.joined(separator: " · "))
            case .услуга:
                if вип { строкаЦены }
                название(строк: 2)
                оценка
                характеристики(товар.продавец ?? "", жирно: false, строк: 1)
                if !вип { строкаЦены }
                пустоВместоЦены
                подвал(товар.city)
            case .товар:
                строкаЦены
                название(строк: 2)
                пустоВместоЦены
                подвал([товар.создано.map { Listing.датаСайта($0, коротко: true) } ?? "", товар.city]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }
    }

    /// .mh-pr — 16 px, насыщенность 800; нет цены — строки нет.
    @ViewBuilder
    private var строкаЦены: some View {
        if let цена {
            цена.текст(кегль: кегль(16), главная: true)
                .lineLimit(1)
                .truncationMode(.tail)
                .вСтрокуКарточки(.system(size: кегль(16), weight: .heavy))
        }
    }

    /// Нет цены — пустая строка её высоты перед подвалом: карточки ряда остаются одной высоты, как в сетке сайта.
    @ViewBuilder
    private var пустоВместоЦены: some View {
        if цена == nil {
            Text(" ")
                .font(.system(size: кегль(16), weight: .heavy))
                .hidden()
                .accessibilityHidden(true)
        }
    }

    /// .mh-tt — 14 px, 600, в две строки (у авто — в одну).
    private func название(строк: Int) -> some View {
        Text(товар.title)
            .font(.system(size: кегль(14), weight: .semibold))
            .foregroundStyle(Theme.текст)
            .lineLimit(строк, reservesSpace: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// .mh-sp — 12 px серым (у жилья — цветом текста, 600); пусто — место той же высоты.
    private func характеристики(_ строка: String, жирно: Bool, строк: Int) -> some View {
        Text(строка.isEmpty ? " " : строка)
            .font(.system(size: кегль(12), weight: жирно ? .semibold : .regular))
            .foregroundStyle(жирно ? Theme.текст : Theme.текстВторой)
            .lineLimit(строк, reservesSpace: true)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// .mh-rate — «★ 4,8  12 отзывов»; нет оценки — пустая строка той же высоты.
    private var оценка: some View {
        HStack(spacing: 4) {
            if let оценка = товар.оценкаУслугиГлавной {
                Image(systemName: "star.fill")
                    .font(.system(size: кегль(12)))
                    .foregroundStyle(Theme.золото)
                Text(оценка.оценка)
                    .font(.system(size: кегль(12), weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(оценка.отзывы)
                    .font(.system(size: кегль(11), weight: .medium))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .lineLimit(1)
        .вСтрокуКарточки(.system(size: кегль(12), weight: .bold))
    }

    /// .mh-ft — 11 px серым в строку.
    /// Растянутая в ряду VIP-сетки карточка — подвал прижат книзу, как низ карточки сайта.
    private func подвал(_ строка: String) -> some View {
        Text(строка.isEmpty ? " " : строка)
            .font(.system(size: кегль(11)))
            .foregroundStyle(Theme.текстВторой)
            .lineLimit(1)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

// MARK: - Карточка вакансии (.mh-c--job)

/// Вакансия ряда «Работа» — mhCardJob: «★ ТОП», название 15 px, зарплата («от …», «… – …» или «Зарплата не указана»),
/// компания, «город · занятость» и «Откликнуться» цветом раздела. Рамка — краска раздела 26 % с линией.
struct КарточкаВакансииГлавной: View {
    let вакансия: ВакансияГлавной
    let краска: UInt32
    @ScaledMetric(relativeTo: .subheadline) private var сотня: CGFloat = 100

    init(вакансия: ВакансияГлавной, краска: UInt32) {
        self.вакансия = вакансия
        self.краска = краска
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if вакансия.топ { МеткаТопГлавной() }
            Text(вакансия.название)
                .font(.system(size: кегль(15), weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text(зарплата ?? DesignText.т("sal_none"))
                .font(.system(size: кегль(зарплата == nil ? 14 : 15), weight: зарплата == nil ? .semibold : .heavy))
                .foregroundStyle(зарплата == nil ? Theme.текстВторой : Theme.текст)
                .lineLimit(1)
                .вСтрокуКарточки(.system(size: кегль(15), weight: .heavy))
            Text(вакансия.компания.isEmpty ? " " : вакансия.компания)
                .font(.system(size: кегль(14), weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            Text(подпись.isEmpty ? " " : подпись)
                .font(.system(size: кегль(12)))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2, reservesSpace: true)
            if !вакансия.топ {
                МеткаТопГлавной().hidden()
            }
            Spacer(minLength: 0)
            Text(DesignText.т("respond"))
                .font(.system(size: кегль(14), weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Color(uiColor: Theme.hex(краска)),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Color(uiColor: рамка), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([вакансия.название, зарплата ?? DesignText.т("sal_none"), вакансия.компания, подпись]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }

    private func кегль(_ пикселей: CGFloat) -> CGFloat { пикселей * сотня / 100 }

    /// color-mix(in srgb, var(--vc) 26%, var(--mk-line)) — у линии своя тема.
    private var рамка: UIColor {
        let база = Theme.hex(краска)
        return UIColor { признаки in
            let линия = признаки.userInterfaceStyle == .dark ? Theme.hex(0xFFFFFF, 0.10) : Theme.hex(0xE3ECE7)
            return Theme.смесь(база, линия, 0.26)
        }
    }

    /// «150 000 – 250 000 ₸», «от 200 000 ₸», «до 300 000 ₸»; не указана — nil.
    private var зарплата: String? {
        let от = вакансия.зарплатаОт, до = вакансия.зарплатаДо
        if от > 0 && до > от {
            return DesignText.число(от) + " – " + DesignText.число(до) + "\u{00A0}₸"
        }
        if от > 0 { return String(format: DesignText.т("sal_from"), DesignText.число(от) + "\u{00A0}₸") }
        if до > 0 { return String(format: DesignText.т("sal_to"), DesignText.число(до) + "\u{00A0}₸") }
        return nil
    }

    /// «Астана · Полная занятость».
    private var подпись: String {
        let занятость = ["full", "part", "shift", "remote", "internship"].contains(вакансия.занятость)
            ? DesignText.т("emp_" + вакансия.занятость) : ""
        return [вакансия.город, занятость].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Баннер «Продавай на Kliko.kz» (.mk-banner)

/// Зелёный баннер под главной (и в конце ленты): «Продавай на Kliko.kz», строка выгод и белая кнопка «Разместить
/// объявление →». В тёмной теме — мятная подложка с рамкой и кнопкой акцента, как [data-theme=dark] .mk-banner.
struct БаннерПродажСайта: View {
    let разместить: () -> Void
    @Environment(\.colorScheme) private var схема

    init(разместить: @escaping () -> Void) {
        self.разместить = разместить
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DesignText.т("sell_h"))
                    .font(.system(.title3, weight: .heavy))
                    .foregroundStyle(тёмная ? Theme.текст : Color.white)
                    .accessibilityAddTraits(.isHeader)
                Text(DesignText.т(ПаузаГаранта.наПаузеСейчас ? "sell_p_np" : "sell_p"))
                    .font(.footnote)
                    .foregroundStyle(тёмная ? Theme.текстВторой : Color.white.opacity(0.78))
            }
            HStack {
                Spacer(minLength: 0)
                Button(action: разместить) {
                    Text(DesignText.т("sell_b"))
                        .font(.system(.subheadline, weight: .heavy))
                        .foregroundStyle(тёмная ? Color(uiColor: Theme.hex(0x08130D)) : Theme.зелёный)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(тёмная ? Theme.акцент : Color.white,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеСайта())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(фон)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            if тёмная {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
    }

    private var тёмная: Bool { схема == .dark }

    @ViewBuilder
    private var фон: some View {
        if тёмная {
            ZStack {
                Theme.поверхность2
                LinearGradient(colors: [Theme.зелёный2.opacity(0.2), Theme.зелёный2.opacity(0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        } else {
            LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

// MARK: - «Вы смотрели» ленты (#mk-viewed)

/**
 «Вы смотрели» как у ленты сайта (mkRenderViewed): только во всей ленте без поиска и раздела, из просмотренных — те, что
 есть среди загруженных объявлений, не меньше двух и до двенадцати; карточки 132 pt (фото 1:1, название в две строки,
 цена — полной суммой, у услуг цены нет, без цены — «Договорная»), справа «Очистить» пилюлей с корзиной.
 */
struct ПолосаНедавнихСайта: View {
    let товары: [Listing]
    let очистить: () -> Void
    /// Карточка со ссылкой — её ставит лента: в стек, в правую колонку iPad или страницей сайта.
    let карточка: (Listing) -> AnyView

    init(товары: [Listing], очистить: @escaping () -> Void, карточка: @escaping (Listing) -> AnyView) {
        self.товары = товары
        self.очистить = очистить
        self.карточка = карточка
    }

    static let ширина: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(RecentText.т("viewed"))
                    .font(.system(.subheadline, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: очистить) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                        Text(RecentText.т("clear"))
                            .font(.system(.caption, weight: .semibold))
                    }
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(Theme.линия, lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RecentText.т("clear_viewed"))
            }
            .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(товары) { товар in
                        карточка(товар)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .padding(.top, 4)
    }
}

/// Карточка «Вы смотрели» (.mk-simc): рамка линии, скругление 14, фото 1:1, название 12 pt в две строки, цена 13/800.
struct КарточкаНедавнегоСайта: View {
    let товар: Listing

    init(товар: Listing) {
        self.товар = товар
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.поверхность2
                .frame(width: ПолосаНедавнихСайта.ширина, height: ПолосаНедавнихСайта.ширина)
                .overlay {
                    КартинкаЛенты(товар.обложка, пунктов: ПолосаНедавнихСайта.ширина) {
                        Color.clear
                    }
                }
                .clipped()
            Text(товар.title)
                .font(.caption)
                .foregroundStyle(Theme.текст)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.top, 8)
            /* У услуг цены нет — строка всё равно держит своё место: карточки полосы одной высоты. */
            Text(цена ?? " ")
                .font(.system(.footnote, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .frame(width: ПолосаНедавнихСайта.ширина, alignment: .leading)
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос)
    }

    /// _simCard: у услуг цены нет; цена больше нуля — полной суммой (mkMoney), иначе «Договорная».
    private var цена: String? {
        if товар.услуга { return nil }
        if let сумма = товар.price, сумма > 0 { return ЦенаКарточкиСайта.полная(сумма) }
        return ListingPageText.т("negotiable")
    }
}

// MARK: - Подгрузка (mkLoadBar)

/**
 Плашка подгрузки ленты как mkLoadBar сайта: появляется через 0,6 с после начала загрузки, над нижней панелью — кольцо,
 «Загружаем объявления» (первая страница) или «Подгружаем ещё объявления», полоса снизу; через 3 с — «Сеть медленная —
 пожалуйста, подождите». Ответ пришёл — плашка уходит.
 */
struct ПлашкаЗагрузкиЛенты: View {
    let ещё: Bool
    let медленно: Bool
    @State private var доля: CGFloat = 0.08

    init(ещё: Bool, медленно: Bool) {
        self.ещё = ещё
        self.медленно = медленно
    }

    var body: some View {
        HStack(spacing: 10) {
            SiteSpinner(размер: 16, толщина: 2, верх: Theme.зелёный2)
            Text(DesignText.т(медленно ? "fl_slow" : (ещё ? "fl_more" : "fl_loading")))
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: 340)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            GeometryReader { место in
                Theme.зелёный2
                    .frame(width: место.size.width * доля, height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: Color(red: 15 / 255, green: 40 / 255, blue: 25 / 255).opacity(0.25), radius: 14, x: 0, y: 10)
        .onAppear {
            withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 3))) { доля = 0.45 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Пустая выдача (#mk-empty)

/// «Ничего не нашлось» как у сайта: лупа, заголовок, «запрос», «Попробуйте другой запрос или сбросьте фильтры»,
/// зелёная «Сохранить поиск», рядом контурная «Ищу это — спросить продавцов» (.mk-empty-post, mkAskSellers) и
/// «Сбросить всё».
struct ПустаяВыдачаСайта: View {
    let запрос: String
    /// «Сохранить поиск»; nil — кнопки нет (рубильник сохранённых поисков выключен или сохранять нечего).
    let сохранить: (() -> Void)?
    let сохранён: Bool
    let сбросить: () -> Void
    /// «Ищу это — спросить продавцов»; nil — кнопки нет.
    let спросить: (() -> Void)?

    init(запрос: String, сохранить: (() -> Void)?, сохранён: Bool, сбросить: @escaping () -> Void,
         спросить: (() -> Void)? = nil) {
        self.запрос = запрос
        self.сохранить = сохранить
        self.сохранён = сохранён
        self.сбросить = сбросить
        self.спросить = спросить
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Theme.текстВторой.opacity(0.5))
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(FeedText.т("empty"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.текст)
                .padding(.bottom, 6)
            if !запрос.isEmpty {
                Text("«" + запрос + "»")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
            Text(DesignText.т("empty_sub"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
            if сохранить != nil || спросить != nil {
                /* .mk-empty-acts: кнопки в ряд по центру, не влезают — друг под другом. */
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { кнопкиДействий }
                    VStack(spacing: 10) { кнопкиДействий }
                }
                .padding(.bottom, 12)
            }
            Button(action: сбросить) {
                Text(FilterText.т("reset_all"))
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 52)
    }

    @ViewBuilder
    private var кнопкиДействий: some View {
        if let сохранить {
            Button(action: сохранить) {
                Label(SavedSearchText.т(сохранён ? "saved" : "save"), systemImage: сохранён ? "bell.fill" : "bell")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеСайта())
        }
        if let спросить {
            /* .mk-empty-post: без заливки, текст --mk-green2, рамка 1,5 px цвета линии. */
            Button(action: спросить) {
                Label(ListingLocationText.т("empty_post"), systemImage: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеСайта())
        }
    }
}
