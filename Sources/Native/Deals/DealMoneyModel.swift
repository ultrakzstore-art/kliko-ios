import Foundation
import SwiftUI
import UIKit

/**
 ДЕНЬГИ СДЕЛКИ — ДЕЙСТВИЯ КАРТОЧКИ (этап 44, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 🔴 ЖИВЁТ ТОЛЬКО ЗА Config.деньгиСделок (false). Пока рубильник выключен, начать(_:) ничего не делает, а экран карточки
 (ЭкранСделки.нажато) открывает вместо него страницу сделки сайта — как на этапе 43.

 Те же шаги, что у js/cabinet.min.js (карта §4.5–§4.12, §4.17, §8.6):
   · «Заморозить N ₸» / «Оплатить N ₸» — dealPay: баллы (escrow.php?action=points) → окно «Применить баллы?» или
     «Заморозить средства?» с условиями возврата → ход «Оформляем безопасную сделку» → pay {deal_id, use_points}:
     ok — карточка заново; need_otp — окно eGov, после него снова окно подтверждения (новое нажатие); short + can_card —
     pay_card → страница банка в листе приложения (ОкноБанка) → возврат ?topup=ok|fail&deal= → pay.php?action=confirm до
     5 раз с шагом 3 с → снова окно «Заморозить?» (деньги уже на кошельке, оплату сделки подтверждает человек); short без
     карты — «Недостаточно средств…» и кошелёк сайта; taken — «Товар уже зарезервирован»;
   · «Отменить сделку…» — dealCancel: окно с причиной, после отправки у покупателя — «сбор 1 000 ₸»; cancel {reason};
   · «Всё в порядке — принять» / «Товар у меня — принять» / «Работа принята» — dealAcceptAsk → buyer_confirm {rating,
     review}; need_otp — eGov; «Есть претензия — открыть спор» — окно спора этапа 43;
   · «Работа выполнена» — seller_confirm {note} (комментарий с карточки);
   · «Договорились — подтверждаю получение» / «Согласен вернуть деньги покупателю» — dealMutualResolve;
   · «Я получил вещь» по коду продавца — pin_enter {pin} после «Вы точно получили товар?»;
   · возврат товара продавцу — cancel {accept_fault, reason} и chat.php?action=clocal_return_confirm;
   · курьер Яндекса — ship_quote → (тариф) → «Оплатить N ₸» → ship_add; не хватает — ship_add_card → банк → ?ship=1;
     «Заберу сам» — ship_drop {accept_paid:0}, курьер уже выехал — второе окно и accept_paid:1.
 Каждый денежный POST — ровно один раз и только после нажатия (ДеньгиСделкиAPI.отправитьОдинРаз). Где сайт сам звал
 денежный запрос второй раз (already_enough у ship_add_card → ship_add), здесь снова окно подтверждения.

 🧪 ЖИВАЯ ПРОВЕРКА — только решением владельца, в сборке с Config.деньгиСделок = true, двумя тестовыми аккаунтами
 (покупатель и продавец; второго в снимке нет), минимальными суммами (гарант от 20 000 ₸, у услуги — любая; сбор от 620 ₸):
   1. без денег: create → «Отменить сделку» в pending; pay_card → закрыть лист банка → ветка ?topup=fail («Оплата не
      прошла — сделка ждёт оплаты»); какой адрес возврата сервер вписывает в redirect_url (§8.12.5) — ловит ли его
      ОкноБанка (свой домен + topup);
   2. с деньгами на минимальной услуге: pay → seller_confirm («Работа выполнена») → buyer_confirm; в wallet_info —
      escrow_hold и escrow_release; need_otp → окно eGov (remote.biometric.kz в листе: камера, SMS, otp_step_check);
   3. код продавца (pin_enter, pin_bad / pin_locked), QR встречи и листок в коробке (?meet=, ?parcel= → meet_scan /
      parcel_open) — только на этой тестовой сделке;
   4. курьер Яндекса: ship_quote с alt (тариф), ship_add, ship_add_card → ?topup=ok&ship=1, ship_drop и paid_cancel;
   5. возврат товара: cancel {accept_fault} + clocal_return_confirm — с курьером Яндекса и без;
   6. сдвоенные нажатия: второй pay не уходит, пока идёт первый (идёт); обрыв сети посреди pay — повтора нет, карточка
      перечитывается.
 */

/// Денежная кнопка карточки: что она делает на сайте.
enum ДействиеДенегСделки: Equatable {
    /// «Заморозить N ₸», «Оплатить N ₸» — dealPay.
    case оплатить
    /// «Отменить сделку», «Отменить (возврат …)», «Отменить заявку» — dealCancel.
    case отменить
    /// «Всё в порядке — принять», «Товар у меня — принять», «Всё в порядке», «Работа принята» — dealBuyerConfirm.
    case принять
    /// «Работа выполнена» — dealSellerConfirm.
    case работаВыполнена
    /// «Договорились — подтверждаю получение» — dealMutualResolve(accept).
    case договорились
    /// «Согласен вернуть деньги покупателю» — dealMutualResolve(cancel).
    case вернутьПокупателю
    /// «Я получил вещь» по коду продавца — dealPinSend.
    case кодПродавца
    /// «Товар вернулся ко мне — вернуть деньги» / «Товар у меня, согласен — вернуть деньги» — clocalReturnConfirm.
    case возвратПринят(сВиной: Bool)
    /// «Курьер Яндекса» (доставка не оплачена) — clocalShipAdd.
    case курьерЯндекса
    /// «Заберу сам» при оплаченном курьере — clocalShipDrop.
    case заберуСам
}

/// Шаг хода «Оформляем безопасную сделку» (escrowProgress): подпись, процент, пауза.
struct ШагХода {
    let текст: String
    let процент: Int
    let мс: UInt64
}

/// Экран хода (#mod-overlay сайта).
struct ХодДенег: Equatable {
    enum Итог: Equatable {
        case идёт
        case готово
        case занято
        case ошибка
    }

    var заголовок: String
    var подпись: String
    var процент: Int
    var итог: Итог = .идёт
}

/// Окно eGov (otpStepOpen): назначение, ссылка (id сделки), заголовок и подсказка сайта, что открыть после проверки.
struct ЗапросEGov: Equatable {
    let назначение: String
    let ссылка: String
    let заголовок: String
    let подсказка: String
    let после: ДействиеДенегСделки
}

/// Котировка курьера Яндекса (api/ship_quote.php): основной тариф и, если есть, второй (alt).
struct ЦенаКурьера: Equatable {
    struct Вариант: Equatable {
        let q: String
        let цена: Int
        let тариф: String
    }

    let основной: Вариант
    let бесплатно: Bool
    let другой: Вариант?

    init(основной: Вариант, бесплатно: Bool, другой: Вариант?) {
        self.основной = основной
        self.бесплатно = бесплатно
        self.другой = другой
    }

    init(_ j: [String: Any]) {
        typealias A = СделкиAPI
        let тариф = A.строка(j["tariff"])
        основной = Вариант(q: A.строка(j["q"]), цена: A.целое(j["price"]), тариф: тариф.isEmpty ? "courier" : тариф)
        бесплатно = A.да(j["free"])
        if let alt = j["alt"] as? [String: Any], !A.строка(alt["q"]).isEmpty {
            другой = Вариант(q: A.строка(alt["q"]), цена: A.целое(alt["price"]), тариф: A.строка(alt["tariff"]))
        } else {
            другой = nil
        }
    }

    /// «Пеший курьер · N ₸» / «Экспресс — быстрее · N ₸» (shpTariffChoice).
    static func подпись(_ в: Вариант) -> String {
        ДеньгиСделкиText.т(в.тариф == "courier" ? "co_ship_walk" : "co_ship_exp") + " · " + СделкиФормат.тенге(в.цена)
    }
}

@MainActor
final class ДеньгиСделкиМодель: ObservableObject {
    enum Лист: Identifiable {
        case баллы(сумма: Int, баллов: Int, максимум: Int)
        case отмена(послеОтправки: Bool)
        case приёмка(звёзды: Bool)
        case eGov(ЗапросEGov)
        case банк(URL, курьер: Bool)
        /// «Недостаточно средств», картой нельзя: экран «Пополнить кошелёк» (только при Config.деньгиКошелька).
        case пополнение

        var id: String {
            switch self {
            case .баллы: return "points"
            case .отмена: return "cancel"
            case .приёмка: return "accept"
            case .eGov(let з): return "egov-" + з.назначение
            case .банк(let адрес, _): return "bank-" + адрес.absoluteString
            case .пополнение: return "topup"
            }
        }
    }

    enum Вопрос: Identifiable {
        case заморозить(Int)
        case договорились
        case вернуть
        case код(String)
        case возврат(сВиной: Bool)
        case курьер(ЦенаКурьера)
        case картойЗаКурьера(недостача: Int, ЦенаКурьера)
        case заберуСам(доставка: Int)
        case платнаяОтмена(сумма: Int, продавец: Bool)
        case ожидание(баланс: Int?)

        var id: String {
            switch self {
            case .заморозить: return "freeze"
            case .договорились: return "mutual-accept"
            case .вернуть: return "mutual-cancel"
            case .код: return "pin"
            case .возврат: return "return"
            case .курьер: return "courier"
            case .картойЗаКурьера: return "courier-card"
            case .заберуСам: return "drop"
            case .платнаяОтмена: return "drop-paid"
            case .ожидание: return "pending"
            }
        }
    }

    /// Слова окна подтверждения.
    struct ТекстВопроса {
        let заголовок: String
        let текст: String
        let кнопка: String
        let опасная: Bool
        let толькоПонятно: Bool
    }

    /*
     Причины, которые уходят серверу, сайт пишет по-русски на любом языке страницы (строки зашиты в js/cabinet.min.js):
     так же и здесь — это данные сделки, а не текст для человека.
     */
    private static let причинаОтмены = "Отменена пользователем"
    private static let причинаВзаимная = "Стороны договорились — взаимная отмена"
    private static let причинаВозврата = "Возврат подтверждён — товар получен обратно"

    let id: String
    weak var карточка: КарточкаСделкиМодель?
    /// Страница сайта (кошелёк для пополнения — этап 47): её подставляет слой экрана.
    var открытьСайт: ((String) -> Void)? = nil

    @Published var лист: Лист? = nil
    @Published var вопрос: Вопрос? = nil
    /// Выбор тарифа курьера (shpTariffChoice).
    @Published var тарифы: ЦенаКурьера? = nil
    @Published private(set) var ход: ХодДенег? = nil
    /// Идёт денежный запрос — второе нажатие ничего не шлёт.
    @Published private(set) var идёт = false
    /// «Есть претензия — открыть спор» в окне приёмки — окно спора откроет экран.
    @Published var нуженСпор = false

    private var ходЗакрыт = false
    /// Лист банка закрылся возвратом (?topup=) — иначе его закрыл человек, и сверять нечего.
    private var вернулисьСБанка = false
    /// На экране (или только что был) лист банка.
    private var банкНаЭкране = false
    /// На экране (или только что был) лист пополнения кошелька.
    private var пополнениеНаЭкране = false

    init(id: String) {
        self.id = id
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }
    private var сделка: Сделка? { карточка?.сделка }
    private func показать(_ текст: String) { карточка?.показать(текст) }
    private func заново() async { await карточка?.загрузить() }
    private func тенге(_ n: Int) -> String { СделкиФормат.тенге(n) }

    /// message сервера, иначе error, иначе запасной текст (toast(i.message||i.error||tt("err_failed")) сайта).
    private func текстОтвета(_ j: [String: Any], запасной: String) -> String {
        let m = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty { return m }
        let e = СделкиAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return e.isEmpty ? запасной : e
    }

    // MARK: - Вход

    /// Денежная кнопка нажата. Рубильник выключен — ничего (экран открывает страницу сайта сам).
    func начать(_ д: ДействиеДенегСделки) {
        guard Config.деньгиСделок, !идёт else { return }
        switch д {
        case .оплатить:
            оплатить()
        case .отменить:
            guard let с = сделка else { return }
            лист = .отмена(послеОтправки: !с.продавец && (с.статус == "shipped" || с.статус == "delivered"))
        case .принять:
            лист = .приёмка(звёзды: сделка?.статус == "delivered")
        case .работаВыполнена:
            работаВыполнена()
        case .договорились:
            вопрос = .договорились
        case .вернутьПокупателю:
            вопрос = .вернуть
        case .кодПродавца:
            кодПродавца()
        case .возвратПринят(let вина):
            вопрос = .возврат(сВиной: вина)
        case .курьерЯндекса:
            курьерЯндекса()
        case .заберуСам:
            вопрос = .заберуСам(доставка: сделка?.доставка ?? 0)
        }
    }

    /// Окно подтверждения: «да».
    func подтвердить(_ в: Вопрос) {
        вопрос = nil
        switch в {
        case .заморозить:
            заморозить(баллами: 0)
        case .договорились:
            подтвердитьПолучение(звёзд: 0, отзыв: "", взаимно: true)
        case .вернуть:
            отменитьЗапросом(причина: Self.причинаВзаимная, готово: т("mr_cn_done"))
        case .код(let код):
            ввестиКод(код)
        case .возврат(let вина):
            возвратПринят(сВиной: вина)
        case .курьер(let цена):
            добавитьКурьера(цена)
        case .картойЗаКурьера(_, let цена):
            курьерКартой(цена)
        case .заберуСам:
            заберуСам(платно: false)
        case .платнаяОтмена:
            заберуСам(платно: true)
        case .ожидание:
            break
        }
    }

    /// Слова окон — сайта (cabConfirm, boostConfirm, tpmOpen).
    func текст(_ в: Вопрос) -> ТекстВопроса {
        switch в {
        case .заморозить(let сумма):
            let суть = ТекстСделки.чистый(ДеньгиСделкиText.т("fz_m", n: тенге(сумма)))
            return ТекстВопроса(заголовок: т("fz_t"), текст: суть + "\n\n" + Self.условияВозврата, кнопка: т("dl_freeze_btn"),
                                опасная: false, толькоПонятно: false)
        case .договорились:
            return ТекстВопроса(заголовок: т("mr_acc_t"), текст: т("mr_acc_m"), кнопка: т("mr_acc_ok"), опасная: false,
                                толькоПонятно: false)
        case .вернуть:
            return ТекстВопроса(заголовок: т("mr_cn_t"), текст: т("mr_cn_m"), кнопка: т("mr_cn_ok"), опасная: true,
                                толькоПонятно: false)
        case .код:
            return ТекстВопроса(заголовок: т("pin_b_ask"), текст: т("pin_b_ask_m"), кнопка: т("pin_b_ask_ok"), опасная: false,
                                толькоПонятно: false)
        case .возврат(let вина):
            return ТекстВопроса(заголовок: т("ret_cf_t"), текст: т(вина ? "ret_cf_m2" : "ret_cf_m"), кнопка: т("ret_cf_ok"),
                                опасная: false, толькоПонятно: false)
        case .курьер(let цена):
            let сумма = тенге(цена.основной.цена)
            return ТекстВопроса(заголовок: т("shp_add_t"),
                                текст: цена.бесплатно ? т("shp_add_m_free") : ДеньгиСделкиText.т("shp_add_m", n: сумма),
                                кнопка: цена.бесплатно ? т("shp_add_ok_free") : ДеньгиСделкиText.т("shp_add_ok", n: сумма),
                                опасная: false, толькоПонятно: false)
        case .картойЗаКурьера(let недостача, _):
            return ТекстВопроса(заголовок: т("shp_card_t"), текст: ДеньгиСделкиText.т("shp_card_m", n: тенге(недостача)),
                                кнопка: т("shp_card_ok"), опасная: false, толькоПонятно: false)
        case .заберуСам(let доставка):
            let суть = доставка > 0 ? ДеньгиСделкиText.т("shp_drop_m_if", n: тенге(доставка)) : т("shp_drop_m0")
            return ТекстВопроса(заголовок: т("shp_drop_t"), текст: суть, кнопка: т("shp_drop_ok"), опасная: false,
                                толькоПонятно: false)
        case .платнаяОтмена(let сумма, let продавец):
            let суть = ДеньгиСделкиText.т(продавец ? "shp_drop_paid_ms" : "shp_drop_paid_m", n: тенге(сумма))
            return ТекстВопроса(заголовок: т("shp_drop_paid_t"), текст: суть, кнопка: т("shp_drop_paid_ok"), опасная: true,
                                толькоПонятно: false)
        case .ожидание(let баланс):
            let строкаБаланса = баланс.map { ДеньгиСделкиText.т("tpm_bal", n: тенге($0)) + "\n\n" } ?? ""
            return ТекстВопроса(заголовок: т("tpm_pend_t"), текст: строкаБаланса + т("tpm_pend_m"), кнопка: т("tpm_ok"),
                                опасная: false, толькоПонятно: true)
        }
    }

    /// dealReturnNote: «Возврат и обратная доставка» тремя пунктами.
    static var условияВозврата: String {
        /* Не цепочкой «+»: семь слагаемых в одном выражении — лишняя работа проверке типов (этап f0d29e1). */
        let пункты: [String] = [ДеньгиСделкиText.т("ret_pol_defect"), ДеньгиСделкиText.т("ret_pol_asis"),
                                ДеньгиСделкиText.т("ret_pol_fwd")]
        let строки: [String] = [ДеньгиСделкиText.т("ret_pol_title")] + пункты.map { "• " + $0 }
        return строки.joined(separator: "\n")
    }

    // MARK: - Общий путь денежного POST

    /**
     POST по нажатию: один раз (ДеньгиСделкиAPI.отправитьОдинРаз). Сессии нет — экран входа. Обрыв сети — текст и
     карточка заново: запрос мог дойти, и что с деньгами, скажет сама сделка. Повтора нет.
     */
    private func послать(_ хвост: String, _ тело: [String: Any], итог: @escaping ([String: Any]) async -> Void) {
        guard !идёт else { return }
        идёт = true
        Task { @MainActor in
            do {
                let j = try await ДеньгиСделкиAPI.отправитьОдинРаз(хвост, тело: тело)
                if МоиОбъявленияAPI.нетСессии(j) {
                    self.идёт = false
                    self.карточка?.сессияПропала()
                    return
                }
                await итог(j)
            } catch {
                self.показать(self.т("err_no_conn"))
                await self.заново()
            }
            self.идёт = false
        }
    }

    // MARK: - Ход «Оформляем безопасную сделку» (escrowProgress)

    /**
     Шаги с процентами идут, пока запрос в пути; потом «Деньги под защитой гаранта», «Товар уже зарезервирован» (до 10 с,
     нажатие закрывает) или «Не получилось». need_otp, short, need_terms и «нет сессии» — не ошибки: у них свой следующий
     шаг, и «Не получилось · Ошибка», которое показал бы сайт, здесь не рисуется.
     */
    private func сХодом(заголовок: String, шаги: [ШагХода], готово: String,
                        работа: @escaping () async throws -> [String: Any]) async -> [String: Any] {
        ходЗакрыт = false
        ход = ХодДенег(заголовок: заголовок, подпись: т("ep_wait"), процент: 0)
        let запрос = Task { @MainActor () async throws -> [String: Any] in
            try await работа()
        }
        for шаг in шаги {
            ход?.процент = шаг.процент
            ход?.подпись = шаг.текст
            try? await Task.sleep(nanoseconds: шаг.мс * 1_000_000)
        }
        let j: [String: Any]
        do {
            j = try await запрос.value
        } catch {
            j = ["ok": false, "error": "", "message": т("ep_conn"), "net": true]
        }
        await ЗапускХода.итог(j, готово: готово, ход: { self.ход = $0 }, закрыт: { self.ходЗакрыт })
        ход = nil
        return j
    }

    /// Нажатие на «Товар уже зарезервирован» — закрыть сразу (сайт: клик по окну).
    func закрытьХод() {
        ходЗакрыт = true
    }

    // MARK: - Оплата (dealPay, dealPayCard)

    private func оплатить() {
        guard let с = сделка else { return }
        /* dealPay('<id>','<total_pay>') кнопки сайта: сумма окна «Заморозить N ₸» — total_pay; нет его — actual_pay
           (запасной путь dealPay: actual_pay||total_pay из escrow.php?action=deal). */
        let сумма = с.кОплате > 0 ? с.кОплате : с.оплачено
        guard сумма > 0 else {
            показать(т("dp_no_sum"))
            return
        }
        guard !идёт else { return }
        идёт = true
        Task { @MainActor in
            let баллы = await self.баллы()
            self.идёт = false
            if let б = баллы, б.включены, б.баллов > 0 {
                /* Math.round(n*o/100) сайта; доля — с сервера (max_spend), поэтому без Int(Double) напрямую. */
                let доля = Double(сумма) * Double(б.доля) / 100
                let максимум = min(б.баллов, тенгеБезПереполнения(доля))
                if максимум > 0 {
                    self.лист = .баллы(сумма: сумма, баллов: б.баллов, максимум: максимум)
                    return
                }
            }
            self.вопрос = .заморозить(сумма)
        }
    }

    /// escrow.php?action=points — только чтение (_pointsData сайта). Не пришло — без баллов, как у сайта. Ответ обновляет
    /// рубильник приложения (СессияПриложения.баллыВключены): выключены в админке — окна баллов нет, use_points 0.
    private func баллы() async -> (включены: Bool, баллов: Int, доля: Int)? {
        guard let j = try? await ДеньгиСделкиAPI.получить("escrow.php?action=points") else { return nil }
        СессияПриложения.shared.принятьБаллы(j)
        guard СделкиAPI.да(j["ok"]), СессияПриложения.shared.баллыВключены else { return nil }
        let доля = СделкиAPI.целое(j["max_spend"])
        return (СделкиAPI.да(j["enabled"]), СделкиAPI.целое(j["points"]), доля > 0 ? доля : 10)
    }

    /// «Применить и заморозить» / «Без баллов» окна баллов, «Заморозить» окна подтверждения.
    func заморозить(баллами: Int) {
        лист = nil
        guard !идёт else { return }
        идёт = true
        let номер = id
        let шаги: [ШагХода] = [ШагХода(текст: т("ep_s1"), процент: 25, мс: 650),
                               ШагХода(текст: т("ep_s2"), процент: 60, мс: 950),
                               ШагХода(текст: т("ep_s3"), процент: 85, мс: 700)]
        let готово = баллами > 0
            ? т("ep_ok_pts").replacingOccurrences(of: "{p}", with: СделкиФормат.деньги(баллами)) : т("ep_ok_s")
        Task { @MainActor in
            let j = await self.сХодом(заголовок: self.т("ep_title"), шаги: шаги, готово: готово) {
                try await ДеньгиСделкиAPI.отправитьОдинРаз("escrow.php?action=pay",
                                                          тело: ["deal_id": номер, "use_points": баллами])
            }
            let дальше = await self.разобратьОплату(j)
            self.идёт = false
            if let дальше { self.начать(дальше) }
        }
    }

    /// Ответ pay. Возвращает, что открыть следующим нажатием (окно подтверждения ещё раз), или nil.
    private func разобратьОплату(_ j: [String: Any]) async -> ДействиеДенегСделки? {
        typealias A = СделкиAPI
        if МоиОбъявленияAPI.нетСессии(j) {
            карточка?.сессияПропала()
            return nil
        }
        if A.да(j["ok"]) {
            await заново()
            return nil
        }
        if A.да(j["need_otp"]) {
            let назначение = A.строка(j["purpose"])
            лист = .eGov(ЗапросEGov(назначение: назначение.isEmpty ? "escrow_pay" : назначение, ссылка: id,
                                    заголовок: т("otp_face_t"), подсказка: т("otp_face_h"), после: .оплатить))
            return nil
        }
        let недостача = A.целое(j["short"])
        if недостача > 0 {
            if A.да(j["can_card"]) { return await оплатитьКартой() }
            показать(ДеньгиСделкиText.т("short", n: тенге(недостача)))
            пополнитьКошелёк()
            return nil
        }
        if A.да(j["net"]) || A.строка(j["error"]) == "taken" {
            await заново()
            return nil
        }
        let e = A.строка(j["error"])
        if !e.isEmpty {
            let m = A.строка(j["message"])
            показать(m.isEmpty ? ДеньгиСделкиAPI.ошибка(e) : m)
        }
        return nil
    }

    /**
     dealPayCard: «Открываем оплату…» → pay_card {deal_id} → redirect_url — страница банка в листе приложения. Сам
     pay_card денег не списывает: платит человек на странице банка. already_enough — снова окно «Заморозить?».
     */
    private func оплатитьКартой() async -> ДействиеДенегСделки? {
        показать(т("pc_going"))
        do {
            let j = try await ДеньгиСделкиAPI.отправитьОдинРаз("escrow.php?action=pay_card", тело: ["deal_id": id])
            if СделкиAPI.да(j["ok"]), let адрес = URL(string: СделкиAPI.строка(j["redirect_url"])),
               адрес.scheme?.lowercased() == "https" {
                вернулисьСБанка = false
                банкНаЭкране = true
                лист = .банк(адрес, курьер: false)
                return nil
            }
            if СделкиAPI.да(j["already_enough"]) { return .оплатить }
            if МоиОбъявленияAPI.нетСессии(j) {
                карточка?.сессияПропала()
                return nil
            }
            let e = СделкиAPI.строка(j["error"])
            показать(e.isEmpty ? т("pc_fail") : e)
        } catch {
            показать(т("phc_net"))
        }
        return nil
    }

    // MARK: - Возврат со страницы банка (?topup=ok|fail&deal=<id>[&ship=1])

    /**
     То же, что обработчик ?topup= страницы кабинета: fail — «Оплата не прошла…» и сделка заново; ok — «Оплачиваем
     сделку…» / «Оплата прошла — ставим курьера…», затем pay.php?action=confirm до 5 раз с шагом 3 с. Зачислено
     (credited или recent_paid) — курьер: сделка заново; сделка: снова окно «Заморозить?» — сайт зовёт тут dealPay, и
     оплату с кошелька подтверждает человек. Не дождались — «Оплата принята» с балансом.
     */
    func вернулисьСоШлюза(_ итог: ВозвратСоШлюза.Итог) {
        вернулисьСБанка = true
        лист = nil
        guard Config.деньгиСделок else { return }
        if !итог.оплачено {
            показать(т(итог.курьер ? "shp_card_fail" : "pc_cancel"))
            Task { await self.заново() }
            return
        }
        показать(т(итог.курьер ? "shp_card_back" : "pc_paying"))
        guard !идёт else { return }
        идёт = true
        Task { @MainActor in
            var баланс: Int? = nil
            for попытка in 1...5 {
                if let j = try? await ДеньгиСделкиAPI.сверитьОплату() {
                    if j["balance"] != nil { баланс = СделкиAPI.целое(j["balance"]) }
                    let зачтено = СделкиAPI.целое(j["credited"]) > 0 || СделкиAPI.целое(j["recent_paid"]) > 0
                    if СделкиAPI.да(j["ok"]) && зачтено {
                        await self.заново()
                        self.идёт = false
                        if !итог.курьер { self.начать(.оплатить) }
                        return
                    }
                }
                if попытка < 5 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            }
            await self.заново()
            self.идёт = false
            self.вопрос = .ожидание(баланс: баланс)
        }
    }

    /**
     Любой лист закрылся. Был лист банка и возврата с него не было (человек закрыл его сам): денег приложение не
     двигало — только сделка заново; оплатил ли человек до закрытия, скажет она сама (и следующий ?topup= по ссылке).
     */
    func листЗакрыт() {
        if пополнениеНаЭкране {
            /* Кошелёк могли пополнить — сделка заново; оплату с кошелька человек подтвердит новым нажатием. */
            пополнениеНаЭкране = false
            Task { await self.заново() }
            return
        }
        guard банкНаЭкране else { return }
        банкНаЭкране = false
        guard !вернулисьСБанка else { return }
        Task { await self.заново() }
    }

    /**
     showTopup сайта («Недостаточно средств», картой нельзя): при Config.деньгиКошелька — свой экран «Пополнить кошелёк»
     листом поверх карточки (ЛистПополненияКошелька); выключен — кабинет сайта, как на этапе 44. Сам ничего не шлёт.
     */
    private func пополнитьКошелёк() {
        guard Config.деньгиКошелька else {
            открытьСайт?("cabinet.php?go=wallet")
            return
        }
        пополнениеНаЭкране = true
        лист = .пополнение
    }

    // MARK: - Отмена (dealCancel) и взаимное решение (dealMutualResolve)

    /// «Отменить сделку» / «Отменить со сбором 1 000 ₸» окна отмены. Пустая причина — «Отменена пользователем».
    func отменить(причина: String) {
        лист = nil
        let чистая = причина.trimmingCharacters(in: .whitespacesAndNewlines)
        отменитьЗапросом(причина: чистая.isEmpty ? Self.причинаОтмены : String(чистая.prefix(500)), готово: nil)
    }

    /// cancel {reason}. готово nil — текст dealCancel: «Сделка отменена · удержан сбор 1 000 ₸ / · возврат 100%».
    private func отменитьЗапросом(причина: String, готово: String?) {
        послать("escrow.php?action=cancel", ["deal_id": id, "reason": причина]) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                if let готово {
                    self.показать(готово)
                } else {
                    let сбор = СделкиAPI.целое((j["deal"] as? [String: Any])?["escrow_fee_charged"])
                    self.показать(self.т("cn_ok") + self.т(сбор > 0 ? "cn_ok_fee" : "cn_ok_full"))
                }
                await self.заново()
                return
            }
            self.показать(ДеньгиСделкиAPI.ошибка(СделкиAPI.строка(j["error"])))
        }
    }

    // MARK: - Приёмка (dealBuyerConfirm) и «Работа выполнена» (dealSellerConfirm)

    /// «Да, я проверил — подтверждаю» окна приёмки (звёзды — только в delivered, как у сайта).
    func принять(звёзд: Int, отзыв: String) {
        лист = nil
        подтвердитьПолучение(звёзд: звёзд, отзыв: отзыв, взаимно: false)
    }

    /// «Есть претензия — открыть спор».
    func претензия() {
        лист = nil
        нуженСпор = true
    }

    /// buyer_confirm {rating, review}; need_otp — eGov, после него снова окно (приёмки или «Подтвердить получение?»).
    private func подтвердитьПолучение(звёзд: Int, отзыв: String, взаимно: Bool) {
        let тело: [String: Any] = ["deal_id": id, "rating": max(0, min(5, звёзд)),
                                   "review": отзыв.trimmingCharacters(in: .whitespacesAndNewlines)]
        послать("escrow.php?action=buyer_confirm", тело) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                let услуга = СделкиAPI.строка((j["deal"] as? [String: Any])?["kind"]) == "service"
                self.показать(взаимно ? self.т("mr_acc_done") : self.т(услуга ? "bc_ok_svc" : "bc_ok"))
                await self.заново()
                return
            }
            if СделкиAPI.да(j["need_otp"]) {
                let назначение = СделкиAPI.строка(j["purpose"])
                self.лист = .eGov(ЗапросEGov(назначение: назначение.isEmpty ? "escrow" : назначение, ссылка: self.id,
                                             заголовок: self.т("otp_esc_title"), подсказка: self.т("otp_esc_hint"),
                                             после: взаимно ? .договорились : .принять))
                return
            }
            self.показать(ДеньгиСделкиAPI.ошибка(СделкиAPI.строка(j["error"])))
        }
    }

    /// seller_confirm {note}: комментарий — поле «Комментарий (необязательно)…» карточки.
    private func работаВыполнена() {
        let заметка = (карточка?.заметкаИсполнителя ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        послать("escrow.php?action=seller_confirm", ["deal_id": id, "note": заметка]) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                let услуга = СделкиAPI.строка((j["deal"] as? [String: Any])?["kind"]) == "service"
                self.карточка?.заметкаИсполнителя = ""
                self.показать(self.т(услуга ? "sc_ok_svc" : "sc_ok"))
                await self.заново()
                return
            }
            self.показать(ДеньгиСделкиAPI.ошибка(СделкиAPI.строка(j["error"])))
        }
    }

    // MARK: - Код продавца (dealPinSend, dealPinDo)

    /// Четыре цифры (арабские цифры клавиатуры — тоже) → окно «Вы точно получили товар?».
    private func кодПродавца() {
        let цифры = (карточка?.кодПродавца ?? "").compactMap { $0.wholeNumberValue }.map { String($0) }.joined()
        guard цифры.count >= 4 else {
            показать(т("pin_need"))
            return
        }
        вопрос = .код(String(цифры.prefix(4)))
    }

    private func ввестиКод(_ код: String) {
        послать("escrow.php?action=pin_enter", ["deal_id": id, "pin": код]) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                self.карточка?.кодПродавца = ""
                self.показать(self.т(СделкиAPI.строка(j["step"]) == "paid" ? "pin_paid" : "pin_ok"))
                await self.заново()
                return
            }
            let e = СделкиAPI.строка(j["error"])
            if e == "pin_bad" {
                var текстОш = self.т("pin_bad")
                if j["left"] != nil {
                    let сколько = СделкиAPI.строка(j["left"])
                    текстОш = "\(текстОш) · \(self.т("pin_left")): \(сколько)"
                }
                self.показать(текстОш)
            } else if e == "pin_locked" {
                self.показать(self.т("pin_locked"))
            } else {
                self.показать(ТекстыОшибокСделки.текст(e))
            }
        }
    }

    // MARK: - Возврат товара продавцу (clocalReturnConfirm)

    /// cancel {accept_fault, reason}, затем chat.php?action=clocal_return_confirm — как у сайта, его ответ не читается.
    private func возвратПринят(сВиной: Bool) {
        let тело: [String: Any] = ["deal_id": id, "accept_fault": сВиной ? 1 : 0, "reason": Self.причинаВозврата]
        послать("escrow.php?action=cancel", тело) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                _ = try? await ДеньгиСделкиAPI.отправитьОдинРаз("chat.php?action=clocal_return_confirm",
                                                               тело: ["deal_id": self.id])
                self.показать(self.т("ret_done"))
                await self.заново()
                return
            }
            let e = СделкиAPI.строка(j["error"])
            self.показать(e.isEmpty ? self.т("ret_fail") : e)
        }
    }

    // MARK: - Курьер Яндекса: добавить (clocalShipAdd) и отменить (clocalShipDrop)

    private func курьерЯндекса() {
        guard let с = сделка else { return }
        guard let точка = с.точкаКуда else {
            /* Как у сайта: подсказка и сразу окно точки на карте (ЛистТочкиСделки). */
            показать(т("shp_need_pt"))
            карточка?.просьбаТочкиКуда += 1
            return
        }
        guard !идёт else { return }
        идёт = true
        var хвост = "api/ship_quote.php?item=" + СделкиAPI.вАдрес(с.товар) + "&lat=" + String(точка.широта)
        хвост += "&lon=" + String(точка.долгота)
        if с.деньги.уПодъезда { хвост += "&dd=out" }
        /* Сделка оплачена — объявление в резерве (escrow.php ставит reserved), и без номера сделки сервер отвечал
           no_item. С deal= он узнаёт покупателя этой сделки и берёт точку забора, отмеченную продавцом в сделке. */
        хвост += "&deal=" + СделкиAPI.вАдрес(id)
        let запрос = хвост
        Task { @MainActor in
            defer { self.идёт = false }
            guard let j = try? await ДеньгиСделкиAPI.получить(запрос) else {
                self.показать(self.т("err_no_conn"))
                return
            }
            guard СделкиAPI.да(j["ok"]), !СделкиAPI.строка(j["q"]).isEmpty else {
                self.показать(self.ошибкаЦены(j, сделка: с))
                return
            }
            let цена = ЦенаКурьера(j)
            if !цена.бесплатно && цена.другой != nil {
                self.тарифы = цена
            } else {
                self.вопрос = .курьер(цена)
            }
        }
    }

    /// _shpQuoteErr сайта.
    private func ошибкаЦены(_ j: [String: Any], сделка с: Сделка) -> String {
        let причина = СделкиAPI.строка(j["reason"])
        /* Цены перевозчиков (mode carriers) — тоже другой город: курьера Яндекса туда нет. */
        if причина == "intercity" || СделкиAPI.строка(j["mode"]) == "carriers" {
            /* Товар в другом городе: выбор способа дальше — только транспортная компания. */
            карточка?.межгородУзнали = true
            if с.видДоставки == "carrier" {
                return т("shp_e_intercity_car").replacingOccurrences(of: "{name}", with: с.перевозчик.имя)
            }
            return т("shp_e_intercity")
        }
        if причина == "no_courier" { return т("co_ship_bulky") }
        if причина == "slow_down" { return т("co_ship_retry") }
        if СделкиAPI.да(j["ok"]) && СделкиAPI.да(j["free"]) && !СделкиAPI.да(j["courier"]) {
            /* Бесплатная доставка продавца без курьера — точная причина (why сервера, патч 46). */
            switch СделкиAPI.строка(j["why"]) {
            case "no_from": return т("shp_e_free_no_from")
            case "free_costly": return т("shp_e_free_costly")
            default: return т("shp_e_free_self")
            }
        }
        if причина == "free_costly" { return т("shp_e_free_costly") }
        /* Свои причины вместо общего «сюда не возит»: человек должен понять, что делать дальше. */
        switch причина {
        case "no_from":
            /* У продавца нет точной точки (у объявления только город): курьеру неоткуда забрать. */
            return т("shp_e_no_from")
        case "no_item":
            return т("shp_e_no_item")
        case "region":
            return т("shp_e_region")
        case "off":
            return т("shp_e_off")
        case "no_price", "unavailable", "currency":
            return т("shp_e_busy")
        case "bad_args":
            /* Точка сделки не годится — снова окно точки на карте. */
            карточка?.просьбаТочкиКуда += 1
            return т("shp_need_pt")
        default:
            return т("shp_e_na")
        }
    }

    /// Выбор тарифа — сам по себе подтверждение (у сайта после него сразу ship_add).
    func выбратьТариф(_ вариант: ЦенаКурьера.Вариант) {
        тарифы = nil
        добавитьКурьера(ЦенаКурьера(основной: вариант, бесплатно: false, другой: nil))
    }

    private func телоКурьера(_ цена: ЦенаКурьера) -> [String: Any] {
        let с = сделка
        let точка = с?.точкаКуда
        return ["deal_id": id, "ship_q": цена.основной.q, "to_lat": точка?.широта ?? 0, "to_lon": точка?.долгота ?? 0,
                "to_addr": с?.адресКуда ?? ""]
    }

    private func добавитьКурьера(_ цена: ЦенаКурьера) {
        послать("escrow.php?action=ship_add", телоКурьера(цена)) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                self.показать(self.т("shp_added"))
                await self.заново()
                return
            }
            let недостача = СделкиAPI.целое(j["short"])
            if недостача > 0 {
                if цена.бесплатно {
                    self.показать(ДеньгиСделкиText.т("shp_topup", n: self.тенге(недостача)))
                    self.пополнитьКошелёк()
                } else {
                    self.вопрос = .картойЗаКурьера(недостача: недостача, цена)
                }
                return
            }
            /* Бесплатная доставка: курьер дороже выплаты продавцу (ship_add, reason free_costly). */
            if СделкиAPI.строка(j["reason"]) == "free_costly" {
                self.показать(self.т("shp_e_free_costly"))
                return
            }
            self.показать(self.текстОтвета(j, запасной: self.т("err_failed")))
        }
    }

    /// ship_add_card → банк (возврат ?topup=…&ship=1). already_enough — не второй ship_add сам, а снова окно «Оплатить».
    private func курьерКартой(_ цена: ЦенаКурьера) {
        послать("escrow.php?action=ship_add_card", телоКурьера(цена)) { [weak self] j in
            guard let self else { return }
            let ok = СделкиAPI.да(j["ok"])
            if ok, let адрес = URL(string: СделкиAPI.строка(j["redirect_url"])), адрес.scheme?.lowercased() == "https" {
                self.вернулисьСБанка = false
                self.банкНаЭкране = true
                self.лист = .банк(адрес, курьер: true)
                return
            }
            if ok && СделкиAPI.да(j["already"]) {
                self.показать(self.т("shp_added"))
                await self.заново()
                return
            }
            if СделкиAPI.да(j["already_enough"]) {
                self.вопрос = .курьер(цена)
                return
            }
            self.показать(self.текстОтвета(j, запасной: self.т("shp_card_e")))
            if СделкиAPI.да(j["too_small"]) || СделкиAPI.да(j["too_big"]) || СделкиAPI.да(j["payments_off"]) {
                self.пополнитьКошелёк()
            }
        }
    }

    /// ship_drop {accept_paid}: курьер уже выехал (paid_cancel) — второе окно, и только его «Отменить курьера» шлёт 1.
    private func заберуСам(платно: Bool) {
        послать("escrow.php?action=ship_drop", ["deal_id": id, "accept_paid": платно ? 1 : 0]) { [weak self] j in
            guard let self else { return }
            if СделкиAPI.да(j["ok"]) {
                let списано = СделкиAPI.целое(j["charged"])
                if списано > 0 {
                    self.показать(ДеньгиСделкиText.т("shp_dropped_charged", n: self.тенге(списано)))
                } else {
                    self.показать(self.т(СделкиAPI.целое(j["kept"]) > 0 ? "shp_dropped_paid" : "shp_dropped"))
                }
                await self.заново()
                return
            }
            if СделкиAPI.да(j["paid_cancel"]) && !платно {
                self.вопрос = .платнаяОтмена(сумма: СделкиAPI.целое(j["fee"]), продавец: СделкиAPI.да(j["by_seller"]))
                return
            }
            self.показать(self.текстОтвета(j, запасной: self.т("err_failed")))
        }
    }

    // MARK: - eGov прошёл

    /// otpStepOpen → onOk сайта: исходное действие заново — у натива это снова окно подтверждения, не сам запрос.
    func eGovПройден(_ з: ЗапросEGov) {
        лист = nil
        let дальше = з.после
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            self.начать(дальше)
        }
    }
}

// MARK: - Итог хода (общий для карточки и окон создания)

enum ЗапускХода {
    /// Конец хода: «под защитой» (1,2 с), «уже зарезервирован» (до 10 с или нажатие), «не получилось» (1,3 с) — или тихо.
    @MainActor
    static func итог(_ j: [String: Any], готово: String, ход: (ХодДенег) -> Void, закрыт: () -> Bool) async {
        let т: (String) -> String = ДеньгиСделкиText.т
        if СделкиAPI.да(j["ok"]) {
            ход(ХодДенег(заголовок: т("ep_ok_t"), подпись: готово, процент: 100, итог: .готово))
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            return
        }
        let тихо = СделкиAPI.да(j["need_otp"]) || СделкиAPI.целое(j["short"]) > 0 || СделкиAPI.да(j["need_terms"])
            || МоиОбъявленияAPI.нетСессии(j)
        if тихо { return }
        let e = СделкиAPI.строка(j["error"])
        let m = СделкиAPI.строка(j["message"])
        if e == "taken" {
            ход(ХодДенег(заголовок: т("ep_taken_t"), подпись: m.isEmpty ? т("ep_taken_m") : m, процент: 100, итог: .занято))
            for _ in 0..<40 {
                if закрыт() { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            return
        }
        let подпись = !m.isEmpty ? m : (!e.isEmpty ? e : т("ep_fail"))
        ход(ХодДенег(заголовок: т("ep_fail_t"), подпись: подпись, процент: 100, итог: .ошибка))
        try? await Task.sleep(nanoseconds: 1_300_000_000)
    }
}
