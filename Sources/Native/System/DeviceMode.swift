import Foundation
import SwiftUI
import Combine

/**
 ЛЁГКИЙ РЕЖИМ (владелец 06.10.2026: «чтобы приложение летало буквально на всех девайсах»).

 Одна точка, где решается, беречь ли телефон. Лёгкий режим включается, если:
 • железо слабое (ЖелезоУстройства.слабое): памяти не больше «3 ГБ» по паспорту — iPhone XR, XS, SE 2-го поколения,
   iPad 7-го поколения (physicalMemory у таких отдаёт около 2,8 ГиБ, поэтому порог 3,5 ГиБ) — или ядер не больше двух;
 • включён режим энергосбережения (ProcessInfo.isLowPowerModeEnabled);
 • телефон перегрет (thermalState .serious или .critical).

 Что меняется в лёгком режиме — только дорогое и бесконечное: логотип в шапке и на заставке стоит, блеск заготовок
 ленты и мерцание не крутятся, размытая подложка под фото техники и стекло нижней панели — сплошным цветом, меньше
 картинок заранее и одновременно. На мощном телефоне без энергосбережения не меняется ничего.

 Энергосбережение и нагрев меняются на ходу — лёгкий пересчитывается по уведомлениям системы (@Published), экраны,
 которые следят за РежимУстройства.shared, перерисуются сами. Слабость железа за запуск не меняется.
 */
enum ЖелезоУстройства {
    /// Слабое железо: память до «3 ГБ» по паспорту или не больше двух ядер. Считается один раз.
    static let слабое: Bool = {
        let инфо = ProcessInfo.processInfo
        let порогПамяти: UInt64 = 3_584 * 1024 * 1024        // 3,5 ГиБ: «3 ГБ» по паспорту отдают около 2,8 ГиБ
        return инфо.physicalMemory < порогПамяти || инфо.activeProcessorCount <= 2
    }()

    /// Модель — строка utsname.machine («iPhone11,8»), без имени владельца и номеров. На симуляторе — «Simulator».
    static let модель: String = {
        var сведения = utsname()
        uname(&сведения)
        let байты = Mirror(reflecting: сведения.machine).children
            .compactMap { $0.value as? Int8 }
            .prefix { $0 != 0 }
            .map { UInt8(bitPattern: $0) }
        let машина = String(decoding: байты, as: UTF8.self)
        if машина == "x86_64" || машина == "arm64" {
            return "Simulator"
        }
        return String(машина.prefix(32))
    }()

    /// Памяти, ГБ, округлённо до целого — для отчёта о скорости.
    static let памятьГБ: Int = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
}

@MainActor
final class РежимУстройства: ObservableObject {
    static let shared = РежимУстройства()

    /// Беречь телефон: слабое железо, энергосбережение или перегрев.
    @Published private(set) var лёгкий: Bool
    /// Почему лёгкий: "hw", "lowpower", "thermal" (через запятую) или пусто — для отчёта о скорости.
    @Published private(set) var причина: String

    private var подписки = Set<AnyCancellable>()

    private init() {
        let (лёгкий, причина) = Self.посчитать()
        self.лёгкий = лёгкий
        self.причина = причина
        let центр = NotificationCenter.default
        /* Уведомления приходят на любой очереди — пересчёт на главной. */
        центр.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .merge(with: центр.publisher(for: ProcessInfo.thermalStateDidChangeNotification))
            .sink { _ in
                Task { @MainActor in РежимУстройства.shared.пересчитать() }
            }
            .store(in: &подписки)
    }

    /// Лёгкий режим сейчас — для кода вне представлений (КартинкиЛенты, предзагрузка).
    static var сейчас: Bool { shared.лёгкий }

    private func пересчитать() {
        let (новый, почему) = Self.посчитать()
        if новый != лёгкий { лёгкий = новый }
        if почему != причина { причина = почему }
    }

    nonisolated private static func посчитать() -> (Bool, String) {
        let инфо = ProcessInfo.processInfo
        var причины: [String] = []
        if ЖелезоУстройства.слабое { причины.append("hw") }
        if инфо.isLowPowerModeEnabled { причины.append("lowpower") }
        switch инфо.thermalState {
        case .serious, .critical: причины.append("thermal")
        case .nominal, .fair: break
        @unknown default: break
        }
        return (!причины.isEmpty, причины.joined(separator: ","))
    }
}
