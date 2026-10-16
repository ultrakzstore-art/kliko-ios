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

// MARK: - Вся запись

/// Всё «Моё» одним файлом my-things.json (до ~50 КБ).
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

    static let пределМашин = 5
    static let пределУстройств = 6
    static let нетНоутбука = "laptop"
    static let нетЭкрана = "screen"

    enum CodingKeys: String, CodingKey {
        case версия = "v"
        case машины = "cars"
        case главная = "main"
        case телефон = "phone"
        case устройства = "devices"
        case нет = "none"
        case тело = "body"
    }

    init() {
        версия = 1
        машины = []
        главная = nil
        телефон = nil
        устройства = []
        нет = []
        тело = ТелоМоего()
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
    }

    /// Главная машина; если отметка потерялась — первая.
    var главнаяМашина: МашинаМоего? {
        машины.first(where: { $0.id == главная }) ?? машины.first
    }

    var ноутбуки: [УстройствоМоего] { устройства.filter { $0.вид == .ноутбук } }
    var экраны: [УстройствоМоего] { устройства.filter { $0.вид != .ноутбук } }

    var пусто: Bool {
        машины.isEmpty && телефон == nil && устройства.isEmpty && нет.isEmpty && тело.пусто
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
