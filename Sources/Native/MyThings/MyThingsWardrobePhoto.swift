import SwiftUI
import UIKit
import PhotosUI
import Vision

/**
 «МОЙ ГАРДЕРОБ» — ФОТО ВЕЩИ НА ТЕЛЕФОНЕ (пачка 16.10.2026 «мой дом, компьютер, гардероб и для вас»; владелец: «так же и
 гардероб вещей»; «стандарты = удобство: не пустые поля, а выбор по стандартам, шаблоны, камера»).

 Снимок — только по нажатию (камера или системный выбор фото), обработка — без главной нити (Task.detached), без сети:
   · подготовка — тем же путём, что у всего «Моего» (ОбработкаФотоМоего.подготовить): поворот из EXIF учтён, EXIF и
     место съёмки в файл не уходят;
   · вырезка фона — движок студии подачи и примерочной (ВырезкаПредмета.вырезать, Vision
     VNGenerateForegroundInstanceMaskRequest, iOS 17.0): вещь обрезана по себе, вокруг прозрачно; PNG до 1024 px и
     миниатюра 400 px (в оба поля ГотовоеФотоМоего — PNG, расширение «png»). Не вырезалось (вещь — почти весь кадр,
     маски нет) — обычный JPEG, как у комнаты;
   · цвет сам — пиксели вырезки (без фона) к ближайшему из 16 цветов каталога (ЦветСтандарта.ближайший): первый —
     самый заметный, второй — если его не меньше трети и это не тень того же цвета; без вырезки — середина кадра;
   · вид по фото — метки Vision (VNClassifyImageRequest) словарём ниже: только подсказка «похоже на», человек
     подтверждает чипом.
 Файлы пишет хранилище (МоёХранилище.сохранитьФото, место .вещьГардероба или .образ): сначала вещь в записи, потом фото.
 */

/// Снимок вещи после обработки: готовое к записи фото, его расширение, цвета и вид по фото.
struct СнимокВещиГардероба: @unchecked Sendable {
    let готовое: ГотовоеФотоМоего
    /// «png» — вырезка с прозрачным фоном, «jpg» — снимок как есть.
    let расширение: String
    let вырезано: Bool
    let цвета: [ЦветСтандарта]
    let вид: ВидВещиГардеробаМоего?
    /// Для экрана сразу, без чтения файла.
    let картинка: UIImage
}

enum ОбработкаВещиГардероба {
    /// Длинная сторона рабочего кадра вырезки и файла PNG, px.
    static let сторона: CGFloat = 1024
    static let сторонаМини: CGFloat = 400

    /// Источник → вырезка, цвета, вид. nil — фото не открылось или задачу отменили.
    static func обработать(_ источник: ИсточникСнимкаМоего) -> СнимокВещиГардероба? {
        let готовое: ГотовоеФотоМоего?
        switch источник {
        case .кадр(let кадр): готовое = ОбработкаФотоМоего.подготовить(кадр)
        case .файл(let данные): готовое = ОбработкаФотоМоего.подготовить(данные)
        }
        guard let готовое, !Task.isCancelled, let прямое = UIImage(data: готовое.jpeg)?.cgImage,
              let рабочий = уменьшить(прямое, сторона: сторона) else { return nil }
        let похоже = видПоФото(рабочий)
        guard !Task.isCancelled else { return nil }
        if let вырез = ВырезкаПредмета.вырезать(рабочий, поле: 0.04), !Task.isCancelled,
           let png = вPNG(вырез, сторона: сторона), let мини = вPNG(вырез, сторона: сторонаМини) {
            let найденные = цветаВырезки(вырез)
            let фото = ГотовоеФотоМоего(jpeg: png, мини: мини, ширина: вырез.width, высота: вырез.height)
            return СнимокВещиГардероба(готовое: фото, расширение: "png", вырезано: true, цвета: найденные,
                                       вид: похоже, картинка: UIImage(cgImage: вырез))
        }
        guard !Task.isCancelled, let картинка = UIImage(data: готовое.jpeg) else { return nil }
        return СнимокВещиГардероба(готовое: готовое, расширение: "jpg", вырезано: false,
                                   цвета: цветаСередины(рабочий), вид: похоже, картинка: картинка)
    }

    // MARK: Размеры и PNG

    /// Кадр не длиннее стороны (RGBA, sRGB); меньше — как есть.
    static func уменьшить(_ кадр: CGImage, сторона: CGFloat) -> CGImage? {
        let w = CGFloat(кадр.width)
        let h = CGFloat(кадр.height)
        let k = min(1, сторона / max(w, h))
        guard k < 1 else { return кадр }
        let ширина = max(1, Int((w * k).rounded()))
        let высота = max(1, Int((h * k).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let холст = CGContext(data: nil, width: ширина, height: высота, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: пространство, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        холст.interpolationQuality = .high
        холст.draw(кадр, in: CGRect(x: 0, y: 0, width: ширина, height: высота))
        return холст.makeImage()
    }

    /// PNG с прозрачностью не длиннее стороны.
    private static func вPNG(_ кадр: CGImage, сторона: CGFloat) -> Data? {
        guard let малый = уменьшить(кадр, сторона: сторона) else { return nil }
        let размер = CGSize(width: малый.width, height: малый.height)
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = false
        let картинка = UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
            UIImage(cgImage: малый).draw(in: CGRect(origin: .zero, size: размер))
        }
        return картинка.pngData()
    }

    // MARK: Цвет сам

    /// Цвета вырезки: только пиксели вещи (непрозрачные).
    static func цветаВырезки(_ кадр: CGImage) -> [ЦветСтандарта] {
        цвета(кадр, область: CGRect(x: 0, y: 0, width: 1, height: 1), порогПервого: 0)
    }

    /// Без вырезки — середина кадра (половина по ширине и высоте); первый цвет — если его не меньше трети.
    static func цветаСередины(_ кадр: CGImage) -> [ЦветСтандарта] {
        цвета(кадр, область: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5), порогПервого: 0.34)
    }

    /// Тени одного цвета на ткани — не второй цвет.
    private static let тени: Set<String> = ["grey|white", "black|grey", "grey|silver", "beige|white", "beige|brown"]

    /**
     Пиксели области (доли кадра) в квадрате 40 × 40 → ближайший цвет каталога у каждого непрозрачного; доли по счёту.
     Второй — от трети и не тень первого. Три заметных ярких (каждый от 18 %) и ни один не главный — «разноцветный».
     */
    private static func цвета(_ кадр: CGImage, область: CGRect, порогПервого: Double) -> [ЦветСтандарта] {
        let сторона = 40
        let кусок = CGRect(x: CGFloat(кадр.width) * область.minX, y: CGFloat(кадр.height) * область.minY,
                           width: CGFloat(кадр.width) * область.width, height: CGFloat(кадр.height) * область.height)
            .integral
        guard let часть = кадр.cropping(to: кусок), let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let холст = CGContext(data: nil, width: сторона, height: сторона, bitsPerComponent: 8,
                                    bytesPerRow: сторона * 4, space: пространство,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        холст.interpolationQuality = .medium
        холст.draw(часть, in: CGRect(x: 0, y: 0, width: сторона, height: сторона))
        guard let сырые = холст.data else { return [] }
        let байты = сырые.bindMemory(to: UInt8.self, capacity: сторона * сторона * 4)
        var счёт: [ЦветСтандарта: Int] = [:]
        var всего = 0
        for i in stride(from: 0, to: сторона * сторона * 4, by: 4) {
            let альфа = Double(байты[i + 3]) / 255
            guard альфа > 0.7 else { continue }
            let цвет = ЦветСтандарта.ближайший(красный: Double(байты[i]) / 255 / альфа,
                                               зелёный: Double(байты[i + 1]) / 255 / альфа,
                                               синий: Double(байты[i + 2]) / 255 / альфа)
            счёт[цвет, default: 0] += 1
            всего += 1
        }
        guard всего >= 40 else { return [] }
        let порядок = счёт.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
        guard let первый = порядок.first else { return [] }
        let доляПервого = Double(первый.value) / Double(всего)
        guard доляПервого >= порогПервого else { return [] }
        let яркие = порядок.filter { !$0.key.нейтральный && Double($0.value) / Double(всего) >= 0.18 }
        if яркие.count >= 3 && доляПервого < 0.4 { return [.разноцветный] }
        var итог = [первый.key]
        if порядок.count > 1 {
            let второй = порядок[1]
            let ключ = [первый.key.rawValue, второй.key.rawValue].sorted().joined(separator: "|")
            if Double(второй.value) / Double(всего) >= 0.33, !тени.contains(ключ) { итог.append(второй.key) }
        }
        return итог
    }

    // MARK: Вид по фото

    /// Слово метки Vision → вид вещи. Метка — «running_shoe», «t_shirt»: сначала целиком, потом слова с конца.
    private static let целые: [String: ВидВещиГардеробаМоего] = [
        "t_shirt": .футболка, "tshirt": .футболка, "jersey": .футболка, "polo_shirt": .футболка,
        "running_shoe": .кроссовки, "sweatshirt": .худи, "fur_coat": .пальто, "trench_coat": .пальто,
        "evening_dress": .платье, "cowboy_hat": .шапка, "baseball_cap": .шапка
    ]

    private static let слова: [String: ВидВещиГардеробаМоего] = [
        "jeans": .джинсы, "denim": .джинсы, "dress": .платье, "gown": .платье, "skirt": .юбка, "miniskirt": .юбка,
        "shorts": .шорты, "trousers": .брюки, "pants": .брюки, "slacks": .брюки, "shirt": .рубашка, "blouse": .рубашка,
        "sweater": .свитер, "cardigan": .свитер, "pullover": .свитер, "jumper": .свитер, "hoodie": .худи,
        "blazer": .пиджак, "jacket": .куртка, "parka": .куртка, "windbreaker": .куртка, "coat": .пальто,
        "overcoat": .пальто, "raincoat": .пальто, "suit": .костюм, "tracksuit": .спорт, "sneaker": .кроссовки,
        "sneakers": .кроссовки, "boot": .ботинки, "boots": .ботинки, "shoe": .обувь, "shoes": .обувь,
        "footwear": .обувь, "sandal": .обувь, "sandals": .обувь, "heels": .обувь, "loafer": .обувь,
        "handbag": .сумка, "purse": .сумка, "bag": .сумка, "backpack": .сумка, "clutch": .сумка, "tote": .сумка,
        "hat": .шапка, "cap": .шапка, "beanie": .шапка, "headwear": .шапка, "scarf": .шарф, "sunglasses": .аксессуар,
        "eyeglasses": .аксессуар, "belt": .аксессуар, "necktie": .аксессуар, "watch": .аксессуар,
        "wristwatch": .аксессуар, "glove": .аксессуар, "gloves": .аксессуар
    ]

    /// Метка Vision → вид; незнакомая — nil.
    static func вид(метки метка: String) -> ВидВещиГардеробаМоего? {
        let м = метка.lowercased()
        if let целый = целые[м] { return целый }
        for слово in м.split(separator: "_").reversed() {
            if let поСлову = слова[String(слово)] { return поСлову }
        }
        return nil
    }

    /// Самая уверенная метка, которая по словарю — вещь гардероба (уверенность больше 0,25). Не нашлось — nil.
    static func видПоФото(_ кадр: CGImage) -> ВидВещиГардеробаМоего? {
        let запрос = VNClassifyImageRequest()
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return nil
        }
        let уверенные = (запрос.results ?? []).filter { $0.confidence > 0.25 }.sorted { $0.confidence > $1.confidence }
        for метка in уверенные.prefix(8) {
            if let найден = Self.вид(метки: метка.identifier) { return найден }
        }
        return nil
    }
}

// MARK: - Снимок по нажатию

/**
 Камера (системная, КамераПодачи) и системный выбор фото по флагам. Кадр камеры отдаётся, когда её окно уже уехало
 (onDismiss), — следующее окно (лист вещи) встаёт без спора двух окон; файл галереи — после короткой паузы по той же
 причине. Отдаётся на главной нити.
 */
struct ВыборСнимкаГардероба: ViewModifier {
    @Binding var камера: Bool
    @Binding var галерея: Bool
    let получено: (ИсточникСнимкаМоего) -> Void
    @State private var выбор: PhotosPickerItem? = nil
    @State private var снятый: UIImage? = nil

    init(камера: Binding<Bool>, галерея: Binding<Bool>, получено: @escaping (ИсточникСнимкаМоего) -> Void) {
        _камера = камера
        _галерея = галерея
        self.получено = получено
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $камера, onDismiss: отдатьКадр) {
                КамераПодачи(снято: { снимок in снятый = снимок }, закрыть: { камера = false })
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $галерея, selection: $выбор, matching: .images)
            .onChange(of: выбор) { _, новый in
                guard let новый else { return }
                выбор = nil
                Task { @MainActor in
                    guard let данные = try? await новый.loadTransferable(type: Data.self) else {
                        ОткликСайта.предупреждение()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    получено(.файл(данные))
                }
            }
    }

    private func отдатьКадр() {
        guard let кадр = снятый else { return }
        снятый = nil
        получено(.кадр(кадр))
    }
}

extension View {
    /// Снимок по нажатию для «Моего гардероба»: камера или системный выбор фото.
    func выборСнимкаГардероба(камера: Binding<Bool>, галерея: Binding<Bool>,
                              получено: @escaping (ИсточникСнимкаМоего) -> Void) -> some View {
        modifier(ВыборСнимкаГардероба(камера: камера, галерея: галерея, получено: получено))
    }
}

// MARK: - Картинка вещи

/**
 Картинка вещи для сетки, образа и листа: своё фото (вырезка — целиком на мягкой подложке её цвета, снимок — на всё
 поле), иначе обложка купленного на Kliko, иначе значок вида на подложке цвета вещи. мини — миниатюра (сетка, доска).
 */
struct КартинкаВещиГардероба: View {
    let вещь: ВещьГардеробаМоего
    var мини: Bool
    var поля: CGFloat

    init(вещь: ВещьГардеробаМоего, мини: Bool = true, поля: CGFloat = 10) {
        self.вещь = вещь
        self.мини = мини
        self.поля = поля
    }

    private var вырезка: Bool { вещь.фото?.файл.hasSuffix(".png") ?? false }

    var body: some View {
        ZStack {
            подложка
            if let фото = вещь.фото {
                ФотоМоегоВид(имя: мини ? фото.мини : фото.файл, заполнить: !вырезка)
                    .padding(вырезка ? поля : 0)
            } else if let адрес = вещь.адресФото, let url = Config.url(адрес) {
                КартинкаЛенты(url, пунктов: мини ? 180 : 360) {
                    значок
                }
            } else {
                значок
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var подложка: some View {
        let цвет = вещь.цвета.first
        return ZStack {
            Theme.поверхность2
            if let цвет, цвет != .разноцветный {
                цвет.краска.opacity(цвет.светлый ? 0.22 : 0.12)
            }
        }
    }

    private var значок: some View {
        Image(systemName: вещь.вид.значок)
            .font(.system(size: мини ? 30 : 48, weight: .semibold))
            .foregroundStyle(вещь.цвета.first.map { $0 == .разноцветный || $0.светлый ? Theme.текстВторой : $0.краска }
                             ?? Theme.текстВторой)
    }
}

/// Кружок цвета каталога: «разноцветный» — радугой, светлый — с обводкой.
struct КружокЦветаГардероба: View {
    let цвет: ЦветСтандарта
    var размер: CGFloat

    init(_ цвет: ЦветСтандарта, размер: CGFloat = 14) {
        self.цвет = цвет
        self.размер = размер
    }

    var body: some View {
        Group {
            if цвет == .разноцветный {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                              center: .center))
            } else {
                Circle().fill(цвет.краска)
            }
        }
        .frame(width: размер, height: размер)
        .overlay { Circle().strokeBorder(Theme.линия, lineWidth: цвет.светлый ? 1 : 0) }
        .accessibilityHidden(true)
    }
}
