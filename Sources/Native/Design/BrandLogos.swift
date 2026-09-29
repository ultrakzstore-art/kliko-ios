import SwiftUI
import UIKit

/**
 ЛОГОТИПЫ МАРОК С САЙТА (владелец: «в марка иконки пусть берёт с сайта, там есть логотипы»).

 Откуда: сайт кладёт знаки марок в img/brands/ — монохромные SVG Simple Icons (inc/categories.php, BRAND_ICON), в
 браузер справочник уходит как MK_BRAND_ICON (inc/mk_refs.php), адрес — _ULX_BASE + "/img/brands/" + файл (мастер
 авто кабинета _awStepBrand, мастер фильтров _afxBrandIc). Нет файла или он не загрузился — у сайта остаются буквы
 марки; здесь так же: заглушку рисует тот, кто ставит знак.

 SVG ни UIImage, ни ImageIO не читают, поэтому файл разбирается сам: берутся контуры path (у Simple Icons это один
 path на холсте 24 × 24) и рисуются залитой фигурой, как img на белом круге .afx-logo. Если на месте SVG окажется
 растровая картинка (PNG, WebP) — покажется она. Скачивается URLSession.shared (URLCache держит файл между
 запусками), разобранный знак — в памяти на всё время работы; один файл качается один раз на все строки.
 */
enum ЛоготипыМарокСайта {
    /// BRAND_ICON сайта: марка → файл в img/brands/.
    static let файлы: [String: String] = [
        "Acer": "acer.svg", "Adidas": "adidas.svg", "Apple": "apple.svg", "Asus": "asus.svg", "Audi": "audi.svg",
        "BMW": "bmw.svg", "Bosch": "bosch.svg", "Chevrolet": "chevrolet.svg", "DJI": "dji.svg", "Dell": "dell.svg",
        "Ford": "ford.svg", "Fujifilm": "fujifilm.svg", "Google": "google.svg", "HP": "hp.svg", "Honda": "honda.svg",
        "Honor": "honor.svg", "Huawei": "huawei.svg", "Hyundai": "hyundai.svg", "Kia": "kia.svg", "LG": "lg.svg",
        "Lada": "lada.svg", "Lenovo": "lenovo.svg", "MSI": "msi.svg", "Mazda": "mazda.svg", "Motorola": "motorola.svg",
        "New Balance": "newbalance.svg", "Nike": "nike.svg", "Nikon": "nikon.svg", "Nissan": "nissan.svg",
        "Nokia": "nokia.svg", "OPPO": "oppo.svg", "OnePlus": "oneplus.svg", "Panasonic": "panasonic.svg",
        "Porsche": "porsche.svg", "Puma": "puma.svg", "Razer": "razer.svg", "Reebok": "reebok.svg",
        "Renault": "renault.svg", "Samsung": "samsung.svg", "Skoda": "skoda.svg", "Sony": "sony.svg",
        "Subaru": "subaru.svg", "Suzuki": "suzuki.svg", "Tesla": "tesla.svg", "Toyota": "toyota.svg",
        "Under Armour": "underarmour.svg", "Uniqlo": "uniqlo.svg", "Volkswagen": "volkswagen.svg",
        "Volvo": "volvo.svg", "Xiaomi": "xiaomi.svg", "Zara": "zara.svg"
    ]

    /// Адрес знака марки на сайте или nil, если у сайта его нет. Регистр названия не важен.
    static func адрес(_ марка: String) -> URL? {
        let имя = марка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !имя.isEmpty else { return nil }
        var файл = файлы[имя]
        if файл == nil {
            файл = файлы.first(where: { $0.key.caseInsensitiveCompare(имя) == .orderedSame })?.value
        }
        guard let файл else { return nil }
        return URL(string: "https://kliko.kz/img/brands/" + файл)
    }

    /// Буквы-заглушка как _afMono сайта: первые две буквы названия заглавными.
    static func буквы(_ марка: String) -> String {
        let только = марка.filter { $0.isLetter }
        let две = String(только.prefix(2)).uppercased()
        return две.isEmpty ? "?" : две
    }
}

/// Готовый знак марки: контур из SVG (в координатах его холста) или растровая картинка.
enum РисунокЛоготипаМарки {
    case контур(Path, CGRect)
    case растр(UIImage)
}

/// Скачивание и разбор знаков марок; разобранные — в памяти, пропавшие (404, не разобрался) больше не спрашиваются.
@MainActor
final class ЗагрузчикЛоготиповМарок {
    static let общий = ЗагрузчикЛоготиповМарок()

    private enum Итог {
        case есть(РисунокЛоготипаМарки)
        case нет
        case сбой
    }

    private var готовые: [URL: РисунокЛоготипаМарки] = [:]
    private var пустые: Set<URL> = []
    private var вПути: [URL: Task<Итог, Never>] = [:]

    private init() {}

    func готовый(_ адрес: URL) -> РисунокЛоготипаМарки? { готовые[адрес] }

    func загрузить(_ адрес: URL) async -> РисунокЛоготипаМарки? {
        if let есть = готовые[адрес] { return есть }
        if пустые.contains(адрес) { return nil }
        let задача: Task<Итог, Never>
        if let идёт = вПути[адрес] {
            задача = идёт
        } else {
            задача = Task { await ЗагрузчикЛоготиповМарок.скачать(адрес) }
            вПути[адрес] = задача
        }
        let итог = await задача.value
        вПути[адрес] = nil
        switch итог {
        case .есть(let рисунок):
            готовые[адрес] = рисунок
            return рисунок
        case .нет:
            пустые.insert(адрес)
            return nil
        case .сбой:
            return nil
        }
    }

    /// Сеть и разбор — не на главной очереди. Нет сети — «сбой» (спросим в следующий раз), 404 и мусор — «нет».
    nonisolated private static func скачать(_ адрес: URL) async -> Итог {
        guard let ответ = try? await URLSession.shared.data(from: адрес) else { return .сбой }
        if let http = ответ.1 as? HTTPURLResponse {
            if http.statusCode >= 500 { return .сбой }
            if !(200..<300).contains(http.statusCode) { return .нет }
        }
        let данные = ответ.0
        if let текст = String(data: данные, encoding: .utf8), текст.range(of: "<svg", options: .caseInsensitive) != nil {
            guard let знак = РазборЛоготипаSVG.разобрать(текст) else { return .нет }
            return .есть(.контур(знак.0, знак.1))
        }
        if let картинка = UIImage(data: данные) { return .есть(.растр(картинка)) }
        return .нет
    }
}

/// Знак марки с сайта в белом круге (.afx-logo: белый круг с тонкой рамкой, знак 3/4 круга). Пока грузится, нет
/// у сайта или не загрузился — заглушка (буквы марки). Размер один во всех строках: список стоит ровно.
struct ЗнакМаркиСайта<Заглушка: View>: View {
    let марка: String
    let размер: CGFloat
    let заглушка: Заглушка
    @State private var рисунок: РисунокЛоготипаМарки? = nil
    @State private var чей: URL? = nil

    init(_ марка: String, размер: CGFloat = 30, @ViewBuilder заглушка: () -> Заглушка) {
        self.марка = марка
        self.размер = размер
        self.заглушка = заглушка()
    }

    private var адрес: URL? { ЛоготипыМарокСайта.адрес(марка) }

    var body: some View {
        ZStack {
            if let готовый = показать {
                знак(готовый)
            } else {
                заглушка
            }
        }
        .frame(width: размер, height: размер)
        .task(id: адрес) { await загрузить() }
        .accessibilityHidden(true)
    }

    @MainActor
    private var показать: РисунокЛоготипаМарки? {
        guard let цель = адрес else { return nil }
        if чей == цель, let свой = рисунок { return свой }
        return ЗагрузчикЛоготиповМарок.общий.готовый(цель)
    }

    @ViewBuilder
    private func знак(_ р: РисунокЛоготипаМарки) -> some View {
        let внутри = размер * 0.75
        ZStack {
            Circle().fill(Color.white)
            Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
            switch р {
            case .контур(let контур, let холст):
                ФормаЛоготипаМарки(контур: контур, холст: холст)
                    .fill(Color.black)
                    .frame(width: внутри * 0.86, height: внутри * 0.86)
            case .растр(let картинка):
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFit()
                    .frame(width: внутри, height: внутри)
            }
        }
        .frame(width: размер, height: размер)
    }

    @MainActor
    private func загрузить() async {
        guard let цель = адрес else { return }
        if чей == цель && рисунок != nil { return }
        let пришёл = await ЗагрузчикЛоготиповМарок.общий.загрузить(цель)
        guard !Task.isCancelled, let новый = пришёл else { return }
        рисунок = новый
        чей = цель
    }
}

/// Контур SVG, вписанный в рамку с сохранением пропорций, по центру.
private struct ФормаЛоготипаМарки: Shape {
    let контур: Path
    let холст: CGRect

    func path(in rect: CGRect) -> Path {
        guard холст.width > 0, холст.height > 0 else { return Path() }
        let k = min(rect.width / холст.width, rect.height / холст.height)
        let сдвигX = rect.minX + (rect.width - холст.width * k) / 2 - холст.minX * k
        let сдвигY = rect.minY + (rect.height - холст.height * k) / 2 - холст.minY * k
        let t = CGAffineTransform(translationX: сдвигX, y: сдвигY).scaledBy(x: k, y: k)
        return контур.applying(t)
    }
}

/// Разбор SVG знака: холст (viewBox, иначе width/height, иначе 24 × 24) и все path d="…" одним контуром.
enum РазборЛоготипаSVG {
    static func разобрать(_ svg: String) -> (Path, CGRect)? {
        let холст = холстSVG(svg)
        var итог = Path()
        var есть = false
        for d in значения(svg, шаблон: "<path\\b[^>]*?\\sd\\s*=\\s*[\"']([^\"']+)[\"']") {
            var разбор = РазборКонтураSVG(d)
            let контур = разбор.контур()
            if !контур.isEmpty {
                итог.addPath(контур)
                есть = true
            }
        }
        guard есть else { return nil }
        return (итог, холст)
    }

    private static func холстSVG(_ svg: String) -> CGRect {
        if let вид = значения(svg, шаблон: "viewBox\\s*=\\s*[\"']([^\"']+)[\"']").first {
            let числа = вид.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" })
                .compactMap { Double(String($0)) }
            if числа.count == 4, числа[2] > 0, числа[3] > 0 {
                return CGRect(x: числа[0], y: числа[1], width: числа[2], height: числа[3])
            }
        }
        let ш = значения(svg, шаблон: "<svg\\b[^>]*?\\swidth\\s*=\\s*[\"']([0-9.]+)").first.flatMap { Double($0) } ?? 24
        let в = значения(svg, шаблон: "<svg\\b[^>]*?\\sheight\\s*=\\s*[\"']([0-9.]+)").first.flatMap { Double($0) } ?? 24
        return CGRect(x: 0, y: 0, width: ш > 0 ? ш : 24, height: в > 0 ? в : 24)
    }

    /// Первая группа каждого совпадения.
    private static func значения(_ текст: String, шаблон: String) -> [String] {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: [.caseInsensitive]) else { return [] }
        let весь = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        return выражение.matches(in: текст, options: [], range: весь).compactMap { совпадение in
            guard совпадение.numberOfRanges > 1, let r = Range(совпадение.range(at: 1), in: текст) else { return nil }
            return String(текст[r])
        }
    }
}

/// Разбор атрибута d: M L H V C S Q T A Z, строчные — относительные, повтор чисел без буквы — та же команда
/// (после M — L). Ошибка в данных — возвращается то, что успело сложиться.
struct РазборКонтураSVG {
    private let б: [UInt8]
    private var и = 0

    init(_ d: String) {
        б = Array(d.utf8)
    }

    private static let буквыКоманд: Set<UInt8> = Set("MmLlHhVvCcSsQqTtAaZz".utf8)

    private mutating func пропуститьРазделители() {
        while и < б.count {
            let c = б[и]
            if c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D {
                и += 1
            } else {
                break
            }
        }
    }

    private static func цифра(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

    private mutating func число() -> CGFloat? {
        пропуститьРазделители()
        let старт = и
        if и < б.count && (б[и] == 0x2B || б[и] == 0x2D) { и += 1 }
        var цифры = false
        var точка = false
        while и < б.count {
            let c = б[и]
            if Self.цифра(c) {
                цифры = true
                и += 1
            } else if c == 0x2E && !точка {
                точка = true
                и += 1
            } else {
                break
            }
        }
        if цифры && и < б.count && (б[и] == 0x65 || б[и] == 0x45) {
            var j = и + 1
            if j < б.count && (б[j] == 0x2B || б[j] == 0x2D) { j += 1 }
            if j < б.count && Self.цифра(б[j]) {
                и = j
                while и < б.count && Self.цифра(б[и]) { и += 1 }
            }
        }
        guard цифры else {
            и = старт
            return nil
        }
        var запись = String(decoding: б[старт..<и], as: UTF8.self)
        if запись.hasPrefix("+") { запись.removeFirst() }
        if запись.hasSuffix(".") { запись += "0" }
        if запись.hasPrefix(".") { запись = "0" + запись }
        if запись.hasPrefix("-.") { запись = "-0" + String(запись.dropFirst()) }
        guard let значение = Double(запись) else {
            и = старт
            return nil
        }
        return CGFloat(значение)
    }

    /// Флаг дуги — одна цифра 0 или 1, может стоять вплотную к следующему числу («a1 1 0 011 1»).
    private mutating func флаг() -> Bool? {
        пропуститьРазделители()
        guard и < б.count else { return nil }
        if б[и] == 0x30 {
            и += 1
            return false
        }
        if б[и] == 0x31 {
            и += 1
            return true
        }
        return nil
    }

    private mutating func точка(_ база: CGPoint) -> CGPoint? {
        guard let x = число(), let y = число() else { return nil }
        return CGPoint(x: база.x + x, y: база.y + y)
    }

    mutating func контур() -> Path {
        var p = Path()
        var текущая = CGPoint.zero
        var начало = CGPoint.zero
        var упрКуб: CGPoint? = nil
        var упрКв: CGPoint? = nil
        var команда: UInt8 = 0
        var перваяПара = false
        var начат = false
        while true {
            пропуститьРазделители()
            guard и < б.count else { break }
            let c = б[и]
            if Self.буквыКоманд.contains(c) {
                команда = c
                и += 1
                перваяПара = true
                if c == 0x5A || c == 0x7A {
                    if начат { p.closeSubpath() }
                    текущая = начало
                    упрКуб = nil
                    упрКв = nil
                    continue
                }
            } else if команда == 0 || команда == 0x5A || команда == 0x7A {
                break
            }
            let отн = команда >= 0x61
            let база = отн ? текущая : CGPoint.zero
            let строчная = команда | 0x20
            // Начала контура нет (первая команда не M) — начинаем с текущей точки.
            if строчная != 0x6D && !начат {
                p.move(to: текущая)
                начало = текущая
                начат = true
            }
            var новыйКуб: CGPoint? = nil
            var новыйКв: CGPoint? = nil
            switch строчная {
            case 0x6D: // m
                guard let т = точка(база) else { return p }
                if перваяПара {
                    p.move(to: т)
                    начало = т
                    начат = true
                } else {
                    p.addLine(to: т)
                }
                текущая = т
            case 0x6C: // l
                guard let т = точка(база) else { return p }
                p.addLine(to: т)
                текущая = т
            case 0x68: // h
                guard let x = число() else { return p }
                let т = CGPoint(x: отн ? текущая.x + x : x, y: текущая.y)
                p.addLine(to: т)
                текущая = т
            case 0x76: // v
                guard let y = число() else { return p }
                let т = CGPoint(x: текущая.x, y: отн ? текущая.y + y : y)
                p.addLine(to: т)
                текущая = т
            case 0x63: // c
                guard let у1 = точка(база), let у2 = точка(база), let т = точка(база) else { return p }
                p.addCurve(to: т, control1: у1, control2: у2)
                новыйКуб = у2
                текущая = т
            case 0x73: // s
                guard let у2 = точка(база), let т = точка(база) else { return p }
                var у1 = текущая
                if let прошлая = упрКуб {
                    у1 = CGPoint(x: 2 * текущая.x - прошлая.x, y: 2 * текущая.y - прошлая.y)
                }
                p.addCurve(to: т, control1: у1, control2: у2)
                новыйКуб = у2
                текущая = т
            case 0x71: // q
                guard let у = точка(база), let т = точка(база) else { return p }
                p.addQuadCurve(to: т, control: у)
                новыйКв = у
                текущая = т
            case 0x74: // t
                guard let т = точка(база) else { return p }
                var у = текущая
                if let прошлая = упрКв {
                    у = CGPoint(x: 2 * текущая.x - прошлая.x, y: 2 * текущая.y - прошлая.y)
                }
                p.addQuadCurve(to: т, control: у)
                новыйКв = у
                текущая = т
            case 0x61: // a
                guard let rx = число(), let ry = число(), let поворот = число(),
                      let большая = флаг(), let поЧасовой = флаг(), let т = точка(база) else { return p }
                Self.дуга(&p, от: текущая, до: т, rx: rx, ry: ry, поворот: поворот,
                          большая: большая, поЧасовой: поЧасовой)
                текущая = т
            default:
                return p
            }
            упрКуб = новыйКуб
            упрКв = новыйКв
            перваяПара = false
        }
        return p
    }

    /// Дуга SVG (конечные точки) → центр и углы (SVG 1.1, F.6.5) → addRelativeArc единичного круга с переносом.
    private static func дуга(_ p: inout Path, от a: CGPoint, до b: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                             поворот: CGFloat, большая: Bool, поЧасовой: Bool) {
        if a == b { return }
        var rx = abs(rx0)
        var ry = abs(ry0)
        if rx == 0 || ry == 0 {
            p.addLine(to: b)
            return
        }
        let φ = поворот * .pi / 180
        let cosφ = cos(φ)
        let sinφ = sin(φ)
        let dx = (a.x - b.x) / 2
        let dy = (a.y - b.y) / 2
        let x1 = cosφ * dx + sinφ * dy
        let y1 = -sinφ * dx + cosφ * dy
        let λ = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if λ > 1 {
            rx *= λ.squareRoot()
            ry *= λ.squareRoot()
        }
        let rx2 = rx * rx
        let ry2 = ry * ry
        let знаменатель = rx2 * y1 * y1 + ry2 * x1 * x1
        guard знаменатель > 0 else {
            p.addLine(to: b)
            return
        }
        let числитель = rx2 * ry2 - знаменатель
        var коэф = (max(0, числитель / знаменатель)).squareRoot()
        if большая == поЧасовой { коэф = -коэф }
        let cx1 = коэф * rx * y1 / ry
        let cy1 = -коэф * ry * x1 / rx
        let cx = cosφ * cx1 - sinφ * cy1 + (a.x + b.x) / 2
        let cy = sinφ * cx1 + cosφ * cy1 + (a.y + b.y) / 2
        let ux = (x1 - cx1) / rx
        let uy = (y1 - cy1) / ry
        let vx = (-x1 - cx1) / rx
        let vy = (-y1 - cy1) / ry
        let θ1 = atan2(uy, ux)
        var Δ = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !поЧасовой && Δ > 0 { Δ -= 2 * .pi }
        if поЧасовой && Δ < 0 { Δ += 2 * .pi }
        let перенос = CGAffineTransform(translationX: cx, y: cy).rotated(by: φ).scaledBy(x: rx, y: ry)
        p.addRelativeArc(center: .zero, radius: 1, startAngle: Angle(radians: Double(θ1)),
                         delta: Angle(radians: Double(Δ)), transform: перенос)
    }
}

extension МодельАвто {
    /// Годы выпуска модели по поколениям справочника: «2012–2022», «2006–н.в.»; поколений с годами нет — "".
    func годыВыпуска(сейчас: String) -> String {
        let сГодами = поколения.filter { $0.с > 0 }
        guard let первый = сГодами.map({ $0.с }).min() else { return "" }
        if сГодами.contains(where: { $0.по <= 0 }) { return String(первый) + "–" + сейчас }
        let последний = сГодами.map { $0.по }.max() ?? первый
        return последний > первый ? String(первый) + "–" + String(последний) : String(первый)
    }
}
