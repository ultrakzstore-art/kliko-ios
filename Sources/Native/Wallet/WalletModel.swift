import SwiftUI
import UIKit

/**
 КОШЕЛЁК — СОСТОЯНИЕ, ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Одна модель на вкладку «Кабинет» и экран кошелька: сведения wallet_info (баланс, строка под ним, история, готовые
 выплаты, ставки вывода), «Заморожено сейчас», «скрыть баланс», чек сделки из истории, итог выплаты после возврата со
 страницы банка и плашка (toast сайта). Сайт перечитывает кошелёк при каждой загрузке кабинета (loadWalletInfo) —
 приложение тоже: при каждом показе вкладки «Кабинет» (фоном, не уводя страницу под слоем) и при открытии экрана.

 Со страницы кабинета (её уже скачала вкладка) берутся: IS_VERIFIED — вывод только верифицированным (showWithdraw), и три
 строки со ставками из объекта T (wd_min, wd_bank_hint, wd_term2_s, карта §5.3.3): сервер пишет их со своими числами.

 «Скрыть баланс» (toggleHidePrivate сайта) у сайта живёт в localStorage.ulx_hide_priv — у приложения в своих настройках
 телефона под тем же смыслом; прячет и баланс, и номер в карточке профиля, как глаз в шапке кабинета сайта. Это
 настройка человека — выход её стирает.

 🔴 Денег здесь два: «Указать карту» готовой выплаты (payout_link — Config.деньгиКошелька) и «Вернуть деньги» обеспечения
 предложения (offer_unfund — Config.деньгиСделок). Оба — только по нажатию и после вопроса сайта; выключено — страница
 кабинета сайта, где этот же блок. Пополнение и вывод — WalletMoney.swift, за Config.деньгиКошелька.

 Выход (ВыходНачисто): всё стирается; ответ, пришедший после выхода, не примется (поколение).
 */
@MainActor
final class КошелёкМодель: ObservableObject {
    static let shared = КошелёкМодель()

    enum Загрузка: Equatable {
        case нет, идёт, готово, нуженВход
        case ошибка(String)
    }

    /// Итог выплаты (wdOutcomeModal): «Деньги отправлены» / «Не удалось вывести».
    struct ИтогВыплаты: Identifiable, Equatable {
        let id = UUID()
        let отправлено: Bool
        let сумма: Int
        let баланс: Int?
    }

    /// Вопрос «Снять предложение?» (frozenUnfund).
    struct СнятиеПредложения: Identifiable, Equatable {
        let id: String
    }

    @Published private(set) var сведения: СведенияКошелька? = nil
    @Published private(set) var заморожено: ЗамороженоКошелька? = nil
    @Published private(set) var загрузка: Загрузка = .нет
    @Published var скрыто: Bool
    @Published var плашка: String? = nil
    @Published var итогВыплаты: ИтогВыплаты? = nil
    @Published var снять: СнятиеПредложения? = nil
    /// Чек сделки из истории: грузится (id) и готов.
    @Published var чек: Сделка? = nil
    @Published private(set) var чекГрузится: String? = nil
    /// Строки, по которым идёт запрос (wid выплаты, id предложения) — кнопка «Открываем…».
    @Published private(set) var занято: Set<String> = []
    /// Страница банка для карты выплаты (payout_link.url) — лист с перехватом ?payout=back.
    @Published var банкВыплаты: АдресБанка? = nil

    /// IS_VERIFIED страницы кабинета: nil — ещё не читали.
    private(set) var верифицирован: Bool? = nil
    /// Строки T страницы со ставками — пусто: запасной текст словаря.
    private(set) var строкаМинимума = ""
    private(set) var строкаБанка = ""
    private(set) var строкаКомиссии = ""

    private var поколение = 0
    private static let ключСкрыть = "kliko.wallet.hidePrivate"

    private init() {
        скрыто = UserDefaults.standard.bool(forKey: Self.ключСкрыть)
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    // MARK: - Загрузка

    /// Страница кабинета, которую вкладка уже скачала: IS_VERIFIED и строки T со ставками.
    func обновитьСтраницу(_ состояние: КабинетСайта.Состояние, html: String) {
        guard состояние.вошёл == true else { return }
        верифицирован = состояние.верифицирован
        let строки = Self.строкиT(html)
        if let s = строки["wd_min"] { строкаМинимума = s }
        if let s = строки["wd_bank_hint"] { строкаБанка = s }
        if let s = строки["wd_term2_s"] { строкаКомиссии = s }
    }

    /// const T = Object.assign(window.KLK_T_CABINET||{},{…}) — второй аргумент JSON-объект строк.
    nonisolated static func строкиT(_ html: String) -> [String: String] {
        guard let начало = html.range(of: "const T = Object.assign(window.KLK_T_CABINET||{},") else { return [:] }
        let хвост = html[начало.upperBound...].prefix(20000)
        guard let конец = хвост.range(of: "});") else { return [:] }
        let литерал = String(хвост[хвост.startIndex..<конец.lowerBound]) + "}"
        guard let данные = литерал.data(using: .utf8),
              let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return [:] }
        var итог: [String: String] = [:]
        for (к, з) in объект {
            if let s = з as? String { итог[к] = s }
        }
        return итог
    }

    /**
     loadWalletInfo + frozenRender. ждать = false — фон вкладки «Кабинет»: страница под слоем грузится или не на сайте —
     молча оставляем прежнее (сайт при ошибке тоже молчит, catch(e){}). ждать = true — экран кошелька.
     */
    func загрузить(ждать: Bool = true) async {
        let моё = поколение
        if сведения == nil { загрузка = .идёт }
        do {
            guard let j = try await КошелёкAPI.получить("cabinet.php?action=wallet_info", ждать: ждать) else {
                throw КабинетСайта.Сбой.приложение
            }
            guard моё == поколение else { return }
            guard КошелёкAPI.да(j["ok"]) else {
                if МоиОбъявленияAPI.нетСессии(j) {
                    сведения = nil
                    заморожено = nil
                    загрузка = .нуженВход
                } else if сведения == nil {
                    let e = КошелёкAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    загрузка = .ошибка(e.isEmpty || КабинетСайта.машинныйКод(e) ? т("err_generic") : e)
                }
                return
            }
            сведения = СведенияКошелька(j)
            загрузка = .готово
        } catch {
            guard моё == поколение else { return }
            if сведения == nil {
                загрузка = .ошибка(т((error as? КабинетСайта.Сбой) == .сеть ? "err_no_conn" : "err_generic"))
            }
            return
        }
        await загрузитьЗаморожено(ждать: ждать)
    }

    /// frozen_funds: не ok или пусто — блока нет.
    private func загрузитьЗаморожено(ждать: Bool) async {
        let моё = поколение
        guard let j = try? await КошелёкAPI.получить("cabinet.php?action=frozen_funds", ждать: ждать) else { return }
        guard моё == поколение else { return }
        заморожено = ЗамороженоКошелька(j)
    }

    /// wdAutoToggle: сервер принял — walletInfo.auto_withdraw / auto_method / auto_details_mask на месте, как у сайта.
    func изменитьАвто(_ вкл: Bool, способ: String, маска: String) {
        guard var с = сведения else { return }
        с.автоВывод = вкл
        if вкл {
            с.автоСпособ = способ
            с.автоМаска = маска
        }
        сведения = с
    }

    // MARK: - Скрыть баланс

    func переключитьСкрытие() {
        скрыто.toggle()
        UserDefaults.standard.set(скрыто, forKey: Self.ключСкрыть)
        if скрыто { UIAccessibility.post(notification: .announcement, argument: т("a11y_hidden")) }
    }

    /// «12 345 ₸» или «••••• ₸».
    func показ(_ сумма: Int) -> String {
        скрыто ? "••••• ₸" : КошелёкФормат.тенге(сумма)
    }

    // MARK: - Чек (showReceipt)

    func открытьЧек(_ номер: String) {
        guard чекГрузится == nil, СделкиAPI.годныйНомер(номер) else { return }
        чекГрузится = номер
        let моё = поколение
        Task { @MainActor in
            defer { if моё == self.поколение { self.чекГрузится = nil } }
            do {
                guard let j = try await СделкиAPI.получить("escrow.php?action=deal&id=" + СделкиAPI.вАдрес(номер)) else {
                    throw КабинетСайта.Сбой.приложение
                }
                guard моё == self.поколение else { return }
                guard СделкиAPI.да(j["ok"]), let d = j["deal"] as? [String: Any], let сделка = Сделка(d, ответ: j) else {
                    /* Сайт пишет в окно a.error как есть. */
                    let e = СделкиAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.показать(e.isEmpty ? self.т("err_generic") : e)
                    return
                }
                self.чек = сделка
            } catch {
                guard моё == self.поколение else { return }
                self.показать(self.т((error as? КабинетСайта.Сбой) == .сеть ? "err_no_conn" : "err_generic"))
            }
        }
    }

    // MARK: - Готовая выплата (payoutOpenLink) — Config.деньгиКошелька

    /**
     «Указать карту»: GET payout_link&wid= → страница банка. Выключено — вызывающий открывает кабинет сайта и сюда не
     приходит. Номер карты вводится на странице банка и к Kliko не попадает (wd_res_now).
     */
    func ссылкаВыплаты(_ wid: String) {
        guard Config.деньгиКошелька, !занято.contains(wid) else { return }
        занято.insert(wid)
        let моё = поколение
        Task { @MainActor in
            defer { if моё == self.поколение { self.занято.remove(wid) } }
            do {
                let хвост = "cabinet.php?action=payout_link&wid=" + СделкиAPI.вАдрес(wid)
                guard let j = try await КошелёкAPI.получить(хвост) else { throw КабинетСайта.Сбой.приложение }
                guard моё == self.поколение else { return }
                let адрес = КошелёкAPI.строка(j["url"])
                if КошелёкAPI.да(j["ok"]), let url = URL(string: адрес), url.scheme?.lowercased() == "https" {
                    self.банкВыплаты = АдресБанка(адрес: url)
                    return
                }
                let e = КошелёкAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                self.показать(e.isEmpty || КабинетСайта.машинныйКод(e) ? self.т("po_unavail") : e)
            } catch {
                guard моё == self.поколение else { return }
                self.показать(self.т("po_nonet"))
            }
        }
    }

    /// payoutBackCheck: GET payout_outcome; none — ничего; done / failed — окно итога и свежий кошелёк.
    func проверитьВыплату() async {
        let моё = поколение
        guard let j = try? await КошелёкAPI.получить("cabinet.php?action=payout_outcome") else { return }
        guard моё == поколение, КошелёкAPI.да(j["ok"]) else { return }
        let статус = КошелёкAPI.строка(j["status"])
        guard статус != "none" else { return }
        let новый = j["new_balance"]
        let баланс: Int? = (новый == nil || новый is NSNull) ? nil : КошелёкAPI.тенге(новый)
        if статус == "done" || статус == "failed" {
            итогВыплаты = ИтогВыплаты(отправлено: статус == "done", сумма: КошелёкAPI.тенге(j["amount"]), баланс: баланс)
        }
        await загрузить()
    }

    /// Банк вернул человека (?payout=back) — лист закрыт, итог спрашиваем у сервера.
    func вернулисьСБанка() {
        банкВыплаты = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self.проверитьВыплату()
        }
    }

    // MARK: - «Вернуть деньги» обеспечения предложения (frozenUnfund) — Config.деньгиСделок

    func спроситьСнять(_ номер: String) {
        guard Config.деньгиСделок, !номер.isEmpty else { return }
        снять = СнятиеПредложения(id: номер)
    }

    /// После «Снять и вернуть»: POST offer_unfund {listing_id} один раз; читается только ok, как у сайта.
    func снятьПредложение(_ номер: String) {
        guard Config.деньгиСделок, !занято.contains(номер) else { return }
        занято.insert(номер)
        let моё = поколение
        Task { @MainActor in
            defer { if моё == self.поколение { self.занято.remove(номер) } }
            do {
                let j = try await КошелёкAPI.отправитьОдинРаз("cabinet.php?action=offer_unfund", тело: ["listing_id": номер])
                guard моё == self.поколение else { return }
                self.показать(self.т(КошелёкAPI.да(j["ok"]) ? "frz_unfund_done" : "err_generic"))
            } catch {
                guard моё == self.поколение else { return }
                self.показать(self.т("err_net"))
            }
            /* Сайт в любом случае перечитывает «Заморожено» и кошелёк. */
            await self.загрузить()
        }
    }

    // MARK: - Задания из ссылок

    /// ?payout=back / ?topup= из ссылки: выплата — только чтение; возврат пополнения — WalletMoney (за рубильником).
    func забратьЗадание() -> ВозвратКошелька? {
        ЗаданияКошелька.shared.забрать()
    }

    // MARK: - Плашка

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard self.плашка == текст else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.плашка = nil }
        }
    }

    // MARK: - Выход

    func стереть() {
        поколение += 1
        сведения = nil
        заморожено = nil
        загрузка = .нет
        итогВыплаты = nil
        снять = nil
        чек = nil
        чекГрузится = nil
        занято = []
        банкВыплаты = nil
        плашка = nil
        верифицирован = nil
        строкаМинимума = ""
        строкаБанка = ""
        строкаКомиссии = ""
        скрыто = false
        UserDefaults.standard.removeObject(forKey: Self.ключСкрыть)
        ЗаданияКошелька.shared.стереть()
    }
}

/// Адрес страницы банка для листа (Identifiable для .sheet(item:)).
struct АдресБанка: Identifiable, Equatable {
    let id = UUID()
    let адрес: URL
}
