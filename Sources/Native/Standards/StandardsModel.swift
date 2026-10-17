import Foundation

/**
 СТАНДАРТЫ KLIKO НА ТЕЛЕФОНЕ — МОДЕЛЬ (docs/STANDARDS.md §2, §10; владелец 16.10.2026: «стандарты: по ним изи точечно
 подбирать, что почём; шаблоны»; раньше: «стандарты = удобство», «всё должно быть в одном ключе»).

 Стандарт — общий язык вещи, объявления и «Моего»: «160x200», «E27», «VESA 300x300», «DDR4 SO-DIMM 16 ГБ». Здесь —
 то, что нужно пачке «дом, компьютер, гардероб, для вас»:
   · СемьяСтандарта — ключи семей как в docs/SERVER_STANDARDS_catalog.json (навсегда, латиницей);
   · КлючСтандарта — имена полей семей (fields каталога);
   · НаборСтандартов — значения вещи или объявления: std + qty + std_src (§2.2), каноном каталога, а не номером ряда;
   · ИсточникСтандарта — откуда значение и выше какого уровня оно не поднимает;
   · ПунктСверкиСтандарта, ИтогСверкиСтандарта — итог сверки «моё ↔ объявление»: худший пункт и короткое «почему».
 Уровень — та же шкала из пяти, что у «Подойдут ли?» (УровеньАвтоподбора, TryOn/AutoFitMath.swift): второй шкалы нет.
 Чистые данные без сети и состояния: каталог — StandardsCatalog.swift, разбор объявления — StandardsNormalize.swift,
 сверка — StandardsMatch.swift, тексты — StandardsText.swift. Значения «Моего» не уходят на сервер.

 Из какого текста какой уровень (§1 п. 3, §2.2): поле характеристик и строка «Параметры: …» описания — слово продавца;
 стандарт, прямо названный в названии («E27», «160x200», «DDR4 SO-DIMM»), — тоже слово продавца, как «title» договора
 (так же «Подходит моему» v1 сверяет модель телефона по названию); прочее из свободного текста описания и всё выведенное
 (VESA по диагонали, кровать «двуспальная») — не выше «Проверьте».
 */
extension Config {
    /// Стандарты на телефоне: разбор объявлений и сверка с «Моим домом» и «Моим компьютером». false — сверка этих
    /// семей молчит, данные «Моего» не трогаются.
    static let стандарты = true
}

/// Уровень совпадения — та же шкала, что у «Подойдут ли?»: подходит, нужна деталь, неизвестно, проверьте, не подходит.
typealias УровеньСтандарта = УровеньАвтоподбора

// MARK: - Семьи

/// Группа семьи — ведёт в раздел «Моего».
enum ГруппаСтандарта: String, Sendable {
    case дом = "home"
    case текстиль = "textile"
    case свет = "light"
    case экран = "screen"
    case техника = "appliance"
    case пк = "pc"
    case одежда = "wear"
}

/// Семьи стандарта этой пачки. rawValue — ключ семьи каталога.
enum СемьяСтандарта: String, CaseIterable, Codable, Sendable {
    case спальноеМесто = "bed_size"
    case матрас = "mattress"
    case бельё = "bedding"
    case шторы = "curtain"
    case проём = "opening"
    case потолок = "ceiling_height"
    case цоколь = "lamp_base"
    case vesa = "vesa"
    case диагональ = "screen_diag"
    case расходник = "appliance_supply"
    case сокет = "cpu_socket"
    case память = "ram_module"
    case накопитель = "m2_ssd"
    case видеокарта = "gpu_card"
    case блокПитания = "psu"
    case формаПлаты = "board_form"
    case корпус = "case_limits"
    case размер = "size"

    var группа: ГруппаСтандарта {
        switch self {
        case .спальноеМесто, .матрас, .проём, .потолок: return .дом
        case .бельё, .шторы: return .текстиль
        case .цоколь: return .свет
        case .vesa, .диагональ: return .экран
        case .расходник: return .техника
        case .сокет, .память, .накопитель, .видеокарта, .блокПитания, .формаПлаты, .корпус: return .пк
        case .размер: return .одежда
        }
    }

    /// «Спальное место», «Цоколь»… на языке приложения.
    var название: String { СтандартыText.т("sf_" + rawValue) }

    /// SF Symbol семьи (iOS 17).
    var значок: String {
        switch self {
        case .спальноеМесто, .матрас: return "bed.double"
        case .бельё: return "square.stack.3d.down.forward"
        case .шторы: return "curtains.closed"
        case .проём: return "door.left.hand.open"
        case .потолок: return "arrow.up.and.down"
        case .цоколь: return "lightbulb"
        case .vesa, .диагональ: return "tv"
        case .расходник: return "drop"
        case .сокет: return "cpu"
        case .память: return "memorychip"
        case .накопитель: return "internaldrive"
        case .видеокарта: return "rectangle.3.group"
        case .блокПитания: return "bolt"
        case .формаПлаты, .корпус: return "pc"
        case .размер: return "tshirt"
        }
    }

    /// Главные поля (main каталога): без них у объявления — «Проверьте», в «Моём» — «Неизвестно».
    var главные: [String] {
        typealias К = КлючСтандарта
        switch self {
        case .спальноеМесто: return [К.размер]
        case .матрас: return [К.размер]
        case .бельё: return [К.комплект]
        case .шторы: return [К.высота]
        case .проём: return [К.проход]
        case .потолок: return [К.см]
        case .цоколь: return [К.цоколь]
        case .vesa: return [К.шаблон]
        case .диагональ: return [К.диагональ]
        case .расходник: return [К.коды]
        case .сокет: return [К.сокет]
        case .память: return [К.поколение, К.форма, К.гб]
        case .накопитель: return [К.форма, К.протокол]
        case .видеокарта: return [К.чип]
        case .блокПитания: return [К.ватт]
        case .формаПлаты: return [К.форма]
        case .корпус: return [К.длинаКарты]
        case .размер: return [К.таблица, К.значение]
        }
    }
}

/// Имена полей семей — как fields каталога (латиница, навсегда).
enum КлючСтандарта {
    static let размер = "size"
    static let высотаМатраса = "height_cm"
    static let видМатраса = "type"
    static let комплект = "set"
    static let одеяло = "duvet"
    static let пододеяльник = "duvet_cover"
    static let простыня = "sheet"
    static let наРезинке = "fitted"
    static let борт = "fitted_h"
    static let наволочка = "pillow"
    static let высота = "height_cm"
    static let ширина = "width_cm"
    static let видШтор = "kind"
    static let проход = "door_clear_cm"
    static let см = "cm"
    static let цоколь = "base"
    static let вольт = "volt"
    static let шаблон = "pattern"
    static let шаблоны = "patterns"
    static let доКг = "max_kg"
    static let диагональОт = "diag_min"
    static let диагональДо = "diag_max"
    static let диагональ = "diag"
    static let коды = "codes"
    static let сокет = "socket"
    static let чипсет = "chipset"
    static let процессор = "cpu"
    static let поколение = "gen"
    static let форма = "form"
    static let частота = "mts"
    static let гб = "gb"
    static let видПамяти = "kind"
    static let протокол = "proto"
    static let pcie = "pcie"
    static let тб = "tb"
    static let чип = "chip"
    static let памятьКарты = "vram_gb"
    static let длина = "length_mm"
    static let питание = "power_conn"
    static let ватт = "watts"
    static let сертификат = "cert"
    static let длинаКарты = "gpu_max_mm"
    static let таблица = "table"
    static let значение = "value"
}

// MARK: - Источник

/// Откуда значение (std_src договора §2.2).
enum ИсточникСтандарта: String, Codable, Sendable {
    /// Продавец: поле характеристик, строка «Параметры: …», выбранный чип; в «Моём» — введено человеком.
    case продавец = ""
    /// Прямо названо в названии объявления.
    case название = "title"
    /// Камера по маркировке, подтверждено.
    case камера = "scan"
    /// По модели из справочника.
    case модель = "model"
    /// Предложил Kliko AI, продавец подтвердил (docs/SERVER_STANDARDS.md §3.1: лучший уровень — «Подходит»).
    case ии = "ai"
    /// Выведено примерно (шаблон, диагональ → VESA).
    case шаблон = "tpl"
    /// Свободный текст описания.
    case текст = "text"
    /// В «Моём»: снимок купленного на Kliko.
    case сделка = "deal"

    /// Лучший уровень, который даёт значение из этого источника: из текста и выведенного — не выше «Проверьте».
    var потолок: УровеньСтандарта {
        switch self {
        case .шаблон, .текст: return .проверить
        default: return .подходит
        }
    }

    init(from decoder: Decoder) throws {
        let строка = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ИсточникСтандарта(rawValue: строка) ?? .текст
    }
}

// MARK: - Набор значений

/**
 Значения стандартов вещи или объявления: {семья: {поле: значение}}, сколько единиц (qty) и откуда (std_src). Значения —
 строки каноном каталога («160x200», «SO-DIMM», «16», «2280»); числа — с точкой. Незнакомые семьи при чтении
 пропускаются, длинные строки обрезаются: файл «Моего» переживает версии приложения.
 */
struct НаборСтандартов: Codable, Equatable, Hashable, Sendable {
    private(set) var значения: [String: [String: String]]
    /// Сколько единиц: комплект шин 4, кит ОЗУ 2, упаковка ламп 10.
    var сколько: Int
    var источник: ИсточникСтандарта

    static let пределПолей = 16
    static let пределЗначения = 60

    enum CodingKeys: String, CodingKey {
        case значения = "std"
        case сколько = "qty"
        case источник = "src"
    }

    init(значения: [String: [String: String]] = [:], сколько: Int = 1, источник: ИсточникСтандарта = .продавец) {
        self.значения = [:]
        self.сколько = max(1, min(999, сколько))
        self.источник = источник
        for (семья, поля) in значения {
            guard let с = СемьяСтандарта(rawValue: семья) else { continue }
            for (поле, значение) in поля { задать(с, поле, значение) }
        }
    }

    init(from decoder: Decoder) throws {
        let к = try decoder.container(keyedBy: CodingKeys.self)
        let сырые = к.значениеМоего([String: [String: String]].self, .значения) ?? [:]
        self.init(значения: сырые, сколько: к.значениеМоего(Int.self, .сколько) ?? 1,
                  источник: к.значениеМоего(ИсточникСтандарта.self, .источник) ?? .продавец)
    }

    /// Значение поля семьи; пусто — nil.
    subscript(семья: СемьяСтандарта, поле: String) -> String? {
        get { значения[семья.rawValue]?[поле] }
        set { задать(семья, поле, newValue) }
    }

    /// Задать или стереть (nil, пусто) значение поля.
    mutating func задать(_ семья: СемьяСтандарта, _ поле: String, _ значение: String?) {
        let чистое = значение.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.пределЗначения)) }
        var поля = значения[семья.rawValue] ?? [:]
        if let чистое, !чистое.isEmpty, !поле.isEmpty {
            guard поля[поле] != nil || поля.count < Self.пределПолей else { return }
            поля[поле] = чистое
        } else {
            поля[поле] = nil
        }
        значения[семья.rawValue] = поля.isEmpty ? nil : поля
    }

    /// Число поля («16», «2280», «52.5»); не число — nil.
    func число(_ семья: СемьяСтандарта, _ поле: String) -> Double? {
        guard let строка = self[семья, поле], let x = Double(строка), x.isFinite else { return nil }
        return x
    }

    /// Целое поля.
    func целое(_ семья: СемьяСтандарта, _ поле: String) -> Int? {
        число(семья, поле).map { Int($0.rounded()) }
    }

    func поля(_ семья: СемьяСтандарта) -> [String: String] { значения[семья.rawValue] ?? [:] }

    func есть(_ семья: СемьяСтандарта) -> Bool { !(значения[семья.rawValue] ?? [:]).isEmpty }

    /// Все главные поля семьи заполнены. У белья хватает любого изделия: комплект, простыня на резинке, пододеяльник,
    /// наволочка или одеяло.
    func полная(_ семья: СемьяСтандарта) -> Bool {
        if семья == .бельё { return есть(.бельё) }
        return семья.главные.allSatisfy { self[семья, $0] != nil }
    }

    /// Семьи с данными — в порядке каталога.
    var семьи: [СемьяСтандарта] { СемьяСтандарта.allCases.filter { есть($0) } }

    var пусто: Bool { значения.isEmpty }

    /// Дополнить пустыми полями из другого набора (своё не затирается).
    mutating func дополнить(_ другой: НаборСтандартов) {
        for (семья, поля) in другой.значения {
            guard let с = СемьяСтандарта(rawValue: семья) else { continue }
            for (поле, значение) in поля where self[с, поле] == nil {
                задать(с, поле, значение)
            }
        }
        if сколько == 1 && другой.сколько > 1 { сколько = другой.сколько }
    }
}

// MARK: - Итог сверки

/// Пункт сверки: «DDR4 ✓», «Длина 240 мм, корпус до 320 ✓», «БП 500 Вт — советуют 550 ⚠».
struct ПунктСверкиСтандарта: Hashable, Sendable, Identifiable {
    /// Ключ пункта: поле семьи или своё («slots», «psu»).
    let id: String
    let уровень: УровеньСтандарта
    let текст: String

    init(_ id: String, _ уровень: УровеньСтандарта, _ текст: String) {
        self.id = id
        self.уровень = уровень
        self.текст = текст
    }
}

/**
 Итог сверки вещи «Моего» с объявлением: уровень — худший пункт (и не выше потолка источника), заголовок («Подходит
 к вашей кровати ✓»), короткое «почему» («Здесь 160×200 — ваша кровать 160×200»), пункты с причинами в цифрах и
 названная деталь («переходник E14→E27»). куда — с какой вещью «Моего» сверили («Спальня», «Мой ПК»).
 */
struct ИтогСверкиСтандарта: Equatable, Sendable {
    let семья: СемьяСтандарта
    let уровень: УровеньСтандарта
    let заголовок: String
    let почему: String
    let пункты: [ПунктСверкиСтандарта]
    let деталь: String?
    let куда: String?

    init(семья: СемьяСтандарта, уровень: УровеньСтандарта, заголовок: String, почему: String,
         пункты: [ПунктСверкиСтандарта] = [], деталь: String? = nil, куда: String? = nil) {
        self.семья = семья
        self.уровень = уровень
        self.заголовок = заголовок
        self.почему = почему
        self.пункты = пункты
        self.деталь = деталь
        self.куда = куда
    }

    /// Для отбора «Для вас» и чипа «Для моего»: подходит как есть или с названной деталью.
    var подходит: Bool { уровень <= .доработка }
}

/// Худший уровень пунктов; пусто — «неизвестно».
enum УровниСтандарта {
    static func худший(_ уровни: [УровеньСтандарта]) -> УровеньСтандарта {
        уровни.max() ?? .неизвестно
    }

    /// Уровень не лучше потолка источника.
    static func неВыше(_ уровень: УровеньСтандарта, _ потолок: УровеньСтандарта) -> УровеньСтандарта {
        max(уровень, потолок)
    }
}
