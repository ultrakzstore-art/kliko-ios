import Foundation
import SwiftUI
import UIKit

/**
 «ЗАЯВКИ РЯДОМ» — МОДЕЛЬ И ЗАПРОСЫ, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Экран #requests-screen кабинета (loadRequests, renderRequests, reqCardHTML, requestRespond, requestReport,
 reqAcceptDeal, _reqDoConfirm; карта §6.9.1): запросы клиентов по моей специальности поблизости, у открытой заявки —
 обратный отсчёт (5 минут), вкладки «Новые» / «Все».
   · GET  cabinet.php?action=my_requests&me_id=<me> → {ok, new, requests[]} — только чтение, без токена;
   · POST cabinet.php?action=request_action {csrf, act: "respond", rid}  — «Откликнуться» → открыть переписку с клиентом;
   · POST … {csrf, act: "report", rid} — «Скрыть» (сайт прячет заявку сразу и ответ не читает);
   · POST … {csrf, act: "accept", rid} — «Принять заказ» после вопроса «Принять заказ?»;
   · POST … {csrf, act: "confirm", rid, master_id} — «Закрепить за мастером» (карточка заявки в переписке клиента)
     после вопроса «Закрепить заказ за мастером?».
 «Сделка состоялась?» (checkPendingFeedback, fbSubmit): GET my_pending_feedback&me_id= → pending{rid, text, master_name};
 ответ — только по нажатию «Нет» / «Да, всё ок»: POST request_feedback {csrf, rid, done, comment}.
 Денег здесь нет. Всё в памяти; при выходе стирается.
 */
@MainActor
final class ЗаявкиМодель: ObservableObject {
    static let shared = ЗаявкиМодель()

    enum Фильтр: String, CaseIterable, Hashable {
        case new, all

        var название: String {
            switch self {
            case .new: return ИнбоксText.т("req_filter_new")
            case .all: return ИнбоксText.т("f_all")
            }
        }
    }

    @Published private(set) var заявки: [Заявка] = []
    @Published var фильтр: Фильтр = .new
    @Published private(set) var загружено = false
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нуженВход = false
    /// «Новых» — число у строки «Заявки рядом» в кабинете (reqSetNav: new ответа, дальше — reqNewCount).
    @Published private(set) var новых = 0
    @Published private(set) var сейчас = Date()
    @Published private(set) var плашка: String? = nil
    @Published private(set) var занято: Set<String> = []
    /// «Заявка уже неактивна» (_reqClosedInfo) на экране «Заявок»; карточка в переписке держит своё.
    @Published var неактивна = false

    /// Итог «Принять заказ» и «Закрепить за мастером».
    enum ИтогЗаявки: Equatable {
        case готово
        /// closed (у accept — и not assigned): окно «Заявка уже неактивна».
        case неактивна
        case нет
    }

    private var поколение = 0

    private init() {}

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }
    private typealias З = МоиОбъявленияAPI

    // MARK: - Загрузка

    /// loadRequests: отсчёт каждой открытой заявки — от seconds_left в момент ответа.
    func загрузить(ждать: Bool = true) async {
        let моё = поколение
        let я = await ИнбоксAPI.мойНомер(ждать: ждать)
        guard моё == поколение else { return }
        if я.isEmpty {
            let сессия = await SiteSession.состояние()
            if сессия.вошёл == false {
                нуженВход = true
                заявки = []
                новых = 0
                загружено = true
                return
            }
        }
        do {
            let j = try await ИнбоксAPI.получить("cabinet.php?action=my_requests&me_id=" + ИнбоксAPI.вАдрес(я),
                                                 ждать: ждать)
            guard моё == поколение else { return }
            guard let j else {
                ошибка = т("err_load")
                загружено = true
                return
            }
            if З.нетСессии(j) {
                нуженВход = true
                заявки = []
                новых = 0
            } else {
                нуженВход = false
                ошибка = nil
                let момент = Date()
                let скрытые = Set(заявки.filter { $0.скрыта }.map { $0.id })
                var новые: [Заявка] = []
                for r in (j["requests"] as? [[String: Any]]) ?? [] {
                    if var з = Заявка(r, момент: момент) {
                        if скрытые.contains(з.id) { з.скрыта = true }
                        новые.append(з)
                    }
                }
                заявки = новые
                сейчас = момент
                новых = max(0, З.целое(j["new"]))
            }
        } catch {
            guard моё == поколение else { return }
            ошибка = т("err_load")
        }
        загружено = true
    }

    /// Значок у строки кабинета (loadRequestsBadge) — фоном, страницу под слоем не трогает.
    func обновитьЗначок() async {
        let я = await ИнбоксAPI.мойНомер(ждать: false)
        guard !я.isEmpty,
              let j = try? await ИнбоксAPI.получить("cabinet.php?action=my_requests&me_id=" + ИнбоксAPI.вАдрес(я),
                                                    ждать: false),
              З.да(j["ok"]) else { return }
        новых = max(0, З.целое(j["new"]))
    }

    /// reqStartTicker: раз в секунду — отсчёт; истекла открытая — число «новых» пересчитывается.
    func тик() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            let былоНовых = новыхСейчас
            сейчас = Date()
            let сталоНовых = новыхСейчас
            if былоНовых != сталоНовых { новых = сталоНовых }
        }
    }

    /// reqNewCount: открытые, без моего отклика и не скрытые.
    private var новыхСейчас: Int {
        заявки.filter { $0.состояние(сейчас) == "open" && !$0.откликнулся && !$0.скрыта }.count
    }

    /// renderRequests: скрытые не показываются; «Новые» — открытые без моего отклика.
    var видимые: [Заявка] {
        заявки.filter { з in
            if з.скрыта { return false }
            if фильтр == .all { return true }
            return з.состояние(сейчас) == "open" && !з.откликнулся
        }
    }

    // MARK: - Действия по нажатию

    /// requestRespond: ok — «Отклик отправлен — общайтесь в «Чате»» и переписка с клиентом (openDM(client_id,
    /// ctx || rid, client_name)). closed / cap — список заново.
    func откликнуться(_ з: Заявка) async -> ЧатЦель? {
        guard !занято.contains(з.id) else { return nil }
        занято.insert(з.id)
        defer { занято.remove(з.id) }
        let моё = поколение
        do {
            let j = try await ИнбоксAPI.отправить("cabinet.php?action=request_action", тело: ["act": "respond", "rid": з.id])
            guard моё == поколение else { return nil }
            guard З.да(j["ok"]) else {
                let код = З.строка(j["error"])
                показатьПлашку(Self.текстОшибки(код))
                if код == "closed" || код == "cap" { await загрузить(ждать: false) }
                return nil
            }
            if let i = заявки.firstIndex(where: { $0.id == з.id }) {
                заявки[i].откликнулся = true
                заявки[i].откликов += 1
            }
            новых = новыхСейчас
            показатьПлашку(т("req_toast_responded"))
            let клиент = З.строка(j["client_id"])
            guard !клиент.isEmpty else { return nil }
            let контекст = З.строка(j["ctx"])
            let имя = З.строка(j["client_name"])
            return .продавец(id: клиент, имя: имя, объявление: контекст.isEmpty ? з.id : контекст)
        } catch {
            показатьПлашку(т("err_net"))
            return nil
        }
    }

    /// requestReport: сайт прячет заявку сразу и шлёт act "report", не читая ответа.
    func скрыть(_ з: Заявка) {
        if let i = заявки.firstIndex(where: { $0.id == з.id }) { заявки[i].скрыта = true }
        новых = новыхСейчас
        let rid = з.id
        Task { _ = try? await ИнбоксAPI.отправить("cabinet.php?action=request_action", тело: ["act": "report", "rid": rid]) }
    }

    /// _reqDoAccept (после «Принять заказ?»): ok — «Заказ принят — сделка подтверждена» и список заново; closed или
    /// not assigned — «Заявка уже неактивна».
    func принять(_ rid: String) async -> ИтогЗаявки {
        guard !занято.contains(rid) else { return .нет }
        занято.insert(rid)
        defer { занято.remove(rid) }
        do {
            let j = try await ИнбоксAPI.отправить("cabinet.php?action=request_action", тело: ["act": "accept", "rid": rid])
            if З.да(j["ok"]) {
                показатьПлашку(т("req_toast_accepted"))
                if загружено { await загрузить(ждать: false) }
                return .готово
            }
            let код = З.строка(j["error"])
            if код == "closed" || код == "not assigned" { return .неактивна }
            показатьПлашку(код.isEmpty ? т("err_generic") : код)
        } catch {
            показатьПлашку(т("err_net"))
        }
        return .нет
    }

    /// _reqDoConfirm (после «Закрепить заказ за мастером?»): ok — «Закреплено! Ждём подтверждения мастера»; closed —
    /// «Заявка уже неактивна»; not client / bad master — их тексты.
    func закрепить(_ rid: String, мастер: String) async -> ИтогЗаявки {
        guard !занято.contains(rid) else { return .нет }
        занято.insert(rid)
        defer { занято.remove(rid) }
        do {
            let j = try await ИнбоксAPI.отправить("cabinet.php?action=request_action",
                                                  тело: ["act": "confirm", "rid": rid, "master_id": мастер])
            if З.да(j["ok"]) {
                показатьПлашку(т("req_toast_pinned"))
                return .готово
            }
            let код = З.строка(j["error"])
            if код == "closed" { return .неактивна }
            показатьПлашку(Self.текстОшибки(код))
        } catch {
            показатьПлашку(т("err_net"))
        }
        return .нет
    }

    /// Коды ответа request_action → тексты сайта (req_err_*); незнакомый — как есть, пустой — «Ошибка».
    static func текстОшибки(_ код: String) -> String {
        switch код {
        case "closed": return ИнбоксText.т("req_err_closed")
        case "cap": return ИнбоксText.т("req_err_cap")
        case "expired": return ИнбоксText.т("req_err_expired")
        case "not recipient": return ИнбоксText.т("req_err_notyou")
        case "not client": return ИнбоксText.т("req_err_notclient")
        case "bad master": return ИнбоксText.т("req_err_nomaster")
        case "": return ИнбоксText.т("err_generic")
        default: return код
        }
    }

    func показатьПлашку(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.плашка == текст else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.плашка = nil }
        }
    }

    // MARK: - «Сделка состоялась?»

    /// Один раз за запуск приложения — как сайт при загрузке кабинета (через 1,5 с после неё).
    private var отзывСпрошен = false
    @Published var отзыв: ОжидаетОтзыва? = nil

    func проверитьОтзыв() async {
        guard !отзывСпрошен else { return }
        отзывСпрошен = true
        let моё = поколение
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let я = await ИнбоксAPI.мойНомер(ждать: false)
        guard !я.isEmpty, моё == поколение,
              let j = try? await ИнбоксAPI.получить("cabinet.php?action=my_pending_feedback&me_id=" + ИнбоксAPI.вАдрес(я),
                                                    ждать: false),
              З.да(j["ok"]), let p = j["pending"] as? [String: Any], моё == поколение else { return }
        let rid = З.строка(p["rid"])
        guard !rid.isEmpty else { return }
        отзыв = ОжидаетОтзыва(id: rid, текст: З.строка(p["text"]), мастер: З.строка(p["master_name"]))
    }

    /// fbSubmit: ответ сайт не читает; окно закрывается, «Спасибо за отзыв!» или «Спасибо, передали администрации».
    func ответитьНаОтзыв(_ о: ОжидаетОтзыва, состоялась: Bool, комментарий: String) async {
        let тело: [String: Any] = ["rid": о.id, "done": состоялась,
                                   "comment": комментарий.trimmingCharacters(in: .whitespacesAndNewlines)]
        do {
            _ = try await ИнбоксAPI.отправить("cabinet.php?action=request_feedback", тело: тело)
            отзыв = nil
            показатьПлашку(т(состоялась ? "fb_thanks" : "fb_passed"))
        } catch {
            отзыв = nil
        }
    }

    // MARK: - Выход

    func стереть() {
        поколение += 1
        заявки = []
        фильтр = .new
        загружено = false
        ошибка = nil
        нуженВход = false
        новых = 0
        плашка = nil
        занято = []
        неактивна = false
        отзыв = nil
        отзывСпрошен = false
    }
}

/// pending ответа my_pending_feedback.
struct ОжидаетОтзыва: Identifiable, Equatable {
    let id: String
    let текст: String
    let мастер: String
}

/// requests[] ответа my_requests (reqCardHTML).
struct Заявка: Identifiable, Equatable {
    let id: String
    let статус: String
    /// Момент, когда открытая заявка истекает (_deadline = сейчас + seconds_left).
    let срок: Date
    var откликнулся: Bool
    var откликов: Int
    let мне: Bool
    let нуженОтвет: Bool
    let клиент: String
    let имя: String
    let телефон: String
    let адрес: String
    let широта: Double
    let долгота: Double
    let текст: String
    let когда: String
    let город: String
    let специальность: String
    let объявлениеID: String
    let объявление: String
    let фото: String
    var скрыта = false

    init?(_ r: [String: Any], момент: Date) {
        typealias З = МоиОбъявленияAPI
        let rid = З.строка(r["rid"])
        guard !rid.isEmpty else { return nil }
        id = rid
        статус = З.строка(r["eff_status"])
        срок = момент.addingTimeInterval(Double(max(0, З.целое(r["seconds_left"]))))
        откликнулся = З.да(r["i_responded"])
        откликов = З.целое(r["responses"])
        мне = З.да(r["assigned_to_me"])
        нуженОтвет = З.да(r["needs_accept"])
        клиент = З.строка(r["client_id"])
        имя = З.строка(r["client_name"])
        телефон = З.строка(r["client_phone"])
        адрес = З.строка(r["client_address"]).trimmingCharacters(in: .whitespaces)
        широта = СделкиAPI.координата(r["client_lat"]) ?? 0
        долгота = СделкиAPI.координата(r["client_lon"]) ?? 0
        текст = З.строка(r["text"])
        когда = З.строка(r["at"])
        город = З.строка(r["city"])
        специальность = З.строка(r["specialty_label"])
        объявлениеID = З.строка(r["item_id"])
        объявление = З.строка(r["item_title"])
        фото = З.строка(r["item_img"])
    }

    /// reqLeftSec.
    func осталось(_ сейчас: Date) -> Int {
        max(0, Int(срок.timeIntervalSince(сейчас).rounded()))
    }

    /// reqEff: открытая с истёкшим отсчётом — expired.
    func состояние(_ сейчас: Date) -> String {
        if статус == "open" && осталось(сейчас) <= 0 { return "expired" }
        return статус
    }

    /// reqFmtLeft: «м:сс».
    static func отсчёт(_ секунд: Int) -> String {
        let с = секунд % 60
        return String(секунд / 60) + ":" + (с < 10 ? "0" : "") + String(с)
    }
}
