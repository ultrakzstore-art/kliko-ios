import Foundation

/**
 «МОЁ» — ПРОФИЛИ ЧЕЛОВЕКА НА ТЕЛЕФОНЕ (владелец 14.10.2026: «на будущее будет по типу моя машина — туда можно будет
 примерить диски… так же с чехлами для смартфонов, сумками для ноутбуков… одежда — полный рост сфоткал по шаблону»;
 16.10.2026: «по всем моментам разом»).

 Три профиля — одна запись (ЗаписьМоего), один файл и фото рядом (MyThingsStore.swift):
   · «Мой гараж» — до 5 машин: марка, модель, год из того же справочника, что у «Подойдут ли?» (МашинаАвтоподбора),
     параметры колёс (ПосадкаАвтоподбора), своё название и фото сбоку по шаблону с кругами колёс. Главная машина —
     та, с которой сверяются шины и диски в «Подойдут ли?» (ГаражАвтоподбора берёт её отсюда);
   · «Мои устройства» — телефон (модель определяется сама, ЖелезоУстройства.модель), ноутбуки, мониторы и телевизоры
     с диагональю и габаритами Ш×В×Г — как dim_* у объявлений;
   · «Мой рост и мерки» — рост, размеры в своей системе (таблицы ClothingSizes — только вызовы), обхваты тела и фото
     в полный рост с точками позы (Vision на телефоне).
 Пачка 16.10.2026 «мой дом, компьютер, гардероб и для вас» (запись v2) — в той же записи и том же файле:
   · «Мой дом» — ДомМоего (MyThingsHomeModel.swift); «Мой компьютер» — до 4 компьютеров и ноутбуков, КомпьютерМоего
     (MyThingsPCModel.swift); «Мой гардероб» — ГардеробМоего (MyThingsWardrobeModel.swift); всё — по стандартам
     (Sources/Native/Standards);
   · «Куплено на Kliko» — ВещьМоего: купленное в безопасной сделке, добавленное касанием («Добавить из моих покупок»,
     MyThingsFromDeals.swift), с местом в «Моём», значениями стандартов и ПокупкаМоего (сделка, цена, месяц); какие
     сделки уже добавлены — изСделок. Цену видит только владелец на этом телефоне.
 Детских размеров и фото детей здесь нет: данные детей не собираем.

 Файл должен переживать версии приложения: у каждого типа — короткие ASCII-ключи (CodingKeys) и своё чтение через
 decodeIfPresent со значением по умолчанию (синтезированный Codable падает на отсутствующем ключе даже у поля со
 значением по умолчанию), а битая запись массива пропускается, список не теряется (как ИзбранноеФайл.Любая).
 Ничего из этого не уходит на сервер.
 */
extension Config {
    /// «Моё» — гараж, устройства, рост и мерки на телефоне (карточка в кабинете, хаб, строка «Данные на телефоне»).
    /// false — входа нет; «Подойдут ли?» по-прежнему помнит одну машину (главную), данные не стираются.
    static let моё = true
    /// «Мой дом» — карточка хаба и сверка дома (кровать, окна, ТВ, лампы, проёмы). false — карточки нет, данные живут.
    static let мойДом = true
    /// «Мой компьютер / ноутбук» — карточка хаба и сверка ОЗУ, накопителей, видеокарт, БП.
    static let мойКомпьютер = true
    /// «Мой гардероб» — карточка хаба.
    static let мойГардероб = true
    /// «Добавить из моих покупок» — завершённые сделки покупателя (только чтение my_deals) касанием ложатся в «Моё».
    static let покупкиВМоё = true
}

// MARK: - Терпимое чтение

/// Элемент массива, который не разобрался, — nil, а не ошибка всего списка.
struct ЛюбаяМоего<Значение: Decodable>: Decodable {
    let значение: Значение?

    init(from decoder: Decoder) throws {
        значение = try? Значение(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// Значение по ключу; нет ключа или не разобралось — nil.
    func значениеМоего<Значение: Decodable>(_ тип: Значение.Type, _ ключ: Key) -> Значение? {
        try? decodeIfPresent(тип, forKey: ключ)
    }

    /// Список по ключу без битых записей; нет ключа — пусто.
    func списокМоего<Значение: Decodable>(_ тип: Значение.Type, _ ключ: Key) -> [Значение] {
        let сырые = try? decodeIfPresent([ЛюбаяМоего<Значение>].self, forKey: ключ)
        return (сырые ?? []).compactMap(\.значение)
    }
}

// MARK: - Фото

/// Круг на снимке: доли, начало сверху слева; x и r — от ширины, y — от высоты.
struct КругМоего: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var r: Double

    enum CodingKeys: String, CodingKey { case x, y, r }

    init(x: Double, y: Double, r: Double) {
        self.x = x
        self.y = y
        self.r = r
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        x = Self.доля(к.значениеМоего(Double.self, .x) ?? 0.5)
        y = Self.доля(к.значениеМоего(Double.self, .y) ?? 0.5)
        r = min(0.5, max(0.01, к.значениеМоего(Double.self, .r) ?? 0.08))
    }

    static func доля(_ x: Double) -> Double { x.isFinite ? min(1, max(0, x)) : 0.5 }
}

/// Точка позы: доли снимка, начало сверху слева.
struct ТочкаМоего: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double

    enum CodingKeys: String, CodingKey { case x, y }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        x = КругМоего.доля(к.значениеМоего(Double.self, .x) ?? 0.5)
        y = КругМоего.доля(к.значениеМоего(Double.self, .y) ?? 0.5)
    }
}

/// Фото профиля: файл в photos/, размер, когда снято, по какому шаблону; у машины — колёса, у тела — точки позы.
struct ФотоМоего: Codable, Equatable, Sendable {
    /// Имя файла внутри photos/ («<uuid>.jpg»); миниатюра рядом — «<uuid>-s.jpg».
    var файл: String
    var ширина: Int
    var высота: Int
    var снято: Date
    /// «car_side_1», «body_full_1» или «gallery».
    var шаблон: String
    /// Только у машины: круги колёс на снимке.
    var колёса: [КругМоего]
    /// Только у тела: head, neck, lsh, rsh, lhip, rhip, lknee, rknee, lank, rank.
    var поза: [String: ТочкаМоего]
    /// Vision видел людей на фото машины (подсказка «лучше без них»).
    var люди: Bool?
    /// Фигура видна целиком — от головы до лодыжек.
    var полныйРост: Bool?

    static let шаблонМашины = "car_side_1"
    static let шаблонТела = "body_full_1"
    static let шаблонГалереи = "gallery"

    enum CodingKeys: String, CodingKey {
        case файл = "f"
        case ширина = "w"
        case высота = "h"
        case снято = "at"
        case шаблон = "tpl"
        case колёса = "wheels"
        case поза = "pose"
        case люди = "people"
        case полныйРост = "full"
    }

    init(файл: String, ширина: Int, высота: Int, снято: Date = Date(), шаблон: String, колёса: [КругМоего] = [],
         поза: [String: ТочкаМоего] = [:], люди: Bool? = nil, полныйРост: Bool? = nil) {
        self.файл = файл
        self.ширина = ширина
        self.высота = высота
        self.снято = снято
        self.шаблон = шаблон
        self.колёса = колёса
        self.поза = поза
        self.люди = люди
        self.полныйРост = полныйРост
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        файл = try к.decode(String.self, forKey: .файл)
        /* Имя — только своё, без папок: чужой путь из файла не уведёт чтение и удаление за пределы photos/. */
        guard !файл.isEmpty, !файл.contains("/"), !файл.contains("..") else {
            throw DecodingError.dataCorruptedError(forKey: .файл, in: к, debugDescription: "bad name")
        }
        ширина = max(1, к.значениеМоего(Int.self, .ширина) ?? 1)
        высота = max(1, к.значениеМоего(Int.self, .высота) ?? 1)
        снято = к.значениеМоего(Date.self, .снято) ?? Date()
        шаблон = к.значениеМоего(String.self, .шаблон) ?? Self.шаблонГалереи
        колёса = Array(к.списокМоего(КругМоего.self, .колёса).prefix(4))
        поза = к.значениеМоего([String: ТочкаМоего].self, .поза) ?? [:]
        люди = к.значениеМоего(Bool.self, .люди)
        полныйРост = к.значениеМоего(Bool.self, .полныйРост)
    }

    /// Миниатюра 480 px для карточек.
    var мини: String { Self.мини(файл) }

    static func мини(_ файл: String) -> String {
        guard let точка = файл.lastIndex(of: ".") else { return файл + "-s" }
        return String(файл[..<точка]) + "-s" + String(файл[точка...])
    }

    /// Ширина к высоте снимка.
    var пропорция: Double { Double(ширина) / Double(max(1, высота)) }
}

// MARK: - Гараж

/// Машина гаража: марка, модель, год (как в «Подойдут ли?»), параметры колёс, своё название и фото сбоку.
struct МашинаМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var авто: МашинаАвтоподбора?
    var посадка: ПосадкаАвтоподбора?
    /// Своё название («рабочая») — по желанию, до 30 знаков.
    var имя: String
    var фото: ФотоМоего?
    var создана: Date

    static let пределИмени = 30

    enum CodingKeys: String, CodingKey {
        case id
        case авто = "car"
        case посадка = "fit"
        case имя = "name"
        case фото = "photo"
        case создана = "at"
    }

    init(id: UUID = UUID(), авто: МашинаАвтоподбора? = nil, посадка: ПосадкаАвтоподбора? = nil, имя: String = "",
         фото: ФотоМоего? = nil, создана: Date = Date()) {
        self.id = id
        self.авто = авто
        self.посадка = посадка
        self.имя = имя
        self.фото = фото
        self.создана = создана
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        авто = к.значениеМоего(МашинаАвтоподбора.self, .авто)
        посадка = к.значениеМоего(ПосадкаАвтоподбора.self, .посадка).flatMap { $0.пустая ? nil : $0 }
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(Self.пределИмени))
        фото = к.значениеМоего(ФотоМоего.self, .фото)
        создана = к.значениеМоего(Date.self, .создана) ?? Date()
    }

    /// Своё название, иначе «Toyota Camry, 2018», иначе «Моя машина».
    var заголовок: String {
        let своё = имя.trimmingCharacters(in: .whitespacesAndNewlines)
        if !своё.isEmpty { return своё }
        if let авто, !авто.подпись.isEmpty { return авто.подпись }
        return МоёText.т("my_car_unnamed")
    }

    /// Чипы параметров: PCD · ET · DIA · R · шина.
    var чипы: [String] {
        guard let п = посадка else { return [] }
        var итог: [String] = []
        if let р = п.разболтовка { итог.append(р.подпись) }
        if let низ = п.etMin ?? п.etMax, let верх = п.etMax ?? п.etMin {
            итог.append(низ == верх ? "ET" + ЧислаАвтоподбора.ч(низ)
                        : "ET" + ЧислаАвтоподбора.ч(низ) + "…" + ЧислаАвтоподбора.ч(верх))
        }
        if let dia = п.dia { итог.append("DIA " + ЧислаАвтоподбора.ч(dia, знаков: 2)) }
        if let r = п.штатныеДиаметры.first { итог.append("R" + ЧислаАвтоподбора.ч(r)) }
        if let шина = п.шины.first { итог.append(шина.подпись) }
        return итог
    }
}

// MARK: - Устройства

/// Телефон человека: модель так, как пишут в объявлениях чехлов («iPhone 15 Pro»), код железа, диагональ, Ш·В·Т мм.
struct ТелефонМоего: Codable, Equatable, Sendable {
    var модель: String
    /// «iPhone16,1» или пусто (выбрано вручную).
    var код: String
    var диагональ: Double?
    /// Ширина, высота, толщина, мм.
    var мм: [Double]?
    /// Определён автоматически по железу.
    var сам: Bool

    enum CodingKeys: String, CodingKey {
        case модель = "model"
        case код = "code"
        case диагональ = "diag"
        case мм = "mm"
        case сам = "auto"
    }

    init(модель: String, код: String = "", диагональ: Double? = nil, мм: [Double]? = nil, сам: Bool = false) {
        self.модель = модель
        self.код = код
        self.диагональ = диагональ
        self.мм = мм
        self.сам = сам
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        модель = try String(к.decode(String.self, forKey: .модель).prefix(60))
        код = к.значениеМоего(String.self, .код) ?? ""
        диагональ = к.значениеМоего(Double.self, .диагональ).flatMap { (2...20).contains($0) ? $0 : nil }
        мм = к.значениеМоего([Double].self, .мм).flatMap { $0.count == 3 && $0.allSatisfy { $0 > 0 && $0 < 400 } ? $0 : nil }
        сам = к.значениеМоего(Bool.self, .сам) ?? false
    }
}

/// Вид устройства — те же ключи, что у шаблонов габаритов (КаталогРазмеров.встроенные).
enum ВидУстройстваМоего: String, Codable, CaseIterable, Sendable {
    case ноутбук = "laptop"
    case монитор = "monitor"
    case тв = "tv"

    var значок: String {
        switch self {
        case .ноутбук: return "laptopcomputer"
        case .монитор: return "display"
        case .тв: return "tv"
        }
    }

    var название: String {
        switch self {
        case .ноутбук: return МоёТелоText.т("md_laptop")
        case .монитор: return МоёТелоText.т("md_monitor")
        case .тв: return МоёТелоText.т("md_tv")
        }
    }

    /// Ноутбук или экран — ключ «нет такого» в ЗаписьМоего.нет.
    var ключНет: String { self == .ноутбук ? ЗаписьМоего.нетНоутбука : ЗаписьМоего.нетЭкрана }
}

/// Ноутбук, монитор или телевизор: модель по желанию, диагональ и габариты Ш×В×Г в сантиметрах (как dim_*).
struct УстройствоМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var вид: ВидУстройстваМоего
    var модель: String
    var диагональ: Double?
    /// Ширина, высота, глубина, см.
    var см: [Int]?
    /// Габариты подставлены шаблоном — «примерно» (как dims_src «tpl» у объявлений).
    var образец: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case вид = "kind"
        case модель = "model"
        case диагональ = "diag"
        case см = "cm"
        case образец = "tpl"
    }

    init(id: UUID = UUID(), вид: ВидУстройстваМоего, модель: String = "", диагональ: Double? = nil, см: [Int]? = nil,
         образец: Bool = false) {
        self.id = id
        self.вид = вид
        self.модель = модель
        self.диагональ = диагональ
        self.см = см
        self.образец = образец
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        вид = try к.decode(ВидУстройстваМоего.self, forKey: .вид)
        модель = String((к.значениеМоего(String.self, .модель) ?? "").prefix(60))
        диагональ = к.значениеМоего(Double.self, .диагональ).flatMap { (5...150).contains($0) ? $0 : nil }
        см = к.значениеМоего([Int].self, .см).flatMap { $0.count == 3 && $0.allSatisfy { $0 > 0 && $0 <= 500 } ? $0 : nil }
        образец = к.значениеМоего(Bool.self, .образец) ?? false
    }

    /// Что-то указано: без этого устройство в прогресс не идёт.
    var заполнено: Bool {
        диагональ != nil || см != nil || !модель.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Куплено на Kliko

/// Покупка на Kliko: сделка, объявление, цена (₸, оплачено за товар), когда (месяц показа), бренд. Видит только владелец.
struct ПокупкаМоего: Codable, Equatable, Hashable, Sendable {
    var сделка: String
    var объявление: String
    var цена: Int?
    var когда: Date?
    var бренд: String?

    enum CodingKeys: String, CodingKey {
        case сделка = "deal"
        case объявление = "listing"
        case цена = "price"
        case когда = "at"
        case бренд = "brand"
    }

    init(сделка: String, объявление: String = "", цена: Int? = nil, когда: Date? = nil, бренд: String? = nil) {
        self.сделка = сделка
        self.объявление = объявление
        self.цена = цена
        self.когда = когда
        self.бренд = бренд
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        let номер = try к.decode(String.self, forKey: .сделка)
        guard СделкиAPI.годныйНомер(номер) else {
            throw DecodingError.dataCorruptedError(forKey: .сделка, in: к, debugDescription: "deal")
        }
        сделка = номер
        объявление = String((к.значениеМоего(String.self, .объявление) ?? "").prefix(40))
        цена = к.значениеМоего(Int.self, .цена).flatMap { $0 > 0 ? $0 : nil }
        когда = к.значениеМоего(Date.self, .когда)
        бренд = к.значениеМоего(String.self, .бренд).map { String($0.prefix(30)) }
    }

    /// «Куплено на Kliko · окт 2026».
    var подпись: String {
        guard let когда else { return МоёText.т("my_bought_kliko") }
        return String(format: МоёText.т("my_bought_kliko_at"), Self.месяц(когда))
    }

    /// «Куплено на Kliko · окт 2026 · 25 000 ₸» — только владельцу.
    var подписьСЦеной: String {
        guard let цена else { return подпись }
        return подпись + " · " + СделкиФормат.тенге(цена)
    }

    /// Форматтеры месяца на четыре языка — строятся один раз, дальше только читаются (форматирование потокобезопасно).
    private static let форматтеры: [String: DateFormatter] = {
        var итог: [String: DateFormatter] = [:]
        for (язык, место) in [("ru", "ru_RU"), ("kk", "kk_KZ"), ("en", "en_US"), ("ar", "ar")] {
            let ф = DateFormatter()
            ф.locale = Locale(identifier: место)
            ф.dateFormat = "LLL yyyy"
            итог[язык] = ф
        }
        return итог
    }()

    /// «окт 2026» на языке приложения (без точки сокращения).
    static func месяц(_ дата: Date) -> String {
        let ф = форматтеры[ПримерочнаяText.язык] ?? форматтеры["ru"]
        return (ф?.string(from: дата) ?? "").replacingOccurrences(of: ".", with: "")
    }
}

/// Раздел «Моего», куда кладётся вещь.
enum РазделВещиМоего: String, Codable, CaseIterable, Sendable {
    case гараж = "garage"
    case устройства = "devices"
    case дом = "home"
    case компьютер = "pc"
    case гардероб = "wardrobe"
    case мерки = "body"
    case безМеста = "none"

    var значок: String {
        switch self {
        case .гараж: return "car.side"
        case .устройства: return "iphone.gen3"
        case .дом: return "house"
        case .компьютер: return "desktopcomputer"
        case .гардероб: return "hanger"
        case .мерки: return "figure.stand"
        case .безМеста: return "shippingbox"
        }
    }

    var название: String { МоёText.т("my_place_" + rawValue) }
}

/// Место вещи: раздел и, если есть, чья она там — машина, комната, компьютер.
struct МестоВещиМоего: Codable, Equatable, Hashable, Sendable {
    var раздел: РазделВещиМоего
    var id: UUID?

    enum CodingKeys: String, CodingKey {
        case раздел = "s"
        case id
    }

    init(_ раздел: РазделВещиМоего, _ id: UUID? = nil) {
        self.раздел = раздел
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        раздел = к.значениеМоего(РазделВещиМоего.self, .раздел) ?? .безМеста
        id = к.значениеМоего(UUID.self, .id)
    }
}

/**
 Вещь «Моего» из покупки (цифровой двойник, docs/STANDARDS.md §2.8): название, раздел объявления, место, значения
 стандартов (из названия и снимка сделки, источник «deal»), покупка и обложка объявления. Одежда и компьютеры целиком
 ложатся не сюда, а в гардероб и «Мой компьютер» — с той же ПокупкаМоего.
 */
struct ВещьМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var название: String
    /// Раздел объявления (category): «ram», «beds».
    var раздел: String
    var место: МестоВещиМоего
    var стандарты: НаборСтандартов
    var покупка: ПокупкаМоего?
    var адресФото: String?
    var добавлена: Date

    static let пределНазвания = 80

    enum CodingKeys: String, CodingKey {
        case id
        case название = "title"
        case раздел = "cat"
        case место = "place"
        case стандарты = "std"
        case покупка = "bought"
        case адресФото = "img"
        case добавлена = "at"
    }

    init(id: UUID = UUID(), название: String, раздел: String = "", место: МестоВещиМоего,
         стандарты: НаборСтандартов = НаборСтандартов(источник: .сделка), покупка: ПокупкаМоего? = nil,
         адресФото: String? = nil, добавлена: Date = Date()) {
        self.id = id
        self.название = String(название.prefix(Self.пределНазвания))
        self.раздел = раздел
        self.место = место
        self.стандарты = стандарты
        self.покупка = покупка
        self.адресФото = адресФото
        self.добавлена = добавлена
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        название = String((к.значениеМоего(String.self, .название) ?? "").prefix(Self.пределНазвания))
        раздел = String((к.значениеМоего(String.self, .раздел) ?? "").prefix(40))
        место = к.значениеМоего(МестоВещиМоего.self, .место) ?? МестоВещиМоего(.безМеста)
        стандарты = к.значениеМоего(НаборСтандартов.self, .стандарты) ?? НаборСтандартов(источник: .сделка)
        покупка = к.значениеМоего(ПокупкаМоего.self, .покупка)
        адресФото = к.значениеМоего(String.self, .адресФото).flatMap { $0.count <= 500 ? $0 : nil }
        добавлена = к.значениеМоего(Date.self, .добавлена) ?? Date()
    }
}

// MARK: - Вся запись

/// Всё «Моё» одним файлом my-things.json (обычно десятки КБ).
struct ЗаписьМоего: Codable, Equatable, Sendable {
    var версия: Int
    var машины: [МашинаМоего]
    /// Главная машина — её видит «Подойдут ли?». nil — первая по списку.
    var главная: UUID?
    var телефон: ТелефонМоего?
    var устройства: [УстройствоМоего]
    /// «Нет такого»: ноутбука («laptop»), экрана («screen») — засчитывается в прогресс.
    var нет: Set<String>
    var тело: ТелоМоего
    /// v2: «Мой дом».
    var дом: ДомМоего
    /// v2: «Мой компьютер» — компьютеры и ноутбуки, первый — главный для сверки.
    var компьютеры: [КомпьютерМоего]
    /// v2: «Мой гардероб».
    var гардероб: ГардеробМоего
    /// v2: купленное на Kliko и прочие вещи с местом (кроме одежды и компьютеров целиком).
    var вещи: [ВещьМоего]
    /// v2: сделка → id того, что из неё добавлено (вещь, вещь гардероба, компьютер) — «уже в «Моём»» и «Убрать».
    var изСделок: [String: UUID]

    static let пределМашин = 5
    static let пределУстройств = 6
    static let пределКомпьютеров = 4
    static let пределВещей = 300
    static let пределСделок = 500
    static let нетНоутбука = "laptop"
    static let нетЭкрана = "screen"
    static let текущаяВерсия = 2

    enum CodingKeys: String, CodingKey {
        case версия = "v"
        case машины = "cars"
        case главная = "main"
        case телефон = "phone"
        case устройства = "devices"
        case нет = "none"
        case тело = "body"
        case дом = "home"
        case компьютеры = "pcs"
        case гардероб = "wardrobe"
        case вещи = "items"
        case изСделок = "deals"
    }

    init() {
        версия = Self.текущаяВерсия
        машины = []
        главная = nil
        телефон = nil
        устройства = []
        нет = []
        тело = ТелоМоего()
        дом = ДомМоего()
        компьютеры = []
        гардероб = ГардеробМоего()
        вещи = []
        изСделок = [:]
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        версия = к.значениеМоего(Int.self, .версия) ?? 1
        var номера = Set<UUID>()
        машины = Array(к.списокМоего(МашинаМоего.self, .машины).filter { номера.insert($0.id).inserted }
            .prefix(Self.пределМашин))
        let своя = к.значениеМоего(UUID.self, .главная)
        главная = машины.contains(where: { $0.id == своя }) ? своя : машины.first?.id
        телефон = к.значениеМоего(ТелефонМоего.self, .телефон)
        var номераУстройств = Set<UUID>()
        устройства = Array(к.списокМоего(УстройствоМоего.self, .устройства)
            .filter { номераУстройств.insert($0.id).inserted }
            .prefix(Self.пределУстройств))
        нет = Set((к.значениеМоего([String].self, .нет) ?? []).filter { [Self.нетНоутбука, Self.нетЭкрана].contains($0) })
        тело = к.значениеМоего(ТелоМоего.self, .тело) ?? ТелоМоего()
        // v2 — нет ключей у файла v1: пусто, прежнее не трогается.
        дом = к.значениеМоего(ДомМоего.self, .дом) ?? ДомМоего()
        var номераКомпьютеров = Set<UUID>()
        компьютеры = Array(к.списокМоего(КомпьютерМоего.self, .компьютеры)
            .filter { номераКомпьютеров.insert($0.id).inserted }
            .prefix(Self.пределКомпьютеров))
        гардероб = к.значениеМоего(ГардеробМоего.self, .гардероб) ?? ГардеробМоего()
        var номераВещей = Set<UUID>()
        вещи = Array(к.списокМоего(ВещьМоего.self, .вещи).filter { номераВещей.insert($0.id).inserted }
            .prefix(Self.пределВещей))
        изСделок = (к.значениеМоего([String: UUID].self, .изСделок) ?? [:])
            .filter { СделкиAPI.годныйНомер($0.key) }
    }

    /// Главная машина; если отметка потерялась — первая.
    var главнаяМашина: МашинаМоего? {
        машины.first(where: { $0.id == главная }) ?? машины.first
    }

    var ноутбуки: [УстройствоМоего] { устройства.filter { $0.вид == .ноутбук } }
    var экраны: [УстройствоМоего] { устройства.filter { $0.вид != .ноутбук } }

    /// Главный компьютер для сверки и покупок деталей — первый по списку.
    var главныйКомпьютер: КомпьютерМоего? { компьютеры.first }

    func компьютер(_ id: UUID?) -> КомпьютерМоего? {
        guard let id else { return nil }
        return компьютеры.first { $0.id == id }
    }

    /// Вещи «Моего» в месте: раздел и, если указан, чья (машина, комната, компьютер).
    func вещиВ(_ раздел: РазделВещиМоего, _ id: UUID? = nil) -> [ВещьМоего] {
        вещи.filter { $0.место.раздел == раздел && (id == nil || $0.место.id == id) }
    }

    /// Всё купленное на Kliko — вещи, одежда и компьютеры — новые первыми.
    var купленное: [(название: String, покупка: ПокупкаМоего)] {
        var все: [(название: String, покупка: ПокупкаМоего)] = []
        for в in вещи { if let п = в.покупка { все.append((название: в.название, покупка: п)) } }
        for в in гардероб.вещи { if let п = в.покупка { все.append((название: в.заголовок, покупка: п)) } }
        for к in компьютеры { if let п = к.покупка { все.append((название: к.заголовок, покупка: п)) } }
        return все.sorted { ($0.покупка.когда ?? .distantPast) > ($1.покупка.когда ?? .distantPast) }
    }

    var пусто: Bool {
        машины.isEmpty && телефон == nil && устройства.isEmpty && нет.isEmpty && тело.пусто && дом.пусто
            && компьютеры.isEmpty && гардероб.пусто && вещи.isEmpty && изСделок.isEmpty
    }

    /// Все файлы фото записи (большие и миниатюры) — уборка осиротевших после правки.
    var файлыФото: Set<String> {
        var итог = Set<String>()
        for фото in машины.compactMap(\.фото) + [тело.фото].compactMap({ $0 }) {
            итог.insert(фото.файл)
            итог.insert(фото.мини)
        }
        итог.formUnion(дом.файлыФото)
        итог.formUnion(гардероб.файлыФото)
        return итог
    }
}

// MARK: - Числа

/// Числа экранов «Моего»: без лишних нулей; десятичный знак — как пишут на языке текстов (ru, kk — запятая).
enum ЧислоМоего {
    static func ч(_ x: Double, знаков: Int = 1) -> String {
        let строка = ЧислаАвтоподбора.ч(x, знаков: знаков)
        return ["ru", "kk"].contains(ПримерочнаяText.язык) ? строка.replacingOccurrences(of: ".", with: ",") : строка
    }

    /// Набранное в поле: «70,6», «70.6», « 70 »; не число — nil.
    static func разобрать(_ текст: String) -> Double? {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !чистый.isEmpty, let x = Double(чистый), x.isFinite else { return nil }
        return x
    }

    /// Диагональ, как в объявлениях: «15.6″», «55″».
    static func дюймы(_ x: Double) -> String { ЧислаАвтоподбора.ч(x) + "″" }
}
