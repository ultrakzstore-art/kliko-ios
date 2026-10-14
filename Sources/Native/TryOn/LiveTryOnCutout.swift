import UIKit
import Vision
import CoreImage
import CoreVideo
import Photos

/**
 ЖИВАЯ ПРИМЕРКА — ВЕЩЬ С ФОТО ОБЪЯВЛЕНИЯ И СНИМОК (владелец 13.10.2026: «нужнее охват всего»).

 Вырезка — один раз на фото, не на главной нити (Task.detached), результат — PNG с прозрачностью:
   1. фото поворачивается прямо и ужимается до 1024 px;
   2. на фото есть лицо (вещь надета на человека или манекен) — честно «нужна фотография самой вещи»: иначе на лицо
      легло бы чужое лицо;
   3. VNGenerateForegroundInstanceMaskRequest (iOS 17) — предмет переднего плана; у серёг — два самых крупных
      предмета (левая и правая), у остального — все заметные предметы вместе;
   4. Vision не справился (симулятор, тонкая оправа на белом) — запасной путь: однотонный фон по краям фото заливкой от
      краёв (белый каталог, прозрачный PNG); внутренние «дырки» цвета фона (белый циферблат) остаются;
   5. ничего не вышло — «Не получилось отделить вещь от фона на этом фото», выбор другого фото.
 У серёг одна вырезка на двоих: широкая — режется пополам по самому пустому столбцу, иначе вторая — зеркальная.

 Снимок — кадр камеры (тот, что был на экране: заполнение и края — как у превью) и вещь поверх тем же расчётом, что
 у слоя вещи. Сохраняется в Фото только на добавление (NSPhotoLibraryAddUsageDescription).
 */
enum ВырезкаЖивойПримерки {
    /// Картинки неизменяемы — переходят из фоновой задачи на главную нить как есть.
    enum Итог: @unchecked Sendable {
        /// Вырезки с прозрачностью: одна, у серёг — две (левая и правая).
        case готово([UIImage])
        /// Предмет не отделился от фона.
        case фон
        /// На фото — человек.
        case человек
    }

    private static let длиннаяСторона: CGFloat = 1024
    private static let контекст = CIContext(options: [.cacheIntermediates: false])

    /// пара — серьги (две вырезки); стоя — часы и браслет: лежащий поперёк кадра ремешок или цепочку ставим стоя
    /// (на экране высота картинки идёт поперёк руки).
    /// Задачу отменили (другое фото, экран закрыт) — между шагами выходим: итог всё равно выбросят, а Vision и заливка
    /// отбирали бы ресурс у живого анализа лица и руки.
    static func вырезать(_ исходная: UIImage, пара: Bool, стоя: Bool) -> Итог {
        guard let кадр = прямой(исходная), !Task.isCancelled else { return .фон }
        if естьЛицо(кадр) { return .человек }
        if Task.isCancelled { return .фон }
        var куски = черезVision(кадр, пара: пара) ?? []
        if Task.isCancelled { return .фон }
        if куски.isEmpty, let однотонный = черезФон(кадр) { куски = [однотонный] }
        guard !куски.isEmpty, !Task.isCancelled else { return .фон }
        if пара && куски.count == 1 { куски = разделитьПару(куски[0]) }
        if стоя {
            куски = куски.map { (кусок: CGImage) -> CGImage in
                guard Double(кусок.width) > Double(кусок.height) * 1.3, let стоячий = Self.наБок(кусок) else { return кусок }
                return стоячий
            }
        }
        let готовые = куски.compactMap(вPNG)
        guard готовые.count == куски.count, !готовые.isEmpty else { return .фон }
        return .готово(готовые)
    }

    // MARK: Подготовка

    /// Прямо (без метки поворота) и не больше 1024 px по длинной стороне, 8 бит sRGB.
    private static func прямой(_ картинка: UIImage) -> CGImage? {
        let w = картинка.size.width * картинка.scale
        let h = картинка.size.height * картинка.scale
        guard w >= 32, h >= 32 else { return nil }
        let k = min(1, длиннаяСторона / max(w, h))
        if картинка.imageOrientation == .up, k >= 1, let готовая = картинка.cgImage { return готовая }
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = false
        формат.preferredRange = .standard
        return UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
            картинка.draw(in: CGRect(origin: .zero, size: размер))
        }.cgImage
    }

    /// Заметное лицо на фото вещи (выше 10 % высоты кадра).
    private static func естьЛицо(_ кадр: CGImage) -> Bool {
        let запрос = VNDetectFaceRectanglesRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return false
        }
        return (запрос.results ?? []).contains { $0.boundingBox.height > 0.1 && $0.confidence > 0.6 }
    }

    // MARK: Vision

    private struct Предмет {
        var площадь = 0
        var суммаX = 0
    }

    private static func черезVision(_ кадр: CGImage, пара: Bool) -> [CGImage]? {
        let запрос = VNGenerateForegroundInstanceMaskRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return nil
        }
        guard let наблюдение = запрос.results?.first, !наблюдение.allInstances.isEmpty else { return nil }
        let маска = наблюдение.instanceMask
        let предметы = посчитать(маска)
        let всего = max(1, CVPixelBufferGetWidth(маска) * CVPixelBufferGetHeight(маска))
        let свои = предметы.filter { наблюдение.allInstances.contains($0.key) }
        guard let крупнейший = свои.values.map(\.площадь).max(), крупнейший > 0 else { return nil }
        /* Весь кадр — «предмет»: отделить не вышло. */
        if Double(свои.values.map(\.площадь).reduce(0, +)) / Double(всего) > 0.9 { return nil }
        let заметные = свои.filter { Double($0.value.площадь) >= Double(крупнейший) * 0.03 }
        if пара {
            func центр(_ п: Предмет) -> Double { Double(п.суммаX) / Double(max(1, п.площадь)) }
            let два = Array(заметные.sorted { $0.value.площадь > $1.value.площадь }.prefix(2))
            if два.count == 2, Double(два[1].value.площадь) >= Double(крупнейший) * 0.25 {
                let поПорядку = два.sorted { центр($0.value) < центр($1.value) }
                let куски = поПорядку.compactMap { Self.маскированная(наблюдение, IndexSet(integer: $0.key), обработчик) }
                if куски.count == 2 { return куски }
            }
        }
        guard let один = маскированная(наблюдение, IndexSet(заметные.keys), обработчик) else { return nil }
        return [один]
    }

    /// Площадь и сумма x каждого предмета по маске (значение пикселя — номер предмета, 0 — фон).
    private static func посчитать(_ маска: CVPixelBuffer) -> [Int: Предмет] {
        CVPixelBufferLockBaseAddress(маска, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(маска, .readOnly) }
        guard let начало = CVPixelBufferGetBaseAddress(маска) else { return [:] }
        let w = CVPixelBufferGetWidth(маска)
        let h = CVPixelBufferGetHeight(маска)
        let строка = CVPixelBufferGetBytesPerRow(маска)
        let байты = начало.assumingMemoryBound(to: UInt8.self)
        var итог: [Int: Предмет] = [:]
        for y in 0..<h {
            let ряд = байты + y * строка
            for x in 0..<w {
                let номер = Int(ряд[x])
                guard номер > 0 else { continue }
                var п = итог[номер] ?? Предмет()
                п.площадь += 1
                п.суммаX += x
                итог[номер] = п
            }
        }
        return итог
    }

    private static func маскированная(_ наблюдение: VNInstanceMaskObservation, _ набор: IndexSet,
                                      _ обработчик: VNImageRequestHandler) -> CGImage? {
        guard !набор.isEmpty,
              let буфер = try? наблюдение.generateMaskedImage(ofInstances: набор, from: обработчик,
                                                              croppedToInstancesExtent: true) else { return nil }
        let изображение = CIImage(cvPixelBuffer: буфер)
        guard изображение.extent.width >= 12, изображение.extent.height >= 12 else { return nil }
        let пространство = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return контекст.createCGImage(изображение, from: изображение.extent, format: .RGBA8, colorSpace: пространство)
    }

    // MARK: Однотонный фон

    /// Пиксели RGBA8 (умноженные на прозрачность), строки сверху вниз.
    private struct Растр {
        var байты: [UInt8]
        let w: Int
        let h: Int
    }

    private static func растр(_ кадр: CGImage, предел: Int) -> Растр? {
        let k = min(1.0, Double(предел) / Double(max(кадр.width, кадр.height)))
        let w = max(1, Int((Double(кадр.width) * k).rounded()))
        let h = max(1, Int((Double(кадр.height) * k).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var байты = [UInt8](repeating: 0, count: w * h * 4)
        let вышло = байты.withUnsafeMutableBytes { сырые -> Bool in
            guard let к = CGContext(data: сырые.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: пространство,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            к.interpolationQuality = .high
            к.draw(кадр, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return вышло ? Растр(байты: байты, w: w, h: h) : nil
    }

    private static func картинка(_ р: Растр) -> CGImage? {
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let поставщик = CGDataProvider(data: Data(р.байты) as CFData) else { return nil }
        return CGImage(width: р.w, height: р.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: р.w * 4,
                       space: пространство,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: поставщик, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /**
     Фон по краям однотонный (75 % краёв — одного цвета) или прозрачный — заливаем его от краёв; что не залилось —
     предмет. У границы предмета, где цвет близок к фону, — полупрозрачно (мягкий край). Предмет меньше 1 % или больше
     96 % кадра — не вышло.
     */
    private static func черезФон(_ кадр: CGImage) -> CGImage? {
        guard var р = растр(кадр, предел: 800), р.w >= 32, р.h >= 32 else { return nil }
        let w = р.w
        let h = р.h
        var края: [Int] = []
        for x in 0..<w {
            края.append(x)
            края.append((h - 1) * w + x)
        }
        for y in 1..<(h - 1) {
            края.append(y * w)
            края.append(y * w + w - 1)
        }
        let прозрачныхКраёв = края.filter { р.байты[$0 * 4 + 3] < 20 }.count
        let прозрачный = Double(прозрачныхКраёв) >= Double(края.count) * 0.7
        var фон = (r: 0, g: 0, b: 0)
        let допуск = 40
        if !прозрачный {
            let плотные = края.filter { р.байты[$0 * 4 + 3] >= 200 }
            guard плотные.count >= края.count / 2 else { return nil }
            func медиана(_ канал: Int) -> Int {
                let значения = плотные.map { Int(р.байты[$0 * 4 + канал]) }.sorted()
                return значения[значения.count / 2]
            }
            фон = (медиана(0), медиана(1), медиана(2))
            let похожих = плотные.filter { Self.близко(р, $0, фон, допуск) }.count
            guard Double(похожих) >= Double(края.count) * 0.75 else { return nil }
        }
        func фоновый(_ i: Int) -> Bool {
            if р.байты[i * 4 + 3] < 20 { return true }
            return !прозрачный && Self.близко(р, i, фон, допуск)
        }
        /* Заливка от краёв: 1 — фон. */
        var метки = [UInt8](repeating: 0, count: w * h)
        var стопка: [Int] = []
        стопка.reserveCapacity(w * 4)
        for i in края where метки[i] == 0 && фоновый(i) {
            метки[i] = 1
            стопка.append(i)
        }
        while let i = стопка.popLast() {
            let x = i % w
            let y = i / w
            if x > 0 { залить(i - 1, &метки, &стопка, фоновый) }
            if x < w - 1 { залить(i + 1, &метки, &стопка, фоновый) }
            if y > 0 { залить(i - w, &метки, &стопка, фоновый) }
            if y < h - 1 { залить(i + w, &метки, &стопка, фоновый) }
        }
        var минX = w
        var минY = h
        var максX = -1
        var максY = -1
        var предмет = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                if метки[i] == 1 {
                    р.байты[i * 4] = 0
                    р.байты[i * 4 + 1] = 0
                    р.байты[i * 4 + 2] = 0
                    р.байты[i * 4 + 3] = 0
                    continue
                }
                предмет += 1
                минX = min(минX, x)
                максX = max(максX, x)
                минY = min(минY, y)
                максY = max(максY, y)
                let уКрая = (x > 0 && метки[i - 1] == 1) || (x < w - 1 && метки[i + 1] == 1)
                    || (y > 0 && метки[i - w] == 1) || (y < h - 1 && метки[i + w] == 1)
                if уКрая && !прозрачный && близко(р, i, фон, допуск * 2) {
                    for канал in 0..<4 { р.байты[i * 4 + канал] = р.байты[i * 4 + канал] / 2 }
                }
            }
        }
        let доля = Double(предмет) / Double(w * h)
        guard доля > 0.01, доля < 0.96, максX > минX, максY > минY, let целиком = картинка(р) else { return nil }
        return целиком.cropping(to: CGRect(x: минX, y: минY, width: максX - минX + 1, height: максY - минY + 1))
    }

    private static func залить(_ i: Int, _ метки: inout [UInt8], _ стопка: inout [Int], _ фоновый: (Int) -> Bool) {
        guard метки[i] == 0 else { return }
        if фоновый(i) {
            метки[i] = 1
            стопка.append(i)
        } else {
            метки[i] = 2
        }
    }

    private static func близко(_ р: Растр, _ i: Int, _ фон: (r: Int, g: Int, b: Int), _ допуск: Int) -> Bool {
        let dr = Int(р.байты[i * 4]) - фон.r
        let dg = Int(р.байты[i * 4 + 1]) - фон.g
        let db = Int(р.байты[i * 4 + 2]) - фон.b
        return dr * dr + dg * dg + db * db < допуск * допуск
    }

    // MARK: Пара серёг

    /// Одна вырезка на двоих: широкая (пара на одном фото) — пополам по самому пустому столбцу средней трети; иначе —
    /// эта же и её зеркало.
    private static func разделитьПару(_ кусок: CGImage) -> [CGImage] {
        if Double(кусок.width) / Double(max(1, кусок.height)) > 1.45, let половины = пополам(кусок) {
            return половины
        }
        guard let зеркальная = зеркало(кусок) else { return [кусок, кусок] }
        return [кусок, зеркальная]
    }

    private static func пополам(_ кусок: CGImage) -> [CGImage]? {
        guard let р = растр(кусок, предел: max(кусок.width, кусок.height)) else { return nil }
        let от = р.w / 3
        let до = р.w * 2 / 3
        guard до > от else { return nil }
        var лучший = от
        var меньше = Int.max
        for x in от..<до {
            var сумма = 0
            for y in 0..<р.h { сумма += Int(р.байты[(y * р.w + x) * 4 + 3]) }
            if сумма < меньше {
                меньше = сумма
                лучший = x
            }
        }
        guard let левая = кусок.cropping(to: CGRect(x: 0, y: 0, width: лучший, height: кусок.height)),
              let правая = кусок.cropping(to: CGRect(x: лучший, y: 0, width: кусок.width - лучший, height: кусок.height)),
              let левая2 = обрезатьПустое(левая), let правая2 = обрезатьПустое(правая) else { return nil }
        guard левая2.width >= кусок.width / 7, правая2.width >= кусок.width / 7 else { return nil }
        return [левая2, правая2]
    }

    /// Без прозрачных полей по краям.
    private static func обрезатьПустое(_ кусок: CGImage) -> CGImage? {
        guard let р = растр(кусок, предел: max(кусок.width, кусок.height)) else { return nil }
        var минX = р.w
        var минY = р.h
        var максX = -1
        var максY = -1
        for y in 0..<р.h {
            for x in 0..<р.w where р.байты[(y * р.w + x) * 4 + 3] > 8 {
                минX = min(минX, x)
                максX = max(максX, x)
                минY = min(минY, y)
                максY = max(максY, y)
            }
        }
        guard максX >= минX, максY >= минY else { return nil }
        return кусок.cropping(to: CGRect(x: минX, y: минY, width: максX - минX + 1, height: максY - минY + 1))
    }

    private static func зеркало(_ кусок: CGImage) -> CGImage? {
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: кусок.width, height: кусок.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.translateBy(x: CGFloat(кусок.width), y: 0)
        к.scaleBy(x: -1, y: 1)
        к.draw(кусок, in: CGRect(x: 0, y: 0, width: кусок.width, height: кусок.height))
        return к.makeImage()
    }

    /// Поворот на 90° по часовой стрелке: ширина и высота меняются местами.
    private static func наБок(_ кусок: CGImage) -> CGImage? {
        let w = кусок.width
        let h = кусок.height
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: h, height: w, bitsPerComponent: 8, bytesPerRow: 0, space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.translateBy(x: 0, y: CGFloat(w))
        к.rotate(by: -CGFloat.pi / 2)
        к.draw(кусок, in: CGRect(x: 0, y: 0, width: w, height: h))
        return к.makeImage()
    }

    /// Готовая к показу картинка с прозрачностью (масштаб 1). Без круга через PNG: кусок уже растр, а картинка из PNG
    /// раскодировалась бы лениво — на главной нити при первом показе слоя вещи. Здесь, в фоне, — сразу.
    private static func вPNG(_ кусок: CGImage) -> UIImage? {
        guard кусок.width >= 12, кусок.height >= 12 else { return nil }
        let картинка = UIImage(cgImage: кусок, scale: 1, orientation: .up)
        return картинка.preparingForDisplay() ?? картинка
    }
}

// MARK: - Снимок

enum СнимокЖивойПримерки {
    struct Готовый: @unchecked Sendable {
        let картинка: UIImage
        let jpeg: Data
    }

    enum ИтогСохранения: Sendable {
        case готово
        case нетДоступа
        case сбой
    }

    /**
     Кадр камеры во весь размер экрана (заполнение, края режутся — как у превью) и вещи поверх тем же расчётом, что у
     слоя вещи: якорь — в точку центра, поворот, сжатие, ремешок дальше предела гаснет. Не на главной нити.
     */
    static func собрать(кадр: CGImage, экран: CGSize, масштаб: CGFloat, вещи: [UIImage],
                        положения: [РасположениеВещиЖивой]) -> Готовый? {
        guard экран.width > 1, экран.height > 1 else { return nil }
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = масштаб
        формат.opaque = true
        формат.preferredRange = .standard
        let итог = UIGraphicsImageRenderer(size: экран, format: формат).image { холст in
            UIColor.black.setFill()
            холст.fill(CGRect(origin: .zero, size: экран))
            let W = CGFloat(кадр.width)
            let H = CGFloat(кадр.height)
            if W > 0, H > 0 {
                let м = max(экран.width / W, экран.height / H)
                UIImage(cgImage: кадр).draw(in: CGRect(x: (экран.width - W * м) / 2, y: (экран.height - H * м) / 2,
                                                       width: W * м, height: H * м))
            }
            let к = холст.cgContext
            for (номер, р) in положения.enumerated() where р.видимость > 0.05 && вещи.indices.contains(номер) {
                let вещь = вещи[номер]
                let пропорция = вещь.size.width / max(1, вещь.size.height)
                let ш = р.ширина
                let в = ш / max(0.05, пропорция)
                var рисунок = вещь
                if let предел = р.предел, предел < в, в > 0 {
                    рисунок = Self.сМаской(вещь, видно: предел / в)
                }
                к.saveGState()
                к.setAlpha(CGFloat(р.видимость))
                к.translateBy(x: р.центр.x, y: р.центр.y)
                к.rotate(by: CGFloat(р.угол))
                к.scaleBy(x: р.сжатие.width, y: р.сжатие.height)
                рисунок.draw(in: CGRect(x: -р.якорь.x * ш, y: -р.якорь.y * в, width: ш, height: в))
                к.restoreGState()
            }
        }
        guard let jpeg = итог.jpegData(compressionQuality: 0.9) else { return nil }
        return Готовый(картинка: итог, jpeg: jpeg)
    }

    /// Доли стопов маски по высоте: видна середина `видно`, края гаснут плавно.
    static func стопы(видно: CGFloat) -> [CGFloat] {
        let доля = min(1, max(0.05, видно))
        let край = (1 - доля) / 2
        let плавно = доля * 0.12
        return [0, край, min(0.5, край + плавно), max(0.5, 1 - край - плавно), 1 - край, 1]
    }

    /// Та же маска ремешка, что у слоя вещи (LinearGradient сверху вниз): прозрачно — видно — прозрачно.
    private static func сМаской(_ вещь: UIImage, видно: CGFloat) -> UIImage {
        let размер = вещь.size
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = вещь.scale
        формат.opaque = false
        формат.preferredRange = .standard
        return UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            вещь.draw(in: CGRect(origin: .zero, size: размер))
            let места = Self.стопы(видно: видно)
            let доли: [CGFloat] = [0, 0, 1, 1, 0, 0]
            var составляющие: [CGFloat] = []
            for альфа in доли { составляющие += [1, 1, 1, альфа] }
            guard let градиент = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: составляющие,
                                            locations: места, count: места.count) else { return }
            холст.cgContext.setBlendMode(.destinationIn)
            холст.cgContext.drawLinearGradient(градиент, start: .zero, end: CGPoint(x: 0, y: размер.height),
                                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    /// В Фото iPhone: доступ только на добавление.
    static func вФото(_ данные: Data) async -> ИтогСохранения {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return .нетДоступа }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: данные, options: nil)
            }
            return .готово
        } catch {
            return .сбой
        }
    }
}
