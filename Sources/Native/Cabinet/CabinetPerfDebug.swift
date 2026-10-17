import SwiftUI

/**
 ЗАМЕР КАБИНЕТА (скорость, «кабинет легче», разбор cabinet_perf_rank, раздел 2; только отладочная сборка).

 Аргумент запуска -klikoPrintChanges YES (или просто -klikoPrintChanges) включает у корня кабинета и его крупных частей
 (плитки, шапка профиля, кошелёк, карточка «Моё») печать причин перерисовки (Self._printChanges — какое свойство
 сменилось: _сделки, _настройки, @self…) и счётчик проходов body. Раз в 5 с в stderr — строка «[kliko-smoke]
 cabinet-renders N» (всего проходов с запуска) и рядом «[kliko-perf] cabinet-bodies …» по частям. Счётчик — обычный
 статический словарь, не @State и не @Published: перерисовок он не вызывает.

 Метка «[kliko-smoke] cabinet-ready» — первый показ корня кабинета за запуск (onAppear), без аргумента, как остальные
 метки дымовой проверки (ДымоваяПроверка).

 В выпускной сборке (не DEBUG) не делает ничего: вызов в body возвращает true сразу, без печати и счёта.
 */
@MainActor
enum ЗамерКабинета {
    #if DEBUG
    private static let вкл: Bool = UserDefaults.standard.bool(forKey: "klikoPrintChanges")
        || ProcessInfo.processInfo.arguments.contains("-klikoPrintChanges")
    private static var проходов = 0
    private static var поЧастям: [String: Int] = [:]
    private static var печатаем = false
    private static var готовОтмечен = false
    #endif

    /// В начале body: `let _ = ЗамерКабинета.тело("root", Self.self)`.
    @discardableResult
    static func тело<Вид: View>(_ часть: String, _ вид: Вид.Type) -> Bool {
        #if DEBUG
        guard вкл else { return true }
        вид._printChanges()
        проходов += 1
        поЧастям[часть, default: 0] += 1
        запуститьПечать()
        #endif
        return true
    }

    /// Первый показ корня кабинета за запуск — метка для журнала CI.
    static func готов() {
        #if DEBUG
        guard !готовОтмечен else { return }
        готовОтмечен = true
        ДымоваяПроверка.отметить("cabinet-ready")
        #endif
    }

    #if DEBUG
    /// Печать раз в 5 с — с первого счёта до конца запуска.
    private static func запуститьПечать() {
        guard !печатаем else { return }
        печатаем = true
        Task<Void, Never> { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                ДымоваяПроверка.отметить("cabinet-renders " + String(проходов))
                let части: [String] = поЧастям.keys.sorted().map { ключ in ключ + "=" + String(поЧастям[ключ] ?? 0) }
                let строка: String = "[kliko-perf] cabinet-bodies " + части.joined(separator: " ") + "\n"
                FileHandle.standardError.write(Data(строка.utf8))
            }
        }
    }
    #endif
}
