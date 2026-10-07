import Foundation
import SwiftUI

/**
 ПОКАЗЫ И НАЖАТИЯ ТОП — /api/rank_event.php, как у сайта (js/marketplace.min.js, 26.09.2026).

 Сайт:
   · _mkGoldObserve — после каждой отрисовки ленты IntersectionObserver с threshold 0.5 следит за золотыми карточками
     (.top-card[data-id] — объявление в ТОП-месте, _top). Карточка видна наполовину — если этот номер не отмечали последние
     60 секунд (_mkGoldSeen), он ложится в очередь (_mkGoldPend), и если в этом вызове наблюдателя что-то легло, очередь
     сразу уходит (_mkGoldFlush) одним запросом;
   · _mkGoldFlush — POST <APP_L>/api/rank_event.php, Content-Type: application/json, тело {"imp":["id",…]} (Object.keys
     очереди, в порядке появления), keepalive, куки своего сайта (обычный fetch того же источника);
   · mkReportClick — открыли объявление, стоящее в золотом месте: POST туда же {"clk":"id"}.
 По этим imp сервер ставит в золотые места реже показанные ТОП первыми (mkTopsSorted, Feed/FeedRhythm.swift).

 Приложение: то же тело и тот же адрес (/kz/<язык>/api/rank_event.php — APP_L сайта), куки веб-сессии из WebKit, без
 Origin. csrf в теле сайт не шлёт, и мы не добавляем полей в тело; токен сессии уходит заголовком X-Kliko-Csrf — после
 правки сервера 99 именно по нему (вошедшая сессия + её токен) rank_event.php пускает приложение вместо Origin. «Вызов наблюдателя» у SwiftUI не бывает — ячейки
 сообщают о себе по одной; всё, что пришло за 150 мс (кадр-другой прокрутки), уходит одним запросом.
 Видна наполовину: на iOS 18 и новее — onScrollVisibilityChange(threshold: 0.5); на iOS 17 — появление ячейки в сетке.
 */
@MainActor
final class ОтчётТОП {
    static let shared = ОтчётТОП()

    /// Когда номер последний раз ушёл показом — _mkGoldSeen: повтор раньше 60 с не шлём.
    private var отмечены: [String: Date] = [:]
    /// Очередь показов — _mkGoldPend, в порядке появления.
    private var очередь: [String] = []
    private var отправка: Task<Void, Never>?
    /// Токен сессии для заголовка — берём у страницы раз в пять минут.
    private var токен: String?
    private var токенВзят = Date.distantPast

    private init() {}

    /// Золотая карточка видна наполовину.
    func показан(_ id: String) {
        guard !id.isEmpty else { return }
        let сейчас = Date()
        if let был = отмечены[id], сейчас.timeIntervalSince(был) < 60 { return }
        отмечены[id] = сейчас
        if !очередь.contains(id) { очередь.append(id) }
        guard отправка == nil else { return }
        отправка = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await self?.отправитьПоказы()
        }
    }

    /// Открыли объявление из золотого места — mkReportClick.
    func нажат(_ id: String) {
        guard !id.isEmpty else { return }
        Task { [weak self] in await self?.отправить(["clk": id]) }
    }

    private func отправитьПоказы() async {
        let номера = очередь
        очередь = []
        отправка = nil
        guard !номера.isEmpty else { return }
        await отправить(["imp": номера])
    }

    private func отправить(_ тело: [String: Any]) async {
        guard let адрес = Config.страницаСайта("api/rank_event.php"),
              let данные = try? JSONSerialization.data(withJSONObject: тело) else { return }
        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.httpShouldHandleCookies = false
        запрос.timeoutInterval = 20
        запрос.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        if let токен = await токенСессии() { запрос.setValue(токен, forHTTPHeaderField: "X-Kliko-Csrf") }
        запрос.httpBody = данные
        /* Ответ сайту не нужен (у него try{fetch}catch{} без .then) — и нам тоже. */
        _ = try? await URLSession.shared.data(for: запрос)
    }

    private func токенСессии() async -> String? {
        if токен != nil, Date().timeIntervalSince(токенВзят) < 300 { return токен }
        if let свежий = await SiteSession.csrf() {
            токен = свежий
            токенВзят = Date()
        }
        return токен
    }
}

/// Ячейка золотого места сообщает о показе ОтчётТОП: видна наполовину (iOS 18+) или появилась в сетке (iOS 17).
struct ПоказТОП: ViewModifier {
    let id: String
    let золото: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollVisibilityChange(threshold: 0.5) { видно in
                if видно && золото { ОтчётТОП.shared.показан(id) }
            }
        } else {
            content.onAppear {
                if золото { ОтчётТОП.shared.показан(id) }
            }
        }
    }
}
