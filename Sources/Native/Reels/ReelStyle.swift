import UIKit

/**
 СТУДИЯ РОЛИКОВ — стили, раскладка времени и шрифты модуля js/cabinet-reel.min.js сайта (владелец 26.09.2026: «рилс
 студио тоже внедри»).

 Сайт рисует ролик на холсте 1080 × 1920, 30 кадров в секунду, H.264 9 Мбит/с; звук — «Фирменный звук Kliko», который
 синтезируется на месте (треков-файлов у сайта нет). Ход ролика (_ сайта): заставка 0,5 с, по 2 с на каждое фото (от 1 до
 5), концовка 1,4 с. Пять стилей (m сайта): фон-градиент, акцент, шрифт заголовков и текста, форма цены и переход между
 фото. Стиль при открытии выбирается случайно, «Стиль» — другой случайный.

 Шрифты сайта (Unbounded, Oswald, Montserrat, Manrope из Google Fonts) в приложении не встроены: вместо них системный
 шрифт той же ширины и веса — Unbounded широким, Oswald узким, Montserrat и Manrope обычным.
 */
struct СтильРолика: Equatable, Identifiable {
    enum ФормаЦены: Equatable { case пилюля, ярлык, значок, крупно }
    enum Переход: Equatable { case растворение, сдвиг, толчок }

    let id: String
    let ключИмени: String
    /// bg[0], bg[1].
    let фон: (UInt32, UInt32)
    let акцент: UInt32
    /// disp и body сайта.
    let заголовки: String
    let текст: String
    let цена: ФормаЦены
    let переход: Переход

    static func == (a: СтильРолика, b: СтильРолика) -> Bool { a.id == b.id }

    static let все: [СтильРолика] = [
        СтильРолика(id: "emerald", ключИмени: "st_emerald", фон: (0x0F7A44, 0x07130D), акцент: 0x20C274,
                    заголовки: "Unbounded", текст: "Manrope", цена: .пилюля, переход: .растворение),
        СтильРолика(id: "noir", ключИмени: "st_noir", фон: (0x181613, 0x000000), акцент: 0xE8B84B,
                    заголовки: "Oswald", текст: "Montserrat", цена: .ярлык, переход: .сдвиг),
        СтильРолика(id: "violet", ключИмени: "st_violet", фон: (0x3A1C71, 0x0D0A1E), акцент: 0xFFD23F,
                    заголовки: "Montserrat", текст: "Manrope", цена: .значок, переход: .толчок),
        СтильРолика(id: "minimal", ключИмени: "st_minimal", фон: (0x0B0B0B, 0x000000), акцент: 0xFFFFFF,
                    заголовки: "Manrope", текст: "Manrope", цена: .крупно, переход: .растворение),
        СтильРолика(id: "sunset", ключИмени: "st_sunset", фон: (0xFF512F, 0x190A05), акцент: 0xFFD200,
                    заголовки: "Unbounded", текст: "Manrope", цена: .пилюля, переход: .толчок)
    ]

    /// g сайта: случайный номер, не совпадающий с прежним.
    static func случайный(кроме прежний: Int) -> Int {
        guard все.count > 1 else { return 0 }
        var номер = Int.random(in: 0..<все.count)
        while номер == прежний { номер = Int.random(in: 0..<все.count) }
        return номер
    }

    /// v сайта: светлый акцент (яркость > 150) — текст на нём тёмный #141414.
    var светлыйАкцент: Bool {
        let r = Double((акцент >> 16) & 0xFF)
        let g = Double((акцент >> 8) & 0xFF)
        let b = Double(акцент & 0xFF)
        return 0.299 * r + 0.587 * g + 0.114 * b > 150
    }

    /// h сайта: вес шрифта заголовков.
    var весЗаголовков: String {
        switch заголовки {
        case "Manrope": return "800"
        case "Oswald": return "700"
        default: return "900"
        }
    }
}

/// _ сайта: n фото (1…5), заставка, по фото, концовка.
struct ТаймлайнРолика: Equatable {
    let фото: Int
    let заставка: Double = 0.5
    let наФото: Double = 2
    let концовка: Double = 1.4

    init(фото: Int) {
        self.фото = max(1, min(5, фото))
    }

    var всего: Double { заставка + наФото * Double(фото) + концовка }

    static let кадровВСекунду: Int32 = 30
    static let ширина = 1080
    static let высота = 1920
    static let битрейт = 9_000_000
}

/// Шрифты, плавность и краски холста — общие для превью и записи. Всё без главной нити: запись идёт в фоне.
enum КраскиРолика {
    /// y(семейство, вес, размер) сайта → системный шрифт той же ширины.
    static func шрифт(_ семейство: String, _ вес: String, _ размер: CGFloat) -> UIFont {
        let толщина: UIFont.Weight
        switch вес {
        case "900": толщина = .black
        case "800": толщина = .heavy
        case "700": толщина = .bold
        case "600": толщина = .semibold
        default: толщина = .medium
        }
        let ширина: UIFont.Width
        switch семейство {
        case "Unbounded": ширина = .expanded
        case "Oswald": ширина = .condensed
        default: ширина = .standard
        }
        return UIFont.systemFont(ofSize: размер, weight: толщина, width: ширина)
    }

    static func цвет(_ v: UInt32, _ альфа: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: альфа)
    }

    static func белый(_ альфа: CGFloat) -> UIColor { UIColor(white: 1, alpha: альфа) }

    /// T сайта.
    static func предел(_ v: Double, _ a: Double = 0, _ b: Double = 1) -> Double { v < a ? a : (v > b ? b : v) }

    /// k (eO) сайта: плавный выход.
    static func выход(_ t: Double) -> Double {
        let x = предел(t)
        return 1 - pow(1 - x, 3)
    }

    /// C (bk) сайта: выход с перелётом.
    static func перелёт(_ t: Double) -> Double {
        let x = предел(t)
        let c1 = 1.70158
        return 1 + (c1 + 1) * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    /// eIO сайта.
    static func входВыход(_ t: Double) -> Double {
        let x = предел(t)
        return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }
}
