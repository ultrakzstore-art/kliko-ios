import Foundation
import SwiftUI
import UIKit

/**
 «МОИ СДЕЛКИ» — СПИСОК, ЭТАП 43 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Порядок как у экрана сделок сайта (showDeals → dealsTab("seller") → loadDeals, карта §4.2): при каждом открытии —
 вкладка «Я продавец», список my_deals по роли, точка раздела гасится (mark_notif_read_section, как clearSectDot). Значок
 у строки кабинета — как loadDealsBadge: my_deals&role=both, сделки в спорe или ждущие подтверждения.

 🔴 ОШИБКИ САЙТА НЕ ПЕРЕНОСИМ (§4.1, §4.21, §8.0.6):
   · у покупателя сайт считает сбор как mkDealFee("12 345") — строка с пробелом даёт NaN и всегда 620 ₸. Здесь — buyer_fee
     сервера, а без него разница total_pay − amount;
   · после отмены и взаимного решения сайт шлёт второй my_deals&role=undefined. Здесь роль всегда известна;
   · статус expired сайт в карточке не знает (сырое «expired» и шаг 1 из 5). Здесь «Авто-завершена» и все шаги пройдены.

 Данные — одного человека: при выходе стираются (ВыходНачисто), при входе другим аккаунтом — сбрасываются.
 */
@MainActor
final class СделкиМодель: ObservableObject {
    static let shared = СделкиМодель()

    enum Загрузка: Equatable {
        case нет
        case идёт
        case готово
        case ошибка(String)
        case нуженВход
    }

    @Published var роль: РольСделок = .seller
    @Published private(set) var сделки: [СделкаКратко] = []
    @Published private(set) var загрузка: Загрузка = .нет
    /// Сколько сделок ждут человека (disputed|delivered, как loadDealsBadge) — значок у строки «Мои сделки».
    @Published private(set) var ждут: Int = 0

    private var uid = ""
    private var поколение = 0
    private var грузим = false
    private var ещёРаз = false

    private init() {}

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    // MARK: - Открытие экрана

    /**
     showDeals сайта: вкладка «Я продавец», список, погасить точку раздела. Точку сайт гасит запросом
     mark_notif_read_section — человек сам открыл раздел, это его нажатие; ответ не нужен (сайт его не читает).
     */
    func открыт() async {
        роль = .seller
        await загрузить()
        guard загрузка == .готово else { return }
        _ = try? await СделкиAPI.отправить("cabinet.php?action=mark_notif_read_section", тело: ["section": "deals"])
    }

    // MARK: - Загрузка списка

    func загрузить() async {
        if грузим {
            ещёРаз = true
            return
        }
        грузим = true
        defer { грузим = false }
        repeat {
            ещёРаз = false
            await загрузитьОдинРаз()
        } while ещёРаз
    }

    private func загрузитьОдинРаз() async {
        var моё = поколение
        let запрошена = роль
        if сделки.isEmpty { загрузка = .идёт }
        do {
            /* Кто вошёл — со страницы кабинета: чужие сделки не показываем ни секунды (вход другим аккаунтом). */
            let страница = try await КабинетСайта.состояние()
            guard моё == поколение else { return }
            if страница.вошёл == false {
                сбросить()
                загрузка = .нуженВход
                return
            }
            if !страница.uid.isEmpty && страница.uid != uid {
                if !uid.isEmpty {
                    сбросить()
                    моё = поколение
                    загрузка = .идёт
                }
                uid = страница.uid
            }
            МоиОбъявленияAPI.запомнитьТокен(страница.csrf)
            guard let j = try await СделкиAPI.получить("escrow.php?action=my_deals&role=" + запрошена.rawValue) else {
                throw КабинетСайта.Сбой.приложение
            }
            guard моё == поколение, запрошена == роль else { return }
            if !СделкиAPI.да(j["ok"]) {
                if МоиОбъявленияAPI.нетСессии(j) {
                    сбросить()
                    загрузка = .нуженВход
                    return
                }
                загрузка = .ошибка(т("err_load"))
                return
            }
            let сырые: [Any] = (j["deals"] as? [Any]) ?? []
            сделки = сырые.compactMap { з -> СделкаКратко? in
                guard let d = з as? [String: Any] else { return nil }
                return СделкаКратко(d)
            }
            загрузка = .готово
        } catch {
            guard моё == поколение else { return }
            let текст = (error as? КабинетСайта.Сбой) == .сеть ? т("no_conn") : т("err_generic")
            загрузка = .ошибка(текст)
        }
    }

    /// Вкладка — список заново (dealsTab сайта).
    func выбрать(_ новая: РольСделок) {
        guard новая != роль else { return }
        роль = новая
        сделки = []
        загрузка = .идёт
        Task { await загрузить() }
    }

    /**
     Значок: my_deals&role=both, disputed|delivered. Тихо: не пришло — значок прежний. Без ожидания страницы (ждать:
     false), как состояние кабинета на его экране: страница под слоем может быть платёжным шлюзом или eGov — уводить её
     на главную ради значка нельзя.
     */
    func обновитьЗначок() async {
        let моё = поколение
        guard let ответ = try? await КабинетСайта.вызвать("escrow.php?action=my_deals&role=both", ждать: false),
              let j = ответ.json, СделкиAPI.да(j["ok"]), моё == поколение else { return }
        let сырые: [Any] = (j["deals"] as? [Any]) ?? []
        ждут = сырые.filter { з in
            let статус = СделкиAPI.строка((з as? [String: Any])?["status"])
            return статус == "disputed" || статус == "delivered"
        }.count
    }

    // MARK: - Стирание

    private func сбросить() {
        поколение += 1
        сделки = []
        ждут = 0
        uid = ""
    }

    /// Выход (ВыходНачисто): сделки ушедшего — прочь; открытая карточка сама остановит опрос (её поколение).
    func стереть() {
        сбросить()
        загрузка = .нет
        роль = .seller
        КарточкаСделкиМодель.поколениеВыхода += 1
    }
}

// MARK: - Карточка сделки

/**
 КАРТОЧКА СДЕЛКИ — СОСТОЯНИЕ, ЖИВОЕ ОБНОВЛЕНИЕ И ДЕЙСТВИЯ БЕЗ ДЕНЕГ (этап 43).

 Как openDeal + startDealPoll сайта (§4.3): GET deal, потом два опроса, пока карточка на экране и сделка не завершена:
   · long-poll deal_wait&sig=: changed → deal заново и следующий через 250 мс; не изменилось → следующий; ошибка → deal
     заново и пауза 4 с. Сайт после «не изменилось» ждёт 60 мс — он рассчитывает, что сервер держит соединение. Если сервер
     ответит сразу (сколько он держит — неизвестно, риск §8.5), 60 мс — это 16 запросов в секунду. Поэтому здесь между
     двумя опросами не меньше секунды: контракт тот же, нагрузки нет;
   · запасной опрос deal раз в 15 с.
 В фоне (приложение не активно) и пока на экране страница сайта, опросы ждут, как сайт на скрытой вкладке; фоновые
 запросы не ждут страницу и не уводят её на главную (СделкиAPI.получитьВФоне) — под слоем может быть платёжный шлюз.

 Live Activity (§4.16): при каждой смене состояния — то же, что dealLiveActivity сайта: deal.live сервера или шаги,
 посчитанные здесь; завершённая сделка закрывает плашку, но только свою (сайт шлёт end() без номера — §4.21).
 */
@MainActor
final class КарточкаСделкиМодель: ObservableObject {
    /// Растёт при выходе: ответ, пришедший после выхода, в карточку не ляжет, опросы останавливаются.
    static var поколениеВыхода = 0

    let id: String
    @Published private(set) var сделка: Сделка? = nil
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нуженВход = false
    @Published private(set) var плашка: String? = nil
    /// Идёт запрос по нажатию — кнопки неактивны, второй раз то же не уйдёт.
    @Published private(set) var занято = false
    /// Окно «Только ссылки курьерских служб» / «Ссылка слишком длинная» (cmpNote сайта).
    @Published var окно: (заголовок: String, текст: String)? = nil

    // Ввод на карточке — живёт здесь, а не в сделке: опрос не стирает то, что человек пишет.
    @Published var доказательство = ""
    @Published var фотоДоказательства: Data? = nil
    @Published var ссылкаСлежения = ""
    /// Пункты приёма перевозчика (car_points): nil — не грузили.
    @Published private(set) var пункты: [ПунктПриёма]? = nil
    @Published private(set) var пунктыОшибка = false
    @Published private(set) var пунктыСообщение = ""
    @Published var выбранПункт = ""
    /// «Покупатель заберёт сам» / «Заберу сам» раскрыли (#clc-self).
    @Published var самовывозОткрыт = false

    private var моёПоколение: Int
    private var опрос: Task<Void, Never>? = nil
    private var запасной: Task<Void, Never>? = nil
    private var ключLive = ""
    /// car_points в пути — второй такой же запрос не уходит.
    private var грузимПункты = false
    /// _dealSig сайта: из deal.sig и из ответа deal_wait (changed → новый sig).
    private var подписьОжидания = ""

    init(id: String) {
        self.id = id
        моёПоколение = Self.поколениеВыхода
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var живой: Bool { моёПоколение == Self.поколениеВыхода }

    // MARK: - Загрузка и опрос

    /// Карточка на экране: deal, затем опросы (openDeal → startDealPoll).
    func появилась() async {
        await загрузить()
        запуститьОпросы()
    }

    /// Карточка ушла с экрана — опросы стоп (closeDealModal); список перечитывается, как у сайта.
    func исчезла() {
        остановить()
        /* Ушли на страницу сайта (деньги, карта, eGov) — список перечитается, когда человек вернётся в приложение. */
        guard WebBridge.shared.лентаВидна else { return }
        Task { await СделкиМодель.shared.загрузить() }
    }

    func остановить() {
        опрос?.cancel()
        опрос = nil
        запасной?.cancel()
        запасной = nil
    }

    /// фоном = true — запасной опрос и после deal_wait: страницу не ждём (СделкиAPI.получитьВФоне).
    func загрузить(фоном: Bool = false) async {
        guard живой else { return }
        do {
            let хвост = "escrow.php?action=deal&id=" + СделкиAPI.вАдрес(id)
            let ответ: [String: Any]?
            if фоном {
                ответ = try await СделкиAPI.получитьВФоне(хвост)
            } else {
                ответ = try await СделкиAPI.получить(хвост)
            }
            guard let j = ответ else {
                throw КабинетСайта.Сбой.приложение
            }
            guard живой else { return }
            guard СделкиAPI.да(j["ok"]), let d = j["deal"] as? [String: Any], let новая = Сделка(d, ответ: j) else {
                if МоиОбъявленияAPI.нетСессии(j) {
                    нуженВход = true
                    остановить()
                    return
                }
                /* Сайт выводит в окно сырой error; пустой — «Ошибка». */
                if сделка == nil {
                    let текст = СделкиAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    ошибка = текст.isEmpty ? т("err_generic") : ТекстыОшибокСделки.текст(текст)
                }
                return
            }
            ошибка = nil
            нуженВход = false
            применить(новая)
        } catch {
            guard живой, сделка == nil else { return }
            ошибка = (error as? КабинетСайта.Сбой) == .сеть ? т("no_conn") : т("err_generic")
        }
    }

    private func применить(_ новая: Сделка) {
        let сменилось = новая.ключСостояния != ключLive
        сделка = новая
        if !новая.подпись.isEmpty { подписьОжидания = новая.подпись }
        if новая.ссылкаСлежения.isEmpty == false && ссылкаСлежения.isEmpty == false && ссылкаСлежения == новая.ссылкаСлежения {
            ссылкаСлежения = ""
        }
        if сменилось {
            ключLive = новая.ключСостояния
            ЖиваяСделка.показать(новая)
        }
        if новая.конечная { остановить() }
    }

    private func запуститьОпросы() {
        guard let с = сделка, !с.конечная, опрос == nil else { return }
        опрос = Task { @MainActor [weak self] in
            await self?.циклОжидания()
        }
        запасной = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled, self.живой else { return }
                if СделкиAPI.опросМожно { await self.загрузить(фоном: true) }
            }
        }
    }

    private func циклОжидания() async {
        while !Task.isCancelled {
            guard живой, let с = сделка, !с.конечная else { return }
            if !СделкиAPI.опросМожно {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                continue
            }
            let начало = Date()
            var пауза: UInt64 = 0
            do {
                let хвост = "escrow.php?action=deal_wait&id=" + СделкиAPI.вАдрес(id) + "&sig="
                    + СделкиAPI.вАдрес(подписьОжидания.isEmpty ? с.подпись : подписьОжидания)
                let j = try await СделкиAPI.получитьВФоне(хвост)
                guard !Task.isCancelled else { return }
                if let j, СделкиAPI.да(j["ok"]) {
                    if СделкиAPI.да(j["changed"]) {
                        подписьОжидания = СделкиAPI.строка(j["sig"])
                        await загрузить(фоном: true)
                        пауза = 250_000_000
                    } else {
                        пауза = 60_000_000
                    }
                } else {
                    await загрузить(фоном: true)
                    пауза = 4_000_000_000
                }
            } catch {
                guard !Task.isCancelled else { return }
                await загрузить(фоном: true)
                пауза = 4_000_000_000
            }
            /* Не чаще раза в секунду, даже если сервер ответил сразу (см. шапку). */
            let прошло = Date().timeIntervalSince(начало)
            if прошло < 1 {
                пауза = max(пауза, UInt64((1 - прошло) * 1_000_000_000))
            }
            try? await Task.sleep(nanoseconds: пауза)
        }
    }

    // MARK: - Плашка

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

    // MARK: - Общий путь записи

    /**
     POST по нажатию. ok → текст готово и сделка заново (openDeal сайта); иначе — ошибка (разбор — у вызывающего).
     Сбой сети — «Ошибка сети» / «Нет связи»; второй раз запрос не уходит.
     */
    private func записать(_ хвост: String, тело: [String: Any], отКорня: Bool = false,
                          готово: @escaping ([String: Any]) -> String?,
                          ошибка разбор: @escaping ([String: Any]) -> String,
                          сеть: String) {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await СделкиAPI.отправить(хвост, тело: тело, отКорня: отКорня)
                guard self.живой else { return }
                if СделкиAPI.да(j["ok"]) {
                    if let текст = готово(j) { self.показать(текст) }
                    await self.загрузить()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход = true
                    return
                }
                self.показать(разбор(j))
            } catch {
                self.показать(сеть)
            }
        }
    }

    // MARK: - Услуга: подтвердить или отклонить заявку (accept_terms)

    /// dealAcceptTerms: «Подтвердить условия» — сразу; «Отклонить заявку» — после вопроса (его задаёт экран).
    func условия(принять: Bool) {
        записать("escrow.php?action=accept_terms", тело: ["deal_id": id, "accept": принять],
                 готово: { _ in СделкиText.т(принять ? "at_ok" : "at_rejected") },
                 ошибка: { j in
                     let e = СделкиAPI.строка(j["error"])
                     return String(format: СделкиText.т("err_prefix"), e.isEmpty ? СделкиText.т("at_fail") : e)
                 },
                 сеть: т("err_no_conn"))
    }

    // MARK: - Спор (dispute) и доказательства (upload_evidence)

    /**
     dspSend сайта: {reason_code, reason, image}. «Другое» без текста — отказ на месте. Фото — JPEG, сторона ≤1600,
     качество 0.75 (fileToB64); не прочиталось — пустая строка. Итог — через завершение: окно спора само показывает
     ошибку у себя (#dsp-err), а не плашкой. Итог nil — спор открыт; пустая строка — запрос не ушёл.
     */
    func открытьСпор(код: String, текст: String, фото: Data?, итог: @escaping (String?) -> Void) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        if код == "other" && чистый.isEmpty {
            итог(т("dsp_other_need"))
            return
        }
        /* Идёт другой запрос — пустой итог: окно снимает «Открываем…», ничего не показывая. */
        guard !занято else {
            итог("")
            return
        }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            var картинка = ""
            if let фото {
                картинка = await Task.detached(priority: .userInitiated) { () -> String in
                    СнимокСделки.dataURL(фото, сторона: 1600, качество: 0.75) ?? ""
                }.value
            }
            do {
                let j = try await СделкиAPI.отправить("escrow.php?action=dispute",
                                                      тело: ["deal_id": self.id, "reason_code": код, "reason": чистый,
                                                             "image": картинка])
                guard self.живой else { return }
                if СделкиAPI.да(j["ok"]) {
                    итог(nil)
                    self.показать(self.т("dsp_ok"))
                    await self.загрузить()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    итог(ТекстыОшибокСделки.текст("auth"))
                    return
                }
                let e = СделкиAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                итог(e.isEmpty ? self.т("dsp_fail") : ТекстыОшибокСделки.текст(e))
            } catch {
                итог(self.т("dsp_nonet"))
            }
        }
    }

    /**
     dealUploadEvidence: {note, image}. У сайта image — dataURL файла без сжатия; с iPhone это HEIC в десятки мегабайт,
     поэтому здесь — JPEG в полном размере, качество 0.9: тот же вид поля, сервер принимает JPEG.
     */
    func отправитьДоказательство() {
        let заметка = доказательство.trimmingCharacters(in: .whitespacesAndNewlines)
        let фото = фотоДоказательства
        if заметка.isEmpty && фото == nil {
            показать(т("ev_need"))
            return
        }
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            var картинка = ""
            if let фото {
                картинка = await Task.detached(priority: .userInitiated) { () -> String in
                    СнимокСделки.dataURL(фото, сторона: 0, качество: 0.9) ?? ""
                }.value
            }
            do {
                let j = try await СделкиAPI.отправить("escrow.php?action=upload_evidence",
                                                      тело: ["deal_id": self.id, "note": заметка, "image": картинка])
                guard self.живой else { return }
                if СделкиAPI.да(j["ok"]) {
                    self.доказательство = ""
                    self.фотоДоказательства = nil
                    self.показать(self.т("ev_ok"))
                    await self.загрузить()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход = true
                    return
                }
                self.показать(String(format: self.т("err_prefix"), СделкиAPI.строка(j["error"])))
            } catch {
                self.показать(self.т("err_no_conn"))
            }
        }
    }

    // MARK: - Оценка после сделки (update_review)

    /**
     dealReviewSave: {side, rating, review}. side — кого оценивают: покупатель оценивает продавца («seller»), продавец —
     покупателя («buyer»). Без звёзд — «Выберите оценку…». expired — время правки вышло: сделка заново.
     */
    func сохранитьОценку(оцениваем покупателя: Bool, звёзд: Int, отзыв: String, итог: @escaping (Bool) -> Void) {
        guard звёзд >= 1 else {
            показать(т("dl_pick_stars"))
            return
        }
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await СделкиAPI.отправить("escrow.php?action=update_review",
                                                      тело: ["deal_id": self.id, "side": покупателя ? "buyer" : "seller",
                                                             "rating": звёзд, "review": отзыв])
                guard self.живой else { return }
                if СделкиAPI.да(j["ok"]) {
                    итог(true)
                    self.показать(self.т("dl_review_saved"))
                    await self.загрузить()
                    return
                }
                let e = СделкиAPI.строка(j["error"])
                self.показать(e.isEmpty ? self.т("err_generic") : ТекстыОшибокСделки.текст(e))
                if СделкиAPI.да(j["expired"]) {
                    итог(true)
                    await self.загрузить()
                }
            } catch {
                self.показать(self.т("err_no_conn"))
            }
        }
    }

    // MARK: - Гарантийный талон: попросить продавца подписать (warranty_ask)

    /// /escrow.php?action=warranty_ask {id} — путь от корня без локали, как у сайта. already — просто сделка заново.
    func попроситьТалон() {
        записать("/escrow.php?action=warranty_ask", тело: ["id": id], отКорня: true,
                 готово: { j in
                     if СделкиAPI.да(j["already"]) { return nil }
                     return СделкиText.т(СделкиAPI.да(j["recent"]) ? "wc_ask_recent" : "wc_asked")
                 },
                 ошибка: { j in ТекстыОшибокСделки.ulx(j) },
                 сеть: т("err_no_conn"))
    }

    // MARK: - Передача: способ, отслеживание, курьер, перевозчик

    /// hovSetMode: self / courier / carrier; "" — сменить способ (hovSwitchDo, когда нет встречи и посылки).
    func способ(_ режим: String) {
        записать("escrow.php?action=set_handover", тело: ["deal_id": id, "mode": режим],
                 готово: { _ in СделкиText.т(режим.isEmpty ? "hnd_switch_ok" : "prc_started") },
                 ошибка: { j in
                     let e = СделкиAPI.строка(j["error"])
                     return e == "buyer_choice" ? СделкиText.т("hnd_lock_t") : ТекстыОшибокСделки.текст(e)
                 },
                 сеть: т("err_no_conn"))
        самовывозОткрыт = false
    }

    /**
     dealTrackSave: {url} (пусто — убрать). track_host и track_long — окна сайта, прочее — hovErr. Сайт заранее ищет в
     вставленном тексте ссылку службы (trkLinkFind) — здесь то же для «Вставить из буфера».
     */
    func сохранитьСсылку() {
        let адрес = ссылкаСлежения.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await СделкиAPI.отправить("escrow.php?action=set_track", тело: ["deal_id": self.id, "url": адрес])
                guard self.живой else { return }
                if СделкиAPI.да(j["ok"]) {
                    self.показать(self.т(адрес.isEmpty ? "trk_off" : "trk_ok"))
                    self.ссылкаСлежения = ""
                    await self.загрузить()
                    return
                }
                let e = СделкиAPI.строка(j["error"])
                switch e {
                case "track_host":
                    self.окно = (self.т("trk_e_host_t"), self.т("trk_e_host_m"))
                case "track_long":
                    self.окно = (self.т("trk_e_long"), self.т("trk_e_long_m"))
                default:
                    if МоиОбъявленияAPI.нетСессии(j) { self.нуженВход = true }
                    self.показать(ТекстыОшибокСделки.текст(e))
                }
            } catch {
                self.показать(self.т("err_no_conn"))
            }
        }
    }

    /// trkPaste: ссылка Яндекс Go или inDrive из буфера — в поле; нет — «В буфере нет ссылки…».
    func вставитьИзБуфера() {
        let текст = UIPasteboard.general.string ?? ""
        let найдена = ОтслеживаниеСделки.найти(текст)
        if найдена.isEmpty {
            показать(т("trk_clip_no"))
        } else {
            ссылкаСлежения = найдена
            показать(т("trk_clip_ok"))
        }
    }

    /**
     hovCourierMark: человек открыл Яндекс Go или 2ГИС из «Вызвать курьера» — сайт отмечает courier_called. Это его
     нажатие; ответ — только сделка заново, текста нет.
     */
    func курьерВызван() {
        Task { @MainActor in
            let j = try? await СделкиAPI.отправить("escrow.php?action=courier_called", тело: ["deal_id": self.id])
            guard self.живой, let j, СделкиAPI.да(j["ok"]) else { return }
            await self.загрузить()
        }
    }

    /// car_points: пункты приёма рядом с адресом отправки (dealCarPoints). Чтение — грузится, когда блок на экране.
    func загрузитьПункты(заново: Bool = false) {
        if грузимПункты || (пункты != nil && !заново && !пунктыОшибка) { return }
        грузимПункты = true
        пунктыОшибка = false
        пункты = nil
        Task { @MainActor in
            defer { self.грузимПункты = false }
            do {
                let j = try await СделкиAPI.получить("escrow.php?action=car_points&deal_id=" + СделкиAPI.вАдрес(self.id))
                guard self.живой else { return }
                guard let j, СделкиAPI.да(j["ok"]) else {
                    self.пунктыОшибка = true
                    let текст = СделкиAPI.строка(j?["message"]).isEmpty ? СделкиAPI.строка(j?["error"]) : СделкиAPI.строка(j?["message"])
                    self.показать(текст.isEmpty ? self.т("car_pts_err") : текст)
                    return
                }
                let сырые: [Any] = (j["points"] as? [Any]) ?? []
                let список = сырые.compactMap { з -> ПунктПриёма? in
                    guard let d = з as? [String: Any] else { return nil }
                    return ПунктПриёма(d)
                }
                self.пунктыСообщение = СделкиAPI.строка(j["message"])
                self.пункты = список
                if !список.contains(where: { $0.id == self.выбранПункт }) {
                    self.выбранПункт = список.first?.id ?? ""
                }
            } catch {
                guard self.живой else { return }
                self.пунктыОшибка = true
                self.показать(self.т("err_no_conn"))
            }
        }
    }

    /**
     dealCarOrder: {point} — отправка уже оплачена покупателем, запрос оформляет её у перевозчика (без денег, §8.5).
     Без пункта — «Выберите пункт приёма».
     */
    func оформитьОтправку() {
        guard !выбранПункт.isEmpty else {
            показать(т("car_pt_pick"))
            return
        }
        записать("escrow.php?action=car_order", тело: ["deal_id": id, "point": выбранПункт],
                 готово: { _ in СделкиText.т("car_st_created") },
                 ошибка: { j in
                     let m = СделкиAPI.строка(j["message"])
                     let e = СделкиAPI.строка(j["error"])
                     return !m.isEmpty ? m : (!e.isEmpty ? e : СделкиText.т("err_failed"))
                 },
                 сеть: т("err_no_conn"))
    }
}

// MARK: - Тексты ошибок сделки (hovErr, ulxErr)

enum ТекстыОшибокСделки {
    /// hovErr сайта: машинный код → готовый текст; прочее — как пришло; пусто — «Не удалось».
    static func текст(_ код: String) -> String {
        let к = код.trimmingCharacters(in: .whitespacesAndNewlines)
        if к.isEmpty { return СделкиText.т("err_failed") }
        let известные: Set<String> = ["bad_code", "locked", "not_here", "need_open_code", "status", "access", "csrf",
                                      "pin_seller_gone", "pin_wait_buyer", "empty", "not_found", "auth"]
        if известные.contains(к) { return СделкиText.т("he_" + к) }
        return к
    }

    /// ulxErr: message сервера, иначе error; пусто — «Ошибка».
    static func ulx(_ j: [String: Any]) -> String {
        let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        let e = СделкиAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? СделкиText.т("err_generic") : текст(e)
    }
}

// MARK: - Ссылка отслеживания (trkLinkFind)

enum ОтслеживаниеСделки {
    /// _TRK_HOSTS сайта: только Яндекс Go и inDrive (и их поддомены).
    static let хосты: [String] = ["yandex.ru", "yandex.kz", "yandex.com", "yandex.by", "yandex.uz", "go.yandex",
                                   "go.yandex.ru", "indrive.com", "indriver.com", "indrive.kz"]

    /// Первая ссылка службы в тексте; нет — пусто. Текст длиннее 2000 символов сайт не разбирает.
    static func найти(_ текст: String) -> String {
        guard !текст.isEmpty, текст.count <= 2000,
              let выражение = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+", options: [.caseInsensitive]) else {
            return ""
        }
        let диапазон = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        for совпадение in выражение.matches(in: текст, options: [], range: диапазон) {
            guard let r = Range(совпадение.range, in: текст) else { continue }
            let ссылка = String(текст[r])
            guard let хост = URL(string: ссылка)?.host?.lowercased() else { continue }
            if хосты.contains(where: { хост == $0 || хост.hasSuffix("." + $0) }) { return ссылка }
        }
        return ""
    }
}

// MARK: - Фото для спора и доказательств

enum СнимокСделки {
    /**
     dataURL «data:image/jpeg;base64,…» на белом фоне (fileToB64 сайта заливает фон белым). сторона 0 — без уменьшения.
     Не прочиталось — nil.
     */
    static func dataURL(_ данные: Data, сторона: CGFloat, качество: CGFloat) -> String? {
        guard let исходная = UIImage(data: данные) else { return nil }
        let размер = исходная.size
        guard размер.width > 0, размер.height > 0 else { return nil }
        var масштаб: CGFloat = 1
        if сторона > 0 { масштаб = min(1, сторона / max(размер.width, размер.height)) }
        let новый = CGSize(width: (размер.width * масштаб).rounded(), height: (размер.height * масштаб).rounded())
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисунок = UIGraphicsImageRenderer(size: новый, format: формат).image { к in
            UIColor.white.setFill()
            к.fill(CGRect(origin: .zero, size: новый))
            исходная.draw(in: CGRect(origin: .zero, size: новый))
        }
        guard let jpeg = рисунок.jpegData(compressionQuality: качество) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }
}
