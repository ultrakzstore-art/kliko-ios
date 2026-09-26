import Foundation
import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — СОСТОЯНИЕ И ДЕЙСТВИЯ, ЭТАП 41 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Порядок как у главного экрана кабинета сайта (showMain → loadMyItems, карта §3): страница кабинета (токен, IS_SHOP,
 ADV_STATUS_LABEL, CAB_AI) → my_items → блок «Работа». После каждого действия список перечитывается, как loadMyItems()
 у сайта.

 🔴 ОШИБКИ САЙТА НЕ ПЕРЕНОСИМ (§3.8, §8.0.6):
   · после ошибки activate_item сайт не останавливает опрос item_status, и через ~40 с всплывает ложное «Объявление на
     проверке». Здесь опрос начинается только после ответа «ok» и кончается вместе с окном;
   · сайт сам шлёт тихий mod_recheck("") через 1,2 с после загрузки, если есть объявления на проверке. Это запись без
     нажатия — натив её не делает: «Проверить сейчас» только по кнопке;
   · статус ai_check у сайта не попадает ни в одну вкладку — здесь он в «Неактивных» (МоёОбъявление.во).

 Данные — одного человека: при выходе стираются (ВыходНачисто), при входе другим аккаунтом — сбрасываются.
 */
@MainActor
final class МоиОбъявленияМодель: ObservableObject {
    static let shared = МоиОбъявленияМодель()

    enum Загрузка: Equatable {
        case нет
        case идёт
        case готово
        /// Список не пришёл: «Ошибка загрузки» или «Нет соединения», как у сайта.
        case ошибка(String)
        /// Сессии нет — экран предлагает войти.
        case нуженВход
    }

    /// Окна поверх списка — те же, что #mod-overlay и окна подтверждения сайта.
    enum Окно: Equatable {
        /// «Kliko AI проверяет объявление»: шаг и проценты.
        case проверка(шаг: String, процент: Int)
        /// «Отлично!» с отсчётом «Хорошо · 5с».
        case одобрено(секунд: Int)
        /// «Объявление отклонено» с причиной.
        case отклонено(String)
        /// «Объявление на проверке» — 20 опросов прошли без итога.
        case ждём
        /// «Kliko AI-модерация заблокирована»: часы и объявление для «Отправить на ручную проверку» (nil — без кнопки).
        case блокИИ(часы: String, id: String?)
        /// «Запрещённый контент» / «Kliko AI заблокирован» / «Фото не загружено».
        case запрещено(заголовок: String, текст: String)
        /// «Нужна верификация» — текст сервера.
        case верификация(String)
        /// «Вы достигли лимита!» (verify_required) или просто лимит — текст сервера.
        case лимит(текст: String, верификация: Bool)
        /// «{n} ждут этот товар».
        case ждутТовар(id: String, сколько: Int)
    }

    @Published private(set) var товары: [МоёОбъявление] = []
    @Published private(set) var слоты: СлотыОбъявлений? = nil
    @Published private(set) var работа: [МояРабота] = []
    @Published private(set) var кабинет: КабинетСайта.Состояние? = nil
    @Published private(set) var загрузка: Загрузка = .нет
    @Published var вкладка: ВкладкаОбъявлений = .published {
        didSet { UserDefaults.standard.set(вкладка.rawValue, forKey: Self.ключВкладки) }
    }
    @Published var запрос: String = ""
    @Published var окно: Окно? = nil
    @Published private(set) var плашка: String? = nil
    /// Объявления, по которым идёт запрос: их кнопки неактивны, второй раз то же не уйдёт.
    @Published private(set) var занято: Set<String> = []
    /// Идёт mod_recheck — все «Проверить сейчас» неактивны, как у сайта (_advRecheckRun).
    @Published private(set) var проверяем = false

    /// Последняя вкладка — как localStorage.kliko_adv_tab сайта; стирается при выходе.
    static let ключВкладки = "kliko_adv_tab"

    private var uid = ""
    private var грузим = false
    private var ещёРаз = false
    /// Растёт при стирании: ответ, пришедший после выхода, в чистый экран не ляжет.
    private var поколение = 0
    private var шаги: Task<Void, Never>? = nil
    private var отсчёт: Task<Void, Never>? = nil

    private init() {
        if let было = UserDefaults.standard.string(forKey: Self.ключВкладки),
           let вкладка = ВкладкаОбъявлений(rawValue: было) {
            self.вкладка = вкладка
        }
    }

    private func т(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    // MARK: - Что на экране

    /// Объявления выбранной вкладки под поиском — порядок сервера (клиент сайта не сортирует, §3.1.4).
    var видимые: [МоёОбъявление] {
        let сейчас = Date().timeIntervalSince1970
        return товары.filter { $0.во(вкладка, сейчас: сейчас) && $0.подходит(запрос) }
    }

    // MARK: - Загрузка

    /**
     страницу = true — сначала страница кабинета (вход, токен, IS_SHOP, CAB_AI): при показе экрана и «потянуть вниз».
     false — только my_items: после действия. Пока идёт одна загрузка, вторая не начинается, а повторяется следом.
     */
    func загрузить(страницу: Bool) async {
        if грузим {
            ещёРаз = true
            return
        }
        грузим = true
        defer { грузим = false }
        var читатьСтраницу = страницу
        repeat {
            ещёРаз = false
            await загрузитьОдинРаз(страницу: читатьСтраницу || кабинет == nil)
            читатьСтраницу = false
        } while ещёРаз
    }

    private func загрузитьОдинРаз(страницу: Bool) async {
        var моё = поколение
        if товары.isEmpty { загрузка = .идёт }
        do {
            if страницу {
                let страница = try await КабинетСайта.состояние()
                guard моё == поколение else { return }
                if страница.вошёл == false {
                    сброситьДанные()
                    загрузка = .нуженВход
                    return
                }
                /* Вошёл другой человек — чужой список не показываем ни секунды. */
                if !страница.uid.isEmpty && страница.uid != uid {
                    if !uid.isEmpty {
                        сброситьДанные()
                        моё = поколение          // эта загрузка — уже для нового человека
                        загрузка = .идёт
                    }
                    uid = страница.uid
                }
                кабинет = страница
                МоиОбъявленияAPI.запомнитьТокен(страница.csrf)
            }
            guard let j = try await МоиОбъявленияAPI.получить("cabinet.php?action=my_items") else {
                throw КабинетСайта.Сбой.приложение
            }
            guard моё == поколение else { return }
            if !МоиОбъявленияAPI.да(j["ok"]) {
                if МоиОбъявленияAPI.нетСессии(j) {
                    сброситьДанные()
                    загрузка = .нуженВход
                    return
                }
                загрузка = .ошибка(т("load_err"))
                return
            }
            let сырые: [Any] = (j["items"] as? [Any]) ?? []
            товары = сырые.compactMap { запись -> МоёОбъявление? in
                guard let словарь = запись as? [String: Any] else { return nil }
                return МоёОбъявление(словарь)
            }
            слоты = СлотыОбъявлений(j["slots"] as? [String: Any])
            загрузка = .готово
            await загрузитьРаботу(моё)
        } catch {
            guard моё == поколение else { return }
            let текст = (error as? КабинетСайта.Сбой) == .сеть ? т("no_conn") : т("load_err")
            if товары.isEmpty {
                загрузка = .ошибка(текст)
            } else {
                показать(текст)
            }
        }
    }

    /// Блок «Работа» (jobsMineLoad): не пришло — блока нет, как у сайта.
    private func загрузитьРаботу(_ моё: Int) async {
        let ответ = try? await МоиОбъявленияAPI.получить("/api/jobs.php?action=mine", отКорня: true)
        guard моё == поколение else { return }
        guard let j = ответ else {
            работа = []
            return
        }
        let сырые: [Any] = (j["jobs"] as? [Any]) ?? []
        работа = сырые.compactMap { запись -> МояРабота? in
            guard let словарь = запись as? [String: Any] else { return nil }
            return МояРабота(словарь)
        }
    }

    // MARK: - Простые действия: снять, удалить, удалить навсегда

    /// deactivate_item — после «Деактивировать» в вопросе.
    func снять(_ товар: МоёОбъявление) {
        записать("cabinet.php?action=deactivate_item", тело: ["id": товар.id], id: товар.id, готово: т("deact_done"))
    }

    /// delete_item с причиной «Удалено пользователем», как у сайта, — после «Удалить» в вопросе.
    func удалить(_ товар: МоёОбъявление) {
        записать("cabinet.php?action=delete_item", тело: ["id": товар.id, "reason": "Удалено пользователем"],
                 id: товар.id, готово: т("del_done"))
    }

    /// delete_permanent — только после «Да, удалить навсегда» (§8.3: без того же вопроса не звать).
    func удалитьНавсегда(_ товар: МоёОбъявление) {
        записать("cabinet.php?action=delete_permanent", тело: ["id": товар.id], id: товар.id, готово: т("perm_done"))
    }

    /// Общий путь: ok — плашка сайта и список заново; иначе «Ошибка: …»; обрыв — «Ошибка соединения».
    private func записать(_ хвост: String, тело: [String: Any], id: String, готово: String) {
        guard !занято.contains(id) else { return }
        занято.insert(id)
        Task { @MainActor in
            defer { self.занято.remove(id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить(хвост, тело: тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(готово)
                    await self.загрузить(страницу: false)
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход()
                    return
                }
                self.показать(String(format: self.т("err_prefix"), МоиОбъявленияAPI.строка(j["error"])))
            } catch {
                self.показать(self.т("conn_err"))
            }
        }
    }

    // MARK: - Авто-продление и склад

    /// toggle_autorenew {item_id, on} — новое положение переключателя (toggleAutoRenew сайта).
    func автоПродление(_ товар: МоёОбъявление, включить: Bool) {
        guard !занято.contains(товар.id) else { return }
        занято.insert(товар.id)
        Task { @MainActor in
            defer { self.занято.remove(товар.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=toggle_autorenew",
                                                           тело: ["item_id": товар.id, "on": включить])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т(МоиОбъявленияAPI.да(j["auto_renew"]) ? "autorenew_on" : "autorenew_off"))
                    await self.загрузить(страницу: false)
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход()
                    return
                }
                self.показать(self.ошибкаИли(j, self.т("err_generic")))
            } catch {
                self.показать(self.т("err_net"))
            }
        }
    }

    /**
     stock_adjust {id, stock} — «На складе» магазина (stockSave сайта). «−» — «Продал офлайн — убавить»: у магазина это и
     есть «продано» — остаток 0 переводит объявление в sold («Распродано — объявление скрыто из витрины»). Отдельного
     «Продано» у сайта нет (карта §3.2.9).
     */
    func склад(_ товар: МоёОбъявление, количество: Int) {
        guard количество >= 0 else {
            показать(т("stock_bad"))
            return
        }
        guard !занято.contains(товар.id) else { return }
        занято.insert(товар.id)
        Task { @MainActor in
            defer { self.занято.remove(товар.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=stock_adjust",
                                                           тело: ["id": товар.id, "stock": количество])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    if МоиОбъявленияAPI.строка(j["status"]) == "sold" {
                        self.показать(self.т("stock_sold"))
                    } else {
                        self.показать(String(format: self.т("stock_ok"), МоиОбъявленияAPI.целое(j["stock"])))
                    }
                    await self.загрузить(страницу: false)
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход()
                    return
                }
                self.показать(self.ошибкаИли(j, self.т("stock_err")))
            } catch {
                self.показать(self.т("err_net"))
            }
        }
    }

    // MARK: - «Проверить сейчас» (mod_recheck)

    func проверитьСейчас(_ товар: МоёОбъявление) {
        guard !проверяем else { return }
        проверяем = true
        показать(т("recheck_run"))
        Task { @MainActor in
            defer { self.проверяем = false }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=mod_recheck", тело: ["id": товар.id])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let итоги: [Any] = (j["items"] as? [Any]) ?? []
                    let статусы: [String] = итоги.map { МоиОбъявленияAPI.строка(($0 as? [String: Any])?["status"]) }
                    let одобрено = статусы.filter { $0 == "approved" }.count
                    let ждут = статусы.filter { $0 == "pending" || $0 == "ai_check" }.count
                    self.показать(self.т(одобрено > 0 ? "recheck_ok" : (ждут > 0 ? "recheck_wait" : "recheck_done")))
                    await self.загрузить(страницу: false)
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход()
                    return
                }
                self.показать(self.ошибкаИли(j, self.т("err_generic")))
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    // MARK: - Активировать / восстановить (activate_item) и окно модерации

    /**
     activateItem сайта: окно «Kliko AI проверяет объявление» сразу, потом ответ activate_item. «ok» и approved —
     «Отлично!»; «ok» без итога — опрос item_status раз в 2 с, не больше 20 раз. Ошибки — окна сайта: ai_blocked,
     prohibited, need_verify, slots_full. Покупка слотов и верификация — страницами сайта (экран решает, куда вести).
     Тот же вызов у «Восстановить» из удалённых.
     */
    func активировать(_ товар: МоёОбъявление) {
        guard !занято.contains(товар.id) else { return }
        занято.insert(товар.id)
        окно = .проверка(шаг: т("mod_init"), процент: 0)
        запуститьШаги()
        let моё = поколение
        Task { @MainActor in
            defer { self.занято.remove(товар.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=activate_item", тело: ["id": товар.id])
                guard моё == self.поколение else { return }
                if !МоиОбъявленияAPI.да(j["ok"]) {
                    self.остановитьШаги()
                    self.окно = nil
                    self.ошибкаАктивации(j, id: товар.id)
                    return
                }
                if МоиОбъявленияAPI.строка(j["status"]) == "approved" {
                    self.остановитьШаги()
                    self.окно = .одобрено(секунд: 5)
                    self.отсчитать()
                    return
                }
                await self.опросить(товар.id, моё: моё)
            } catch {
                guard моё == self.поколение else { return }
                self.остановитьШаги()
                self.окно = nil
                self.показать(self.т("conn_err"))
            }
        }
    }

    private func ошибкаАктивации(_ j: [String: Any], id: String) {
        typealias A = МоиОбъявленияAPI
        if A.нетСессии(j) {
            нуженВход()
            return
        }
        if A.да(j["ai_blocked"]) {
            let часы = A.строка(j["hours"])
            /* Сайт в массовом режиме показывает «ещё undefined ч.» (§3.8) — без часов пишем то, что знаем: 24. */
            окно = .блокИИ(часы: часы.isEmpty ? "24" : часы, id: id)
            return
        }
        if A.да(j["prohibited"]) {
            окно = окноЗапрета(j)
            Task { @MainActor in await self.загрузить(страницу: false) }
            return
        }
        if A.да(j["need_verify"]) {
            окно = .верификация(A.строка(j["error"]))
            return
        }
        if A.да(j["slots_full"]) {
            let текст = A.строка(j["error"])
            if A.да(j["verify_required"]) {
                окно = .лимит(текст: текст.isEmpty ? т("limit_d") : текст, верификация: true)
            } else {
                /* Сайт: плашка с ошибкой и окно слотов. Слоты — платные (Config.цифровыеПокупки): вместо окна покупки —
                   то же окно лимита с «Расширить лимит», которое ведёт на страницу сайта. */
                показать(текст.isEmpty ? т("limit_d") : текст)
                окно = .лимит(текст: текст.isEmpty ? т("limit_d") : текст, верификация: false)
            }
            return
        }
        показать(String(format: т("err_prefix"), A.строка(j["error"])))
    }

    /// showProhibitedWarning сайта — заголовок и текст по soft / first / block_min.
    private func окноЗапрета(_ j: [String: Any]) -> Окно {
        typealias A = МоиОбъявленияAPI
        let метка = A.строка(j["cat_label"])
        let категория = метка.isEmpty ? т("prh_cat") : метка
        if A.да(j["soft"]) {
            return .запрещено(заголовок: т("prh_soft_t"), текст: String(format: т("prh_soft_b"), категория))
        }
        if A.да(j["first"]) {
            return .запрещено(заголовок: т("prh_t"), текст: String(format: т("prh_first"), категория))
        }
        let минут = A.целое(j["block_min"])
        if минут > 0 {
            var текст = String(format: т("prh_blk"), категория, A.строка(j["block_label"]))
            if минут < 10080 { текст += " " + т("prh_blk_more") }
            return .запрещено(заголовок: т("prh_blk_t"), текст: текст)
        }
        return .запрещено(заголовок: т("prh_t"), текст: String(format: т("prh_now"), категория))
    }

    /// Псевдо-шаги окна проверки — те же подписи и паузы, что у showModerationProgress сайта.
    private func запуститьШаги() {
        шаги?.cancel()
        let план: [(String, Int, UInt64)] = [("mod_s1", 15, 600), ("mod_s2", 40, 2000), ("mod_s3", 60, 1500),
                                              ("mod_s4", 75, 1000), ("mod_s5", 90, 800)]
        шаги = Task { @MainActor [weak self] in
            for шаг in план {
                guard !Task.isCancelled, let модель = self else { return }
                guard case .проверка = модель.окно else { return }
                модель.окно = .проверка(шаг: модель.т(шаг.0), процент: шаг.1)
                try? await Task.sleep(nanoseconds: шаг.2 * 1_000_000)
            }
        }
    }

    private func остановитьШаги() {
        шаги?.cancel()
        шаги = nil
    }

    /// Опрос item_status после «ok»: раз в 2 с, до 20 раз. Окно ушло (выход, другое окно) — опрос кончается.
    private func опросить(_ id: String, моё: Int) async {
        typealias A = МоиОбъявленияAPI
        let номер = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard моё == поколение, case .проверка = окно else { return }
            let ответ = try? await A.получить("cabinet.php?action=item_status&id=" + номер)
            guard моё == поколение, case .проверка = окно else { return }
            guard let j = ответ, A.да(j["ok"]) else { continue }
            let статус = A.строка(j["status"])
            if статус == "approved" {
                await завершитьПроверку(т("mod_ok"), моё: моё)
                guard моё == поколение else { return }
                показать(т("published"))
                return
            }
            if статус == "rejected" {
                let проблемы: [String] = ((j["ai_issues"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty }
                var причина = A.строка(j["reason"])
                if причина.isEmpty { причина = проблемы.joined(separator: ", ") }
                if причина.isEmpty { причина = т("rej_d") }
                await завершитьПроверку(т("mod_rej"), моё: моё)
                guard моё == поколение else { return }
                окно = .отклонено(причина)
                return
            }
            if статус == "deleted_permanent" {
                await завершитьПроверку(т("mod_blk"), моё: моё)
                guard моё == поколение else { return }
                окно = .блокИИ(часы: "24", id: nil)
                return
            }
        }
        guard моё == поколение else { return }
        await завершитьПроверку(т("mod_done"), моё: моё, пауза: 800)
        guard моё == поколение else { return }
        окно = .ждём
    }

    /// 100 % с итогом, пауза, окно прочь, список заново — как setTimeout(…, 900) сайта.
    private func завершитьПроверку(_ итог: String, моё: Int, пауза: UInt64 = 900) async {
        остановитьШаги()
        окно = .проверка(шаг: итог, процент: 100)
        try? await Task.sleep(nanoseconds: пауза * 1_000_000)
        guard моё == поколение else { return }
        окно = nil
        await загрузить(страницу: false)
    }

    /// «Хорошо · 5с»: раз в секунду минус один; на нуле — как нажатие.
    private func отсчитать() {
        отсчёт?.cancel()
        отсчёт = Task { @MainActor [weak self] in
            var осталось = 5
            while осталось > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let модель = self else { return }
                guard case .одобрено = модель.окно else { return }
                осталось -= 1
                if осталось <= 0 {
                    модель.закрытьОдобрено()
                    return
                }
                модель.окно = .одобрено(секунд: осталось)
            }
        }
    }

    /// «Хорошо» в окне «Отлично!» — во «Опубликованные» и список заново (showRepublishOk сайта).
    func закрытьОдобрено() {
        отсчёт?.cancel()
        отсчёт = nil
        окно = nil
        вкладка = .published
        Task { @MainActor in await self.загрузить(страницу: false) }
    }

    /// «Закрыть» любого окна. Окно проверки само не закрывается — как у сайта, ждём итога.
    func закрытьОкно() {
        if case .проверка = окно { return }
        отсчёт?.cancel()
        отсчёт = nil
        окно = nil
    }

    /// «Хорошо» в «Объявление на проверке» — список заново (loadMyItems сайта).
    func закрытьОжидание() {
        окно = nil
        Task { @MainActor in await self.загрузить(страницу: false) }
    }

    /// send_to_manual {id} — «Отправить на ручную проверку» из окна блокировки Kliko AI.
    func наРучнуюПроверку(_ id: String) {
        guard !занято.contains(id) else { return }
        занято.insert(id)
        Task { @MainActor in
            defer { self.занято.remove(id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=send_to_manual", тело: ["id": id])
                self.окно = nil
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т("manual_done"))
                    await self.загрузить(страницу: false)
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход()
                    return
                }
                self.показать(String(format: self.т("err_prefix"), self.ошибкаИли(j, self.т("manual_err"))))
            } catch {
                self.окно = nil
                self.показать(self.т("conn_err"))
            }
        }
    }

    // MARK: - «Работа»: снять / удалить / восстановить (/api/jobs.php)

    /// action — delete (и «Снять», и «Удалить» у сайта) или restore. Вопрос перед delete задаёт экран.
    func действиеРаботы(_ действие: String, _ запись: МояРабота) {
        guard действие == "delete" || действие == "restore" else { return }
        let ключ = "job:" + запись.id
        guard !занято.contains(ключ) else { return }
        занято.insert(ключ)
        let моё = поколение
        Task { @MainActor in
            defer { self.занято.remove(ключ) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("/api/jobs.php?action=" + действие,
                                                           тело: ["id": запись.id], отКорня: true)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    await self.загрузитьРаботу(моё)
                    return
                }
                let текст = МоиОбъявленияAPI.строка(j["msg"])
                self.показать(текст.isEmpty ? self.т("jw_fail") : текст)
            } catch {
                self.показать(self.т("no_net"))
            }
        }
    }

    // MARK: - Плашка, вход, стирание

    /// Короткая плашка внизу — toast сайта. VoiceOver читает её сразу.
    func показать(_ текст: String) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.2)) { плашка = чистый }
        UIAccessibility.post(notification: .announcement, argument: чистый)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard self.плашка == чистый else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.плашка = nil }
        }
    }

    /// error сервера или запасной текст сайта.
    private func ошибкаИли(_ j: [String: Any], _ запасной: String) -> String {
        let текст = МоиОбъявленияAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return текст.isEmpty ? запасной : текст
    }

    /// Сервер сказал «сессии нет» — данные прочь, экран предлагает войти.
    private func нуженВход() {
        сброситьДанные()
        загрузка = .нуженВход
    }

    private func сброситьДанные() {
        поколение += 1
        остановитьШаги()
        отсчёт?.cancel()
        отсчёт = nil
        товары = []
        слоты = nil
        работа = []
        кабинет = nil
        uid = ""
        окно = nil
        занято = []
        МоиОбъявленияAPI.забыть()
    }

    /// Выход (ВыходНачисто): всё ушедшего — прочь, включая выбранную вкладку и строку поиска.
    func стереть() {
        сброситьДанные()
        запрос = ""
        загрузка = .нет
        вкладка = .published
        UserDefaults.standard.removeObject(forKey: Self.ключВкладки)
    }
}
