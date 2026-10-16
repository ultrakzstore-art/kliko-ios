import Foundation

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР / НОУТБУК»: МОДЕЛЬ (владелец 16.10.2026: «мой компьютер — видюха или ОЗУ; подсказывать — можно
 так или так; показывать, что был куплен там — цифровизация реальности»; docs/STANDARDS.md §3.5, §6.5, §8.1).

 Компьютер — набор стандартов, а не анкета: процессор и сокет (AM4, LGA1700, BGA у ноутбуков), чипсет и TDP; память
 (поколение, форма, частота, планки по слотам, всего слотов, максимум, распаяно); видеокарта (чип, память, длина,
 питание); блок питания (ватты, форма, 80 PLUS); корпус (наибольшая плата, длина видеокарты, высота кулера); слоты M.2
 (длина, NVMe / SATA, поколение PCIe) и отсеки 2.5″; накопители. Неизвестное — nil («не знаю»), а не ноль. Значения —
 каноном каталога (КаталогСтандартов): «DDR4», «SO-DIMM», «2280», «nvme».

 История — короткие события («куплено на Kliko», «поставили 8 ГБ»), до 50; покупка — откуда компьютер (ПокупкаМоего).
 Сверка с объявлениями — StandardsMatch.swift (ОЗУ, накопитель, видеокарта, БП, сокет, плата); подсказки апгрейда
 считает экран «Моего компьютера» на тех же правилах. Только на телефоне (МоёХранилище.обновитьКомпьютер).
 */

enum ВидКомпьютераМоего: String, Codable, CaseIterable, Sendable {
    case настольный = "desktop"
    case ноутбук = "laptop"

    var значок: String { self == .ноутбук ? "laptopcomputer" : "desktopcomputer" }

    var название: String { МоёText.т("my_pc_" + rawValue) }
}

/// Оперативная память: поколение и форма каноном, частота МТ/с, планки по слотам (ГБ), слотов, максимум, распаяно.
struct ПамятьКомпьютераМоего: Codable, Equatable, Sendable {
    var поколение: String?
    var форма: String?
    var частота: Int?
    /// ГБ каждой вставленной планки — по слотам.
    var планки: [Int]
    /// Всего слотов (у ноутбука с распаянной памятью — 0 или 1).
    var слотов: Int?
    /// Максимум платы, ГБ.
    var максимум: Int?
    /// Распаяно на плате, ГБ.
    var распаяно: Int?

    enum CodingKeys: String, CodingKey {
        case поколение = "gen"
        case форма = "form"
        case частота = "mts"
        case планки = "sticks"
        case слотов = "slots"
        case максимум = "max"
        case распаяно = "soldered"
    }

    init(поколение: String? = nil, форма: String? = nil, частота: Int? = nil, планки: [Int] = [], слотов: Int? = nil,
         максимум: Int? = nil, распаяно: Int? = nil) {
        self.поколение = поколение
        self.форма = форма
        self.частота = частота
        self.планки = планки
        self.слотов = слотов
        self.максимум = максимум
        self.распаяно = распаяно
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        поколение = к.значениеМоего(String.self, .поколение)
            .flatMap { КаталогСтандартов.поколенияПамяти.contains($0) ? $0 : nil }
        форма = к.значениеМоего(String.self, .форма)
            .flatMap { КаталогСтандартов.формыПамяти.contains($0) || $0 == "soldered" ? $0 : nil }
        частота = к.значениеМоего(Int.self, .частота).flatMap { (800...12000).contains($0) ? $0 : nil }
        планки = Array((к.значениеМоего([Int].self, .планки) ?? []).filter { (1...256).contains($0) }.prefix(8))
        слотов = к.значениеМоего(Int.self, .слотов).flatMap { (0...8).contains($0) ? $0 : nil }
        максимум = к.значениеМоего(Int.self, .максимум).flatMap { (2...2048).contains($0) ? $0 : nil }
        распаяно = к.значениеМоего(Int.self, .распаяно).flatMap { (1...256).contains($0) ? $0 : nil }
    }

    /// Всего памяти, ГБ: планки и распаянное; ничего не знаем — nil.
    var всего: Int? {
        let сумма = планки.reduce(0, +) + (распаяно ?? 0)
        return сумма > 0 ? сумма : nil
    }

    /// Свободных слотов; слотов не знаем — nil.
    var свободно: Int? { слотов.map { max(0, $0 - планки.count) } }

    /// Вся память распаяна — добавить нельзя (LPDDR, «слотов 0»).
    var всяРаспаяна: Bool {
        if let п = поколение, КаталогСтандартов.распаянныеПоколения.contains(п) { return true }
        return форма == "soldered" || (слотов == 0 && (распаяно ?? 0) > 0)
    }

    /// Хватает для сверки планки: поколение, форма и слоты (или «распаяна»).
    var известна: Bool { всяРаспаяна || (поколение != nil && форма != nil) }

    mutating func нормализовать() {
        планки = Array(планки.filter { (1...256).contains($0) }.prefix(8))
        if let с = слотов, !(0...8).contains(с) { слотов = nil }
        if let с = слотов, планки.count > с { слотов = планки.count }
    }
}

/// Видеокарта: чип каноном («RTX 4060», «RX 7800 XT»), память ГБ, длина мм, разъём питания; встроенная — без карты.
struct ВидеокартаМоего: Codable, Equatable, Sendable {
    var чип: String?
    var памятьГБ: Int?
    var длина: Int?
    var питание: String?
    /// Только встроенная графика (у ноутбука и мини-ПК).
    var встроенная: Bool

    enum CodingKeys: String, CodingKey {
        case чип = "chip"
        case памятьГБ = "vram"
        case длина = "len"
        case питание = "power"
        case встроенная = "igpu"
    }

    init(чип: String? = nil, памятьГБ: Int? = nil, длина: Int? = nil, питание: String? = nil, встроенная: Bool = false) {
        self.чип = чип
        self.памятьГБ = памятьГБ
        self.длина = длина
        self.питание = питание
        self.встроенная = встроенная
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        чип = к.значениеМоего(String.self, .чип).map { String($0.prefix(40)) }
        памятьГБ = к.значениеМоего(Int.self, .памятьГБ).flatMap { (1...64).contains($0) ? $0 : nil }
        длина = к.значениеМоего(Int.self, .длина).flatMap { (60...450).contains($0) ? $0 : nil }
        питание = к.значениеМоего(String.self, .питание)
            .flatMap { КаталогСтандартов.разъёмыПитанияКарт.contains($0) ? $0 : nil }
        встроенная = к.значениеМоего(Bool.self, .встроенная) ?? false
    }

    var пусто: Bool { чип == nil && памятьГБ == nil && длина == nil && питание == nil && !встроенная }
}

/// Блок питания: ватты, форма, сертификат 80 PLUS.
struct БлокПитанияМоего: Codable, Equatable, Sendable {
    var ватт: Int?
    var форма: String?
    var сертификат: String?

    enum CodingKeys: String, CodingKey {
        case ватт = "w"
        case форма = "form"
        case сертификат = "cert"
    }

    init(ватт: Int? = nil, форма: String? = nil, сертификат: String? = nil) {
        self.ватт = ватт
        self.форма = форма
        self.сертификат = сертификат
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        ватт = к.значениеМоего(Int.self, .ватт).flatMap { (150...3000).contains($0) ? $0 : nil }
        форма = к.значениеМоего(String.self, .форма).flatMap { КаталогСтандартов.формыБП.contains($0) ? $0 : nil }
        сертификат = к.значениеМоего(String.self, .сертификат)
            .flatMap { КаталогСтандартов.сертификатыБП.contains($0) ? $0 : nil }
    }

    var пусто: Bool { ватт == nil && форма == nil && сертификат == nil }
}

/// Корпус: наибольшая плата, длина видеокарты и высота кулера — пределы, мм.
struct КорпусМоего: Codable, Equatable, Sendable {
    var плата: String?
    var длинаКарты: Int?
    var высотаКулера: Int?

    enum CodingKeys: String, CodingKey {
        case плата = "board"
        case длинаКарты = "gpu"
        case высотаКулера = "cooler"
    }

    init(плата: String? = nil, длинаКарты: Int? = nil, высотаКулера: Int? = nil) {
        self.плата = плата
        self.длинаКарты = длинаКарты
        self.высотаКулера = высотаКулера
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        плата = к.значениеМоего(String.self, .плата).flatMap { КаталогСтандартов.ранг(формы: $0) != nil ? $0 : nil }
        длинаКарты = к.значениеМоего(Int.self, .длинаКарты).flatMap { (100...600).contains($0) ? $0 : nil }
        высотаКулера = к.значениеМоего(Int.self, .высотаКулера).flatMap { (20...250).contains($0) ? $0 : nil }
    }

    var пусто: Bool { плата == nil && длинаКарты == nil && высотаКулера == nil }
}

/// Слот M.2: наибольшая длина («2280»), протокол («nvme», «sata», «both»), поколение PCIe, занят ли.
struct СлотM2Моего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var длина: String
    var протокол: String
    var pcie: Int?
    var занят: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case длина = "len"
        case протокол = "proto"
        case pcie
        case занят = "used"
    }

    init(id: UUID = UUID(), длина: String = "2280", протокол: String = "nvme", pcie: Int? = nil, занят: Bool = false) {
        self.id = id
        self.длина = длина
        self.протокол = протокол
        self.pcie = pcie
        self.занят = занят
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        длина = к.значениеМоего(String.self, .длина).flatMap { КаталогСтандартов.формыM2.contains($0) ? $0 : nil } ?? "2280"
        протокол = к.значениеМоего(String.self, .протокол).flatMap { ["nvme", "sata", "both"].contains($0) ? $0 : nil }
            ?? "nvme"
        pcie = к.значениеМоего(Int.self, .pcie).flatMap { (2...6).contains($0) ? $0 : nil }
        занят = к.значениеМоего(Bool.self, .занят) ?? false
    }
}

/// Накопитель: форма («2280», «2.5», «3.5»), протокол («nvme», «sata»), поколение PCIe, объём ТБ.
struct НакопительМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var форма: String
    var протокол: String?
    var pcie: Int?
    var тб: Double?
    /// Жёсткий диск (HDD), а не SSD.
    var hdd: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case форма = "form"
        case протокол = "proto"
        case pcie
        case тб = "tb"
        case hdd
    }

    init(id: UUID = UUID(), форма: String = "2280", протокол: String? = "nvme", pcie: Int? = nil, тб: Double? = nil,
         hdd: Bool = false) {
        self.id = id
        self.форма = форма
        self.протокол = протокол
        self.pcie = pcie
        self.тб = тб
        self.hdd = hdd
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        форма = к.значениеМоего(String.self, .форма)
            .flatMap { (КаталогСтандартов.формыM2 + КаталогСтандартов.формыДисков).contains($0) ? $0 : nil } ?? "2280"
        протокол = к.значениеМоего(String.self, .протокол).flatMap { КаталогСтандартов.протоколы.contains($0) ? $0 : nil }
        pcie = к.значениеМоего(Int.self, .pcie).flatMap { (2...6).contains($0) ? $0 : nil }
        тб = к.значениеМоего(Double.self, .тб).flatMap { $0 > 0 && $0 <= 64 ? $0 : nil }
        hdd = к.значениеМоего(Bool.self, .hdd) ?? false
    }
}

/// Событие истории: когда, что (ключ: bought, installed, removed, edited), текст («Куплено на Kliko · ОЗУ 8 ГБ»).
struct СобытиеКомпьютераМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var когда: Date
    var что: String
    var текст: String

    enum CodingKeys: String, CodingKey {
        case id
        case когда = "at"
        case что = "ev"
        case текст = "text"
    }

    init(id: UUID = UUID(), когда: Date = Date(), что: String, текст: String) {
        self.id = id
        self.когда = когда
        self.что = что
        self.текст = String(текст.prefix(120))
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        когда = к.значениеМоего(Date.self, .когда) ?? Date()
        что = String((к.значениеМоего(String.self, .что) ?? "edited").prefix(20))
        текст = String((к.значениеМоего(String.self, .текст) ?? "").prefix(120))
    }
}

/// Компьютер или ноутбук «Моего»: компоненты по стандартам, покупка и история.
struct КомпьютерМоего: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var вид: ВидКомпьютераМоего
    /// Своё название («Игровой», «Рабочий ноутбук») — до 30 знаков.
    var имя: String
    /// Модель ноутбука или материнской платы: «Lenovo IdeaPad 5 14ALC05», «B550M DS3H».
    var модель: String
    /// Процессор как в «Диспетчере задач»: «Ryzen 5 5600», «Core i5-12400F», «Apple M2».
    var процессор: String
    var сокет: String?
    var чипсет: String?
    /// TDP процессора, Вт — для расчёта БП.
    var tdp: Int?
    var память: ПамятьКомпьютераМоего
    var видеокарта: ВидеокартаМоего
    var бп: БлокПитанияМоего
    var корпус: КорпусМоего
    var слотыM2: [СлотM2Моего]
    /// Отсеков 2.5″ (у ноутбука обычно 0 или 1).
    var отсеков25: Int?
    var накопители: [НакопительМоего]
    /// Связь с ноутбуком «Моих устройств» (диагональ, габариты), по желанию.
    var устройство: UUID?
    var покупка: ПокупкаМоего?
    var история: [СобытиеКомпьютераМоего]
    var создан: Date

    static let пределИмени = 30
    static let пределИстории = 50

    enum CodingKeys: String, CodingKey {
        case id
        case вид = "kind"
        case имя = "name"
        case модель = "model"
        case процессор = "cpu"
        case сокет = "socket"
        case чипсет = "chipset"
        case tdp
        case память = "ram"
        case видеокарта = "gpu"
        case бп = "psu"
        case корпус = "case"
        case слотыM2 = "m2"
        case отсеков25 = "bays"
        case накопители = "drives"
        case устройство = "dev"
        case покупка = "bought"
        case история = "history"
        case создан = "at"
    }

    init(id: UUID = UUID(), вид: ВидКомпьютераМоего, имя: String = "", модель: String = "", процессор: String = "",
         сокет: String? = nil, чипсет: String? = nil, tdp: Int? = nil, память: ПамятьКомпьютераМоего = .init(),
         видеокарта: ВидеокартаМоего = .init(), бп: БлокПитанияМоего = .init(), корпус: КорпусМоего = .init(),
         слотыM2: [СлотM2Моего] = [], отсеков25: Int? = nil, накопители: [НакопительМоего] = [],
         устройство: UUID? = nil, покупка: ПокупкаМоего? = nil, история: [СобытиеКомпьютераМоего] = [],
         создан: Date = Date()) {
        self.id = id
        self.вид = вид
        self.имя = имя
        self.модель = модель
        self.процессор = процессор
        self.сокет = сокет
        self.чипсет = чипсет
        self.tdp = tdp
        self.память = память
        self.видеокарта = видеокарта
        self.бп = бп
        self.корпус = корпус
        self.слотыM2 = слотыM2
        self.отсеков25 = отсеков25
        self.накопители = накопители
        self.устройство = устройство
        self.покупка = покупка
        self.история = история
        self.создан = создан
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        id = к.значениеМоего(UUID.self, .id) ?? UUID()
        вид = к.значениеМоего(ВидКомпьютераМоего.self, .вид) ?? .настольный
        имя = String((к.значениеМоего(String.self, .имя) ?? "").prefix(Self.пределИмени))
        модель = String((к.значениеМоего(String.self, .модель) ?? "").prefix(80))
        процессор = String((к.значениеМоего(String.self, .процессор) ?? "").prefix(60))
        сокет = к.значениеМоего(String.self, .сокет).flatMap { КаталогСтандартов.сокет($0)?.код }
        чипсет = к.значениеМоего(String.self, .чипсет).map { String($0.prefix(10)) }
        tdp = к.значениеМоего(Int.self, .tdp).flatMap { (5...500).contains($0) ? $0 : nil }
        память = к.значениеМоего(ПамятьКомпьютераМоего.self, .память) ?? ПамятьКомпьютераМоего()
        видеокарта = к.значениеМоего(ВидеокартаМоего.self, .видеокарта) ?? ВидеокартаМоего()
        бп = к.значениеМоего(БлокПитанияМоего.self, .бп) ?? БлокПитанияМоего()
        корпус = к.значениеМоего(КорпусМоего.self, .корпус) ?? КорпусМоего()
        слотыM2 = Array(к.списокМоего(СлотM2Моего.self, .слотыM2).prefix(6))
        отсеков25 = к.значениеМоего(Int.self, .отсеков25).flatMap { (0...12).contains($0) ? $0 : nil }
        накопители = Array(к.списокМоего(НакопительМоего.self, .накопители).prefix(12))
        устройство = к.значениеМоего(UUID.self, .устройство)
        покупка = к.значениеМоего(ПокупкаМоего.self, .покупка)
        история = Array(к.списокМоего(СобытиеКомпьютераМоего.self, .история).suffix(Self.пределИстории))
        создан = к.значениеМоего(Date.self, .создан) ?? Date()
    }

    /// Своё название, иначе модель, иначе «Мой компьютер» / «Мой ноутбук».
    var заголовок: String {
        let своё = имя.trimmingCharacters(in: .whitespacesAndNewlines)
        if !своё.isEmpty { return своё }
        let м = модель.trimmingCharacters(in: .whitespacesAndNewlines)
        if !м.isEmpty { return м }
        return МоёText.т(вид == .ноутбук ? "my_pc_my_laptop" : "my_pc_my_desktop")
    }

    /// Сокет: свой, иначе по чипсету, у ноутбука — BGA.
    var сокетДляСверки: String? {
        сокет ?? КаталогСтандартов.сокет(чипсета: чипсет) ?? (вид == .ноутбук ? "BGA" : nil)
    }

    /// Свободный слот M.2; нет — nil.
    var свободныйM2: СлотM2Моего? { слотыM2.first { !$0.занят } }

    /// Добавить событие истории (старые уходят за пределом).
    mutating func записать(_ что: String, _ текст: String, когда: Date = Date()) {
        история.append(СобытиеКомпьютераМоего(когда: когда, что: что, текст: текст))
        if история.count > Self.пределИстории { история.removeFirst(история.count - Self.пределИстории) }
    }

    /// Что известно — для прогресса и сводки: процессор, память, накопитель, «железо» корпуса.
    var естьПроцессор: Bool { !процессор.trimmingCharacters(in: .whitespaces).isEmpty || сокет != nil }
    var естьПамять: Bool { память.известна && (память.всяРаспаяна || память.слотов != nil) }
    var естьНакопитель: Bool { !накопители.isEmpty || !слотыM2.isEmpty }
    var естьЖелезо: Bool {
        вид == .ноутбук ? !модель.trimmingCharacters(in: .whitespaces).isEmpty
            : (!видеокарта.пусто || !бп.пусто || !корпус.пусто)
    }

    /// «Ryzen 5 5600 · 16 ГБ DDR4 · RTX 3060 · SSD 1 ТБ».
    var сводка: String {
        var части: [String] = []
        let цп = процессор.trimmingCharacters(in: .whitespaces)
        if !цп.isEmpty { части.append(цп) } else if let с = сокетДляСверки, с != "BGA" { части.append(с) }
        if let всего = память.всего {
            части.append(String(всего) + " " + СтандартыText.т("u_gb") + (память.поколение.map { " " + $0 } ?? ""))
        } else if let п = память.поколение {
            части.append(п + (память.форма.map { " " + $0 } ?? ""))
        }
        if let чип = видеокарта.чип { части.append(чип) }
        if let н = накопители.first, let тб = н.тб {
            let объём = тб < 1 ? ЧислоМоего.ч(тб * 1000, знаков: 0) + " " + СтандартыText.т("u_gb")
                : ЧислоМоего.ч(тб) + " " + СтандартыText.т("u_tb")
            части.append((н.hdd ? "HDD " : "SSD ") + объём)
        }
        return части.joined(separator: " · ")
    }

    mutating func нормализовать() {
        имя = String(имя.prefix(Self.пределИмени))
        модель = String(модель.prefix(80))
        процессор = String(процессор.prefix(60))
        if let с = сокет { сокет = КаталогСтандартов.сокет(с)?.код }
        память.нормализовать()
        var номера = Set<UUID>()
        слотыM2 = Array(слотыM2.filter { номера.insert($0.id).inserted }.prefix(6))
        накопители = Array(накопители.filter { номера.insert($0.id).inserted }.prefix(12))
        if история.count > Self.пределИстории { история = Array(история.suffix(Self.пределИстории)) }
    }
}

// MARK: - Шаблоны

/// Шаблон компьютера: касание заполняет частое («Ноутбук · 8 ГБ DDR4 3200, 2 слота», «ПК · AM4 · DDR4 · ATX»).
struct ШаблонКомпьютераМоего: Identifiable, Sendable {
    let id: String
    /// Ключ подписи в МоёText.
    let ключ: String
    let компьютер: @Sendable () -> КомпьютерМоего

    var подпись: String { МоёText.т(ключ) }

    static let все: [ШаблонКомпьютераМоего] = [
        ШаблонКомпьютераМоего(id: "laptop_ddr4", ключ: "my_pc_tpl_laptop_ddr4") {
            КомпьютерМоего(вид: .ноутбук, память: ПамятьКомпьютераМоего(поколение: "DDR4", форма: "SO-DIMM",
                                                                       частота: 3200, планки: [8], слотов: 2,
                                                                       максимум: 32),
                           слотыM2: [СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 3, занят: true)],
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 3, тб: 0.5)])
        },
        ШаблонКомпьютераМоего(id: "laptop_ddr5", ключ: "my_pc_tpl_laptop_ddr5") {
            КомпьютерМоего(вид: .ноутбук, память: ПамятьКомпьютераМоего(поколение: "DDR5", форма: "SO-DIMM",
                                                                       частота: 5600, планки: [8, 8], слотов: 2,
                                                                       максимум: 64),
                           слотыM2: [СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 4, занят: true)],
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 4, тб: 0.5)])
        },
        ШаблонКомпьютераМоего(id: "laptop_soldered", ключ: "my_pc_tpl_laptop_soldered") {
            КомпьютерМоего(вид: .ноутбук, память: ПамятьКомпьютераМоего(поколение: "LPDDR5", форма: "soldered",
                                                                       слотов: 0, распаяно: 8),
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 4, тб: 0.256)])
        },
        ШаблонКомпьютераМоего(id: "pc_am4", ключ: "my_pc_tpl_am4") {
            КомпьютерМоего(вид: .настольный, сокет: "AM4", tdp: 65,
                           память: ПамятьКомпьютераМоего(поколение: "DDR4", форма: "DIMM", частота: 3200,
                                                         планки: [8, 8], слотов: 4, максимум: 128),
                           бп: БлокПитанияМоего(ватт: 550, форма: "ATX"),
                           корпус: КорпусМоего(плата: "ATX", длинаКарты: 320),
                           слотыM2: [СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 3, занят: true)],
                           отсеков25: 2,
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 3, тб: 0.5)])
        },
        ШаблонКомпьютераМоего(id: "pc_lga1700", ключ: "my_pc_tpl_lga1700") {
            КомпьютерМоего(вид: .настольный, сокет: "LGA1700", tdp: 65,
                           память: ПамятьКомпьютераМоего(поколение: "DDR5", форма: "DIMM", частота: 5600,
                                                         планки: [16, 16], слотов: 4, максимум: 192),
                           бп: БлокПитанияМоего(ватт: 650, форма: "ATX"),
                           корпус: КорпусМоего(плата: "ATX", длинаКарты: 340),
                           слотыM2: [СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 4, занят: true),
                                     СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 4, занят: false)],
                           отсеков25: 2,
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 4, тб: 1)])
        },
        ШаблонКомпьютераМоего(id: "pc_am5", ключ: "my_pc_tpl_am5") {
            КомпьютерМоего(вид: .настольный, сокет: "AM5", tdp: 105,
                           память: ПамятьКомпьютераМоего(поколение: "DDR5", форма: "DIMM", частота: 6000,
                                                         планки: [16, 16], слотов: 4, максимум: 192),
                           бп: БлокПитанияМоего(ватт: 750, форма: "ATX"),
                           корпус: КорпусМоего(плата: "ATX", длинаКарты: 360),
                           слотыM2: [СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 4, занят: true),
                                     СлотM2Моего(длина: "2280", протокол: "nvme", pcie: 4, занят: false)],
                           отсеков25: 2,
                           накопители: [НакопительМоего(форма: "2280", протокол: "nvme", pcie: 4, тб: 1)])
        }
    ]
}
