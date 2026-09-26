import SwiftUI
import UIKit

/**
 ФОТО ПОДАЧИ — СЖАТИЕ, ВОДЯНОЙ ЗНАК, МИНИАТЮРА, КАМЕРА (этап 42, владелец 26.09.2026: «всё одно и то же, просто код
 разный»).

 Как у сайта (uploadImageSmart → srcToBlob → klikoWatermark, карта §2.2), с одним отличием, которое диктует iOS:
   · 🔴 WebP телефон кодировать не умеет (без чужой библиотеки), а сайт на этот случай сам держит запасной путь —
     canWebp() == false: белая подложка, длинная сторона не больше 1280 px, JPEG q0.70. Им и идём;
   · водяной знак — тот же рисунок, что window.KLK_WM страницы (значок-булавка в зелёном квадрате и «Klıko.kz» с
     маяком над «ı»), те же размеры и место: высота 6,2 % меньшей стороны, отступ 2,8 %, один из шести углов/краёв
     со случайным сдвигом, прозрачность 0,45 и тень. Светлый фон под знаком (средняя яркость > 140) — тёмная надпись,
     тёмный — белая. После знака сайт перекодирует JPEG в q0.90 — так же и здесь;
   · миниатюра — из исходного снимка, без знака: 420 px, JPEG q0.62 (uploadThumb);
   · исходник больше 15 МБ — «Фото больше 15 МБ», файл пропускается.
 Надпись «Klıko» и «.kz» — те же векторные картинки приложения (WmKliko, WmKz), что у заставки и открытки.

 Всё здесь — чистые функции без главного потока: их зовут из Task.detached, чтобы 12-мегапиксельный снимок не
 подвешивал экран.
 */
/// Только Data: результат идёт из Task.detached обратно на главный поток, а Data — Sendable (превью строит экран).
struct ГотовоеФото {
    let картинка: Data
    let миниатюра: Data
}

enum ОбработкаФото {
    /// 15 МБ — предел исходного файла у сайта (15728640 байт).
    static let предел = 15_728_640

    static func подготовить(_ данные: Data) -> ГотовоеФото? {
        guard let изображение = UIImage(data: данные) else { return nil }
        return подготовить(изображение)
    }

    /// srcToBlob(1280, q0.7) → klikoWatermark (JPEG q0.9); миниатюра — srcToBlob(420, q0.62) из исходника.
    static func подготовить(_ изображение: UIImage) -> ГотовоеФото? {
        guard let ужатое = ужать(изображение, сторона: 1280),
              let первыйJPEG = ужатое.jpegData(compressionQuality: 0.7),
              let снова = UIImage(data: первыйJPEG) else { return nil }
        let сЗнаком = знак(снова)
        guard let итог = сЗнаком.jpegData(compressionQuality: 0.9) else { return nil }
        let мини = ужать(изображение, сторона: 420)
        let итогМини = мини?.jpegData(compressionQuality: 0.62) ?? Data()
        return ГотовоеФото(картинка: итог, миниатюра: итогМини)
    }

    static func dataURL(_ данные: Data) -> String {
        "data:image/jpeg;base64," + данные.base64EncodedString()
    }

    /// Белая подложка и длинная сторона не больше заданной; поворот снимка — уже учтён (рисуем как видно на экране).
    static func ужать(_ изображение: UIImage, сторона: CGFloat) -> UIImage? {
        let ширина = изображение.size.width * изображение.scale
        let высота = изображение.size.height * изображение.scale
        guard ширина > 0, высота > 0 else { return nil }
        let k = min(1, сторона / max(ширина, высота))
        let размер = CGSize(width: max(1, (ширина * k).rounded()), height: max(1, (высота * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисовальщик = UIGraphicsImageRenderer(size: размер, format: формат)
        return рисовальщик.image { контекст in
            UIColor.white.setFill()
            контекст.fill(CGRect(origin: .zero, size: размер))
            изображение.draw(in: CGRect(origin: .zero, size: размер))
        }
    }

    // MARK: - Водяной знак (js/watermark.min.js + window.KLK_WM)

    static func знак(_ фото: UIImage) -> UIImage {
        let ширина = фото.size.width * фото.scale
        let высота = фото.size.height * фото.scale
        let меньшая = min(ширина, высота)
        guard меньшая > 0 else { return фото }
        let m = max(16, (0.062 * меньшая).rounded())
        let d = (3.71875 * m).rounded()
        let отступ = max(10, (0.028 * меньшая).rounded())
        let место = Int.random(in: 0..<6)
        var x: CGFloat = (место == 1 || место == 3 || место == 5) ? ширина - отступ - d : отступ
        var y: CGFloat
        if место == 0 || место == 1 {
            y = отступ
        } else if место == 2 || место == 3 {
            y = (высота - m) / 2
        } else {
            y = высота - отступ - m
        }
        let сдвигX = min(отступ, 0.05 * ширина)
        let сдвигY = min(отступ, 0.05 * высота)
        x += CGFloat.random(in: -сдвигX...сдвигX)
        y += CGFloat.random(in: -сдвигY...сдвигY)
        x = max(0, min(ширина - d, x))
        y = max(0, min(высота - m, y))
        let рамка = CGRect(x: x, y: y, width: d, height: m)
        let светлый = светлоПод(фото, рамка)

        let размер = CGSize(width: ширина, height: высота)
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисовальщик = UIGraphicsImageRenderer(size: размер, format: формат)
        return рисовальщик.image { контекст in
            фото.draw(in: CGRect(origin: .zero, size: размер))
            let к = контекст.cgContext
            к.saveGState()
            к.setAlpha(0.45)
            let тень = светлый ? UIColor(white: 1, alpha: 0.65) : UIColor(white: 0, alpha: 0.55)
            к.setShadow(offset: CGSize(width: 0, height: max(1, (0.05 * m).rounded())),
                        blur: max(3, (0.22 * m).rounded()), color: тень.cgColor)
            к.beginTransparencyLayer(auxiliaryInfo: nil)
            нарисоватьЗнак(к, рамка: рамка, светлыйФон: светлый)
            к.endTransparencyLayer()
            к.restoreGState()
        }
    }

    /// Средняя яркость под знаком (0.299 R + 0.587 G + 0.114 B) больше 140 — фон светлый.
    private static func светлоПод(_ фото: UIImage, _ область: CGRect) -> Bool {
        guard let полное = фото.cgImage, let кусок = полное.cropping(to: область.integral) else { return false }
        let w = 16
        let h = 8
        var пиксели = [UInt8](repeating: 0, count: w * h * 4)
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        let нарисовано: Bool = пиксели.withUnsafeMutableBytes { буфер -> Bool in
            guard let контекст = CGContext(data: буфер.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                           bytesPerRow: w * 4, space: пространство,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            контекст.draw(кусок, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard нарисовано else { return false }
        var сумма: Double = 0
        var i = 0
        while i + 2 < пиксели.count {
            сумма += 0.299 * Double(пиксели[i]) + 0.587 * Double(пиксели[i + 1]) + 0.114 * Double(пиксели[i + 2])
            i += 4
        }
        return сумма / Double(w * h) > 140
    }

    /// Рисунок KLK_WM: холст 238 × 64 — значок 64 × 64 (viewBox 48) и надпись 160 × 40 с x = 78, y = 12 (viewBox 296 × 74).
    private static func нарисоватьЗнак(_ к: CGContext, рамка: CGRect, светлыйФон: Bool) {
        let масштаб = рамка.height / 64
        к.saveGState()
        к.translateBy(x: рамка.minX, y: рамка.minY)
        к.scaleBy(x: масштаб, y: масштаб)

        /* Значок: зелёный квадрат со скруглением 13, кольцо, белая булавка, циферблат со стрелками. */
        к.saveGState()
        let значок: CGFloat = 64.0 / 48.0
        к.scaleBy(x: значок, y: значок)
        к.saveGState()
        let коробка = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 48, height: 48), cornerRadius: 13)
        к.addPath(коробка.cgPath)
        к.clip()
        let цвета: [CGColor] = [Theme.hex(0x16A34A).cgColor, Theme.hex(0x0F7A44).cgColor]
        if let градиент = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: цвета as CFArray,
                                     locations: [0, 1]) {
            к.drawLinearGradient(градиент, start: .zero, end: CGPoint(x: 48, y: 48), options: [])
        }
        к.restoreGState()
        к.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
        к.setLineWidth(2)
        к.strokeEllipse(in: CGRect(x: 16, y: 11.5, width: 16, height: 16))
        let булавка = UIBezierPath()
        булавка.move(to: CGPoint(x: 24, y: 9.8))
        булавка.addCurve(to: CGPoint(x: 34.2, y: 19.9), controlPoint1: CGPoint(x: 29.9, y: 9.8),
                         controlPoint2: CGPoint(x: 34.2, y: 14.3))
        булавка.addCurve(to: CGPoint(x: 24, y: 38), controlPoint1: CGPoint(x: 34.2, y: 27),
                         controlPoint2: CGPoint(x: 24, y: 38))
        булавка.addCurve(to: CGPoint(x: 13.8, y: 19.9), controlPoint1: CGPoint(x: 24, y: 38),
                         controlPoint2: CGPoint(x: 13.8, y: 27))
        булавка.addCurve(to: CGPoint(x: 24, y: 9.8), controlPoint1: CGPoint(x: 13.8, y: 14.3),
                         controlPoint2: CGPoint(x: 18.1, y: 9.8))
        булавка.close()
        к.setFillColor(UIColor.white.cgColor)
        к.addPath(булавка.cgPath)
        к.fillPath()
        к.setFillColor(Theme.hex(0x0F7A44).cgColor)
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

        /* Надпись «Klıko» (на светлом — тёмная, на тёмном — белая) и зелёное «.kz», маяк над «ı». */
        let надпись = CGRect(x: 78, y: 12, width: 160, height: 40)
        if let klk = UIImage(named: "WmKliko") {
            klk.withTintColor(светлыйФон ? UIColor.black : UIColor.white, renderingMode: .alwaysOriginal).draw(in: надпись)
        }
        if let kz = UIImage(named: "WmKz") {
            kz.draw(in: надпись)
        }
        let s: CGFloat = 160.0 / 296.0
        let центр = CGPoint(x: 78 + 79 * s, y: 12 + 15 * s)
        let маяк = Theme.hex(0x25D366)
        к.setStrokeColor(маяк.cgColor)
        к.setLineWidth(2.4 * s)
        к.strokeEllipse(in: CGRect(x: центр.x - 10 * s, y: центр.y - 10 * s, width: 20 * s, height: 20 * s))
        к.setFillColor(маяк.cgColor)
        к.fillEllipse(in: CGRect(x: центр.x - 6.2 * s, y: центр.y - 6.2 * s, width: 12.4 * s, height: 12.4 * s))
        к.restoreGState()
    }
}

// MARK: - Камера

/**
 «Камера» формы подачи (#camera-input с capture="environment" у сайта): системный экран съёмки, снимок уходит тем же
 путём, что и из галереи. Нет камеры (симулятор, iPad без неё) — кнопки нет.
 */
struct КамераПодачи: UIViewControllerRepresentable {
    let снято: (UIImage) -> Void
    let закрыть: () -> Void

    init(снято: @escaping (UIImage) -> Void, закрыть: @escaping () -> Void) {
        self.снято = снято
        self.закрыть = закрыть
    }

    static var есть: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Посредник {
        Посредник(снято: снято, закрыть: закрыть)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let экран = UIImagePickerController()
        экран.sourceType = .camera
        экран.cameraCaptureMode = .photo
        экран.delegate = context.coordinator
        return экран
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Посредник: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let снято: (UIImage) -> Void
        private let закрыть: () -> Void

        init(снято: @escaping (UIImage) -> Void, закрыть: @escaping () -> Void) {
            self.снято = снято
            self.закрыть = закрыть
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let снимок = info[.originalImage] as? UIImage { снято(снимок) }
            закрыть()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            закрыть()
        }
    }
}
