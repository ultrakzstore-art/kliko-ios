import Foundation
import UIKit
import UserNotifications

/**
 ОТВЕТ ПРЯМО ИЗ УВЕДОМЛЕНИЯ (владелец 07.10.2026: «сделай всё, что предлагаешь»).

 Пуш о новом сообщении — личная переписка (type "dm", tid) и чат по объявлению (type "chat" | "lead" | "buychat", cid) —
 получает две кнопки: «Ответить» (поле ввода) и «Прочитано». Приложение не открывается: iOS будит его в фоне, ответ
 уходит теми же запросами сайта, что у экранов чата, под beginBackgroundTask, и только потом зовётся completionHandler.

 Запросы (как у экранов):
   · личная — dm.php {action: "send", me_id, thread_id, text} (ChatAPI.написать); прочитано — dm.php?action=poll&tid=
     (сервер помечает переписку прочитанной, как при открытии);
   · лид, я продавец — chat.php?action=seller_reply {chat_id, text} (ЛидМодель.отправить); прочитано — seller_chat&cid=;
   · чат по объявлению, я покупатель — chat.php?action=buyer_chat&cid= (заодно помечает прочитанным и даёт номер
     объявления) и chat.php?action=send {pid, text} (ЧатОбъявленияAPI.написать, как МодельЧатаОбъявления.отправить).
   Кто я в чате cid, пуш не говорит («lead» приходит и продавцу, и покупателю): сначала buyer_chat — ответ «access»
   значит, что я продавец.

 ТРАНСПОРТ. Из уведомления приложение поднимается без окна, страницы сайта под слоем нет — fetch из неё не сработает.
 Поэтому сперва НативныйТранспортКабинета (URLSession с куками WebKit, как у Config.нативнаяСессия), и лишь если сессию
 он не узнал — прежний путь через страницу (бывает, когда приложение и так живо). Запись не повторяется: оборвалась
 связь после отправки — считаем «не отправлено» и просим открыть чат.

 🔴 СЕРВЕР. Кнопки iOS показывает только у пуша, в aps которого стоит category с именем ниже (категорияСообщения).
 inc/apns.php сайта (apns_send_token) её пока не ставит — до правки сайта кнопок не будет, всё остальное работает как
 раньше. Нужная строка — рядом с thread-id для чат-типов: $aps['aps']['category'] = 'KLIKO_MESSAGE'.
 */
@MainActor
enum ОтветИзУведомления {

    /// Имя категории — его же ставит сервер в aps.category.
    static let категорияСообщения = "KLIKO_MESSAGE"
    /// Действия кнопок; те же строки сверяет обработать() без актора.
    private static let действиеОтветить = "kliko.reply"
    private static let действиеПрочитано = "kliko.read"

    // MARK: - Регистрация

    /// На запуске, до первого пуша. Чужие категории (если появятся) не стираем — добавляем свою к ним.
    static func зарегистрировать() {
        let ответ = UNTextInputNotificationAction(identifier: действиеОтветить,
                                                  title: т("reply"),
                                                  options: [.authenticationRequired],
                                                  textInputButtonTitle: т("send"),
                                                  textInputPlaceholder: т("placeholder"))
        let прочитано = UNNotificationAction(identifier: действиеПрочитано, title: т("read"), options: [])
        let категория = UNNotificationCategory(identifier: категорияСообщения,
                                               actions: [ответ, прочитано],
                                               intentIdentifiers: [],
                                               options: [])
        let центр = UNUserNotificationCenter.current()
        let имя = категорияСообщения
        центр.getNotificationCategories { есть in
            var все = есть.filter { $0.identifier != имя }
            все.insert(категория)
            центр.setNotificationCategories(все)
        }
    }

    // MARK: - Нажатие

    /// Наше ли это действие. Да — сделает работу в фоне и сам позовёт готово(); нет — false, решает AppDelegate.
    /// Без актора: делегат уведомлений зовёт его синхронно; вся работа — в задаче на главном акторе.
    nonisolated static func обработать(_ ответ: UNNotificationResponse, готово: @escaping () -> Void) -> Bool {
        let действие = ответ.actionIdentifier
        guard действие == "kliko.reply" || действие == "kliko.read" else { return false }
        let инфо = ответ.notification.request.content.userInfo
        let текст = ((ответ as? UNTextInputNotificationResponse)?.userText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ответить = действие == "kliko.reply"
        Task { @MainActor in
            await выполнить(ответить: ответить, текст: текст, инфо: инфо)
            готово()
        }
        return true
    }

    /// Фоновое задание держит приложение живым, пока запрос в пути (iOS даёт около 30 с).
    private final class ФоновоеЗадание {
        var номер = UIBackgroundTaskIdentifier.invalid
    }

    private static func выполнить(ответить: Bool, текст: String, инфо: [AnyHashable: Any]) async {
        guard let чат = Чат(инфо) else { return }
        let фон = ФоновоеЗадание()
        фон.номер = UIApplication.shared.beginBackgroundTask(withName: "kliko.reply") {
            UIApplication.shared.endBackgroundTask(фон.номер)
            фон.номер = .invalid
        }
        if ответить {
            if !текст.isEmpty {
                let ушло = await сТаймаутом(25) { await отправить(текст, в: чат) }
                if !ушло { неОтправлено(инфо) }
            }
        } else {
            _ = await сТаймаутом(20) { await прочитать(чат) }
        }
        /* Списки «Чата» и число на иконке — заново, если приложение живо. */
        NotificationCenter.default.post(name: .klikoПушПришёл, object: nil)
        if фон.номер != .invalid {
            UIApplication.shared.endBackgroundTask(фон.номер)
            фон.номер = .invalid
        }
    }

    // MARK: - Какой чат

    private enum Чат {
        case личный(String)
        case объявления(String)

        init?(_ инфо: [AnyHashable: Any]) {
            let тип = (инфо["type"] as? String) ?? ""
            func строка(_ ключ: String) -> String {
                guard let v = инфо[ключ] else { return "" }
                return "\(v)".trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if тип == "dm", !строка("tid").isEmpty {
                self = .личный(строка("tid"))
            } else if ["chat", "lead", "buychat"].contains(тип) {
                let cid = строка("cid").isEmpty ? строка("chat_id") : строка("cid")
                guard !cid.isEmpty else { return nil }
                self = .объявления(cid)
            } else {
                return nil
            }
        }
    }

    // MARK: - Работа

    private static func отправить(_ текст: String, в чат: Чат) async -> Bool {
        switch чат {
        case .личный(let tid):
            var тело: [String: Any] = ["action": "send", "thread_id": tid, "text": текст]
            let я = await ИнбоксAPI.номерБыстро()
            if !я.isEmpty { тело["me_id"] = я }
            guard let j = await запрос("dm.php", метод: "POST", тело: тело) else { return false }
            return да(j["ok"])
        case .объявления(let cid):
            let адрес = "chat.php?action=buyer_chat&cid=" + ИнбоксAPI.вАдрес(cid)
            guard let j = await запрос(адрес, метод: "GET", тело: nil) else { return false }
            if да(j["ok"]) {
                guard let товар = j["product"] as? [String: Any], let pid = товар["id"].map({ "\($0)" }),
                      !pid.isEmpty else { return false }
                if case .готово = await ЧатОбъявленияAPI.написать(объявление: pid, текст: текст,
                                                                  предложение: nil, позвать: false) {
                    return true
                }
                return false
            }
            guard (j["error"] as? String) == "access" else { return false }
            guard let о = await запрос("chat.php?action=seller_reply", метод: "POST",
                                       тело: ["chat_id": cid, "text": текст]) else { return false }
            return да(о["ok"])
        }
    }

    private static func прочитать(_ чат: Чат) async -> Bool {
        switch чат {
        case .личный(let tid):
            var адрес = "dm.php?action=poll&tid=" + ИнбоксAPI.вАдрес(tid)
            let я = await ИнбоксAPI.номерБыстро()
            if !я.isEmpty { адрес += "&me_id=" + ИнбоксAPI.вАдрес(я) }
            return await запрос(адрес, метод: "GET", тело: nil) != nil
        case .объявления(let cid):
            let номер = ИнбоксAPI.вАдрес(cid)
            if let j = await запрос("chat.php?action=buyer_chat&cid=" + номер, метод: "GET", тело: nil),
               да(j["ok"]) {
                return true
            }
            return await запрос("chat.php?action=seller_chat&cid=" + номер, метод: "GET", тело: nil) != nil
        }
    }

    /// Запрос к /kz/<язык>/<хвост>: сначала без страницы, иначе страницей (если она есть). nil — сбой или не JSON.
    private static func запрос(_ хвост: String, метод: String, тело: [String: Any]?) async -> [String: Any]? {
        var строкаТела = ""
        if let тело, let данные = try? JSONSerialization.data(withJSONObject: тело) {
            строкаТела = String(decoding: данные, as: UTF8.self)
        }
        let видТела: НативныйТранспортКабинета.Тело = метод == "POST" ? .json(строкаТела) : .нет
        switch await НативныйТранспортКабинета.выполнить(путьСайта(хвост), метод: метод, тело: видТела) {
        case .ответ(_, let текст):
            return разобрать(текст)
        case .сеть(let отправлен):
            if отправлен && метод != "GET" { return nil }
        case .черезСтраницу:
            break
        }
        guard let ответ = try? await КабинетСайта.вызвать(хвост, метод: метод, тело: тело, ждать: false) else {
            return nil
        }
        return ответ.json
    }

    /// «/kz/<язык>/<хвост>» — тот же путь, что КабинетСайта строит для fetch страницы.
    private static func путьСайта(_ хвост: String) -> String {
        guard let полный = Config.страницаСайта(хвост),
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return "/kz/ru/" + хвост }
        let запрос = части.percentEncodedQuery.map { "?" + $0 } ?? ""
        return части.percentEncodedPath + запрос
    }

    private static func разобрать(_ текст: String) -> [String: Any]? {
        guard let данные = текст.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any]
    }

    private static func да(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue != 0 }
        if let текст = значение as? String { return текст == "1" || текст == "true" }
        return false
    }

    /// Работа или срок — что раньше. Работу не обрываем (запись могла уйти), просто перестаём ждать.
    private static func сТаймаутом(_ секунд: UInt64, _ работа: @escaping @MainActor () async -> Bool) async -> Bool {
        final class Однажды { var было = false }
        let флаг = Однажды()
        return await withCheckedContinuation { (продолжение: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                let итог = await работа()
                if !флаг.было { флаг.было = true; продолжение.resume(returning: итог) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: секунд * 1_000_000_000)
                if !флаг.было { флаг.было = true; продолжение.resume(returning: false) }
            }
        }
    }

    /// «Не отправлено — откройте чат»: тап ведёт туда же, куда вёл исходный пуш (его url).
    private static func неОтправлено(_ исходное: [AnyHashable: Any]) {
        let содержимое = UNMutableNotificationContent()
        содержимое.title = т("failed_t")
        содержимое.body = т("failed_b")
        содержимое.sound = .default
        var инфо: [AnyHashable: Any] = [:]
        for ключ in ["url", "type", "cid", "tid"] {
            if let v = исходное[ключ] { инфо[ключ] = v }
        }
        содержимое.userInfo = инфо
        let запрос = UNNotificationRequest(identifier: "kliko.reply.failed." + UUID().uuidString,
                                           content: содержимое, trigger: nil)
        UNUserNotificationCenter.current().add(запрос)
    }

    // MARK: - Тексты

    private static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["reply": "Ответить", "send": "Отправить", "placeholder": "Сообщение", "read": "Прочитано",
               "failed_t": "Не отправлено", "failed_b": "Ответ не ушёл — откройте чат"],
        "kk": ["reply": "Жауап беру", "send": "Жіберу", "placeholder": "Хабарлама", "read": "Оқылды",
               "failed_t": "Жіберілмеді", "failed_b": "Жауап кетпеді — чатты ашыңыз"],
        "en": ["reply": "Reply", "send": "Send", "placeholder": "Message", "read": "Mark as read",
               "failed_t": "Not sent", "failed_b": "Your reply wasn't sent — open the chat"]
    ]
}
