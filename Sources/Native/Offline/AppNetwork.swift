import Foundation
import Network
import SwiftUI

/**
 СЕТЬ ПРИЛОЖЕНИЯ — ОФЛАЙН-РЕЖИМ (владелец 08.10.2026: «без сети человек видит последнее, что видел, а сообщения уходят,
 когда сеть вернётся»).

 Один общий монитор для экранов и очереди сообщений: есть ли путь в сеть (NWPath.status == .satisfied) и дорогая ли она
 (сотовая или модем). Замеры скорости держат свой монитор (СетьДляЗамеров, PerfTelemetry.swift) — он читается из любого
 потока под замком, а этот живёт на главной и публикует перемены для SwiftUI.

 «Сеть вернулась» (нет → есть) — счётчик возвратов: экраны, показавшие копию с диска, по нему перечитывают себя сами
 (приВозвратеСети), очередь исходящих — отправляет ждущее.

 🔴 ЗАПУСК ЛЕНИВЫЙ И БЕЗ СОСЕДЕЙ. init пустой и не трогает других синглтонов: в 1.11 (58) приложение падало на запуске
 из-за взаимной инициализации двух shared (EXC_BREAKPOINT в swift_once). Монитор стартует из SceneDelegate после запуска;
 до первого ответа монитора считаем, что сеть есть, — плашка «нет сети» не мигает на каждом запуске.
 */
@MainActor
final class СетьПриложения: ObservableObject {
    static let shared = СетьПриложения()

    /// Есть путь в сеть. До первого ответа монитора — да.
    @Published private(set) var онлайн = true
    /// Сеть дорогая: сотовая, режим модема или «Экономия данных».
    @Published private(set) var дорогая = false
    /// Растёт при каждом возвращении сети (нет → есть).
    @Published private(set) var возвратов = 0

    private var монитор: NWPathMonitor? = nil
    private let очередьМонитора = DispatchQueue(label: "kz.kliko.app.net", qos: .utility)

    private init() {}

    /// Запуск монитора (SceneDelegate). Повторный вызов ничего не делает.
    func запустить() {
        guard монитор == nil else { return }
        let новый = NWPathMonitor()
        новый.pathUpdateHandler = { путь in
            let есть = путь.status == .satisfied
            let дорого = путь.isExpensive || путь.isConstrained
            Task { @MainActor in СетьПриложения.shared.пришло(есть: есть, дорогая: дорого) }
        }
        монитор = новый
        новый.start(queue: очередьМонитора)
    }

    private func пришло(есть: Bool, дорогая новая: Bool) {
        if новая != дорогая { дорогая = новая }
        guard есть != онлайн else { return }
        онлайн = есть
        if есть { возвратов += 1 }
    }
}

extension View {
    /// Сеть вернулась (нет → есть) — действие экрана: показанная копия с диска перечитывается сама.
    func приВозвратеСети(_ действие: @escaping () -> Void) -> some View {
        modifier(ВозвратСети(действие: действие))
    }
}

private struct ВозвратСети: ViewModifier {
    @ObservedObject private var сеть = СетьПриложения.shared
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    func body(content: Content) -> some View {
        content.onChange(of: сеть.возвратов) { _, _ in действие() }
    }
}
