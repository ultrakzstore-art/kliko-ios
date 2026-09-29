import SwiftUI

/**
 ВИТРИНА ПОД ВЕРТИКАЛИ (владелец 29.09.2026: «витрина под вертикали — чтобы у каждой своя была; сейчас все одинаково;
 нужна уникальная, удобная витрина»).

 Макет владельца «Витрина Kliko» (design/vitrina-preview.html, Card.dc.html): карточка — кадр 4:3, цена, название в две
 строки, строка фактов «из фасетов категории» и знак доверия своей вертикали внизу («Проверен по VIN» у авто, «Кадастр»
 у жилья, «Мастер верифицирован» у услуг, «Гарант» у товаров); широкая карточка — фото слева, факты и продавец справа.
 Здесь — что у каждой вертикали своё:
   · факты — чипы со значком SF Symbols: значок берётся по SVG-значку, который сервер кладёт в specs (emoji, ICO_* из
     inc/categories.php), поэтому он верен на любом языке подписи; у жилья — из realty, у услуг — оценка и режим;
   · к фактам — заявления продавца своей вертикали (trust: «Не битый», «Привит», «Оригинал», «Чек»…) и доставка у
     товаров;
   · жильё — заголовок «3-комн. · 75 м² · 5/9 эт.» и район вместо названия, цена за м² у продажи;
   · техника — фото целиком на светлом (предмет не обрезается), услуги — «от N ₸» и аватар мастера на фото,
     животные без цены — «Даром», запчасти — «для Toyota Camry».
 Смешанная лента — сетка равных карточек: фото той же доли, строк текста столько же, чипы — в одну строку (что не
 влезло, не рисуется). Лента одного корня — по выбору списком: широкая карточка с фактами в две строки (как у Kolesa
 и Krisha); выбор помнится для каждого корня, по умолчанию списком — транспорт и жильё.
 */

// MARK: - Вертикаль

/// Вертикаль карточки — по корню раздела (13 корней сайта, inc/categories_data.php), у транспорта — по подразделу.
enum ВертикальВитрины: Hashable {
    case авто, транспорт, запчасти, жильё, техника, одежда, дом, детское, спорт, хобби, красота, еда, животные, услуги,
         работа, прочее

    init(_ т: Listing) {
        switch т.корень {
        case "transport":
            if РазделыСайта.внутри(т.категория, ["auto-parts"]) {
                self = .запчасти
            } else if РазделыСайта.внутри(т.категория, ["cars"]) {
                self = .авто
            } else {
                self = .транспорт
            }
        case "realty": self = .жильё
        case "electronics": self = .техника
        case "clothing": self = .одежда
        case "home-garden": self = .дом
        case "kids": self = .детское
        case "sport": self = .спорт
        case "hobby": self = .хобби
        case "beauty": self = .красота
        case "food-farm": self = .еда
        case "animals": self = .животные
        case "services": self = .услуги
        case "jobs": self = .работа
        default: self = т.жильё["kind"] != nil ? .жильё : .прочее
        }
    }

    /// Фото целиком, без обрезки: техника — предмет на светлом, услуги — баннер с надписями по краям.
    var фотоЦеликом: Bool { self == .техника || self == .услуги }

    /// Доставка бывает (mkIsDeliverable сайта): у всего, кроме жилья, транспорта, услуг и вакансий.
    var сДоставкой: Bool {
        switch self {
        case .авто, .транспорт, .запчасти, .жильё, .услуги, .работа: return false
        default: return true
        }
    }

    /// Заявления продавца (trust), которые у этой вертикали — факт карточки, в порядке важности.
    var заявленияФактов: [String] {
        switch self {
        case .авто, .транспорт: return ["not_crashed", "vin_clean", "one_owner", "service_book", "docs_ok"]
        case .запчасти: return ["original", "working"]
        case .жильё: return ["docs_ok", "no_liens", "lawyer_checked"]
        case .техника: return ["receipt", "complete", "working"]
        case .животные: return ["vet_passport", "pedigree", "vet_checked", "sterilized", "trained"]
        case .услуги: return ["licensed", "portfolio", "contract"]
        case .работа: return []
        default: return ["original", "tags", "no_defects", "receipt", "safety_cert"]
        }
    }
}

// MARK: - Сетка или список

/// Как лента раскладывает карточки: сеткой равных или списком широких.
enum РасстановкаВитрины: Hashable {
    case сетка, список

    /// Корни, у которых в ленте есть выбор «сетка / список» (у «Работы» — своя карточка вакансии).
    static let корниСВыбором: Set<String> = ["transport", "realty", "electronics", "clothing", "home-garden", "kids",
                                             "sport", "animals", "beauty", "hobby", "food-farm", "services"]

    /// Без выбора человека: транспорт и жильё — списком (как у Kolesa и Krisha), прочее — сеткой.
    static func поУмолчанию(_ корень: String) -> РасстановкаВитрины {
        корень == "transport" || корень == "realty" ? .список : .сетка
    }

    /// Выбор для корня из записи «transport:1,realty:0»; корень без выбора (смешанная лента) — сетка.
    static func выбор(корень: String, запись: String) -> РасстановкаВитрины {
        guard корниСВыбором.contains(корень) else { return .сетка }
        for пара in запись.split(separator: ",") {
            let части = пара.split(separator: ":")
            if части.count == 2 && String(части[0]) == корень { return части[1] == "1" ? .список : .сетка }
        }
        return поУмолчанию(корень)
    }

    /// Запись с новым выбором для корня.
    static func записать(_ расстановка: РасстановкаВитрины, корень: String, в запись: String) -> String {
        var пары = запись.split(separator: ",").map(String.init).filter { !$0.hasPrefix(корень + ":") }
        пары.append(корень + ":" + (расстановка == .список ? "1" : "0"))
        return пары.joined(separator: ",")
    }
}

private struct КлючРасстановкиВитрины: EnvironmentKey {
    static let defaultValue: РасстановкаВитрины = .сетка
}

extension EnvironmentValues {
    /// Лента одного корня списком — ListingCard рисует широкую карточку.
    var расстановкаВитрины: РасстановкаВитрины {
        get { self[КлючРасстановкиВитрины.self] }
        set { self[КлючРасстановкиВитрины.self] = newValue }
    }
}

// MARK: - Факты

/// Факт карточки: значок SF Symbols и короткий текст.
struct ФактВитрины: Hashable {
    let значок: String
    let текст: String
    /// Заявление продавца или проверка — значок зелёным.
    var подтверждён: Bool = false
}

extension Listing {
    var вертикаль: ВертикальВитрины { ВертикальВитрины(self) }

    /// Значок SF Symbols по SVG-значку характеристики сайта (emoji у specs): по кусочку пути, который есть только у него.
    static func значокХарактеристики(_ svg: String) -> String? {
        for (след, значок) in следыЗначков where svg.contains(след) { return значок }
        return nil
    }

    /// Кусочек SVG → значок. ICO_* и значки CAT_ATTR сайта (inc/categories.php).
    private static let следыЗначков: [(String, String)] = [
        ("M3 9h18M8 3v3M16 3v3", "calendar"),                       // год
        ("M6 21L9 3M18 21L15 3", "gauge.with.dots.needle.33percent"), // пробег авто
        ("M4 19a8 8 0 1 1 16 0", "gauge.with.dots.needle.33percent"), // пробег прочего транспорта
        ("M19.4 13a7.6", "engine.combustion"),                      // двигатель, л
        ("M6 9h3l2-2h4v2h3", "engine.combustion"),                  // двигатель, мощность
        ("M15 5a4 4 0 0 0-5 5L3 17", "gearshift.layout.sixspeed"),  // коробка
        ("M14 7l3 3v6", "fuelpump"),                                // топливо
        ("M4 4v16h16z", "square.dashed"),                           // площадь
        ("M5 21V4a1 1 0 0 1 1-1h9", "door.left.hand.closed"),       // комнат
        ("M9 7h2M13 7h2", "building.2"),                            // этаж
        ("M12 22v-5", "tree"),                                      // участок
        ("rect x=\"7.5\" y=\"3\"", "square.3.layers.3d"),           // материал одежды
        ("M12 3l9 5-9 5-9-5 9-5z", "square.3.layers.3d"),           // материал
        ("M12 3a9 9 0 1 0 0 18", "paintpalette"),                   // цвет
        ("M3 8l5-5 13 13-5 5z", "ruler"),                           // размер
        ("M5.5 21a6.5 6.5 0 0 1 13 0", "birthday.cake"),            // возраст
        ("r=\"4.5\"", "figure.and.child.holdinghands"),             // пол
        ("cx=\"7\" cy=\"10\" r=\"1.4\"", "pawprint"),               // вид животного
        ("M14.5 6.2a3.6", "wrench.and.screwdriver"),                // деталь
        ("M5 17h14M4 17v-4l2-5h12", "car"),                         // модель (совместимость)
        ("M20.5 12.5l-8 8L3 11V4h7z", "tag"),                       // тип, порода
        ("M7.5 9h9l1.4 10", "scalemass"),                           // вес
        ("M12 3s5.5 6 5.5 9.5", "drop")                             // объём
    ]

    /// Значение «пусто» как у сайта (spec_is_blank): «0», «—», «не указано»…
    private static func пустойФакт(_ з: String) -> Bool {
        з.isEmpty || з.range(of: "^0+([.,]0+)?$", options: .regularExpression) != nil
            || ["-", "—", "–", "n/a", "na", "null", "undefined", "нет", "нет данных", "не указано", "не задано"]
                .contains(з.lowercased())
    }

    /// Факты карточки вертикали по порядку важности. В сетке видно, сколько влезет в строку, в списке — до двух строк.
    func фактыВитрины(список: Bool) -> [ФактВитрины] {
        let в = вертикаль
        var итог: [ФактВитрины] = []
        switch в {
        case .жильё:
            итог = фактыЖилья(список: список)
        case .услуги:
            итог = фактыУслуги
        case .работа:
            return []
        default:
            итог = фактыХарактеристик(в, образцы: список)
            if итог.isEmpty { итог = фактыПлоских(в) }
        }
        /* Запчасти: марка машины к совместимости — «для Toyota Camry». */
        if в == .запчасти, let марка, !марка.isEmpty {
            if let номер = итог.firstIndex(where: { $0.значок == "car" }) {
                let модель = итог[номер].текст
                let полное = модель.localizedCaseInsensitiveContains(марка) ? модель : марка + " " + модель
                итог[номер] = ФактВитрины(значок: "car", текст: String(format: ВитринаВертикалейТекст.т("fits"), полное))
            } else {
                итог.insert(ФактВитрины(значок: "car", текст: String(format: ВитринаВертикалейТекст.т("fits"), марка)),
                            at: min(1, итог.count))
            }
        }
        /* Гарантия у техники и товаров — если знак внизу уже не она. */
        if в != .жильё && в != .услуги && !гарантияВыключена, let дни = гарантияДней, дни > 0 {
            let срок = Listing.срокГарантии(дни)
            if знакДоверияЛенты?.текст != String(format: DesignText.т("t_warranty"), срок) {
                итог.append(ФактВитрины(значок: "checkmark.shield", текст: срок, подтверждён: true))
            }
        }
        /* Заявления продавца своей вертикали. */
        for ключ in в.заявленияФактов where заявления.contains(ключ) {
            итог.append(ФактВитрины(значок: "checkmark.seal", текст: ВитринаВертикалейТекст.т("c_" + ключ),
                                    подтверждён: true))
        }
        /* Доставка у товаров. */
        if в.сДоставкой {
            if доставкаБесплатно {
                итог.append(ФактВитрины(значок: "shippingbox", текст: ListingPageText.т("ship_free")))
            } else if let дни = доставкаДней {
                итог.append(ФактВитрины(значок: "shippingbox",
                                        текст: String(format: ВитринаВертикалейТекст.т("ship_days"), дни)))
            }
        }
        return Array(итог.prefix(список ? 8 : 5))
    }

    /// Факты из specs сервера (набор раздела: CAT_ATTR, e_specs) — значок по SVG, значение как в строке ленты.
    private func фактыХарактеристик(_ в: ВертикальВитрины, образцы: Bool) -> [ФактВитрины] {
        var итог: [ФактВитрины] = []
        for пункт in характеристикиКарточки {
            if пункт.образец && !образцы { continue }
            let сырое = пункт.значение.trimmingCharacters(in: .whitespaces)
            if Self.пустойФакт(сырое) { continue }
            let база = в == .техника ? Self.объёмПамяти(сырое) : сырое
            let текст = Self.значениеСтрокиЛенты(пункт.ключ, база)
            итог.append(ФактВитрины(значок: Self.значокВертикали(пункт.значок, в), текст: текст))
        }
        return итог
    }

    /// Значок факта с поправкой на вертикаль: у техники «объём» — память, «мощность» — молния.
    private static func значокВертикали(_ значок: String?, _ в: ВертикальВитрины) -> String {
        guard let значок else { return в == .техника ? "cpu" : "tag" }
        if в == .техника && значок == "drop" { return "memorychip" }
        if в == .техника && значок == "engine.combustion" { return "bolt" }
        return значок
    }

    /// Нет specs — плоские поля, как у сайта: у машин год, пробег, объём, коробка; у техники — процессор, память, диск.
    private func фактыПлоских(_ в: ВертикальВитрины) -> [ФактВитрины] {
        func чисто(_ s: String?) -> String {
            let з = (s ?? "").trimmingCharacters(in: .whitespaces)
            return Self.пустойФакт(з) ? "" : з
        }
        var итог: [ФактВитрины] = []
        switch в {
        case .авто, .транспорт:
            let год = чисто(годСтрокой)
            if !год.isEmpty { итог.append(ФактВитрины(значок: "calendar", текст: год)) }
            if let пробег = Int(String(чисто(ramСтрокой).filter { $0.isASCII && $0.isNumber }).prefix(9)), пробег > 0 {
                итог.append(ФактВитрины(значок: "gauge.with.dots.needle.33percent",
                                        текст: DesignText.число(пробег) + " " + DesignText.т("km")))
            }
            var объём = чисто(storageСтрокой)
            if let запятая = объём.range(of: ",") { объём.replaceSubrange(запятая, with: ".") }
            if объём.range(of: "^\\d{1,2}(\\.\\d)?$", options: .regularExpression) != nil, (Double(объём) ?? 0) > 0 {
                итог.append(ФактВитрины(значок: "engine.combustion", текст: объём + " " + DesignText.т("l")))
            }
            let коробка = чисто(cpuСтрокой)
            if в == .авто && !коробка.isEmpty && коробка.count < 14 {
                итог.append(ФактВитрины(значок: "gearshift.layout.sixspeed",
                                        текст: Self.значениеСтрокиЛенты("", коробка)))
            }
        case .техника:
            let ram = чисто(ramСтрокой)
            let голыеЦифры = !ram.isEmpty && ram.allSatisfy { $0.isASCII && $0.isNumber }
            let память: String = голыеЦифры ? ram + " " + DesignText.т("gb_ram") : Self.объёмПамяти(ram)
            let поля: [(String, String)] = [
                ("memorychip", память),
                ("internaldrive", Self.объёмПамяти(чисто(storageСтрокой))),
                ("cpu", чисто(cpuСтрокой)),
                ("display", чисто(gpuСтрокой))
            ]
            for (значок, текст) in поля where !текст.isEmpty {
                итог.append(ФактВитрины(значок: значок, текст: текст))
            }
        default:
            break
        }
        return итог
    }

    /// Слово справочника жилья (r_*) на языке приложения; нет в справочнике — как пришло.
    private static func словоЖилья(_ значение: String) -> String {
        let ключ = "r_" + значение
        let слово = DesignText.т(ключ)
        return слово == ключ ? значение : слово
    }

    /// Факты жилья: ремонт, дом, год постройки, санузел, срок аренды, ипотека, мебель, парковка…
    private func фактыЖилья(список: Bool) -> [ФактВитрины] {
        var итог: [ФактВитрины] = []
        let поля: [(String, String)] = [("renovation", "paintbrush.pointed"), ("building", "building.2"),
                                        ("term", "calendar.badge.clock"), ("year_built", "calendar"),
                                        ("bathroom", "shower"), ("land_use", "tree"), ("owner", "person")]
        for (ключ, значок) in поля {
            guard let значение = жильё[ключ], !Self.пустойФакт(значение) else { continue }
            if ключ == "owner" && !список { continue }
            итог.append(ФактВитрины(значок: значок, текст: Self.словоЖилья(значение)))
        }
        let признаки: [(String, String)] = [("mortgage_ok", "banknote"), ("furniture", "sofa"), ("parking", "parkingsign"),
                                            ("utilities", "bolt"), ("kids", "figure.and.child.holdinghands"),
                                            ("pets", "pawprint")]
        for (ключ, значок) in признаки where жильё[ключ] == "1" {
            итог.append(ФактВитрины(значок: значок, текст: DesignText.т("rl_" + ключ)))
        }
        /* В списке заголовок уже несёт комнаты, площадь и этаж; в сетке — тоже. Нет заголовка — площадь фактом. */
        if заголовокЖилья == nil, let площадь = Self.числоВНачале(жильё["area"] ?? ""), площадь > 0 {
            итог.insert(ФактВитрины(значок: "square.dashed", текст: Self.дробь(площадь) + " " + DesignText.т("m2")), at: 0)
        }
        return итог
    }

    /// Факты услуги: оценка с отзывами, режим работы, сделки.
    private var фактыУслуги: [ФактВитрины] {
        var итог: [ФактВитрины] = []
        if let оценка = оценкаУслугиГлавной {
            итог.append(ФактВитрины(значок: "star.fill", текст: оценка.оценка + " · " + оценка.отзывы))
        }
        if let часы = текстЧасов { итог.append(ФактВитрины(значок: "clock", текст: часы)) }
        if let сделки = сделкиПродавца, сделки > 0 {
            итог.append(ФактВитрины(значок: "hand.thumbsup", текст: ListingPageText.число(сделки, "deals")))
        }
        return итог
    }

    /// «3-комн. · 75 м² · 5/9 эт.» — заголовок карточки жилья (как у Krisha); у дома — площадь, участок и этажность.
    /// Нечего сказать — nil, и карточка показывает название.
    var заголовокЖилья: String? {
        guard вертикаль == .жильё else { return nil }
        var части: [String] = []
        let комнаты = жильё["rooms"] ?? ""
        if !комнаты.isEmpty && комнаты.allSatisfy({ $0.isASCII && $0.isNumber }) {
            части.append(String(format: DesignText.т("rooms"), комнаты))
        } else if комнаты == "studio" {
            части.append(DesignText.т("studio"))
        }
        if let площадь = Self.числоВНачале(жильё["area"] ?? ""), площадь > 0 {
            части.append(Self.дробь(площадь) + " " + DesignText.т("m2"))
        }
        if let участок = Self.числоВНачале(жильё["land_area"] ?? ""), участок > 0 {
            части.append(Self.дробь(участок) + " " + DesignText.т("sot"))
        }
        let этаж = Int(Self.числоВНачале(жильё["floor"] ?? "") ?? 0)
        let этажей = Int(Self.числоВНачале(жильё["floors"] ?? "") ?? 0)
        if этаж > 0 {
            части.append((этажей > 0 ? "\(этаж)/\(этажей)" : String(этаж)) + " " + DesignText.т("fl"))
        } else if этажей > 0 {
            части.append(String(этажей) + " " + DesignText.т("fl"))
        }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    /// Вторая строка карточки жилья: район (без «(…)»), нет его — название объявления.
    var адресЖилья: String {
        if let район = районНазвание, !район.contains("(") { return район }
        return title
    }

    /// «450 000 ₸/м²» — у продажи жилья с площадью.
    var ценаЗаМетр: String? {
        guard вертикаль == .жильё, !forRent, let цена = price, цена > 0,
              let площадь = Self.числоВНачале(жильё["area"] ?? ""), площадь >= 1 else { return nil }
        return ЦенаКарточкиСайта.сумма(цена / площадь) + "/" + DesignText.т("m2")
    }

    /// Животное без цены и без «договорной» — «Даром».
    var даром: Bool {
        вертикаль == .животные && !forRent && !negotiable && (price ?? 0) <= 0 && (rentPriceDay ?? 0) <= 0
    }
}

// MARK: - Чипы

/// Чип факта: значок и короткий текст вторичным цветом на мягкой подложке.
struct ЧипФактаВитрины: View {
    let факт: ФактВитрины
    let кегль: CGFloat

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: факт.значок)
                .font(.system(size: кегль * 0.85, weight: .semibold))
                .foregroundStyle(факт.подтверждён ? Theme.зелёный2 : Theme.текстВторой)
            Text(факт.текст)
                .font(.system(size: кегль, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Чипы в одну строку: сколько влезло целиком — столько и видно (первый ужимается многоточием), остальные за краем.
struct РядФактовВитрины: Layout {
    var зазор: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let размеры = subviews.map { $0.sizeThatFits(.unspecified) }
        let высота = размеры.map(\.height).max() ?? 0
        if let ширина = proposal.width, ширина.isFinite { return CGSize(width: ширина, height: высота) }
        let всего = размеры.map(\.width).reduce(0, +) + зазор * CGFloat(max(0, размеры.count - 1))
        return CGSize(width: всего, height: высота)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var влезает = true
        for (номер, вид) in subviews.enumerated() {
            let размер = вид.sizeThatFits(.unspecified)
            let остаток = bounds.maxX - x
            if влезает && (размер.width <= остаток || номер == 0) {
                let ширина = max(0, min(размер.width, остаток))
                вид.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: ширина, height: размер.height))
                x += ширина + зазор
            } else {
                влезает = false
                вид.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(размер))
            }
        }
    }
}

/// Чипы в несколько строк (широкая карточка списка): не больше `строк`, что не влезло — за краем.
struct ПотокФактовВитрины: Layout {
    var зазор: CGFloat = 5
    var строк: Int = 2

    private func места(_ ширина: CGFloat, _ subviews: Subviews) -> (точки: [CGPoint?], высота: CGFloat) {
        var точки: [CGPoint?] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var строка = 0
        var высотаСтроки: CGFloat = 0
        var хватит = false
        for вид in subviews {
            if хватит {
                точки.append(nil)
                continue
            }
            let размер = вид.sizeThatFits(.unspecified)
            let w = min(размер.width, ширина)
            if x > 0 && x + w > ширина {
                строка += 1
                if строка >= строк {
                    хватит = true
                    точки.append(nil)
                    continue
                }
                x = 0
                y += высотаСтроки + зазор
                высотаСтроки = 0
            }
            точки.append(CGPoint(x: x, y: y))
            x += w + зазор
            высотаСтроки = max(высотаСтроки, размер.height)
        }
        return (точки, y + высотаСтроки)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var ширина = proposal.width ?? 320
        if !ширина.isFinite { ширина = 320 }
        return CGSize(width: ширина, height: места(ширина, subviews).высота)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let расклад = места(bounds.width, subviews)
        for (номер, вид) in subviews.enumerated() {
            let размер = вид.sizeThatFits(.unspecified)
            if номер < расклад.точки.count, let точка = расклад.точки[номер] {
                вид.place(at: CGPoint(x: bounds.minX + точка.x, y: bounds.minY + точка.y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: min(размер.width, bounds.width), height: размер.height))
            } else {
                вид.place(at: CGPoint(x: bounds.maxX + 10_000, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(размер))
            }
        }
    }
}

/// Строка чипов карточки сетки: высота — ровно один чип и у пустой, чтобы карточки сетки были одной высоты.
struct СтрокаФактовВитрины: View {
    let факты: [ФактВитрины]
    let кегль: CGFloat

    var body: some View {
        ЧипФактаВитрины(факт: ФактВитрины(значок: "tag", текст: " "), кегль: кегль)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                РядФактовВитрины {
                    ForEach(Array(факты.enumerated()), id: \.offset) { _, факт in
                        ЧипФактаВитрины(факт: факт, кегль: кегль)
                    }
                }
                .clipped()
            }
            .accessibilityHidden(true)
    }
}

/// Чипы широкой карточки — в две строки (при крупном тексте — в три).
struct ПотокЧиповВитрины: View {
    let факты: [ФактВитрины]
    let кегль: CGFloat
    let строк: Int

    var body: some View {
        ПотокФактовВитрины(строк: строк) {
            ForEach(Array(факты.enumerated()), id: \.offset) { _, факт in
                ЧипФактаВитрины(факт: факт, кегль: кегль)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: - Переключатель «сетка / список»

/// Два значка у заголовка выдачи раздела: сеткой или списком. Выбранный — на зелёной подложке.
struct ПереключательРасстановки: View {
    let выбрано: РасстановкаВитрины
    let выбрать: (РасстановкаВитрины) -> Void

    var body: some View {
        HStack(spacing: 2) {
            кнопка(.сетка, значок: "square.grid.2x2", подпись: ВитринаВертикалейТекст.т("grid"))
            кнопка(.список, значок: "rectangle.grid.1x2", подпись: ВитринаВертикалейТекст.т("list"))
        }
        .padding(2)
        .background(Theme.поверхность2, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.линия, lineWidth: 1))
        .fixedSize()
    }

    private func кнопка(_ вид: РасстановкаВитрины, значок: String, подпись: String) -> some View {
        let выбран = выбрано == вид
        return Button {
            if !выбран { выбрать(вид) }
        } label: {
            Image(systemName: значок)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                .frame(width: 34, height: 28)
                .background(выбран ? Theme.зелёный2 : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Тексты

/// Тексты витрины вертикалей на языке приложения (ru, kk, en, ar).
enum ВитринаВертикалейТекст {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[DesignText.язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "free": "Даром", "fits": "для %@", "ship_days": "Доставка %@ дн.", "grid": "Сеткой", "list": "Списком",
            "c_not_crashed": "Не битый", "c_vin_clean": "VIN чистый", "c_one_owner": "Один владелец",
            "c_service_book": "Сервисная книжка", "c_docs_ok": "Документы в порядке", "c_original": "Оригинал",
            "c_working": "Проверено", "c_no_liens": "Без обременений", "c_lawyer_checked": "Проверено юристом",
            "c_receipt": "Есть чек", "c_complete": "Полный комплект", "c_vet_passport": "Привит, ветпаспорт",
            "c_pedigree": "Родословная", "c_vet_checked": "Осмотрен ветеринаром", "c_sterilized": "Стерилизован",
            "c_trained": "Приучен", "c_licensed": "Лицензия", "c_portfolio": "Портфолио", "c_contract": "Договор",
            "c_tags": "С бирками", "c_no_defects": "Без дефектов", "c_safety_cert": "Сертификат"
        ],
        "kk": [
            "free": "Тегін", "fits": "%@ үшін", "ship_days": "Жеткізу %@ күн", "grid": "Тормен", "list": "Тізіммен",
            "c_not_crashed": "Соғылмаған", "c_vin_clean": "VIN таза", "c_one_owner": "Бір иесі",
            "c_service_book": "Сервистік кітапша", "c_docs_ok": "Құжаттары дұрыс", "c_original": "Түпнұсқа",
            "c_working": "Тексерілген", "c_no_liens": "Ауыртпалықсыз", "c_lawyer_checked": "Заңгер тексерген",
            "c_receipt": "Чегі бар", "c_complete": "Толық жиынтық", "c_vet_passport": "Екпесі, ветпаспорты бар",
            "c_pedigree": "Тегі бар", "c_vet_checked": "Ветеринар қараған", "c_sterilized": "Стерилизацияланған",
            "c_trained": "Үйретілген", "c_licensed": "Лицензия", "c_portfolio": "Портфолио", "c_contract": "Шарт",
            "c_tags": "Жапсырмасы бар", "c_no_defects": "Ақаусыз", "c_safety_cert": "Сертификат"
        ],
        "en": [
            "free": "Free", "fits": "for %@", "ship_days": "Delivery %@ d", "grid": "Grid", "list": "List",
            "c_not_crashed": "No accidents", "c_vin_clean": "Clean VIN", "c_one_owner": "One owner",
            "c_service_book": "Service book", "c_docs_ok": "Papers in order", "c_original": "Original",
            "c_working": "Tested", "c_no_liens": "No liens", "c_lawyer_checked": "Lawyer-checked",
            "c_receipt": "Receipt", "c_complete": "Complete set", "c_vet_passport": "Vaccinated, vet passport",
            "c_pedigree": "Pedigree", "c_vet_checked": "Vet-checked", "c_sterilized": "Neutered",
            "c_trained": "Trained", "c_licensed": "Licensed", "c_portfolio": "Portfolio", "c_contract": "Contract",
            "c_tags": "With tags", "c_no_defects": "No defects", "c_safety_cert": "Certified"
        ],
        "ar": [
            "free": "مجانًا", "fits": "لـ %@", "ship_days": "توصيل %@ يوم", "grid": "شبكة", "list": "قائمة",
            "c_not_crashed": "بلا حوادث", "c_vin_clean": "VIN نظيف", "c_one_owner": "مالك واحد",
            "c_service_book": "دفتر الصيانة", "c_docs_ok": "الوثائق سليمة", "c_original": "أصلي",
            "c_working": "مُختبَر", "c_no_liens": "بلا رهون", "c_lawyer_checked": "فحصه محامٍ",
            "c_receipt": "مع الفاتورة", "c_complete": "طقم كامل", "c_vet_passport": "مُطعَّم، جواز بيطري",
            "c_pedigree": "نسب موثّق", "c_vet_checked": "فحصه بيطري", "c_sterilized": "معقّم",
            "c_trained": "مُدرَّب", "c_licensed": "مرخّص", "c_portfolio": "معرض أعمال", "c_contract": "عقد",
            "c_tags": "مع الملصقات", "c_no_defects": "بلا عيوب", "c_safety_cert": "شهادة"
        ]
    ]
}
