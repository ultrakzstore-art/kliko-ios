import CoreMotion
import SwiftUI

/**
 КАК ДЕРЖАТ ТЕЛЕФОН — ДЛЯ КАМЕРЫ ПОДАЧИ (владелец 14.10.2026: «можешь предлагать повернуть камеру горизонтально»).

 Интерфейс камеры всегда портретный, поэтому ориентацию спрашиваем не у UIDevice (при замке поворота он молчит), а у
 датчика: гравитация CMMotionManager (разрешения не требует). По ней — угол снимка для AVCaptureConnection
 (videoRotationAngle: 90 — вертикально, 0 — горизонтально, «домой» справа, 180 — горизонтально, «домой» слева),
 чтобы горизонтальный кадр не лёг боком, и поворот подсказок к человеку. С запасом (порог 0,65 и «кто сильнее»), чтобы
 не дёргалось на краю.
 */
@MainActor
final class НаклонТелефонаКамеры: ObservableObject {
    /// Угол снимка для камеры: 90 — вертикально, 0 или 180 — горизонтально.
    @Published private(set) var угол: CGFloat = 90

    private let датчик = CMMotionManager()

    var горизонтально: Bool { угол != 90 }

    /// Поворот подписи к человеку, когда телефон лёг горизонтально (интерфейс остаётся портретным).
    var поворотПодписи: Angle {
        switch угол {
        case 0: return .degrees(90)
        case 180: return .degrees(-90)
        default: return .zero
        }
    }

    func запустить() {
        guard датчик.isDeviceMotionAvailable, !датчик.isDeviceMotionActive else { return }
        датчик.deviceMotionUpdateInterval = 0.15
        датчик.startDeviceMotionUpdates(to: .main) { [weak self] движение, _ in
            guard let self, let г = движение?.gravity else { return }
            MainActor.assumeIsolated { self.обновить(x: г.x, y: г.y) }
        }
    }

    func остановить() {
        if датчик.isDeviceMotionActive { датчик.stopDeviceMotionUpdates() }
        угол = 90
    }

    private func обновить(x: Double, y: Double) {
        let новый: CGFloat
        if abs(x) > 0.65 && abs(x) > abs(y) {
            новый = x < 0 ? 0 : 180
        } else if abs(y) > 0.65 && abs(y) > abs(x) {
            новый = 90
        } else {
            return
        }
        if новый != угол { угол = новый }
    }
}
