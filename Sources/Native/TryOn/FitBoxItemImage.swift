import UIKit
import ImageIO
import CoreGraphics

/**
 «ПОМЕСТИТСЯ ЛИ?» — РЕЖИМ «ВЕЩЬ»: КАРТИНКА ДЛЯ «СТОЙКИ» (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ — 5 разных
 фото, и ИИ сам собрал 3D любой вещи или авто»). Модель режима — ВещьГабаритов (FitBoxItem.swift), сцена —
 СборкаВещиГабаритов (FitBoxItemScene.swift).

 3D-модели нет (или она не загрузилась) — вещь встаёт «стойкой»: вырезанное фото на вертикальной плоскости настоящих
 ширины и высоты. Откуда берём вырезку, по порядку:
   · ракурс «спереди» из 3D-обзора (model3d.angles[0]) — это уже PNG-вырезка движка студии из подачи (Model3DImages.swift):
     прозрачный — только обрезаем по вещи; непрозрачный (на телефоне продавца вырезать не вышло) — вырезаем сами;
   · главное фото объявления, за ним ещё два — та же вырезка, что у живой примерки (ВырезкаЖивойПримерки → общий движок
     студии ВырезкаПредмета, запасной путь — однотонный фон по краям); на фото человек — фото не годится, берём следующее.
 К вырезке — она же зеркально (задняя сторона стойки: сзади силуэт вещи отражён) и средний цвет вещи (боковины стойки).

 Чистые функции без главной нити: их зовут из Task.detached, отмену задачи проверяют между шагами.
 */
enum ПодготовкаВещиГабаритов {
    /// Готовая вырезка: лицо — с прозрачностью, обрезано по вещи; спина — оно же зеркально; средний цвет вещи — 0…1.
    /// Картинки неизменяемы — переходят на главную нить как есть.
    struct Готово: @unchecked Sendable {
        let лицо: CGImage
        let спина: CGImage
        let красный: CGFloat
        let зелёный: CGFloat
        let синий: CGFloat
    }

    /// Скачанное фото объявления — в фоновую задачу как есть (картинка неизменяема).
    struct Фото: @unchecked Sendable {
        let картинка: UIImage
    }

    enum Итог: @unchecked Sendable {
        case готово(Готово)
        /// На фото — человек (вырезался бы он).
        case человек
        /// Вещь не отделилась от фона, файл битый, задачу отменили.
        case фон
    }

    /// Файл ракурса (PNG-вырезка или JPEG кадра): не больше `сторона` px по длинной стороне.
    static func изФайла(_ файл: URL, сторона: Int) -> Итог {
        guard let кадр = прочитать(файл, сторона: сторона), !Task.isCancelled else { return .фон }
        if прозрачныеКрая(кадр) {
            guard let обрезанный = обрезатьПрозрачное(кадр) else { return .фон }
            return собрать(обрезанный)
        }
        return вырезать(кадр, сторона: сторона)
    }

    /// Фото объявления (уже скачанное): прямо, не больше 1024 px, вырезка общим движком; потом — до `сторона` px.
    static func изФото(_ картинка: UIImage, сторона: Int) -> Итог {
        guard let кадр = ВырезкаЖивойПримерки.кадр(картинка), !Task.isCancelled else { return .фон }
        return вырезать(кадр, сторона: сторона)
    }

    // MARK: Вырезка

    private static func вырезать(_ кадр: CGImage, сторона: Int) -> Итог {
        switch ВырезкаЖивойПримерки.вырезать(кадр: кадр, пара: false, стоя: false) {
        case .готово(let куски, _):
            guard let кусок = куски.first?.cgImage, !Task.isCancelled else { return .фон }
            let меньше = уменьшить(кусок, сторона: сторона) ?? кусок
            return собрать(обрезатьПрозрачное(меньше) ?? меньше)
        case .человек:
            return .человек
        case .фон:
            return .фон
        }
    }

    /// Вырезка → лицо, спина и средний цвет.
    private static func собрать(_ лицо: CGImage) -> Итог {
        guard лицо.width >= 12, лицо.height >= 12, !Task.isCancelled, let спина = зеркало(лицо) else { return .фон }
        let цвет = средний(лицо)
        return .готово(Готово(лицо: лицо, спина: спина, красный: цвет.0, зелёный: цвет.1, синий: цвет.2))
    }

    // MARK: Файл

    /// Файл с диска — сразу уменьшенным (ImageIO), с учётом поворота; PNG сохраняет прозрачность.
    private static func прочитать(_ файл: URL, сторона: Int) -> CGImage? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithURL(файл as CFURL, чтение) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: max(64, сторона)] as CFDictionary
        guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры),
              кадр.width >= 32, кадр.height >= 32 else { return nil }
        return кадр
    }

    // MARK: Растр

    /// Пиксели RGBA8 (умноженные на прозрачность), строки сверху вниз.
    private struct Растр {
        let байты: [UInt8]
        let w: Int
        let h: Int
    }

    private static func растр(_ кадр: CGImage, предел: Int) -> Растр? {
        let k = min(1.0, Double(предел) / Double(max(1, max(кадр.width, кадр.height))))
        let w = max(1, Int((Double(кадр.width) * k).rounded()))
        let h = max(1, Int((Double(кадр.height) * k).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var байты = [UInt8](repeating: 0, count: w * h * 4)
        let вышло = байты.withUnsafeMutableBytes { сырые -> Bool in
            guard let к = CGContext(data: сырые.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: пространство,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            к.interpolationQuality = .medium
            к.draw(кадр, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return вышло ? Растр(байты: байты, w: w, h: h) : nil
    }

    /// Края картинки почти все прозрачные — это уже вырезка (PNG студии), вырезать заново не надо.
    private static func прозрачныеКрая(_ кадр: CGImage) -> Bool {
        switch кадр.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        guard let р = растр(кадр, предел: 64), р.w >= 4, р.h >= 4 else { return false }
        var края: [Int] = []
        for x in 0..<р.w {
            края.append(x)
            края.append((р.h - 1) * р.w + x)
        }
        for y in 1..<(р.h - 1) {
            края.append(y * р.w)
            края.append(y * р.w + р.w - 1)
        }
        let прозрачных = края.filter { р.байты[$0 * 4 + 3] < 24 }.count
        return Double(прозрачных) >= Double(края.count) * 0.8
    }

    /// Без прозрачных полей вокруг вещи: рамка по растру до 512 px, обрезка — по самой картинке. Пусто — nil.
    private static func обрезатьПрозрачное(_ кадр: CGImage) -> CGImage? {
        guard let р = растр(кадр, предел: 512) else { return nil }
        var минX = р.w
        var минY = р.h
        var максX = -1
        var максY = -1
        for y in 0..<р.h {
            for x in 0..<р.w where р.байты[(y * р.w + x) * 4 + 3] > 12 {
                минX = min(минX, x)
                максX = max(максX, x)
                минY = min(минY, y)
                максY = max(максY, y)
            }
        }
        guard максX > минX, максY > минY else { return nil }
        let кx = CGFloat(кадр.width) / CGFloat(р.w)
        let кy = CGFloat(кадр.height) / CGFloat(р.h)
        let рамка = CGRect(x: CGFloat(минX) * кx, y: CGFloat(минY) * кy, width: CGFloat(максX - минX + 1) * кx,
                           height: CGFloat(максY - минY + 1) * кy)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: кадр.width, height: кадр.height))
        guard !рамка.isNull, рамка.width >= 12, рамка.height >= 12 else { return nil }
        return кадр.cropping(to: рамка)
    }

    /// Средний цвет вещи (по непрозрачным пикселям), чуть приглушённый — для боковин; пусто — серый.
    private static func средний(_ кадр: CGImage) -> (CGFloat, CGFloat, CGFloat) {
        guard let р = растр(кадр, предел: 48) else { return (0.5, 0.5, 0.5) }
        var r = 0.0
        var g = 0.0
        var b = 0.0
        var a = 0.0
        for i in 0..<(р.w * р.h) {
            let альфа = Double(р.байты[i * 4 + 3])
            guard альфа > 40 else { continue }
            r += Double(р.байты[i * 4])
            g += Double(р.байты[i * 4 + 1])
            b += Double(р.байты[i * 4 + 2])
            a += альфа
        }
        guard a > 0 else { return (0.5, 0.5, 0.5) }
        return (CGFloat(min(1, r / a) * 0.85), CGFloat(min(1, g / a) * 0.85), CGFloat(min(1, b / a) * 0.85))
    }

    /// Не больше `сторона` px по длинной стороне (лёгкий режим — меньше текстура).
    private static func уменьшить(_ кадр: CGImage, сторона: Int) -> CGImage? {
        let длинная = max(кадр.width, кадр.height)
        guard длинная > сторона, сторона >= 32 else { return кадр }
        let k = Double(сторона) / Double(длинная)
        let w = max(1, Int((Double(кадр.width) * k).rounded()))
        let h = max(1, Int((Double(кадр.height) * k).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.interpolationQuality = .high
        к.draw(кадр, in: CGRect(x: 0, y: 0, width: w, height: h))
        return к.makeImage()
    }

    /// Зеркально по горизонтали: задняя сторона стойки (сзади силуэт вещи отражён).
    private static func зеркало(_ кадр: CGImage) -> CGImage? {
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: кадр.width, height: кадр.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.translateBy(x: CGFloat(кадр.width), y: 0)
        к.scaleBy(x: -1, y: 1)
        к.draw(кадр, in: CGRect(x: 0, y: 0, width: кадр.width, height: кадр.height))
        return к.makeImage()
    }
}
