import Foundation

/**
 «МОЁ» — «МОЙ ДОМ»: МОДЕЛЬ (владелец 16.10.2026: «мой дом — что можно по дому?»; «стандарты: по ним изи точечно
 подбирать»; docs/STANDARDS.md §8.2, docs/SERVER_CIRCLE.md §11).

 Что знает «Мой дом» — всё по стандартам, чтобы сверять объявления без анкет:
   · комнаты — вид, своё название, Ш×Д×В в сантиметрах (шаблоны «спальня 3×4» — примерно), фото, палитра цветов;
   · проёмы — входная и межкомнатные двери (проход в свету), лифт (шаблон EN 81-70, «советский — замерьте» или свой
     замер), лестница; этаж и «лифта нет» — «Пройдёт ли в дверь и лифт?» у мебели и техники;
   · кровати — спальное место («160x200»), матрас (высота, вид), одеяло, подушки — матрас, бельё, простыня на резинке;
   · окна — Ш×В, см — жалюзи и рулонные шторы ±1 см, шторы по потолку;
   · ТВ на стене — диагональ, VESA (или «обычно» по диагонали — примерно), вес — кронштейны;
   · лампы — цоколь счётчиком («E27 ×6») по комнатам — лампы того же цоколя или с переходником;
   · техника — вид, бренд, модель, код расходника — фильтры, мешки, капсулы;
   · стиль и цвета дома — только порядок подборки, никогда не отсекают.
 У каждой вещи — комната (UUID) по желанию. Значения — каноном каталога (КаталогСтандартов), а не номером ряда. Чтение
 терпимое, ключи короткие ASCII (как вся ЗаписьМоего, MyThingsModel.swift); пределы — чтобы файл оставался маленьким.
 Хранится только на телефоне (МоёХранилище.обновитьДом), на сервер ничего не уходит.
 */

// MARK: - Комнаты

enum ВидКомнатыМоего: String, Codable, CaseIterable, Sendable {
    case спальня = "bedroom"
    case гостиная = "living"
    case кухня = "kitchen"
    case детская = "kids"
    case ванная = "bath"
    case прихожая = "hall"
    case кабинет = "office"
    case балкон = "balcony"
    case другая = "other"

    var значок: String {
        switch self {
        case .спальня: return "bed.double"
        case .гостиная: return "sofa"
        case .кухня: return "refrigerator"
        case .детская: return "teddybear"
        case .ванная: return "bathtub"
        case .прихожая: return "door.left.hand.closed"
        case .кабинет: return "desktopcomputer"
        case .балкон: return "sun.max"
        case .другая: return "square.split.bottomrightquarter"
        }
    }

    var название: String { МоёText.т("my_room_" + rawValue) }
}

/// Комната: вид, своё название, Ш×Д×В (см), фото, палитра.
struct КомнатаМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var вид: ВидКомнатыМоего
    /// Своё название («Спальня детей») — по желанию, до 30 знаков.
    var имя: String
    /// Ширина, длина, высота потолка — см.
    var ширина: Int?
    var длина: Int?
    var высота: Int?
    /// Размеры подставлены шаблоном — «примерно, замерьте».
    var примерно: Bool
    var фото: ФотоМоего?
    /// Цвета комнаты — с фото на телефоне или чипами; до пяти.
    var палитра: [ЦветСтандарта]
    var создана: Date

    static let пределИмени = 30
    static let пределыСм: ClosedRange<Int> = 50...3000
    static let пределыПотолка: ClosedRange<Int> = 200...600
    static let пределПалитры = 5

    enum CodingKeys: String, CodingKey {
        case id
        case вид = "kind"
        case имя = "name"
        case ширина = "w"
        case длина = "l"
        case высота = "h"
        case примерно = "approx"
        case фото = "photo"
        case палитра = "colors"
        case создана = "at"
    }

    init(id: UUID = UUID(), вид: ВидКомнатыМоего, имя: String = "", ширина: Int? = nil, длина: Int? = nil,
         высота: Int? = nil, примерно: Bool = false, фото: ФотоМоего? = nil, палитра: [ЦветСтандарта] = [],
         создана: Date = Date()) {
        self.id = id
        self.вид = вид
        self.имя = имя
        self.ширина = ширина
        self.длина = длина
        self.высота = высота
        self.примерно = примерно
        self.фото = фото
        self.палитра = палитра
        self.создана = создана
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        вид = к.значениеМоего(ВидКомнатыМоего.self, .вид) ?? .другая
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(Self.пределИмени))
        ширина = к.значениеМоего(Int.self, .ширина).flatMap { Self.пределыСм.contains($0) ? $0 : nil }
        длина = к.значениеМоего(Int.self, .длина).flatMap { Self.пределыСм.contains($0) ? $0 : nil }
        высота = к.значениеМоего(Int.self, .высота).flatMap { Self.пределыПотолка.contains($0) ? $0 : nil }
        примерно = к.значениеМоего(Bool.self, .примерно) ?? false
        фото = к.значениеМоего(ФотоМоего.self, .фото)
        палитра = ЦветСтандарта.из(к.значениеМоего([String].self, .палитра) ?? [], предел: Self.пределПалитры)
        создана = к.значениеМоего(Date.self, .создана) ?? Date()
    }

    /// Своё название, иначе вид («Спальня»).
    var заголовок: String {
        let своё = имя.trimmingCharacters(in: .whitespacesAndNewlines)
        return своё.isEmpty ? вид.название : своё
    }

    /// Площадь, м²; нет размеров — nil.
    var площадь: Double? {
        guard let ширина, let длина else { return nil }
        return Double(ширина * длина) / 10_000
    }

    /// Пределы и порядок после правки.
    mutating func нормализовать() {
        имя = String(имя.prefix(Self.пределИмени))
        if let ш = ширина, !Self.пределыСм.contains(ш) { ширина = nil }
        if let д = длина, !Self.пределыСм.contains(д) { длина = nil }
        if let в = высота, !Self.пределыПотолка.contains(в) { высота = nil }
        палитра = ЦветСтандарта.из(палитра.map(\.rawValue), предел: Self.пределПалитры)
    }
}

/// Шаблон комнаты: касание ставит вид и Ш×Д×В — «примерно, замерьте».
struct ШаблонКомнатыМоего: Identifiable, Hashable, Sendable {
    let id: String
    let вид: ВидКомнатыМоего
    let ширина: Int
    let длина: Int
    let высота: Int

    /// «Спальня 3×4 м».
    var подпись: String {
        вид.название + " " + ЧислоМоего.ч(Double(ширина) / 100) + "×" + ЧислоМоего.ч(Double(длина) / 100) + " "
            + МоёText.т("my_u_m")
    }

    func комната() -> КомнатаМоего {
        КомнатаМоего(вид: вид, ширина: ширина, длина: длина, высота: высота, примерно: true)
    }

    static let все: [ШаблонКомнатыМоего] = [
        ШаблонКомнатыМоего(id: "bed_3x4", вид: .спальня, ширина: 300, длина: 400, высота: 270),
        ШаблонКомнатыМоего(id: "bed_35x4", вид: .спальня, ширина: 350, длина: 400, высота: 270),
        ШаблонКомнатыМоего(id: "liv_4x5", вид: .гостиная, ширина: 400, длина: 500, высота: 270),
        ШаблонКомнатыМоего(id: "kit_3x3", вид: .кухня, ширина: 300, длина: 300, высота: 270),
        ШаблонКомнатыМоего(id: "kid_3x35", вид: .детская, ширина: 300, длина: 350, высота: 270),
        ШаблонКомнатыМоего(id: "bath_17x25", вид: .ванная, ширина: 170, длина: 250, высота: 260),
        ШаблонКомнатыМоего(id: "hall_15x3", вид: .прихожая, ширина: 150, длина: 300, высота: 270),
        ШаблонКомнатыМоего(id: "off_25x3", вид: .кабинет, ширина: 250, длина: 300, высота: 270)
    ]
}

// MARK: - Проёмы

enum ВидПроёмаМоего: String, Codable, CaseIterable, Sendable {
    case входная = "entry"
    case дверь = "door"
    case лифт = "lift"
    case лестница = "stairs"
    case балкон = "balcony"

    var значок: String {
        switch self {
        case .входная: return "door.left.hand.closed"
        case .дверь: return "door.left.hand.open"
        case .лифт: return "arrow.up.arrow.down.square"
        case .лестница: return "stairs"
        case .балкон: return "door.sliding.left.hand.open"
        }
    }

    var название: String { МоёText.т("my_open_" + rawValue) }
}

/**
 Проём: дверь — проход в свету (ширина) и высота, см; лифт — дверь (ширина × высота) и кабина Ш×Г; лестница — ширина
 марша. шаблон — ключ лифта каталога («en81_2», «soviet»); примерно — подставлено шаблоном, «замерьте».
 */
struct ПроёмМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var вид: ВидПроёмаМоего
    var имя: String
    /// Проход в свету (у лифта — дверь кабины), см.
    var ширина: Int?
    /// Высота прохода, см.
    var высота: Int?
    /// Лифт: кабина ширина и глубина, см.
    var кабинаШирина: Int?
    var кабинаГлубина: Int?
    var шаблон: String?
    var примерно: Bool

    static let пределыСм: ClosedRange<Int> = 30...400

    enum CodingKeys: String, CodingKey {
        case id
        case вид = "kind"
        case имя = "name"
        case ширина = "w"
        case высота = "h"
        case кабинаШирина = "cw"
        case кабинаГлубина = "cd"
        case шаблон = "tpl"
        case примерно = "approx"
    }

    init(id: UUID = UUID(), вид: ВидПроёмаМоего, имя: String = "", ширина: Int? = nil, высота: Int? = nil,
         кабинаШирина: Int? = nil, кабинаГлубина: Int? = nil, шаблон: String? = nil, примерно: Bool = false) {
        self.id = id
        self.вид = вид
        self.имя = имя
        self.ширина = ширина
        self.высота = высота
        self.кабинаШирина = кабинаШирина
        self.кабинаГлубина = кабинаГлубина
        self.шаблон = шаблон
        self.примерно = примерно
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        вид = try к.decode(ВидПроёмаМоего.self, forKey: .вид)
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(30))
        let см: (CodingKeys) -> Int? = { ключ in
            к.значениеМоего(Int.self, ключ).flatMap { Self.пределыСм.contains($0) ? $0 : nil }
        }
        ширина = см(.ширина)
        высота = см(.высота)
        кабинаШирина = см(.кабинаШирина)
        кабинаГлубина = см(.кабинаГлубина)
        шаблон = к.значениеМоего(String.self, .шаблон).map { String($0.prefix(20)) }
        примерно = к.значениеМоего(Bool.self, .примерно) ?? false
    }

    /// Лифт по шаблону каталога: дверь, высота двери, кабина — «примерно», если шаблон такой.
    static func лифт(_ шаблон: КаталогСтандартов.ЛифтСтандарта) -> ПроёмМоего {
        ПроёмМоего(вид: .лифт, ширина: шаблон.дверь, высота: шаблон.высотаДвери, кабинаШирина: шаблон.кабинаШирина,
                   кабинаГлубина: шаблон.кабинаГлубина, шаблон: шаблон.id, примерно: шаблон.примерно)
    }

    /// Входная дверь «обычно» — 80 × 200, примерно.
    static func входнаяОбычно() -> ПроёмМоего {
        ПроёмМоего(вид: .входная, ширина: КаталогСтандартов.входнаяПроход.ширина,
                   высота: КаталогСтандартов.входнаяПроход.высота, примерно: true)
    }

    var заполнен: Bool { ширина != nil }

    mutating func нормализовать() {
        имя = String(имя.prefix(30))
        let пути: [WritableKeyPath<ПроёмМоего, Int?>] = [\.ширина, \.высота, \.кабинаШирина, \.кабинаГлубина]
        for путь in пути {
            if let x = self[keyPath: путь], !Self.пределыСм.contains(x) { self[keyPath: путь] = nil }
        }
    }
}

// MARK: - Кровати

/// Кровать: спальное место каноном («160x200»), матрас (высота, вид), одеяло и подушки.
struct КроватьМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var комната: UUID?
    var место: String?
    var матрасВысота: Int?
    /// Ключ вида матраса каталога: «independent_springs», «foam»…
    var матрас: String?
    var одеяло: String?
    var подушки: String?

    enum CodingKeys: String, CodingKey {
        case id
        case комната = "room"
        case место = "size"
        case матрасВысота = "mh"
        case матрас = "mt"
        case одеяло = "duvet"
        case подушки = "pillow"
    }

    init(id: UUID = UUID(), комната: UUID? = nil, место: String? = nil, матрасВысота: Int? = nil, матрас: String? = nil,
         одеяло: String? = nil, подушки: String? = nil) {
        self.id = id
        self.комната = комната
        self.место = место
        self.матрасВысота = матрасВысота
        self.матрас = матрас
        self.одеяло = одеяло
        self.подушки = подушки
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        комната = к.значениеМоего(UUID.self, .комната)
        место = Self.размер(к.значениеМоего(String.self, .место))
        матрасВысота = к.значениеМоего(Int.self, .матрасВысота)
            .flatMap { КаталогСтандартов.высотыМатраса.contains($0) ? $0 : nil }
        матрас = к.значениеМоего(String.self, .матрас).flatMap { КаталогСтандартов.видыМатраса.contains($0) ? $0 : nil }
        одеяло = Self.размер(к.значениеМоего(String.self, .одеяло))
        подушки = Self.размер(к.значениеМоего(String.self, .подушки))
    }

    /// Размер «ШxД» каноном; мусор — nil.
    static func размер(_ строка: String?) -> String? {
        guard let пара = КаталогСтандартов.пара(строка), пара.0 <= 400, пара.1 <= 400 else { return nil }
        return КаталогСтандартов.канон(пара.0, пара.1)
    }

    /// Ширина спального места, см.
    var ширина: Int? { КаталогСтандартов.пара(место).map { Int($0.0) } }

    var заполнена: Bool { место != nil }

    mutating func нормализовать() {
        место = Self.размер(место)
        одеяло = Self.размер(одеяло)
        подушки = Self.размер(подушки)
        if let в = матрасВысота, !КаталогСтандартов.высотыМатраса.contains(в) { матрасВысота = nil }
    }
}

// MARK: - Окна

/// Окно: Ш×В створки или проёма, см; примерно — «замерьте».
struct ОкноДомаМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var комната: UUID?
    var ширина: Int?
    var высота: Int?
    var створок: Int?
    var примерно: Bool

    static let пределыСм: ClosedRange<Int> = 20...600

    enum CodingKeys: String, CodingKey {
        case id
        case комната = "room"
        case ширина = "w"
        case высота = "h"
        case створок = "n"
        case примерно = "approx"
    }

    init(id: UUID = UUID(), комната: UUID? = nil, ширина: Int? = nil, высота: Int? = nil, створок: Int? = nil,
         примерно: Bool = false) {
        self.id = id
        self.комната = комната
        self.ширина = ширина
        self.высота = высота
        self.створок = створок
        self.примерно = примерно
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        комната = к.значениеМоего(UUID.self, .комната)
        ширина = к.значениеМоего(Int.self, .ширина).flatMap { Self.пределыСм.contains($0) ? $0 : nil }
        высота = к.значениеМоего(Int.self, .высота).flatMap { Self.пределыСм.contains($0) ? $0 : nil }
        створок = к.значениеМоего(Int.self, .створок).flatMap { (1...8).contains($0) ? $0 : nil }
        примерно = к.значениеМоего(Bool.self, .примерно) ?? false
    }

    var заполнено: Bool { ширина != nil && высота != nil }

    mutating func нормализовать() {
        if let ш = ширина, !Self.пределыСм.contains(ш) { ширина = nil }
        if let в = высота, !Self.пределыСм.contains(в) { высота = nil }
        if let с = створок, !(1...8).contains(с) { створок = nil }
    }
}

// MARK: - ТВ на стене

/// Телевизор или монитор на стене: диагональ, VESA, вес; устройство — связь с «Моими устройствами» (по желанию).
struct ЭкранНаСтенеМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var комната: UUID?
    var устройство: UUID?
    var диагональ: Double?
    /// Шаблон VESA каноном («300x300»); nil — не знаем (тогда «обычно» по диагонали).
    var vesa: String?
    /// Вес без подставки, кг.
    var вес: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case комната = "room"
        case устройство = "dev"
        case диагональ = "diag"
        case vesa
        case вес = "kg"
    }

    init(id: UUID = UUID(), комната: UUID? = nil, устройство: UUID? = nil, диагональ: Double? = nil,
         vesa: String? = nil, вес: Double? = nil) {
        self.id = id
        self.комната = комната
        self.устройство = устройство
        self.диагональ = диагональ
        self.vesa = vesa
        self.вес = вес
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        комната = к.значениеМоего(UUID.self, .комната)
        устройство = к.значениеМоего(UUID.self, .устройство)
        диагональ = к.значениеМоего(Double.self, .диагональ).flatMap { (10...150).contains($0) ? $0 : nil }
        vesa = к.значениеМоего(String.self, .vesa).flatMap { КаталогСтандартов.шаблоныVESA.contains($0) ? $0 : nil }
        вес = к.значениеМоего(Double.self, .вес).flatMap { (0.5...200).contains($0) ? $0 : nil }
    }

    /// Шаблон для сверки: свой — точно; иначе «обычно» по диагонали — примерно (сверка не выше «Проверьте»).
    var шаблонДляСверки: (шаблон: String, примерно: Bool)? {
        if let vesa { return (vesa, false) }
        guard let диагональ else { return nil }
        return (КаталогСтандартов.vesaОбычно(диагональ: диагональ), true)
    }

    var заполнен: Bool { vesa != nil || диагональ != nil }

    mutating func нормализовать() {
        if let в = vesa, !КаталогСтандартов.шаблоныVESA.contains(в) { vesa = nil }
        if let д = диагональ, !(10...150).contains(д) { диагональ = nil }
        if let к = вес, !(0.5...200).contains(к) { вес = nil }
    }
}

// MARK: - Лампы

/// Лампы одного цоколя в комнате: «E27 ×6». Напряжение — из каталога (GU5.3 — 12 В).
struct ЛампыМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var комната: UUID?
    /// Код цоколя каталога: «E27», «GU5.3».
    var цоколь: String
    var сколько: Int

    static let пределыСколько: ClosedRange<Int> = 1...99

    enum CodingKeys: String, CodingKey {
        case id
        case комната = "room"
        case цоколь = "base"
        case сколько = "n"
    }

    init(id: UUID = UUID(), комната: UUID? = nil, цоколь: String, сколько: Int = 1) {
        self.id = id
        self.комната = комната
        self.цоколь = цоколь
        self.сколько = min(Self.пределыСколько.upperBound, max(Self.пределыСколько.lowerBound, сколько))
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        комната = к.значениеМоего(UUID.self, .комната)
        guard let код = КаталогСтандартов.цоколь(к.значениеМоего(String.self, .цоколь))?.id else {
            throw DecodingError.dataCorruptedError(forKey: .цоколь, in: к, debugDescription: "base")
        }
        цоколь = код
        сколько = min(Self.пределыСколько.upperBound, max(Self.пределыСколько.lowerBound,
                                                         к.значениеМоего(Int.self, .сколько) ?? 1))
    }

    /// Напряжение цоколя по каталогу.
    var вольт: Int { КаталогСтандартов.цоколь(цоколь)?.вольт ?? 230 }

    /// «E27 ×6».
    var подпись: String { цоколь + " ×" + String(сколько) }

    mutating func нормализовать() {
        сколько = min(Self.пределыСколько.upperBound, max(Self.пределыСколько.lowerBound, сколько))
        if let код = КаталогСтандартов.цоколь(цоколь)?.id { цоколь = код }
    }
}

// MARK: - Техника

enum ВидТехникиМоего: String, Codable, CaseIterable, Sendable {
    case холодильник = "fridge"
    case стиральная = "washer"
    case посудомойка = "dishwasher"
    case пылесос = "vacuum"
    case робот = "robot_vacuum"
    case фильтр = "water_filter"
    case кофемашина = "coffee"
    case кондиционер = "ac"
    case плита = "stove"
    case духовка = "oven"
    case микроволновка = "microwave"
    case водонагреватель = "water_heater"
    case принтер = "printer"
    case другая = "other"

    var значок: String {
        switch self {
        case .холодильник: return "refrigerator"
        case .стиральная: return "washer"
        case .посудомойка: return "dishwasher"
        case .пылесос, .робот: return "fan"
        case .фильтр: return "drop"
        case .кофемашина: return "cup.and.saucer"
        case .кондиционер: return "air.conditioner.horizontal"
        case .плита: return "stove"
        case .духовка: return "oven"
        case .микроволновка: return "microwave"
        case .водонагреватель: return "heater.vertical"
        case .принтер: return "printer"
        case .другая: return "powerplug"
        }
    }

    var название: String { МоёText.т("my_app_" + rawValue) }
}

/// Техника дома: вид, бренд, модель, код расходника («Brita Maxtra», «s-bag»), габариты Ш×В×Г (см).
struct ТехникаМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var комната: UUID?
    var вид: ВидТехникиМоего
    var бренд: String
    var модель: String
    var расходник: String
    var см: [Int]?
    var покупка: ПокупкаМоего?
    /// Обложка объявления, если техника куплена на Kliko (адрес сайта).
    var адресФото: String?

    enum CodingKeys: String, CodingKey {
        case id
        case комната = "room"
        case вид = "kind"
        case бренд = "brand"
        case модель = "model"
        case расходник = "supply"
        case см = "cm"
        case покупка = "bought"
        case адресФото = "img"
    }

    init(id: UUID = UUID(), комната: UUID? = nil, вид: ВидТехникиМоего, бренд: String = "", модель: String = "",
         расходник: String = "", см: [Int]? = nil, покупка: ПокупкаМоего? = nil, адресФото: String? = nil) {
        self.id = id
        self.комната = комната
        self.вид = вид
        self.бренд = бренд
        self.модель = модель
        self.расходник = расходник
        self.см = см
        self.покупка = покупка
        self.адресФото = адресФото
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        комната = к.значениеМоего(UUID.self, .комната)
        вид = к.значениеМоего(ВидТехникиМоего.self, .вид) ?? .другая
        бренд = String((к.значениеМоего(String.self, .бренд) ?? "").prefix(30))
        модель = String((к.значениеМоего(String.self, .модель) ?? "").prefix(60))
        расходник = String((к.значениеМоего(String.self, .расходник) ?? "").prefix(40))
        см = к.значениеМоего([Int].self, .см).flatMap { $0.count == 3 && $0.allSatisfy { $0 > 0 && $0 <= 500 } ? $0 : nil }
        покупка = к.значениеМоего(ПокупкаМоего.self, .покупка)
        адресФото = к.значениеМоего(String.self, .адресФото).flatMap { $0.count <= 500 ? $0 : nil }
    }

    /// «Bosch Serie 4», иначе вид.
    var заголовок: String {
        let имя = [бренд, модель].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return имя.isEmpty ? вид.название : имя
    }

    mutating func нормализовать() {
        бренд = String(бренд.prefix(30))
        модель = String(модель.prefix(60))
        расходник = String(расходник.prefix(40))
        if let см, !(см.count == 3 && см.allSatisfy({ $0 > 0 && $0 <= 500 })) { self.см = nil }
    }
}

// MARK: - Весь дом

/// Стиль дома — только порядок подборки.
enum СтильДомаМоего: String, Codable, CaseIterable, Sendable {
    case сканди = "scandi"
    case лофт = "loft"
    case классика = "classic"
    case минимализм = "minimal"
    case современный = "modern"
    case эко = "eco"

    var название: String { МоёText.т("my_style_" + rawValue) }
}

struct ДомМоего: Codable, Equatable, Sendable {
    var комнаты: [КомнатаМоего]
    var проёмы: [ПроёмМоего]
    var кровати: [КроватьМоего]
    var окна: [ОкноДомаМоего]
    var экраны: [ЭкранНаСтенеМоего]
    var лампы: [ЛампыМоего]
    var техника: [ТехникаМоего]
    /// Этаж квартиры; 0 — частный дом или первый.
    var этаж: Int?
    /// «Лифта нет» — засчитывается в прогресс.
    var лифтаНет: Bool
    var стиль: [СтильДомаМоего]
    /// Цвета дома (общие); у комнаты — своя палитра.
    var палитра: [ЦветСтандарта]

    static let пределКомнат = 12
    static let пределПроёмов = 8
    static let пределКроватей = 6
    static let пределОкон = 20
    static let пределЭкранов = 6
    static let пределЛамп = 40
    static let пределТехники = 24

    enum CodingKeys: String, CodingKey {
        case комнаты = "rooms"
        case проёмы = "openings"
        case кровати = "beds"
        case окна = "windows"
        case экраны = "screens"
        case лампы = "lamps"
        case техника = "appliances"
        case этаж = "floor"
        case лифтаНет = "nolift"
        case стиль = "style"
        case палитра = "colors"
    }

    init() {
        комнаты = []
        проёмы = []
        кровати = []
        окна = []
        экраны = []
        лампы = []
        техника = []
        этаж = nil
        лифтаНет = false
        стиль = []
        палитра = []
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        комнаты = Self.без(к.списокМоего(КомнатаМоего.self, .комнаты), Self.пределКомнат)
        проёмы = Self.без(к.списокМоего(ПроёмМоего.self, .проёмы), Self.пределПроёмов)
        кровати = Self.без(к.списокМоего(КроватьМоего.self, .кровати), Self.пределКроватей)
        окна = Self.без(к.списокМоего(ОкноДомаМоего.self, .окна), Self.пределОкон)
        экраны = Self.без(к.списокМоего(ЭкранНаСтенеМоего.self, .экраны), Self.пределЭкранов)
        лампы = Self.без(к.списокМоего(ЛампыМоего.self, .лампы), Self.пределЛамп)
        техника = Self.без(к.списокМоего(ТехникаМоего.self, .техника), Self.пределТехники)
        этаж = к.значениеМоего(Int.self, .этаж).flatMap { (0...200).contains($0) ? $0 : nil }
        лифтаНет = к.значениеМоего(Bool.self, .лифтаНет) ?? false
        стиль = Array(Set((к.значениеМоего([String].self, .стиль) ?? []).compactMap { СтильДомаМоего(rawValue: $0) }))
            .sorted { $0.rawValue < $1.rawValue }
        палитра = ЦветСтандарта.из(к.значениеМоего([String].self, .палитра) ?? [], предел: 5)
    }

    /// Без повторов id и не больше предела.
    private static func без<Т: Identifiable>(_ список: [Т], _ предел: Int) -> [Т] where Т.ID == UUID {
        var номера = Set<UUID>()
        return Array(список.filter { номера.insert($0.id).inserted }.prefix(предел))
    }

    var пусто: Bool {
        комнаты.isEmpty && проёмы.isEmpty && кровати.isEmpty && окна.isEmpty && экраны.isEmpty && лампы.isEmpty
            && техника.isEmpty && этаж == nil && !лифтаНет && стиль.isEmpty && палитра.isEmpty
    }

    func комната(_ id: UUID?) -> КомнатаМоего? {
        guard let id else { return nil }
        return комнаты.first { $0.id == id }
    }

    /// Название комнаты для «почему» («Спальня»); нет — nil.
    func имяКомнаты(_ id: UUID?) -> String? { комната(id)?.заголовок }

    /// Входная дверь, межкомнатные двери, лифт — то, через что вещь заносят.
    var путьВДом: [ПроёмМоего] { проёмы.filter { $0.заполнен && $0.вид != .балкон } }

    /// Узкий проход по пути в дом: дверь или лифт с наименьшей шириной (лестница не в счёт — её ширина не «дверь»).
    var самыйУзкий: ПроёмМоего? {
        путьВДом.filter { $0.вид != .лестница && $0.ширина != nil }.min { ($0.ширина ?? 999) < ($1.ширина ?? 999) }
    }

    /// Цоколи дома с числом ламп: «E27» → 9.
    var цоколи: [String: Int] {
        лампы.reduce(into: [:]) { итог, л in итог[л.цоколь, default: 0] += л.сколько }
    }

    /// Потолок дома: самый частый среди комнат.
    var потолок: Int? {
        let высоты = комнаты.compactMap(\.высота)
        guard !высоты.isEmpty else { return nil }
        let счёт = высоты.reduce(into: [Int: Int]()) { $0[$1, default: 0] += 1 }
        return счёт.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
    }

    /// Пределы, повторы и связи с удалёнными комнатами — после каждой правки (хранилище).
    mutating func нормализовать() {
        комнаты = Self.без(комнаты, Self.пределКомнат)
        проёмы = Self.без(проёмы, Self.пределПроёмов)
        кровати = Self.без(кровати, Self.пределКроватей)
        окна = Self.без(окна, Self.пределОкон)
        экраны = Self.без(экраны, Self.пределЭкранов)
        лампы = Self.без(лампы, Self.пределЛамп)
        техника = Self.без(техника, Self.пределТехники)
        for i in комнаты.indices { комнаты[i].нормализовать() }
        for i in проёмы.indices { проёмы[i].нормализовать() }
        for i in кровати.indices { кровати[i].нормализовать() }
        for i in окна.indices { окна[i].нормализовать() }
        for i in экраны.indices { экраны[i].нормализовать() }
        for i in лампы.indices { лампы[i].нормализовать() }
        for i in техника.indices { техника[i].нормализовать() }
        let есть = Set(комнаты.map(\.id))
        let отвязать: (UUID?) -> UUID? = { $0.flatMap { есть.contains($0) ? $0 : nil } }
        for i in кровати.indices { кровати[i].комната = отвязать(кровати[i].комната) }
        for i in окна.indices { окна[i].комната = отвязать(окна[i].комната) }
        for i in экраны.indices { экраны[i].комната = отвязать(экраны[i].комната) }
        for i in лампы.indices { лампы[i].комната = отвязать(лампы[i].комната) }
        for i in техника.indices { техника[i].комната = отвязать(техника[i].комната) }
        if let э = этаж, !(0...200).contains(э) { этаж = nil }
        палитра = ЦветСтандарта.из(палитра.map(\.rawValue), предел: 5)
    }

    /// Имена фото дома (для уборки файлов).
    var файлыФото: [String] {
        комнаты.compactMap(\.фото).flatMap { [$0.файл, $0.мини] }
    }
}
