import SwiftUI
import UIKit

/**
 ПОСТЕР УСЛУГИ — «Фото-карточка» и «Для сторис» у услуг и вакансий (владелец 26.09.2026: «QR на постере услуги»).

 Сайт (js/marketplace.min.js): mkShareCard(id) для mkIsService(товар) рисует не зелёную карточку товара, а
 _mkServicePoster: холст 1080 × 1350, тема по названию и разделу (MK_POSTER_THEMES: эвакуатор, грузоперевозки, техника,
 авто, ремонт, красота, клининг, обучение, фото и видео; иначе зелёная MK_POSTER_DEF) — диагональный градиент c1 → c2,
 белые косые полосы с прозрачностью 0,06 и толщиной 40, большой значок темы (прозрачность 0,1, 620 в точке 520, 790),
 «УСЛУГА · KLIKO.KZ» 800 30 слева вверху, круг фото 170 в белом кольце 180 (нет фото — первая буква продавца 900 130),
 кружок значка темы цвета ac, название 900 84 до трёх строк по центру, «от <цена> ₸» 900 76 цветом ac, строка «★ рейтинг ·
 ✓ Проверен · город» 700 38, продавец 800 46, внизу белая кнопка 760 × 96 «Записаться на Kliko.kz  →» 800 40 цветом c2 и
 QR 150 в белой рамке 170 справа. Здесь — тот же холст по тем же числам на Core Graphics; для сторис (1920) середина
 опускается на половину прибавки высоты, кнопка и QR остаются у низа. Всегда одинаков в светлой и тёмной теме: его
 увидят в чужой ленте. Подписи — на языке телефона (SiteShareText).
 */
struct ДанныеУслугиПостера: Hashable {
    var продавец: String = ""
    var рейтинг: Double = 0
    var проверен = false
    var город: String = ""
    /// Раздел объявления — вместе с названием выбирает тему, как _mkPosterTheme сайта.
    var раздел: String = ""
}

/// Тема постера — одна запись MK_POSTER_THEMES сайта.
struct ТемаПостераУслуги {
    let c1: UInt32
    let c2: UInt32
    let ac: UInt32
    let значок: String

    /// MK_POSTER_THEMES сайта по порядку: первое совпадение по «название раздел».
    private static let список: [(шаблон: String, тема: ТемаПостераУслуги)] = [
        ("эвакуатор|букси", ТемаПостераУслуги(c1: 0xB45309, c2: 0x7C2D12, ac: 0xFBBF24, значок: "tow")),
        ("грузоперев|газел|переезд|грузчик|доставк", ТемаПостераУслуги(c1: 0xC2410C, c2: 0x7C2D12, ac: 0xFDBA74, значок: "truck")),
        ("ноутбук|компьютер|смартфон|телефон|электрон|\\bпк\\b|ремонт техник",
         ТемаПостераУслуги(c1: 0x1D4ED8, c2: 0x0B2A63, ac: 0x38BDF8, значок: "laptop")),
        ("шиномонт|автосервис|\\bсто\\b|детейл|развал|автоэлектр|автомойк",
         ТемаПостераУслуги(c1: 0xDC2626, c2: 0x7F1D1D, ac: 0xFCA5A5, значок: "car")),
        ("сантех|электрик|маляр|плитк|отделк|потолк|обои|строит|мастер на час|ремонт кварт",
         ТемаПостераУслуги(c1: 0x475569, c2: 0x1E293B, ac: 0xFBBF24, значок: "wrench")),
        ("маникюр|педикюр|парикмах|космет|красот|макияж|бров|ресниц|визаж|стрижк|массаж",
         ТемаПостераУслуги(c1: 0xDB2777, c2: 0x831843, ac: 0xF9A8D4, значок: "spark")),
        ("уборк|клининг|химчист|мойк|чист", ТемаПостераУслуги(c1: 0x0891B2, c2: 0x083344, ac: 0x67E8F9, значок: "spark")),
        ("репетит|обучен|\\bкурс|урок|препод|няня|логопед", ТемаПостераУслуги(c1: 0x7C3AED, c2: 0x3B0764, ac: 0xC4B5FD, значок: "book")),
        ("фото|видео|съёмк|съемк|оператор|монтаж", ТемаПостераУслуги(c1: 0x0D9488, c2: 0x134E4A, ac: 0x5EEAD4, значок: "cam"))
    ]

    /// MK_POSTER_DEF сайта.
    static let обычная = ТемаПостераУслуги(c1: 0x0E7A44, c2: 0x0A3A22, ac: 0x5CD693, значок: "wrench")

    static func подобрать(_ текст: String) -> ТемаПостераУслуги {
        for запись in список where текст.range(of: запись.шаблон, options: [.regularExpression, .caseInsensitive]) != nil {
            return запись.тема
        }
        return обычная
    }
}

enum ПостерУслугиСайта {
    private static func т(_ ключ: String) -> String { SiteShareText.т(ключ) }

    /// _mkServicePoster сайта шириной 1080: высота 1350 — «Фото-карточка», 1920 — «Для сторис».
    static func нарисовать(_ данные: ДанныеОтправкиСайта, услуга у: ДанныеУслугиПостера, фото: UIImage?, qr: UIImage?,
                           высота: CGFloat) -> UIImage {
        let ш: CGFloat = 1080
        let в = max(1350, высота)
        let сдвиг = ((в - 1350) / 2).rounded()
        let тема = ТемаПостераУслуги.подобрать(данные.название + " " + у.раздел)
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисовальщик = UIGraphicsImageRenderer(size: CGSize(width: ш, height: в), format: формат)
        return рисовальщик.image { холст in
            let c = холст.cgContext
            фон(c, тема: тема, ширина: ш, высота: в)

            c.saveGState()
            c.setAlpha(0.1)
            значок(c, тема.значок, x: 520, y: 790 + сдвиг, размер: 620)
            c.restoreGState()

            текст(т("svc_label"), шрифт(30, .heavy), Theme.hex(0xFFFFFF, 0.9), x: 64, базовая: 90, центр: false)

            лицо(c, фото: фото, продавец: у.продавец, тема: тема, центрY: 360 + сдвиг)

            /* Название, цена, «★ · ✓ · город», продавец — по центру. */
            let шрифтНазвания = шрифт(84, .black)
            let название = данные.название.isEmpty ? т("svc_item") : данные.название
            let строки = строкиПоШирине(название, шрифтНазвания, ширина: 940, максимум: 3)
            var y: CGFloat = 680 + сдвиг
            for (номер, строка) in строки.enumerated() {
                текст(строка, шрифтНазвания, .white, x: 540, базовая: y + 92 * CGFloat(номер), центр: true)
            }
            y += 92 * CGFloat(строки.count) + 6
            let цена = данные.цена > 0
                ? String(format: т("svc_from"), ЦенаКарточкиСайта.полная(данные.цена))
                : ListingPageText.т("negotiable")
            текст(цена, шрифт(76, .black), Theme.hex(тема.ac), x: 540, базовая: y + 60, центр: true)
            y += 140
            let сведения = строкаСведений(у)
            if !сведения.isEmpty {
                текст(сведения, шрифт(38, .bold), .white, x: 540, базовая: y, центр: true)
                y += 70
            }
            if !у.продавец.isEmpty {
                текст(у.продавец, шрифт(46, .heavy), Theme.hex(0xFFFFFF, 0.95), x: 540, базовая: y + 16, центр: true)
            }

            /* Кнопка «Записаться на Kliko.kz  →» и QR справа — у низа холста. */
            let низКнопки = в - 150
            c.setFillColor(UIColor.white.cgColor)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 64, y: низКнопки, width: 760, height: 96), cornerRadius: 48).cgPath)
            c.fillPath()
            текст(т("svc_cta"), шрифт(40, .heavy), Theme.hex(тема.c2), x: 444, базовая: низКнопки + 62, центр: true)
            if let qr {
                c.setFillColor(UIColor.white.cgColor)
                c.addPath(UIBezierPath(roundedRect: CGRect(x: 856, y: в - 187, width: 170, height: 170), cornerRadius: 16).cgPath)
                c.fillPath()
                c.interpolationQuality = .none
                qr.draw(in: CGRect(x: 866, y: в - 177, width: 150, height: 150))
                c.interpolationQuality = .default
            }
        }
    }

    // MARK: Части

    /// Диагональный градиент c1 → c2 и белые косые полосы (прозрачность 0,06, толщина 40, шаг 120).
    private static func фон(_ c: CGContext, тема: ТемаПостераУслуги, ширина: CGFloat, высота: CGFloat) {
        let цвета = [Theme.hex(тема.c1).cgColor, Theme.hex(тема.c2).cgColor] as CFArray
        if let градиент = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: цвета, locations: [0, 1]) {
            c.drawLinearGradient(градиент, start: .zero, end: CGPoint(x: ширина, y: высота),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        c.saveGState()
        c.setAlpha(0.06)
        c.setStrokeColor(UIColor.white.cgColor)
        c.setLineWidth(40)
        for номер in -2..<20 {
            let x = 120 * CGFloat(номер)
            c.move(to: CGPoint(x: x, y: 0))
            c.addLine(to: CGPoint(x: x - 400, y: высота))
            c.strokePath()
        }
        c.restoreGState()
    }

    /// Круг фото 170 в кольце 180 (белый 25 %); нет фото — подложка и первая буква продавца. Справа внизу — кружок темы.
    private static func лицо(_ c: CGContext, фото: UIImage?, продавец: String, тема: ТемаПостераУслуги, центрY: CGFloat) {
        let x: CGFloat = 540
        c.setFillColor(Theme.hex(0xFFFFFF, 0.25).cgColor)
        c.fillEllipse(in: CGRect(x: x - 180, y: центрY - 180, width: 360, height: 360))

        c.saveGState()
        c.addEllipse(in: CGRect(x: x - 170, y: центрY - 170, width: 340, height: 340))
        c.clip()
        if let фото, фото.size.width > 0, фото.size.height > 0 {
            let доля = фото.size.width / фото.size.height
            let w: CGFloat = доля > 1 ? 340 * доля : 340
            let h: CGFloat = доля > 1 ? 340 : 340 / доля
            фото.draw(in: CGRect(x: x - w / 2, y: центрY - h / 2, width: w, height: h))
        } else {
            c.setFillColor(Theme.hex(0xFFFFFF, 0.16).cgColor)
            c.fill(CGRect(x: x - 170, y: центрY - 170, width: 340, height: 340))
            let буква = продавец.first.map { String($0).uppercased() } ?? "K"
            текст(буква, шрифт(130, .black), .white, x: x, базовая: центрY + 48, центр: true)
        }
        c.restoreGState()

        c.setFillColor(Theme.hex(тема.ac).cgColor)
        c.fillEllipse(in: CGRect(x: 690 - 52, y: центрY + 150 - 52, width: 104, height: 104))
        значок(c, тема.значок, x: 656, y: центрY + 116, размер: 68)
    }

    /// «★ 4.8   ·   ✓ Проверен   ·   Алматы» — как у сайта.
    private static func строкаСведений(_ у: ДанныеУслугиПостера) -> String {
        var части: [String] = []
        if у.рейтинг > 0 {
            let число = у.рейтинг == у.рейтинг.rounded() ? String(Int(у.рейтинг)) : String(format: "%g", у.рейтинг)
            части.append("★ \(число)")
        }
        if у.проверен { части.append(т("svc_verified")) }
        if !у.город.isEmpty { части.append(у.город) }
        return части.joined(separator: "   ·   ")
    }

    private static func шрифт(_ размер: CGFloat, _ вес: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: размер, weight: вес)
    }

    private static func ширина(_ строка: String, _ шрифт: UIFont) -> CGFloat {
        (строка as NSString).size(withAttributes: [.font: шрифт]).width
    }

    /// fillText холста: `базовая` — базовая линия, `центр` — textAlign center относительно x.
    private static func текст(_ строка: String, _ шрифт: UIFont, _ цвет: UIColor, x: CGFloat, базовая: CGFloat, центр: Bool) {
        let атрибуты: [NSAttributedString.Key: Any] = [.font: шрифт, .foregroundColor: цвет]
        let надпись = NSAttributedString(string: строка, attributes: атрибуты)
        let левый = центр ? x - надпись.size().width / 2 : x
        надпись.draw(at: CGPoint(x: левый, y: базовая - шрифт.ascender))
    }

    /// _mkWrap сайта: по словам не шире `ширина`, не больше `максимум` строк; не влезло — многоточие.
    private static func строкиПоШирине(_ текст: String, _ шрифт: UIFont, ширина предел: CGFloat, максимум: Int) -> [String] {
        let слова = текст.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var итог: [String] = []
        var строка = ""
        for слово in слова {
            let проба = строка.isEmpty ? слово : строка + " " + слово
            if ширина(проба, шрифт) > предел && !строка.isEmpty {
                итог.append(строка)
                строка = слово
                if итог.count >= максимум { break }
            } else {
                строка = проба
            }
        }
        if !строка.isEmpty && итог.count < максимум { итог.append(строка) }
        if var последняя = итог.last, ширина(последняя, шрифт) > предел {
            while последняя.count > 1 && ширина(последняя + "…", шрифт) > предел { последняя.removeLast() }
            итог[итог.count - 1] = последняя + "…"
        }
        return итог
    }

    /// _mkPosterIcon сайта: белые линии толщиной 0,085 размера в квадрате `размер` с левым верхним углом x, y.
    private static func значок(_ c: CGContext, _ вид: String, x: CGFloat, y: CGFloat, размер r: CGFloat) {
        c.saveGState()
        c.setStrokeColor(UIColor.white.cgColor)
        c.setFillColor(UIColor.white.cgColor)
        c.setLineWidth(0.085 * r)
        c.setLineCap(.round)
        c.setLineJoin(.round)

        func точка(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: x + r * a, y: y + r * b)
        }
        func ломаная(_ точки: [(CGFloat, CGFloat)]) {
            c.beginPath()
            for (номер, п) in точки.enumerated() {
                if номер == 0 { c.move(to: точка(п.0, п.1)) } else { c.addLine(to: точка(п.0, п.1)) }
            }
            c.strokePath()
        }
        func круги(_ центры: [(CGFloat, CGFloat)], радиус: CGFloat) {
            c.beginPath()
            for п in центры {
                let ц = точка(п.0, п.1)
                c.addEllipse(in: CGRect(x: ц.x - радиус * r, y: ц.y - радиус * r, width: 2 * радиус * r, height: 2 * радиус * r))
            }
            c.strokePath()
        }

        switch вид {
        case "tow":
            ломаная([(0.1, 0.62), (0.1, 0.34), (0.5, 0.34), (0.5, 0.62)])
            ломаная([(0.5, 0.44), (0.78, 0.44), (0.9, 0.58), (0.9, 0.62)])
            круги([(0.28, 0.66), (0.78, 0.66)], радиус: 0.07)
            ломаная([(0.1, 0.34), (-0.02, 0.16)])
        case "truck":
            ломаная([(0.06, 0.3), (0.58, 0.3), (0.58, 0.62), (0.06, 0.62), (0.06, 0.3)])
            ломаная([(0.58, 0.4), (0.8, 0.4), (0.92, 0.52), (0.92, 0.62), (0.58, 0.62)])
            круги([(0.24, 0.66), (0.78, 0.66)], радиус: 0.07)
        case "laptop":
            let угол = точка(0.16, 0.24)
            c.addPath(UIBezierPath(roundedRect: CGRect(x: угол.x, y: угол.y, width: 0.68 * r, height: 0.4 * r),
                                   cornerRadius: 0.05 * r).cgPath)
            c.strokePath()
            ломаная([(0.06, 0.72), (0.94, 0.72)])
        case "car":
            ломаная([(0.08, 0.6), (0.16, 0.4), (0.34, 0.34), (0.66, 0.34), (0.84, 0.4), (0.92, 0.6)])
            ломаная([(0.08, 0.6), (0.92, 0.6)])
            круги([(0.28, 0.62), (0.72, 0.62)], радиус: 0.07)
        case "spark":
            let лучи: [(CGFloat, CGFloat)] = [(0.5, 0.14), (0.6, 0.4), (0.86, 0.5), (0.6, 0.6), (0.5, 0.86), (0.4, 0.6),
                                              (0.14, 0.5), (0.4, 0.4)]
            c.beginPath()
            for (номер, п) in лучи.enumerated() {
                if номер == 0 { c.move(to: точка(п.0, п.1)) } else { c.addLine(to: точка(п.0, п.1)) }
            }
            c.closePath()
            c.fillPath()
        case "book":
            ломаная([(0.16, 0.2), (0.5, 0.28), (0.84, 0.2), (0.84, 0.72), (0.5, 0.8), (0.16, 0.72), (0.16, 0.2)])
            ломаная([(0.5, 0.28), (0.5, 0.8)])
        case "cam":
            ломаная([(0.1, 0.34), (0.34, 0.34), (0.42, 0.24), (0.58, 0.24), (0.66, 0.34), (0.9, 0.34), (0.9, 0.68),
                      (0.1, 0.68), (0.1, 0.34)])
            круги([(0.5, 0.5)], радиус: 0.13)
        default:
            ломаная([(0.28, 0.28), (0.2, 0.36), (0.28, 0.44), (0.44, 0.4), (0.72, 0.68), (0.66, 0.74), (0.4, 0.46)])
        }
        c.restoreGState()
    }
}
