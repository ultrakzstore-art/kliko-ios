import Foundation

/**
 АДРЕСА КАБИНЕТА — ЭТАП 40 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Пуш, универсальная ссылка или kliko://open?u= с адресом кабинета: /cabinet.php, /cabinet (после replaceState сайта),
 /kz/<язык>/cabinet(.php). Что значит каждый параметр — сводка роутера кабинета (карта §0.10). Есть нативный экран —
 NativeRouter откроет его, нет — nil, и адрес открывает страница сайта, как раньше: там он сработает целиком.

 Свой экран есть у переписки (?s=messages, ?go=messages — вкладка «Сообщения», этапы 3 и 38), у «Моих объявлений»
 (?go=items, этап 41) и у мастера подачи (?go=add и ?edit=<id>, этап 42). Остальное — страницей сайта, и так будет до
 своих этапов (§8):
   · ?go=items                                                — «Мои объявления» своим экраном (этап 41, Config.нативныеОбъявления);
   · ?go=add, ?edit=<id>                                      — мастер подачи и правки (этап 42, Config.нативнаяПодача);
   · ?promote=, ?top=                                         — продвижение (48, деньги) — сайт;
   · ?go=import, ?go=aiimport                                 — перенос по ссылке и AI-импорт: модуль aiimport — сайт;
   · ?go=deals, ?s=deals, ?deal=, ?start_deal=, ?start_service=, ?eds= — сделки (43–44, деньги — Config.деньгиСделок);
   · ?topup=, ?payout=                                        — возвраты со шлюза: pay.php?action=confirm и payout_outcome
                                                                зовёт страница сайта (деньги — не трогать нативно);
   · ?go=wallet                                               — кошелёк (47);
   · ?go=verify, ?go=egov, ?open=password                     — профиль и верификация (46);
   · ?s=<раздел>, ?go=exchanges|requests|deliveries           — разделы (45);
   · ?egov=1, ?egov_confirm=1, ?after=, ?return=, ?bye=1      — только экран гостя (eGov живёт на странице);
   · ?meet=, ?parcel=, ?ticket=, ?share=, ?social=, ?logout=  — страница сайта (коды сделок, поддержка, выход с токеном).
 Адрес без параметров — тоже сайт: вошедшему нужен полный кабинет (объявления, сделки, кошелёк), а его нативного ещё нет.
 */
enum АдресаКабинета {
    /// Путь — страница кабинета.
    static func кабинет(_ путь: String) -> Bool {
        путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil
    }

    /// Нативный экран для параметров адреса кабинета (метки utm_ уже убраны) или nil — страница сайта.
    static func цель(_ параметры: [URLQueryItem]) -> NativeRouter.Цель? {
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
            return nil
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
}
