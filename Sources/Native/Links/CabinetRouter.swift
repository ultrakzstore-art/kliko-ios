import Foundation

/**
 АДРЕСА КАБИНЕТА — ЭТАП 40 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Пуш, универсальная ссылка или kliko://open?u= с адресом кабинета: /cabinet.php, /cabinet (после replaceState сайта),
 /kz/<язык>/cabinet(.php). Что значит каждый параметр — сводка роутера кабинета (карта §0.10). Есть нативный экран —
 NativeRouter откроет его, нет — nil, и адрес открывает страница сайта, как раньше: там он сработает целиком.

 Свой экран есть у переписки (?s=messages, ?go=messages — вкладка «Сообщения», этапы 3 и 38; с этапа 45 — единый инбокс
 кабинета), у «Моих объявлений» (?go=items, этап 41), у мастера подачи (?go=add и ?edit=<id>, этап 42), у сделок
 (?go=deals, ?s=deals, ?deal=<id>, этап 43), у «Заявок рядом» (?s=requests, ?go=requests, этап 45) и у переписки по
 обращению в поддержку (?ticket=<id>, этап 45). Остальное — страницей сайта, и так будет до своих этапов (§8):
   · ?go=items                                                — «Мои объявления» своим экраном (этап 41, Config.нативныеОбъявления);
   · ?go=add, ?edit=<id>                                      — мастер подачи и правки (этап 42, Config.нативнаяПодача);
   · ?promote=, ?top=, ?go=promote                            — покупка продвижения: в приложении не продаётся (без
                                                                покупок Apple, правило 3.1.1) — «Платные услуги»
                                                                сведениями, страница оплаты сайта не открывается;
   · ?go=import, ?go=aiimport                                 — перенос по ссылке и AI-импорт: свой МастерИмпорта
                                                                (НативныеОкна, этап 50);
   · ?go=deals, ?s=deals, ?deal=<id>                          — «Мои сделки» и карточка сделки своим экраном (этап 43,
                                                                Config.нативныеСделки; деньги в карточке — страницей сайта);
   · ?start_deal=, ?start_service=                            — создание сделки: этап 44, только за Config.деньгиСделок
                                                                (false) — иначе сайт; ?eds= (сделки eGov) — сайт;
   · ?topup=…&deal=                                           — возврат со шлюза по сделке: этап 44 за тем же рубильником
                                                                (pay.php?action=confirm);
   · ?topup=ok|fail (без deal и pro)                          — возврат с оплаты пополнения: этап 47, только за
                                                                Config.деньгиКошелька (false) — иначе сайт;
   · ?payout=back                                             — возврат со страницы банка выплаты: экран кошелька и
                                                                payout_outcome (этап 47, только чтение);
   · ?meet=, ?parcel=                                         — коды передачи: этап 44 за тем же рубильником, иначе сайт;
   · ?go=wallet                                               — экран кошелька (этап 47, Config.нативныйКошелёк; у сайта
                                                                ветки нет — главный экран, где кошелёк в шапке);
   · ?s=points                                                — «Баллы» своим экраном (этап 47);
   · ?open=password                                           — окно пароля своим экраном (этап 46,
                                                                Config.нативныеНастройки);
   · ?go=verify, ?go=egov                                     — верификация: eGov живёт на странице — сайт (46);
   · ?s=appear                                                — полный экран оформления сайта (скины, шрифты) — сайт;
   · ?s=requests, ?go=requests                                — «Заявки рядом» своим экраном (этап 45,
                                                                Config.нативныеСообщенияКабинета);
   · ?ticket=<id>                                             — переписка по обращению своим экраном (этап 45);
   · ?s=<раздел>, ?go=exchanges|deliveries                    — аренды, обмены, доставки, подписки — свои экраны
                                                                (.разделКабинета), аналитика и КП — окна НативныеОкна;
   · ?s=company                                               — сайт: этап 48 перенёс из «Компании» только сведения,
                                                                реквизиты, «Стать магазином» и список заказов B2B, а
                                                                ссылки сюда ведут к счетам и документам (их действия и
                                                                печать живут на странице), — строка «Счета» во
                                                                вкладке «Кабинет» открывает свой экран;
   · ?egov=1, ?egov_confirm=1, ?return=, ?bye=1               — только экран гостя (eGov — окно ОкноEgov);
   · ?after=import|add|deals (и с ?egov=1)                    — вход или регистрация, затем перенос, подача или сделки
                                                                (.входЗатем, ВходПоСсылке);
   · ?add=1                                                   — баннер «Продавайте на Kliko»: по роли (.продажа);
   · ?share=, ?social=, ?logout=                              — страница сайта (приём файлов, соцсети, выход с токеном).
 Адрес без параметров — тоже сайт: вошедшему нужен полный кабинет (объявления, сделки, кошелёк), а его нативного ещё нет.

 «КАБИНЕТ ПОЛНОСТЬЮ SWIFTUI» (владелец): адрес без параметров — корень вкладки «Кабинет» (.кабинет); ?s=deliveries,
 ?s=rentals, ?s=exchanges, ?go=deliveries, ?go=exchanges — свои экраны доставок, аренд и обменов; ?s=company — «Счета»;
 ?s=founder — «Акции»; ?s=subs — вкладка «Избранное»; ?s=appear — корень «Кабинета». Сайтом остаются только eGov
 (?egov=, ?go=verify — окно ОкноEgov) и деньги за своими рубильниками. Покупки ТОП/PRO (?promote=, ?top=,
 ?go=promote) ведут в «Платные услуги» (только сведения), а не на страницу оплаты сайта.
 */
enum АдресаКабинета {
    /// Путь — страница кабинета.
    static func кабинет(_ путь: String) -> Bool {
        путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil
    }

    /// Нативный экран для параметров адреса кабинета (метки utm_ уже убраны) или nil — страница сайта.
    static func цель(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
        if let деньги = цельДенег(параметры) { return деньги }
        if let кошелёк = цельКошелька(параметры) { return кошелёк }
        if let услуги = цельПлатныхУслуг(параметры) { return услуги }
        /* «Кабинет полностью SwiftUI»: адрес кабинета без параметров — корень вкладки «Кабинет», а не кабинет сайта. */
        if параметры.isEmpty { return Config.нативныйКабинет ? .кабинет : nil }
        /* ?after=import|add|deals (и с ?egov=1) — экран гостя: после входа туда (ВходПоСсылке.войтиЗатем). */
        if let после = цельПослеВхода(параметры) { return после }
        guard параметры.count == 1, let п = параметры.first else { return nil }
        let значение = (п.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch п.name {
        case "s", "go":
            if значение == "messages" && Config.нативныйЧат { return .сообщения }
            /* Этап 41: ?go=items — «Мои объявления» своим экраном во вкладке «Кабинет». */
            if п.name == "go" && значение == "items" && Config.нативныеОбъявления && Config.нативныйКабинет {
                return .моиОбъявления
            }
            /* Этап 42: ?go=add — мастер подачи поверх вкладок. */
            if п.name == "go" && значение == "add" && Config.нативнаяПодача { return .подача }
            /* Этап 43: ?go=deals и ?s=deals — «Мои сделки» своим экраном во вкладке «Кабинет». */
            if значение == "deals" && Config.нативныеСделки && Config.нативныйКабинет { return .сделки }
            /* Этап 45: ?s=requests и ?go=requests — «Заявки рядом» (у сайта оба ведут в showRequests). */
            if значение == "requests" && Config.нативныеСообщенияКабинета && Config.нативныйКабинет { return .заявки }
            /* Этап 47: ?go=wallet — экран кошелька; ?s=points — «Баллы» (showPoints модуля deals). */
            if п.name == "go" && значение == "wallet" && Config.нативныйКошелёк && Config.нативныйКабинет { return .кошелёк }
            if п.name == "s" && значение == "points" && Config.нативныйКошелёк && Config.нативныйКабинет { return .баллы }
            /* Разделы меню кабинета сайта (cabRoute), у которых теперь свои экраны в стеке вкладки «Кабинет». */
            if let раздел = разделМеню(значение, имя: п.name) { return раздел }
            return nil
        case "add":
            /* Баннер главной «Продавайте на Kliko» (a.mh-bn-s data-k="sell" href="/cabinet?add=1"): по роли, как кнопка
               продажи главной — мастер подачи, верификация или регистрация продавца через eGov. ?add=jobs — мастер
               «Работы» (НативныеОкна, раньше этого разбора). */
            guard значение == "1", Config.нативнаяПодача else { return nil }
            return .продажа
        case "open":
            /* Этап 46: ?open=password — openChangePassword сайта: окно пароля поверх кабинета. */
            guard значение == "password", Config.нативныеНастройки && Config.нативныйВход && Config.нативныйКабинет
            else { return nil }
            return .пароль
        case "ticket":
            /* Этап 45: ?ticket=<id> — openTicket(id) сайта. Номер — буквы, цифры, дефис, подчёркивание. */
            let номер = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            guard Config.нативныеСообщенияКабинета && Config.нативныйКабинет,
                  номер.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return nil }
            return .обращение(id: номер)
        case "deal":
            /* Этап 43: ?deal=<id> — карточка сделки (сайт: showDeals и через 350 мс openDeal). Номер — как у сайта,
               регистр важен («KLK-C2D0905C»). */
            let номер = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            guard Config.нативныеСделки && Config.нативныйКабинет, СделкиAPI.годныйНомер(номер) else { return nil }
            return .сделка(id: номер)
        case "edit":
            /* Этап 42: ?edit=<id> — правка тем же мастером. Номер — как у сайта (encodeURIComponent id), регистр важен. */
            let номер = (п.value ?? "").trimmingCharacters(in: .whitespaces)
            guard Config.нативнаяПодача,
                  номер.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else { return nil }
            return .правка(id: номер)
        default:
            return nil
        }
    }

    /**
     Экран гостя с ?after= (карта кабинета §1.1, _AFTER_OK сайта: { import: 'cabinet?go=import', add: 'cabinet?go=add',
     deals: 'cabinet?go=deals' }): после входа или регистрации — перенос объявлений, мастер подачи или «Мои сделки».
     Рядом бывает ?egov=1 — окно регистрации ленты (mkRegGate: /cabinet?egov=1&after=…): тогда сначала eGov. Прочие
     значения after сайт не знает — nil, адрес идёт своим путём.
     */
    static func цельПослеВхода(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
        let имена = Set(параметры.map { $0.name })
        guard имена.contains("after"), имена.isSubset(of: ["after", "egov", "bye"]),
              Config.нативныйВход && Config.нативныйКабинет else { return nil }
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        let хвосты = ["import": "cabinet?go=import", "add": "cabinet?go=add", "deals": "cabinet?go=deals"]
        guard let хвост = хвосты[знач("after").lowercased()], let адрес = Config.страницаСайта(хвост) else { return nil }
        return .входЗатем(адрес: адрес, egov: знач("egov") == "1")
    }

    /// Адрес кабинета с ?after= — для WebBridge.перейти раньше окна eGov (?egov=1&after= иначе забрал бы ОкноEgov без
    /// перехода после регистрации).
    static func цельПослеВхода(адреса адрес: URL) -> NativeRouter.Цель? {
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false),
              кабинет(части.path) else { return nil }
        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        return цельПослеВхода(параметры)
    }

    /**
     Покупки ТОП / PRO: ?promote=<id>, ?top=<id>, ?go=promote. Платные услуги в приложении не продаются (решение
     владельца, правило App Store 3.1.1) — свой экран «Платные услуги» (только сведения) или корень «Кабинета», но не
     страница оплаты сайта.
     */
    private static func цельПлатныхУслуг(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
        let покупка = параметры.contains { п in
            let значение = (п.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            return п.name == "promote" || п.name == "top" || (п.name == "go" && значение == "promote")
        }
        guard покупка, Config.нативныйКабинет else { return nil }
        return Config.нативныеПлатныеУслуги ? .разделКабинета(.платныеУслуги) : .кабинет
    }

    /**
     Разделы меню кабинета сайта: ?s=deliveries | rentals | exchanges | subs | company | founder | appear и ?go=deliveries |
     exchanges (карта §6.1.1–6.1.2). Доставки, аренды и обмены — свои экраны (CabinetPlus), «Подписки» — вкладка
     «Избранное» (избранное, поиски и продавцы — там и в «Кабинете»), «Счета» — ЭкранКомпании, «Акции» — клуб, «Оформление»
     — корень «Кабинета» (тема и язык — его разделы).
     */
    private static func разделМеню(_ значение: String, имя: String) -> NativeRouter.Цель? {
        guard Config.нативныйКабинет else { return nil }
        switch (имя, значение) {
        case (_, "deliveries"): return .разделКабинета(.доставки)
        case (_, "exchanges"): return .разделКабинета(.обмены)
        case ("s", "rentals"): return .разделКабинета(.аренды)
        case ("s", "subs"): return Config.избранное ? .избранное : nil
        case ("s", "company"): return Config.нативныйБизнес ? .разделКабинета(.компания) : nil
        case ("s", "founder"): return Config.нативныйБизнес ? .разделКабинета(.клуб) : nil
        case ("s", "appear"), ("s", "home"): return .кабинет
        default: return nil
        }
    }

    /**
     Этап 44 — ссылки денег сделок, только при Config.деньгиСделок (false) и своих «Моих сделках». Задание кладётся в
     ящик (ЗаданияДенегСделок), экран его забирает; распознать() зовётся только при входе снаружи (WebBridge), поэтому
     задание кладётся, только когда адрес действительно открывают. Выключено — nil, и адрес открывает страница сайта.
       · ?start_deal=<pid>[&pay=][&term=] и ?start_service=<pid> — «Мои сделки» и окно создания;
       · ?meet=<qr>, ?parcel=<token>                            — «Мои сделки» и «Вы точно получили товар?»;
       · ?topup=ok|fail&deal=<id>[&ship=1]                      — карточка сделки и сверка оплаты (без deal — кошелёк,
                                                                  этап 47, страница сайта).
     */
    private static func цельДенег(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
        guard Config.деньгиСделок && Config.нативныеСделки && Config.нативныйКабинет, !параметры.isEmpty else { return nil }
        let имена = Set(параметры.map { $0.name })
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces)
        }
        func годный(_ s: String) -> Bool {
            s.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil
        }
        if имена.contains("start_deal") && имена.isSubset(of: ["start_deal", "pay", "term"]) {
            let товар = знач("start_deal")
            guard годный(товар) else { return nil }
            /* (pay||"").replace(/[^a-z_]/gi,"").toLowerCase() и parseInt(term) сайта. */
            let оплата = String(знач("pay").filter { $0.isASCII && ($0.isLetter || $0 == "_") }).lowercased()
            let срок = Int(String(знач("term").prefix(while: { $0.isASCII && $0.isNumber }))) ?? 0
            ЗаданияДенегСделок.shared.положить(.сделка(товар: товар, оплата: оплата, срок: срок))
            return .сделки
        }
        if имена == ["start_service"] {
            let товар = знач("start_service")
            guard годный(товар) else { return nil }
            ЗаданияДенегСделок.shared.положить(.услуга(товар: товар))
            return .сделки
        }
        if имена == ["meet"] || имена == ["parcel"] {
            let встреча = имена.contains("meet")
            let токен = знач(встреча ? "meet" : "parcel")
            guard годный(токен) else { return nil }
            ЗаданияДенегСделок.shared.положить(.код(встреча: встреча, токен: токен))
            return .сделки
        }
        if имена.contains("topup") && имена.contains("deal") && имена.isSubset(of: ["topup", "deal", "ship"]) {
            let номер = знач("deal")
            guard СделкиAPI.годныйНомер(номер) else { return nil }
            let итог = ВозвратСоШлюза.Итог(оплачено: знач("topup") == "ok", сделка: номер, курьер: знач("ship") == "1")
            ЗаданияДенегСделок.shared.положить(.шлюз(итог))
            return .сделка(id: номер)
        }
        return nil
    }

    /**
     Этап 47 — возвраты со страниц банка для кошелька. Задание кладётся в ящик (ЗаданияКошелька), экран кошелька его
     забирает. ?payout=back — только чтение (payout_outcome), при своём кошельке; ?topup=ok|fail без deal и pro — сверка
     оплаты пополнения (pay.php?action=confirm), только при Config.деньгиКошелька: выключено — nil, страница сайта.
     */
    private static func цельКошелька(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
        guard Config.нативныйКошелёк && Config.нативныйКабинет, !параметры.isEmpty else { return nil }
        let имена = Set(параметры.map { $0.name })
        func знач(_ имя: String) -> String {
            (параметры.first(where: { $0.name == имя })?.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        }
        if имена == ["payout"] && знач("payout") == "back" {
            ЗаданияКошелька.shared.положить(.выплата)
            return .кошелёк
        }
        if имена == ["topup"] && Config.деньгиКошелька {
            let итог = знач("topup")
            guard итог == "ok" || итог == "fail" else { return nil }
            ЗаданияКошелька.shared.положить(.пополнение(оплачено: итог == "ok"))
            return .кошелёк
        }
        return nil
    }
}
