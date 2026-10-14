import SwiftUI
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА В КАМЕРЕ — ЧТО ПРИМЕРЯЕМ И КАК ОТКРЫТЬ (владелец 13.10.2026: «распиши примерочную; нужен ли 3D — очки,
 шины, диски?» → «нужнее охват всего»).

 Настоящий 3D не нужен: у продавцов нет 3D-моделей. Вещь берётся с фото объявления — Vision на телефоне отделяет её от
 фона (LiveTryOnCutout.swift) — и кладётся поверх живой камеры туда, где ей место: очки — на глаза, головной убор — на
 лоб, серьги — к мочкам, колье — под подбородок (лицо, VNDetectFaceLandmarksRequest, передняя камера); часы и браслет —
 на запястье, кольцо — на безымянный палец (рука, VNDetectHumanHandPoseRequest, задняя камера). Без сервера: ни видео,
 ни фото никуда не уходят. Камера и анализ — LiveTryOnCamera.swift, посадка — LiveTryOnFit.swift, состояние —
 LiveTryOnModel.swift, экран — LiveTryOnScreen.swift, тексты — LiveTryOnText.swift.

 Вход один — хаб «Примерить / проверить» (TryOnHub.swift): кнопка есть, когда включён его рубильник
 Config.живаяПримерка и ОкноЖивойПримерки.подходит(товар); по нажатию хаб зовёт ОкноЖивойПримерки.открыть(товар:фото:).
 */
enum ВидЖивойПримерки: String, CaseIterable, Sendable {
    case очки
    case шапка
    case серьги
    case колье
    case часы
    case браслет
    case кольцо

    /// Вещь на лице или голове — смотрим лицо; иначе — руку.
    var лицо: Bool {
        switch self {
        case .очки, .шапка, .серьги, .колье: return true
        case .часы, .браслет, .кольцо: return false
        }
    }

    /// С какой камеры начинать: лицо — с передней (как в зеркале), руку — с задней (другая рука держит телефон).
    var передняя: Bool { лицо }

    /// Серьги — парой: у левой и у правой мочки.
    var пара: Bool { self == .серьги }

    /// Ключ текстов (lt_kind_…).
    var ключ: String {
        switch self {
        case .очки: return "glasses"
        case .шапка: return "hat"
        case .серьги: return "earrings"
        case .колье: return "necklace"
        case .часы: return "watch"
        case .браслет: return "bracelet"
        case .кольцо: return "ring"
        }
    }

    var название: String { ЖиваяПримеркаText.т("lt_kind_" + ключ) }

    /// Значок вида (SF Symbols из iOS 14 и раньше).
    var значок: String {
        switch self {
        case .очки: return "eyeglasses"
        case .шапка: return "face.smiling"
        case .серьги, .колье: return "sparkles"
        case .часы: return "clock"
        case .браслет, .кольцо: return "hand.raised"
        }
    }

    // MARK: Раздел объявления → вид

    /// Листья дерева сайта (РазделыСайта) с точным видом. Их потомки — тот же вид.
    static let поРазделу: [String: ВидЖивойПримерки] = [
        "sunglasses": .очки, "optics-glasses": .очки, "optics-sun": .очки,
        "hats": .шапка,
        "earrings": .серьги,
        "necklaces": .колье,
        "watches": .часы, "smartwatches": .часы,
        "bracelets": .браслет,
        "rings": .кольцо
    ]

    /// Общие разделы: объявление положили прямо в них, без листа, — вид угадываем по названию.
    static let общиеРазделы: Set<String> = ["jewelry", "bags-accessories", "beauty-optics"]

    /// Все разделы с живой примеркой — листья с точным видом и общие разделы (список хаба, ПодборПримерки.разделыЖивой).
    /// 🔴 Только справочно: в общих разделах вид решает название (сумка из bags-accessories примерки не получит), поэтому
    /// есть ли кнопка у объявления — только ОкноЖивойПримерки.подходит, а не «раздел внутри этого списка».
    static var всеРазделы: Set<String> { Set(поРазделу.keys).union(общиеРазделы) }

    /// Вид примерки объявления: по разделу (и его предкам), в общих разделах — по названию. nil — живой примерки нет.
    static func для(_ товар: Listing) -> ВидЖивойПримерки? {
        guard let раздел = товар.категория?.trimmingCharacters(in: .whitespacesAndNewlines), !раздел.isEmpty else {
            return nil
        }
        var текущий: String? = раздел
        var шаги = 0
        while let т = текущий, шаги < 25 {
            if let вид = поРазделу[т] { return вид }
            текущий = РазделыСайта.родитель(т)
            шаги += 1
        }
        guard общиеРазделы.contains(раздел) else { return nil }
        return поНазванию(товар.title)
    }

    /// По словам названия (ru, kk, en). Серьги раньше кольца: «earring» не должно стать «ring».
    static func поНазванию(_ название: String) -> ВидЖивойПримерки? {
        let слова = название.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        func начало(_ основы: [String]) -> Bool {
            слова.contains { слово in основы.contains { слово.hasPrefix($0) } }
        }
        func целиком(_ варианты: Set<String>) -> Bool {
            слова.contains { варианты.contains($0) }
        }
        if начало(["серьг", "серёж", "сереж", "пусет", "сырға", "earring"]) { return .серьги }
        if начало(["очк", "оправ", "көзілдір", "sunglass", "eyeglass"]) || целиком(["glasses"]) { return .очки }
        if начало(["наручн", "сағат", "smartwatch"]) || целиком(["часы", "часов", "watch", "watches"]) { return .часы }
        if начало(["браслет", "білезік", "bracelet", "bangle"]) { return .браслет }
        if начало(["кольц", "перстен", "сақина"]) || целиком(["ring", "rings"]) { return .кольцо }
        if начало(["колье", "цепоч", "кулон", "ожерел", "подвеск", "алқа", "necklace", "pendant"])
            || целиком(["chain"]) { return .колье }
        if начало(["шапк", "кепк", "бейсбол", "панам", "шляп", "берет", "бөрік", "beanie"])
            || целиком(["cap", "hat", "hats", "caps"]) { return .шапка }
        return nil
    }

    // MARK: Настоящий размер из характеристик

    /**
     Размер вещи в миллиметрах из характеристик объявления, если продавец его указал: у очков — ширина оправы (или по
     ширине линзы, или «52-18-140» — линза, перемычка, дужка), у часов — диаметр корпуса. Нет или странное — nil, и
     посадка берёт средний размер.
     */
    static func размерМм(_ товар: Listing, вид: ВидЖивойПримерки) -> Double? {
        switch вид {
        case .очки:
            for пункт in товар.характеристики {
                let имя = пункт.ключ.lowercased()
                let значение = пункт.значение.lowercased()
                if let тройка = маркировкаОправы(значение) { return тройка }
                guard имя.contains("ширин") || имя.contains("width") || имя.contains("ені") else { continue }
                guard let число = первоеЧисло(значение) else { continue }
                if имя.contains("линз") || имя.contains("lens") || имя.contains("стекл") || имя.contains("линза") {
                    if (40...70).contains(число) { return число * 2 + 34 }
                } else if (110...170).contains(число) {
                    return число
                }
            }
            return nil
        case .часы:
            for пункт in товар.характеристики {
                let имя = пункт.ключ.lowercased()
                guard имя.contains("диаметр") || имя.contains("diameter") || имя.contains("корпус")
                        || имя.contains("case") else { continue }
                if let число = первоеЧисло(пункт.значение), (20...60).contains(число) { return число }
            }
            return nil
        case .шапка, .серьги, .колье, .браслет, .кольцо:
            return nil
        }
    }

    /// Первое число строки: «42 мм» → 42, «52,5» → 52.5.
    private static func первоеЧисло(_ строка: String) -> Double? {
        guard let место = строка.range(of: "[0-9]+([.,][0-9]+)?", options: .regularExpression) else { return nil }
        return Double(строка[место].replacingOccurrences(of: ",", with: "."))
    }

    /// Маркировка оправы «52-18-140» или «52□18 140»: ширина ≈ две линзы, перемычка и по 7 мм на края.
    private static func маркировкаОправы(_ строка: String) -> Double? {
        let образец = "([4-6][0-9])\\s*[-–□x×]\\s*([1-2][0-9])\\s*[-–\\s]\\s*1[2-5][0-9]"
        guard let место = строка.range(of: образец, options: .regularExpression) else { return nil }
        let числа = строка[место]
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Double(String($0)) }
        guard числа.count >= 2 else { return nil }
        let итог = числа[0] * 2 + числа[1] + 14
        return (110...170).contains(итог) ? итог : nil
    }
}

// MARK: - Окно

/**
 Публичная точка входа. Экран — во весь экран (камера — не лист: смахивание листа спорило бы с пальцем, которым
 двигают вещь), тёмный всегда. Защита от двойного нажатия — как у ПоверхВсего: второе такое же окно за секунду не
 кладём поверх первого.
 */
@MainActor
enum ОкноЖивойПримерки {
    private static var последнееОткрытие: Date? = nil

    /// Есть ли у объявления живая примерка (без рубильника хаба — его проверяет хаб): фото и подходящий вид.
    static func подходит(_ товар: Listing) -> Bool {
        !товар.фотоАдреса.isEmpty && ВидЖивойПримерки.для(товар) != nil
    }

    /// Открыть живую примерку. фото — номер фото галереи на экране: его и примеряем первым.
    static func открыть(товар: Listing, фото: Int) {
        guard !товар.фотоАдреса.isEmpty, let вид = ВидЖивойПримерки.для(товар) else { return }
        let сейчас = Date()
        if let прежнее = последнееОткрытие, сейчас.timeIntervalSince(прежнее) < 1 { return }
        последнееОткрытие = сейчас
        let всего = товар.фотоАдреса.count
        let номер = min(max(0, фото), всего - 1)
        Task { @MainActor in
            for попытка in 0..<12 {
                if let верх = верхний() {
                    let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
                    let закрыть: () -> Void = { [weak хост] in
                        хост?.dismiss(animated: true)
                    }
                    хост.rootView = AnyView(ЭкранЖивойПримерки(товар: товар, вид: вид, фото: номер, закрыть: закрыть))
                    хост.modalPresentationStyle = .fullScreen
                    хост.overrideUserInterfaceStyle = .dark
                    хост.view.backgroundColor = .black
                    верх.present(хост, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: попытка == 0 ? 120_000_000 : 250_000_000)
            }
        }
    }

    /// Верхний показанный контроллер ключевого окна; nil — что-то ещё уезжает или приезжает.
    private static func верхний() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first,
              var верх = окно.rootViewController else { return nil }
        while let следующий = верх.presentedViewController {
            if следующий.isBeingDismissed || следующий.isBeingPresented { return nil }
            верх = следующий
        }
        if верх.isBeingDismissed { return nil }
        return верх
    }
}
