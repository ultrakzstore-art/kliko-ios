import Foundation
import ImageIO
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
    /// Скорость: на экране копия списка с диска (КэшКабинета), а свежий ответ ещё не пришёл или не пришёл вовсе.
    @Published private(set) var сКопии = false

    /// Этап 44: вкладка для следующего открытия экрана (новая сделка — «Я покупатель»); nil — «Я продавец», как у сайта.
    var рольПриОткрытии: РольСделок? = nil

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
        /* Этап 44: после создания сделки сайт открывает вкладку «Я покупатель» (dealsTab("buyer")) — один раз. */
        роль = рольПриОткрытии ?? .seller
        рольПриОткрытии = nil
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
        /* Скорость: первый показ за запуск — последний список этой вкладки с диска сразу, пока идут страница кабинета и
           ответ; чужой (другой uid) модель сбросит ниже, как при смене аккаунта. */
        if сделки.isEmpty, СессияПриложения.shared.вошёл == true,
           let копия = await КэшКабинета.прочитать("deals-" + запрошена.rawValue),
           моё == поколение, запрошена == роль, сделки.isEmpty, uid.isEmpty || uid == копия.uid {
            let из = копия.строки.compactMap { СделкаКратко($0) }
            if !из.isEmpty {
                uid = копия.uid
                сделки = из.filter { !$0.закрыта } + из.filter { $0.закрыта }
                сКопии = true
            }
        }
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
            let все = сырые.compactMap { з -> СделкаКратко? in
                guard let d = з as? [String: Any] else { return nil }
                return СделкаКратко(d)
            }
            /* Сделка закрылась с прошлой загрузки — её объявление перечитывают лента и «Мои объявления». */
            var прежние: [String: String] = [:]
            for с in сделки { прежние[с.id] = с.статус }
            for с in все {
                ОбъявлениеПослеСделки.сверить(сделка: с.id, товар: с.товар, было: прежние[с.id], стало: с.статус)
            }
            /* Незакрытые — всегда сверху, завершённые и отменённые — ниже; внутри групп порядок сервера (новые первыми). */
            сделки = все.filter { !$0.закрыта } + все.filter { $0.закрыта }
            сКопии = false
            загрузка = .готово
            КэшКабинета.сохранить(сырые, имя: "deals-" + запрошена.rawValue, uid: uid)
        } catch {
            guard моё == поколение else { return }
            /* Скорость: нет связи, а на экране копия — список остаётся, сверху плашка «Нет связи». */
            if сКопии && !сделки.isEmpty {
                загрузка = .готово
                return
            }
            let текст = (error as? КабинетСайта.Сбой) == .сеть ? т("no_conn") : т("err_generic")
            загрузка = .ошибка(текст)
        }
    }

    /// Вкладка — список заново (dealsTab сайта).
    func выбрать(_ новая: РольСделок) {
        guard новая != роль else { return }
        роль = новая
        сделки = []
        сКопии = false
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
        /* Виджет «Kliko»: активные сделки обеих ролей — из того же ответа (HomeWidgetFeed.swift). */
        ВиджетKliko.сделки(сырые)
        ждут = сырые.filter { з in
            let статус = СделкиAPI.строка((з as? [String: Any])?["status"])
            return статус == "disputed" || статус == "delivered"
        }.count
    }

    // MARK: - Стирание

    private func сбросить() {
        поколение += 1
        сделки = []
        сКопии = false
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
    /// Этап 44: «Комментарий (необязательно)…» исполнителя к «Работа выполнена» (#dm-seller-note) и «Код продавца»
    /// покупателя (#deal-pin-in) — ввод на карточке, опрос его не стирает.
    @Published var заметкаИсполнителя = ""
    @Published var кодПродавца = ""
    /// Окно eGov для подписи гарантийного талона (warranty_sign → need_otp): денег не двигает.
    @Published var eGovТалона: ЗапросEGov? = nil
    /// Этап 44: денежные действия карточки — только за Config.деньгиСделок (ДеньгиСделкиМодель).
    let деньги: ДеньгиСделкиМодель
    /// Передача своими блоками: посылка с кодом, встреча с QR, возврат, курьер по городу (ПередачаСделкиМодель).
    let передача: ПередачаСделкиМодель
    /// Межгород, узнанный не из deal.intercity: расчёт курьера ответил reason "intercity" или сервер сравнил города
    /// (logistics_partners). Тогда, как у сайта при intercity, — только транспортная компания, без Яндекса.
    @Published var межгородУзнали = false
    /// Курьеру нужна точка «куда везти» — экран карточки откроет окно карты (clocalShipAdd сайта → hovAddrOpen).
    @Published var просьбаТочкиКуда = 0
    /// Города сторон сверены один раз за жизнь карточки.
    private var городаСверены = false

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
        деньги = ДеньгиСделкиМодель(id: id)
        передача = ПередачаСделкиМодель(id: id)
        деньги.карточка = self
        передача.карточка = self
    }

    /// Этап 44: ответ «нужен вход» на денежный запрос — тот же экран «Вы не вошли», что и у запросов этапа 43.
    func сессияПропала() {
        нуженВход = true
        остановить()
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var живой: Bool { моёПоколение == Self.поколениеВыхода }

    // MARK: - Загрузка и опрос

    /// Карточка на экране: deal, затем опросы (openDeal → startDealPoll).
    func появилась() async {
        await загрузить()
        /* Карточку закрыли, пока шла первая загрузка: .task уже отменён и исчезла() всё остановила — опросы не
           запускаем, иначе сделка опрашивалась бы в фоне до конца жизни модели. */
        guard !Task.isCancelled else { return }
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
        передача.остановитьКод()
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
        ОбъявлениеПослеСделки.сверить(сделка: новая.id, товар: новая.товар, было: сделка?.статус, стало: новая.статус)
        сделка = новая
        сверитьГорода(новая)
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

    /// Межгород ли это: GET chat.php?action=logistics_partners&pid=&to_city= (как mkIntercityToggle сайта) — только
    /// покупателю, пока способ получения не выбран и сервер сам не пометил сделку.
    private func сверитьГорода(_ с: Сделка) {
        guard !городаСверены, !с.межгород, с.межгородДанные == nil, !с.продавец, !с.услуга, с.статус == "held",
              с.способПередачи.isEmpty, с.курьер == nil, !с.черезПеревозчика, !с.товар.isEmpty else { return }
        городаСверены = true
        let товар = с.товар
        let город = МаршрутОбъявления.мойГород
        Task { @MainActor [weak self] in
            let ответ = await ДоставкаТКAPI.партнёры(объявление: товар, мойГород: город, выборПродавца: nil)
            guard let self, self.живой, ответ?.межгород == true else { return }
            self.межгородУзнали = true
        }
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
        withAnimation(ДвижениеСайта.появление) { плашка = чистый }
        UIAccessibility.post(notification: .announcement, argument: чистый)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard self.плашка == чистый else { return }
            withAnimation(ДвижениеСайта.уход) { self.плашка = nil }
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
                    /* Сначала общая плашка, потом итог: вызывающий может сменить её своей (ret_disp_done). */
                    self.показать(self.т("dsp_ok"))
                    итог(nil)
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
     поэтому здесь — JPEG как у фото спора того же окна (fileToB64(файл, 1600, .75) сайта): большая сторона ≤1600,
     качество 0.75. Полный кадр 48 Мп в память не декодируется (СнимокСделки), для модератора 1600 достаточно.
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
                    СнимокСделки.dataURL(фото, сторона: 1600, качество: 0.75) ?? ""
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

    // MARK: - Гарантийный талон: подпись продавца (warranty_sign)

    /**
     dealWarrantySign сайта: /escrow.php?action=warranty_sign {id}. need_otp — окно eGov (otpStepOpen с wc_otp_t и
     wc_otp_h), после проверки подпись уходит ещё раз; ok — «Талон подписан…» и сделка заново. Денег не двигает.
     */
    func подписатьТалон() {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await СделкиAPI.отправить("/escrow.php?action=warranty_sign", тело: ["id": self.id],
                                                      отКорня: true)
                guard self.живой else { return }
                if СделкиAPI.да(j["need_otp"]) {
                    let назначение = СделкиAPI.строка(j["purpose"])
                    let ссылка = СделкиAPI.строка(j["ref"])
                    /* после: — только потому, что его требует ЗапросEGov; итог разбирает послеEGovТалона. */
                    self.eGovТалона = ЗапросEGov(назначение: назначение.isEmpty ? "warranty_sign" : назначение,
                                                 ссылка: ссылка.isEmpty ? self.id : ссылка,
                                                 заголовок: self.т("wc_otp_t"), подсказка: self.т("wc_otp_h"),
                                                 после: .оплатить)
                    return
                }
                if СделкиAPI.да(j["ok"]) {
                    self.показать(self.т("wc_signed_toast"))
                    await self.загрузить()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.нуженВход = true
                    return
                }
                self.показать(ТекстыОшибокСделки.ulx(j))
            } catch {
                self.показать(self.т("err_no_conn"))
            }
        }
    }

    /// eGov пройден — подпись ещё раз, как колбэк otpStepOpen сайта.
    func послеEGovТалона() {
        eGovТалона = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.подписатьТалон()
        }
    }

    // MARK: - Передача: способ, отслеживание, курьер, перевозчик

    /// rcpSave: получатель-подарок — escrow.php?action=set_recipient {deal_id, name, phone, clear}; сам — clear: 1.
    func сохранитьПолучателя(имя: String, телефон: String, сам: Bool) {
        записать("escrow.php?action=set_recipient",
                 тело: ["deal_id": id, "name": сам ? "" : имя, "phone": сам ? "" : телефон, "clear": сам ? 1 : 0],
                 готово: { _ in КабинетПлюсText.т(сам ? "rcp_cleared" : "rcp_saved") },
                 ошибка: { j in
                     let текст = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                     return текст.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : текст
                 },
                 сеть: т("err_no_conn"))
    }

    /**
     hovSetMode: self / courier / carrier; "" — сменить способ. hovSwitchDo сайта: есть встреча или посылка (или способ не
     записан в сделке) — chat.php?action=handover_cancel {deal_id}, иначе set_handover с пустым mode.
     */
    func способ(_ режим: String) {
        if режим.isEmpty, let с = сделка, с.способПередачи.isEmpty || с.естьВстреча || с.естьПосылка {
            передача.остановитьКод()
            записать("chat.php?action=handover_cancel", тело: ["deal_id": id],
                     готово: { _ in СделкиText.т("hnd_switch_ok") },
                     ошибка: { j in
                         let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                         return m.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : m
                     },
                     сеть: т("err_no_conn"))
            самовывозОткрыт = false
            return
        }
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

// MARK: - Передача своими блоками (посылка, встреча, возврат, курьер по городу)

/// Лист передачи — показывает СлойПередачиСделки (DealHandover.swift).
enum ЛистПередачи: Identifiable, Equatable {
    /// hovParcelClaim: «Что не так с содержимым?».
    case претензия
    /// clocalRefuseModal: «Оформить возврат» — причина отказа от товара.
    case отказ
    /// Окно адреса: clocalReady без адреса, clocalPickupModal, clocalCallCourier без точки доставки.
    case адрес(ВидАдресаКурьера)
    /// clocalCourierCall: «Звонок курьеру» — подменный номер и добавочный.
    case звонок(ЗвонокКурьеруТрека)
    /// Своя камера приложения: QR встречи (встреча: true) или листка посылки.
    case сканер(встреча: Bool)
    /// hovFromEdit / hovAddrEdit посылки: окно карты, сохранение — parcel_from / parcel_addr.
    case адресПосылки(откуда: Bool)

    var id: String {
        switch self {
        case .претензия: return "claim"
        case .отказ: return "refuse"
        case .адрес(let вид): return "addr-" + вид.код
        case .звонок(let з): return "call-" + з.номер
        case .сканер(let встреча): return встреча ? "scan-meet" : "scan-parcel"
        case .адресПосылки(let откуда): return откуда ? "parcel-from" : "parcel-to"
        }
    }
}

/// Какое окно адреса открыто (clocalModal сайта с полем адреса).
enum ВидАдресаКурьера: Equatable {
    /// clocalReady: «Откуда забрать товар?» → clocal_ready.
    case готов
    /// clocalPickupModal: «Точка забора товара» → clocal_set_pickup.
    case точкаЗабора
    /// clocalCallCourier: «Куда привезти товар?» / «Организовать доставку курьером» → clocal_start.
    case куда(продавец: Bool)

    var код: String {
        switch self {
        case .готов: return "ready"
        case .точкаЗабора: return "pickup"
        case .куда(let продавец): return продавец ? "to-s" : "to-b"
        }
    }
}

/// Вопрос перед действием передачи (boostConfirm сайта) — своим листом по высоте.
enum ВопросПередачи: Identifiable, Equatable {
    /// hovParcelNoCode: «Подтвердить без кода?» → parcel_nocode.
    case безКода
    /// hovParcelLost: «Посылка не доехала?» → parcel_lost.
    case потеряна
    /// Вызвать оплаченного курьера Яндекса, когда точка доставки уже есть → clocal_start {deal_id}.
    case вызвать(продавец: Bool)
    /// QR отсканирован своей камерой: «Вы точно получили товар?» → meet_scan / parcel_open {token}.
    case код(встреча: Bool, токен: String)

    var id: String {
        switch self {
        case .безКода: return "nocode"
        case .потеряна: return "lost"
        case .вызвать(let продавец): return продавец ? "call-s" : "call-b"
        case .код(let встреча, let токен): return (встреча ? "meet-" : "parcel-") + токен
        }
    }
}

/// Слова окна вопроса.
struct СловаВопросаПередачи {
    let заголовок: String
    let текст: String
    let кнопка: String
    let опасная: Bool
    let символ: String
}

/// Код встречи на экране продавца (ответ meet_qr): сам код и когда он истечёт.
struct КодВстречи: Equatable {
    let код: String
    let до: Date
}

/**
 ПЕРЕДАЧА ТОВАРА СВОИМИ БЛОКАМИ — ЗАПРОСЫ (hovPost и clocalPost сайта, карта §9.5, §9.7, §9.8, §9.10).

 Всё идёт POST /kz/<язык>/chat.php?action=<act> с csrf в теле и один раз по нажатию:
   · посылка: parcel_from / parcel_addr {deal_id, addr, lat, lon} (окно карты), parcel_sent {deal_id}, parcel_open
     {deal_id, code}, parcel_release {deal_id, code}, parcel_claim {deal_id, reason ≥ 3}, parcel_nocode {deal_id},
     parcel_lost {deal_id, note:""};
   · встреча: meet_qr {deal_id} → meet{qr, qr_left}, снова за 10 с до конца, пока код на экране (hovQRSchedule);
     QR, отсканированный своей камерой, — meet_scan / parcel_open {token} после «Вы точно получили товар?»;
   · возврат: clocal_return_reason {deal_id, reason}, clocal_refuse {deal_id, reason};
   · курьер: clocal_start {deal_id[, dropoff_addr, dropoff_geo]}, clocal_ready {deal_id, pickup_addr[, pickup_geo]},
     clocal_set_pickup, clocal_yandex_order {deal_id}, clocal_courier_phone {deal_id} → phone, ext, ttl.
 Ответ: ok → плашка сайта и сделка заново; need_otp → своё окно eGov (purpose, по умолчанию escrow_handover, «Передача
 курьеру»), после проверки то же действие ещё раз — как колбэк otpStepOpen сайта; иначе msg || message || hovErr(error)
 и сделка заново (свежие fails и locked). Где деньги (коды посылки и встречи, вызов и заказ курьера, готовность, отказ) —
 ДеньгиСделкиAPI.отправитьОдинРаз: без повтора ни на «csrf», ни при обрыве сети.
 */
@MainActor
final class ПередачаСделкиМодель: ObservableObject {
    /// Запрос передачи: действие chat.php, тело, деньги ли (один раз без повторов), плашка при ok, свои тексты ошибок.
    struct Запрос {
        let действие: String
        let тело: [String: Any]
        let деньги: Bool
        let готово: ([String: Any]) -> String?
        var ошибки: [String: String] = [:]
        /// Свой запасной текст (clocalYandexOrder): тогда message сервера не читается.
        var запасной: String? = nil
    }

    let id: String
    weak var карточка: КарточкаСделкиМодель?

    @Published var лист: ЛистПередачи? = nil {
        didSet { if лист != oldValue { ошибкаОкна = nil } }
    }
    @Published var вопрос: ВопросПередачи? = nil
    /// Запрос в пути — кнопки неактивны, второй раз то же не уйдёт.
    @Published private(set) var идёт = false
    /// Ошибка, пока открыто окно: показывается в нём самом (плашка карточки была бы под листом).
    @Published var ошибкаОкна: String? = nil
    /// Ввод четырёх цифр посылки (hov-parcel-in) — опрос сделки его не стирает.
    @Published var кодПосылки = ""
    /// Код встречи на экране продавца.
    @Published private(set) var кодВстречи: КодВстречи? = nil

    private var задачаКода: Task<Void, Never>? = nil
    private var кодНаЭкране = false

    init(id: String) {
        self.id = id
    }

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }
    private var сделка: Сделка? { карточка?.сделка }
    private func заново() async { await карточка?.загрузить() }

    /// Плашка карточки; открыто окно — текст в нём.
    private func сказать(_ текст: String) {
        if лист != nil {
            ошибкаОкна = текст
        } else {
            карточка?.показать(текст)
        }
    }

    // MARK: - Общий путь (hovPost, clocalPost)

    private func послать(_ з: Запрос, итог: ((Bool) -> Void)? = nil) {
        guard !идёт else { return }
        идёт = true
        ошибкаОкна = nil
        let хвост = "chat.php?action=" + з.действие
        Task { @MainActor in
            let j: [String: Any]
            do {
                if з.деньги {
                    j = try await ДеньгиСделкиAPI.отправитьОдинРаз(хвост, тело: з.тело)
                } else {
                    j = try await СделкиAPI.отправить(хвост, тело: з.тело)
                }
            } catch {
                self.идёт = false
                self.сказать(СделкиText.т("err_no_conn"))
                итог?(false)
                /* Денежный запрос мог дойти — что с ним, скажет сама сделка. */
                if з.деньги { await self.заново() }
                return
            }
            self.идёт = false
            if МоиОбъявленияAPI.нетСессии(j) {
                итог?(false)
                self.лист = nil
                self.карточка?.сессияПропала()
                return
            }
            if СделкиAPI.да(j["ok"]) {
                self.лист = nil
                if let текст = з.готово(j) { self.карточка?.показать(текст) }
                итог?(true)
                await self.заново()
                return
            }
            if СделкиAPI.да(j["need_otp"]) {
                итог?(false)
                self.лист = nil
                self.eGov(j, повтор: з, итог: итог)
                return
            }
            self.сказать(self.текстОшибки(j, з))
            итог?(false)
            await self.заново()
        }
    }

    /// need_otp: своё окно eGov (otpStepOpen сайта с «Передача курьеру»); проверка пройдена — то же действие ещё раз.
    private func eGov(_ j: [String: Any], повтор з: Запрос, итог: ((Bool) -> Void)?) {
        let назначение = СделкиAPI.строка(j["purpose"])
        let ссылка = СделкиAPI.строка(j["ref"])
        ПотокEgov.шаг(назначение: назначение.isEmpty ? "escrow_handover" : назначение,
                      ссылка: ссылка.isEmpty ? id : ссылка,
                      заголовок: т("otp_hand_t"), подсказка: т("otp_hand_h"),
                      готово: { [weak self] in
                          self?.послать(з, итог: итог)
                      })
    }

    /// clocalPost: msg || message || hovErr(error); у заказа курьера — msg || свой текст кода || запасной.
    private func текстОшибки(_ j: [String: Any], _ з: Запрос) -> String {
        let msg = СделкиAPI.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !msg.isEmpty { return msg }
        let e = СделкиAPI.строка(j["error"])
        if let своё = з.ошибки[e] { return своё }
        if let запасной = з.запасной { return запасной }
        let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        return ТекстыОшибокСделки.текст(e)
    }

    // MARK: - Посылка с кодом (hovParcel*)

    /// hovVal: только цифры (любые цифры клавиатуры), не больше четырёх (maxlength 4).
    nonisolated static func цифры(_ текст: String) -> String {
        let все = текст.compactMap { $0.wholeNumberValue }.map { String($0) }.joined()
        return String(все.prefix(4))
    }

    /// «Отдал курьеру» (hovParcelSent).
    func посылкаУКурьера() {
        послать(Запрос(действие: "parcel_sent", тело: ["deal_id": id], деньги: false,
                       готово: { _ in ПередачаText.т("prc_sent_ok") }))
    }

    /// «Подтвердить вскрытие» (hovParcelOpen): код с листка — получение подтверждено.
    func вскрытьПосылку() {
        let код = Self.цифры(кодПосылки)
        guard код.count >= 4 else {
            сказать(т("prc_need4"))
            return
        }
        послать(Запрос(действие: "parcel_open", тело: ["deal_id": id, "code": код], деньги: true,
                       готово: { _ in ПередачаText.т("prc_open_ok") })) { [weak self] ok in
            if ok { self?.кодПосылки = "" }
        }
    }

    /// «Подтвердить и получить деньги» (hovParcelRelease): код покупателя отпускает деньги продавцу.
    func деньгиЗаПосылку() {
        let код = Self.цифры(кодПосылки)
        guard код.count >= 4 else {
            сказать(т("prc_need4"))
            return
        }
        послать(Запрос(действие: "parcel_release", тело: ["deal_id": id, "code": код], деньги: true,
                       готово: { _ in ПередачаText.т("prc_release_ok") })) { [weak self] ok in
            if ok { self?.кодПосылки = "" }
        }
    }

    /// «Открыть спор» окна претензии (hovParcelClaim): не короче трёх знаков.
    func претензия(_ текст: String) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard чистый.count >= 3 else {
            сказать(т("prc_claim_need"))
            return
        }
        послать(Запрос(действие: "parcel_claim", тело: ["deal_id": id, "reason": String(чистый.prefix(300))],
                       деньги: false, готово: { _ in ПередачаText.т("prc_claim_done") }))
    }

    /// Окно карты посылки сохранило адрес (hovAddrSave при _hovParcel): parcel_from / parcel_addr.
    func адресПосылки(откуда: Bool, адрес: String, точка: ТочкаСделки?, итог: @escaping (String?) -> Void) {
        var тело: [String: Any] = ["deal_id": id, "addr": адрес]
        if let к = точка {
            тело["lat"] = к.широта
            тело["lon"] = к.долгота
        } else {
            тело["lat"] = NSNull()
            тело["lon"] = NSNull()
        }
        guard !идёт else {
            итог("")
            return
        }
        идёт = true
        Task { @MainActor in
            defer { self.идёт = false }
            do {
                let j = try await СделкиAPI.отправить("chat.php?action=" + (откуда ? "parcel_from" : "parcel_addr"),
                                                      тело: тело)
                if СделкиAPI.да(j["ok"]) {
                    итог(nil)
                    self.карточка?.показать(ПередачаText.т("apk_saved"))
                    await self.заново()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    итог("")
                    self.карточка?.сессияПропала()
                    return
                }
                let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                итог(m.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : m)
                await self.заново()
            } catch {
                итог(СделкиText.т("err_no_conn"))
            }
        }
    }

    // MARK: - Вопросы

    func слова(_ в: ВопросПередачи) -> СловаВопросаПередачи {
        switch в {
        case .безКода:
            return СловаВопросаПередачи(заголовок: т("prc_nocode_t"), текст: т("prc_nocode_q"), кнопка: т("prc_nocode_yes"),
                                        опасная: true, символ: "checkmark.seal.fill")
        case .потеряна:
            return СловаВопросаПередачи(заголовок: т("prc_lost_t"), текст: т("prc_lost_m"), кнопка: т("prc_lost_ok"),
                                        опасная: true, символ: "exclamationmark.triangle.fill")
        case .вызвать(let продавец):
            let с = сделка
            var текст = с.map { БлокПередачи.подписьОплаченногоКурьера($0) } ?? ""
            if !продавец, let адрес = с?.адресКуда, !адрес.isEmpty {
                текст = т("clc_call_here") + " " + адрес + "\n\n" + текст
            }
            return СловаВопросаПередачи(заголовок: СделкиText.т(продавец ? "hnd_ya_s" : "hnd_ya_b"), текст: текст,
                                        кнопка: т("clc_call_ok"), опасная: false, символ: "car.fill")
        case .код:
            return СловаВопросаПередачи(заголовок: ДеньгиСделкиText.т("pin_b_ask"), текст: ДеньгиСделкиText.т("pin_b_ask_m"),
                                        кнопка: ДеньгиСделкиText.т("pin_b_ask_ok"), опасная: false, символ: "qrcode")
        }
    }

    /// «Да» окна вопроса.
    func подтвердить(_ в: ВопросПередачи) {
        вопрос = nil
        switch в {
        case .безКода:
            послать(Запрос(действие: "parcel_nocode", тело: ["deal_id": id], деньги: true,
                           готово: { _ in ПередачаText.т("prc_nocode_ok") }))
        case .потеряна:
            послать(Запрос(действие: "parcel_lost", тело: ["deal_id": id, "note": ""], деньги: false,
                           готово: { _ in ПередачаText.т("prc_lost_done") }))
        case .вызвать(let продавец):
            вызватьКурьера(продавец: продавец, адрес: nil, точка: nil)
        case .код(let встреча, let токен):
            послать(Запрос(действие: встреча ? "meet_scan" : "parcel_open", тело: ["token": токен], деньги: true,
                           готово: { _ in ДеньгиСделкиText.т(встреча ? "meet_ok" : "prc_opened") }))
        }
    }

    // MARK: - Встреча с QR (hovQRShow, hovQRSchedule)

    /// «Показать код передачи»: meet_qr → meet{qr, qr_left}; дальше — снова за 10 с до конца, пока код на экране.
    func показатьКод() {
        guard !идёт else { return }
        идёт = true
        кодНаЭкране = true
        Task { @MainActor in
            await self.запроситьКод()
            self.идёт = false
        }
    }

    private func запроситьКод() async {
        var сек = 60
        do {
            let j = try await СделкиAPI.отправить("chat.php?action=meet_qr", тело: ["deal_id": id])
            if МоиОбъявленияAPI.нетСессии(j) {
                карточка?.сессияПропала()
                return
            }
            if let м = j["meet"] as? [String: Any] {
                let код = СделкиAPI.строка(м["qr"]).trimmingCharacters(in: .whitespaces)
                let осталось = СделкиAPI.целое(м["qr_left"])
                if осталось > 0 { сек = min(осталось, 3600) }
                if !код.isEmpty { кодВстречи = КодВстречи(код: код, до: Date().addingTimeInterval(Double(сек))) }
            }
            if !СделкиAPI.да(j["ok"]) {
                let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                карточка?.показать(m.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : m)
            }
        } catch {
            карточка?.показать(СделкиText.т("err_no_conn"))
        }
        await заново()
        запланироватьКод(через: сек)
    }

    /// hovQRSchedule: за 10 с до конца (не раньше чем через 5 с) — новый код; приложение в фоне — проверка через 5 с.
    private func запланироватьКод(через сек: Int) {
        задачаКода?.cancel()
        let пауза = UInt64(max(5, сек - 10))
        задачаКода = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: пауза * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.кодНаЭкране, self.сделка?.встреча?.статус != "done" else {
                self.остановитьКод()
                return
            }
            if UIApplication.shared.applicationState != .active {
                self.запланироватьКод(через: 15)
                return
            }
            await self.запроситьКод()
        }
    }

    /**
     Код на экране продавца. Свой код уже есть (вернулись на карточку) — следим за его сроком заново; нет — берём код из
     сделки (qr, qr_left).
     */
    func кодНаЭкранеПоявился(_ в: ВстречаСделки) {
        кодНаЭкране = true
        if let есть = кодВстречи {
            guard задачаКода == nil else { return }
            запланироватьКод(через: Int(max(0, min(есть.до.timeIntervalSinceNow, 3600))))
            return
        }
        guard !в.код.isEmpty else { return }
        let сек = в.кодСек > 0 ? min(в.кодСек, 3600) : 60
        кодВстречи = КодВстречи(код: в.код, до: Date().addingTimeInterval(Double(сек)))
        запланироватьКод(через: сек)
    }

    /// Код ушёл с экрана (передача подтверждена, карточка закрыта, способ сменили) — hovQRStop.
    func остановитьКод() {
        кодНаЭкране = false
        задачаКода?.cancel()
        задачаКода = nil
    }

    // MARK: - Сканер QR (своя камера вместо системной)

    /**
     Токен из QR: адрес kliko.kz с ?meet=<qr> (экран продавца) или ?parcel=<open_token> (листок в коробке) — те же ссылки,
     что открывает системная камера (CabinetRouter → ЗаданияДенегСделок). Не наш адрес или не тот параметр — nil.
     */
    nonisolated static func токен(из текст: String, встреча: Bool) -> String? {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let адрес = URL(string: чистый),
              let части = URLComponents(url: адрес, resolvingAgainstBaseURL: false) else { return nil }
        let хост = (адрес.host ?? "").lowercased()
        guard хост == "kliko.kz" || хост == "www.kliko.kz" else { return nil }
        let имя = встреча ? "meet" : "parcel"
        guard let значение = части.queryItems?.first(where: { $0.name == имя })?.value,
              значение.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
        return значение
    }

    /// Камера прочла код: лист уезжает, потом — «Вы точно получили товар?» (код отпускает деньги продавцу).
    func отсканирован(токен: String, встреча: Bool) {
        лист = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.вопрос = .код(встреча: встреча, токен: токен)
        }
    }

    // MARK: - Возврат (clocalReturnReason, clocalDoRefuse)

    /// «Почему отказались?» покупателя: clocal_return_reason {deal_id, reason} → «Причина записана».
    func причинаВозврата(_ код: String) {
        послать(Запрос(действие: "clocal_return_reason", тело: ["deal_id": id, "reason": код], деньги: false,
                       готово: { _ in ПередачаText.т("ret_reason_ok") }))
    }

    /// «Не приму — оформить возврат»: причина → clocal_refuse {deal_id, reason}.
    func отказаться(_ причина: String) {
        послать(Запрос(действие: "clocal_refuse", тело: ["deal_id": id, "reason": причина], деньги: true,
                       готово: { _ in ПередачаText.т("ret_rf_ok") }))
    }

    // MARK: - Курьер по городу (clocalCallCourier, clocalReady, clocalPickupModal, clocalYandexOrder, clocalCourierCall)

    /**
     «Товар готов — вызвать курьера Яндекса» / «Курьер Яндекса» при оплаченной доставке (clocalCallCourier): продавцу нужен
     to_point_ok, покупателю — адрес и точка доставки; тогда окно подтверждения, иначе окно «Куда привезти товар?» /
     «Организовать доставку курьером». Перевозчик (dealShipCar) — ничего, как у сайта.
     */
    func вызватьОплаченного() {
        guard let с = сделка, !с.черезПеревозчика else { return }
        let я = с.продавец
        let можно = я ? с.точкаКудаГотова : (!с.адресКуда.isEmpty && с.точкаКуда != nil)
        if можно {
            вопрос = .вызвать(продавец: я)
        } else {
            лист = .адрес(.куда(продавец: я))
        }
    }

    /// clocal_start: без адреса — {deal_id}; из окна — {deal_id, dropoff_addr, dropoff_geo?} (точку шлёт только покупатель).
    func вызватьКурьера(продавец: Bool, адрес: String?, точка: ТочкаСделки?) {
        var тело: [String: Any] = ["deal_id": id]
        let готово: String
        if let адрес {
            тело["dropoff_addr"] = адрес
            if !продавец, let к = точка { тело["dropoff_geo"] = ["lat": к.широта, "lon": к.долгота] }
            готово = т("clc_call_done")
        } else if продавец {
            готово = т("clc_call_done")
        } else {
            готово = т("clc_call_here") + " " + (сделка?.адресКуда ?? "")
        }
        послать(Запрос(действие: "clocal_start", тело: тело, деньги: true, готово: { _ in готово }))
    }

    /// «Я на месте, товар готов» (clocalReady): адреса забора нет — окно «Откуда забрать товар?».
    func товарГотов() {
        guard let к = сделка?.курьер else { return }
        if к.адресЗабора.isEmpty {
            лист = .адрес(.готов)
        } else {
            готовЗдесь(адрес: к.адресЗабора, точка: nil)
        }
    }

    /// clocal_ready {deal_id, pickup_addr[, pickup_geo]}.
    func готовЗдесь(адрес: String, точка: ТочкаСделки?) {
        var тело: [String: Any] = ["deal_id": id, "pickup_addr": адрес]
        if let к = точка { тело["pickup_geo"] = ["lat": к.широта, "lon": к.долгота] }
        послать(Запрос(действие: "clocal_ready", тело: тело, деньги: true,
                       готово: { _ in ПередачаText.т("clc_rd_done") }))
    }

    /// «Сохранить точку» окна «Точка забора товара» (clocalPickupModal) — clocal_set_pickup.
    func точкаЗабора(адрес: String, точка: ТочкаСделки?) {
        var тело: [String: Any] = ["deal_id": id, "pickup_addr": адрес]
        if let к = точка { тело["pickup_geo"] = ["lat": к.широта, "lon": к.долгота] }
        послать(Запрос(действие: "clocal_set_pickup", тело: тело, деньги: false,
                       готово: { _ in ПередачаText.т("clc_pk_done") }))
    }

    /// «Заказать курьера Яндекса» / «Заказать курьера снова» (clocalYandexOrder) — коды ошибок сайта (CAB @461220).
    func заказатьЯндекс() {
        let ошибки: [String: String] = [
            "no_pickup_geo": т("yac_e_pickup"), "no_dropoff_geo": т("yac_e_dropoff"), "not_arranger": т("yac_e_arranger"),
            "off": т("yac_e_off"), "ship_none": т("yac_e_unpaid"), "ship_unpaid": т("yac_e_unpaid"),
            "not_ready": т("yac_e_ready"), "busy": т("yac_e_busy")
        ]
        послать(Запрос(действие: "clocal_yandex_order", тело: ["deal_id": id], деньги: true,
                       готово: { j in ПередачаText.т(СделкиAPI.да(j["already"]) ? "yac_already" : "yac_ordered") },
                       ошибки: ошибки, запасной: т("yac_e_fail")))
    }

    /// «Позвонить курьеру» (clocalCourierCall): clocal_courier_phone {deal_id} → окно с номером и добавочным.
    func позвонитьКурьеру() {
        guard !идёт else { return }
        идёт = true
        Task { @MainActor in
            defer { self.идёт = false }
            do {
                let j = try await СделкиAPI.отправить("chat.php?action=clocal_courier_phone", тело: ["deal_id": self.id])
                if СделкиAPI.да(j["ok"]) {
                    let номер = СделкиAPI.строка(j["phone"]).trimmingCharacters(in: .whitespaces)
                    guard !номер.isEmpty else {
                        self.сказать(СделкиText.т("err_failed"))
                        return
                    }
                    let добавочный = СделкиAPI.строка(j["ext"]).filter { $0.isNumber }
                    let срок = min(max(0, СделкиAPI.число(j["ttl"])), 86_400)
                    let минут = срок > 0 ? max(1, Int((срок / 60).rounded())) : 0
                    self.лист = .звонок(ЗвонокКурьеруТрека(номер: номер, добавочный: добавочный, минут: минут))
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.карточка?.сессияПропала()
                    return
                }
                let msg = СделкиAPI.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
                self.сказать(msg.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : msg)
            } catch {
                self.сказать(СделкиText.т("err_no_conn"))
            }
        }
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
     dataURL «data:image/jpeg;base64,…» на белом фоне (fileToB64 сайта заливает фон белым). сторона — предел большей
     стороны в пикселях, 0 — без уменьшения. Не прочиталось — nil.

     Снимок декодируется сразу уменьшенным (ImageIO, миниатюра с пределом стороны): полный кадр в память не
     разворачивается. Прежний путь через UIImage(data:) и перерисовку держал весь кадр 48 Мп — около 200 МБ.
     Поворот камеры (EXIF) ImageIO применяет сам (CreateThumbnailWithTransform).
     */
    static func dataURL(_ данные: Data, сторона: CGFloat, качество: CGFloat) -> String? {
        autoreleasepool { () -> String? in
            let опцииИсточника = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let источник = CGImageSourceCreateWithData(данные as CFData, опцииИсточника),
                  CGImageSourceGetCount(источник) > 0 else { return nil }
            let предел: Int
            if сторона > 0 {
                предел = Int(сторона.rounded())
            } else {
                // Без уменьшения: предел — собственная большая сторона кадра (из заголовка, без декодирования).
                let свойства = CGImageSourceCopyPropertiesAtIndex(источник, 0, nil) as? [CFString: Any] ?? [:]
                let ш = (свойства[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
                let в = (свойства[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
                предел = max(ш, в)
            }
            guard предел > 0 else { return nil }
            let опцииМиниатюры = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: предел
            ] as CFDictionary
            guard let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, опцииМиниатюры) else { return nil }
            let размер = CGSize(width: кадр.width, height: кадр.height)
            guard размер.width > 0, размер.height > 0 else { return nil }
            let формат = UIGraphicsImageRendererFormat()
            формат.scale = 1
            формат.opaque = true
            let рисунок = UIGraphicsImageRenderer(size: размер, format: формат).image { к in
                UIColor.white.setFill()
                к.fill(CGRect(origin: .zero, size: размер))
                UIImage(cgImage: кадр).draw(in: CGRect(origin: .zero, size: размер))
            }
            guard let jpeg = рисунок.jpegData(compressionQuality: качество) else { return nil }
            return "data:image/jpeg;base64," + jpeg.base64EncodedString()
        }
    }
}
