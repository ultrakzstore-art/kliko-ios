import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import UIKit
import Vision

/**
 ИИ-СТУДИЯ ФОТО ПОДАЧИ — ОБРАБОТКА (владелец 13.10.2026: «свой редактор фото для техники через ИИ»).

 Всё на телефоне — без сервера, без денег, без чужих библиотек:
   · Vision VNGenerateForegroundInstanceMaskRequest (iOS 17.0) — маска предмета, то же «поднять объект», что у Фото.
     Предмет — самый крупный экземпляр и всё рядом с ним; мелочь (меньше 0,2 % кадра) и дальние небольшие пятна (водяной
     знак у края, соринка) отбрасываются. Предмет меньше 0,4 % кадра или маски нет вовсе (симулятор, пустой стол) — «не
     нашли», работает только «Свет и цвет»;
   · CoreImage — студийный фон («Белый», «Светлый», «Градиент», «Тёплый», «Тёмный»), мягкая тень (размытый силуэт
     чуть ниже предмета и пятно касания под ним), предмет — по центру с полями; autoAdjustmentFilters (свет и цвет) и
     лёгкая резкость;
   · холст — того же размера, что исходник (длинная сторона не больше 1280, белая подложка — ОбработкаФото.ужать, как
     у любого фото подачи); JPEG, миниатюру и знак делает ОбработкаФото.подготовить — тем же путём.
 Всё здесь — чистые функции без главного потока: их зовут из Task.detached, на входе и выходе — CGImage (через
 ящики @unchecked Sendable: CGImage неизменяем).
 */
extension Config {
    /// ИИ-студия фото в подаче: «Студия» в меню плитки фото и плашка «Сделать как в каталоге» над фото техники. Всё на
    /// телефоне — сервер не нужен, поэтому включено. false — ни пункта, ни значка, ни плашки.
    static let студияФото = true
}

/// Фон студии. «Свой» — фон снимка как есть (меняются только свет и цвет).
enum ФонСтудииФото: String, CaseIterable, Identifiable, Sendable {
    case свой = "own"
    case белый = "white"
    case светлый = "light"
    case градиент = "gradient"
    case тёплый = "warm"
    case тёмный = "dark"

    var id: String { rawValue }

    /// Ключ подписи в СтудияФотоText.
    var ключ: String { "st_bg_" + rawValue }

    /// Цвета фона: верх и низ (у «Градиента» и «Тёмного» — середина и края). Ими же рисуется кружок-образец.
    var цвета: (UInt32, UInt32) {
        switch self {
        case .свой, .белый: return (0xFFFFFF, 0xFFFFFF)
        case .светлый: return (0xF7F8F8, 0xE4E9E7)
        case .градиент: return (0xFFFFFF, 0xC6D1D9)
        case .тёплый: return (0xFFF8EE, 0xE8D4BA)
        case .тёмный: return (0x3D434A, 0x111315)
        }
    }

    /// Круглое пятно света от середины к краям, а не сверху вниз.
    var круглый: Bool { self == .градиент || self == .тёмный }
}

/// Что выбрано на экране студии.
struct НастройкиСтудииФото: Equatable, Sendable {
    var фон: ФонСтудииФото = .белый
    var тень = true
    var свет = true
}

/// Неизменяемый кадр для Task.detached.
struct КадрСтудииФото: @unchecked Sendable {
    let картинка: CGImage?
}

/**
 Разбор снимка — один раз на открытие студии: исходник, он же со «Светом и цветом», вырезанный предмет (на своём месте,
 вокруг прозрачно) в обоих видах и рамка предмета. Дальше любой фон и тень собираются из этого за доли секунды.
 */
struct АнализСтудииФото: @unchecked Sendable {
    let исходник: CGImage
    let светлый: CGImage
    let предмет: CGImage?
    let предметСветлый: CGImage?
    /// Рамка предмета в пикселях исходника, начало — снизу слева (как у CoreImage).
    let рамка: CGRect

    var ширина: CGFloat { CGFloat(исходник.width) }
    var высота: CGFloat { CGFloat(исходник.height) }
    var холст: CGRect { CGRect(x: 0, y: 0, width: ширина, height: высота) }
    var естьПредмет: Bool { (предмет != nil || предметСветлый != nil) && рамка.width >= 2 && рамка.height >= 2 }

    /// Студийный фон: предмет найден и фон не «Свой».
    func вырез(_ н: НастройкиСтудииФото) -> Bool { естьПредмет && н.фон != .свой }

    /// Вырезанный предмет на своём месте — с «Светом и цветом» или как снят.
    func предметДля(_ н: НастройкиСтудииФото) -> CGImage? {
        н.свет ? (предметСветлый ?? предмет) : (предмет ?? предметСветлый)
    }

    /**
     Куда предмет встаёт на студийном фоне: по центру, поля — 11 % по бокам и 13 % сверху и снизу, чуть выше середины
     (под ним — тень). Мелкий предмет растягивается не больше чем в 1,8 раза — дальше уже мыло.
     */
    var место: CGRect {
        guard рамка.width > 0, рамка.height > 0 else { return холст }
        var к = min(ширина * 0.78 / рамка.width, высота * 0.74 / рамка.height)
        к = min(к, 1.8)
        let ш = рамка.width * к
        let в = рамка.height * к
        let низ = max(высота * 0.06, (высота - в) / 2 + высота * 0.025)
        return CGRect(x: (ширина - ш) / 2, y: низ, width: ш, height: в)
    }

    /// Во сколько раз предмет меняет размер на студийном фоне.
    var масштаб: CGFloat { рамка.width > 0 ? место.width / рамка.width : 1 }

    /// Рамка и место с началом сверху слева — для экрана (SwiftUI считает сверху).
    var рамкаСверху: CGRect { сверху(рамка) }
    var местоСверху: CGRect { сверху(место) }

    private func сверху(_ р: CGRect) -> CGRect {
        CGRect(x: р.minX, y: высота - р.maxY, width: р.width, height: р.height)
    }
}

/// Готовые картинки из Task.detached: «После» целиком и фон с тенью без предмета (для полёта предмета).
struct СлоиСтудииФото: @unchecked Sendable {
    let итог: CGImage?
    let фон: CGImage?
}

enum ДвижокСтудииФото {
    /// Один на всё: CIContext потокобезопасен, а создавать его на каждую отрисовку дорого.
    private static let контекст = CIContext(options: [.cacheIntermediates: false])
    private static let пространство = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Снимок подачи → прямой кадр (поворот учтён) на белой подложке, длинная сторона не больше 1280 — как фото подачи.
    static func кадр(_ данные: Data) -> CGImage? {
        guard let картинка = UIImage(data: данные),
              let ровное = ОбработкаФото.ужать(картинка, сторона: 1280) else { return nil }
        return ровное.cgImage
    }

    /// Разбор: свет и цвет, маска Vision, вырезанный предмет. nil — отменено или кадр не отрисовался.
    static func разобрать(_ кадр: CGImage) -> АнализСтудииФото? {
        let вход = CIImage(cgImage: кадр)
        let холст = CGRect(x: 0, y: 0, width: CGFloat(кадр.width), height: CGFloat(кадр.height))
        guard let светлый = отрисовать(подправить(вход, холст), холст) else { return nil }
        if Task.isCancelled { return nil }
        guard let найдено = найтиПредмет(кадр) else {
            return АнализСтудииФото(исходник: кадр, светлый: светлый, предмет: nil, предметСветлый: nil, рамка: .zero)
        }
        if Task.isCancelled { return nil }
        let предмет = вырезать(вход, найдено.маска, холст)
        let предметСветлый = вырезать(CIImage(cgImage: светлый), найдено.маска, холст)
        return АнализСтудииФото(исходник: кадр, светлый: светлый, предмет: предмет, предметСветлый: предметСветлый,
                                рамка: найдено.рамка)
    }

    /// «После» целиком — то, что видно на экране и что уйдёт в подачу.
    static func итог(_ а: АнализСтудииФото, _ н: НастройкиСтудииФото) -> CGImage? {
        guard а.вырез(н), let предмет = предметНаМесте(а, н) else { return н.свет ? а.светлый : а.исходник }
        return отрисовать(предмет.composited(over: фонСТенью(а, н)).cropped(to: а.холст), а.холст)
    }

    /// Студийный фон с тенью, но без предмета: под ним предмет «перелетает» на своё место. nil — фона нет.
    static func фонПолёта(_ а: АнализСтудииФото, _ н: НастройкиСтудииФото) -> CGImage? {
        guard а.вырез(н) else { return nil }
        return отрисовать(фонСТенью(а, н), а.холст)
    }

    // MARK: - Свет и цвет

    /// autoAdjustmentFilters (экспозиция, тени и света, насыщенность — то же «Улучшить», что у Фото) и лёгкая резкость.
    private static func подправить(_ кадр: CIImage, _ холст: CGRect) -> CIImage {
        var итог = кадр
        for фильтр in кадр.autoAdjustmentFilters(options: [.redEye: false]) {
            фильтр.setValue(итог, forKey: kCIInputImageKey)
            if let выход = фильтр.outputImage { итог = выход }
        }
        let резкость = CIFilter.sharpenLuminance()
        резкость.inputImage = итог
        резкость.sharpness = 0.4
        return (резкость.outputImage ?? итог).cropped(to: холст)
    }

    // MARK: - Предмет (Vision)

    /// Маска предмета на весь кадр и его рамка (снизу слева, в пикселях кадра). nil — предмета нет.
    private static func найтиПредмет(_ кадр: CGImage) -> (маска: CIImage, рамка: CGRect)? {
        let запрос = VNGenerateForegroundInstanceMaskRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return nil
        }
        guard let наблюдение = запрос.results?.first else { return nil }
        let отобранные = отобрать(наблюдение)
        guard !отобранные.isEmpty,
              let буфер = try? наблюдение.generateScaledMaskForImage(forInstances: отобранные, from: обработчик),
              let границы = границыМаски(буфер), границы.доля >= 0.004 else { return nil }
        let ширина = CGFloat(кадр.width)
        let высота = CGFloat(кадр.height)
        var маска = CIImage(cvPixelBuffer: буфер)
        let размер = маска.extent.size
        if размер.width > 0, размер.height > 0, (размер.width != ширина || размер.height != высота) {
            маска = маска.transformed(by: CGAffineTransform(scaleX: ширина / размер.width, y: высота / размер.height))
        }
        let кx = ширина / CGFloat(границы.ширина)
        let кy = высота / CGFloat(границы.высота)
        let р = границы.рамка
        let рамка = CGRect(x: р.minX * кx, y: высота - р.maxY * кy, width: р.width * кx, height: р.height * кy)
        return (маска, рамка)
    }

    /**
     Экземпляры предмета: главный (самый крупный) и те, что рядом с ним, — без мелочи (меньше 0,2 % кадра). Крупная
     вторая часть (не меньше четверти главной: комплект, коробка рядом) входит всегда; небольшая — только если её рамка
     касается рамки главного с запасом 6 % кадра. Дальнее пятно у края — водяной знак Kliko (около 1 % кадра, в одном из
     шести мест ОбработкаФото.знак), соринка, чужая мелочь — в предмет не входит, иначе рамка растянулась бы до угла
     кадра и вещь встала бы мельче и не по центру. Метки не читаются.
     */
    private static func отобрать(_ наблюдение: VNInstanceMaskObservation) -> IndexSet {
        let все = наблюдение.allInstances
        guard все.count > 1 else { return все }
        let буфер = наблюдение.instanceMask
        CVPixelBufferLockBaseAddress(буфер, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(буфер, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(буфер) == kCVPixelFormatType_OneComponent8,
              let база = CVPixelBufferGetBaseAddress(буфер) else { return все }
        let ширина = CVPixelBufferGetWidth(буфер)
        let высота = CVPixelBufferGetHeight(буфер)
        let ряд = CVPixelBufferGetBytesPerRow(буфер)
        guard ширина > 0, высота > 0 else { return все }
        var счёт = [Int](repeating: 0, count: 256)
        var минX = [Int](repeating: Int.max, count: 256)
        var минY = [Int](repeating: Int.max, count: 256)
        var максX = [Int](repeating: -1, count: 256)
        var максY = [Int](repeating: -1, count: 256)
        for y in 0..<высота {
            let строка = база.advanced(by: y * ряд)
            for x in 0..<ширина {
                let метка = Int(строка.load(fromByteOffset: x, as: UInt8.self))
                счёт[метка] += 1
                guard метка > 0 else { continue }
                if x < минX[метка] { минX[метка] = x }
                if x > максX[метка] { максX[метка] = x }
                if y < минY[метка] { минY[метка] = y }
                if y > максY[метка] { максY[метка] = y }
            }
        }
        let порог = max(1, ширина * высота / 500)
        var лучший = -1
        var лучшийСчёт = 0
        for номер in все where номер > 0 && номер < 256 && счёт[номер] > лучшийСчёт {
            лучший = номер
            лучшийСчёт = счёт[номер]
        }
        guard лучший > 0 else { return все }
        func рамка(_ номер: Int) -> CGRect {
            CGRect(x: минX[номер], y: минY[номер], width: максX[номер] - минX[номер] + 1,
                   height: максY[номер] - минY[номер] + 1)
        }
        let запас = CGFloat(max(ширина, высота)) * 0.06
        let рядом = рамка(лучший).insetBy(dx: -запас, dy: -запас)
        var итог = IndexSet(integer: лучший)
        for номер in все where номер > 0 && номер < 256 && номер != лучший && счёт[номер] >= порог {
            if счёт[номер] * 4 >= лучшийСчёт || рядом.intersects(рамка(номер)) { итог.insert(номер) }
        }
        return итог
    }

    /// Где маска плотнее половины: рамка (в точках буфера, начало сверху слева), доля кадра и размер буфера.
    private static func границыМаски(_ буфер: CVPixelBuffer) -> (рамка: CGRect, доля: Double, ширина: Int, высота: Int)? {
        CVPixelBufferLockBaseAddress(буфер, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(буфер, .readOnly) }
        guard let база = CVPixelBufferGetBaseAddress(буфер) else { return nil }
        let ширина = CVPixelBufferGetWidth(буфер)
        let высота = CVPixelBufferGetHeight(буфер)
        let ряд = CVPixelBufferGetBytesPerRow(буфер)
        let формат = CVPixelBufferGetPixelFormatType(буфер)
        let дробный = формат == kCVPixelFormatType_OneComponent32Float
        guard дробный || формат == kCVPixelFormatType_OneComponent8, ширина > 0, высота > 0 else { return nil }
        /* Шаг выборки: хватает примерно 400 точек по меньшей стороне — рамка точна до долей процента. */
        let шаг = max(1, min(ширина, высота) / 400)
        var минX = Int.max
        var минY = Int.max
        var максX = -1
        var максY = -1
        var внутри = 0
        var всего = 0
        var y = 0
        while y < высота {
            let строка = база.advanced(by: y * ряд)
            var x = 0
            while x < ширина {
                let значение: Float
                if дробный {
                    значение = строка.load(fromByteOffset: x * 4, as: Float32.self)
                } else {
                    значение = Float(строка.load(fromByteOffset: x, as: UInt8.self)) / 255
                }
                всего += 1
                if значение > 0.5 {
                    внутри += 1
                    минX = min(минX, x)
                    максX = max(максX, x)
                    минY = min(минY, y)
                    максY = max(максY, y)
                }
                x += шаг
            }
            y += шаг
        }
        guard внутри > 0, максX >= минX, максY >= минY else { return nil }
        let весь = CGRect(x: 0, y: 0, width: ширина, height: высота)
        let рамка = CGRect(x: минX, y: минY, width: максX - минX + шаг, height: максY - минY + шаг).intersection(весь)
        guard !рамка.isNull, !рамка.isEmpty else { return nil }
        return (рамка, Double(внутри) / Double(max(1, всего)), ширина, высота)
    }

    /// Предмет по маске (края чуть смягчены), вокруг — прозрачно. Холст — весь кадр: предмет на своём месте.
    private static func вырезать(_ кадр: CIImage, _ маска: CIImage, _ холст: CGRect) -> CGImage? {
        let мягкая = маска.clampedToExtent().applyingGaussianBlur(sigma: 0.7).cropped(to: холст)
        let смесь = CIFilter.blendWithMask()
        смесь.inputImage = кадр
        смесь.backgroundImage = CIImage(color: CIColor.clear).cropped(to: холст)
        смесь.maskImage = мягкая
        guard let выход = смесь.outputImage else { return nil }
        return отрисовать(выход.cropped(to: холст), холст)
    }

    // MARK: - Сборка

    /// Вырезанный предмет, перенесённый с исходного места на место каталога.
    private static func предметНаМесте(_ а: АнализСтудииФото, _ н: НастройкиСтудииФото) -> CIImage? {
        guard let вырезанный = а.предметДля(н) else { return nil }
        let к = а.масштаб
        let место = а.место
        let рамка = а.рамка
        let перенос = CGAffineTransform(a: к, b: 0, c: 0, d: к, tx: место.minX - рамка.minX * к,
                                        ty: место.minY - рамка.minY * к)
        return CIImage(cgImage: вырезанный).transformed(by: перенос).cropped(to: а.холст)
    }

    private static func фонСТенью(_ а: АнализСтудииФото, _ н: НастройкиСтудииФото) -> CIImage {
        let фон = фонКартинка(н.фон, а.холст)
        guard н.тень, let предмет = предметНаМесте(а, н) else { return фон }
        return тень(предмет, место: а.место, холст: а.холст, тёмный: н.фон == .тёмный).composited(over: фон)
            .cropped(to: а.холст)
    }

    /**
     Мягкая тень: силуэт предмета, чёрный, сдвинут чуть вниз и сильно размыт, плюс пятно касания — сплющенный круг под
     низом предмета. На тёмном фоне тень гуще — иначе её не видно.
     */
    private static func тень(_ предмет: CIImage, место: CGRect, холст: CGRect, тёмный: Bool) -> CIImage {
        let м = min(холст.width, холст.height)
        let сила: CGFloat = тёмный ? 0.5 : 0.24
        let силуэт = предмет.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: сила),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
        let мягкая = силуэт
            .transformed(by: CGAffineTransform(translationX: 0, y: -м * 0.018))
            .applyingGaussianBlur(sigma: Double(м * 0.024))
        let пятно = CIFilter.radialGradient()
        пятно.center = .zero
        пятно.radius0 = 0
        пятно.radius1 = Float(max(1, место.width * 0.5))
        пятно.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: тёмный ? 0.55 : 0.3)
        пятно.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let круг = пятно.outputImage else { return мягкая.cropped(to: холст) }
        let сплющить = CGAffineTransform(scaleX: 1, y: 0.085)
            .concatenating(CGAffineTransform(translationX: место.midX, y: место.minY + м * 0.006))
        return круг.transformed(by: сплющить).cropped(to: холст).composited(over: мягкая).cropped(to: холст)
    }

    private static func цвет(_ код: UInt32) -> CIColor {
        CIColor(red: CGFloat((код >> 16) & 0xFF) / 255, green: CGFloat((код >> 8) & 0xFF) / 255,
                blue: CGFloat(код & 0xFF) / 255)
    }

    /// Студийный фон: ровный, сверху вниз или круглым пятном света.
    private static func фонКартинка(_ вид: ФонСтудииФото, _ холст: CGRect) -> CIImage {
        let (первый, второй) = вид.цвета
        if первый == второй {
            return CIImage(color: цвет(первый)).cropped(to: холст)
        }
        if вид.круглый {
            let г = CIFilter.radialGradient()
            г.center = CGPoint(x: холст.midX, y: холст.minY + холст.height * 0.56)
            г.radius0 = Float(min(холст.width, холст.height) * 0.08)
            г.radius1 = Float(max(холст.width, холст.height) * 0.82)
            г.color0 = цвет(первый)
            г.color1 = цвет(второй)
            return (г.outputImage ?? CIImage(color: цвет(второй))).cropped(to: холст)
        }
        let г = CIFilter.linearGradient()
        г.point0 = CGPoint(x: холст.midX, y: холст.maxY)
        г.point1 = CGPoint(x: холст.midX, y: холст.minY)
        г.color0 = цвет(первый)
        г.color1 = цвет(второй)
        return (г.outputImage ?? CIImage(color: цвет(первый))).cropped(to: холст)
    }

    /// Отрисовка в 8-битный sRGB с прозрачностью (у предмета вокруг пусто).
    private static func отрисовать(_ картинка: CIImage, _ холст: CGRect) -> CGImage? {
        контекст.createCGImage(картинка, from: холст, format: .RGBA8, colorSpace: пространство)
    }
}
