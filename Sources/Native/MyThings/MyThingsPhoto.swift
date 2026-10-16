import SwiftUI
import UIKit
import ImageIO
import Vision

/**
 «МОЁ» — ФОТО МАШИНЫ И ФОТО В ПОЛНЫЙ РОСТ: ПОДГОТОВКА, КОЛЁСА, ПОЗА, КЭШ.

 Всё здесь — без главной нити (зовётся из Task.detached), на входе и выходе — Data, числа и UIImage:
   · подготовить — чтение ImageIO с уменьшением до 2048 px уже при чтении (фото 48 Мп не разворачивается целиком),
     перерисовка с поворотом из EXIF: в файл не уходят ни EXIF, ни место съёмки; JPEG 0,85 и миниатюра 480 px;
   · колёса — где на снимке колёса машины, если человек снимал по контуру (математика заполнения превью камеры);
   · поза — точки тела Vision (VNDetectHumanBodyPoseRequest) на телефоне: голова, плечи, бёдра, колени, лодыжки.
     Лицо не распознаётся, биометрических шаблонов нет — только «где стоит человек» для будущей примерки;
   · люди — есть ли люди на фото машины (ФотоПримерочной.естьЛюди): только подсказка «лучше без них».
 КэшФотоМоего — готовые картинки в памяти (NSCache), чтение файла — вне главной нити.
 */

/// Фото, готовое к записи: JPEG до 2048 px и миниатюра 480 px; размер большого в пикселях.
struct ГотовоеФотоМоего: Sendable {
    let jpeg: Data
    let мини: Data
    let ширина: Int
    let высота: Int
}

/// Откуда снимок: кадр камеры или файл галереи.
enum ИсточникСнимкаМоего: @unchecked Sendable {
    case кадр(UIImage)
    case файл(Data)
}

/// Где стоял контур машины в миг снимка: рамка фигуры и размер превью — в координатах превью (во весь экран).
struct РамкаШаблонаМоего: Sendable, Equatable {
    let контур: CGRect
    let вид: CGSize
}

/// Снимок после обработки — для шага проверки и записи.
struct СнимокМоего: @unchecked Sendable {
    let готовое: ГотовоеФотоМоего
    /// То же фото для экрана (2048 px).
    let картинка: UIImage
    var колёса: [КругМоего]
    let люди: Bool?
    let поза: [String: ТочкаМоего]
    let полныйРост: Bool?
    /// «car_side_1», «body_full_1» или «gallery».
    let шаблон: String
}

enum ОбработкаФотоМоего {
    /// Длинная сторона снимка и миниатюры, px.
    static let сторона: CGFloat = 2048
    static let сторонаМини: CGFloat = 480

    /// Кольца колёс у фото из галереи: где колёса у машины, снятой боком по центру кадра.
    static let колёсаПоУмолчанию = [КругМоего(x: 0.27, y: 0.62, r: 0.08), КругМоего(x: 0.73, y: 0.62, r: 0.08)]

    /// Центры колёс контура машины (СилуэтМашиныПримерочной, поле 240 × 104) и их радиус.
    private static let центрыКолёс = [CGPoint(x: 54.0 / 240.0, y: 82.0 / 104.0), CGPoint(x: 190.0 / 240.0, y: 82.0 / 104.0)]
    private static let радиусКолеса: CGFloat = 17.0 / 240.0

    // MARK: Подготовка

    /// Файл галереи: ImageIO уменьшает уже при чтении, поворот из EXIF учтён.
    static func подготовить(_ данные: Data) -> ГотовоеФотоМоего? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, чтение) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary
        guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры) else { return nil }
        return подготовить(UIImage(cgImage: кадр))
    }

    /// Кадр камеры или прочитанный файл: перерисовать (поворот учтён, метаданных нет), JPEG 0,85 и миниатюра.
    static func подготовить(_ снимок: UIImage) -> ГотовоеФотоМоего? {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard w >= 64, h >= 64 else { return nil }
        let большой = перерисовать(снимок, сторона: сторона)
        let малый = перерисовать(снимок, сторона: сторонаМини)
        guard let jpeg = большой.картинка.jpegData(compressionQuality: 0.85),
              let мини = малый.картинка.jpegData(compressionQuality: 0.8) else { return nil }
        return ГотовоеФотоМоего(jpeg: jpeg, мини: мини, ширина: Int(большой.размер.width),
                                высота: Int(большой.размер.height))
    }

    private static func перерисовать(_ снимок: UIImage, сторона: CGFloat) -> (картинка: UIImage, размер: CGSize) {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        let k = min(1, сторона / max(w, h))
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let картинка = UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            UIColor.black.setFill()
            холст.fill(CGRect(origin: .zero, size: размер))
            снимок.draw(in: CGRect(origin: .zero, size: размер))
        }
        return (картинка, размер)
    }

    // MARK: Снимок целиком

    /**
     Источник → готовое фото и разбор: у машины — кольца колёс (по контуру камеры, а у галереи и без замера контура — по
     умолчанию) и «люди в кадре», у тела — точки позы и «в полный рост». nil — фото не открылось.
     */
    static func снимок(_ источник: ИсточникСнимкаМоего, тело: Bool, рамка: РамкаШаблонаМоего?) -> СнимокМоего? {
        let готовое: ГотовоеФотоМоего?
        let изКамеры: Bool
        switch источник {
        case .кадр(let кадр):
            готовое = подготовить(кадр)
            изКамеры = true
        case .файл(let данные):
            готовое = подготовить(данные)
            изКамеры = false
        }
        guard let готовое, !Task.isCancelled, let картинка = UIImage(data: готовое.jpeg) else { return nil }
        let шаблон = !изКамеры ? ФотоМоего.шаблонГалереи : (тело ? ФотоМоего.шаблонТела : ФотоМоего.шаблонМашины)
        if тело {
            let разбор = картинка.cgImage.map { поза($0) } ?? (точки: [:], полныйРост: nil)
            return СнимокМоего(готовое: готовое, картинка: картинка, колёса: [], люди: nil, поза: разбор.точки,
                               полныйРост: разбор.полныйРост, шаблон: шаблон)
        }
        let размер = CGSize(width: готовое.ширина, height: готовое.высота)
        let круги = рамка.map { колёса(рамкаКонтура: $0.контур, вид: $0.вид, размерСнимка: размер) }
            ?? колёсаПоУмолчанию
        return СнимокМоего(готовое: готовое, картинка: картинка, колёса: круги,
                           люди: ФотоПримерочной.естьЛюди(картинка), поза: [:], полныйРост: nil, шаблон: шаблон)
    }

    // MARK: Колёса по контуру

    /**
     Колёса контура → доли снимка. Превью камеры заполняет экран (aspect-fill): м = max(вид.w / фото.w, вид.h / фото.h),
     сдвиг = ((вид.w − фото.w·м) / 2, (вид.h − фото.h·м) / 2), точка снимка = (точка экрана − сдвиг) / м. Центры колёс —
     (54/240, 82/104) и (190/240, 82/104) рамки контура, радиус — 17/240 её ширины.
     */
    static func колёса(рамкаКонтура: CGRect, вид: CGSize, размерСнимка: CGSize) -> [КругМоего] {
        guard вид.width > 0, вид.height > 0, размерСнимка.width > 0, размерСнимка.height > 0,
              рамкаКонтура.width > 1, рамкаКонтура.height > 1 else { return колёсаПоУмолчанию }
        let м = max(вид.width / размерСнимка.width, вид.height / размерСнимка.height)
        guard м > 0 else { return колёсаПоУмолчанию }
        let сдвигX = (вид.width - размерСнимка.width * м) / 2
        let сдвигY = (вид.height - размерСнимка.height * м) / 2
        let радиус = радиусКолеса * рамкаКонтура.width / м
        return центрыКолёс.map { доля in
            let наЭкранеX = рамкаКонтура.minX + доля.x * рамкаКонтура.width
            let наЭкранеY = рамкаКонтура.minY + доля.y * рамкаКонтура.height
            let x = (наЭкранеX - сдвигX) / м
            let y = (наЭкранеY - сдвигY) / м
            return КругМоего(x: КругМоего.доля(Double(x / размерСнимка.width)),
                             y: КругМоего.доля(Double(y / размерСнимка.height)),
                             r: min(0.3, max(0.02, Double(радиус / размерСнимка.width))))
        }
    }

    // MARK: Поза

    /// Суставы позы и их ключи в записи.
    private static let суставы: [(ключ: String, сустав: VNHumanBodyPoseObservation.JointName)] = [
        ("neck", .neck), ("lsh", .leftShoulder), ("rsh", .rightShoulder), ("lhip", .leftHip), ("rhip", .rightHip),
        ("lknee", .leftKnee), ("rknee", .rightKnee), ("lank", .leftAnkle), ("rank", .rightAnkle)
    ]

    /// Голова: нос, а нет его — глаз или ухо.
    private static let голова: [VNHumanBodyPoseObservation.JointName] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]

    /// Для мерок по фото (ОценкаМерокПоФото, MyThingsBodyEstimate.swift): локти и запястья — длина руки. Ещё пишется
    /// «eyes» — уровень глаз одной средней точкой (масштаб по росту); расстояние между глазами не храним.
    private static let суставыМерок: [(ключ: String, сустав: VNHumanBodyPoseObservation.JointName)] = [
        ("lelb", .leftElbow), ("relb", .rightElbow), ("lwri", .leftWrist), ("rwri", .rightWrist)
    ]

    /**
     Точки позы самого крупного человека: доли снимка, начало сверху слева (у Vision — снизу, поэтому y = 1 − y),
     уверенность не ниже 0,3. «В полный рост» — видны голова (или шея) и хоть одна лодыжка, а фигура не ниже 55 % кадра.
     Человека не нашли — пусто и nil.
     */
    static func поза(_ кадр: CGImage) -> (точки: [String: ТочкаМоего], полныйРост: Bool?) {
        let запрос = VNDetectHumanBodyPoseRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return ([:], nil)
        }
        var лучшие: [String: ТочкаМоего] = [:]
        var лучшаяВысота = -1.0
        for наблюдение in запрос.results ?? [] {
            guard let все = try? наблюдение.recognizedPoints(.all) else { continue }
            var точки: [String: ТочкаМоего] = [:]
            func точка(_ сустав: VNHumanBodyPoseObservation.JointName) -> ТочкаМоего? {
                guard let т = все[сустав], т.confidence >= 0.3 else { return nil }
                return ТочкаМоего(x: КругМоего.доля(Double(т.location.x)), y: КругМоего.доля(1 - Double(т.location.y)))
            }
            if let г = голова.lazy.compactMap({ точка($0) }).first { точки["head"] = г }
            for пара in суставы {
                if let т = точка(пара.сустав) { точки[пара.ключ] = т }
            }
            guard точки.count >= 3 else { continue }
            let ys = точки.values.map(\.y)
            let высота = (ys.max() ?? 0) - (ys.min() ?? 0)
            // Точки для мерок — после замера высоты: на выбор человека и «в полный рост» не влияют.
            for пара in суставыМерок {
                if let т = точка(пара.сустав) { точки[пара.ключ] = т }
            }
            let глаза = [точка(.leftEye), точка(.rightEye)].compactMap { $0 }
            if !глаза.isEmpty {
                точки["eyes"] = ТочкаМоего(x: глаза.map(\.x).reduce(0, +) / Double(глаза.count),
                                           y: глаза.map(\.y).reduce(0, +) / Double(глаза.count))
            }
            if высота > лучшаяВысота {
                лучшаяВысота = высота
                лучшие = точки
            }
        }
        guard !лучшие.isEmpty else { return ([:], nil) }
        let верх = лучшие["head"] != nil || лучшие["neck"] != nil
        let низ = лучшие["lank"] != nil || лучшие["rank"] != nil
        return (лучшие, верх && низ && лучшаяВысота >= 0.55)
    }

    /// Кости позы для рисунка: пары ключей точек.
    static let кости: [(String, String)] = [
        ("head", "neck"), ("neck", "lsh"), ("neck", "rsh"), ("lsh", "lhip"), ("rsh", "rhip"), ("lhip", "rhip"),
        ("lhip", "lknee"), ("lknee", "lank"), ("rhip", "rknee"), ("rknee", "rank")
    ]

    /// Порядок появления точек — сверху вниз.
    static let порядокТочек = ["head", "neck", "lsh", "rsh", "lhip", "rhip", "lknee", "rknee", "lank", "rank"]
}

// MARK: - Кэш картинок

/// Готовые картинки фото «Моего» в памяти; чтение файла — вне главной нити. NSCache сам отдаёт память под нагрузкой.
/// Предел — и по числу, и по весу в байтах: полный снимок 2048 px в памяти весит 12–16 МБ, на слабом телефоне — до 32 МБ.
enum КэшФотоМоего {
    private static let кэш: NSCache<NSString, UIImage> = {
        let к = NSCache<NSString, UIImage>()
        к.countLimit = 24
        к.totalCostLimit = ЖелезоУстройства.слабое ? 32 << 20 : 64 << 20
        return к
    }()

    /// Вес картинки в памяти, байт: пиксели × 4.
    private static func вес(_ картинка: UIImage) -> Int {
        if let cg = картинка.cgImage { return cg.bytesPerRow * cg.height }
        return Int(картинка.size.width * картинка.size.height * картинка.scale * картинка.scale * 4)
    }

    static func готовая(_ имя: String) -> UIImage? {
        кэш.object(forKey: имя as NSString)
    }

    static func загрузить(_ имя: String) async -> UIImage? {
        if let есть = готовая(имя) { return есть }
        guard let адрес = ФайлыМоего.адресФото(имя) else { return nil }
        let картинка = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let данные = try? Data(contentsOf: адрес), let к = UIImage(data: данные) else { return nil }
            return к.preparingForDisplay() ?? к
        }.value
        if let картинка { кэш.setObject(картинка, forKey: имя as NSString, cost: вес(картинка)) }
        return картинка
    }

    static func забыть(_ имя: String) {
        кэш.removeObject(forKey: имя as NSString)
    }

    static func очистить() {
        кэш.removeAllObjects()
    }
}

/// Фото «Моего» по имени файла: из кэша сразу, иначе — проявляется, когда прочитается. Пока нет — прозрачно.
struct ФотоМоегоВид: View {
    let имя: String
    var заполнить: Bool
    @State private var картинка: UIImage?

    init(имя: String, заполнить: Bool = true) {
        self.имя = имя
        self.заполнить = заполнить
        _картинка = State(initialValue: КэшФотоМоего.готовая(имя))
    }

    var body: some View {
        ZStack {
            if let картинка {
                Image(uiImage: картинка)
                    .resizable()
                    .aspectRatio(contentMode: заполнить ? .fill : .fit)
                    .transition(.opacity)
            } else {
                Color.clear
            }
        }
        .accessibilityHidden(true)
        .task(id: имя) {
            if let есть = КэшФотоМоего.готовая(имя) {
                картинка = есть
                return
            }
            let прочитанная = await КэшФотоМоего.загрузить(имя)
            withAnimation(ДвижениеСайта.появление) { картинка = прочитанная }
        }
    }
}
