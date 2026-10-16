import SwiftUI
import PhotosUI
import Vision
import UIKit

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР»: ЗАПОЛНИТЬ ПО СНИМКУ ЭКРАНА (docs/STANDARDS.md §8.1: «главный путь — снять экран компьютера»;
 владелец: «стандарты = удобство: не пустые поля, а выбор по стандартам, шаблоны, камера»).

 Человек выбирает в «Фото» до четырёх снимков (системный выбор фото: приложение видит только выбранное, доступа к
 медиатеке не просит): Windows — «Диспетчер задач → Производительность → Память» (объём, «Скорость: 3200 МГц»,
 «Использовано гнезд: 1 из 2», «Форм-фактор: SODIMM»), там же ЦП, Диск 0 и Графический процессор; Mac — «Об этом Mac»
 (чип M1…M4, память). Текст читает Vision на телефоне (ru, en), снимок никуда не уходит и не сохраняется. Из текста
 берётся только нужное: процессор и сокет, объём и поколение памяти, частота, слоты, форма, распаяна ли, видеокарта и её
 память, накопитель (SSD NVMe / HDD, ёмкость), вид и модель Mac; имя компьютера, серийный номер и прочее не читаются.

 Найденное — строками «верно?»: каждую можно снять касанием; выведенное (DDR4 по частоте 3200, «ноутбук» по процессору)
 помечено «проверьте». «Применить» — в компьютер, с событием «По снимку экрана» и вспышкой частей на схеме.
 */

// MARK: - Находка

enum НаходкаСнимкаКомпьютераМоего: Hashable, Sendable {
    case вид(ВидКомпьютераМоего, примерно: Bool)
    case модель(String)
    case процессор(имя: String, сокет: String?)
    case всегоПамяти(Int)
    case распаяна(Int, примерно: Bool)
    case поколение(String, примерно: Bool)
    case форма(String)
    case частота(Int)
    case слоты(занято: Int, всего: Int)
    case видеокарта(String)
    case памятьКарты(Int)
    case встроенная
    case накопитель(тб: Double, протокол: String?, hdd: Bool)

    /// Род: из двух находок одного рода (второй снимок) остаётся новая.
    var род: String {
        switch self {
        case .вид: return "kind"
        case .модель: return "model"
        case .процессор: return "cpu"
        case .всегоПамяти: return "ram_total"
        case .распаяна: return "ram_soldered"
        case .поколение: return "ram_gen"
        case .форма: return "ram_form"
        case .частота: return "ram_mts"
        case .слоты: return "ram_slots"
        case .видеокарта, .встроенная: return "gpu"
        case .памятьКарты: return "vram"
        case .накопитель(let тб, _, let hdd): return "drive_" + String(тб) + (hdd ? "_hdd" : "_ssd")
        }
    }

    var часть: ЧастьКомпьютераМоего? {
        switch self {
        case .вид, .модель: return nil
        case .процессор: return .процессор
        case .всегоПамяти, .распаяна, .поколение, .форма, .частота, .слоты: return .память
        case .видеокарта, .памятьКарты, .встроенная: return .видеокарта
        case .накопитель: return .накопители
        }
    }

    /// Выведено, а не прочитано: «проверьте».
    var примерно: Bool {
        switch self {
        case .вид(_, let п): return п
        case .распаяна(_, let п): return п
        case .поколение(_, let п): return п
        default: return false
        }
    }

    var значок: String {
        switch self {
        case .вид(let в, _): return в.значок
        case .модель: return "tag"
        default: return часть?.значок ?? "checkmark"
        }
    }

    /// «ОЗУ: 16 ГБ», «Слоты: 1 из 2», «SSD 512 ГБ · NVMe».
    var подпись: String {
        let т = МойКомпьютерText.т
        switch self {
        case .вид(let в, _): return в.название
        case .модель(let м): return м
        case .процессор(let имя, let сокет):
            guard let код = сокет else { return имя }
            let подписьСокета: String = код == "BGA" ? т("mpc_bga") : код
            return имя + " · " + подписьСокета
        case .всегоПамяти(let г): return т("mpc_part_ram") + ": " + ФорматКомпьютераМоего.гб(г)
        case .распаяна(let г, _): return String(format: т("mpc_scan_soldered"), ФорматКомпьютераМоего.гб(г))
        case .поколение(let п, _): return п
        case .форма(let ф): return ф
        case .частота(let ч): return String(ч) + " " + т("mpc_mts")
        case .слоты(let занято, let всего):
            return т("mpc_ram_slots") + ": " + String(format: т("mpc_slots_of"), String(занято), String(всего))
        case .видеокарта(let чип): return чип
        case .памятьКарты(let г): return String(format: т("mpc_scan_vram"), ФорматКомпьютераМоего.гб(г))
        case .встроенная: return т("mpc_gpu_igpu")
        case .накопитель(let тб, let протокол, let hdd):
            var итог = (hdd ? "HDD " : "SSD ") + ФорматКомпьютераМоего.объём(тб)
            if протокол == "nvme" { итог += " · NVMe" }
            return итог
        }
    }
}

// MARK: - Разбор текста

enum РазборСнимкаКомпьютераМоего {
    private static func рег(_ шаблон: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive])
    }

    private static func первое(_ р: NSRegularExpression?, _ s: String) -> [String]? {
        guard let р else { return nil }
        let ns = s as NSString
        guard let совпадение = р.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<совпадение.numberOfRanges).map { номер in
            let место = совпадение.range(at: номер)
            return место.location == NSNotFound ? "" : ns.substring(with: место)
        }
    }

    private static let регApple = рег(#"apple\s?(m[1-9])(?:\s?(pro|max|ultra))?(?![a-z0-9])"#)
    private static let регОдноГБ = рег(#"^\s*(\d{1,3}(?:\.\d{1,2})?)\s?(?:гб|gb)(?:\s?(?:lp)?ddr\d[a-z]?)?\s*$"#)
    private static let регДробьГБ = рег(#"(?:\d{1,3}(?:\.\d{1,2})?\s?/\s?)?(\d{1,3}(?:\.\d{1,2})?)\s?(?:гб|gb)"#)
    private static let регСкорость = рег(#"(?:скорост|speed|жылдамд)\S*\s*:?\s*(\d{4})(?!\d)"#)
    private static let регМгц = рег(#"(?<![\d.])(\d{4})\s?(?:мгц|mhz|mt/s|мт/с)"#)
    private static let регГнезда =
        рег(#"(?:гнезд|разъем|слот|slots?\s?used|ұяшық)\S*\s*(?:used|использовано)?\s*:?\s*(\d)\s*(?:из|of|/)\s*(\d)"#)
    private static let регГнездаНет = рег(#"(?:гнезд|slots?\s?used)\S*\s*:?\s*(?:н/д|n/a|нет данных)"#)
    private static let регФорма = рег(#"(?:форм-?фактор|form\s?factor)\S*\s*:?\s*([a-zа-я -]{3,24})"#)
    private static let регЁмкость = рег(#"(?:емкост|capacity|сыйымдылы)\S*\s*:?\s*(\d{2,4}(?:\.\d{1,2})?)\s?(гб|gb|тб|tb)"#)
    private static let регЧислоДиска = рег(#"^\s*(\d{2,4}(?:\.\d{1,2})?)\s?(гб|gb|тб|tb)\s*$"#)

    private static let словаПамяти = ["память", "memory", "озу", " ram", "жады", "оперативн"]
    private static let исключения = ["видео", "графич", "gpu", "dedicated", "выделен", "shared", "общая", "емкост",
                                     "capacity", "диск", "disk", "использ", "in use", "usage", "доступн", "available",
                                     "кэш", "cached", "выгруж", "paged", "зарезерв", "reserved", "сжат", "compressed",
                                     "committed", "подкачк", "swap", "свобод", "free"]
    private static let контекстПамяти = ["гнезд", "slots used", "slot used", "форм-фактор", "форм фактор",
                                         "form factor", "скорость", "speed", "ұяшық"]

    /// Строка для разбора: строчные, «ё» = «е», без (R) и (TM), запятая в числах — точка.
    static func нормально(_ строка: String) -> String {
        var s = строка
        for знак in ["(R)", "(r)", "(TM)", "(tm)", "(Tm)", "®", "™"] { s = s.replacingOccurrences(of: знак, with: "") }
        return РазборСтандартов.нормально(s).trimmingCharacters(in: .whitespaces)
    }

    /// Находки одного снимка (строки Vision по порядку).
    static func разобрать(_ строки: [String], вид: ВидКомпьютераМоего?) -> [НаходкаСнимкаКомпьютераМоего] {
        let нижние = строки.map { нормально($0) }.filter { !$0.isEmpty }
        guard !нижние.isEmpty else { return [] }
        let весь = " " + нижние.joined(separator: "\n") + " "
        var итог: [НаходкаСнимкаКомпьютераМоего] = []
        let apple = первое(регApple, весь)
        итог += видИМодель(строки, весь, apple: apple != nil)
        let цп = процессор(весь, apple: apple)
        if let цп { итог.append(цп) }
        итог += память(нижние, весь, apple: apple)
        итог += видеокарта(нижние, весь, apple: apple != nil)
        if let диск = накопитель(нижние, весь) { итог.append(диск) }
        // Вид по процессору ноутбука (BGA без Apple) — только догадка.
        if вид == nil, !итог.contains(where: { $0.род == "kind" }),
           case .процессор(_, let сокет)? = цп, сокет == "BGA", apple == nil {
            итог.insert(.вид(.ноутбук, примерно: true), at: 0)
        }
        return итог
    }

    private static func видИМодель(_ строки: [String], _ весь: String, apple: Bool) -> [НаходкаСнимкаКомпьютераМоего] {
        var итог: [НаходкаСнимкаКомпьютераМоего] = []
        if весь.contains("macbook") {
            итог.append(.вид(.ноутбук, примерно: false))
        } else if ["imac", "mac mini", "mac studio", "mac pro"].contains(where: { весь.contains($0) }) {
            итог.append(.вид(.настольный, примерно: false))
        } else if весь.contains("laptop gpu") || весь.contains("ноутбук") {
            итог.append(.вид(.ноутбук, примерно: true))
        }
        if apple || весь.contains("macbook") || весь.contains("imac") {
            let модель = строки.first { строка in
                let н = строка.lowercased()
                return ["macbook", "imac", "mac mini", "mac studio"].contains(where: { н.contains($0) })
            }
            if let модель {
                let чистая = String(модель.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                if !чистая.isEmpty { итог.append(.модель(чистая)) }
            }
        }
        return итог
    }

    private static func процессор(_ весь: String, apple: [String]?) -> НаходкаСнимкаКомпьютераМоего? {
        if let apple {
            var имя = "Apple " + apple[1].uppercased()
            if !apple[2].isEmpty { имя += " " + apple[2].capitalized }
            return .процессор(имя: имя, сокет: "BGA")
        }
        guard let цп = РазборСтандартов.процессор(весь) else { return nil }
        return .процессор(имя: цп.имя, сокет: цп.сокет)
    }

    // MARK: Память

    private static func память(_ нижние: [String], _ весь: String, apple: [String]?) -> [НаходкаСнимкаКомпьютераМоего] {
        var итог: [НаходкаСнимкаКомпьютераМоего] = []
        let контекст = контекстПамяти.contains { весь.contains($0) } || apple != nil
        let всего = объёмПамяти(нижние, контекст: контекст)
        var распаяна = false
        if let apple, let всего {
            итог.append(.распаяна(всего, примерно: false))
            распаяна = true
            let поколение: String
            switch apple[1] {
            case "m1": поколение = "LPDDR4X"
            case "m2", "m3": поколение = "LPDDR5"
            default: поколение = "LPDDR5X"
            }
            итог.append(.поколение(поколение, примерно: true))
            return итог
        }
        var форма: String? = nil
        if let г = первое(регФорма, весь) {
            let значение = г[1]
            if значение.contains("sodimm") || значение.contains("so-dimm") || значение.contains("so dimm") {
                форма = "SO-DIMM"
            } else if значение.contains("camm") {
                форма = "CAMM2"
            } else if значение.contains("dimm") {
                форма = "DIMM"
            } else if ["chip", "микросх", "other", "друг"].contains(where: { значение.contains($0) }) {
                распаяна = true
            }
        }
        if первое(регГнездаНет, весь) != nil { распаяна = true }
        if let всего {
            итог.append(распаяна ? .распаяна(всего, примерно: true) : .всегоПамяти(всего))
        }
        if let форма, !распаяна { итог.append(.форма(форма)) }
        if !распаяна, let г = первое(регГнезда, весь), let занято = Int(г[1]), let слотов = Int(г[2]),
           (1...8).contains(слотов), занято <= слотов {
            итог.append(.слоты(занято: занято, всего: слотов))
        }
        var частота: Int? = nil
        if контекст || всего != nil {
            let г = первое(регСкорость, весь) ?? первое(регМгц, весь)
            if let г, let ч = Int(г[1]), (800...9600).contains(ч) {
                частота = КаталогСтандартов.частотыПамяти.first { abs($0 - ч) <= 40 } ?? ч
            }
        }
        if let частота { итог.append(.частота(частота)) }
        let набор = РазборСтандартов.разобрать(текст: весь, семьи: [.память], источник: .камера).набор
        if let поколение = набор[.память, КлючСтандарта.поколение] {
            итог.append(.поколение(поколение, примерно: false))
        } else if let частота {
            switch частота {
            case ..<2000: итог.append(.поколение("DDR3", примерно: true))
            case 2000...3600: итог.append(.поколение("DDR4", примерно: true))
            case 4800...: итог.append(.поколение(распаяна ? "LPDDR5" : "DDR5", примерно: true))
            default: break
            }
        }
        return итог
    }

    /// Объём памяти: строка со словом «память» (без «видео», «использовано», «доступно»…) до первой скобки, или
    /// отдельная строка «16,0 ГБ» на странице памяти, или «Память» и число строкой ниже.
    private static func объёмПамяти(_ нижние: [String], контекст: Bool) -> Int? {
        for (номер, строка) in нижние.enumerated() {
            let до = String(строка.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            let начало = " " + до
            guard словаПамяти.contains(where: { начало.contains($0) }),
                  !исключения.contains(where: { начало.contains($0) }) else { continue }
            if let г = первое(регДробьГБ, до), let x = Double(г[1]), let гб = округлитьПамять(x) { return гб }
            if номер + 1 < нижние.count, let г = первое(регОдноГБ, нижние[номер + 1]), let x = Double(г[1]),
               let гб = округлитьПамять(x) {
                return гб
            }
        }
        guard контекст else { return nil }
        for строка in нижние {
            if let г = первое(регОдноГБ, строка), let x = Double(г[1]), let гб = округлитьПамять(x) { return гб }
        }
        return nil
    }

    /// 15,8 → 16, 7,9 → 8; вне 2…512 — nil.
    static func округлитьПамять(_ x: Double) -> Int? {
        guard x >= 1.5, x <= 512 else { return nil }
        let ряд = [2, 3, 4, 6, 8, 12, 16, 18, 20, 24, 32, 36, 40, 48, 64, 96, 128, 192, 256, 384, 512]
        if let ближ = ряд.min(by: { abs(Double($0) - x) < abs(Double($1) - x) }),
           abs(Double(ближ) - x) / Double(ближ) <= 0.08 {
            return ближ
        }
        return Int(x.rounded())
    }

    // MARK: Видеокарта

    private static func видеокарта(_ нижние: [String], _ весь: String, apple: Bool) -> [НаходкаСнимкаКомпьютераМоего] {
        var итог: [НаходкаСнимкаКомпьютераМоего] = []
        let набор = РазборСтандартов.разобрать(текст: весь, семьи: [.видеокарта], источник: .камера).набор
        if let чип = набор[.видеокарта, КлючСтандарта.чип] {
            итог.append(.видеокарта(чип))
        } else if apple || ["uhd graphics", "iris", "radeon graphics", "vega", "intel graphics", "adreno"]
                    .contains(where: { весь.contains($0) }) {
            итог.append(.встроенная)
        }
        for (номер, строка) in нижние.enumerated() {
            guard ["выделенная память графическ", "dedicated gpu memory", "видеопамять", "video memory"]
                .contains(where: { строка.contains($0) }) else { continue }
            var где: [String] = [строка]
            if номер + 1 < нижние.count { где.append(нижние[номер + 1]) }
            for s in где {
                if let г = первое(регДробьГБ, s), let x = Double(г[1]), x >= 1, x <= 48 {
                    итог.append(.памятьКарты(Int(x.rounded())))
                    return итог
                }
            }
        }
        return итог
    }

    // MARK: Накопитель

    private static func накопитель(_ нижние: [String], _ весь: String) -> НаходкаСнимкаКомпьютераМоего? {
        let nvme = весь.contains("nvme")
        let hdd = весь.contains("hdd") && !весь.contains("ssd")
        let ssd = nvme || весь.contains("ssd")
        guard ssd || hdd else { return nil }
        var значение: (Double, String)? = nil
        if let г = первое(регЁмкость, весь), let x = Double(г[1]) {
            значение = (x, г[2])
        } else {
            for (номер, строка) in нижние.enumerated() where строка.hasPrefix("емкост") || строка.hasPrefix("capacity") {
                if номер + 1 < нижние.count, let г = первое(регЧислоДиска, нижние[номер + 1]), let x = Double(г[1]) {
                    значение = (x, г[2])
                    break
                }
            }
        }
        guard let пара = значение else { return nil }
        let число = пара.0
        let тб = пара.1 == "тб" || пара.1 == "tb" ? число : число / 1000
        guard тб >= 0.06, тб <= 64 else { return nil }
        let ряд = КаталогСтандартов.объёмыНакопителя
        let ближ = ряд.min { abs($0 - тб) < abs($1 - тб) } ?? тб
        let итогТБ = abs(ближ - тб) / ближ <= 0.12 ? ближ : (тб * 1000).rounded() / 1000
        return .накопитель(тб: итогТБ, протокол: nvme ? "nvme" : (hdd ? "sata" : nil), hdd: hdd)
    }

    // MARK: Применить

    /// Найденное — в компьютер; части, которые поменялись (для вспышки на схеме).
    static func применить(_ находки: [НаходкаСнимкаКомпьютераМоего], к: inout КомпьютерМоего) -> Set<ЧастьКомпьютераМоего> {
        var части = Set<ЧастьКомпьютераМоего>()
        var всего: Int? = nil
        var слоты: (занято: Int, всего: Int)? = nil
        var распаяно: Int? = nil
        var диски: [НакопительМоего] = []
        for н in находки {
            if let ч = н.часть { части.insert(ч) }
            switch н {
            case .вид(let в, _): к.вид = в
            case .модель(let м): к.модель = м
            case .процессор(let имя, let сокет):
                к.процессор = имя
                if let сокет, сокет != "BGA" || к.вид == .ноутбук { к.сокет = сокет }
            case .всегоПамяти(let г): всего = г
            case .распаяна(let г, _): распаяно = г
            case .поколение(let п, _): к.память.поколение = п
            case .форма(let ф): к.память.форма = ф
            case .частота(let ч): к.память.частота = ч
            case .слоты(let занято, let слотов): слоты = (занято: занято, всего: слотов)
            case .видеокарта(let чип):
                к.видеокарта.чип = чип
                к.видеокарта.встроенная = false
            case .памятьКарты(let г): к.видеокарта.памятьГБ = г
            case .встроенная:
                if к.видеокарта.чип == nil { к.видеокарта.встроенная = true }
            case .накопитель(let тб, let протокол, let hdd):
                диски.append(НакопительМоего(форма: hdd ? "3.5" : (протокол == "nvme" ? "2280" : "2.5"), протокол: протокол,
                                             тб: тб, hdd: hdd))
            }
        }
        if let распаяно {
            к.память.планки = []
            к.память.слотов = 0
            к.память.форма = "soldered"
            к.память.распаяно = распаяно
        } else if let всего {
            к.память.распаяно = nil
            if к.память.форма == "soldered" { к.память.форма = nil }
            if let слоты {
                к.память.слотов = слоты.всего
                let занято = max(1, слоты.занято)
                if всего % занято == 0, КаталогСтандартов.объёмыМодуля.contains(всего / занято) {
                    к.память.планки = Array(repeating: всего / занято, count: занято)
                } else {
                    к.память.планки = [всего]
                }
            } else if к.память.всего != всего {
                к.память.планки = [всего]
            }
        } else if let слоты {
            к.память.слотов = слоты.всего
        }
        к.память.нормализовать()
        for диск in диски {
            let такой = к.накопители.contains { старый in
                guard let тб = старый.тб, let новый = диск.тб else { return false }
                return старый.hdd == диск.hdd && abs(тб - новый) / новый <= 0.12
            }
            guard !такой, к.накопители.count < 12 else { continue }
            if КаталогСтандартов.длинаM2(диск.форма) != nil {
                if let i = к.слотыM2.firstIndex(where: { !$0.занят }) {
                    к.слотыM2[i].занят = true
                } else if к.слотыM2.count < 6 {
                    к.слотыM2.append(СлотM2Моего(длина: "2280", протокол: "nvme", занят: true))
                }
            }
            к.накопители.append(диск)
        }
        return части
    }
}

// MARK: - Распознавание

/// Vision на телефоне: текст снимка, затем разбор — вне главной нити.
enum РаспознаваниеСнимкаКомпьютераМоего {
    static func найти(_ данные: Data, вид: ВидКомпьютераМоего?) async -> [НаходкаСнимкаКомпьютераМоего] {
        await Task.detached(priority: .userInitiated) {
            РазборСнимкаКомпьютераМоего.разобрать(РаспознаваниеСнимкаКомпьютераМоего.прочитать(данные), вид: вид)
        }.value
    }

    /// Строки текста снимка (лучший вариант каждой), ru и en; не вышло — пусто.
    static func прочитать(_ данные: Data) -> [String] {
        guard let картинка = UIImage(data: данные), let кадр = картинка.cgImage else { return [] }
        let запрос = VNRecognizeTextRequest()
        запрос.recognitionLevel = .accurate
        запрос.usesLanguageCorrection = false
        let поддержка = (try? запрос.supportedRecognitionLanguages()) ?? []
        let языки = ["ru-RU", "en-US"].filter { поддержка.contains($0) }
        if !языки.isEmpty { запрос.recognitionLanguages = языки }
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: ориентация(картинка.imageOrientation),
                                               options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return []
        }
        return (запрос.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    private static func ориентация(_ о: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch о {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Лист

/// «По снимку экрана»: что снять, выбор снимков, чтение и найденное строками «верно?».
struct ЛистСканаКомпьютераМоего: View {
    let вид: ВидКомпьютераМоего?
    let готово: ([НаходкаСнимкаКомпьютераМоего]) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var элементы: [PhotosPickerItem] = []
    @State private var галерея = false
    @State private var читаем = false
    @State private var ничего = false
    @State private var находки: [НаходкаСнимкаКомпьютераМоего] = []
    @State private var сняты: Set<НаходкаСнимкаКомпьютераМоего> = []
    @State private var задача: Task<Void, Never>? = nil

    init(вид: ВидКомпьютераМоего?, готово: @escaping ([НаходкаСнимкаКомпьютераМоего]) -> Void) {
        self.вид = вид
        self.готово = готово
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var выбранные: [НаходкаСнимкаКомпьютераМоего] { находки.filter { !сняты.contains($0) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    что
                    if читаем { чтение }
                    if !находки.isEmpty { найденное }
                    if ничего && !читаем { пусто }
                    ЗелёнаяКнопкаФото(заголовок: т(находки.isEmpty ? "mpc_scan_pick" : "mpc_scan_more"),
                                      значок: "photo.on.rectangle", контурная: !находки.isEmpty) {
                        ОткликСайта.выбор()
                        галерея = true
                    }
                    .disabled(читаем)
                    Label {
                        Text(т("mpc_scan_private"))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Theme.акцент)
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.смена, value: читаем)
                .animation(ДвижениеСайта.вставкаСписка, value: находки)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("mpc_scan_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("mpc_scan_apply")) {
                        ОткликСайта.успех()
                        готово(выбранные)
                        закрыть()
                    }
                    .disabled(выбранные.isEmpty || читаем)
                }
            }
        }
        .tint(Theme.акцент)
        .photosPicker(isPresented: $галерея, selection: $элементы, maxSelectionCount: 4, matching: .images)
        .onChange(of: элементы) { _, новые in
            if !новые.isEmpty { читать(новые) }
        }
        .onDisappear { задача?.cancel() }
    }

    /// Что снять: Windows — «Диспетчер задач», Mac — «Об этом Mac».
    private var что: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mpc_scan_what"), значок: "text.viewfinder")
            строкаСовета("pc", т("mpc_scan_win"))
            строкаСовета("cpu", т("mpc_scan_win_more"))
            строкаСовета("laptopcomputer", т("mpc_scan_mac"))
        }
        .карточкаМоего()
    }

    private func строкаСовета(_ значок: String, _ текст: String) -> some View {
        Label {
            Text(текст)
                .font(.subheadline)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: значок)
                .foregroundStyle(Theme.акцент)
        }
    }

    private var чтение: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(т("mpc_scan_reading"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текст)
        }
        .карточкаМоего()
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    private var пусто: some View {
        ЗаметкаКомпьютераМоего(т("mpc_scan_nothing"), значок: "exclamationmark.triangle")
            .transition(.opacity)
    }

    private var найденное: some View {
        VStack(alignment: .leading, spacing: 4) {
            ЗаголовокМоего(т("mpc_scan_found"), значок: "checkmark.seal")
                .padding(.bottom, 6)
            ForEach(находки, id: \.self) { н in
                строка(н)
            }
        }
        .карточкаМоего()
        .transition(.opacity)
    }

    private func строка(_ н: НаходкаСнимкаКомпьютераМоего) -> some View {
        let включена = !сняты.contains(н)
        return Button {
            ОткликСайта.выбор()
            if включена { сняты.insert(н) } else { сняты.remove(н) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: включена ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(включена ? Theme.зелёный2 : Theme.текстВторой)
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: н.значок)
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(н.подпись)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(включена ? Theme.текст : Theme.текстВторой)
                        .strikethrough(!включена)
                        .multilineTextAlignment(.leading)
                    if н.примерно {
                        Text(т("mpc_scan_check"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.оранжевый)
                    }
                }
                Spacer(minLength: 8)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        .accessibilityAddTraits(включена ? .isSelected : [])
        .accessibilityHint(т("mpc_scan_toggle"))
    }

    /// Снимки по очереди: Vision и разбор — вне главной нити; находка того же рода заменяет прежнюю.
    private func читать(_ выбор: [PhotosPickerItem]) {
        задача?.cancel()
        читаем = true
        ничего = false
        let видСейчас = вид
        задача = Task { @MainActor in
            var новые: [НаходкаСнимкаКомпьютераМоего] = []
            for элемент in выбор {
                guard let данные = try? await элемент.loadTransferable(type: Data.self) else { continue }
                if Task.isCancelled { return }
                новые += await РаспознаваниеСнимкаКомпьютераМоего.найти(данные, вид: видСейчас)
            }
            if Task.isCancelled { return }
            var итог = находки
            for н in новые {
                if let i = итог.firstIndex(where: { $0.род == н.род }) {
                    итог[i] = н
                } else {
                    итог.append(н)
                }
            }
            находки = итог
            элементы = []
            читаем = false
            ничего = новые.isEmpty
            if новые.isEmpty {
                ОткликСайта.предупреждение()
                UIAccessibility.post(notification: .announcement, argument: т("mpc_scan_nothing"))
            } else {
                ОткликСайта.успех()
                UIAccessibility.post(notification: .announcement,
                                     argument: String(format: т("mpc_scan_found_n"), String(новые.count)))
            }
        }
    }
}
