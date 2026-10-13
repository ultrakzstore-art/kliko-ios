import SwiftUI
import UIKit

/**
 Кнопка «Продолжить с Google» по правилам оформления Google: светлая — белая с рамкой #747775 и текстом #1F1F1F, тёмная —
 #131314 с рамкой #8E918F и текстом #E3E3E3, слева — цветной знак «G». Размер и скругление — как у соседних кнопок
 экрана входа (.soc-btn: 48, радиус 14, 14/700), нажатие — то же сжатие. Чужих картинок нет: знак нарисован путями.
 */
struct КнопкаGoogle: View {
    let подпись: String
    let действие: () -> Void

    private static let фон = Theme.цвет(0xFFFFFF, 0x131314)
    private static let рамка = Theme.цвет(0x747775, 0x8E918F)
    private static let текст = Theme.цвет(0x1F1F1F, 0xE3E3E3)

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: действие) {
            HStack(spacing: 10) {
                ЗнакGoogle()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Self.текст)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Self.фон, in: форма)
            .overlay { форма.strokeBorder(Self.рамка, lineWidth: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityLabel(подпись)
    }
}

/// Знак «G» Google — четыре цветные части, нарисованные путями в квадрате 48×48 и растянутые под рамку.
struct ЗнакGoogle: View {
    var body: some View {
        ZStack {
            ЧастьЗнакаGoogle(часть: .красная).fill(Color(uiColor: Theme.hex(0xEA4335)))
            ЧастьЗнакаGoogle(часть: .синяя).fill(Color(uiColor: Theme.hex(0x4285F4)))
            ЧастьЗнакаGoogle(часть: .жёлтая).fill(Color(uiColor: Theme.hex(0xFBBC05)))
            ЧастьЗнакаGoogle(часть: .зелёная).fill(Color(uiColor: Theme.hex(0x34A853)))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Одна цветная часть знака «G»: координаты — в квадрате 48×48, путь вписывается по центру рамки.
struct ЧастьЗнакаGoogle: Shape {
    enum Часть {
        case красная, синяя, жёлтая, зелёная
    }

    let часть: Часть

    func path(in rect: CGRect) -> Path {
        let м = min(rect.width, rect.height) / 48
        let x0 = rect.midX - 24 * м
        let y0 = rect.midY - 24 * м
        func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * м, y: y0 + y * м) }
        var путь = Path()
        switch часть {
        case .красная:
            путь.move(to: т(24, 9.5))
            путь.addCurve(to: т(33.21, 13.1), control1: т(27.54, 9.5), control2: т(30.71, 10.72))
            путь.addLine(to: т(40.06, 6.25))
            путь.addCurve(to: т(24, 0), control1: т(35.9, 2.38), control2: т(30.47, 0))
            путь.addCurve(to: т(2.56, 13.22), control1: т(14.62, 0), control2: т(6.51, 5.38))
            путь.addLine(to: т(10.54, 19.41))
            путь.addCurve(to: т(24, 9.5), control1: т(12.43, 13.72), control2: т(17.74, 9.5))
        case .синяя:
            путь.move(to: т(46.98, 24.55))
            путь.addCurve(to: т(46.6, 20), control1: т(46.98, 22.98), control2: т(46.83, 21.46))
            путь.addLine(to: т(24, 20))
            путь.addLine(to: т(24, 29.02))
            путь.addLine(to: т(36.94, 29.02))
            путь.addCurve(to: т(32.16, 36.2), control1: т(36.36, 31.98), control2: т(34.68, 34.5))
            путь.addLine(to: т(39.89, 42.2))
            путь.addCurve(to: т(46.98, 24.55), control1: т(44.4, 38.02), control2: т(46.98, 31.84))
        case .жёлтая:
            путь.move(to: т(10.53, 28.59))
            путь.addCurve(to: т(9.77, 24), control1: т(10.05, 27.14), control2: т(9.77, 25.6))
            путь.addCurve(to: т(10.53, 19.41), control1: т(9.77, 22.4), control2: т(10.04, 20.86))
            путь.addLine(to: т(2.55, 13.22))
            путь.addCurve(to: т(0, 24), control1: т(0.92, 16.46), control2: т(0, 20.12))
            путь.addCurve(to: т(2.56, 34.78), control1: т(0, 27.88), control2: т(0.92, 31.54))
            путь.addLine(to: т(10.53, 28.59))
        case .зелёная:
            путь.move(to: т(24, 48))
            путь.addCurve(to: т(39.89, 42.19), control1: т(30.48, 48), control2: т(35.93, 45.87))
            путь.addLine(to: т(32.16, 36.19))
            путь.addCurve(to: т(24, 38.49), control1: т(30.01, 37.64), control2: т(27.24, 38.49))
            путь.addCurve(to: т(10.53, 28.58), control1: т(17.74, 38.49), control2: т(12.43, 34.27))
            путь.addLine(to: т(2.55, 34.77))
            путь.addCurve(to: т(24, 48), control1: т(6.51, 42.62), control2: т(14.62, 48))
        }
        путь.closeSubpath()
        return путь
    }
}
