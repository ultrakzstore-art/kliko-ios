import Foundation

/**
 ПАУЗА ГАРАНТА (владелец, упрощения для новичка): обещания «Безопасной сделки» — баннер главной, значки карточек,
 подсказки и строки страницы объявления — только пока гарант работает.

 Флаг — MK_ESCROW_PAUSED страницы кабинета (var MK_ESCROW_PAUSED=false; так же читает ПополнениеМодель.гарантНаПаузе).
 Страницу читаем не чаще раза в 10 минут и не ждём её (ждать: false); не прочиталась — остаётся прежнее значение.
 Последнее известное хранится на телефоне: пауза, замеченная в прошлый запуск, не мигнёт обещанием на старте.
 Флага на странице нет — паузы нет, как у сайта. Денег это не касается: только что показывать.
 */
@MainActor
final class ПаузаГаранта: ObservableObject {
    static let shared = ПаузаГаранта()

    /// true — гарант на паузе: обещаний «Безопасной сделки» не показываем.
    @Published private(set) var наПаузе: Bool

    private var сверено: Date? = nil
    private var идёт = false
    private static let ключ = "kliko.escrowPaused"
    private static let шаблон = #"MK_ESCROW_PAUSED\s*=\s*(true|1|!0)\b"#

    private init() {
        наПаузе = UserDefaults.standard.bool(forKey: Self.ключ)
    }

    /// Гарант работает — «Безопасную сделку» можно обещать.
    var работает: Bool { !наПаузе }

    /// Сверить флаг со страницей кабинета — не чаще раза в 10 минут.
    func сверить() async {
        guard !идёт else { return }
        if let сверено, Date().timeIntervalSince(сверено) < 600 { return }
        идёт = true
        defer { идёт = false }
        guard let страница = try? await КабинетСайта.страницаКабинета(ждать: false) else { return }
        let пауза = страница.html.range(of: Self.шаблон, options: .regularExpression) != nil
        сверено = Date()
        UserDefaults.standard.set(пауза, forKey: Self.ключ)
        if пауза != наПаузе { наПаузе = пауза }
    }
}
