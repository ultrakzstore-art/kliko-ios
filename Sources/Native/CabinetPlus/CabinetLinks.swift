import SwiftUI
import UIKit

/**
 АДРЕСА КАБИНЕТА ИЗ ЭКРАНОВ ПРИЛОЖЕНИЯ — СВОИМИ ЭКРАНАМИ (владелец: «и кабинет полностью SwiftUI сделай»).

 Нативные экраны открывают страницы через одно корневое «открыть» (RootWebView): раньше адрес кабинета, у которого нет
 своего окна (ОкноEgov, ОкноПродавца, НативныеОкна), уходил в WKWebView — приложение целиком становилось сайтом. Теперь
 перед этим адрес смотрит ПереходыКабинета.перехватить:
   · документы кабинета — договор и акт аренды, акт работ, гарантийный талон (escrow.php?action=rental_contract |
     rental_act | service_act | warranty_card, cabinet.php?action=rent_contract) — своё окно PDF (ОкноДокумента);
   · раздел меню кабинета со своим экраном (АдресаКабинета: ?s=company, ?s=founder, ?s=deliveries, ?s=rentals,
     ?s=exchanges, ?s=subs, …) — вкладка «Кабинет» и этот экран. /cabinet.php без параметров, ?deal=, ?go=items и
     ?go=wallet из экранов приложения — страница сайта, как раньше: так их зовут только денежные и платные кнопки.
 Остальное — WebBridge.перейти: свои экраны кабинета, сделок и кошелька (NativeRouter), иначе окно «недоступно» — не
 сайт (владелец: «главное, чтобы на сайт не прыгал с приложения»). eGov и биометрия — ОкноEgov. Покупки ТОП / PRO / слотов (?promote=, ?top=, ?go=promote) в приложении не продаются: их адреса
 АдресаКабинета ведёт в «Платные услуги» (только сведения).
 */
@MainActor
enum ПереходыКабинета {
    /// Слой вкладок на месте — туда можно вести (как вкладкиЕсть у WebBridge).
    private static var вкладкиЕсть: Bool {
        Config.нативнаяЛента && Config.нижниеВкладки && !WebBridge.shared.сайтВместоЛенты
    }

    /// Для корневого «открыть»: адрес открыт своим экраном — true; иначе false (дальше решает WebBridge.перейти).
    static func перехватить(_ адрес: URL) -> Bool {
        guard Config.нативныеСсылки else { return false }
        if let документ = документ(адрес) {
            ОкнаДокументов.показать(документ)
            return true
        }
        guard вкладкиЕсть, кабинет(адрес), let куда = NativeRouter.распознать(адрес) else { return false }
        /* Только разделы меню кабинета, у которых раньше не было своего экрана (доставки, аренды, обмены, «Счета»,
           «Акции», «Подписки»). /cabinet.php без параметров, ?go=items, ?deal=, ?go=wallet нативные экраны сами
           открывают как страницу сайта для денег (Config.деньгиКошелька, деньгиСделок) —
           перехватить их значило бы вернуть человека в тот же свой экран вместо оплаты. */
        switch куда {
        case .разделКабинета, .избранное: break
        default: return false
        }
        WebBridge.shared.лентаВидна = true
        NativeRouter.shared.цель = куда
        return true
    }

    /// Полный путь «открыть» для окон этого модуля: eGov, витрина продавца, свои окна, кабинет, сделки, кошелёк, лента;
    /// своего экрана нет — окно «недоступно» (WebBridge.перейти), не сайт.
    static func открыть(_ адрес: URL) {
        WebBridge.shared.перейти(адрес)
    }

    /**
     Цепочка корня приложения (RootWebView) без запасной страницы сайта: true — адрес открыт своим экраном. eGov —
     листом ОкноEgov (egov: false — пропустить: страница сайта уже в своём потоке), витрина продавца, свои окна, раздел
     кабинета, затем раздел ленты, «Работа» и поддержка (NativeRouter, этап 51). объявление: true — и
     /marketplace?item= нативной карточкой: так только ссылки внутри страницы сайта (WebContainer) и историй. Экраны
     приложения нарочно открывают объявление страницей сайта — там чат, сделка и оплата (WebBridge.открытьСнаружи).
     Первой — сделка с подписью eGov: /cabinet.php?eds=<id>[&t=] и /eds.php?action=go&t= (QR кода посылки или встречи) —
     своё окно сделки поверх всего (СделкиEDS), под ним «Мои сделки», как showDeals() сайта; раньше первое вело в корень
     «Кабинета», второе — в окно «недоступно».
     Следом — экран гостя с ?after=import|add|deals (и /cabinet?egov=1&after=… окна регистрации mkRegGate): вход или
     регистрация, затем перенос, подача или «Мои сделки» (.входЗатем, ВходПоСсылке), как у WebBridge.перейти. Раньше
     кнопка истории и ссылка страницы под слоем с таким адресом доставались ОкноEgov без перехода после регистрации или
     (egov: false, ?after= без eGov) уходили странице сайта.
     */
    static func своимЭкраном(_ адрес: URL, egov: Bool = true, объявление: Bool = false) -> Bool {
        if СделкиEDS.перехватить(адрес, подСписок: вкладкиЕсть) { return true }
        if войтиЗатем(адрес) { return true }
        if egov && ОкноEgov.перехватить(адрес) { return true }
        if ОкноПродавца.перехватить(адрес) { return true }
        if НативныеОкна.перехватить(адрес) { return true }
        if перехватить(адрес) { return true }
        return ссылкаЛенты(адрес, объявление: объявление)
    }

    /// /cabinet?after=<куда>[&egov=1] — целью .входЗатем на слое вкладок (NativeTabsView зовёт ВходПоСсылке.войтиЗатем:
    /// вошедшему — сразу туда, гостю — вход или eGov, затем туда). Прочие значения after сайт не знает (_AFTER_OK) — false.
    private static func войтиЗатем(_ адрес: URL) -> Bool {
        guard Config.нативныеСсылки, вкладкиЕсть, let куда = АдресаКабинета.цельПослеВхода(адреса: адрес),
              NativeRouter.доступна(куда) else { return false }
        WebBridge.shared.лентаВидна = true
        NativeRouter.shared.цель = куда
        return true
    }

    /// Раздел ленты, поиск, «Работа», поддержка (и объявление, если можно) — целью NativeRouter на слое вкладок.
    private static func ссылкаЛенты(_ адрес: URL, объявление: Bool) -> Bool {
        guard Config.нативныеСсылки, вкладкиЕсть, let куда = NativeRouter.распознать(адрес),
              NativeRouter.доступна(куда) else { return false }
        switch куда {
        case .найти, .вакансии, .поддержка:
            break
        case .объявление:
            if !объявление { return false }
        default:
            /* Кабинет и деньги — выше (перехватить) или страницей сайта, как было. */
            return false
        }
        WebBridge.shared.лентаВидна = true
        NativeRouter.shared.цель = куда
        return true
    }

    /**
     /cabinet.php без параметров. Снаружи (пуш, универсальная ссылка) это свой кабинет (.кабинет), а из окон приложения
     его зовут только кнопки «Открыть в кабинете на сайте» у денег — им нужна страница сайта (НативныеОкна).
     */
    static func кореньКабинета(_ адрес: URL) -> Bool {
        guard Config.deepLink(адрес.absoluteURL) != nil,
              let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: true),
              АдресаКабинета.кабинет(части.path) else { return false }
        return (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }.isEmpty
    }

    // MARK: - Разбор адреса

    /// Путь — страница кабинета (/cabinet.php, /cabinet, /kz/<язык>/cabinet(.php)).
    private static func кабинет(_ адрес: URL) -> Bool {
        guard let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: true) else { return false }
        return АдресаКабинета.кабинет(части.path)
    }

    /// Документ кабинета по адресу или nil.
    static func документ(_ адрес: URL) -> ДокументКабинета? {
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return nil }
        let параметры = части.queryItems ?? []
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        let действие = знач("action").lowercased()
        let номер = знач("id")
        guard !номер.isEmpty, номер.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            return nil
        }
        let путь = части.path
        let запрос = части.percentEncodedQuery.map { "?" + $0 } ?? ""
        if путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/escrow(\\.php)?$", options: .regularExpression) != nil {
            let заголовки: [String: String] = ["rental_contract": "doc_rent_contract", "rental_act": "doc_rent_act",
                                               "service_act": "doc_work_act", "warranty_card": "doc_warranty"]
            guard let ключ = заголовки[действие] else { return nil }
            return ДокументКабинета(заголовок: ДокументыText.т(ключ), источник: .путь(путь + запрос))
        }
        if АдресаКабинета.кабинет(путь) && действие == "rent_contract" {
            return ДокументКабинета(заголовок: ДокументыText.т("doc_rent_contract"), источник: .путь(путь + запрос))
        }
        return nil
    }

    // MARK: - Верхний контроллер

    /// Верхний показанный контроллер ключевого окна; nil — идёт показ или скрытие (подождать).
    static func верхнийКонтроллер() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first,
              var верх = окно.rootViewController else { return nil }
        while let следующий = верх.presentedViewController {
            if следующий.isBeingDismissed || следующий.isBeingPresented { return nil }
            верх = следующий
        }
        if верх.isBeingDismissed { return nil }
        return верх
    }
}
