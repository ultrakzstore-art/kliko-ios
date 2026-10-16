import Foundation

/**
 «МОЁ» — «МОЙ ГАРДЕРОБ»: МОДЕЛЬ (владелец 16.10.2026: «так же и гардероб вещей»; «это нужно для рекомендаций — по этим
 параметрам новинки и прочее»; docs/SERVER_CIRCLE.md §11.1–11.3).

 Вещь — вид, цвет (палитра из 16 ключей, «цвет сам» по вырезке на телефоне), размер своей системы (РазмерМоего — та же
 бирка всех систем, что у «Моих мерок»), бренд, заметка, фото (вырезка фона — на телефоне, файлом как в v1), покупка на
 Kliko. Образ — несколько своих вещей. Заметка посадки по бренду — «Zara M — мала в плечах»: точнее «мой размер» у этого
 бренда. По ним — «с чем носить» (цвета ЦветСтандарта.сочетается) и подходящее в «Для вас». Детских вещей нет: данные
 детей не собираем. Только на телефоне (МоёХранилище.обновитьГардероб).
 */

/// Слой вещи для образа: верх, низ, целиком, верхняя одежда, обувь, аксессуар.
enum СлойГардеробаМоего: String, Codable, CaseIterable, Sendable {
    case верх = "top"
    case низ = "bottom"
    case целиком = "full"
    case верхняя = "outer"
    case обувь = "shoes"
    case аксессуар = "acc"
}

enum ВидВещиГардеробаМоего: String, Codable, CaseIterable, Sendable {
    case футболка = "tshirt"
    case рубашка = "shirt"
    case свитер = "sweater"
    case худи = "hoodie"
    case пиджак = "blazer"
    case куртка = "jacket"
    case пальто = "coat"
    case платье = "dress"
    case юбка = "skirt"
    case брюки = "trousers"
    case джинсы = "jeans"
    case шорты = "shorts"
    case костюм = "suit"
    case спорт = "sport"
    case обувь = "shoes"
    case кроссовки = "sneakers"
    case ботинки = "boots"
    case сумка = "bag"
    case шапка = "hat"
    case шарф = "scarf"
    case аксессуар = "accessory"
    case другое = "other"

    var значок: String {
        switch self {
        case .футболка, .рубашка, .свитер, .худи, .спорт: return "tshirt"
        case .пиджак, .куртка, .пальто, .костюм: return "jacket"
        case .платье, .юбка: return "figure.dress.line.vertical.figure"
        case .брюки, .джинсы, .шорты: return "rectangle.portrait.split.2x1"
        case .обувь, .кроссовки, .ботинки: return "shoeprints.fill"
        case .сумка: return "handbag"
        case .шапка: return "crown"
        case .шарф: return "wind"
        case .аксессуар: return "eyeglasses"
        case .другое: return "hanger"
        }
    }

    var название: String { МоёText.т("my_wk_" + rawValue) }

    var слой: СлойГардеробаМоего {
        switch self {
        case .футболка, .рубашка, .свитер, .худи, .спорт: return .верх
        case .брюки, .джинсы, .шорты, .юбка: return .низ
        case .платье, .костюм: return .целиком
        case .пиджак, .куртка, .пальто: return .верхняя
        case .обувь, .кроссовки, .ботинки: return .обувь
        case .сумка, .шапка, .шарф, .аксессуар, .другое: return .аксессуар
        }
    }

    /// Виды размера «Моего», которыми меряют вещь (чип размера с биркой всех систем).
    var видыРазмера: [ВидРазмераМоего] {
        switch слой {
        case .верх, .целиком, .верхняя: return [.одеждаЖ, .одеждаМ]
        case .низ: return self == .джинсы ? [.джинсыЖ, .джинсыМ] : [.одеждаЖ, .одеждаМ, .джинсыЖ, .джинсыМ]
        case .обувь: return [.обувьЖ, .обувьМ]
        case .аксессуар: return self == .шапка ? [.шапка] : []
        }
    }

    /// Вид по словам названия («Куртка Zara M» → куртка); не узнали — nil.
    static func поНазванию(_ название: String) -> ВидВещиГардеробаМоего? {
        let н = название.lowercased().replacingOccurrences(of: "ё", with: "е")
        let слова: [(String, ВидВещиГардеробаМоего)] = [
            ("кроссовк", .кроссовки), ("кеды", .кроссовки), ("sneaker", .кроссовки), ("ботин", .ботинки),
            ("сапог", .ботинки), ("boots", .ботинки), ("туфл", .обувь), ("сандал", .обувь), ("лофер", .обувь),
            ("shoes", .обувь), ("футболк", .футболка), ("поло", .футболка), ("t-shirt", .футболка),
            ("рубашк", .рубашка), ("блуз", .рубашка), ("shirt", .рубашка), ("свитер", .свитер), ("джемпер", .свитер),
            ("кардиган", .свитер), ("водолазк", .свитер), ("худи", .худи), ("толстовк", .худи), ("свитшот", .худи),
            ("hoodie", .худи), ("пиджак", .пиджак), ("жакет", .пиджак), ("blazer", .пиджак), ("пуховик", .куртка),
            ("куртк", .куртка), ("ветровк", .куртка), ("jacket", .куртка), ("пальто", .пальто), ("плащ", .пальто),
            ("тренч", .пальто), ("шуба", .пальто), ("coat", .пальто), ("платье", .платье), ("сарафан", .платье),
            ("dress", .платье), ("юбк", .юбка), ("skirt", .юбка), ("джинс", .джинсы), ("jeans", .джинсы),
            ("брюк", .брюки), ("штаны", .брюки), ("trousers", .брюки), ("шорт", .шорты), ("shorts", .шорты),
            ("костюм", .костюм), ("suit", .костюм), ("спортивн", .спорт), ("легинс", .спорт), ("сумк", .сумка),
            ("рюкзак", .сумка), ("клатч", .сумка), ("bag", .сумка), ("шапк", .шапка), ("кепк", .шапка),
            ("бейсболк", .шапка), ("панам", .шапка), ("шарф", .шарф), ("платок", .шарф), ("ремень", .аксессуар),
            ("очки", .аксессуар), ("перчатк", .аксессуар), ("часы", .аксессуар)
        ]
        return слова.first { н.contains($0.0) }?.1
    }
}

/// Сезон вещи — по желанию.
enum СезонВещиМоего: String, Codable, CaseIterable, Sendable {
    case лето = "summer"
    case демисезон = "demi"
    case зима = "winter"
    case всесезон = "all"

    var название: String { МоёText.т("my_season_" + rawValue) }
}

/// Вещь гардероба: вид, своё название, цвета, размер своей системы, бренд, заметка, сезон, фото, покупка.
struct ВещьГардеробаМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var вид: ВидВещиГардеробаМоего
    var имя: String
    /// До двух цветов палитры.
    var цвета: [ЦветСтандарта]
    /// Цвет определён по фото сам (до первой правки руками).
    var цветСам: Bool
    var размер: РазмерМоего?
    var бренд: String
    /// «Сидит свободно», «садится после стирки» — до 120 знаков.
    var заметка: String
    var сезон: СезонВещиМоего?
    /// Фото вещи (вырезка — «<uuid>.png» с прозрачным фоном).
    var фото: ФотоМоего?
    /// Обложка объявления, если вещь куплена на Kliko (адрес сайта), — пока своего фото нет.
    var адресФото: String?
    var покупка: ПокупкаМоего?
    var добавлена: Date

    static let пределИмени = 40
    static let пределБренда = 30
    static let пределЗаметки = 120

    enum CodingKeys: String, CodingKey {
        case id
        case вид = "kind"
        case имя = "name"
        case цвета = "colors"
        case цветСам = "auto_color"
        case размер = "size"
        case бренд = "brand"
        case заметка = "note"
        case сезон = "season"
        case фото = "photo"
        case адресФото = "img"
        case покупка = "bought"
        case добавлена = "at"
    }

    init(id: UUID = UUID(), вид: ВидВещиГардеробаМоего, имя: String = "", цвета: [ЦветСтандарта] = [],
         цветСам: Bool = false, размер: РазмерМоего? = nil, бренд: String = "", заметка: String = "",
         сезон: СезонВещиМоего? = nil, фото: ФотоМоего? = nil, адресФото: String? = nil, покупка: ПокупкаМоего? = nil,
         добавлена: Date = Date()) {
        self.id = id
        self.вид = вид
        self.имя = имя
        self.цвета = цвета
        self.цветСам = цветСам
        self.размер = размер
        self.бренд = бренд
        self.заметка = заметка
        self.сезон = сезон
        self.фото = фото
        self.адресФото = адресФото
        self.покупка = покупка
        self.добавлена = добавлена
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        вид = к.значениеМоего(ВидВещиГардеробаМоего.self, .вид) ?? .другое
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(Self.пределИмени))
        цвета = ЦветСтандарта.из(к.значениеМоего([String].self, .цвета) ?? [])
        цветСам = к.значениеМоего(Bool.self, .цветСам) ?? false
        размер = к.значениеМоего(РазмерМоего.self, .размер)
        бренд = String((к.значениеМоего(String.self, .бренд) ?? "").prefix(Self.пределБренда))
        заметка = String((к.значениеМоего(String.self, .заметка) ?? "").prefix(Self.пределЗаметки))
        сезон = к.значениеМоего(СезонВещиМоего.self, .сезон)
        фото = к.значениеМоего(ФотоМоего.self, .фото)
        адресФото = к.значениеМоего(String.self, .адресФото).flatMap { $0.count <= 500 ? $0 : nil }
        покупка = к.значениеМоего(ПокупкаМоего.self, .покупка)
        добавлена = к.значениеМоего(Date.self, .добавлена) ?? Date()
    }

    /// Своё название, иначе «Zara · Куртка», иначе вид.
    var заголовок: String {
        let своё = имя.trimmingCharacters(in: .whitespacesAndNewlines)
        if !своё.isEmpty { return своё }
        let б = бренд.trimmingCharacters(in: .whitespacesAndNewlines)
        return б.isEmpty ? вид.название : б + " · " + вид.название
    }

    /// Сочетается ли по цвету с другой вещью (нет цвета — да: не отсекаем).
    func сочетается(с другой: ВещьГардеробаМоего) -> Bool {
        guard let мой = цвета.first, let его = другой.цвета.first else { return true }
        return мой.сочетается(с: его)
    }

    mutating func нормализовать() {
        имя = String(имя.prefix(Self.пределИмени))
        бренд = String(бренд.prefix(Self.пределБренда))
        заметка = String(заметка.prefix(Self.пределЗаметки))
        цвета = ЦветСтандарта.из(цвета.map(\.rawValue))
    }
}

/// Образ: своё название и вещи (до 12), фото по желанию.
struct ОбразМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var имя: String
    var вещи: [UUID]
    var фото: ФотоМоего?
    var создан: Date

    static let пределВещей = 12

    enum CodingKeys: String, CodingKey {
        case id
        case имя = "name"
        case вещи = "items"
        case фото = "photo"
        case создан = "at"
    }

    init(id: UUID = UUID(), имя: String = "", вещи: [UUID] = [], фото: ФотоМоего? = nil, создан: Date = Date()) {
        self.id = id
        self.имя = имя
        self.вещи = вещи
        self.фото = фото
        self.создан = создан
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(40))
        var номера = Set<UUID>()
        вещи = Array((к.значениеМоего([UUID].self, .вещи) ?? []).filter { номера.insert($0).inserted }
            .prefix(Self.пределВещей))
        фото = к.значениеМоего(ФотоМоего.self, .фото)
        создан = к.значениеМоего(Date.self, .создан) ?? Date()
    }
}

/// Как сидит вещь бренда: мала, впору, велика (те же ключи, что «Подошло?» сервера: small, ok, large).
enum ПосадкаВещиМоего: String, Codable, CaseIterable, Sendable {
    case мала = "small"
    case впору = "ok"
    case велика = "large"

    var название: String { МоёText.т("my_fit_" + rawValue) }
}

/// Заметка посадки: «Zara M — мала в плечах», «Nike EU 43 — впору».
struct ЗаметкаПосадкиМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var бренд: String
    var вид: ВидРазмераМоего?
    /// Размер как на бирке: «M», «EU 43», «W32 L32».
    var размер: String
    var посадка: ПосадкаВещиМоего
    /// Где мала или велика: «в плечах» — до 60 знаков.
    var текст: String
    var когда: Date

    enum CodingKeys: String, CodingKey {
        case id
        case бренд = "brand"
        case вид = "kind"
        case размер = "size"
        case посадка = "fit"
        case текст = "text"
        case когда = "at"
    }

    init(id: UUID = UUID(), бренд: String, вид: ВидРазмераМоего? = nil, размер: String, посадка: ПосадкаВещиМоего,
         текст: String = "", когда: Date = Date()) {
        self.id = id
        self.бренд = бренд
        self.вид = вид
        self.размер = размер
        self.посадка = посадка
        self.текст = текст
        self.когда = когда
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        бренд = try String(к.decode(String.self, forKey: .бренд).prefix(30))
        вид = к.значениеМоего(ВидРазмераМоего.self, .вид)
        размер = String((к.значениеМоего(String.self, .размер) ?? "").prefix(16))
        посадка = к.значениеМоего(ПосадкаВещиМоего.self, .посадка) ?? .впору
        текст = String((к.значениеМоего(String.self, .текст) ?? "").prefix(60))
        когда = к.значениеМоего(Date.self, .когда) ?? Date()
    }

    /// «Zara M — мала в плечах».
    var подпись: String {
        /* По шагам с явными типами: склейка с тернарником в одном выражении — риск проверки типов в CI. */
        let хвост: String = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        let начало: String = бренд + " " + размер + " — " + посадка.название
        return хвост.isEmpty ? начало : начало + " " + хвост
    }
}

struct ГардеробМоего: Codable, Equatable, Sendable {
    var вещи: [ВещьГардеробаМоего]
    var образы: [ОбразМоего]
    var посадка: [ЗаметкаПосадкиМоего]

    static let пределВещей = 300
    static let пределОбразов = 50
    static let пределЗаметок = 60

    enum CodingKeys: String, CodingKey {
        case вещи = "items"
        case образы = "outfits"
        case посадка = "fit"
    }

    init() {
        вещи = []
        образы = []
        посадка = []
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        var номера = Set<UUID>()
        вещи = Array(к.списокМоего(ВещьГардеробаМоего.self, .вещи).filter { номера.insert($0.id).inserted }
            .prefix(Self.пределВещей))
        образы = Array(к.списокМоего(ОбразМоего.self, .образы).filter { номера.insert($0.id).inserted }
            .prefix(Self.пределОбразов))
        посадка = Array(к.списокМоего(ЗаметкаПосадкиМоего.self, .посадка).filter { номера.insert($0.id).inserted }
            .prefix(Self.пределЗаметок))
        убратьПотерянные()
    }

    var пусто: Bool { вещи.isEmpty && образы.isEmpty && посадка.isEmpty }

    func вещь(_ id: UUID) -> ВещьГардеробаМоего? { вещи.first { $0.id == id } }

    /// Вещи образа по порядку (удалённые пропускаются).
    func вещиОбраза(_ образ: ОбразМоего) -> [ВещьГардеробаМоего] { образ.вещи.compactMap { вещь($0) } }

    /// Заметки посадки бренда — «у Zara беру L».
    func заметки(бренда бренд: String) -> [ЗаметкаПосадкиМоего] {
        let б = бренд.trimmingCharacters(in: .whitespaces).lowercased()
        guard !б.isEmpty else { return [] }
        return посадка.filter { $0.бренд.lowercased() == б }
    }

    /// Свои вещи, которые сочетаются с этой по цвету (сама — не в списке).
    func сЧемНосить(_ вещь: ВещьГардеробаМоего) -> [ВещьГардеробаМоего] {
        вещи.filter { $0.id != вещь.id && $0.вид.слой != вещь.вид.слой && $0.сочетается(с: вещь) }
    }

    /// Цвета всего гардероба по частоте — для «с чем носить» в «Для вас».
    var частыеЦвета: [ЦветСтандарта] {
        /* Циклы и сортировка с явной сигнатурой: reduce и sorted с тернарником по кортежам — риск проверки типов в CI.
           Порядок прежний: чаще — раньше, при равенстве — по rawValue. */
        var счёт: [ЦветСтандарта: Int] = [:]
        for в in вещи {
            for цвет in в.цвета { счёт[цвет, default: 0] += 1 }
        }
        let порядок: [(key: ЦветСтандарта, value: Int)] = счёт.sorted {
            (а: (key: ЦветСтандарта, value: Int), б: (key: ЦветСтандарта, value: Int)) -> Bool in
            if а.value != б.value { return а.value > б.value }
            return а.key.rawValue < б.key.rawValue
        }
        return порядок.map { (пара: (key: ЦветСтандарта, value: Int)) -> ЦветСтандарта in пара.key }
    }

    /// Образы без удалённых вещей.
    private mutating func убратьПотерянные() {
        let есть = Set(вещи.map(\.id))
        for i in образы.indices { образы[i].вещи.removeAll { !есть.contains($0) } }
    }

    mutating func нормализовать() {
        var номера = Set<UUID>()
        вещи = Array(вещи.filter { номера.insert($0.id).inserted }.prefix(Self.пределВещей))
        образы = Array(образы.filter { номера.insert($0.id).inserted }.prefix(Self.пределОбразов))
        посадка = Array(посадка.filter { номера.insert($0.id).inserted }.prefix(Self.пределЗаметок))
        for i in вещи.indices { вещи[i].нормализовать() }
        for i in образы.indices {
            образы[i].имя = String(образы[i].имя.prefix(40))
            var свои = Set<UUID>()
            образы[i].вещи = Array(образы[i].вещи.filter { свои.insert($0).inserted }.prefix(ОбразМоего.пределВещей))
        }
        убратьПотерянные()
    }

    /// Имена фото гардероба (для уборки файлов).
    var файлыФото: [String] {
        (вещи.compactMap(\.фото) + образы.compactMap(\.фото)).flatMap { [$0.файл, $0.мини] }
    }
}
