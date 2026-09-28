import SwiftUI
import UIKit

/**
 ПОПОЛНЕНИЕ И ВЫВОД КОШЕЛЬКА — ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 🔴 ВСЁ ЗДЕСЬ — ТОЛЬКО ЗА Config.деньгиКошелька (стоит false). Пока рубильник выключен, ни одна функция этого файла не
 шлёт запрос (каждая начинается с guard): кнопки «Пополнить» и «Вывести» открывают кабинет сайта, как было до этапа 47.
 Включать — только решением владельца после живой проверки (список ниже).

 Код сайта — докачанный модуль js/cabinet-wallet.min.js (карта §5.2–§5.3 писалась без него: теперь тела известны).
 Пополнение (doTopup):
   · POST pay.php?action=create {csrf, amount, fresh} → {ok, redirect_url} — страница банка (Freedom Pay). fresh — «после
     неудачной оплаты» (sessionStorage.ulx_pay_retry сайта: ставит возврат ?topup=fail, снимает следующий doTopup);
   · ответ payments_off → сайт сам шлёт POST cabinet.php?action=topup {csrf, amount, fresh} → ok «Баланс пополнен на N ₸»;
     need_verify → «Нужна верификация»; иначе error || «Онлайн-оплата временно недоступна». Натив второй денежный запрос
     сам не шлёт: спрашивает «Пополнить кошелёк?» ещё раз (то же правило, что у этапа 44 для повторов сайта);
   · банк вернул (?topup=ok|fail) — pay.php?action=confirm "{}" до пяти раз с шагом 3 с (tpmOpen: «Проверяем оплату…»,
     «Кошелёк пополнен», «Оплата принята», «Оплата не прошла»).
 Вывод (showWithdraw, wdUpdateBtn, doWithdraw):
   · правила суммы и расчёт комиссии — ПравилаВывода (wdAmountOk, wdCalcFee, showWithdraw) из ставок wallet_info;
   · способ — только «Банковская карта» (в разметке страницы он один, сайт отмечает его сам на шаге 2); для карты
     реквизиты не шлются (details ""), карту человек вводит на странице банка по ссылке выплаты;
   · POST cabinet.php?action=withdraw {csrf, amount, method, details} → ok (fee, payout, new_balance, wid, payout_url) —
     окно «Заявка принята»; need_otp — окно eGov (otp_step_create purpose "withdraw", ref = сумма), need_terms — окно
     соглашения этапа 40, need_split — «Стать магазином», payout_failed — «Не удалось вывести»; иначе «Ошибка: …».
     После eGov и соглашения сайт сам повторяет doWithdraw — натив просит нажать ещё раз (денежный POST — только по нажатию);
   · авто-вывод: POST cabinet.php?action=wd_autopay {csrf, enabled:true, method, details} / {csrf, enabled:false} — по
     переключателю, ответ details_mask.
 Каждый денежный POST — ровно один раз (ДеньгиСделкиAPI.отправитьОдинРаз): ни повтора на «csrf», ни при обрыве сети.

 ПРОВЕРИТЬ ВЖИВУЮ (до включения): pay.php?action=create на 100 ₸ и адрес возврата банка (?topup=ok — в листе); ответ
 payments_off; withdraw на минимальную сумму верифицированным аккаунтом и need_otp; wd_autopay вкл/выкл; payout_link и
 возврат ?payout=back → payout_outcome.
 */

// MARK: - Правила вывода (wdAmountOk, wdCalcFee, showWithdraw)

/// Итог wdCalcFee: без комиссии / под комиссию, банковский сбор, комиссия площадки, всего удержано, к зачислению.
struct РасчётВывода: Equatable {
    let безКомиссии: Int
    let подКомиссию: Int
    let сборБанка: Int
    let комиссия: Int
    let всего: Int
    let кЗачислению: Int
    let процент: Double
}

struct ПравилаВывода {
    let с: СведенияКошелька

    /// wdAvail: available, нет — balance.
    var доступно: Int { с.доступно }
    /// wd_min || 5000 — для подсказки и пресетов (showWithdraw).
    private var минимумПоказ: Int { с.минимум > 0 ? тенгеБезПереполнения(с.минимум) : 5000 }
    /// wd_max || 1 500 000.
    var потолок: Int { с.максимум > 0 ? тенгеБезПереполнения(с.максимум) : 1_500_000 }
    /// l = min(доступно, потолок).
    var предел: Int { min(доступно, потолок) }
    private var остатокПоказ: Int { с.остатокМин > 0 ? тенгеБезПереполнения(с.остатокМин) : 1000 }
    /// s — нижняя граница пресетов: остаток целиком, если он меньше минимума.
    var низ: Int { (предел >= остатокПоказ && предел < минимумПоказ) ? остатокПоказ : минимумПоказ }

    /// Подсказка под полем: «Остаток N ₸ выводится целиком» или строка сервера wd_min.
    func подсказкаМинимума(строкаСтраницы: String) -> String {
        if низ == остатокПоказ && предел >= остатокПоказ {
            return КошелёкText.т("wd_min_tail", n: КошелёкФормат.деньги(предел))
        }
        if !строкаСтраницы.isEmpty { return строкаСтраницы }
        return КошелёкText.т("wd_min", n: КошелёкФормат.деньги(минимумПоказ))
    }

    /// Пресеты: 5 000 / 10 000 / 20 000 в пределах и «всё». Пусто — выводить нечего.
    var пресеты: [Int] {
        guard предел >= низ else { return [] }
        var список = [5000, 10000, 20000].filter { $0 <= предел && $0 >= низ }
        if !список.contains(предел) { список.append(предел) }
        return список
    }

    /// wdAmountOk — сырые wd_min / wd_tail_min / wd_max (без запасных чисел: нет минимума — вывода нет).
    func годна(_ e: Int) -> Bool {
        let n = с.минимум
        let d = с.остатокМин
        if e <= 0 || e > доступно || n <= 0 { return false }
        if с.максимум > 0 && Double(e) > с.максимум { return false }
        return Double(e) >= n || (e == доступно && Double(e) >= d)
    }

    /// wdCalcFee — формула сайта целиком (Math.round, Math.ceil, Math.max, Math.min).
    func расчёт(_ e: Int) -> РасчётВывода {
        let сумма = Double(e)
        let n = max(0, с.безКомиссии)
        let d = с.комиссияПроц
        let a = с.эквайрВыводПроц
        let o = с.эквайрВыводМин
        let r = с.эквайрВводПроц
        let l = с.эквайрВводМин
        let i = с.наценка
        let s = min(сумма, n)
        let c = max(0, сумма - s)
        let u = (сумма * a / 100).rounded()
        let w = сумма > 0 ? max((сумма * a / 100).rounded(.up), o) : 0
        let p = max(0, w - u)
        var v: Double = 0
        if c > 0 {
            let вход = max((c * r / 100).rounded(.up), l) + (c * a / 100).rounded()
            v = max((c * d / 100).rounded(.up), (вход * i).rounded(.up))
        }
        let m = min(p + v, max(0, сумма - 1))
        /* Ставки — с сервера: бесконечность или NaN в них не должны уронить приложение (тенгеБезПереполнения). */
        let всего = тенгеБезПереполнения(m)
        return РасчётВывода(безКомиссии: тенгеБезПереполнения(s), подКомиссию: тенгеБезПереполнения(c),
                            сборБанка: тенгеБезПереполнения(p), комиссия: тенгеБезПереполнения(v), всего: всего,
                            кЗачислению: max(0, e - всего), процент: d)
    }
}

/**
 Цифры из ввода суммы. Берутся только десятичные цифры 0…9 трёх записей: ASCII, арабско-индийские (٠…٩, U+0660…0669,
 клавиатура арабского iPhone) и восточные арабско-индийские (۰…۹, U+06F0…06F9). wholeNumberValue сюда не годится: он
 понимает и «万» (10 000), «½», «Ⅻ» — такая «цифра» больше 9 сломала бы сумму. Цифр не больше девяти (999 999 999 ₸),
 поэтому ×10 и + не переполняют Int; для верности — сложение с проверкой.
 */
func цифрыКошелька(_ текст: String) -> Int {
    var цифры: [Int] = []
    for знак in текст {
        guard let ц = цифраВвода(знак) else { continue }
        цифры.append(ц)
        if цифры.count == 9 { break }
    }
    var итог = 0
    for ц in цифры {
        let (умножено, п1) = итог.multipliedReportingOverflow(by: 10)
        let (сложено, п2) = умножено.addingReportingOverflow(ц)
        if п1 || п2 { return 0 }
        итог = сложено
    }
    return итог
}

/// Одна десятичная цифра 0…9 или nil (см. цифрыКошелька).
func цифраВвода(_ знак: Character) -> Int? {
    let скаляры = знак.unicodeScalars
    guard скаляры.count == 1, let с = скаляры.first else { return nil }
    let v = Int(с.value)
    if v >= 0x30 && v <= 0x39 { return v - 0x30 }
    if v >= 0x660 && v <= 0x669 { return v - 0x660 }
    if v >= 0x6F0 && v <= 0x6F9 { return v - 0x6F0 }
    return nil
}

/**
 Double → целые тенге без падения: Int(Double) роняет приложение на NaN, бесконечности и числах за пределами Int.
 Ставки и суммы приходят с сервера (wallet_info, страница кабинета) — любое из них может оказаться мусором; мусор
 становится 0, а огромное — потолком в ±10¹⁵ ₸ (больше тенге не бывает, а сложение двух таких не переполнит Int).
 */
func тенгеБезПереполнения(_ x: Double) -> Int {
    guard x.isFinite else { return 0 }
    let предел = 1_000_000_000_000_000.0
    if x >= предел { return 1_000_000_000_000_000 }
    if x <= -предел { return -1_000_000_000_000_000 }
    return Int(x.rounded())
}

// MARK: - Пополнение

@MainActor
final class ПополнениеМодель: ObservableObject {
    static let суммы: [Int] = [500, 1000, 2000, 5000, 10000, 50000]
    static let минимум = 100
    static let максимум = 1_000_000

    /// Окно tpmOpen.
    enum Итог: Equatable {
        case проверяем
        case пополнен(сумма: Int, баланс: Int?)
        case принята(баланс: Int?)
        case неПрошла
    }

    /// selectedTopupAmt: 0 — сумма не выбрана.
    @Published private(set) var выбрано = 0
    @Published var своя = "" {
        didSet { if своя != oldValue && !меняемСами { применитьСвою() } }
    }
    /// Последним трогали своё поле (подпись кнопки «Минимум / Максимум»).
    @Published private(set) var своёПоле = false
    @Published private(set) var идёт: String? = nil
    @Published var банк: АдресБанка? = nil
    @Published var итог: Итог? = nil
    @Published var ошибка: String? = nil
    /// payments_off: спросить ещё раз, прежде чем слать cabinet.php?action=topup.
    @Published var безБанка: Int? = nil
    @Published var верификация: String? = nil

    /// ulx_pay_retry сайта: последняя оплата не прошла — следующий create с fresh:true (на время запуска, как sessionStorage).
    private static var повторОплаты = false
    private var последнийСвежий = false
    private var меняемСами = false

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    /// Подпись кнопки #topup-btn-txt.
    var подписьКнопки: String {
        if let надпись = идёт { return надпись }
        if выбрано > 0 { return КошелёкText.т("topup_btn", n: КошелёкФормат.деньги(выбрано)) }
        if своёПоле {
            return т(цифрыКошелька(своя) > Self.максимум ? "topup_max" : "topup_min")
        }
        return т("topup_choose_btn")
    }

    /// selectTopup: чип — сумма, своё поле пустеет.
    func выбрать(_ сумма: Int) {
        меняемСами = true
        своя = ""
        меняемСами = false
        своёПоле = false
        выбрано = сумма
    }

    /// topupStep: ±1000 от своей суммы, в пределах 100…1 000 000.
    func шаг(_ e: Int) {
        let r = abs(e)
        let o = цифрыКошелька(своя)
        var n: Int
        if o > 0 {
            n = e > 0 ? (o / r) * r + r : Int((Double(o) / Double(r)).rounded(.up)) * r - r
        } else {
            n = e > 0 ? r : Self.минимум
        }
        n = min(max(n, Self.минимум), Self.максимум)
        своя = String(n)
    }

    /// topupCustom: в пределах — выбрана, иначе кнопка «Минимум 100 ₸» / «Максимум 1 000 000 ₸».
    private func применитьСвою() {
        let t = цифрыКошелька(своя)
        своёПоле = true
        выбрано = (t >= Self.минимум && t <= Self.максимум) ? t : 0
    }

    /// Идёт сверка после банка (окно «Проверяем оплату…»): лист не смахнуть, второй сверки нет.
    var сверяем: Bool {
        if case .проверяем? = итог { return true }
        return false
    }

    /**
     doTopup — только за рубильником и только по нажатию. Кнопка выключена, пока идёт (идёт != nil), и второй раз
     функция ничего не шлёт. Перед денежным POST — только чтение страницы кабинета: MK_ESCROW_PAUSED (см. гарантНаПаузе).
     */
    func пополнить() {
        guard Config.деньгиКошелька, выбрано > 0, выбрано <= Self.максимум, идёт == nil, !сверяем else { return }
        let сумма = выбрано
        идёт = т("topup_processing")
        Task { @MainActor in
            /* 🔴 Правило App Store 3.1.1: пока гарант-сделка на паузе, пополнение с карты тратится только на услуги Kliko
               (ТОП, слоты, PRO — wal_topup_rule сайта), то есть это покупка цифрового без In-App Purchase. Такое
               пополнение приложение не продаёт: текст сайта «Эта возможность недоступна в приложении.», запроса нет.
               Флаг не прочитать — тоже без запроса (нет сети — «Нет соединения»). */
            guard let пауза = await ПополнениеМодель.гарантНаПаузе() else {
                self.идёт = nil
                self.ошибка = self.т("err_net")
                return
            }
            if пауза {
                self.идёт = nil
                self.ошибка = self.т("topup_paused_app")
                return
            }
            let свежий = ПополнениеМодель.повторОплаты
            ПополнениеМодель.повторОплаты = false
            self.последнийСвежий = свежий
            do {
                let j = try await КошелёкAPI.отправитьОдинРаз("pay.php?action=create",
                                                              тело: ["amount": сумма, "fresh": свежий])
                let адрес = КошелёкAPI.строка(j["redirect_url"])
                if КошелёкAPI.да(j["ok"]), let url = URL(string: адрес), url.scheme?.lowercased() == "https" {
                    self.идёт = self.т("topup_going")
                    self.банк = АдресБанка(адрес: url)
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    self.идёт = nil
                    return
                }
                self.идёт = nil
                if КошелёкAPI.да(j["payments_off"]) {
                    self.безБанка = сумма
                } else {
                    self.ошибка = self.текст(КошелёкAPI.строка(j["error"]), запасной: self.т("err_generic"))
                }
            } catch {
                /* Ответ не дошёл. pay.php?action=create сам денег не списывает (платят на странице банка), но и повтора
                   нет: следующий create — только новым нажатием. */
                self.идёт = nil
                self.ошибка = self.т("err_net")
            }
        }
    }

    /**
     MK_ESCROW_PAUSED страницы кабинета (var MK_ESCROW_PAUSED=false; в снимке — false). true — пауза, false — нет или
     флага на странице нет вовсе, nil — страницу не прочитать.
     */
    static func гарантНаПаузе() async -> Bool? {
        guard let страница = try? await КабинетСайта.страницаКабинета() else { return nil }
        let html = страница.html
        let шаблон = #"MK_ESCROW_PAUSED\s*=\s*(true|1|!0)\b"#
        return html.range(of: шаблон, options: .regularExpression) != nil
    }

    /// Лист банка закрыли сами (без возврата ?topup=): денег приложение не двигало — только свежий кошелёк.
    func листБанкаЗакрыт() {
        банк = nil
        Task { @MainActor in await КошелёкМодель.shared.загрузить() }
    }

    /// Второй вопрос после payments_off — «Пополнить на N ₸»: POST cabinet.php?action=topup один раз.
    func пополнитьБезБанка(_ сумма: Int, готово: @escaping () -> Void) {
        guard Config.деньгиКошелька, сумма > 0, идёт == nil else { return }
        идёт = т("topup_processing")
        let свежий = последнийСвежий
        Task { @MainActor in
            defer { self.идёт = nil }
            do {
                let j = try await КошелёкAPI.отправитьОдинРаз("cabinet.php?action=topup",
                                                              тело: ["amount": сумма, "fresh": свежий])
                if КошелёкAPI.да(j["ok"]) {
                    let кошелёк = КошелёкМодель.shared
                    кошелёк.показать(КошелёкText.т("topup_done", n: КошелёкФормат.деньги(сумма)))
                    await кошелёк.загрузить()
                    готово()
                    return
                }
                if КошелёкAPI.да(j["need_verify"]) {
                    self.верификация = КошелёкAPI.строка(j["error"])
                    return
                }
                self.ошибка = self.текст(КошелёкAPI.строка(j["error"]), запасной: self.т("topup_off"))
            } catch {
                /* Ответ не дошёл, а деньги могли зачислиться: без повтора — только свежий баланс. */
                self.ошибка = self.т("err_net")
                await КошелёкМодель.shared.загрузить()
            }
        }
    }

    /// Банк вернул человека (лист перехватил ?topup=, или ссылка ?topup= пришла снаружи).
    func вернулисьСБанка(оплачено: Bool) {
        банк = nil
        guard Config.деньгиКошелька, !сверяем else { return }
        guard оплачено else {
            Self.повторОплаты = true
            итог = .неПрошла
            return
        }
        итог = .проверяем
        Task { @MainActor in
            var баланс: Int? = nil
            for попытка in 1...5 {
                if let j = try? await ДеньгиСделкиAPI.сверитьОплату() {
                    let б = j["balance"]
                    if б != nil && !(б is NSNull) { баланс = КошелёкAPI.тенге(б) }
                    let зачислено = КошелёкAPI.тенге(j["credited"])
                    if КошелёкAPI.да(j["ok"]) && (зачислено > 0 || КошелёкAPI.число(j["recent_paid"]) > 0) {
                        self.итог = .пополнен(сумма: зачислено, баланс: баланс)
                        await КошелёкМодель.shared.загрузить()
                        return
                    }
                }
                if попытка < 5 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            }
            self.итог = .принята(баланс: баланс)
            await КошелёкМодель.shared.загрузить()
        }
    }

    private func текст(_ e: String, запасной: String) -> String {
        let чистая = e.trimmingCharacters(in: .whitespacesAndNewlines)
        return (чистая.isEmpty || КабинетСайта.машинныйКод(чистая)) ? запасной : чистая
    }
}

// MARK: - Вывод

@MainActor
final class ВыводМодель: ObservableObject {
    /// wdResultModal: заявка принята.
    struct Итог: Identifiable, Equatable {
        let id = UUID()
        let сумма: Int
        let комиссия: Int
        let кЗачислению: Int
        /// payout_url — выплату подтвердили сразу: «Указать карту».
        let ссылка: URL?
    }

    /// Окно eGov (otpStepOpen "withdraw").
    struct ПроверкаEGov: Identifiable {
        let id = UUID()
        let запрос: ЗапросEGov
    }

    /// Окно соглашения (termsRenewAsk).
    struct Условия: Identifiable {
        let id = UUID()
        let редакция: String
        let пункты: [String]
    }

    @Published var шаг = 1
    @Published var сумма = ""
    /// _wdMethod: пусто — не выбран. Способ в разметке один — «card».
    @Published private(set) var способ = ""
    @Published private(set) var идёт = false
    @Published private(set) var автоИдёт = false
    @Published var итог: Итог? = nil
    @Published var eGov: ПроверкаEGov? = nil
    @Published var условия: Условия? = nil
    /// need_split без pending — вопрос «Стать магазином».
    @Published var магазин = false
    @Published var ошибка: String? = nil
    @Published var подсказка: String? = nil
    @Published var банк: АдресБанка? = nil

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var сведения: СведенияКошелька { КошелёкМодель.shared.сведения ?? СведенияКошелька() }
    var правила: ПравилаВывода { ПравилаВывода(с: сведения) }
    var число: Int { цифрыКошелька(сумма) }
    var годна: Bool { правила.годна(число) }

    /// wdSetAmount.
    func поставить(_ n: Int) {
        сумма = String(n)
    }

    /// wdStep: на шаг 2 — только с годной суммой; способ один — отмечается сам.
    func перейти(_ куда: Int) {
        var к = куда
        if к == 2 && !годна { к = 1 }
        шаг = к
        if к == 2 && способ.isEmpty { способ = "card" }
    }

    /// Подпись #wd-next.
    var подписьДалее: String {
        let e = число
        if годна { return КошелёкText.т("wd_next_sum", n: КошелёкФормат.деньги(e)) }
        let c = сведения.максимум
        if e > 0 && c > 0 && Double(e) > c {
            return КошелёкText.т("wd_over_cap", n: КошелёкФормат.деньги(тенгеБезПереполнения(c)))
        }
        if e > 0 && e > правила.доступно {
            return КошелёкText.т("wd_over_avail", n: КошелёкФормат.деньги(правила.доступно))
        }
        return т("wd_next")
    }

    /// Кнопка #wd-btn доступна: сумма годна и способ выбран (для карты реквизиты не нужны).
    var можноВывести: Bool { годна && !способ.isEmpty && !идёт }

    var подписьВывести: String {
        if идёт { return т("wd_sending") }
        if годна && !способ.isEmpty {
            return КошелёкText.т("wd_confirm_btn", n: КошелёкФормат.деньги(число))
        }
        return т("wd_submit")
    }

    /// doWithdraw — только за рубильником и по нажатию «Всё верно, вывести N ₸».
    func вывести(закрыть: @escaping () -> Void, открыть: @escaping (URL) -> Void) {
        guard Config.деньгиКошелька, !идёт else { return }
        let e = число
        guard e > 0, !способ.isEmpty else {
            ошибка = т("wd_need")
            return
        }
        /* wdAmountOk ещё раз: кнопка и так выключена без годной суммы, но денежный POST — только с ней. */
        guard годна else { return }
        let метод = способ
        идёт = true
        подсказка = nil
        Task { @MainActor in
            defer { self.идёт = false }
            do {
                let j = try await КошелёкAPI.отправитьОдинРаз("cabinet.php?action=withdraw",
                                                              тело: ["amount": e, "method": метод, "details": ""])
                await self.разобрать(j, сумма: e, закрыть: закрыть, открыть: открыть)
            } catch {
                /* Ответ не дошёл, а заявка могла уйти: повтора нет, только свежий баланс (заявку покажет кошелёк). */
                self.ошибка = self.т("err_net")
                await КошелёкМодель.shared.загрузить()
            }
        }
    }

    private func разобрать(_ j: [String: Any], сумма e: Int, закрыть: @escaping () -> Void,
                           открыть: @escaping (URL) -> Void) async {
        typealias A = КошелёкAPI
        if A.да(j["ok"]) {
            let выплата = j["payout"]
            let к = (выплата == nil || выплата is NSNull) ? e : A.тенге(выплата)
            let адрес = A.строка(j["payout_url"])
            var ссылка: URL? = nil
            if let u = URL(string: адрес), u.scheme?.lowercased() == "https" { ссылка = u }
            итог = Итог(сумма: e, комиссия: A.тенге(j["fee"]), кЗачислению: к, ссылка: ссылка)
            /* Заявка ушла — сумма из поля стирается: следующий «Вывести» начнётся с пустого поля, а не с этой же суммы. */
            сумма = ""
            шаг = 1
            await КошелёкМодель.shared.загрузить()
            return
        }
        if A.да(j["need_otp"]) {
            /* Окно eGov этапа 44 (ОкноEGov) шлёт только назначение и ссылку; поле «после» окно не читает — его
               читает лишь карточка сделки, поэтому здесь оно формальное. Повтор вывода — нажатием человека. */
            let запрос = ЗапросEGov(назначение: "withdraw", ссылка: String(e), заголовок: т("otp_wd_title"),
                                    подсказка: т("otp_wd_hint"), после: .оплатить)
            eGov = ПроверкаEGov(запрос: запрос)
            return
        }
        if A.да(j["need_terms"]) {
            let с = try? await КабинетСайта.состояние()
            условия = Условия(редакция: с?.редакция ?? "", пункты: с?.чтоИзменилось ?? [])
            return
        }
        if A.да(j["need_split"]) {
            let текстОш = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
            КошелёкМодель.shared.показать(текстОш.isEmpty ? т("split_need") : текстОш)
            if A.строка(j["split_status"]) != "pending" {
                магазин = true
            } else if let u = ВыводМодель.адресМагазина {
                закрыть()
                открыть(u)
            }
            return
        }
        if A.да(j["payout_failed"]) {
            let суммаОтвета = j["amount"]
            let итогСумма = (суммаОтвета == nil || суммаОтвета is NSNull || A.тенге(суммаОтвета) == 0) ? e : A.тенге(суммаОтвета)
            let новый = j["new_balance"]
            let баланс: Int? = (новый == nil || новый is NSNull) ? nil : A.тенге(новый)
            let кошелёк = КошелёкМодель.shared
            закрыть()
            кошелёк.итогВыплаты = КошелёкМодель.ИтогВыплаты(отправлено: false, сумма: итогСумма, баланс: баланс)
            await кошелёк.загрузить()
            return
        }
        let ош = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let причина = (ош.isEmpty || КабинетСайта.машинныйКод(ош)) ? т("wd_err_retry") : ош
        ошибка = КошелёкText.т("wd_err", ["e": причина])
    }

    /// openShop сайта — раздел «Компания» модуля business (этап 48): страницей кабинета сайта (?s=company).
    static var адресМагазина: URL? { Config.страницаСайта("cabinet.php?s=company") }

    /// После eGov сайт сам зовёт doWithdraw ещё раз; натив — просит нажать (денежный POST только по нажатию).
    func eGovПройден() {
        eGov = nil
        подсказка = т("otp_passed")
    }

    // MARK: Авто-вывод (wdAutoToggle)

    /// Переключатель: вкл — нужен способ; POST wd_autopay один раз; не вышло — назад.
    func переключитьАвто(_ вкл: Bool) {
        guard Config.деньгиКошелька, !автоИдёт else { return }
        let кошелёк = КошелёкМодель.shared
        if вкл && способ.isEmpty {
            кошелёк.показать(т("wd_auto_need"))
            return
        }
        автоИдёт = true
        let тело: [String: Any] = вкл ? ["enabled": true, "method": способ, "details": ""] : ["enabled": false]
        let метод = способ
        Task { @MainActor in
            defer { self.автоИдёт = false }
            do {
                let j = try await КошелёкAPI.отправитьОдинРаз("cabinet.php?action=wd_autopay", тело: тело)
                guard КошелёкAPI.да(j["ok"]) else {
                    let e = КошелёкAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    кошелёк.показать(e.isEmpty || КабинетСайта.машинныйКод(e) ? self.т("err_generic") : e)
                    return
                }
                кошелёк.изменитьАвто(вкл, способ: метод, маска: КошелёкAPI.строка(j["details_mask"]))
                кошелёк.показать(self.т(вкл ? "wd_auto_done_on" : "wd_auto_done_off"))
            } catch {
                кошелёк.показать(self.т("err_net"))
            }
        }
    }
}
