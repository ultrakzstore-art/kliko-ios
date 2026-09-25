import Foundation

/**
 ССЫЛКИ В НАТИВНЫЕ ЭКРАНЫ — ЭТАП 8 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Пуш, kliko://open?u=… и универсальная ссылка раньше всегда открывали страницу сайта. Теперь две известные страницы
 открываются своими экранами: объявление (/marketplace?item=<номер>) — нативной карточкой во вкладке «Лента»,
 переписка (/cabinet.php?s=messages) — вкладкой «Сообщения». Всё остальное — сайтом, как было.

 Узнаём только то, что видно в самом приложении: канонический адрес объявления (Listing.адрес, FeedSnapshot) и адрес
 переписки из пуша (ChatThreadModel.адресПереписки). Номера диалога в адресе переписки приложение не встречало,
 поэтому отдельного «открыть диалог» нет — только список.

 🔴 ЛИШНИЙ ПАРАМЕТР — НА САЙТ. Ссылка с чем-то ещё, кроме item / s (и меток utm_), или с #якорем может значить то,
 чего нативный экран не умеет (раздел страницы, предложение, сделку). Такую открываем сайтом: там она сработает.
 */
@MainActor
final class NativeRouter: ObservableObject {
    static let shared = NativeRouter()

    enum Цель: Hashable {
        /// Карточка объявления по номеру — полную ListingDetailView дотянет сама (?id=).
        case объявление(id: String)
        /// Вкладка «Сообщения», список диалогов.
        case сообщения
    }

    /// Куда вести. Ставит WebBridge.открытьСнаружи, забирает и обнуляет NativeTabsView — в том числе на холодном
    /// старте, когда цель пришла раньше, чем вкладки появились на экране.
    @Published var цель: Цель?

    private init() {}

    /// Нативный экран для адреса или nil — тогда страница сайта. Экран, выключенный своим рубильником, не предлагаем.
    static func распознать(_ адрес: URL) -> Цель? {
        let полный = адрес.absoluteURL                  // путь из пуша приходит относительным к Config.apiBase
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              Config.deepLink(полный) != nil,          // наш домен — та же проверка, что у внешних ссылок
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false),
              (части.fragment ?? "").isEmpty else { return nil }

        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        /// Значение параметра, если он в адресе единственный (не считая меток utm_).
        func единственный(_ имя: String) -> String? {
            guard параметры.count == 1, let п = параметры.first, п.name == имя else { return nil }
            let значение = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            return значение.isEmpty ? nil : значение
        }

        switch части.path {
        case "/marketplace", "/marketplace/", "/marketplace.php":
            guard Config.нативнаяКарточка, let номер = единственный("item"),
                  номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else { return nil }
            return .объявление(id: номер)
        case "/cabinet.php":
            guard Config.нативныйЧат, единственный("s") == "messages" else { return nil }
            return .сообщения
        default:
            return nil
        }
    }
}

extension Listing {
    /// Заготовка по одному номеру — объявление из ссылки: остальное ListingDetailView дотянет по ?id=.
    init(номер: String) {
        id = номер
        title = ""
        price = nil
        oldPrice = nil
        negotiable = false
        forRent = false
        rentPriceDay = nil
        thumb = nil
        city = ""
        isTop = false
        isNew = false
    }

    /// Известен только номер (открыли по ссылке, карточка ещё не пришла). Такую не показываем пустой карточкой с
    /// «Ценой по запросу» и не кладём ни в избранное, ни в «Вы смотрели».
    var заготовка: Bool { title.isEmpty && thumb == nil && price == nil && !полная }
}
