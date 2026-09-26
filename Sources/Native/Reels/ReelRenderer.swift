import UIKit

/// Одна строка «чипов» под названием: город с булавкой или пара «подпись — значение» из характеристик (reelSpecPairs).
struct ПараРолика: Equatable {
    var подпись: String
    var значение: String
    var булавка: Bool = false
}

/// Всё, из чего рисуется ролик: стиль, тексты, фото и QR. Снимок настроек студии — рисовальщик его не меняет.
struct СодержимоеРолика {
    var стиль: СтильРолика
    var название: String
    /// Готовая строка цены: «12 000 ₸» или «Договорная».
    var цена: String
    /// Первая строка концовки: «Скачайте приложение Kliko».
    var призыв: String
    var пары: [ПараРолика]
    /// Фото карточки (до 5) и размытые фоны к ним — R сайта.
    var фото: [UIImage]
    var фоны: [UIImage?]
    var qr: UIImage?
    /// Надписи кадра (по языку приложения; русские — слово в слово как у сайта).
    var подзаголовок: String
    var доверие: String
    var магазинМелко: String
    var подсказкаQR: String
    var подсказкаПостера: String
}

/// Разложенный чип: координаты и обрезанные строки (O сайта).
private struct ЧипРолика {
    let x: CGFloat
    let y: CGFloat
    let w: CGFloat
    let подпись: String
    let ширинаПодписи: CGFloat
    let значение: String
    let булавка: Bool
}

/// Холст одного кадра: контекст и масштаб (тени и размытие от CTM не зависят — их множим сами).
private struct ХолстРолика {
    let к: CGContext
    let м: CGFloat
}

/**
 Кадр ролика в момент t — функция K сайта целиком: заставка (градиент стиля, знак Kliko «выпрыгивает», «площадка
 сделок»), фото (размытый фон с медленным приближением — Ken Burns, затемнение, карточка фото со скруглением 34 и
 многослойной тенью, переходы «растворение», «сдвиг», «толчок»), подписи (цена одной из четырёх форм с «пружиной» и
 бликом, название в две строки, чипы города и характеристик, «Безопасная сделка»), полоски хода сверху и концовка
 (кольца, знак, «Скачайте приложение Kliko», плашка App Store, QR объявления).

 Координаты — пиксели холста 1080 × 1920 сверху вниз, как у canvas сайта. Всё неизменяемое после init — один
 рисовальщик рисует превью на главной нити и кадры записи в фоне.
 */
final class РисовальщикРолика: @unchecked Sendable {
    typealias К = КраскиРолика

    static let ширина: CGFloat = 1080
    static let высота: CGFloat = 1920
    /// M сайта: место карточки фото.
    static let рамкаФото = CGRect(x: 60, y: 196, width: 960, height: 1060)

    let содержимое: СодержимоеРолика
    let постер: Bool
    let ход: ТаймлайнРолика

    private let строкиНазвания: [String]
    private let верхЦены: CGFloat
    private let верхНазвания: CGFloat
    private let чипы: [ЧипРолика]
    private let верхДоверия: CGFloat
    private let строкаДоверия: String
    private let шрифтЦены: UIFont
    private let ширинаЦены: CGFloat
    private let центрЦены: CGPoint
    private let надписьKliko: UIImage?
    private let надписьKz: UIImage?

    /// `постер` — «Картинка» сайта (ne): кадр без полосок хода, справа от цены белая карточка с QR.
    init(_ содержимое: СодержимоеРолика, постер: Bool = false) {
        self.содержимое = содержимое
        self.постер = постер
        self.ход = ТаймлайнРолика(фото: содержимое.фото.count)
        надписьKliko = UIImage(named: "WmKliko")?.withTintColor(UIColor.white, renderingMode: .alwaysOriginal)
        надписьKz = UIImage(named: "WmKz")

        let с = содержимое.стиль
        let резерв: CGFloat = (постер && содержимое.qr != nil) ? 250 : 0
        let ширинаНазвания = 972 - резерв
        let низФото = РисовальщикРолика.рамкаФото.maxY
        let вЦены = низФото + 34
        верхЦены = вЦены
        let граница = вЦены + резерв + 12
        func ширинаНа(_ y: CGFloat) -> CGFloat { резерв > 0 && y < граница ? ширинаНазвания : 972 }

        let шНазвания = К.шрифт(с.текст, "800", 56)
        let название = содержимое.название.trimmingCharacters(in: .whitespacesAndNewlines)
        let строки = РисовальщикРолика.разбить(название, шНазвания, ширинаНазвания, 2)
        строкиНазвания = строки
        let вНазвания = вЦены + 134
        верхНазвания = вНазвания

        var разложено: [ЧипРолика] = []
        var y = вНазвания + CGFloat(строки.count) * 66 + 22
        var x: CGFloat = 54
        var ряд = 0
        let шПодписи = К.шрифт(с.текст, "600", 27)
        let шЗначения = К.шрифт(с.текст, "800", 30)
        for пара in содержимое.пары where разложено.count < 6 {
            guard !пара.значение.isEmpty else { continue }
            let подпись = пара.подпись.isEmpty ? "" : РисовальщикРолика.обрезать(пара.подпись, шПодписи, 300)
            let шП: CGFloat = подпись.isEmpty ? 0 : РисовальщикРолика.ширинаТекста(подпись, шПодписи) + 12
            let шБ: CGFloat = пара.булавка ? 30 : 0
            var значение = РисовальщикРолика.обрезать(пара.значение, шЗначения, ширинаНа(y) - 44 - шП - шБ)
            var w = 44 + шБ + шП + РисовальщикРолика.ширинаТекста(значение, шЗначения)
            if x > 54 && x + w > 54 + ширинаНа(y) {
                ряд += 1
                x = 54
                y += 72
                значение = РисовальщикРолика.обрезать(пара.значение, шЗначения, ширинаНа(y) - 44 - шП - шБ)
                w = 44 + шБ + шП + РисовальщикРолика.ширинаТекста(значение, шЗначения)
            }
            if ряд > 1 { break }
            разложено.append(ЧипРолика(x: x, y: y, w: w, подпись: подпись, ширинаПодписи: шП, значение: значение,
                                       булавка: пара.булавка))
            x += w + 12
        }
        чипы = разложено
        let низ = разложено.last.map { $0.y + 60 } ?? (вНазвания + CGFloat(строки.count) * 66)
        верхДоверия = низ + 28
        строкаДоверия = РисовальщикРолика.обрезать(содержимое.доверие, К.шрифт(с.текст, "700", 31), ширинаНа(низ + 28) - 60)

        /* q сайта: шрифт и центр цены (вокруг него «пружинит» появление). */
        let шЦены: UIFont
        switch с.цена {
        case .крупно: шЦены = К.шрифт(с.заголовки, с.весЗаголовков, 100)
        case .ярлык: шЦены = К.шрифт(с.заголовки, с.весЗаголовков, 68)
        case .значок: шЦены = К.шрифт(с.заголовки, с.весЗаголовков, 62)
        case .пилюля: шЦены = К.шрифт(с.заголовки, с.весЗаголовков, 74)
        }
        let pw = min(900, РисовальщикРолика.ширинаТекста(содержимое.цена, шЦены))
        шрифтЦены = шЦены
        ширинаЦены = pw
        switch с.цена {
        case .крупно: центрЦены = CGPoint(x: 54 + pw / 2, y: вЦены + 48)
        case .ярлык: центрЦены = CGPoint(x: 54 + (pw + 96) / 2, y: вЦены + 52)
        case .значок: центрЦены = CGPoint(x: 54 + (pw + 56) / 2, y: вЦены + 41)
        case .пилюля: центрЦены = CGPoint(x: 54 + (pw + 64) / 2, y: вЦены + 54)
        }
    }

    // MARK: Кадр целиком

    /// Кадр картинкой (превью и «Картинка»): `масштаб` 0,5 — 540 × 960, как холст превью сайта.
    func кадр(_ время: Double, масштаб: CGFloat) -> UIImage? {
        let w = Int((РисовальщикРолика.ширина * масштаб).rounded())
        let h = Int((РисовальщикРолика.высота * масштаб).rounded())
        let пространство = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let раскладка = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let к = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: пространство, bitmapInfo: раскладка) else { return nil }
        нарисовать(в: к, время: время, масштаб: масштаб)
        guard let готово = к.makeImage() else { return nil }
        return UIImage(cgImage: готово)
    }

    /// Кадр «Картинки»: момент заставка + 0,98 шага (ne сайта).
    var времяПостера: Double { ход.заставка + 0.98 * ход.наФото }

    /// Рисует кадр в контекст растра (начало координат внизу слева, как у CGBitmapContext и CVPixelBuffer).
    func нарисовать(в к: CGContext, время t: Double, масштаб: CGFloat) {
        к.saveGState()
        к.translateBy(x: 0, y: РисовальщикРолика.высота * масштаб)
        к.scaleBy(x: масштаб, y: -масштаб)
        к.interpolationQuality = .high
        к.setShouldAntialias(true)
        UIGraphicsPushContext(к)
        let х = ХолстРолика(к: к, м: масштаб)
        к.setFillColor(UIColor.black.cgColor)
        к.fill(CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина, height: РисовальщикРолика.высота))
        if t < ход.заставка {
            заставка(х, t / ход.заставка)
        } else {
            let a = t - ход.заставка
            let фотоВсего = Double(ход.фото) * ход.наФото
            if a >= фотоВсего {
                концовка(х, К.предел((a - фотоВсего) / ход.концовка))
            } else {
                кадрФото(х, a)
            }
        }
        if постер { карточкаQR(х) }
        UIGraphicsPopContext()
        к.restoreGState()
    }

    // MARK: Заставка и концовка

    private func заставка(_ х: ХолстРолика, _ u: Double) {
        let с = содержимое.стиль
        градиент(х, [К.цвет(с.фон.0), К.цвет(с.фон.1)], от: .zero, до: CGPoint(x: РисовальщикРолика.ширина, y: РисовальщикРолика.высота),
                 в: CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина, height: РисовальщикРолика.высота))
        let i = CGFloat(0.82 + 0.18 * К.перелёт(К.предел(u / 0.7)))
        х.к.saveGState()
        х.к.setAlpha(CGFloat(К.выход(К.предел(u / 0.45))))
        х.к.translateBy(x: 540, y: 960)
        х.к.scaleBy(x: i, y: i)
        _ = знакKliko(х, x: 0, y: -16, размер: 150, поЦентру: true, тень: false)
        х.к.setFillColor(К.цвет(с.акцент).cgColor)
        х.к.fill(CGRect(x: -130, y: 66, width: 260, height: 9))
        надпись(содержимое.подзаголовок, К.шрифт(с.текст, "700", 44), К.белый(0.85), 0, 120, поЦентру: true,
                база: .середина)
        х.к.restoreGState()
        водянойЗнак(х)
    }

    private func концовка(_ х: ХолстРолика, _ u: Double) {
        let с = содержимое.стиль
        градиент(х, [К.цвет(с.фон.0), К.цвет(с.фон.1)], от: .zero, до: CGPoint(x: 0, y: РисовальщикРолика.высота),
                 в: CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина, height: РисовальщикРолика.высота))
        х.к.setStrokeColor(К.белый(0.10).cgColor)
        х.к.setLineWidth(3)
        for n in 0..<3 {
            let r = CGFloat(150 + 170 * Double(n) + 150 * u)
            х.к.strokeEllipse(in: CGRect(x: 540 - r, y: 870 - r, width: 2 * r, height: 2 * r))
        }
        let c = CGFloat(0.72 + 0.28 * К.перелёт(К.предел(u / 0.5)))
        х.к.saveGState()
        х.к.setAlpha(CGFloat(К.выход(К.предел(u / 0.4))))
        х.к.translateBy(x: 540, y: 630)
        х.к.scaleBy(x: c, y: c)
        _ = знакKliko(х, x: 0, y: 0, размер: 130, поЦентру: true, тень: false)
        х.к.restoreGState()
        залить(х, скруглённый(CGRect(x: 450, y: 720, width: 180, height: 8), 4), К.цвет(с.акцент))

        let k = CGFloat(К.выход(К.предел((u - 0.22) / 0.5)))
        х.к.saveGState()
        х.к.setAlpha(k)
        х.к.translateBy(x: 0, y: 46 * (1 - k))
        текстыКонцовки(х)
        х.к.restoreGState()

        if let qr = содержимое.qr {
            х.к.saveGState()
            х.к.setAlpha(CGFloat(К.выход(К.предел((u - 0.35) / 0.5))))
            залить(х, скруглённый(CGRect(x: 364, y: 1104, width: 352, height: 352), 30), UIColor.white)
            х.к.interpolationQuality = .none
            qr.draw(in: CGRect(x: 390, y: 1130, width: 300, height: 300))
            х.к.restoreGState()
        }
        водянойЗнак(х)
    }

    /// p сайта (с REEL_CFG.ios): призыв, плашка App Store, подсказка про QR.
    private func текстыКонцовки(_ х: ХолстРолика) {
        let с = содержимое.стиль
        let шПризыва = подогнать(содержимое.призыв, К.шрифт(с.текст, "800", 52), 1000)
        надпись(содержимое.призыв, шПризыва, UIColor.white, 540, 810, поЦентру: true, база: .середина)
        залить(х, скруглённый(CGRect(x: 260, y: 880, width: 560, height: 132), 30), UIColor.black)
        обвести(х, скруглённый(CGRect(x: 261.5, y: 881.5, width: 557, height: 129), 29), К.белый(0.75), 3)
        значокKliko(х, CGRect(x: 290, y: 904, width: 84, height: 84))
        надпись(содержимое.магазинМелко, К.шрифт("Manrope", "700", 30), К.белый(0.85), 398, 922, база: .середина)
        надпись("App Store", К.шрифт("Manrope", "800", 56), UIColor.white, 398, 968, база: .середина)
        let шПодсказки = подогнать(содержимое.подсказкаQR, К.шрифт(с.текст, "600", 34), 1000)
        надпись(содержимое.подсказкаQR, шПодсказки, К.белый(0.85), 540, 1070, поЦентру: true, база: .середина)
    }

    // MARK: Фото

    private func кадрФото(_ х: ХолстРолика, _ a: Double) {
        let с = содержимое.стиль
        let шаг = ход.наФото
        let idx = min(ход.фото - 1, Int(floor(a / шаг)))
        let u = (a - Double(idx) * шаг) / шаг
        let ua = a / шаг
        let фото = содержимое.фото
        let фоны = содержимое.фоны
        let прежнее: UIImage? = idx > 0 && фото.indices.contains(idx - 1) ? фото[idx - 1] : nil
        let текущее: UIImage? = фото.indices.contains(idx) ? фото[idx] : фото.first
        let фонПрежний: UIImage? = idx > 0 && фоны.indices.contains(idx - 1) ? фоны[idx - 1] : nil
        let фонТекущий: UIImage? = фоны.indices.contains(idx) ? фоны[idx] : (фоны.first ?? nil)
        let смена = прежнее != nil && u < 0.2
        let k = u / 0.2
        if смена {
            фон(х, фонПрежний, 1, 1)
            фон(х, фонТекущий, u, К.выход(k))
        } else {
            фон(х, фонТекущий, u, 1)
        }
        затемнение(х)
        if смена {
            let ek = К.выход(k)
            switch с.переход {
            case .сдвиг:
                карточка(х, прежнее, 1 - ek, CGFloat(-756 * К.входВыход(k)), 1.012)
                карточка(х, текущее, 1, CGFloat(756 * (1 - ek)), 1)
            case .толчок:
                карточка(х, прежнее, 1 - k, 0, CGFloat(1.012 + 0.05 * k))
                карточка(х, текущее, ek, 0, CGFloat(1.12 - 0.12 * ek))
            case .растворение:
                карточка(х, прежнее, 1 - k, 0, 1.012)
                карточка(х, текущее, ek, 0, CGFloat(0.97 + 0.03 * ek))
            }
        } else {
            let мас = idx == 0 ? 0.93 + 0.07 * К.перелёт(К.предел(u / 0.3)) : 1
            let альфа = idx == 0 ? К.выход(К.предел(u / 0.16)) : 1
            карточка(х, текущее, альфа, 0, CGFloat(мас * (1 + 0.012 * u)))
        }
        подписи(х, ua, idx, u)
        if !постер { полоски(х, idx, u) }
    }

    /// bgd сайта: размытый фон на весь кадр, приближается 1,08 → 1,16.
    private func фон(_ х: ХолстРолика, _ картинка: UIImage?, _ u: Double, _ альфа: Double) {
        guard let картинка, альфа > 0 else { return }
        let z = CGFloat(1.08 + 0.08 * u)
        let w = РисовальщикРолика.ширина * z
        let h = РисовальщикРолика.высота * z
        х.к.saveGState()
        х.к.setAlpha(CGFloat(альфа))
        картинка.draw(in: CGRect(x: (РисовальщикРолика.ширина - w) / 2, y: (РисовальщикРолика.высота - h) / 2, width: w, height: h))
        х.к.restoreGState()
    }

    /// Слой поверх фона: затемнение 30 %, градиент низа под подписи, градиент верха и водяной знак.
    private func затемнение(_ х: ХолстРолика) {
        let с = содержимое.стиль
        х.к.setFillColor(UIColor(white: 0, alpha: 0.30).cgColor)
        х.к.fill(CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина, height: РисовальщикРолика.высота))
        let t0 = РисовальщикРолика.рамкаФото.maxY - 260
        градиент(х, [UIColor(white: 0, alpha: 0), К.цвет(с.фон.1, 0.78), К.цвет(с.фон.1, 0.96)], места: [0, 0.35, 1],
                 от: CGPoint(x: 0, y: t0), до: CGPoint(x: 0, y: РисовальщикРолика.высота),
                 в: CGRect(x: 0, y: t0, width: РисовальщикРолика.ширина, height: РисовальщикРолика.высота - t0))
        градиент(х, [UIColor(white: 0, alpha: 0.55), UIColor(white: 0, alpha: 0)], от: .zero, до: CGPoint(x: 0, y: 300),
                 в: CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина, height: 300))
        водянойЗнак(х)
    }

    /// card сайта: фото целиком в рамке M, скругление 34, шесть слоёв тени и светлый кант.
    private func карточка(_ х: ХолстРолика, _ картинка: UIImage?, _ альфа: Double, _ сдвиг: CGFloat, _ мас: CGFloat) {
        guard let картинка, альфа > 0, картинка.size.width > 0, картинка.size.height > 0 else { return }
        let М = РисовальщикРолика.рамкаФото
        let kf = min(М.width / картинка.size.width, М.height / картинка.size.height)
        let w = картинка.size.width * kf
        let h = картинка.size.height * kf
        let r = CGRect(x: М.minX + (М.width - w) / 2, y: М.minY + (М.height - h) / 2, width: w, height: h)
        х.к.saveGState()
        х.к.setAlpha(CGFloat(альфа))
        х.к.translateBy(x: r.midX + сдвиг, y: r.midY)
        х.к.scaleBy(x: мас, y: мас)
        х.к.translateBy(x: -r.midX, y: -r.midY)
        for n in stride(from: 6, through: 1, by: -1) {
            let e = CGFloat(n * 8)
            let тень = CGRect(x: r.minX - e, y: r.minY - e + 18, width: r.width + 2 * e, height: r.height + 2 * e)
            залить(х, скруглённый(тень, 34 + e), UIColor(white: 0, alpha: 0.07))
        }
        х.к.saveGState()
        х.к.addPath(скруглённый(r, 34))
        х.к.clip()
        картинка.draw(in: r)
        х.к.restoreGState()
        обвести(х, скруглённый(r.insetBy(dx: 1.5, dy: 1.5), 32.5), К.белый(0.22), 3)
        х.к.restoreGState()
    }

    /// bars сайта: полоски хода по числу фото.
    private func полоски(_ х: ХолстРолика, _ idx: Int, _ u: Double) {
        let n = ход.фото
        let tw = (972 - 10 * CGFloat(n - 1)) / CGFloat(n)
        for i in 0..<n {
            let a = 54 + CGFloat(i) * (tw + 10)
            let f: CGFloat = i < idx ? 1 : (i == idx ? CGFloat(u) : 0)
            залить(х, скруглённый(CGRect(x: a, y: 48, width: tw, height: 7), 4), К.белый(0.32))
            if f > 0 {
                залить(х, скруглённый(CGRect(x: a, y: 48, width: tw * f, height: 7), 4), К.цвет(содержимое.стиль.акцент))
            }
        }
    }

    // MARK: Подписи под фото

    /// j сайта: цена «пружинит», блик, название выезжает, чипы открываются шторкой, «Безопасная сделка» поднимается.
    private func подписи(_ х: ХолстРолика, _ ua: Double, _ idx: Int, _ u: Double) {
        let pu = К.предел((ua - 0.10) / 0.34)
        var ps = 0.45 + 0.55 * К.перелёт(pu)
        if pu >= 1 && idx > 0 && u < 0.25 { ps = 1 + 0.07 * sin(Double.pi * u / 0.25) }
        х.к.saveGState()
        х.к.setAlpha(CGFloat(К.выход(pu)))
        х.к.translateBy(x: центрЦены.x, y: центрЦены.y)
        х.к.scaleBy(x: CGFloat(ps), y: CGFloat(ps))
        х.к.translateBy(x: -центрЦены.x, y: -центрЦены.y)
        цена(х)
        х.к.restoreGState()
        блик(х, u, верхЦены - 12)

        let tu = К.выход(К.предел((ua - 0.04) / 0.34))
        х.к.saveGState()
        х.к.setAlpha(CGFloat(tu))
        х.к.translateBy(x: 0, y: CGFloat(46 * (1 - tu)))
        название(х)
        х.к.restoreGState()

        let su = К.предел((ua - 0.18) / 0.42)
        if su > 0 && !чипы.isEmpty {
            х.к.saveGState()
            х.к.clip(to: CGRect(x: 0, y: 0, width: РисовальщикРолика.ширина * CGFloat(К.выход(su)) + 2, height: РисовальщикРолика.высота))
            х.к.setAlpha(CGFloat(К.выход(К.предел(su * 1.6))))
            нарисоватьЧипы(х)
            х.к.restoreGState()
        }

        let ru = К.выход(К.предел((ua - 0.34) / 0.3))
        х.к.saveGState()
        х.к.setAlpha(CGFloat(ru))
        х.к.translateBy(x: 0, y: CGFloat(24 * (1 - ru)))
        доверие(х)
        х.к.restoreGState()
    }

    /// G сайта: четыре формы цены.
    private func цена(_ х: ХолстРолика) {
        let с = содержимое.стиль
        let n = верхЦены
        let акцент = К.цвет(с.акцент)
        let наАкценте = с.светлыйАкцент ? К.цвет(0x141414) : UIColor.white
        let текст = содержимое.цена
        switch с.цена {
        case .крупно:
            надпись(текст, шрифтЦены, акцент, 54, n + 82, база: .линия)
            залить(х, скруглённый(CGRect(x: 54, y: n + 98, width: min(ширинаЦены, 340), height: 9), 4), акцент)
        case .ярлык:
            let w = ширинаЦены + 96
            let h: CGFloat = 104
            let x: CGFloat = 54
            let s = n
            let путь = CGMutablePath()
            путь.move(to: CGPoint(x: 92, y: s))
            путь.addLine(to: CGPoint(x: x + w - 18, y: s))
            путь.addArc(tangent1End: CGPoint(x: x + w, y: s), tangent2End: CGPoint(x: x + w, y: s + 18), radius: 18)
            путь.addLine(to: CGPoint(x: x + w, y: s + h - 18))
            путь.addArc(tangent1End: CGPoint(x: x + w, y: s + h), tangent2End: CGPoint(x: x + w - 18, y: s + h), radius: 18)
            путь.addLine(to: CGPoint(x: 92, y: s + h))
            путь.addLine(to: CGPoint(x: x, y: s + 52))
            путь.closeSubpath()
            залить(х, путь, акцент)
            х.к.setFillColor(UIColor(white: 0, alpha: 0.4).cgColor)
            х.к.fillEllipse(in: CGRect(x: 76, y: s + 42, width: 20, height: 20))
            надпись(текст, шрифтЦены, наАкценте, 114, s + 54, база: .середина)
        case .значок:
            let d = ширинаЦены + 56
            let u = n - 6
            залить(х, скруглённый(CGRect(x: 54, y: u, width: d, height: 94), 18), акцент)
            обвести(х, скруглённый(CGRect(x: 61, y: u + 7, width: d - 14, height: 80), 12), К.белый(0.55), 4)
            надпись(текст, шрифтЦены, наАкценте, 82, u + 49, база: .середина)
        case .пилюля:
            залить(х, скруглённый(CGRect(x: 54, y: n, width: ширинаЦены + 64, height: 108), 26), акцент)
            надпись(текст, шрифтЦены, наАкценте, 86, n + 56, база: .середина)
        }
    }

    /// shine сайта: светлая полоса проходит по цене (наложение «overlay»).
    private func блик(_ х: ХолстРолика, _ u: Double, _ y: CGFloat) {
        let su = (u - 0.45) / 0.32
        guard su >= 0 && su <= 1 else { return }
        х.к.saveGState()
        х.к.setBlendMode(.overlay)
        х.к.setAlpha(CGFloat(0.55 * (1 - abs(su - 0.5) * 2)))
        let a = CGFloat(-260 + 1600 * su)
        градиент(х, [К.белый(0), К.белый(0.75), К.белый(0)], места: [0, 0.5, 1],
                 от: CGPoint(x: a - 150, y: 0), до: CGPoint(x: a + 150, y: 0),
                 в: CGRect(x: 0, y: y, width: РисовальщикРолика.ширина, height: 132))
        х.к.restoreGState()
    }

    private func название(_ х: ХолстРолика) {
        let шрифт = К.шрифт(содержимое.стиль.текст, "800", 56)
        х.к.saveGState()
        х.к.setShadow(offset: .zero, blur: 12 * х.м, color: UIColor(white: 0, alpha: 0.35).cgColor)
        for (n, строка) in строкиНазвания.enumerated() {
            надпись(строка, шрифт, UIColor.white, 54, верхНазвания + CGFloat(n) * 66, база: .верх)
        }
        х.к.restoreGState()
    }

    private func нарисоватьЧипы(_ х: ХолстРолика) {
        let с = содержимое.стиль
        let наАкценте = с.светлыйАкцент ? К.цвет(0x141414) : UIColor.white
        let шПодписи = К.шрифт(с.текст, "600", 27)
        let шЗначения = К.шрифт(с.текст, "800", 30)
        for ч in чипы {
            let oy = ч.y + 30
            var ix = ч.x + 22
            залить(х, скруглённый(CGRect(x: ч.x, y: ч.y, width: ч.w, height: 60), 30), К.белый(0.13))
            обвести(х, скруглённый(CGRect(x: ч.x + 1, y: ч.y + 1, width: ч.w - 2, height: 58), 29), К.белый(0.24), 2)
            if ч.булавка {
                булавка(х, ix + 8, oy - 6, 9, К.цвет(с.акцент), наАкценте)
                ix += 30
            }
            if !ч.подпись.isEmpty {
                надпись(ч.подпись, шПодписи, К.белый(0.66), ix, oy + 1, база: .середина)
                ix += ч.ширинаПодписи
            }
            надпись(ч.значение, шЗначения, UIColor.white, ix, oy + 1, база: .середина)
        }
    }

    /// W сайта: булавка города.
    private func булавка(_ х: ХолстРолика, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ цвет: UIColor, _ середина: UIColor) {
        let путь = CGMutablePath()
        путь.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        путь.move(to: CGPoint(x: x - 0.72 * r, y: y + 0.55 * r))
        путь.addLine(to: CGPoint(x: x, y: y + 2.35 * r))
        путь.addLine(to: CGPoint(x: x + 0.72 * r, y: y + 0.55 * r))
        путь.closeSubpath()
        х.к.addPath(путь)
        х.к.setFillColor(цвет.cgColor)
        х.к.fillPath()
        х.к.setFillColor(середина.cgColor)
        х.к.fillEllipse(in: CGRect(x: x - 0.42 * r, y: y - 0.42 * r, width: 0.84 * r, height: 0.84 * r))
    }

    /// V сайта: щит с галочкой и «Безопасная сделка: оплата через гарант Kliko».
    private func доверие(_ х: ХолстРолика) {
        let с = содержимое.стиль
        let a = верхДоверия
        х.к.saveGState()
        х.к.translateBy(x: 54, y: a)
        х.к.scaleBy(x: 42.0 / 24.0, y: 42.0 / 24.0)
        let щит = CGMutablePath()
        щит.move(to: CGPoint(x: 12, y: 1.5))
        щит.addLine(to: CGPoint(x: 21, y: 5.2))
        щит.addLine(to: CGPoint(x: 21, y: 11.6))
        щит.addCurve(to: CGPoint(x: 12, y: 22.8), control1: CGPoint(x: 21, y: 17), control2: CGPoint(x: 17.2, y: 21.3))
        щит.addCurve(to: CGPoint(x: 3, y: 11.6), control1: CGPoint(x: 6.8, y: 21.3), control2: CGPoint(x: 3, y: 17))
        щит.addLine(to: CGPoint(x: 3, y: 5.2))
        щит.closeSubpath()
        х.к.addPath(щит)
        х.к.setFillColor(К.цвет(с.акцент).cgColor)
        х.к.fillPath()
        х.к.move(to: CGPoint(x: 8, y: 12.2))
        х.к.addLine(to: CGPoint(x: 10.9, y: 15))
        х.к.addLine(to: CGPoint(x: 16.2, y: 9.4))
        х.к.setLineWidth(2.6)
        х.к.setLineCap(.round)
        х.к.setLineJoin(.round)
        х.к.setStrokeColor((с.светлыйАкцент ? К.цвет(0x141414) : UIColor.white).cgColor)
        х.к.strokePath()
        х.к.restoreGState()
        надпись(строкаДоверия, К.шрифт(с.текст, "700", 31), К.белый(0.9), 112, a + 22, база: .середина)
    }

    /// «Картинка» (ne сайта): белая карточка с QR справа от цены и «наведи камеру».
    private func карточкаQR(_ х: ХолстРолика) {
        guard let qr = содержимое.qr else { return }
        let f = верхЦены + 4
        залить(х, скруглённый(CGRect(x: 808, y: f - 18, width: 236, height: 266), 22), UIColor.white)
        х.к.saveGState()
        х.к.interpolationQuality = .none
        qr.draw(in: CGRect(x: 826, y: f, width: 200, height: 200))
        х.к.restoreGState()
        надпись(содержимое.подсказкаПостера, К.шрифт(содержимое.стиль.текст, "700", 22), К.цвет(0x0E1411), 926,
                f + 208, поЦентру: true, база: .верх)
    }

    // MARK: Знак Kliko

    /// f сайта: знак в левом верхнем углу кадра с тенью.
    private func водянойЗнак(_ х: ХолстРолика) {
        _ = знакKliko(х, x: 54, y: 106, размер: 60, поЦентру: false, тень: true)
    }

    /**
     u сайта: значок `размер` × `размер`, отступ 0,3 размера и надпись «Klıko.kz» (векторные WmKliko и WmKz — тот же
     Unbounded 800, что у сайта), маяк над «ı». Возвращает ширину.
     */
    @discardableResult
    private func знакKliko(_ х: ХолстРолика, x: CGFloat, y: CGFloat, размер a: CGFloat, поЦентру: Bool,
                           тень: Bool) -> CGFloat {
        let шНадписи = 2.5 * a
        let вНадписи = 0.625 * a
        let зазор = 0.3 * a
        let всего = a + зазор + шНадписи
        let m = поЦентру ? x - всего / 2 : x
        х.к.saveGState()
        if тень {
            х.к.setShadow(offset: .zero, blur: max(6, 0.15 * a) * х.м, color: UIColor(white: 0, alpha: 0.5).cgColor)
        }
        х.к.beginTransparencyLayer(auxiliaryInfo: nil)
        значокKliko(х, CGRect(x: m, y: y - a / 2, width: a, height: a))
        let рамка = CGRect(x: m + a + зазор, y: y - вНадписи / 2, width: шНадписи, height: вНадписи)
        if let надписьKliko { надписьKliko.draw(in: рамка) }
        if let надписьKz { надписьKz.draw(in: рамка) }
        х.к.endTransparencyLayer()
        х.к.restoreGState()

        let s = шНадписи / 296
        let центр = CGPoint(x: рамка.minX + 79 * s, y: рамка.minY + 15 * s)
        let маяк = К.цвет(0x25D366)
        х.к.saveGState()
        х.к.setAlpha(0.55)
        х.к.setStrokeColor(маяк.cgColor)
        х.к.setLineWidth(2.4 * s)
        х.к.strokeEllipse(in: CGRect(x: центр.x - 10 * s, y: центр.y - 10 * s, width: 20 * s, height: 20 * s))
        х.к.restoreGState()
        х.к.setFillColor(маяк.cgColor)
        х.к.fillEllipse(in: CGRect(x: центр.x - 6.2 * s, y: центр.y - 6.2 * s, width: 12.4 * s, height: 12.4 * s))
        return всего
    }

    /// REEL_CFG.logo сайта (viewBox 48): зелёный квадрат 13, кольцо, белая булавка с циферблатом.
    private func значокKliko(_ х: ХолстРолика, _ рамка: CGRect) {
        let к = х.к
        let k = рамка.width / 48
        к.saveGState()
        к.translateBy(x: рамка.minX, y: рамка.minY)
        к.scaleBy(x: k, y: k)
        к.saveGState()
        к.addPath(скруглённый(CGRect(x: 0, y: 0, width: 48, height: 48), 13))
        к.clip()
        let цвета: [CGColor] = [К.цвет(0x16A34A).cgColor, К.цвет(0x0F7A44).cgColor]
        if let г = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: цвета as CFArray, locations: [0, 1]) {
            к.drawLinearGradient(г, start: .zero, end: CGPoint(x: 48, y: 48), options: [])
        }
        к.restoreGState()
        к.setStrokeColor(К.белый(0.5).cgColor)
        к.setLineWidth(2)
        к.strokeEllipse(in: CGRect(x: 16, y: 11.5, width: 16, height: 16))
        let пин = CGMutablePath()
        пин.move(to: CGPoint(x: 24, y: 9.8))
        пин.addCurve(to: CGPoint(x: 34.2, y: 19.9), control1: CGPoint(x: 29.9, y: 9.8), control2: CGPoint(x: 34.2, y: 14.3))
        пин.addCurve(to: CGPoint(x: 24, y: 38), control1: CGPoint(x: 34.2, y: 27), control2: CGPoint(x: 24, y: 38))
        пин.addCurve(to: CGPoint(x: 13.8, y: 19.9), control1: CGPoint(x: 24, y: 38), control2: CGPoint(x: 13.8, y: 27))
        пин.addCurve(to: CGPoint(x: 24, y: 9.8), control1: CGPoint(x: 13.8, y: 14.3), control2: CGPoint(x: 18.1, y: 9.8))
        пин.closeSubpath()
        к.addPath(пин)
        к.setFillColor(UIColor.white.cgColor)
        к.fillPath()
        к.setFillColor(К.цвет(0x0F7A44).cgColor)
        к.fillEllipse(in: CGRect(x: 24 - 6.2, y: 19.5 - 6.2, width: 12.4, height: 12.4))
        к.setStrokeColor(UIColor.white.cgColor)
        к.setLineWidth(1.5)
        к.setLineCap(.round)
        к.move(to: CGPoint(x: 24, y: 19.5))
        к.addLine(to: CGPoint(x: 21.4, y: 17.2))
        к.move(to: CGPoint(x: 24, y: 19.5))
        к.addLine(to: CGPoint(x: 27, y: 16.9))
        к.strokePath()
        к.setFillColor(UIColor.white.cgColor)
        к.fillEllipse(in: CGRect(x: 24 - 1.05, y: 19.5 - 1.05, width: 2.1, height: 2.1))
        к.restoreGState()
    }

    // MARK: Примитивы холста

    private enum БазаТекста { case верх, середина, линия }

    /// fillText сайта: textBaseline top, middle или alphabetic; textAlign left или center.
    private func надпись(_ текст: String, _ шрифт: UIFont, _ цвет: UIColor, _ x: CGFloat, _ y: CGFloat,
                         поЦентру: Bool = false, база: БазаТекста) {
        guard !текст.isEmpty else { return }
        let атрибуты: [NSAttributedString.Key: Any] = [.font: шрифт, .foregroundColor: цвет]
        let строка = текст as NSString
        let w = строка.size(withAttributes: атрибуты).width
        let левый = поЦентру ? x - w / 2 : x
        let линия: CGFloat
        switch база {
        case .верх: линия = y + шрифт.ascender
        case .середина: линия = y + (шрифт.ascender + шрифт.descender) / 2
        case .линия: линия = y
        }
        строка.draw(at: CGPoint(x: левый, y: линия - шрифт.ascender), withAttributes: атрибуты)
    }

    /// Уменьшает шрифт, пока строка не влезет в `ширина` (длинный свой призыв).
    private func подогнать(_ текст: String, _ шрифт: UIFont, _ ширина: CGFloat) -> UIFont {
        let w = РисовальщикРолика.ширинаТекста(текст, шрифт)
        guard w > ширина, w > 0 else { return шрифт }
        return шрифт.withSize(max(18, шрифт.pointSize * ширина / w))
    }

    private func залить(_ х: ХолстРолика, _ путь: CGPath, _ цвет: UIColor) {
        х.к.addPath(путь)
        х.к.setFillColor(цвет.cgColor)
        х.к.fillPath()
    }

    private func обвести(_ х: ХолстРолика, _ путь: CGPath, _ цвет: UIColor, _ толщина: CGFloat) {
        х.к.addPath(путь)
        х.к.setStrokeColor(цвет.cgColor)
        х.к.setLineWidth(толщина)
        х.к.strokePath()
    }

    /// Линейный градиент в прямоугольнике; за краями — крайние цвета, как у canvas.
    private func градиент(_ х: ХолстРолика, _ цвета: [UIColor], места: [CGFloat]? = nil, от: CGPoint, до: CGPoint,
                          в прямоугольник: CGRect) {
        let точки: [CGFloat] = места ?? цвета.indices.map { CGFloat($0) / CGFloat(max(1, цвета.count - 1)) }
        let краски: [CGColor] = цвета.map { $0.cgColor }
        guard let г = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: краски as CFArray,
                                 locations: точки) else { return }
        х.к.saveGState()
        х.к.clip(to: прямоугольник)
        х.к.drawLinearGradient(г, start: от, end: до, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        х.к.restoreGState()
    }

    /// rr сайта (arcTo): скругление не больше половины стороны — CGPath(roundedRect:) на таком падает.
    private func скруглённый(_ r: CGRect, _ радиус: CGFloat) -> CGPath {
        let rad = max(0, min(радиус, r.width / 2, r.height / 2))
        let путь = CGMutablePath()
        путь.move(to: CGPoint(x: r.minX + rad, y: r.minY))
        путь.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        путь.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        путь.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rad)
        путь.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: rad)
        путь.closeSubpath()
        return путь
    }

    // MARK: Текст: ширина, обрезка, строки

    static func ширинаТекста(_ текст: String, _ шрифт: UIFont) -> CGFloat {
        (текст as NSString).size(withAttributes: [.font: шрифт]).width
    }

    /// I сайта: обрезать с «…» до ширины.
    static func обрезать(_ текст: String, _ шрифт: UIFont, _ ширина: CGFloat) -> String {
        if ширинаТекста(текст, шрифт) <= ширина { return текст }
        var t = текст
        while t.count > 1 && ширинаТекста("\(t)…", шрифт) > ширина { t.removeLast() }
        return "\(t)…"
    }

    /// Разбивка названия сайта: до `строк` строк по словам, одинокое тире — к прежнему слову, хвост — с «…».
    static func разбить(_ текст: String, _ шрифт: UIFont, _ ширина: CGFloat, _ строк: Int) -> [String] {
        var слова = текст.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var i = слова.count - 1
        while i > 0 {
            if слова[i] == "—" || слова[i] == "–" || слова[i] == "-" {
                слова[i - 1] = "\(слова[i - 1]) \(слова[i])"
                слова.remove(at: i)
            }
            i -= 1
        }
        var итог: [String] = []
        var n = 0
        while n < слова.count && итог.count < строк {
            let последняя = итог.count == строк - 1
            var строка = слова[n]
            n += 1
            while n < слова.count {
                let проба = "\(строка) \(слова[n])"
                let хвост = последняя && n + 1 < слова.count ? "…" : ""
                if ширинаТекста("\(проба)\(хвост)", шрифт) > ширина { break }
                строка = проба
                n += 1
            }
            if последняя && n < слова.count {
                var чистая = строка
                while let знак = чистая.last, " ,.;:!?—–-".contains(знак) { чистая.removeLast() }
                строка = обрезать("\(чистая.isEmpty ? строка : чистая)…", шрифт, ширина)
            } else if ширинаТекста(строка, шрифт) > ширина {
                строка = обрезать(строка, шрифт, ширина)
            }
            итог.append(строка)
        }
        return итог
    }
}
