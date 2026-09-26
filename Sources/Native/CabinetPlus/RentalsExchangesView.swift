import SwiftUI
import UIKit

/**
 «МОИ АРЕНДЫ» И «ОБМЕНЫ» — СВОИМИ ЭКРАНАМИ (showRentals / showExchanges модуля js/cabinet-deals.min.js;
 владелец: «кабинет полностью SwiftUI»).

 Аренды (loadRentals, rentTab, rentAction, rentDocBlock):
   · GET  cabinet.php?action=my_rentals&me_id=<я> → {rentals[{id, _role: seller|buyer, status, item{images[]},
     item_title, start_date, end_date, days, total, deposit, message, _housing, _doc_avail, _doc{paid, mine, other, both},
     _doc_price, _doc_sign}]};
   · POST cabinet.php?action=rental_action {csrf, rental_id, act: confirm|decline|activate|return|cancel|dispute, reason};
   · договор: «Открыть договор» — свой PDF (cabinet.php?action=rent_contract&id=, ОкноДокумента); «Подписать через eGov» —
     rent_doc_sign {rental_id}: need_otp — своё окно eGov (ОкноEGov: otp_step_create → remote.biometric.kz, otp_step_check),
     после него подпись ещё раз; «Оформить договор» (rent_doc_buy) — платный документ: при цене 0 (бесплатно по PRO)
     своим вызовом, при цене — кабинет сайта (списание с кошелька за документ, правило 3.1.1).
 Обмены (loadExchanges, exchRespond, exchCancel):
   · GET  cabinet.php?action=my_exchanges&me_id=<я> → {ok, exchanges[{id, seller_id, buyer_id, item, offer_item,
     item_id, offer_item_id, status, surcharge, surcharge_dir, comment, buyer_name, seller_name, buyer_phone,
     seller_phone}]}; входящий — если seller_id = я;
   · POST exchange_respond {csrf, exchange_id, decision: accept|decline}; exchange_cancel {csrf, exchange_id} после
     вопроса сайта «Отменить обмен?»;
   · «Чат с …» — своя переписка (ЧатЦель.продавец) в стеке «Кабинета»; объявления — своя карточка (Listing).
 */

// MARK: - Аренды

struct АрендаКабинета: Identifiable, Equatable {
    let id: String
    let роль: String
    let статус: String
    let картинка: String
    let название: String
    let начало: String
    let конец: String
    let дней: Int
    let итого: Double
    let залог: Double
    let сообщение: String
    let жильё: Bool
    let договорДоступен: Bool
    let договорОплачен: Bool
    let подписалЯ: Bool
    let подписалДругой: Bool
    let подписалиОба: Bool
    let ценаДоговора: Int
    let подписьНужна: Bool
    let подписьЯвно: Bool

    init?(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        роль = A.строка(j["_role"])
        статус = A.строка(j["status"])
        let товар = (j["item"] as? [String: Any]) ?? [:]
        картинка = ((товар["images"] as? [Any])?.first).map { A.строка($0) } ?? ""
        название = A.строка(j["item_title"])
        начало = A.строка(j["start_date"])
        конец = A.строка(j["end_date"])
        дней = A.целое(j["days"])
        итого = A.число(j["total"])
        залог = A.число(j["deposit"])
        сообщение = A.строка(j["message"])
        жильё = A.да(j["_housing"])
        let документ = j["_doc"] as? [String: Any]
        договорДоступен = A.да(j["_doc_avail"]) && документ != nil
        договорОплачен = A.да(документ?["paid"])
        подписалЯ = A.да(документ?["mine"])
        подписалДругой = A.да(документ?["other"])
        подписалиОба = A.да(документ?["both"])
        ценаДоговора = A.целое(j["_doc_price"])
        /* _doc_sign: false — подписывать уже не нужно (аренда завершена); нет поля — нужно. */
        if let знак = j["_doc_sign"] {
            подписьЯвно = true
            подписьНужна = A.да(знак)
        } else {
            подписьЯвно = false
            подписьНужна = true
        }
    }

    var продавец: Bool { роль == "seller" }
}

@MainActor
final class АрендыМодель: ObservableObject {
    @Published var роль = "seller"
    @Published private(set) var все: [АрендаКабинета] = []
    @Published private(set) var грузим = false
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нуженВход = false
    @Published var занято: Set<String> = []
    @Published private(set) var плашка: String? = nil
    @Published var eGov: ЗапросEGov? = nil
    private var подписатьПосле: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var показанные: [АрендаКабинета] { все.filter { $0.роль == роль } }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    func загрузить() async {
        грузим = все.isEmpty
        defer { грузим = false }
        let я = await ЗапросыКабинета.мойНомер()
        let номер = я.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? я
        do {
            let сырой = try await МоиОбъявленияAPI.получить("cabinet.php?action=my_rentals&me_id=" + номер)
            guard let j = сырой else {
                ошибка = т("err_load")
                return
            }
            if МоиОбъявленияAPI.нетСессии(j) {
                ошибка = CabinetText.т("signed_out")
                нуженВход = true
                return
            }
            все = ((j["rentals"] as? [Any]) ?? []).compactMap { запись -> АрендаКабинета? in
                guard let а = запись as? [String: Any] else { return nil }
                return АрендаКабинета(а)
            }
            ошибка = nil
            нуженВход = false
        } catch {
            ошибка = т("err_load")
        }
    }

    /// rentAction: act — confirm | decline | activate | return | cancel | dispute (с причиной).
    func действие(_ аренда: АрендаКабинета, _ act: String, причина: String? = nil) {
        guard !занято.contains(аренда.id) else { return }
        занято.insert(аренда.id)
        var тело: [String: Any] = ["rental_id": аренда.id, "act": act]
        if let причина { тело["reason"] = причина }
        Task { @MainActor in
            defer { self.занято.remove(аренда.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=rental_action", тело: тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let тексты = ["confirm": "rent_toast_confirm", "decline": "rent_toast_decline",
                                  "activate": "rent_toast_active", "return": "rent_toast_return",
                                  "cancel": "rent_toast_cancel", "dispute": "rent_st_disputed"]
                    self.показать(self.т(тексты[act] ?? "done"))
                    await self.загрузить()
                } else {
                    let ошибка = МоиОбъявленияAPI.строка(j["error"])
                    self.показать(self.т("err_pfx") + (ошибка.isEmpty ? "?" : ошибка))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    /// rentDocSign: ok — «Подписан обеими сторонами» / «Ждём подпись второй стороны»; need_otp — окно eGov.
    func подписать(_ аренда: АрендаКабинета) {
        guard !занято.contains(аренда.id) else { return }
        занято.insert(аренда.id)
        Task { @MainActor in
            defer { self.занято.remove(аренда.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("/cabinet.php?action=rent_doc_sign",
                                                           тело: ["rental_id": аренда.id], отКорня: true)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т(МоиОбъявленияAPI.да(j["both"]) ? "rent_doc_ready" : "rent_doc_wait"))
                    await self.загрузить()
                } else if МоиОбъявленияAPI.да(j["need_otp"]) {
                    let назначение = МоиОбъявленияAPI.строка(j["purpose"])
                    let ссылка = МоиОбъявленияAPI.строка(j["ref"])
                    self.подписатьПосле = аренда.id
                    self.eGov = ЗапросEGov(назначение: назначение.isEmpty ? "rent_sign" : назначение,
                                           ссылка: ссылка.isEmpty ? аренда.id : ссылка,
                                           заголовок: self.т("rent_doc_sign"), подсказка: "", после: .оплатить)
                } else {
                    self.показать(ЗапросыКабинета.текстОшибки(j))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    /// eGov пройден — подпись ещё раз, как колбэк otpStepOpen сайта.
    func послеEGov() {
        eGov = nil
        guard let номер = подписатьПосле, let аренда = все.first(where: { $0.id == номер }) else { return }
        подписатьПосле = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.подписать(аренда)
        }
    }

    /// rentDocBuy при цене 0 (бесплатно по PRO): денег не списывает.
    func оформитьДоговор(_ аренда: АрендаКабинета) {
        guard !занято.contains(аренда.id) else { return }
        занято.insert(аренда.id)
        Task { @MainActor in
            defer { self.занято.remove(аренда.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("/cabinet.php?action=rent_doc_buy",
                                                           тело: ["rental_id": аренда.id], отКорня: true)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т("rent_doc_done"))
                    await self.загрузить()
                } else {
                    self.показать(ЗапросыКабинета.текстОшибки(j))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }
}

struct ЭкранАренд: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = АрендыМодель()
    @State private var входОткрыт = false
    @State private var спор: АрендаКабинета? = nil
    @State private var причина = ""

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ВкладкиРаздела(варианты: [("seller", т("rent_tab_seller")), ("buyer", т("rent_tab_buyer"))],
                               выбрано: $модель.роль)
                Text(т("rent_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                содержимое
            }
            .padding(12)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("rent_title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await модель.загрузить() }
        .task { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
        .sheet(item: Binding(get: { модель.eGov.map { ОкноEGovАренды(запрос: $0) } },
                             set: { if $0 == nil { модель.eGov = nil } })) { окно in
            ОкноEGov(запрос: окно.запрос, готово: { модель.послеEGov() }, закрыть: { модель.eGov = nil })
        }
        .alert(т("rent_dispute_prompt"), isPresented: Binding(get: { спор != nil }, set: { if !$0 { спор = nil } })) {
            TextField(т("rent_dispute_prompt"), text: $причина)
            Button(т("rent_dispute_send"), role: .destructive) {
                let текст = причина.trimmingCharacters(in: .whitespacesAndNewlines)
                if let аренда = спор, !текст.isEmpty { модель.действие(аренда, "dispute", причина: текст) }
                спор = nil
                причина = ""
            }
            Button(CabinetText.т("cancel"), role: .cancel) {
                спор = nil
                причина = ""
            }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if модель.грузим {
            ЗагрузкаБизнеса().frame(height: 200)
        } else if let ошибка = модель.ошибка, модель.все.isEmpty {
            ПустоСайта(значок: модель.нуженВход ? "person.crop.circle" : "wifi.exclamationmark", заголовок: ошибка,
                       кнопка: модель.нуженВход ? CabinetText.т("login") : т("retry"),
                       действие: {
                if модель.нуженВход { входОткрыт = true } else { Task { await модель.загрузить() } }
            })
        } else if модель.показанные.isEmpty {
            Text(т("rent_empty"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            ForEach(модель.показанные) { аренда in
                КарточкаАренды(аренда: аренда, занято: модель.занято.contains(аренда.id), модель: модель,
                               спор: { спор = аренда })
            }
        }
    }
}

/// Обёртка запроса eGov для .sheet(item:).
private struct ОкноEGovАренды: Identifiable {
    let запрос: ЗапросEGov
    var id: String { запрос.назначение + ":" + запрос.ссылка }
}

private struct КарточкаАренды: View {
    let аренда: АрендаКабинета
    let занято: Bool
    @ObservedObject var модель: АрендыМодель
    let спор: () -> Void

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    private var статус: (String, ЗаметкаБизнеса.Тон) {
        switch аренда.статус {
        case "requested": return (т("rent_st_requested"), .предупреждение)
        case "confirmed": return (т("rent_st_confirmed"), .хорошо)
        case "active": return (т("rent_st_active"), .хорошо)
        case "returned": return (т("rent_st_returned"), .серый)
        case "cancelled": return (т("rent_st_cancelled"), .плохо)
        case "disputed": return (т("rent_st_disputed"), .предупреждение)
        default: return (аренда.статус, .серый)
        }
    }

    var body: some View {
        КарточкаРаздела {
            HStack(alignment: .top, spacing: 10) {
                МиниатюраРаздела(адрес: ЗапросыКабинета.картинка(аренда.картинка))
                VStack(alignment: .leading, spacing: 3) {
                    Text(аренда.название.isEmpty ? "—" : аренда.название)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text("\(аренда.начало) → \(аренда.конец) (\(аренда.дней) \(т("days_short")))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                МеткаСтатуса(текст: статус.0, тон: статус.1)
            }
            if аренда.итого > 0 || аренда.залог > 0 {
                HStack(spacing: 14) {
                    if аренда.итого > 0 {
                        Text(т("rent_total")).foregroundStyle(Theme.текстВторой)
                            + Text(ЗапросыКабинета.деньги(аренда.итого) + "₸").bold()
                    }
                    if аренда.залог > 0 {
                        Text(т("rent_deposit")).foregroundStyle(Theme.текстВторой)
                            + Text(ЗапросыКабинета.деньги(аренда.залог) + "₸").bold()
                    }
                }
                .font(.system(size: 13.5))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            if !аренда.сообщение.isEmpty {
                ЗаметкаБизнеса(аренда.сообщение, тон: .серый, значок: "text.bubble")
            }
            договор
            кнопки
        }
    }

    // MARK: Договор (rentDocBlock)

    @ViewBuilder
    private var договор: some View {
        if аренда.договорДоступен {
            let заголовок = т(аренда.жильё ? "rent_doc_ttl" : "rent_doc_ttl_t")
            VStack(alignment: .leading, spacing: 8) {
                Label(заголовок, systemImage: "doc.text")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                if !аренда.договорОплачен {
                    if аренда.продавец {
                        Text(т("rent_doc_notyet"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.текстВторой)
                    } else if !(аренда.подписьЯвно && !аренда.подписьНужна) {
                        Text(т("rent_doc_hint"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.текстВторой)
                        КнопкаРаздела(подпись: подписьПокупки, вид: .главная, занято: занято) { купитьДоговор() }
                    }
                } else {
                    КнопкаРаздела(подпись: т("rent_doc_open"), значок: "doc.richtext", вид: .обычная) {
                        ОкнаДокументов.показать(ДокументКабинета(
                            заголовок: заголовок,
                            источник: .путь("/cabinet.php?action=rent_contract&id="
                                            + (аренда.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? аренда.id))))
                    }
                    строкаПодписи(т(аренда.жильё ? "rent_doc_role_ll_h" : "rent_doc_role_ll"), подписал: подписалАрендодатель)
                    строкаПодписи(т(аренда.жильё ? "rent_doc_role_tn_h" : "rent_doc_role_tn"), подписал: подписалАрендатор)
                    if аренда.подписалиОба {
                        Text(т("rent_doc_ready"))
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                    } else if !аренда.подписьНужна {
                        Text(т("rent_doc_final"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.текстВторой)
                    } else if аренда.подписалЯ {
                        Text(т("rent_doc_wait"))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.текстВторой)
                    } else {
                        КнопкаРаздела(подпись: т("rent_doc_sign"), значок: "signature", вид: .главная, занято: занято) {
                            модель.подписать(аренда)
                        }
                    }
                }
            }
            .padding(10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
    }

    private var подписалАрендодатель: Bool {
        аренда.подписалиОба || (аренда.продавец ? аренда.подписалЯ : аренда.подписалДругой)
    }

    private var подписалАрендатор: Bool {
        аренда.подписалиОба || (аренда.продавец ? аренда.подписалДругой : аренда.подписалЯ)
    }

    private var подписьПокупки: String {
        let цена = аренда.ценаДоговора > 0 ? ЗапросыКабинета.деньги(Double(аренда.ценаДоговора)) + "₸" : т("rent_doc_free")
        return "\(т("rent_doc_buy")) · \(цена)"
    }

    /// Бесплатный договор (по PRO) — свой вызов. Платный списывает деньги с кошелька сайта (rent_doc_buy) — это покупка
    /// цифрового документа (правило App Store 3.1.1): только кабинет сайта, из приложения этот запрос не шлётся.
    private func купитьДоговор() {
        if аренда.ценаДоговора <= 0 {
            модель.оформитьДоговор(аренда)
        } else {
            модель.показать(БизнесText.т("no_digital"))
            ПереходыКабинета.сайт("cabinet.php?s=rentals")
        }
    }

    private func строкаПодписи(_ роль: String, подписал: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: подписал ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(подписал ? КраскаОбъявлений.хорошоТекст : Theme.текстВторой)
                .accessibilityHidden(true)
            Text(роль)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 6)
            Text(т(подписал ? "rent_doc_signed" : "rent_doc_notsigned"))
                .font(.system(size: 12.5))
                .foregroundStyle(подписал ? КраскаОбъявлений.хорошоТекст : Theme.текстВторой)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Кнопки (rentTab)

    @ViewBuilder
    private var кнопки: some View {
        let с = аренда.статус
        if аренда.продавец {
            if с == "requested" {
                HStack(spacing: 8) {
                    КнопкаРаздела(подпись: т("rent_confirm"), значок: "checkmark", вид: .главная, занято: занято) {
                        модель.действие(аренда, "confirm")
                    }
                    КнопкаРаздела(подпись: т("rent_decline"), значок: "xmark", вид: .плохо) {
                        модель.действие(аренда, "decline")
                    }
                }
            } else if с == "confirmed" {
                КнопкаРаздела(подпись: т(аренда.жильё ? "rent_handed_h" : "rent_handed"), значок: "key", вид: .главная,
                              занято: занято) {
                    модель.действие(аренда, "activate")
                }
            } else if с == "active" {
                HStack(spacing: 8) {
                    КнопкаРаздела(подпись: т(аренда.жильё ? "rent_returned_btn_h" : "rent_returned_btn"),
                                  значок: "arrow.uturn.backward", вид: .главная, занято: занято) {
                        модель.действие(аренда, "return")
                    }
                    КнопкаРаздела(подпись: т("rent_dispute_btn"), значок: "exclamationmark.bubble", вид: .внимание) {
                        спор()
                    }
                }
            }
        } else {
            if с == "requested" || с == "confirmed" {
                КнопкаРаздела(подпись: т("rent_cancel_btn"), значок: "xmark", вид: .плохо, занято: занято) {
                    модель.действие(аренда, "cancel")
                }
            } else if с == "active" {
                HStack(spacing: 8) {
                    КнопкаРаздела(подпись: т(аренда.жильё ? "rent_i_returned_h" : "rent_i_returned"),
                                  значок: "arrow.uturn.backward", вид: .главная, занято: занято) {
                        модель.действие(аренда, "return")
                    }
                    КнопкаРаздела(подпись: т("rent_open_dispute"), значок: "exclamationmark.bubble", вид: .внимание) {
                        спор()
                    }
                }
            }
        }
        if с == "disputed" {
            ЗаметкаБизнеса(т("rent_disp_wait"), тон: .предупреждение, значок: "scalemass")
            HStack(spacing: 8) {
                КнопкаРаздела(подпись: т(аренда.жильё ? "rent_close_returned_h" : "rent_close_returned"),
                              значок: "checkmark", вид: .главная, занято: занято) {
                    модель.действие(аренда, "return")
                }
                КнопкаРаздела(подпись: т("rent_close_cancel"), значок: "xmark", вид: .плохо) {
                    модель.действие(аренда, "cancel")
                }
            }
        }
    }
}

// MARK: - Обмены

struct ОбменКабинета: Identifiable, Equatable {
    struct Товар: Equatable {
        let id: String
        let название: String
        let картинка: String
    }

    let id: String
    let входящий: Bool
    let статус: String
    /// Что человек получает (у входящего — предложенный ему товар) и что отдаёт.
    let получаю: Товар
    let отдаю: Товар
    let доплата: Double
    let доплачиваюЯ: Bool
    let комментарий: String
    let собеседник: String
    let имяСобеседника: String
    let телефонСобеседника: String
    let объявление: String

    init?(_ j: [String: Any], я: String) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        let продавец = A.строка(j["seller_id"])
        входящий = !я.isEmpty && продавец == я
        статус = A.строка(j["status"])
        func товар(_ ключ: String, _ номерКлюч: String) -> Товар {
            let т = (j[ключ] as? [String: Any]) ?? [:]
            var картинка = A.строка(т["img"])
            if картинка.isEmpty, let первая = (т["images"] as? [Any])?.first { картинка = A.строка(первая) }
            return Товар(id: A.строка(j[номерКлюч]), название: A.строка(т["title"]), картинка: картинка)
        }
        let мой = товар("item", "item_id")
        let предложенный = товар("offer_item", "offer_item_id")
        получаю = входящий ? предложенный : мой
        отдаю = входящий ? мой : предложенный
        доплата = A.число(j["surcharge"])
        let платитПокупатель = A.строка(j["surcharge_dir"]) == "buyer"
        доплачиваюЯ = (!входящий && платитПокупатель) || (входящий && !платитПокупатель)
        комментарий = A.строка(j["comment"])
        собеседник = входящий ? A.строка(j["buyer_id"]) : продавец
        let имя = A.строка(j[входящий ? "buyer_name" : "seller_name"])
        имяСобеседника = имя
        телефонСобеседника = A.строка(j[входящий ? "buyer_phone" : "seller_phone"])
        объявление = A.строка(j["item_id"])
    }
}

@MainActor
final class ОбменыМодель: ObservableObject {
    @Published private(set) var обмены: [ОбменКабинета] = []
    @Published private(set) var грузим = false
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нуженВход = false
    @Published var занято: Set<String> = []
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    func загрузить() async {
        грузим = обмены.isEmpty
        defer { грузим = false }
        let я = await ЗапросыКабинета.мойНомер()
        let номер = я.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? я
        do {
            let сырой = try await МоиОбъявленияAPI.получить("cabinet.php?action=my_exchanges&me_id=" + номер)
            guard let j = сырой else {
                ошибка = т("err_load")
                return
            }
            if МоиОбъявленияAPI.нетСессии(j) {
                ошибка = CabinetText.т("signed_out")
                нуженВход = true
                return
            }
            обмены = ((j["exchanges"] as? [Any]) ?? []).compactMap { запись -> ОбменКабинета? in
                guard let о = запись as? [String: Any] else { return nil }
                return ОбменКабинета(о, я: я)
            }
            ошибка = nil
            нуженВход = false
        } catch {
            ошибка = т("err_load")
        }
    }

    /// exchRespond: decision — accept | decline.
    func ответить(_ обмен: ОбменКабинета, принять: Bool) {
        выполнить(обмен, "cabinet.php?action=exchange_respond",
                  ["exchange_id": обмен.id, "decision": принять ? "accept" : "decline"],
                  успех: принять ? "exch_toast_accepted" : "exch_toast_declined")
    }

    func отменить(_ обмен: ОбменКабинета) {
        выполнить(обмен, "cabinet.php?action=exchange_cancel", ["exchange_id": обмен.id], успех: "exch_toast_cancelled")
    }

    private func выполнить(_ обмен: ОбменКабинета, _ хвост: String, _ тело: [String: Any], успех: String) {
        guard !занято.contains(обмен.id) else { return }
        занято.insert(обмен.id)
        Task { @MainActor in
            defer { self.занято.remove(обмен.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить(хвост, тело: тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т(успех))
                    await self.загрузить()
                } else {
                    let ошибка = МоиОбъявленияAPI.строка(j["error"])
                    self.показать(self.т("err_pfx") + (ошибка.isEmpty ? "?" : ошибка))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }
}

struct ЭкранОбменов: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = ОбменыМодель()
    @State private var входОткрыт = false
    @State private var отменить: ОбменКабинета? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(т("exch_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                содержимое
            }
            .padding(12)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("exch_title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await модель.загрузить() }
        .task { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
        .alert(т("exch_cancel_q"), isPresented: Binding(get: { отменить != nil }, set: { if !$0 { отменить = nil } })) {
            Button(т("exch_cancel_btn"), role: .destructive) {
                if let обмен = отменить { модель.отменить(обмен) }
                отменить = nil
            }
            Button(т("back"), role: .cancel) { отменить = nil }
        } message: {
            Text(т("exch_cancel_s"))
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if модель.грузим {
            ЗагрузкаБизнеса().frame(height: 200)
        } else if let ошибка = модель.ошибка, модель.обмены.isEmpty {
            ПустоСайта(значок: модель.нуженВход ? "person.crop.circle" : "wifi.exclamationmark", заголовок: ошибка,
                       кнопка: модель.нуженВход ? CabinetText.т("login") : т("retry"),
                       действие: {
                if модель.нуженВход { входОткрыт = true } else { Task { await модель.загрузить() } }
            })
        } else if модель.обмены.isEmpty {
            Text(т("exch_empty"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else {
            ForEach(модель.обмены) { обмен in
                КарточкаОбмена(обмен: обмен, занято: модель.занято.contains(обмен.id), модель: модель,
                               отменить: { отменить = обмен })
            }
        }
    }
}

private struct КарточкаОбмена: View {
    let обмен: ОбменКабинета
    let занято: Bool
    @ObservedObject var модель: ОбменыМодель
    let отменить: () -> Void

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    private var статус: (String, ЗаметкаБизнеса.Тон, String) {
        switch обмен.статус {
        case "accepted": return (т("exch_st_accepted"), .хорошо, "checkmark.circle")
        case "declined": return (т("exch_st_declined"), .плохо, "xmark.circle")
        case "pending": return (т("exch_st_pending"), .предупреждение, "clock")
        default: return (обмен.статус, .предупреждение, "clock")
        }
    }

    var body: some View {
        КарточкаРаздела {
            HStack {
                МеткаСтатуса(текст: статус.0, тон: статус.1)
                Spacer(minLength: 6)
                Text(т(обмен.входящий ? "exch_incoming" : "exch_outgoing"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            HStack(alignment: .top, spacing: 8) {
                товар(обмен.получаю, подпись: т(обмен.входящий ? "exch_you_offered" : "exch_you_receive"))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .padding(.top, 30)
                    .accessibilityHidden(true)
                товар(обмен.отдаю, подпись: т(обмен.входящий ? "exch_your_item" : "exch_you_give"))
            }
            if обмен.доплата > 0 {
                ЗаметкаБизнеса("\(т(обмен.доплачиваюЯ ? "exch_you_pay" : "exch_you_get_paid")) \(ЗапросыКабинета.деньги(обмен.доплата)) ₸",
                               тон: обмен.доплачиваюЯ ? .предупреждение : .хорошо, значок: "banknote")
            }
            if !обмен.комментарий.isEmpty {
                ЗаметкаБизнеса(обмен.комментарий, тон: .серый, значок: "text.bubble")
            }
            if обмен.статус == "accepted" {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(т("exch_agreed_a")) \(т("exch_agreed_b"))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                    HStack(spacing: 6) {
                        Text(имя)
                            .font(.system(size: 13))
                        if !обмен.телефонСобеседника.isEmpty,
                           let звонок = URL(string: "tel:" + обмен.телефонСобеседника.filter { $0.isNumber || $0 == "+" }) {
                            Link(обмен.телефонСобеседника, destination: звонок)
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(КраскаОбъявлений.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            if !обмен.собеседник.isEmpty {
                NavigationLink(value: ЧатЦель.продавец(id: обмен.собеседник, имя: имя, объявление: обмен.объявление)) {
                    Label("\(т("exch_chat_with"))\(имя)", systemImage: "bubble.left.and.bubble.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.оттенокАкцента,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if обмен.входящий && обмен.статус == "pending" {
                HStack(spacing: 8) {
                    КнопкаРаздела(подпись: т("exch_accept"), значок: "checkmark", вид: .главная, занято: занято) {
                        модель.ответить(обмен, принять: true)
                    }
                    КнопкаРаздела(подпись: т("exch_decline"), значок: "xmark", вид: .плохо) {
                        модель.ответить(обмен, принять: false)
                    }
                }
            }
            if (!обмен.входящий && обмен.статус == "pending") || обмен.статус == "accepted" {
                Button {
                    отменить()
                } label: {
                    Label(т(обмен.статус == "accepted" ? "exch_cancel_btn" : "exch_withdraw"), systemImage: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(занято)
            }
        }
    }

    private var имя: String {
        if !обмен.имяСобеседника.isEmpty { return обмен.имяСобеседника }
        return т(обмен.входящий ? "exch_buyer_inst" : "exch_seller_inst")
    }

    @ViewBuilder
    private func товар(_ вещь: ОбменКабинета.Товар, подпись: String) -> some View {
        let содержимое = VStack(alignment: .leading, spacing: 4) {
            МиниатюраРаздела(адрес: ЗапросыКабинета.картинка(вещь.картинка), размер: 72)
            Text(вещь.название.isEmpty ? "—" : вещь.название)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
            Text(подпись)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !вещь.id.isEmpty, вещь.id.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
            Button {
                WebBridge.shared.открытьЭкран(.объявление(id: вещь.id), запасной: nil)
            } label: {
                содержимое
            }
            .buttonStyle(.plain)
        } else {
            содержимое
        }
    }
}
