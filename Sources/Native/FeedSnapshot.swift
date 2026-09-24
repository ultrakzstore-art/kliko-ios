import Foundation

/**
 СНИМОК ЛЕНТЫ — ТО, ЧТО ЧЕЛОВЕК ВИДЕЛ В ПРОШЛЫЙ РАЗ.

 Владелец 24.09.2026: «когда интернет кончается — очень долго работает».

 Что было. Запуск приложения — это сплэш минимум полторы секунды и ожидание страницы (76 КБ сжатыми). На
 хорошей связи это незаметно, на плохой — несколько секунд пустого экрана с логотипом. Показать при этом есть
 что: ту самую ленту, которую человек листал вчера.

 🔴 СНИМОК ПРИСЫЛАЕТ СТРАНИЦА, А НЕ ЗАПРАШИВАЕТ ПРИЛОЖЕНИЕ. Приложение могло бы сходить за лентой само, но
 получило бы ленту ПО УМОЛЧАНИЮ: город, радиус и точка живут в веб-сессии, и без неё астанинская лента
 приехала бы алматинцу. Страница отдаёт мостом `klikoFeed` ровно то, что человек только что видел своими
 глазами, — вместе с названиями разделов на его языке и их красками (js/marketplace-home.js, `_mhToApp`).
 Отсюда и форма записи: короткие ключи, десять товаров на раздел, никаких сорока полей карточки.

 Поля необязательные намеренно. Снимок мог лечь на диск старой сборкой сайта, а поле с тех пор переименовали —
 тогда разбор всей записи упал бы целиком, и вместо ленты человек снова увидел бы пустой сплэш. Обязателен
 только номер объявления: без него карточка никуда не ведёт и показывать её незачем.
 */
struct FeedSnapshot: Codable {
    /// Когда сняли, в миллисекундах unix — так же, как `Date.now()` на странице.
    let t: Double?
    let rows: [Row]

    struct Row: Codable, Identifiable {
        /// Ключ раздела: transport, realty, jobs…
        let k: String
        /// Название раздела — уже на языке человека, словарь второй раз не нужен.
        let t: String?
        /// Краска раздела, «#DC2626».
        let c: String?
        let items: [Item]

        var id: String { k }
        /// Название раздела, а если его не прислали — ключ: лучше «transport», чем пустая строка над полкой.
        var название: String {
            if let t, !t.isEmpty { return t }
            return k
        }
    }

    struct Item: Codable, Identifiable {
        let id: String
        let t: String?
        /// Цена числом. Ноль или пусто — цены нет (услуга «по договорённости»).
        let p: Double?
        /// Торг уместен.
        let n: Bool?
        /// Обложка: путь от корня сайта («/img/uploads/…_t.webp»).
        let img: String?
        let city: String?
        let top: Bool?

        var название: String { t ?? "" }
        var город: String { city ?? "" }
        var вТопе: Bool { top ?? false }
        var торг: Bool { n ?? false }
        var обложка: URL? {
            guard let img, !img.isEmpty else { return nil }
            return Config.url(img)
        }
        /// Куда ведёт карточка. Канонический адрес объявления — /marketplace?item=<номер>: у него 200, а у
        /// marketplace.php тот же адрес отдаётся перенаправлением, и это лишний круг по плохой связи.
        var адрес: URL? {
            guard !id.isEmpty else { return nil }
            var ч = URLComponents(url: Config.apiBase, resolvingAgainstBaseURL: false)
            ч?.path = "/marketplace"
            ч?.queryItems = [URLQueryItem(name: "item", value: id)]
            return ч?.url
        }
    }

    /// Возраст снимка. Нет отметки — считаем очень старым: показывать неизвестно что не будем.
    var возраст: TimeInterval {
        guard let t, t > 0 else { return .greatestFiniteMagnitude }
        return Date().timeIntervalSince1970 - t / 1000
    }

    /// Есть ли что показывать вообще.
    var пустой: Bool { rows.allSatisfy { $0.items.isEmpty } }
}
