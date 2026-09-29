import Foundation

/**
 ССЫЛКИ В НАТИВНЫЕ ЭКРАНЫ — ЭТАП 8 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Пуш, kliko://open?u=… и универсальная ссылка раньше всегда открывали страницу сайта. Теперь две известные страницы
 открываются своими экранами: объявление (/marketplace?item=<номер>) — нативной карточкой во вкладке «Лента»,
 переписка (/cabinet.php?s=messages) — вкладкой «Сообщения». Всё остальное — сайтом, как было.

 Узнаём только то, что видно в самом приложении: канонический адрес объявления (Listing.адрес, FeedSnapshot) и адрес
 переписки из пуша (ChatThreadModel.адресПереписки). Номера диалога в адресе переписки приложение не встречало,
 поэтому отдельного «открыть диалог» нет — только список.

 Этап 51: ещё раздел ленты (/?cat=, /marketplace?cat=, /?q=, /?all=1), «Работа» (/?cat=jobs) и форма обращения
 (/support.php?topic=) — им лишние параметры и #якорь не мешают (цельЛентыИПоддержки).

 🔴 ЛИШНИЙ ПАРАМЕТР — НЕ ЭТОТ РАЗБОР (сайта больше нет: WebBridge.перейти берёт ближайший свой экран, БезСайта.ближайший). Ссылка с чем-то ещё, кроме item / s (и меток utm_), или с #якорем может значить то,
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
        /// Лента с полем поиска наготове — быстрое действие «Поиск» с иконки (этап 10). Адреса на сайте у неё нет.
        case поиск
        /// Вкладка «Избранное» — быстрое действие с иконки (этап 10). Живёт на телефоне, адреса на сайте тоже нет.
        case избранное
        /// Лента с готовым поиском — уведомление о новых по сохранённому поиску и строка кабинета (этап 12); с этапа 51 —
        /// и ссылки ленты сайта (раздел, поиск, SEO-раздел, фильтры в адресе — СсылкиЛенты). добавка — место и фильтры
        /// адреса, которых искомое не несёт (sort, verified, photo, ymin, ymax, city, region); nil — нет.
        case найти(ИскомоеЛенты, добавка: ДобавкаЛенты? = nil)
        /// «Мои объявления» во вкладке «Кабинет» — /cabinet?go=items (этап 41).
        case моиОбъявления
        /// Мастер подачи поверх вкладок — /cabinet?go=add (этап 42).
        case подача
        /// Правка объявления тем же мастером — /cabinet.php?edit=<id> (этап 42).
        case правка(id: String)
        /// «Мои сделки» во вкладке «Кабинет» — /cabinet?go=deals, ?s=deals (этап 43).
        case сделки
        /// Карточка сделки поверх «Моих сделок» — /cabinet.php?deal=<id> (этап 43; пуш и уведомление о сделке).
        case сделка(id: String)
        /// «Заявки рядом» во вкладке «Кабинет» — /cabinet?s=requests, ?go=requests (этап 45).
        case заявки
        /// Переписка по обращению в поддержку — /cabinet.php?ticket=<id> (этап 45).
        case обращение(id: String)
        /// Окно «Сменить пароль» поверх кабинета — /cabinet?open=password (этап 46; ссылка окна «Это были вы?»).
        case пароль
        /// Экран кошелька во вкладке «Кабинет» — /cabinet?go=wallet, ?payout=back (этап 47).
        case кошелёк
        /// «Баллы» во вкладке «Кабинет» — /cabinet?s=points (этап 47).
        case баллы
        /// Корень вкладки «Кабинет» — /cabinet.php без параметров: свой кабинет вместо кабинета сайта.
        case кабинет
        /// Раздел меню кабинета сайта своим экраном в стеке «Кабинета» (?s=deliveries, ?s=rentals, ?s=company, …).
        case разделКабинета(КабинетЦель)
        /// «Работа» — /?cat=jobs, /kz/<язык>/jobs, вакансия — #vac=<номер>: свой список и карточка (ОкноВакансий, этап 51).
        /// запрос — ?q= чипов главной («Водитель», «Курьер»…): список сразу с этим поиском.
        case вакансии(номер: String?, запрос: String = "")
        /// Форма обращения — /support.php?topic=<тема> (ЛистОбращения, этап 51).
        case поддержка(тема: String)
        /// «Продавайте на Kliko» — /cabinet?add=1: по роли, как кнопка продажи главной (ВходПоСсылке.продать).
        case продажа
        /// Экран гостя с ?after=import|add|deals (и ?egov=1): вход или регистрация, затем адрес своего экрана
        /// (ВходПоСсылке.войтиЗатем).
        case входЗатем(адрес: URL, egov: Bool)
    }

    /// Включён ли экран цели своим рубильником. Нет — вход снаружи идёт сайтом (WebBridge.открытьЭкран).
    static func доступна(_ куда: Цель) -> Bool {
        switch куда {
        case .объявление: return Config.нативнаяКарточка
        case .сообщения:  return Config.нативныйЧат
        case .поиск:      return true
        case .избранное:  return Config.избранное
        case .найти:      return true
        case .моиОбъявления: return Config.нативныеОбъявления && Config.нативныйКабинет
        case .подача, .правка: return Config.нативнаяПодача
        case .сделки, .сделка: return Config.нативныеСделки && Config.нативныйКабинет
        case .заявки, .обращение: return Config.нативныеСообщенияКабинета && Config.нативныйКабинет
        case .пароль: return Config.нативныеНастройки && Config.нативныйВход && Config.нативныйКабинет
        case .кошелёк, .баллы: return Config.нативныйКошелёк && Config.нативныйКабинет
        case .кабинет, .разделКабинета: return Config.нативныйКабинет
        case .вакансии: return Config.нижниеВкладки
        case .поддержка: return true
        case .продажа: return Config.нативнаяПодача
        case .входЗатем: return Config.нативныйВход && Config.нативныйКабинет
        }
    }

    /// Куда вести. Ставит WebBridge.открытьСнаружи (быстрые действия с иконки — открытьЭкран, этап 10), забирает и
    /// обнуляет NativeTabsView — в том числе на холодном старте, когда цель пришла раньше, чем вкладки появились.
    @Published var цель: Цель?

    private init() {}

    /// Нативный экран для адреса или nil — тогда страница сайта. Экран, выключенный своим рубильником, не предлагаем.
    static func распознать(_ адрес: URL) -> Цель? {
        let полный = адрес.absoluteURL                  // путь из пуша приходит относительным к Config.apiBase
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              Config.deepLink(полный) != nil,          // наш домен — та же проверка, что у внешних ссылок
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        /* Этап 51: раздел ленты, «Работа» и поддержка — лишние параметры и #якорь им не мешают. */
        if let своя = цельЛентыИПоддержки(части) { return своя }
        guard (части.fragment ?? "").isEmpty else { return nil }

        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        /// Значение параметра, если он в адресе единственный (не считая меток utm_).
        func единственный(_ имя: String) -> String? {
            guard параметры.count == 1, let п = параметры.first, п.name == имя else { return nil }
            let значение = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            return значение.isEmpty ? nil : значение
        }

        /* Язык в пути (/kz/ru/marketplace, /kz/kz/…) — те же адреса, что без него. */
        let путь = части.path.replacingOccurrences(of: "^/[a-z]{2}/[a-z]{2}(?=/)", with: "",
                                                   options: .regularExpression)
        /* ЧПУ объявления: /toyota-camry-pb61110afe145/ (так делится SiteShare), ?p= — номер фото. */
        if Config.нативнаяКарточка, параметры.allSatisfy({ $0.name == "p" }),
           путь.range(of: "^/[a-z0-9-]+-p[0-9a-f]{8,20}/?$", options: .regularExpression) != nil,
           let r = путь.range(of: "p[0-9a-f]{8,20}(?=/?$)", options: .regularExpression) {
            return .объявление(id: String(путь[r]))
        }

        switch путь {
        case "/marketplace", "/marketplace/", "/marketplace.php":
            /* ?item=<номер>&p=<фото> и ?ret= не мешают; прочие параметры (chat=1 и т.п.) — сайтом. */
            let своё = параметры.filter { $0.name != "p" && $0.name != "ret" }
            guard Config.нативнаяКарточка, своё.count == 1, let п = своё.first, п.name == "item" else { return nil }
            let номер = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            guard номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else { return nil }
            return .объявление(id: номер)
        case "/cabinet.php":
            /* Этап 40: адреса кабинета разбирает АдресаКабинета (все параметры §0.10 карты кабинета). */
            if Config.адресаКабинета { return АдресаКабинета.цель(параметры) }
            guard Config.нативныйЧат, единственный("s") == "messages" else { return nil }
            return .сообщения
        default:
            /* Этап 40: /cabinet и /kz/<язык>/cabinet(.php) — те же адреса кабинета. */
            guard Config.адресаКабинета, АдресаКабинета.кабинет(части.path) else { return nil }
            return АдресаКабинета.цель(параметры)
        }
    }

    /**
     Этап 51 (владелец: «всё нативно»): /?cat=<раздел>, /marketplace?cat=<раздел>, /?q=, /?all=1 — лента с этим
     разделом или поиском; /?cat=jobs (#vac=<номер>) — «Работа»; /support.php?topic=<тема> — форма обращения.
     Язык в пути (/kz/<язык>/) и лишние параметры не мешают; объявление (?item=) разбирает распознать.
     «Без переходов на сайт»: и лента без параметров (/kz/<язык>/marketplace, /index.php), SEO-разделы (/kupit/<раздел>/,
     /uslugi/<раздел>/), ?vs=goods, /kz/<язык>/jobs, фильтры в адресе и ?s=<продавец> — разбор СсылкиЛенты.
     */
    private static func цельЛентыИПоддержки(_ части: URLComponents) -> Цель? {
        let путь = части.path
        let все = части.queryItems ?? []
        func значение(_ имя: String) -> String {
            let v = все.first(where: { $0.name == имя })?.value ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/support(\\.php)?/?$", options: .regularExpression) != nil {
            /* ?action= (отправка формы) и ?ticket= (переписка) — не форма нового обращения. */
            guard значение("action").isEmpty, значение("ticket").isEmpty else { return nil }
            let тема = значение("topic").lowercased().filter { $0.isASCII && $0.isLetter }
            return .поддержка(тема: тема.isEmpty ? "other" : тема)
        }
        return СсылкиЛенты.цель(части)
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
