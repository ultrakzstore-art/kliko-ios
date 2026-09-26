import Foundation
import SwiftUI
import UIKit

/**
 ЧАТ ПО ЛИДУ (Я ПРОДАВЕЦ) — МОДЕЛЬ, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Окно #lead-chat-modal кабинета сайта (openLeadChat, _lcmLoop, _lcmApply, lcmJoin, _lcmSendNow, lcmSetLabel, _lcmBlock*,
 reportUserModal, lcmOffer*, карта §6.4.9 и §4.13.1). Лид — чат по МОЕМУ объявлению: сначала покупателю отвечает Kliko
 AI-ассистент, продавец может подключиться и отвечать сам.

 Запросы (все пути — /kz/<язык>/chat.php; токен — только там, где его шлёт сайт):
   · GET  seller_chat&cid=<id>                     — открыть: переписка, товар, статус, метка, контакт горячего лида…;
   · GET  seller_chat&wait=1&cid=<id>&since=<count> — long-poll, пока экран открыт (первый раз since=-1, как у сайта);
   · POST seller_join {chat_id}                     — «Подключиться»;
   · POST seller_reply {chat_id, text}              — ответ;
   · POST typing {cid}                               — «печатает», не чаще раза в 2,5 с, пока человек пишет;
   · POST presence_event {cid, state}                — как сайт: при смене buyer_online в ответе опроса («back»/«left»)
                                                        и «left», когда приложение уходит в фон с открытым чатом
                                                        (у сайта — sendBeacon при скрытии вкладки);
   · POST set_label {chat_id, label}                 — метка диалога;
   · POST /kz/<язык>/subs.php?action=block|unblock {user_id, csrf} — заблокировать / разблокировать покупателя;
   · POST request_unblock {peer_id}                  — меня заблокировали: попросить разблокировать (раз в 72 ч);
   · POST /kz/<язык>/report.php?action=submit {target_id, listing_id: "", reason, comment, csrf} — жалоба;
   · POST offer_accept {csrf, chat_id}               — «Принять · N ₸» (цена согласована, денег не двигает);
   · POST offer_counter {csrf, chat_id, pct}         — встречная цена +5/10/15/20 %.
 🔴 ДЕНЬГИ: offer_decline {csrf, chat_id[, final: 1]} («Отказаться», «Цена окончательная») возвращает покупателю
 обеспечение предложения (карта §8.7) — только за Config.деньгиСделок (false), ровно один запрос, без повтора даже на
 «csrf». Выключен — ключ ulx_open_lead и страница «Чата» кабинета: сайт сам откроет этот лид-чат (§6.4.11).

 🔴 ОТЛИЧИЯ ОТ САЙТА, НАМЕРЕННЫЕ:
   · между запросами long-poll — не меньше секунды (у сайта 200 мс): если сервер вдруг ответит сразу, опрос не
     превратится в пять запросов в секунду (так же сделан deal_wait этапа 43);
   · сайт без сети кладёт ответ в очередь и сам отправляет при подключении. Здесь текст возвращается в поле с «Нет
     соединения» — отправит сам человек: запись без нажатия не уходит;
   · медиа, геолокация, быстрые ответы и межгород-доставка из этого окна — пока на сайте (кнопка «Открыть на сайте»).
 Всё — в памяти экрана.
 */
@MainActor
final class ЛидМодель: ObservableObject {
    let номер: String

    @Published private(set) var имя: String
    @Published private(set) var сообщения: [СообщениеЛида] = []
    /// ai | hot_lead | seller_active | closed.
    @Published private(set) var статус = ""
    @Published private(set) var метка = ""
    /// agreed_price — согласованная цена (после offer_accept).
    @Published private(set) var согласовано = 0
    @Published private(set) var товар: ТоварЛида? = nil
    @Published private(set) var продавецПроверен = true
    @Published private(set) var контакт: КонтактЛида? = nil
    @Published private(set) var присутствие = ""
    @Published private(set) var покупатель = ""
    @Published private(set) var заблокирован = false
    @Published private(set) var мнойЗаблокирован = false
    /// deal_id — покупатель уже оформил сделку.
    @Published private(set) var сделка = ""
    @Published private(set) var печатает = false
    @Published private(set) var загружено = false
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нетСвязи = false
    @Published private(set) var плашка: String? = nil
    @Published private(set) var отправляем = false
    /// Идёт запрос по нажатию (подключиться, метка, блок, предложение) — вторая кнопка ждёт.
    @Published private(set) var занято = false
    @Published var черновик = "" {
        didSet {
            if черновик != oldValue && !черновик.isEmpty { набор() }
        }
    }

    /// count последнего ответа (since следующего long-poll).
    private var счёт = -1
    private var онлайнБыл: Bool? = nil
    private var последнийНабор = Date.distantPast
    private var поколение = 0

    init(номер: String, имя: String, покупатель: String = "") {
        self.номер = номер
        self.имя = имя.isEmpty ? ИнбоксText.т("buyer") : имя
        self.покупатель = покупатель
    }

    /// Номер покупателя для шапки — его витрина (ОкноПродавца); негодный или пустой — nil, шапка не нажимается.
    var витринаПокупателя: String? {
        let номер = покупатель.trimmingCharacters(in: .whitespacesAndNewlines)
        return ВитринаПродавцаAPI.годный(номер) ? номер : nil
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }
    private typealias З = МоиОбъявленияAPI
    private var cid: String { ИнбоксAPI.вАдрес(номер) }

    // MARK: - Открыть и опрос

    /// openLeadChat: GET seller_chat. Не ok — «Ошибка», как у сайта.
    func начать() async {
        do {
            let j = try await ИнбоксAPI.получить("chat.php?action=seller_chat&cid=" + cid)
            guard let j, З.да(j["ok"]) else {
                ошибка = ИнбоксText.т("err_generic")
                загружено = true
                return
            }
            ошибка = nil
            применить(j)
            счёт = -1
        } catch {
            ошибка = ИнбоксAPI.текстСбоя(error)
        }
        загружено = true
    }

    /**
     _lcmLoop: long-poll, пока экран открыт (задача .task отменяется при уходе). Паузы — сайта: ответ пришёл — 0,2 с
     (печатает — 1,5 с; здесь не меньше секунды, см. шапку), ok:false — 5 с, access — стоп, чат закрыт — стоп, нет сети —
     4 с, приложение не активно или на экране страница сайта — 4 с.
     */
    func опрос() async {
        guard ошибка == nil else { return }
        while !Task.isCancelled {
            guard СделкиAPI.опросМожно else {
                await пауза(4)
                continue
            }
            let начало = Date()
            let хвост = "chat.php?action=seller_chat&wait=1&cid=" + cid + "&since=" + String(счёт)
            do {
                let j = try await ИнбоксAPI.получить(хвост, ждать: false)
                guard !Task.isCancelled else { return }
                нетСвязи = false
                guard let j else {
                    await пауза(5)
                    continue
                }
                if З.да(j["ok"]) {
                    if let n = j["count"] as? NSNumber { счёт = n.intValue }
                    применить(j)
                    if статус == "closed" { return }
                    let ждать: Double = печатает ? 1.5 : 1.0
                    let прошло = Date().timeIntervalSince(начало)
                    if прошло < ждать { await пауза(ждать - прошло) }
                } else {
                    if З.строка(j["error"]) == "access" { return }
                    await пауза(5)
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let сбой = error as? КабинетСайта.Сбой, сбой == .сеть { нетСвязи = true }
                await пауза(4)
            }
        }
    }

    private func пауза(_ секунд: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(max(0, секунд) * 1_000_000_000))
    }

    /// _lcmPoll: один внеочередной снимок (после ответа и действий с предложением).
    func обновить() async {
        guard let j = try? await ИнбоксAPI.получить("chat.php?action=seller_chat&cid=" + cid, ждать: false),
              З.да(j["ok"]) else { return }
        применить(j)
    }

    /// _lcmApply + _lcmSyncDeal + _lcmRenderMessages: только поля, которые пришли (сайт проверяет void 0 !== …).
    private func применить(_ j: [String: Any]) {
        if let чат = j["chat"] as? [String: Any] {
            let покупательИмя = З.строка(чат["buyer_name"])
            if !покупательИмя.isEmpty { имя = покупательИмя }
            if чат["label"] != nil { метка = З.строка(чат["label"]) }
            let новыйСтатус = З.строка(чат["status"])
            if !новыйСтатус.isEmpty { статус = новыйСтатус }
            if чат["agreed_price"] != nil { согласовано = max(0, З.целое(чат["agreed_price"])) }
            if let список = чат["messages"] as? [[String: Any]] {
                let новые = СообщениеЛида.разобрать(список)
                if новые != сообщения { сообщения = новые }
            }
            /* Последнее сообщение лида — сразу в его строку «Чата» (превью, время, место), непрочитанные гаснут:
               чат открыт. Лид сайт показывает без «Вы: ». */
            var последнее: ПоследнееВПереписке? = nil
            if let с = сообщения.last, !с.когда.isEmpty {
                последнее = ПоследнееВПереписке(текст: ЧатСообщение.подпись(тип: с.тип, текст: с.текст), моё: false,
                                                значок: nil, когда: с.когда)
            }
            ИнбоксМодель.shared.вПереписке(номера: [номер], последнее: последнее, прочитано: true)
        }
        if let п = j["product"] as? [String: Any] { товар = ТоварЛида(п) }
        if j["seller_verified"] != nil { продавецПроверен = З.да(j["seller_verified"]) }
        if j["buyer_contact"] != nil { контакт = КонтактЛида(j["buyer_contact"] as? [String: Any]) }
        if j["buyer_presence"] != nil { присутствие = З.строка(j["buyer_presence"]) }
        if j["buyer_online"] != nil {
            let онлайн = З.да(j["buyer_online"])
            /* _lcmApply сайта: смена buyer_online между ответами — presence_event "back" / "left". */
            if let был = онлайнБыл, был != онлайн { отправитьПрисутствие(онлайн ? "back" : "left") }
            онлайнБыл = онлайн
        }
        /* Пустой buyer_id известный номер (из строки инбокса) не стирает. */
        if j["buyer_id"] != nil {
            let номер = З.строка(j["buyer_id"])
            if !номер.isEmpty { покупатель = номер }
        }
        if j["blocked"] != nil {
            заблокирован = З.да(j["blocked"])
            мнойЗаблокирован = З.да(j["blocked_by_me"])
        }
        if j["deal_id"] != nil { сделка = З.строка(j["deal_id"]) }
        печатает = З.да(j["typing"])
    }

    // MARK: - Подзаголовок (_lcmSubtitle)

    var подзаголовок: String {
        if нетСвязи { return т("lcm_offline") }
        var s: String
        switch статус {
        case "ai": s = т("lcm_st_ai")
        case "hot_lead": s = т("lcm_st_hot")
        case "seller_active": s = т("lcm_st_active")
        case "closed": s = т("lcm_st_closed")
        default: s = статус
        }
        if !присутствие.isEmpty { s += String(format: т("lcm_presence"), присутствие) }
        return s
    }

    /// Полоса «Подключитесь, чтобы ответить лично» — пока статус не seller_active и не closed.
    var нужноПодключиться: Bool {
        загружено && ошибка == nil && статус != "seller_active" && статус != "closed"
    }

    // MARK: - Действия по нажатию

    /// lcmJoin: POST seller_join {chat_id} → «Вы подключились к чату ✓».
    func подключиться() async {
        guard !занято else { return }
        занято = true
        defer { занято = false }
        do {
            let j = try await ИнбоксAPI.отправитьБезТокена("chat.php?action=seller_join", тело: ["chat_id": номер])
            if З.да(j["ok"]) {
                статус = "seller_active"
                if let чат = j["chat"] as? [String: Any], let список = чат["messages"] as? [[String: Any]] {
                    сообщения = СообщениеЛида.разобрать(список)
                }
                показатьПлашку(т("lcm_joined"))
            } else {
                показатьПлашку(ИнбоксAPI.текстОшибки(j, запасной: т("err_generic")))
            }
        } catch {
            показатьПлашку(ИнбоксAPI.текстСбоя(error))
        }
    }

    /// _lcmSendNow: POST seller_reply {chat_id, text}. ok — снимок; blocked — плашка блокировки и текст обратно в поле.
    func отправить() async {
        let текст = черновик.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !текст.isEmpty, !отправляем else { return }
        отправляем = true
        черновик = ""
        defer { отправляем = false }
        do {
            let j = try await ИнбоксAPI.отправитьБезТокена("chat.php?action=seller_reply",
                                                           тело: ["chat_id": номер, "text": текст])
            if З.да(j["ok"]) {
                await обновить()
            } else if З.да(j["blocked"]) {
                заблокирован = true
                let сообщение = З.строка(j["msg"])
                показатьПлашку(сообщение.isEmpty ? т("lcm_blocked_send") : сообщение)
                if черновик.isEmpty { черновик = текст }
            } else {
                показатьПлашку(т("send_err"))
                if черновик.isEmpty { черновик = текст }
            }
        } catch {
            /* У сайта — очередь «отправлю при подключении»; здесь текст ждёт человека (см. шапку). */
            показатьПлашку(ИнбоксAPI.текстСбоя(error))
            if черновик.isEmpty { черновик = текст }
        }
    }

    /// _lcmTypingPing: пока человек пишет — не чаще раза в 2,5 с; ответ не читается.
    private func набор() {
        let сейчас = Date()
        guard сейчас.timeIntervalSince(последнийНабор) >= 2.5 else { return }
        последнийНабор = сейчас
        let тело: [String: Any] = ["cid": номер]
        Task { _ = try? await ИнбоксAPI.отправитьБезТокена("chat.php?action=typing", тело: тело, ждать: false) }
    }

    /// _lcmPresenceEvent: ответ не читается.
    private func отправитьПрисутствие(_ состояние: String) {
        let тело: [String: Any] = ["cid": номер, "state": состояние]
        Task {
            _ = try? await ИнбоксAPI.отправитьБезТокена("chat.php?action=presence_event", тело: тело, ждать: false)
        }
    }

    /// Приложение ушло в фон с открытым чатом — «left», как sendBeacon сайта при скрытии вкладки.
    func ушлиВФон() {
        guard загружено, ошибка == nil else { return }
        отправитьПрисутствие("left")
    }

    /// lcmSetLabel: POST set_label {chat_id, label} → «Метка сохранена ✓».
    func поставитьМетку(_ ключ: String) async {
        guard !занято else { return }
        занято = true
        defer { занято = false }
        let итог = await ИнбоксAPI.метка(ключ, лид: true, номер: номер)
        switch итог {
        case .готово:
            метка = ключ
            показатьПлашку(т("label_saved"))
        case .ошибка(let текст):
            показатьПлашку(текст)
        }
    }

    /// _lcmBlockBuyerDo — после вопроса «Заблокировать покупателя?».
    func заблокировать() async {
        guard !покупатель.isEmpty, !занято else { return }
        занято = true
        defer { занято = false }
        do {
            let j = try await ИнбоксAPI.отправить("subs.php?action=block", тело: ["user_id": покупатель])
            if З.да(j["ok"]) {
                заблокирован = true
                мнойЗаблокирован = true
                показатьПлашку(т("lcm_blocked_done"))
            } else {
                let текст = З.строка(j["error"])
                показатьПлашку(текст.isEmpty ? т("fail") : текст)
            }
        } catch {
            показатьПлашку(т("err_no_conn"))
        }
    }

    /// _lcmBlockAction: заблокировал я — unblock; заблокировали меня — request_unblock (без токена).
    func кнопкаБлокировки() async {
        guard !покупатель.isEmpty, !занято else { return }
        занято = true
        defer { занято = false }
        do {
            if мнойЗаблокирован {
                let j = try await ИнбоксAPI.отправить("subs.php?action=unblock", тело: ["user_id": покупатель])
                if З.да(j["ok"]) {
                    заблокирован = false
                    мнойЗаблокирован = false
                    показатьПлашку(т("lcm_unblocked"))
                } else {
                    let текст = З.строка(j["error"])
                    показатьПлашку(текст.isEmpty ? т("fail") : текст)
                }
            } else {
                let j = try await ИнбоксAPI.отправитьБезТокена("chat.php?action=request_unblock",
                                                               тело: ["peer_id": покупатель])
                if З.да(j["ok"]) {
                    показатьПлашку(т("lcm_unblock_sent"))
                } else {
                    let текст = З.строка(j["error"])
                    показатьПлашку(текст.isEmpty ? т("fail") : текст)
                }
            }
        } catch {
            показатьПлашку(т("err_no_conn"))
        }
    }

    enum ИтогЖалобы: Equatable {
        case отправлена
        case ошибка(String)
    }

    /// _repUSend: POST report.php?action=submit — ok (exists — «уже отправлена ранее»); auth — «Войдите…».
    func пожаловаться(причина: String, комментарий: String) async -> ИтогЖалобы {
        guard !покупатель.isEmpty else { return .ошибка(т("fail")) }
        do {
            let тело: [String: Any] = ["target_id": покупатель, "listing_id": "", "reason": причина,
                                       "comment": String(комментарий.prefix(600))]
            let j = try await ИнбоксAPI.отправить("report.php?action=submit", тело: тело)
            if З.да(j["ok"]) {
                показатьПлашку(т(З.да(j["exists"]) ? "rep_exists" : "rep_done"))
                return .отправлена
            }
            if З.нетСессии(j) { return .ошибка(т("rep_auth")) }
            let текст = З.строка(j["error"])
            return .ошибка(текст.isEmpty ? т("fail") : текст)
        } catch {
            return .ошибка(т("err_no_conn"))
        }
    }

    // MARK: - Предложение цены (§4.13.1)

    /// lcmOfferAccept: POST offer_accept {csrf, chat_id} → price — «Цена согласована: N ₸».
    func принятьПредложение() async {
        guard !занято else { return }
        занято = true
        defer { занято = false }
        do {
            let j = try await ИнбоксAPI.отправить("chat.php?action=offer_accept", тело: ["chat_id": номер])
            if З.да(j["ok"]) {
                согласовано = max(0, З.целое(j["price"]))
                показатьПлашку(т("of_ok") + ": " + СделкиФормат.тенге(З.целое(j["price"])))
                await обновить()
            } else {
                показатьПлашку(ИнбоксAPI.текстОшибки(j, запасной: т("send_err")))
            }
        } catch {
            показатьПлашку(т("no_conn"))
        }
    }

    /// lcmOfferCounter: POST offer_counter {csrf, chat_id, pct} → price — «Встречная цена отправлена: N ₸».
    func встречная(_ шаг: Int) async {
        guard !занято, ЛидМодель.шаги.contains(шаг) else { return }
        занято = true
        defer { занято = false }
        do {
            let j = try await ИнбоксAPI.отправить("chat.php?action=offer_counter", тело: ["chat_id": номер, "pct": шаг])
            if З.да(j["ok"]) {
                показатьПлашку(т("of_ctr_done") + ": " + СделкиФормат.тенге(З.целое(j["price"])))
                await обновить()
            } else {
                показатьПлашку(ИнбоксAPI.текстОшибки(j, запасной: т("send_err")))
            }
        } catch {
            показатьПлашку(т("no_conn"))
        }
    }

    /**
     🔴 «Отказаться» / «Цена окончательная» — offer_decline: обеспечение возвращается покупателю (деньги, §8.7). Только при
     Config.деньгиСделок; один запрос, без повтора и на «csrf» (токен — один раз, как есть). Выключен — сайт.
     */
    func отказ(окончательная: Bool) async -> Bool {
        guard Config.деньгиСделок else { return false }
        guard !занято else { return true }
        занято = true
        defer { занято = false }
        do {
            let токен = try await З.токенСейчас()
            guard !токен.isEmpty else {
                показатьПлашку(т("err_generic"))
                return true
            }
            var тело: [String: Any] = ["csrf": токен, "chat_id": номер]
            if окончательная { тело["final"] = 1 }
            let ответ = try await КабинетСайта.вызвать("chat.php?action=offer_decline", метод: "POST", тело: тело)
            guard let j = ответ.json else {
                показатьПлашку(т("err_generic"))
                return true
            }
            if З.да(j["ok"]) {
                if окончательная {
                    показатьПлашку(т("of_final_done"))
                } else {
                    показатьПлашку(т(З.да(j["refunded"]) ? "of_no_refund" : "of_no"))
                }
                await обновить()
            } else {
                показатьПлашку(ИнбоксAPI.текстОшибки(j, запасной: т("send_err")))
            }
        } catch {
            показатьПлашку(т("no_conn"))
        }
        return true
    }

    /**
     Денежная кнопка при выключенном рубильнике: ключ ulx_open_lead {cid, me, ts} — кабинет сайта при загрузке сам
     откроет этот лид-чат (восстановление, моложе часа, §6.4.11) — и страница «Чата» кабинета.
     */
    func открытьНаСайте(_ открыть: (URL) -> Void) async {
        let я = await ИнбоксAPI.мойНомер(ждать: false)
        let мс = Int(Date().timeIntervalSince1970 * 1000)
        let ключ: [String: Any] = ["cid": номер, "me": я, "ts": мс]
        if let данные = try? JSONSerialization.data(withJSONObject: ключ),
           let строка = String(data: данные, encoding: .utf8) {
            await КабинетСайта.положитьВХранилище("ulx_open_lead", строка)
        }
        if let адрес = Config.страницаСайта("cabinet.php?s=messages") { открыть(адрес) }
    }

    /// _lcmNudgeBuyer: в поле ввода — «Цена согласована — {sum}. Оформляйте безопасную сделку…».
    func напомнить() {
        черновик = т("of_nudge_msg").replacingOccurrences(of: "{sum}", with: СделкиФормат.тенге(согласовано))
    }

    /// _LCM_STEPS сайта.
    static let шаги: [Int] = [5, 10, 15, 20]

    /// _lcmCounterPrice: вверх до 100 ₸; не больше предложения или не меньше цены объявления — варианта нет (0).
    static func встречнаяЦена(_ цена: Int, шаг: Int, объявление: Int) -> Int {
        guard цена > 0, шаги.contains(шаг) else { return 0 }
        let сырая = Double(цена) * Double(100 + шаг) / 100.0 / 100.0
        let округлённая = Int(сырая.rounded(.up)) * 100
        if округлённая <= цена { return 0 }
        if объявление > 0 && округлённая >= объявление { return 0 }
        return округлённая
    }

    func показатьПлашку(_ текст: String) {
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard let self, self.плашка == текст else { return }
            withAnimation(ДвижениеСайта.уход) { self.плашка = nil }
        }
    }
}

// MARK: - Данные лид-чата

/// product ответа seller_chat.
struct ТоварЛида: Equatable {
    let id: String
    let фото: String
    let название: String
    let цена: Int
    let вАренду: Bool

    init(_ п: [String: Any]) {
        typealias З = МоиОбъявленияAPI
        id = З.строка(п["id"])
        фото = З.строка(п["img"])
        название = З.строка(п["title"])
        цена = max(0, З.целое(п["price"]))
        вАренду = З.да(п["for_rent"])
    }
}

/// buyer_contact {tel, disp, wa} — полоса «Горячий лид — свяжитесь сразу» (при непустом tel).
struct КонтактЛида: Equatable {
    let телефон: String
    let показ: String
    let whatsApp: String

    init?(_ к: [String: Any]?) {
        typealias З = МоиОбъявленияAPI
        guard let к else { return nil }
        let тел = З.строка(к["tel"])
        guard !тел.isEmpty else { return nil }
        телефон = тел
        показ = З.строка(к["disp"])
        whatsApp = З.строка(к["wa"])
    }
}

/// offer{} предложения покупателя (_lcmOfferCard).
struct ПредложениеЛида: Equatable {
    let цена: Int
    /// cash | inst | cred.
    let способ: String
    let срок: Int
    let заберёт: Bool
    let доставкаПокупателя: Bool
    let подкреплено: Int
    let отозвано: Bool
    let принято: Bool
    /// countered — я уже отправил встречную цену.
    let встречная: Int
}

/// counter{} моей встречной цены (_lcmCounterCard).
struct ВстречнаяЛида: Equatable {
    let цена: Int
    let база: Int
    let шаг: Int
    let принята: Bool
    let отклонена: Bool
    let устарела: Bool
}

/// Сообщение chat.messages[] (карта §6.4.10): role buyer | seller | ai | system; type geo | image | voice | video;
/// kind offer | counter; медиа и гео — на верхнем уровне (url, dur, exp, lat, lon); via "telegram".
struct СообщениеЛида: Identifiable, Equatable {
    let id: String
    let роль: String
    let текст: String
    let вид: String
    let тип: String
    let когда: String
    let изTelegram: Bool
    let широта: Double?
    let долгота: Double?
    let медиа: String
    let длительность: Int
    let предложение: ПредложениеЛида?
    let встречная: ВстречнаяЛида?
    /// Старые offer / counter перед последним offer — «Заменено новым предложением» (_replaced).
    var заменено: Bool = false

    /// Моё — продавца или ассистента (у сайта обе стороны «me»).
    var моё: Bool { роль == "seller" || роль == "ai" }

    /// Правило карты кабинета (§6.4.10) — общее с перепиской dm.php.
    var служебное: Bool { ЧатСообщение.этоУведомление(роль: роль, вид: вид, тип: тип, текст: текст) }

    /// Разбор списка и отметка «заменено» (_lcmRenderMessages).
    static func разобрать(_ список: [[String: Any]]) -> [СообщениеЛида] {
        var сообщения: [СообщениеЛида] = []
        for (i, м) in список.enumerated() {
            сообщения.append(СообщениеЛида(м, номер: i))
        }
        guard let последнее = сообщения.lastIndex(where: { $0.вид == "offer" }) else { return сообщения }
        for i in сообщения.indices where i < последнее {
            if сообщения[i].вид == "offer" || сообщения[i].вид == "counter" { сообщения[i].заменено = true }
        }
        return сообщения
    }

    init(_ м: [String: Any], номер: Int) {
        typealias З = МоиОбъявленияAPI
        роль = З.строка(м["role"])
        текст = З.строка(м["text"])
        вид = З.строка(м["kind"])
        тип = З.строка(м["type"])
        когда = З.строка(м["at"])
        изTelegram = З.строка(м["via"]) == "telegram"
        широта = СделкиAPI.координата(м["lat"])
        долгота = СделкиAPI.координата(м["lon"])
        медиа = З.строка(м["url"])
        длительность = З.целое(м["dur"])
        /* Номера у сообщения нет; лента только дописывается — место в ней и время его и различают. */
        id = String(номер) + "|" + когда + "|" + роль
        if вид == "offer", let o = м["offer"] as? [String: Any] {
            предложение = ПредложениеЛида(цена: З.целое(o["price"]), способ: З.строка(o["method"]),
                                          срок: З.целое(o["term"]), заберёт: З.да(o["pickup"]),
                                          доставкаПокупателя: З.да(o["ship_by_buyer"]),
                                          подкреплено: З.целое(o["funded"]), отозвано: З.да(o["withdrawn"]),
                                          принято: З.да(o["accepted"]), встречная: З.целое(o["countered"]))
        } else {
            предложение = nil
        }
        if вид == "counter", let c = м["counter"] as? [String: Any] {
            встречная = ВстречнаяЛида(цена: З.целое(c["price"]), база: З.целое(c["base"]), шаг: З.целое(c["pct"]),
                                      принята: З.да(c["accepted"]), отклонена: З.да(c["declined"]),
                                      устарела: З.да(c["superseded"]))
        } else {
            встречная = nil
        }
    }
}
