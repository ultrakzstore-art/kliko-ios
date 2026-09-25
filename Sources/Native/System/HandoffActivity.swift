import Foundation
import Combine

/**
 HANDOFF — ЭТАП 10 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Открытая в приложении карточка объявления предлагается Mac и iPad того же Apple ID: значок в Dock или в
 переключателе приложений — и то же объявление открывается в Safari (NSUserActivityTypeBrowsingWeb, webpageURL —
 канонический адрес /marketplace?item=). Стоит там Kliko — ссылку, как любую ссылку сайта, откроет он.

 Активность ведём сами, через becomeCurrent, а не модификатором SwiftUI .userActivity: окно создаёт сцена UIKit
 (SceneDelegate), а не WindowGroup, и работу модификатора в такой сцене не проверить без устройства.

 🔴 ОДНА КАРТОЧКА — ОДНА АКТИВНОСТЬ. При переходе на похожее объявление onAppear новой карточки приходит раньше
 onDisappear прежней, поэтому гасим только свою активность (по номеру), а не «текущую вообще». Слой вкладок спрятан
 под страницей сайта — карточки на экране нет, хотя SwiftUI её не убирал: тогда не предлагаем.
 */
@MainActor
final class Передача {
    static let shared = Передача()

    /// Держим сами: NSUserActivity, на которую никто не ссылается, система забывает.
    private var активность: NSUserActivity?
    /// Номер объявления этой активности.
    private var чья: String?
    private var подписка: AnyCancellable?

    private init() {
        подписка = WebBridge.shared.$лентаВидна
            .removeDuplicates()
            .sink { [weak self] видна in
                guard let self, let текущая = self.активность else { return }
                if видна { текущая.becomeCurrent() } else { текущая.resignCurrent() }
            }
    }

    /// Карточка на экране — предлагаем её страницу. Та же карточка дотянулась полностью — обновляем название.
    func показать(_ товар: Listing) {
        guard Config.handoff, !товар.заготовка, let адрес = товар.адрес else { return }
        let текущая: NSUserActivity
        if let прежняя = активность, чья == товар.id {
            текущая = прежняя
        } else {
            активность?.invalidate()
            текущая = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            текущая.isEligibleForHandoff = true
            текущая.isEligibleForSearch = false        // в поиск iPhone объявление кладёт ПоискТелефона, второй копии не надо
            активность = текущая
            чья = товар.id
        }
        текущая.webpageURL = адрес
        текущая.title = товар.title.isEmpty ? nil : товар.title
        if WebBridge.shared.лентаВидна { текущая.becomeCurrent() }
    }

    /// Карточка ушла с экрана — гасим её активность, если она всё ещё наша.
    func убрать(_ товар: Listing) {
        guard чья == товар.id, let текущая = активность else { return }
        текущая.invalidate()
        активность = nil
        чья = nil
    }
}
