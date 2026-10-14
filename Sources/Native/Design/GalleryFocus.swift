import UIKit
import Vision
import ImageIO

/**
 РАМКА ФОТО НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ И УМНАЯ ОБРЕЗКА (владелец 14.10.2026, TestFlight: «отображение товара в модалке —
 все должны быть одного вида 16 на 9, и только в полноэкранном виде видно, что это 9 на 16»; «фото в модалке товара —
 у всех одинаковая схема должна быть»).

 Галерея (ГалереяСайта, SiteListingParts.swift) у всех объявлений одной высоты — ширина × 9/16, снимок заполняет её
 целиком, без полос и размытой подложки: вертикальный и горизонтальный выглядят одинаково. Снимок целиком, в своей
 пропорции, — только на весь экран (ФотоНаВесьЭкран, ListingDetailView.swift).

 Чтобы у вертикального снимка (телефон, человек в одежде, машина сбоку) не отрезался главный предмет, кадр сдвигается
 к нему: Vision на уменьшенной до 256 px копии находит предметы (VNGenerateObjectnessBasedSaliencyImageRequest — рамка
 во весь предмет: весь человек, вся машина, а не только лицо или надпись), и середина их общей рамки встаёт в центр
 рамки галереи — но край снимка внутрь неё не заходит. Предметов не нашлось — куда смотрит глаз (внимание,
 VNGenerateAttentionBasedSaliencyImageRequest). Считается на своей очереди, вне главной нити и не на нитях Swift
 Concurrency, по одному снимку за раз, один раз на адрес: точки лежат в памяти (NSCache), повторное открытие
 объявления — без Vision. Галерея ждёт не дольше 0,3 с (первый разбор после запуска грузит модель): не успел — центр,
 а точка ляжет в память к следующему показу. Снимок почти той же пропорции, что рамка, не режется — Vision для него
 не зовём. Ошибка Vision или ничего не нашлось — центр.
 */
enum РамкаГалереиОбъявления {
    /// Ширина к высоте фото в галерее — одна на все объявления, от снимков не зависит (16:9).
    static let пропорция: CGFloat = 16.0 / 9.0

    /// Высота фото при этой ширине (без строки состояния над ним).
    static func высотаФото(ширина: CGFloat) -> CGFloat {
        max(0, ширина) / пропорция
    }
}

enum ФокусСнимка {
    /// Длинная сторона копии для Vision, px: карты предметов и внимания у Vision всё равно грубые, а копия считается
    /// за миллисекунды.
    private static let сторона: CGFloat = 256
    /// Центр снимка — когда фокуса нет.
    static let центр = CGPoint(x: 0.5, y: 0.5)

    /// Готовые точки по адресу снимка: второй показ того же фото — сразу, без Vision. NSCache сам потокобезопасен и
    /// сам чистится при нехватке памяти.
    private static let кэш: NSCache<NSURL, NSValue> = {
        let хранилище = NSCache<NSURL, NSValue>()
        хранилище.countLimit = 600
        return хранилище
    }()

    /// Своя очередь на весь разбор: синхронный perform Vision (на холодном старте — сотни миллисекунд) не держит нити
    /// Swift Concurrency, на которых идут сеть и раскодирование соседних слайдов; снимки идут по одному, модель
    /// грузится один раз.
    private static let очередь = DispatchQueue(label: "kz.kliko.gallery-focus", qos: .userInitiated)

    /// Точка главного предмета в долях 0…1 от левого верхнего угла снимка (как его видно — с учётом поворота
    /// UIImage). Не на главной нити; один раз на адрес. Ждёт Vision сколько нужно — для прогрева заранее.
    static func фокус(для снимок: UIImage, адрес: URL) async -> CGPoint {
        if let готовая = ФокусСнимка.безРазбора(снимок, адрес: адрес) { return готовая }
        return await withCheckedContinuation { (продолжить: CheckedContinuation<CGPoint, Never>) in
            ФокусСнимка.очередь.async {
                продолжить.resume(returning: ФокусСнимка.разобрать(снимок, адрес: адрес))
            }
        }
    }

    /// То же, но не дольше срока, с: первый разбор после запуска грузит модель Vision, и спиннер галереи ждал бы её.
    /// Не успел — центр сейчас (кадр потом не прыгает), а разбор доходит до конца и кладёт точку в память — следующий
    /// показ уже с ней.
    static func фокус(для снимок: UIImage, адрес: URL, неДольше срок: Double) async -> CGPoint {
        if let готовая = ФокусСнимка.безРазбора(снимок, адрес: адрес) { return готовая }
        return await withCheckedContinuation { (продолжить: CheckedContinuation<CGPoint, Never>) in
            let ответ = ОдинОтветФокуса(продолжить)
            ФокусСнимка.очередь.async {
                ответ.отдать(ФокусСнимка.разобрать(снимок, адрес: адрес))
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + срок) {
                ответ.отдать(ФокусСнимка.центр)
            }
        }
    }

    /// Ответ без Vision: точка уже в памяти; снимок пустой; почти та же пропорция, что у рамки, — обрезать нечего.
    /// nil — нужен разбор.
    private static func безРазбора(_ снимок: UIImage, адрес: URL) -> CGPoint? {
        if let готовая = кэш.object(forKey: адрес as NSURL) { return готовая.cgPointValue }
        let размер = снимок.size
        guard размер.width > 0, размер.height > 0 else { return центр }
        let доля = (размер.width / размер.height) / РамкаГалереиОбъявления.пропорция
        if abs(доля - 1) < 0.03 { return центр }
        return nil
    }

    /// Разбор на очереди и точка в память. Сначала память: пока снимок ждал очереди, его мог разобрать другой показ.
    private static func разобрать(_ снимок: UIImage, адрес: URL) -> CGPoint {
        let ключ = адрес as NSURL
        if let готовая = кэш.object(forKey: ключ) { return готовая.cgPointValue }
        let точка = найти(снимок)
        кэш.setObject(NSValue(cgPoint: точка), forKey: ключ)
        return точка
    }

    /**
     Где лежит снимок, заполняющий рамку (как scaledToFill): точка фокуса — в центре рамки, но край снимка внутрь рамки
     не заходит (сдвиг зажат). Прямоугольник — в координатах рамки, начало в левом верхнем углу; его ширина и высота —
     размер снимка на экране (не меньше рамки).
     */
    static func кадр(снимок размер: CGSize, рамка: CGSize, фокус: CGPoint) -> CGRect {
        guard размер.width > 0, размер.height > 0, рамка.width > 0, рамка.height > 0 else {
            return CGRect(origin: .zero, size: рамка)
        }
        let масштаб = max(рамка.width / размер.width, рамка.height / размер.height)
        let ширина = размер.width * масштаб
        let высота = размер.height * масштаб
        let x = min(0, max(рамка.width - ширина, рамка.width / 2 - фокус.x * ширина))
        let y = min(0, max(рамка.height - высота, рамка.height / 2 - фокус.y * высота))
        return CGRect(x: x, y: y, width: ширина, height: высота)
    }

    // MARK: - Vision

    /// Сам разбор — для очереди: уменьшенная копия, предметы Vision (не нашлось — внимание), середина общей рамки
    /// найденного. Внимание тянется к лицу и надписям: у человека в одежде во весь рост кадр встал бы на голову, а
    /// рамка предмета — весь человек, и в центр встаёт сама вещь.
    private static func найти(_ снимок: UIImage) -> CGPoint {
        guard let копия = уменьшить(снимок) else { return центр }
        /* Пиксели копии лежат как у исходного CGImage, а поворот — в метке UIImage: Vision поворачивает сам и отдаёт
           рамки уже в координатах снимка, каким его видно. */
        let обработчик = VNImageRequestHandler(cgImage: копия, orientation: ориентация(снимок.imageOrientation),
                                              options: [:])
        let предметы = VNGenerateObjectnessBasedSaliencyImageRequest()
        var рамки = (try? обработчик.perform([предметы])) != nil ? рамкиИз(предметы.results?.first) : []
        if рамки.isEmpty {
            let внимание = VNGenerateAttentionBasedSaliencyImageRequest()
            if (try? обработчик.perform([внимание])) != nil { рамки = рамкиИз(внимание.results?.first) }
        }
        guard var общая = рамки.first else { return центр }
        for рамка in рамки.dropFirst() { общая = общая.union(рамка) }
        /* У Vision начало — снизу слева, у экрана — сверху слева. */
        return CGPoint(x: min(1, max(0, общая.midX)), y: min(1, max(0, 1 - общая.midY)))
    }

    /// Рамки найденного (у Vision — доли 0…1, начало снизу слева), без пустых.
    private static func рамкиИз(_ итог: VNSaliencyImageObservation?) -> [CGRect] {
        (итог?.salientObjects ?? [])
            .map { $0.boundingBox }
            .filter { !$0.isNull && $0.width > 0 && $0.height > 0 }
    }

    /// Копия не больше 256 px по длинной стороне — пиксели как у исходного CGImage (без поворота). Снимок без CGImage
    /// (из CIImage) — nil.
    private static func уменьшить(_ снимок: UIImage) -> CGImage? {
        guard let исходный = снимок.cgImage, исходный.width > 0, исходный.height > 0 else { return nil }
        let доля = min(1, сторона / CGFloat(max(исходный.width, исходный.height)))
        let ширина = max(1, Int((CGFloat(исходный.width) * доля).rounded()))
        let высота = max(1, Int((CGFloat(исходный.height) * доля).rounded()))
        guard let холст = CGContext(data: nil, width: ширина, height: высота, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        холст.interpolationQuality = .medium
        холст.draw(исходный, in: CGRect(x: 0, y: 0, width: ширина, height: высота))
        return холст.makeImage()
    }

    /// Поворот снимка для Vision: пиксели CGImage лежат как сняты, а поворот — в метке UIImage.
    private static func ориентация(_ метка: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch метка {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// Ответить галерее ровно один раз — кто первым: разбор Vision с точкой или срок с центром.
private final class ОдинОтветФокуса: @unchecked Sendable {
    private let замок = NSLock()
    private var продолжить: CheckedContinuation<CGPoint, Never>?

    init(_ продолжить: CheckedContinuation<CGPoint, Never>) {
        self.продолжить = продолжить
    }

    func отдать(_ точка: CGPoint) {
        замок.lock()
        let ждущее = продолжить
        продолжить = nil
        замок.unlock()
        ждущее?.resume(returning: точка)
    }
}
