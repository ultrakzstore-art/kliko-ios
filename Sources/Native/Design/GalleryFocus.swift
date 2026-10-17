import UIKit
import Vision
import ImageIO
import CoreImage

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

 СБОРКА 84, рубильник gallery_43 (Config.фотоЦеликом, ListingWindowV2.swift; владелец 17.10.2026: «фото внутри модалки —
 как сделать, чтобы не резал… универсальное решение надо», на макет — «Собирай 84»). Рамка по-прежнему одна у всех, но
 4:3 — родной кадр камеры телефона и 61 % снимков kliko.kz (замер 17.10, docs/LISTING_MODAL_V2.md). Решение — по
 каждому снимку: видимая доля при заполнении min(r/f, f/r) (r — ширина к высоте снимка, f — рамки) от 85 % — снимок
 заполняет рамку с умным фокусом, как раньше; меньше — снимок целиком (scaledToFit) поверх своей размытой копии
 (РазмытаяКопияСнимка ниже: крошечная, размытая один раз вне главной нити, без живого .blur на большом кадре). Такому
 снимку Vision не нужен — резать нечего. Рубильник выключен — 16:10 и заполнение у всех, как до сборки 84.
 */
enum РамкаГалереиОбъявления {
    /// Прежняя рамка — 16:10 (владелец 14.10.2026: «во всех фото модалка 16:10»; было 16:9). Рубильник gallery_43 выключен.
    static let пропорцияПрежняя: CGFloat = 16.0 / 10.0
    /// Рамка сборки 84 — 4:3 (владелец 17.10.2026, gallery_43): как кадр камеры телефона и карточка витрины.
    static let пропорция43: CGFloat = 4.0 / 3.0
    /// Видимая доля снимка, с которой он заполняет рамку (с умным фокусом); меньше — целиком на размытой копии.
    static let порогЗаполнения: CGFloat = 0.85

    /// Ширина к высоте фото в галерее — одна на все объявления, от снимков не зависит; тот же кадр у камеры подачи.
    /// Читает рубильник сейчас; вид, который держит рамку на экране, берёт рубильник один раз при создании и зовёт
    /// пропорцияРамки(целиком:) — ответ настроек не перестраивает открытое окно.
    static var пропорция: CGFloat { пропорцияРамки(целиком: Config.фотоЦеликом) }

    /// Пропорция по уже снятому значению рубильника gallery_43: включён — 4:3, выключен — 16:10.
    static func пропорцияРамки(целиком: Bool) -> CGFloat {
        целиком ? пропорция43 : пропорцияПрежняя
    }

    /// Высота фото при этой ширине (без строки состояния над ним).
    static func высотаФото(ширина: CGFloat) -> CGFloat {
        высотаФото(ширина: ширина, целиком: Config.фотоЦеликом)
    }

    /// То же по уже снятому значению рубильника (ГалереяСайта снимает его один раз при создании).
    static func высотаФото(ширина: CGFloat, целиком: Bool) -> CGFloat {
        max(0, ширина) / пропорцияРамки(целиком: целиком)
    }

    /// Какая доля снимка видна, когда он заполняет рамку (как scaledToFill): min(r/f, f/r). Пустой снимок или рамка — 1.
    static func видимаяДоля(снимок размер: CGSize, рамка доля: CGFloat) -> CGFloat {
        guard размер.width > 0, размер.height > 0, доля > 0 else { return 1 }
        let r = размер.width / размер.height
        return min(r / доля, доля / r)
    }

    /// Снимок заполняет рамку (видно не меньше 85 %) — иначе его показывают целиком на размытой копии.
    static func заполняет(снимок размер: CGSize, рамка доля: CGFloat) -> Bool {
        видимаяДоля(снимок: размер, рамка: доля) >= порогЗаполнения
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

    /// Точка без Vision и без ожидания — для первого кадра слайда (СлайдФото): из памяти или по пропорции; nil — нужен
    /// разбор.
    static func изПамяти(_ снимок: UIImage, адрес: URL) -> CGPoint? {
        безРазбора(снимок, адрес: адрес)
    }

    /// Точка, найденная по снимку той же пропорции (обложка ленты для первого фото), — в память и для этого адреса:
    /// следующий показ встанет из памяти, без Vision.
    static func запомнить(_ точка: CGPoint, адрес: URL) {
        кэш.setObject(NSValue(cgPoint: точка), forKey: адрес as NSURL)
    }

    /// Модель Vision загружена (трогается только на очереди).
    private static var прогрето = false

    /// Скорость (владелец 16.10.2026): модель Vision грузится в простое после запуска, на крошечном холсте, — первое
    /// открытое объявление не ждёт её загрузки. Один раз за запуск, на своей очереди.
    static func прогреть() {
        очередь.async {
            guard !прогрето else { return }
            прогрето = true
            guard let холст = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let пустой = холст.makeImage() else { return }
            try? VNImageRequestHandler(cgImage: пустой, options: [:])
                .perform([VNGenerateObjectnessBasedSaliencyImageRequest()])
        }
    }

    /// Ответ без Vision: точка уже в памяти; снимок пустой; почти та же пропорция, что у рамки, — обрезать нечего.
    /// nil — нужен разбор.
    private static func безРазбора(_ снимок: UIImage, адрес: URL) -> CGPoint? {
        if let готовая = кэш.object(forKey: адрес as NSURL) { return готовая.cgPointValue }
        let размер = снимок.size
        guard размер.width > 0, размер.height > 0 else { return центр }
        /* Сборка 84 (gallery_43): снимок, который галерея покажет целиком на размытой копии, не режется — Vision ему не
           нужен (и заготовке следующего объявления тоже). В память центр не кладём: рубильник могут выключить, и тогда
           тот же снимок заполнит рамку 16:10 и получит свою точку. */
        if Config.фотоЦеликом,
           !РамкаГалереиОбъявления.заполняет(снимок: размер, рамка: РамкаГалереиОбъявления.пропорция43) {
            return центр
        }
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

/**
 Размытая копия снимка — подложка под снимок «целиком» в рамке 4:3 (сборка 84, gallery_43; владелец 17.10.2026: «фото
 внутри модалки — как сделать, чтобы не резал»). Дёшево: снимок уменьшается до 48 px по длинной стороне, размывается
 CIGaussianBlur (края продлены clampedToExtent — без тёмной каймы), один раз на адрес, на своей очереди — не на главной
 нити и не на нитях Swift Concurrency. Готовая лежит в памяти (NSCache сам потокобезопасен и сам чистится), галерея
 растягивает её на всю рамку (resizable, scaledToFill) — живого .blur на большом кадре нет: он «летает» при листании.
 */
enum РазмытаяКопияСнимка {
    /// Длинная сторона копии, px: после размытия больше и не нужно, весит она ~7 КБ.
    private static let сторона: CGFloat = 48
    /// Радиус размытия в пикселях копии (≈ 40 pt на экране).
    private static let радиус: Double = 5

    private static let кэш: NSCache<NSURL, UIImage> = {
        let хранилище = NSCache<NSURL, UIImage>()
        хранилище.countLimit = 300
        return хранилище
    }()

    /// Своя очередь: копии делаются по одной, повторная просьба того же адреса находит готовую в памяти.
    private static let очередь = DispatchQueue(label: "kz.kliko.gallery-backdrop", qos: .userInitiated)

    /// Один холст CoreImage на все копии (создаётся при первой копии, на очереди): CIContext дорог в создании, а
    /// пользоваться им можно с любой нити. Считает процессор: копия в 48 px — микросекунды, а работа видеокарты из
    /// фона (заготовка следующего объявления, пока приложение уходит в фон) iOS запрещает.
    private static let холст = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])

    /// Копия из памяти — без ожидания; nil — ещё не делали или память её выкинула.
    static func готовая(_ адрес: URL) -> UIImage? {
        кэш.object(forKey: адрес as NSURL)
    }

    /// Копия для снимка: из памяти или сделанная на очереди. nil — снимок пустой или CoreImage не справился (галерея
    /// остаётся на подложке поверхности).
    static func копия(для снимок: UIImage, адрес: URL) async -> UIImage? {
        if let готовая = РазмытаяКопияСнимка.готовая(адрес) { return готовая }
        return await withCheckedContinuation { (продолжить: CheckedContinuation<UIImage?, Never>) in
            РазмытаяКопияСнимка.очередь.async {
                продолжить.resume(returning: РазмытаяКопияСнимка.сделать(снимок, адрес: адрес))
            }
        }
    }

    /// Заготовить копию заранее, без ожидания (снимок только что раскодирован для галереи: заготовка следующего
    /// объявления, ListingFlip.swift) — первый кадр слайда встанет уже на ней.
    static func заготовить(_ снимок: UIImage, адрес: URL) {
        guard РазмытаяКопияСнимка.готовая(адрес) == nil else { return }
        РазмытаяКопияСнимка.очередь.async {
            _ = РазмытаяКопияСнимка.сделать(снимок, адрес: адрес)
        }
    }

    /// Сама копия — для очереди. Сначала память: пока снимок ждал очереди, копию мог сделать другой показ.
    private static func сделать(_ снимок: UIImage, адрес: URL) -> UIImage? {
        let ключ = адрес as NSURL
        if let готовая = кэш.object(forKey: ключ) { return готовая }
        guard let малая = уменьшить(снимок), let пиксели = малая.cgImage,
              let фильтр = CIFilter(name: "CIGaussianBlur") else { return nil }
        let исходная = CIImage(cgImage: пиксели)
        фильтр.setValue(исходная.clampedToExtent(), forKey: kCIInputImageKey)
        фильтр.setValue(радиус, forKey: kCIInputRadiusKey)
        guard let размыто = фильтр.outputImage?.cropped(to: исходная.extent),
              let итог = холст.createCGImage(размыто, from: исходная.extent) else { return nil }
        let копия = UIImage(cgImage: итог)
        кэш.setObject(копия, forKey: ключ)
        return копия
    }

    /// Снимок как его видно (поворот учтён: UIImage.draw рисует его с меткой ориентации) — в 48 px по длинной стороне.
    private static func уменьшить(_ снимок: UIImage) -> UIImage? {
        let размер = снимок.size
        guard размер.width > 0, размер.height > 0 else { return nil }
        let доля = сторона / max(размер.width, размер.height)
        let малый = CGSize(width: max(1, (размер.width * доля).rounded()),
                           height: max(1, (размер.height * доля).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let холстКопии = UIGraphicsImageRenderer(size: малый, format: формат)
        return холстКопии.image { _ in
            снимок.draw(in: CGRect(origin: .zero, size: малый))
        }
    }
}
