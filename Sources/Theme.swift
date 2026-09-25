import SwiftUI
import UIKit

/// Бренд Kliko.kz — зелёная палитра (зеркалит веб --mk-green).
enum Theme {
    static let green   = Color(red: 0.06, green: 0.32, blue: 0.20)   // #0F5132 бренд
    static let green2  = Color(red: 0.10, green: 0.62, blue: 0.41)   // акцент светлее
    static let mint    = Color(red: 0.91, green: 0.96, blue: 0.93)   // подложка
    static let ink     = Color(red: 0.08, green: 0.13, blue: 0.10)
    static let muted   = Color(red: 0.42, green: 0.49, blue: 0.45)

    /*
     ЭТАП 24 — ДИЗАЙН-ТОКЕНЫ САЙТА (владелец 25.09.2026: «приложение должно быть почти 100% похоже на сайт, только
     нативное SwiftUI — такой же красивый, как сайт»).

     Значения — из CSS сайта, а не на глаз: :root и [data-theme=dark] в css/marketplace.min.css (--mk-ink, --mk-surf,
     --mk-surf2, --mk-line, --mk-green2, --mk-gold…), акцент тёмной темы — html[data-theme=dark] (--g, --g2, --g3),
     шапка — <style id="mk-gtop-css"> главной, нижняя панель — <style id="ulx-bbar-css">, плитки и ряды — css/marketplace-
     home.min.css. Сайт меняет тему атрибутом data-theme, приложение — окном (этап 15, overrideUserInterfaceStyle),
     поэтому каждый цвет — динамический UIColor: он сам берёт светлое или тёмное значение по теме окна, и SwiftUI
     перекрашивает экран без перезапуска.

     Прежние пять имён выше не трогаем: ими живёт прежний вид (Config.дизайнКакНаСайте = false), и смена их значений
     перекрасила бы его.
     */

    // MARK: - Страница и поверхности

    /// Фон страницы: body сайта — var(--mk-surf2): #f4f8f6 и #1c1c26.
    static let фонСтраницы = цвет(0xF4F8F6, 0x1C1C26)
    /// Карточка, плашки, нижняя панель: --mk-surf — #fff и #16161f.
    static let поверхность = цвет(0xFFFFFF, 0x16161F)
    /// Подложка фото и полей: --mk-surf2.
    static let поверхность2 = цвет(0xF4F8F6, 0x1C1C26)
    /// Тонкая линия: --mk-line — #e3ece7 и белый 10 %.
    static let линия = цвет(светлый: hex(0xE3ECE7), тёмный: hex(0xFFFFFF, 0.10))

    // MARK: - Текст

    /// Основной текст: --mk-ink — #13211b и #eaf3ee.
    static let текст = цвет(0x13211B, 0xEAF3EE)
    /// Второстепенный: --mk-muted — #5f6c63 и #90a499.
    static let текстВторой = цвет(0x5F6C63, 0x90A499)

    // MARK: - Зелёные

    /// Бренд: --mk-green, в тёмной теме — --g (#22a05b).
    static let зелёный = цвет(0x0F5132, 0x22A05B)
    /// Второй зелёный: --mk-green2, в тёмной — --g2 (#34c997).
    static let зелёный2 = цвет(0x1D7D4A, 0x34C997)
    /// Яркий: --mk-bright, в тёмной — --g3 (#5cd39a).
    static let зелёныйЯркий = цвет(0x16A34A, 0x5CD39A)
    /// Активный пункт и ссылки: --acc-on — --mk-green2 (#1d7d4a) и --g3 (#5cd39a).
    static let акцент = цвет(0x1D7D4A, 0x5CD39A)

    // MARK: - Шапка главной (html.mk-gtop .mk-topbar)

    /// Градиент шапки сверху вниз: #1b7a4d → #166b46 → #136141, в тёмной — #0f2a22 → #122f26 → #12332a.
    static let шапкаВерх = цвет(0x1B7A4D, 0x0F2A22)
    static let шапкаСередина = цвет(0x166B46, 0x122F26)
    static let шапкаНиз = цвет(0x136141, 0x12332A)
    /// Блик шапки слева сверху (radial-gradient): rgba(190,240,215,.16) и rgba(163,220,192,.1).
    static let шапкаБлик = цвет(светлый: hex(0xBEF0D7, 0.16), тёмный: hex(0xA3DCC0, 0.10))
    /// Мятный акцент шапки: «.kz» надписи, плашка значка города, стрелка — #a3dcc0 в обеих темах.
    static let шапкаМята = Color(uiColor: hex(0xA3DCC0))
    /// Значок на мятной плашке города — #12332a.
    static let шапкаМятаТекст = Color(uiColor: hex(0x12332A))
    /// Кнопки на шапке (тема, карта): белый 12 % и рамка белый 18 %; в тёмной — белый 8 %.
    static let шапкаКнопка = цвет(светлый: hex(0xFFFFFF, 0.12), тёмный: hex(0xFFFFFF, 0.08))
    static let шапкаКнопкаРамка = Color.white.opacity(0.18)
    /// Поле поиска на шапке: #fff и #15201a.
    static let полеПоиска = цвет(0xFFFFFF, 0x15201A)
    /// Кружок камеры в поле: #f1f4f2 и белый 8 %.
    static let полеПоискаКнопка = цвет(светлый: hex(0xF1F4F2), тёмный: hex(0xFFFFFF, 0.08))

    // MARK: - ТОП, избранное, счётчик

    /// Золото: --mk-gold — #bf922a и #e0bd5e.
    static let золото = цвет(0xBF922A, 0xE0BD5E)
    /// Метка «★ ТОП»: linear-gradient(135deg, #d9b24c, #b88a1e) — одинаковая в обеих темах.
    static let топНачало = Color(uiColor: hex(0xD9B24C))
    static let топКонец = Color(uiColor: hex(0xB88A1E))
    /// Рамка карточки в ТОПе: 1.5px #d9b24c, в тёмной — #b8923a.
    static let топРамка = цвет(0xD9B24C, 0xB8923A)
    /// Подложка карточки в ТОПе: сверху 9 % золота к поверхности (в тёмной 12 %), к середине — чистая поверхность.
    static let топФон = цвет(светлый: смесь(hex(0xD9B24C), .white, 0.09), тёмный: смесь(hex(0xD9B24C), hex(0x16161F), 0.12))
    /// Сердечко в избранном и счётчик на панели: #e0245e.
    static let сердце = Color(uiColor: hex(0xE0245E))

    // MARK: - Нижняя панель (.ulx-bbar)

    /// Фон панели: #fff и #16161f.
    static let панель = цвет(0xFFFFFF, 0x16161F)
    /// Пункт панели: #5f6c63 и #90a499; выбранный — --acc-on.
    static let панельПункт = цвет(0x5F6C63, 0x90A499)
    /// Кнопка камеры: linear-gradient(135deg, var(--g,#1d7d4a), var(--g2,#16a34a)); в тёмной --g #22a05b, --g2 #34c997.
    static let кнопкаКамерыНачало = цвет(0x1D7D4A, 0x22A05B)
    static let кнопкаКамерыКонец = цвет(0x16A34A, 0x34C997)
    /// Кромка панели сверху: зелёный 50 % по центру (светлая), мятный 42 % (тёмная).
    static let панельКромка = цвет(светлый: hex(0x1D7D4A, 0.5), тёмный: hex(0xA3DCC0, 0.42))

    // MARK: - Страница объявления (этап 28, .mk-modal сайта в css/marketplace.min.css)

    /// Подложка значков подзаголовков («ОПИСАНИЕ», «ПРОДАВЕЦ УТВЕРЖДАЕТ»): --mk-mint — #e7f6ee и rgba(22,48,36,.5).
    static let мята = цвет(светлый: hex(0xE7F6EE), тёмный: hex(0x163024, 0.5))
    /// Ключевой пункт «Продавец утверждает» (.is-key): --acc-tint rgba(29,125,74,.10); в тёмной все пункты —
    /// rgba(52,201,151,.14) (html[data-theme=dark] .mk-trustbox-i).
    static let оттенокАкцента = цвет(светлый: hex(0x1D7D4A, 0.10), тёмный: hex(0x34C997, 0.14))
    /// Рамка пункта «Продавец утверждает»: линия, в тёмной — rgba(52,201,151,.3).
    static let рамкаПункта = цвет(светлый: hex(0xE3ECE7), тёмный: hex(0x34C997, 0.30))
    /// Обычный пункт: серый текст на поверхности; в тёмной — зелёный акцент, как ключевой.
    static let текстПункта = цвет(0x5F6C63, 0x5CD39A)
    static let фонПункта = цвет(светлый: hex(0xFFFFFF), тёмный: hex(0x34C997, 0.14))
    /// Метка «Б/У» на фото (.mk-gcond.used): #b8620c, в тёмной #c96f14. «Новое» — --mk-green2.
    static let меткаБУ = цвет(0xB8620C, 0xC96F14)
    /// Подложка фото (.mk-gslide): #0d1512 в обеих темах.
    static let подложкаФото = Color(uiColor: hex(0x0D1512))
    /// Кнопки над фото (.mk-mhead .mk-mbtn): rgba(14,20,17,.45) с размытием.
    static let кнопкаНадФото = Color(uiColor: hex(0x0E1411, 0.45))
    /// Звезда рейтинга (.mk-st.full): #b07a06 и #e0bd5e.
    static let звезда = цвет(0xB07A06, 0xE0BD5E)
    /// Цена со скидкой (.mk-price-drop) — #dc2626; «↓ N%» (.mk-pricedrop-badge): #fee2e2/#b91c1c, в тёмной #3a1414/#f87171.
    static let ценаСкидка = Color(uiColor: hex(0xDC2626))
    static let скидкаФон = цвет(0xFEE2E2, 0x3A1414)
    static let скидкаТекст = цвет(0xB91C1C, 0xF87171)
    /// Режим работы: «не на месте» — #d97706 (.mk-hours.away), «закрыто» у магазина — #e11d48 (.mk-hours.off).
    static let оранжевый = Color(uiColor: hex(0xD97706))
    static let малиновый = Color(uiColor: hex(0xE11D48))
    /// Значок «Проверен через eGov» (VFY сайта) — #1d9bf0.
    static let проверен = Color(uiColor: hex(0x1D9BF0))

    // MARK: - Нижняя панель объявления (этап 29, .mk-stickyone и .mk-sb-*)

    /// Пилюля: linear-gradient(135deg, #1d7d4a, #0f5132) — одинаковая в обеих темах, белый текст на ней читается и там.
    static let панельСвязиНачало = Color(uiColor: hex(0x1D7D4A))
    static let панельСвязиКонец = Color(uiColor: hex(0x0F5132))
    /// Левая часть пилюли (.mk-stickyone .mk-mescrow): #1d7d4a → #116039.
    static let кнопкаСвязиКонец = Color(uiColor: hex(0x116039))
    /// Кнопка WhatsApp (.mk-sb-wa) — #25d366.
    static let whatsApp = Color(uiColor: hex(0x25D366))

    // MARK: - Чат (этап 30, .kc-* в css/chat.min.css)

    /// Своё сообщение (.kc-msg.me): --kc-acc = --mk-bright #16a34a; в тёмной — --acc-on #5cd39a под 44 % чёрного
    /// (linear-gradient(rgba(0,0,0,.44)…) — #337656: белый текст на нём читается.
    static let пузырьМой = цвет(0x16A34A, 0x337656)
    /// Чужое сообщение (.kc-msg.peer): --kc-peer = --mk-surf2.
    static let пузырьЧужой = цвет(0xF4F8F6, 0x1C1C26)
    /// Счётчик непрочитанных в списке диалогов: --kc-unread #ef4444.
    static let непрочитано = Color(uiColor: hex(0xEF4444))

    // MARK: - Скругления (--r-*)

    enum Радиус {
        /// --r-xs: метка ТОП.
        static let xs: CGFloat = 8
        /// --r-ms: мелкие кнопки.
        static let ms: CGFloat = 12
        /// --r-md: карточка объявления.
        static let md: CGFloat = 14
        /// --r-lg: плитка раздела и баннер.
        static let lg: CGFloat = 18
        /// --r-xl: полоса ряда.
        static let xl: CGFloat = 20
        /// Низ шапки и верх нижней панели — 22px.
        static let шапка: CGFloat = 22
        /// --r-2xs: пункты «Продавец утверждает».
        static let xxs: CGFloat = 6
        /// --r-sm: кнопки над фото, «Понятно».
        static let sm: CGFloat = 10
    }

    // MARK: - Краски из CSS

    /// Число «0xRRGGBB» → UIColor.
    static func hex(_ v: UInt32, _ альфа: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: альфа)
    }

    /// Строка «#DC2626» из данных сайта → UIColor; не разобралась — бренд.
    static func hex(_ строка: String?) -> UIColor {
        var s = (строка ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return hex(0x0F5132) }
        return hex(v)
    }

    /// Светлое и тёмное значение одним цветом: SwiftUI берёт нужное по теме окна.
    static func цвет(светлый: UIColor, тёмный: UIColor) -> Color {
        Color(uiColor: UIColor { признаки in признаки.userInterfaceStyle == .dark ? тёмный : светлый })
    }

    static func цвет(_ светлый: UInt32, _ тёмный: UInt32) -> Color {
        цвет(светлый: hex(светлый), тёмный: hex(тёмный))
    }

    /// color-mix(in srgb, a доля, b): доля 0…1 — сколько взять от a.
    static func смесь(_ a: UIColor, _ b: UIColor, _ доля: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        _ = a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        _ = b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let p = max(0, min(1, доля))
        return UIColor(red: ar * p + br * (1 - p), green: ag * p + bg * (1 - p),
                       blue: ab * p + bb * (1 - p), alpha: aa * p + ba * (1 - p))
    }
}

extension View {
    /**
     Тень карточки сайта (.mh-c): 0 1px 2px rgba(16,40,28,.06), 0 6px 18px -14px rgba(16,40,28,.28). Отрицательного
     разлёта у SwiftUI нет — вторая тень поуже и послабее, чтобы вышла та же мягкая подложка снизу. В тёмной теме тени
     на сайте нет: там рамка 1px цвета линии (box-shadow: 0 0 0 1px var(--mk-line)).
     */
    func теньКарточкиСайта(радиус: CGFloat = Theme.Радиус.md) -> some View {
        modifier(ТеньКарточкиСайта(радиус: радиус))
    }
}

private struct ТеньКарточкиСайта: ViewModifier {
    let радиус: CGFloat
    @Environment(\.colorScheme) private var схема

    init(радиус: CGFloat) {
        self.радиус = радиус
    }

    func body(content: Content) -> some View {
        if схема == .dark {
            content.overlay {
                RoundedRectangle(cornerRadius: радиус, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        } else {
            content
                .shadow(color: Color(red: 16 / 255, green: 40 / 255, blue: 28 / 255).opacity(0.06), radius: 1, x: 0, y: 1)
                .shadow(color: Color(red: 16 / 255, green: 40 / 255, blue: 28 / 255).opacity(0.16), radius: 4, x: 0, y: 5)
        }
    }
}
