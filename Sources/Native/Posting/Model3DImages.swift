import Foundation
import ImageIO
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — КАДРЫ РАКУРСОВ: подготовка, вырезка, файлы на телефоне.

 Снимок камеры или файл галереи → кадр прямо (поворот учтён), длинная сторона не больше max_px из info (1280), белая
 подложка; EXIF и место съёмки не уходят — картинка рисуется заново. Дальше — общая вырезка студии (ВырезкаПредмета,
 поле 4 %): вещь или машина без фона, PNG с прозрачностью. Не вышло (пёстрый фон, предмет на весь кадр) — уходит JPEG
 кадра с cut:false, фон уберёт сервер. Подсказка «в кадре люди» — Vision на телефоне (ФотоПримерочной.естьЛюди), решает
 сервер. Всё здесь — чистые функции без главной нити: их зовут из Task.detached, на входе и выходе — Data и UIImage.

 Файлы ракурсов лежат в Caches/kliko-model3d-angles/<папка записи>/ (a0.png, o0.jpg…) — до публикации или
 «Убрать», не дольше 7 дней. Система может стереть Caches сама: тогда остаются адреса, уже загруженные на сервер.
 */
enum КартинкиОбзора3DПодачи {
    /// Готовый ракурс: картинка для upload_angle (PNG с прозрачностью или JPEG, уже в пределе), исходный JPEG и признаки.
    struct Готовый: Sendable {
        let картинка: Data
        /// true — PNG вырезки; false — JPEG кадра (вырезать не вышло).
        let вырезан: Bool
        let исходник: Data
        /// Vision нашёл людей или лица; nil — не знаем.
        let людиВКадре: Bool?
    }

    /// Предел data URL картинки ракурса, байты: с исходником тело upload_angle меньше 4 МБ (docs/SERVER_3D.md, раздел 0).
    static let пределКартинки = 2_000_000
    /// Предел data URL исходника.
    static let пределИсходника = 1_200_000

    /// Файл галереи: уменьшаем уже при чтении (ImageIO) — фото 48 Мп не разворачивается в полный битмап ради 1280 px.
    static func подготовить(_ данные: Data, вид: ВидОбзора3DПодачи, сторона: Int) -> Готовый? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, чтение) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: max(640, сторона)] as CFDictionary
        guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры) else { return nil }
        return подготовить(UIImage(cgImage: кадр), вид: вид, сторона: сторона)
    }

    /// Снимок камеры (UIImage с меткой поворота) → готовый ракурс. nil — снимок меньше 256 px, битый или задачу отменили.
    static func подготовить(_ снимок: UIImage, вид: ВидОбзора3DПодачи, сторона: Int) -> Готовый? {
        guard let прямой = ровный(снимок, сторона: CGFloat(max(640, сторона))), let кадр = прямой.cgImage,
              !Task.isCancelled else { return nil }
        guard let исходник = jpegВПределе(прямой) else { return nil }
        /* У машины кузов часто занимает почти весь кадр — предел «весь кадр» мягче, чем у вещи. */
        let предел = вид == .машина ? 0.97 : ВырезкаПредмета.предельнаяДоля
        var картинка: Data? = nil
        if let вырезанное = ВырезкаПредмета.вырезатьСРамкой(кадр, поле: 0.04, предел: предел), !Task.isCancelled {
            картинка = pngВПределе(вырезанное.картинка)
        }
        if Task.isCancelled { return nil }
        let люди = ФотоПримерочной.естьЛюди(прямой)
        if let картинка {
            return Готовый(картинка: картинка, вырезан: true, исходник: исходник, людиВКадре: люди)
        }
        return Готовый(картинка: исходник, вырезан: false, исходник: исходник, людиВКадре: люди)
    }

    /// data URL картинки ракурса для upload_angle.
    static func адрес(_ данные: Data, вырезан: Bool) -> String {
        (вырезан ? "data:image/png;base64," : "data:image/jpeg;base64,") + данные.base64EncodedString()
    }

    /// Длина data URL без самого кодирования: 4 знака на каждые 3 байта и заголовок.
    static func длинаАдреса(_ байт: Int) -> Int { 23 + (байт + 2) / 3 * 4 }

    /// Миниатюра из файла (PNG сохраняет прозрачность); сторона — в пикселях.
    static func миниатюра(_ данные: Data, сторона: Int) -> UIImage? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, чтение) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: max(64, сторона)] as CFDictionary
        guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры) else { return nil }
        return UIImage(cgImage: кадр)
    }

    // MARK: Внутреннее

    /// Кадр прямо, длинная сторона ≤ сторона, белая подложка, масштаб 1. nil — меньше 256 px по короткой стороне.
    private static func ровный(_ снимок: UIImage, сторона: CGFloat) -> UIImage? {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard min(w, h) >= 256 else { return nil }
        let k = min(1, сторона / max(w, h))
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        формат.preferredRange = .standard
        return UIGraphicsImageRenderer(size: размер, format: формат).image { холст in
            UIColor.white.setFill()
            холст.fill(CGRect(origin: .zero, size: размер))
            снимок.draw(in: CGRect(origin: .zero, size: размер))
        }
    }

    /// JPEG кадра: 0,82, а если data URL больше пределИсходника — 0,7 и 0,6.
    private static func jpegВПределе(_ картинка: UIImage) -> Data? {
        for качество in [0.82, 0.7, 0.6] {
            guard let jpeg = картинка.jpegData(compressionQuality: качество) else { return nil }
            if длинаАдреса(jpeg.count) <= пределИсходника || качество == 0.6 { return jpeg }
        }
        return nil
    }

    /// PNG вырезки не больше пределКартинки: крупнее — ужимается до трёх раз по 0,8. nil — не влезло или отменили.
    private static func pngВПределе(_ картинка: CGImage) -> Data? {
        var текущая = картинка
        for _ in 0..<4 {
            guard !Task.isCancelled, let png = UIImage(cgImage: текущая).pngData() else { return nil }
            if длинаАдреса(png.count) <= пределКартинки { return png }
            guard let меньше = ужать(текущая, доля: 0.8) else { return nil }
            текущая = меньше
        }
        return nil
    }

    /// Картинка с прозрачностью, меньше в `доля` раз по каждой стороне.
    private static func ужать(_ картинка: CGImage, доля: CGFloat) -> CGImage? {
        let w = max(1, Int((CGFloat(картинка.width) * доля).rounded()))
        let h = max(1, Int((CGFloat(картинка.height) * доля).rounded()))
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        к.interpolationQuality = .high
        к.draw(картинка, in: CGRect(x: 0, y: 0, width: w, height: h))
        return к.makeImage()
    }
}

// MARK: - Файлы ракурсов на телефоне

/// Папка записи в Caches: картинки ракурсов (a<номер>.png или .jpg) и исходники (o<номер>.jpg). Имя папки — draft_id
/// первой съёмки; сервер может выдать записи новый черновик (прежний истёк), папка остаётся. Без главной нити.
enum ФайлыОбзора3DПодачи {
    private static let имяПапки = "kliko-model3d-angles"

    static var корень: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(имяПапки, isDirectory: true)
    }

    /// Имя годится в имя папки: только латиница в нижнем регистре, цифры и «_», 8–64 знака.
    static func годный(_ папка: String) -> Bool {
        guard (8...64).contains(папка.count) else { return false }
        return папка.unicodeScalars.allSatisfy { знакиПапки.contains($0) }
    }

    private static let знакиПапки = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")

    static func путь(_ папка: String) -> URL? {
        guard годный(папка) else { return nil }
        return корень?.appendingPathComponent(папка, isDirectory: true)
    }

    static func имяКартинки(_ ракурс: РакурсОбзора3DПодачи, вырезан: Bool) -> String {
        "a" + String(ракурс.rawValue) + (вырезан ? ".png" : ".jpg")
    }

    static func имяИсходника(_ ракурс: РакурсОбзора3DПодачи) -> String {
        "o" + String(ракурс.rawValue) + ".jpg"
    }

    /// Имя файла — только то, что выдали имяКартинки и имяИсходника.
    private static func годноеИмя(_ имя: String) -> Bool {
        guard (6...7).contains(имя.count), let первая = имя.first, первая == "a" || первая == "o" else { return false }
        return имя.hasSuffix(".png") || имя.hasSuffix(".jpg")
    }

    @discardableResult
    static func записать(_ данные: Data, папка: String, имя: String) -> Bool {
        guard годноеИмя(имя), let место = путь(папка) else { return false }
        do {
            try FileManager.default.createDirectory(at: место, withIntermediateDirectories: true)
            try данные.write(to: место.appendingPathComponent(имя), options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    static func прочитать(папка: String, имя: String) -> Data? {
        guard !имя.isEmpty, годноеИмя(имя), let место = путь(папка) else { return nil }
        return try? Data(contentsOf: место.appendingPathComponent(имя))
    }

    static func удалитьФайл(папка: String, имя: String) {
        guard годноеИмя(имя), let место = путь(папка) else { return }
        try? FileManager.default.removeItem(at: место.appendingPathComponent(имя))
    }

    static func удалить(папка: String) {
        guard let место = путь(папка) else { return }
        try? FileManager.default.removeItem(at: место)
    }

    /// Убрать папки, которых больше нет в записях (опубликовали, убрали, истекли 7 дней).
    static func прибрать(оставить: Set<String>) {
        guard let корень,
              let папки = try? FileManager.default.contentsOfDirectory(at: корень, includingPropertiesForKeys: nil)
        else { return }
        for место in папки where !оставить.contains(место.lastPathComponent) {
            try? FileManager.default.removeItem(at: место)
        }
    }
}
