import SwiftUI
import AVFoundation
import Vision
import CoreImage
import ImageIO
import UIKit

/**
 ПОИСК КАМЕРОЙ ВЖИВУЮ — режим «Навести камеру» на экране поиска по фото (рядом с прежним «Выбрать фото»).

 Как работает:
 • та же живая камера (КамераПоиска), что у снимка; в этом режиме к сессии добавлен выход кадров видео
   (AVCaptureVideoDataOutput), а сама сессия — 1280×720 вместо .photo: меньше работы датчику и процессору;
 • раз в 0,3 с анализ (АнализКадровПоиска, своя очередь) снимает с кадра грубую подпись — среднюю яркость в сетке
   8×8 прямо из плоскости яркости CVPixelBuffer, без копии буфера. Кадр, стоящий 0,8 с и непохожий на последний
   отправленный, уходит JPEG-ом (длинная сторона до 768, качество 0,6) в тот же поиск по фото сайта
   (ПоискПоФотоAPI.отправить, api/photo_search.php), не чаще раза в 1,5 с, в лёгком режиме — раз в 3 с; прежний
   запрос отменяется. Тёмный или пустой кадр (голая стена) не уходит — сайту там нечего узнавать;
 • без сети: Vision (VNClassifyImageRequest) смотрит тот же стабильный кадр; метку с уверенностью больше 0,3, которая
   по словарю совпала с разделом сайта, показываем сверху «Похоже на: <раздел>»; не совпала — подписи нет;
 • снизу — полоса мини-карточек «Вы смотрели» (КарточкаНедавнегоСайта) по распознанному запросу (api/listings.php,
   как у снимка), нажатие открывает объявление тем же стеком окна, что и сетка похожих; затвор — «Снять»: прежний
   полный поиск по фото этим снимком;
 • энергия: минуту без движения — камера засыпает («Продолжить» будит), ушли с экрана или в фон — сессия стоит.

 🔴 ЛИМИТ САЙТА. photo_search.php пускает 20 поисков в час на человека (rate_limit) — и ручных, и живых вместе.
 Живой поиск сам отправляет не больше 12 кадров за час (БюджетЖивогоПоиска, на телефоне), остальное — кнопке «Снять».
 Сайт отказал не «не распознал», а иначе («Слишком часто», ИИ недоступен) — живой больше сам не шлёт до следующего
 открытия окна, а текст отказа стоит над полосой.
 */

/// Что анализ кадров сообщает модели — на главной нити.
enum СобытиеЖивогоКадра {
    /// Стабильный новый кадр — «data:image/jpeg;base64,…» для сайта.
    case кадр(String)
    /// Подсказка Vision без сети: ключ раздела сайта по словарю или nil — подписи нет.
    case раздел(String?)
    /// Минуту без движения — пора усыпить камеру.
    case покой
}

// MARK: - Анализ кадров

/// Приёмник кадров видео: подпись, покой, подсказка Vision и JPEG для сайта. Всё состояние — только на своей очереди.
final class АнализКадровПоиска: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let очередь = DispatchQueue(label: "kz.kliko.photosearch.live", qos: .userInitiated)

    /// Как часто смотреть на кадр.
    static let шагВзгляда: CFTimeInterval = 0.3
    /// Сколько кадр должен простоять, чтобы считаться стабильным.
    static let нуженПокой: CFTimeInterval = 0.8
    /// Через сколько без движения камера засыпает.
    static let сонЧерез: CFTimeInterval = 60
    /// Средняя разница подписей (яркость 0…255): больше — кадр «поехал», стабильность сначала.
    static let порогПокоя: Float = 7
    /// Больше — было движение (для сна); дрожь руки и шум матрицы — меньше.
    static let порогДвижения: Float = 3
    /// Больше — это уже другой кадр, чем отправленный (или распознанный Vision).
    static let порогНовизны: Float = 10
    static let длиннаяСторона: CGFloat = 768
    static let качество: CGFloat = 0.6

    private let наГлавную: @MainActor (СобытиеЖивогоКадра) -> Void

    /* Дальше — только на очереди анализа. */
    private var включён = false
    private var можноОтправлять = true
    private var интервал: CFTimeInterval = 1.5
    private var ориентация: CGImagePropertyOrientation = .right
    private var последнийВзгляд: CFTimeInterval = 0
    private var прежняя: [Float]? = nil
    private var началоПокоя: CFTimeInterval = 0
    private var последнееДвижение: CFTimeInterval = 0
    private var отправленная: [Float]? = nil
    private var последняяОтправка: CFTimeInterval = 0
    private var распознанная: [Float]? = nil
    private var контекст: CIContext? = nil

    init(наГлавную: @escaping @MainActor (СобытиеЖивогоКадра) -> Void) {
        self.наГлавную = наГлавную
        super.init()
    }

    /// Экран живого поиска на виду: счёт покоя и сна — заново; интервал отправки и разрешение — от модели.
    func включить(интервал: CFTimeInterval, можноОтправлять: Bool) {
        очередь.async {
            let сейчас = CACurrentMediaTime()
            self.включён = true
            self.интервал = интервал
            self.можноОтправлять = можноОтправлять
            self.прежняя = nil
            self.началоПокоя = сейчас
            self.последнееДвижение = сейчас
        }
    }

    func выключить() {
        очередь.async { self.включён = false }
    }

    func разрешитьОтправку(_ можно: Bool) {
        очередь.async { self.можноОтправлять = можно }
    }

    /// Движение не в кадре, а на экране (листают полосу похожих) — сон откладывается.
    func отметитьДвижение() {
        очередь.async { self.последнееДвижение = CACurrentMediaTime() }
    }

    /// Забыть отправленное и распознанное: после «Снять» тот же вид снова уйдёт и снова получит подсказку.
    func забыть() {
        очередь.async {
            self.отправленная = nil
            self.распознанная = nil
            self.последняяОтправка = 0
        }
    }

    /// Поворот превью (КамераПоиска передаёт его со своей очереди): 90 — портрет, кадры датчика лежат на боку.
    func повернуть(_ угол: CGFloat) {
        let новая: CGImagePropertyOrientation
        switch Int(угол.rounded()) {
        case 0: новая = .up
        case 180: новая = .down
        case 270: новая = .left
        default: новая = .right
        }
        очередь.async { self.ориентация = новая }
    }

    private func сообщить(_ событие: СобытиеЖивогоКадра) {
        let получатель = наГлавную
        Task { @MainActor in получатель(событие) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard включён else { return }
        let сейчас = CACurrentMediaTime()
        guard сейчас - последнийВзгляд >= Self.шагВзгляда else { return }
        последнийВзгляд = сейчас
        guard let буфер = CMSampleBufferGetImageBuffer(sampleBuffer), let подпись = Self.подпись(буфер) else { return }

        let сдвиг = прежняя.map { Self.разница($0, подпись) } ?? Float.greatestFiniteMagnitude
        прежняя = подпись
        if сдвиг > Self.порогДвижения { последнееДвижение = сейчас }
        if сдвиг > Self.порогПокоя { началоПокоя = сейчас }
        if сейчас - последнееДвижение >= Self.сонЧерез {
            включён = false
            сообщить(.покой)
            return
        }
        guard сейчас - началоПокоя >= Self.нуженПокой, Self.естьЧтоИскать(подпись) else { return }

        /* Подсказка без сети — на каждый новый стабильный кадр, и когда отправлять сайту уже нельзя. */
        if распознанная.map({ Self.разница($0, подпись) > Self.порогНовизны }) ?? true {
            распознанная = подпись
            сообщить(.раздел(разделVision(буфер)))
        }
        guard можноОтправлять, сейчас - последняяОтправка >= интервал,
              отправленная.map({ Self.разница($0, подпись) > Self.порогНовизны }) ?? true,
              let адрес = снимок(буфер) else { return }
        отправленная = подпись
        последняяОтправка = сейчас
        сообщить(.кадр(адрес))
    }

    /// Грубая подпись кадра: средняя яркость 8×8 клеток (0…255) по 36 точкам на клетку, прямо из буфера, без копии.
    static func подпись(_ буфер: CVPixelBuffer) -> [Float]? {
        let плоский: Bool
        switch CVPixelBufferGetPixelFormatType(буфер) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            плоский = true
        case kCVPixelFormatType_32BGRA:
            плоский = false
        default:
            return nil
        }
        guard CVPixelBufferLockBaseAddress(буфер, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(буфер, .readOnly) }
        let начальныйАдрес: UnsafeMutableRawPointer?
        let ширина: Int
        let высота: Int
        let строка: Int
        if плоский {
            начальныйАдрес = CVPixelBufferGetBaseAddressOfPlane(буфер, 0)
            ширина = CVPixelBufferGetWidthOfPlane(буфер, 0)
            высота = CVPixelBufferGetHeightOfPlane(буфер, 0)
            строка = CVPixelBufferGetBytesPerRowOfPlane(буфер, 0)
        } else {
            начальныйАдрес = CVPixelBufferGetBaseAddress(буфер)
            ширина = CVPixelBufferGetWidth(буфер)
            высота = CVPixelBufferGetHeight(буфер)
            строка = CVPixelBufferGetBytesPerRow(буфер)
        }
        guard let база = начальныйАдрес, ширина >= 16, высота >= 16 else { return nil }
        let байты = база.assumingMemoryBound(to: UInt8.self)
        /* У BGRA яркость ближе всего к зелёному каналу; у 420 — сама плоскость яркости. */
        let шагТочки = плоский ? 1 : 4
        let канал = плоский ? 0 : 1
        let сетка = 8
        let точек = 6
        let доли = сетка * точек * 2
        var итог = [Float](repeating: 0, count: сетка * сетка)
        for ряд in 0..<сетка {
            for столбец in 0..<сетка {
                var сумма = 0
                for i in 0..<точек {
                    let y = (ряд * точек * 2 + i * 2 + 1) * высота / доли
                    let начало = y * строка
                    for j in 0..<точек {
                        let x = (столбец * точек * 2 + j * 2 + 1) * ширина / доли
                        сумма += Int(байты[начало + x * шагТочки + канал])
                    }
                }
                итог[ряд * сетка + столбец] = Float(сумма) / Float(точек * точек)
            }
        }
        return итог
    }

    /// Средняя разница двух подписей по клеткам.
    static func разница(_ а: [Float], _ б: [Float]) -> Float {
        guard а.count == б.count, !а.isEmpty else { return Float.greatestFiniteMagnitude }
        var сумма: Float = 0
        for i in а.indices { сумма += abs(а[i] - б[i]) }
        return сумма / Float(а.count)
    }

    /// Не темно и не голая стена: есть свет и перепады — иначе сайту нечего распознавать, а лимит тратится.
    static func естьЧтоИскать(_ подпись: [Float]) -> Bool {
        guard let мин = подпись.min(), let макс = подпись.max(), !подпись.isEmpty else { return false }
        let средняя = подпись.reduce(0, +) / Float(подпись.count)
        return средняя > 18 && макс - мин > 12
    }

    /// Кадр — JPEG для сайта: повёрнут как экран, длинная сторона до 768, качество 0,6; «data:…;base64,…».
    private func снимок(_ буфер: CVPixelBuffer) -> String? {
        var картинка = CIImage(cvPixelBuffer: буфер).oriented(ориентация)
        let длинная = max(картинка.extent.width, картинка.extent.height)
        guard длинная > 0 else { return nil }
        let к = min(1, Self.длиннаяСторона / длинная)
        if к < 1 { картинка = картинка.transformed(by: CGAffineTransform(scaleX: к, y: к)) }
        let рамка = картинка.extent
        картинка = картинка.cropped(to: CGRect(x: рамка.minX, y: рамка.minY, width: рамка.width.rounded(.down),
                                               height: рамка.height.rounded(.down)))
        let рисовальщик = контекст ?? CIContext(options: [.cacheIntermediates: false])
        контекст = рисовальщик
        let цвета = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ключКачества = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        guard let данные = рисовальщик.jpegRepresentation(of: картинка, colorSpace: цвета,
                                                          options: [ключКачества: Self.качество]) else { return nil }
        let адрес = "data:image/jpeg;base64," + данные.base64EncodedString()
        return адрес.count > 120 ? адрес : nil
    }

    /// Vision без сети: из меток увереннее 0,3 — первая (по уверенности), что по словарю совпала с разделом сайта.
    private func разделVision(_ буфер: CVPixelBuffer) -> String? {
        let запрос = VNClassifyImageRequest()
        let обработчик = VNImageRequestHandler(cvPixelBuffer: буфер, orientation: ориентация, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return nil
        }
        let уверенные = (запрос.results ?? [])
            .filter { $0.confidence > 0.3 }
            .sorted { $0.confidence > $1.confidence }
        for метка in уверенные.prefix(5) {
            if let ключ = СловарьЖивогоПоиска.раздел(метка.identifier) { return ключ }
        }
        return nil
    }
}

// MARK: - Словарь меток Vision → раздел сайта

/// Метки VNClassifyImageRequest («golden_retriever», «computer_keyboard») → ключ раздела сайта (дерево MK_CATS).
/// Сначала вся метка, потом её слова с конца (главное слово английской метки — последнее). Нет в словаре — nil.
enum СловарьЖивогоПоиска {
    static func раздел(_ метка: String) -> String? {
        let м = метка.lowercased()
        if мимо.contains(м) { return nil }
        if let ключ = целые[м] { return ключ }
        for слово in м.split(separator: "_").reversed() {
            if let ключ = слова[String(слово)] { return ключ }
        }
        return nil
    }

    /// Название раздела на языке приложения: справочник сайта, иначе имя корня из текстов страницы объявления.
    @MainActor
    static func имя(_ ключ: String) -> String? {
        if let имя = ЗагрузкаКаталогаПоиска.имя(ключ) { return имя }
        let корень = РазделыСайта.корень(ключ)
        let имяКорня = ListingPageText.т("root_" + корень)
        return имяКорня == "root_" + корень ? nil : имяКорня
    }

    /// Метки, чьё слово обманет словарь (хот-дог — не собака).
    private static let мимо: Set<String> = ["hot_dog", "sea_lion", "dog_house", "doghouse", "horse_cart", "bus_stop",
                                            "car_park", "parking_lot", "train_car", "cable_car"]

    /// Составные метки, которые по словам легли бы не туда.
    private static let целые: [String: String] = [
        "computer_keyboard": "keyboards-mice", "computer_mouse": "keyboards-mice", "musical_keyboard": "keyboards-piano",
        "computer_monitor": "monitors", "game_controller": "gamepads", "video_game": "video-games",
        "smart_watch": "smartwatches", "car_seat": "car-seats", "toy_car": "toys", "teddy_bear": "toys",
        "rubber_duck": "toys", "stuffed_animal": "toys", "rocking_horse": "toys", "guinea_pig": "rodents-guinea",
        "washing_machine": "washing-machines", "sewing_machine": "handmade", "coffee_maker": "kettles-coffee",
        "air_conditioner": "air-conditioners", "vacuum_cleaner": "vacuum-cleaners", "hair_dryer": "beauty-hairdryers",
        "nail_polish": "nails-polish", "lawn_mower": "lawn-mowers", "steering_wheel": "auto-accessories",
        "jet_ski": "jet-skis", "ice_skate": "ice-skates", "roller_skate": "sport", "table_tennis": "racket-sports",
        "pool_table": "sport", "tennis_racket": "racket-sports", "soccer_ball": "football-gear",
        "fishing_rod": "fishing-rods", "sleeping_bag": "sleeping-bags", "yoga_mat": "yoga-mats",
        "baby_bottle": "baby-feeding", "baby_carriage": "strollers", "high_chair": "highchairs",
        "potted_plant": "plants", "light_bulb": "lighting", "picture_frame": "decor-items",
        "apartment_building": "apartments", "board_game": "board-games", "teapot": "tableware"
    ]

    /// Отдельные слова меток.
    private static let слова: [String: String] = [
        /* электроника */
        "laptop": "laptops", "computer": "computers", "desktop": "desktops", "monitor": "monitors",
        "keyboard": "keyboards-mice", "printer": "printers", "router": "networking", "television": "tv", "tv": "tv",
        "smartphone": "smartphones", "cellphone": "smartphones", "phone": "smartphones", "telephone": "smartphones",
        "iphone": "smartphones", "tablet": "tablets", "ipad": "tablets", "smartwatch": "smartwatches",
        "headphones": "headphones", "headphone": "headphones", "earphones": "headphones", "earbuds": "headphones",
        "headset": "headphones", "speaker": "speakers", "loudspeaker": "speakers", "projector": "projectors",
        "radio": "tv-audio", "camera": "cameras", "camcorder": "camcorders", "lens": "lenses", "drone": "drones",
        "tripod": "tripods", "console": "consoles", "gamepad": "gamepads", "joystick": "gamepads",
        "microphone": "studio-gear",
        /* транспорт */
        "car": "cars", "automobile": "cars", "sedan": "cars", "suv": "cars", "jeep": "cars", "convertible": "cars",
        "coupe": "cars", "hatchback": "cars", "minivan": "cars", "motorcycle": "motorcycles", "motorbike": "motorcycles",
        "scooter": "scooters", "moped": "scooters", "atv": "atvs", "truck": "trucks", "lorry": "trucks", "bus": "buses",
        "tractor": "agricultural", "excavator": "construction-equip", "bulldozer": "construction-equip",
        "forklift": "forklifts", "boat": "boats", "yacht": "boats", "kayak": "boats", "canoe": "boats",
        "motorboat": "boats", "tire": "tires-wheels", "tyre": "tires-wheels", "wheel": "tires-wheels",
        /* недвижимость */
        "house": "houses", "cottage": "houses", "villa": "houses", "apartment": "apartments",
        "garage": "garages-parking",
        /* одежда, обувь, аксессуары */
        "dress": "womens-dresses", "shirt": "clothing", "tshirt": "clothing", "blouse": "clothing",
        "sweater": "clothing", "hoodie": "clothing", "jacket": "clothing", "coat": "clothing", "jeans": "clothing",
        "pants": "clothing", "trousers": "clothing", "shorts": "clothing", "skirt": "clothing", "suit": "mens-suits",
        "clothing": "clothing", "shoe": "shoes", "shoes": "shoes", "sneaker": "shoes", "sneakers": "shoes",
        "boot": "shoes", "boots": "shoes", "sandal": "shoes", "sandals": "shoes", "footwear": "shoes",
        "heels": "shoes", "handbag": "handbags", "purse": "handbags", "bag": "handbags", "backpack": "backpacks",
        "wallet": "wallets", "suitcase": "bags-accessories", "luggage": "bags-accessories",
        "umbrella": "bags-accessories", "hat": "hats", "cap": "hats", "beanie": "hats", "scarf": "belts-scarves",
        "belt": "belts-scarves", "necktie": "belts-scarves", "sunglasses": "sunglasses",
        "eyeglasses": "optics-glasses", "jewelry": "jewelry", "jewellery": "jewelry", "necklace": "necklaces",
        "bracelet": "bracelets", "earring": "earrings", "earrings": "earrings", "watch": "watches",
        "wristwatch": "watches",
        /* дом и сад */
        "sofa": "sofas", "couch": "sofas", "bed": "beds", "table": "tables", "desk": "tables", "chair": "furniture",
        "armchair": "furniture", "stool": "furniture", "furniture": "furniture", "wardrobe": "wardrobes",
        "closet": "wardrobes", "cabinet": "wardrobes", "dresser": "wardrobes", "cupboard": "wardrobes",
        "bookcase": "furniture", "bookshelf": "furniture", "refrigerator": "fridges", "fridge": "fridges",
        "dishwasher": "dishwashers", "stove": "stoves", "oven": "stoves", "cooktop": "stoves",
        "microwave": "microwaves", "kettle": "kettles-coffee", "toaster": "small-appliances",
        "blender": "small-appliances", "appliance": "appliances", "pan": "cookware", "saucepan": "cookware",
        "cookware": "cookware", "plate": "tableware", "bowl": "tableware", "cup": "tableware", "mug": "tableware",
        "dishware": "tableware", "tableware": "tableware", "fork": "cutlery", "spoon": "cutlery", "knife": "cutlery",
        "cutlery": "cutlery", "lamp": "lamps", "chandelier": "chandeliers", "carpet": "carpets", "rug": "carpets",
        "curtain": "curtains", "curtains": "curtains", "pillow": "bedding", "blanket": "bedding", "quilt": "bedding",
        "bedding": "bedding", "vase": "decor-items", "candle": "decor-items", "clock": "decor-items",
        "houseplant": "plants", "plant": "plants", "drill": "power-tools", "chainsaw": "power-tools",
        "hammer": "tools", "screwdriver": "tools", "wrench": "tools", "pliers": "tools", "saw": "tools",
        "toolbox": "tools", "tool": "tools", "door": "windows-doors", "faucet": "plumbing", "sink": "plumbing",
        "toilet": "plumbing", "bathtub": "plumbing",
        /* детям */
        "toy": "toys", "toys": "toys", "doll": "dolls-figures", "lego": "lego-constructors", "plush": "toys",
        "stroller": "strollers", "pram": "strollers", "crib": "cribs", "cradle": "cribs", "diaper": "baby-diapers",
        "pacifier": "baby-feeding", "playground": "kids-playgrounds",
        /* спорт */
        "bicycle": "bicycles", "bike": "bicycles", "dumbbell": "weights-barbells", "barbell": "weights-barbells",
        "kettlebell": "weights-barbells", "treadmill": "treadmills", "ski": "skis", "skis": "skis",
        "snowboard": "snowboards", "skates": "ice-skates", "surfboard": "surfing", "tent": "tents",
        "football": "football-gear", "basketball": "basketball-gear", "volleyball": "volleyball-gear",
        "racket": "racket-sports", "skateboard": "sport",
        /* животные */
        "dog": "dogs", "puppy": "dogs", "canine": "dogs", "retriever": "dogs", "labrador": "dogs", "husky": "dogs",
        "terrier": "dogs", "poodle": "dogs", "bulldog": "dogs", "shepherd": "dogs", "spaniel": "dogs",
        "beagle": "dogs", "chihuahua": "dogs", "dachshund": "dogs", "pug": "dogs", "corgi": "dogs", "collie": "dogs",
        "rottweiler": "dogs", "doberman": "dogs", "malamute": "dogs", "sheepdog": "dogs", "samoyed": "dogs",
        "cat": "cats", "kitten": "cats", "feline": "cats", "tabby": "cats", "siamese": "cats", "bird": "birds",
        "parrot": "parrots", "budgerigar": "parrots", "parakeet": "parrots", "cockatoo": "parrots",
        "cockatiel": "parrots", "macaw": "parrots", "canary": "canaries", "pigeon": "pigeons", "dove": "pigeons",
        "fish": "fish", "goldfish": "fish", "aquarium": "aquariums", "hamster": "rodents-hamsters",
        "rabbit": "rodents-rabbits", "bunny": "rodents-rabbits", "rodent": "rodents", "turtle": "reptiles-turtles",
        "tortoise": "reptiles-turtles", "lizard": "reptiles-lizards", "gecko": "reptiles-lizards",
        "iguana": "reptiles-lizards", "chameleon": "reptiles-lizards", "snake": "reptiles-snakes",
        "reptile": "reptiles", "horse": "horses", "pony": "horses", "foal": "horses", "cow": "cattle",
        "cattle": "cattle", "bull": "cattle", "calf": "cattle", "sheep": "sheep-goats", "goat": "sheep-goats",
        "lamb": "sheep-goats", "camel": "camels", "pig": "pigs", "piglet": "pigs", "chicken": "poultry-chickens",
        "hen": "poultry-chickens", "rooster": "poultry-chickens", "duck": "poultry-ducks-geese",
        "goose": "poultry-ducks-geese", "turkey": "poultry-turkeys", "quail": "poultry-quails",
        /* хобби */
        "guitar": "guitars", "piano": "keyboards-piano", "synthesizer": "keyboards-piano", "drum": "drums",
        "drums": "drums", "violin": "musical-instruments", "cello": "musical-instruments",
        "accordion": "musical-instruments", "ukulele": "musical-instruments", "harp": "musical-instruments",
        "saxophone": "wind-instruments", "trumpet": "wind-instruments", "flute": "wind-instruments",
        "clarinet": "wind-instruments", "trombone": "wind-instruments", "book": "books", "books": "books",
        "magazine": "books", "comic": "comics-manga", "coin": "coins", "coins": "coins", "chess": "chess",
        "chessboard": "chess", "puzzle": "puzzles", "jigsaw": "puzzles", "easel": "art-easels",
        "paintbrush": "art-paints", "yarn": "knitting",
        /* продукты */
        "fruit": "fruits-vegetables", "vegetable": "fruits-vegetables", "apple": "fruits-vegetables",
        "banana": "fruits-vegetables", "tomato": "fruits-vegetables", "potato": "fruits-vegetables",
        "cucumber": "fruits-vegetables", "watermelon": "fruits-vegetables", "melon": "fruits-vegetables",
        "honey": "honey", "egg": "eggs", "eggs": "eggs", "cheese": "dairy", "bread": "grocery-bakery",
        /* красота */
        "perfume": "beauty-perfume", "fragrance": "beauty-perfume", "lipstick": "makeup-lips",
        "cosmetics": "beauty-makeup", "makeup": "beauty-makeup", "hairdryer": "beauty-hairdryers",
        "shampoo": "hair-shampoo"
    ]
}

// MARK: - Лимит живых отправок

/// Сколько кадров живой поиск сам отправил на сайт за последний час (на телефоне). Сайт пускает 20 поисков по фото
/// в час на человека — живому из них 12, остальные остаются кнопке «Снять» и галерее.
enum БюджетЖивогоПоиска {
    static let вЧас = 12
    private static let ключ = "kliko.photosearch.live.sent"

    static var можно: Bool { свежие().count < вЧас }

    static func отметить() {
        var список = свежие()
        список.append(Date().timeIntervalSince1970)
        UserDefaults.standard.set(список, forKey: ключ)
    }

    private static func свежие() -> [Double] {
        let порог = Date().timeIntervalSince1970 - 3600
        let все = UserDefaults.standard.array(forKey: ключ) as? [Double] ?? []
        return все.filter { $0 > порог }
    }
}

// MARK: - Модель

/// Живой поиск окна поиска по фото: кадры → сайт → полоса похожих; подсказка Vision; сон камеры. Живёт, пока открыто
/// окно (@StateObject ОкноПоискаПоФото), и ни к каким общим объектам при создании не обращается.
@MainActor
final class ЖивойПоискКамеры: ObservableObject {
    /// Похожие объявления для полосы.
    @Published private(set) var товары: [Listing] = []
    /// Что распознал Kliko AI в последний раз.
    @Published private(set) var запрос = ""
    /// Название раздела по подсказке Vision — «Похоже на: …»; nil — подписи нет.
    @Published private(set) var похоже: String? = nil
    @Published private(set) var ищем = false
    /// Минуту без движения — камера спит, на экране «Продолжить».
    @Published private(set) var спит = false
    /// Живой поиск сам больше не шлёт: час исчерпан или сайт отказал; текст — человеку.
    @Published private(set) var стоп: String? = nil
    /// Номер выдачи: новая — полоса плавно сменяется и начинается сначала.
    @Published private(set) var выдача = 0

    private(set) lazy var анализ: АнализКадровПоиска = АнализКадровПоиска(наГлавную: { [weak self] событие in
        self?.принять(событие)
    })
    private weak var камера: КамераПоиска? = nil
    private weak var поиск: ПоискПоФотоСайта? = nil
    private var задача: Task<Void, Never>? = nil
    private var поколение = 0
    private var включён = false
    /// «запрос|раздел» последнего ответа сайта: тот же ответ — выдачу заново не грузим.
    private var распознано = ""

    init() {}

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    /// Режим «Навести камеру» на экране: кадры камеры — анализу; отправка не чаще раза в 1,5 с, в лёгком — раз в 3 с.
    func включить(камера: КамераПоиска, поиск: ПоискПоФотоСайта) {
        self.камера = камера
        self.поиск = поиск
        включён = true
        спит = false
        if стоп == nil && !БюджетЖивогоПоиска.можно { стоп = т("ps_live_limit") }
        let интервал: CFTimeInterval = РежимУстройства.shared.лёгкий ? 3 : 1.5
        анализ.включить(интервал: интервал, можноОтправлять: стоп == nil)
        камера.живыеКадры(анализ, очередь: анализ.очередь)
    }

    /// Ушли с экрана или в фон: анализ стоит, запрос на сайт отменён; выход кадров и найденное остаются.
    func приостановить() {
        включён = false
        анализ.выключить()
        отменитьЗапрос()
    }

    /// Переключили на «Выбрать фото»: выход кадров снят, сессия снова для снимка; сон — забыт.
    func выключить() {
        приостановить()
        спит = false
        камера?.живыеКадры(nil, очередь: nil)
    }

    /// «Продолжить» после сна: анализ и камера снова.
    func проснуться() {
        guard let камера, let поиск else { return }
        включить(камера: камера, поиск: поиск)
        камера.запустить()
    }

    /// Человек листает полосу — это тоже движение: сон откладывается.
    func тронули() {
        guard включён else { return }
        анализ.отметитьДвижение()
    }

    /// Сняли затвором — к прежнему полному поиску; вернутся — полоса с чистого листа.
    func забыть() {
        отменитьЗапрос()
        анализ.забыть()
        распознано = ""
        запрос = ""
        похоже = nil
        товары = []
    }

    private func отменитьЗапрос() {
        поколение += 1
        задача?.cancel()
        задача = nil
        ищем = false
    }

    private func принять(_ событие: СобытиеЖивогоКадра) {
        guard включён else { return }
        switch событие {
        case .раздел(let ключ):
            let имя = ключ.flatMap { СловарьЖивогоПоиска.имя($0) }
            if имя != похоже {
                withAnimation(ДвижениеСайта.смена) { похоже = имя }
            }
        case .кадр(let адрес):
            отправить(адрес)
        case .покой:
            уснуть()
        }
    }

    private func уснуть() {
        включён = false
        отменитьЗапрос()
        withAnimation(ДвижениеСайта.смена) { спит = true }
        камера?.остановить()
    }

    private func остановитьОтправку(_ текст: String) {
        анализ.разрешитьОтправку(false)
        withAnimation(ДвижениеСайта.смена) { стоп = текст }
    }

    /// «Не удалось распознать фото» — обычное дело для случайного кадра, это не повод останавливаться.
    private func нераспознано(_ текст: String) -> Bool {
        текст == т("ps_fail") || текст.hasPrefix("Не удалось распознать")
    }

    /// Кадр — в тот же поиск по фото сайта, что у снимка; прежний запрос отменяется.
    private func отправить(_ адрес: String) {
        guard стоп == nil else { return }
        guard БюджетЖивогоПоиска.можно else {
            остановитьОтправку(т("ps_live_limit"))
            return
        }
        БюджетЖивогоПоиска.отметить()
        поколение += 1
        let номер = поколение
        задача?.cancel()
        ищем = true
        задача = Task { @MainActor [weak self] in
            let ответ = await ПоискПоФотоAPI.отправить(адрес)
            guard let self, номер == self.поколение, !Task.isCancelled else { return }
            switch ответ {
            case .найдено(let найдено, let ключ):
                if найдено + "|" + ключ == self.распознано {
                    self.ищем = false
                    return
                }
                await self.найтиПохожие(найдено, ключ, номер)
            case .нуженВход:
                self.приостановить()
                self.поиск?.входДляЖивого()
            case .отказ(let текст):
                self.ищем = false
                /* Отказы кроме «не распознал» (часто, ИИ недоступен, лимит) — сам больше не шлёт, «Снять» работает. */
                if !self.нераспознано(текст) { self.остановитьОтправку(текст) }
            case .сеть:
                self.ищем = false
            }
        }
    }

    /// Объявления по распознанному — как у снимка (api/listings.php); в разделе пусто — ещё раз без раздела.
    private func найтиПохожие(_ найдено: String, _ ключ: String, _ номер: Int) async {
        var з = ListingsAPI.Запрос()
        з.per = 12
        з.q = найдено
        з.cat = ключ
        do {
            var страница = try await ListingsAPI.загрузить(з).страница
            guard номер == поколение, !Task.isCancelled else { return }
            if страница.items.isEmpty && !з.cat.isEmpty {
                з.cat = ""
                let шире = try await ListingsAPI.загрузить(з).страница
                guard номер == поколение, !Task.isCancelled else { return }
                if !шире.items.isEmpty { страница = шире }
            }
            /* ТОП по кругу приходит дважды — два одинаковых id ломают ForEach полосы; оставляем первое. */
            var были = Set<String>()
            let новые = страница.items.filter { были.insert($0.id).inserted }
            let новыйЗапрос = найдено != запрос
            распознано = найдено + "|" + ключ
            ищем = false
            withAnimation(ДвижениеСайта.смена) {
                запрос = найдено
                товары = новые
                выдача += 1
            }
            if новыйЗапрос {
                let всего = страница.total ?? новые.count
                let объявление = новые.isEmpty ? т("ps_empty") : String(format: т("ps_count"), всего)
                UIAccessibility.post(notification: .announcement, argument: объявление)
            }
        } catch {
            guard номер == поколение, !Task.isCancelled else { return }
            ищем = false
        }
    }
}

// MARK: - Вид

/// «Навести камеру» / «Выбрать фото» — капсула над затвором; выбор запоминается (ЭкранКамерыПоиска).
struct ПереключательРежимаКамеры: View {
    @Binding var живой: Bool
    @Namespace private var пилюля

    init(живой: Binding<Bool>) {
        self._живой = живой
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        HStack(spacing: 4) {
            вариант(т("ps_mode_live"), значок: "viewfinder", выбран: живой) { живой = true }
            вариант(т("ps_mode_photo"), значок: "camera", выбран: !живой) { живой = false }
        }
        .padding(4)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(т("ps_mode"))
    }

    private func вариант(_ заголовок: String, значок: String, выбран: Bool,
                         _ действие: @escaping () -> Void) -> some View {
        Button {
            guard !выбран else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(ДвижениеСайта.выбор) { действие() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.footnote.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(выбран ? Color.black : Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background {
                if выбран {
                    Capsule()
                        .fill(Color.white)
                        .matchedGeometryEffect(id: "выбор", in: пилюля)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// «Похоже на: Ноутбуки» сверху — подсказка Vision без сети.
struct ПодписьЖивогоПоиска: View {
    let имя: String

    init(имя: String) {
        self.имя = имя
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .accessibilityHidden(true)
            Text(String(format: ПоискСайтаText.т("ps_live_like"), имя))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Снизу над затвором: строка состояния (подсказка, «Ищем похожие…», «Kliko AI: …», лимит) и мини-карточки похожих.
struct ПолосаЖивогоПоиска: View {
    @ObservedObject var живой: ЖивойПоискКамеры
    /// Первая видимая карточка: листают полосу — человек здесь, камера не засыпает, даже если телефон неподвижен.
    @State private var видимая: String? = nil

    init(живой: ЖивойПоискКамеры) {
        self.живой = живой
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            состояние
                .padding(.horizontal, 16)
            if !живой.товары.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) {
                        ForEach(живой.товары) { товар in
                            NavigationLink(value: товар) { КарточкаНедавнегоСайта(товар: товар) }
                                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollPosition(id: $видимая)
                .id(живой.выдача)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(т("ps_live_strip"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: видимая) { _, новая in
            if новая != nil { живой.тронули() }
        }
        .onChange(of: живой.выдача) { _, _ in
            видимая = nil
        }
    }

    private var текст: String {
        if let стоп = живой.стоп { return стоп }
        if живой.ищем { return т("ps_searching") }
        if !живой.товары.isEmpty { return String(format: т("ps_ai_saw"), живой.запрос) }
        if !живой.запрос.isEmpty { return т("ps_empty") }
        return т("ps_live_hint")
    }

    private var состояние: some View {
        HStack(spacing: 8) {
            if живой.ищем {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.зелёныйЯркий)
            } else {
                Image(systemName: живой.стоп == nil ? "sparkles" : "pause.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .animation(ДвижениеСайта.смена, value: текст)
        .accessibilityElement(children: .combine)
    }
}

/// Камера уснула (минуту без движения): объяснение и «Продолжить».
struct ПаузаЖивогоПоиска: View {
    let продолжить: () -> Void

    init(продолжить: @escaping () -> Void) {
        self.продолжить = продолжить
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .frame(width: 72, height: 72)
                .background(Color.white.opacity(0.1), in: Circle())
                .padding(.bottom, 16)
                .accessibilityHidden(true)
            Text(т("ps_live_sleep"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
            Text(т("ps_live_sleep_hint"))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)
            ЗелёнаяКнопкаФото(заголовок: т("ps_live_resume"), значок: "play.fill", действие: продолжить)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
