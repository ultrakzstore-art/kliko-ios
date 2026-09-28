import SwiftUI
import UIKit

/**
 «МОИ ДОСТАВКИ» — СВОИМ ЭКРАНОМ (showDeliveries модуля js/cabinet-deals.min.js; владелец: «кабинет полностью SwiftUI»).

 Межгород-доставка: покупатель видит ставки транспортных компаний и выбирает, продавец — заказы, которые пора передать.
   · GET  chat.php?action=logistics_my (вкладка «Покупаю») | logistics_seller («Продаю») → {ok, items[{id, status,
     from_city, to_city, product, product_img, price, escrow_id, track_no, carrier_track_no, bids[{partner_id,
     partner_name, eta, price}], assigned_to, assigned_price, history[{event, detail, at}], ship_deadline, ship_late}]};
     отменённые и истёкшие не показываются. Пока экран открыт — перечитываем раз в 5 с, как _dlvPoll сайта;
   · POST logistics_pick {id, partner} — «Выбрать» ставку; logistics_confirm {id} — «Подтвердить заказ»;
     logistics_cancel {id} — «Отменить заявку»; logistics_handover {id} — продавец «Передал курьеру» (not_ready —
     «Перевозчик ещё не принял заказ»);
   · «Поделиться» — ссылка слежки /track.php?id=<id> системным листом (dlvShare).
 Денег здесь нет: доставка уже оплачена в сделке; выбор ставки — выбор перевозчика.
 */
struct ДоставкаКабинета: Identifiable, Equatable {
    struct Ставка: Identifiable, Equatable {
        let id: String
        let имя: String
        let срок: String
        let цена: Double
    }

    struct Событие: Identifiable, Equatable {
        let id: Int
        let событие: String
        let подробно: String
        let когда: String
    }

    let id: String
    let статус: String
    let откуда: String
    let куда: String
    let товар: String
    let картинка: String
    let цена: Double
    let сделка: String
    let трек: String
    let трекПеревозчика: String
    let ставки: [Ставка]
    let назначен: String
    let ценаНазначения: Double
    let история: [Событие]
    let срокПередачи: String
    let просрочено: Bool

    init?(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        let номер = A.строка(j["id"])
        guard !номер.isEmpty else { return nil }
        id = номер
        статус = A.строка(j["status"])
        откуда = A.строка(j["from_city"])
        куда = A.строка(j["to_city"])
        товар = A.строка(j["product"])
        картинка = A.строка(j["product_img"])
        цена = A.число(j["price"])
        сделка = A.строка(j["escrow_id"])
        трек = A.строка(j["track_no"])
        трекПеревозчика = A.строка(j["carrier_track_no"])
        ставки = ((j["bids"] as? [Any]) ?? []).compactMap { запись -> Ставка? in
            guard let с = запись as? [String: Any] else { return nil }
            return Ставка(id: A.строка(с["partner_id"]), имя: A.строка(с["partner_name"]), срок: A.строка(с["eta"]),
                          цена: A.число(с["price"]))
        }.sorted { $0.цена < $1.цена }
        назначен = A.строка(j["assigned_to"])
        ценаНазначения = A.число(j["assigned_price"])
        var события: [Событие] = []
        for (n, запись) in ((j["history"] as? [Any]) ?? []).enumerated() {
            guard let с = запись as? [String: Any] else { continue }
            события.append(Событие(id: n, событие: A.строка(с["event"]), подробно: A.строка(с["detail"]),
                                   когда: A.строка(с["at"])))
        }
        история = события
        срокПередачи = A.строка(j["ship_deadline"])
        просрочено = A.да(j["ship_late"])
    }

    /// dlvPartnerName: имя из ставки назначенного, иначе его номер, иначе «ТК».
    var перевозчик: String {
        if let с = ставки.first(where: { $0.id == назначен }), !с.имя.isEmpty { return с.имя }
        return назначен.isEmpty ? КабинетПлюсText.т("dlv_carrier") : назначен
    }
}

@MainActor
final class ДоставкиМодель: ObservableObject {
    @Published var вкладка = "buyer"
    @Published private(set) var доставки: [ДоставкаКабинета] = []
    @Published private(set) var грузим = false
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var нуженВход = false
    @Published var занято: Set<String> = []
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

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

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    func загрузить(тихо: Bool = false) async {
        if !тихо { грузим = true }
        defer { грузим = false }
        let вкладкаСейчас = вкладка
        do {
            let действие = вкладкаСейчас == "seller" ? "logistics_seller" : "logistics_my"
            let j = try await ЗапросыКабинета.получить("chat.php?action=" + действие)
            guard вкладкаСейчас == вкладка else { return }
            доставки = ((j["items"] as? [Any]) ?? []).compactMap { запись -> ДоставкаКабинета? in
                guard let д = запись as? [String: Any] else { return nil }
                return ДоставкаКабинета(д)
            }.filter { $0.статус != "canceled" && $0.статус != "expired" }
            ошибка = nil
            нуженВход = false
        } catch let с as ЗапросыКабинета.Сбой {
            if !тихо || доставки.isEmpty {
                ошибка = с.текст
                нуженВход = с.нуженВход
            }
        } catch {
            if !тихо { ошибка = т("no_conn") }
        }
    }

    /// Опрос раз в 5 с, пока экран на месте (_dlvPoll).
    func следить() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if Task.isCancelled { return }
            if UIApplication.shared.applicationState == .active { await загрузить(тихо: true) }
        }
    }

    func действие(_ имя: String, _ доставка: ДоставкаКабинета, партнёр: String? = nil) {
        guard !занято.contains(доставка.id) else { return }
        занято.insert(доставка.id)
        var тело: [String: Any] = ["id": доставка.id]
        if let партнёр { тело["partner"] = партнёр }
        Task { @MainActor in
            defer { self.занято.remove(доставка.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("chat.php?action=" + имя, тело: тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let тексты = ["logistics_pick": "dlv_toast_picked", "logistics_confirm": "dlv_toast_confirmed",
                                  "logistics_handover": "dlv_toast_handed"]
                    if let ключ = тексты[имя] { self.показать(self.т(ключ)) }
                    await self.загрузить(тихо: true)
                } else if МоиОбъявленияAPI.строка(j["error"]) == "not_ready" {
                    self.показать(self.т("dlv_not_ready"))
                } else {
                    self.показать(self.т("err_failed"))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }
}

struct ЭкранДоставок: View {
    @StateObject private var модель = ДоставкиМодель()
    @State private var входОткрыт = false
    @State private var отменить: ДоставкаКабинета? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ВкладкиРаздела(варианты: [("buyer", т("dlv_tab_buyer")), ("seller", т("dlv_tab_seller"))],
                               выбрано: $модель.вкладка)
                Text(т(модель.вкладка == "seller" ? "dlv_sub_seller" : "dlv_sub_buyer"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                содержимое
            }
            .padding(12)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("dlv_title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await модель.загрузить() }
        .task { await модель.загрузить() }
        .task { await модель.следить() }
        .onChange(of: модель.вкладка) { _, _ in
            Task { await модель.загрузить() }
        }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
        .alert(т("dlv_cancel_req"), isPresented: Binding(get: { отменить != nil }, set: { if !$0 { отменить = nil } })) {
            Button(т("dlv_cancel_req"), role: .destructive) {
                if let д = отменить { модель.действие("logistics_cancel", д) }
                отменить = nil
            }
            Button(CabinetText.т("cancel"), role: .cancel) { отменить = nil }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if модель.грузим && модель.доставки.isEmpty {
            ЗагрузкаБизнеса().frame(height: 200)
        } else if let ошибка = модель.ошибка, модель.доставки.isEmpty {
            ПустоСайта(значок: модель.нуженВход ? "person.crop.circle" : "wifi.exclamationmark", заголовок: ошибка,
                       кнопка: модель.нуженВход ? CabinetText.т("login") : т("retry"),
                       действие: {
                if модель.нуженВход { входОткрыт = true } else { Task { await модель.загрузить() } }
            })
        } else if модель.доставки.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "truck.box")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Text(т(модель.вкладка == "seller" ? "dlv_empty_seller_1" : "dlv_empty_buyer_1"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Text(т(модель.вкладка == "seller" ? "dlv_empty_seller_2" : "dlv_empty_buyer_2"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            ForEach(модель.доставки) { доставка in
                КарточкаДоставки(доставка: доставка, продаю: модель.вкладка == "seller",
                                 занято: модель.занято.contains(доставка.id),
                                 действие: { имя, партнёр in
                    if имя == "logistics_cancel" {
                        отменить = доставка
                    } else {
                        модель.действие(имя, доставка, партнёр: партнёр)
                    }
                })
            }
        }
    }
}

private struct КарточкаДоставки: View {
    let доставка: ДоставкаКабинета
    let продаю: Bool
    let занято: Bool
    let действие: (String, String?) -> Void

    @State private var история = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    /// Шаги ленты (renderDeliveries / renderSellerDeliveries).
    private var шаги: [(ключ: String, подпись: String, событие: String)] {
        if продаю {
            return [("open", т("dlv_step_open"), "created"), ("assigned", т("dlv_step_assigned"), "picked"),
                    ("accepted", т("dlv_step_accepted"), "accepted"), ("picked_up", т("dlv_step_handed"), "picked_up"),
                    ("in_transit", т("dlv_step_transit"), "in_transit"), ("delivered", т("dlv_step_delivered"), "delivered")]
        }
        return [("open", т("dlv_step_open"), "created"), ("assigned", т("dlv_step_assigned"), "picked"),
                ("accepted", т("dlv_step_accepted"), "accepted"), ("confirmed", т("dlv_step_confirmed"), "confirmed"),
                ("picked_up", т("dlv_step_picked"), "picked_up"), ("in_transit", т("dlv_step_transit"), "in_transit"),
                ("delivered", т("dlv_step_delivered"), "delivered")]
    }

    private var метка: String {
        let покупатель: [String: String] = ["open": "dlv_pill_open", "assigned": "dlv_pill_assigned",
                                            "accepted": "dlv_step_accepted", "confirmed": "dlv_pill_confirmed",
                                            "picked_up": "dlv_step_picked", "in_transit": "dlv_step_transit",
                                            "delivered": "dlv_step_delivered"]
        let продавец: [String: String] = ["open": "dlv_pill_seeking", "assigned": "dlv_pill_assigned",
                                          "accepted": "dlv_pill_time_hand", "picked_up": "dlv_pill_handed",
                                          "in_transit": "dlv_step_transit", "delivered": "dlv_step_delivered"]
        let ключ = (продаю ? продавец : покупатель)[доставка.статус]
        return ключ.map { т($0) } ?? доставка.статус
    }

    var body: some View {
        КарточкаРаздела {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(доставка.откуда.isEmpty ? "?" : доставка.откуда) → \(доставка.куда.isEmpty ? "?" : доставка.куда)")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    Text(т(продаю ? "dlv_to_buyer" : "dlv_intercity"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 8)
                МеткаСтатуса(текст: метка, тон: доставка.статус == "delivered" ? .хорошо : .инфо, крупная: true)
            }
            трек
            товар
            лента
            действия
            if !доставка.история.isEmpty {
                DisclosureGroup(isExpanded: $история) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(доставка.история) { с in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(названиеСобытия(с.событие))
                                    .font(.system(size: 12.5, weight: .bold))
                                Text(с.подробно)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.текстВторой)
                                Spacer(minLength: 6)
                                Text(СделкиФормат.сВременем(с.когда))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(т(продаю ? "dlv_history_short" : "dlv_history_toggle"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
                .tint(Theme.текстВторой)
            }
        }
    }

    private var трек: some View {
        HStack(spacing: 6) {
            Text(доставка.трек.isEmpty ? "—" : доставка.трек)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.текст)
                .textSelection(.enabled)
            if !доставка.трекПеревозчика.isEmpty {
                Text("/ " + доставка.трекПеревозчика)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(Theme.текстВторой)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 6)
            if let ссылка = Config.url("/track.php?id=" + (доставка.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? доставка.id)) {
                ShareLink(item: ссылка, subject: Text(т("dlv_share_title")), message: Text(т("dlv_share_text"))) {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .tint(Theme.акцент)
            }
        }
    }

    private var товар: some View {
        HStack(spacing: 10) {
            МиниатюраРаздела(адрес: ЗапросыКабинета.картинка(доставка.картинка), размер: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(доставка.товар.isEmpty ? т("dlv_parcel") : доставка.товар)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                if доставка.цена > 0 {
                    Text(ЗапросыКабинета.деньги(доставка.цена) + " ₸")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                if !доставка.сделка.isEmpty {
                    Label(продаю ? т("dlv_paid_escrow") : т("dlv_escrow_deal") + доставка.сделка,
                          systemImage: "checkmark.shield")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                }
            }
        }
    }

    private var лента: some View {
        let номер = max(0, шаги.firstIndex(where: { $0.ключ == доставка.статус }) ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(шаги.enumerated()), id: \.offset) { i, шаг in
                let готово = доставка.статус == "delivered" || i < номер
                let сейчас = i == номер && доставка.статус != "delivered"
                HStack(spacing: 8) {
                    Image(systemName: готово ? "checkmark.circle.fill" : (сейчас ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(готово || сейчас ? Theme.акцент : Theme.текстВторой.opacity(0.5))
                        .accessibilityHidden(true)
                    Text(шаг.подпись)
                        .font(.system(size: 13, weight: сейчас ? .bold : .regular))
                        .foregroundStyle(готово || сейчас ? Theme.текст : Theme.текстВторой)
                    Spacer(minLength: 6)
                    if let когда = доставка.история.first(where: { $0.событие == шаг.событие })?.когда {
                        Text(СделкиФормат.сВременем(когда))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    @ViewBuilder
    private var действия: some View {
        if продаю {
            действияПродавца
        } else {
            действияПокупателя
        }
    }

    @ViewBuilder
    private var действияПокупателя: some View {
        switch доставка.статус {
        case "open":
            if доставка.ставки.isEmpty {
                ЗаметкаБизнеса(т("dlv_wait_bids"), тон: .серый, значок: "clock")
            } else {
                ForEach(доставка.ставки) { ставка in
                    HStack(spacing: 10) {
                        Text(String((ставка.имя.isEmpty ? "?" : ставка.имя).prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .frame(width: 34, height: 34)
                            .background(Theme.акцент, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ставка.имя.isEmpty ? т("dlv_carrier_abbr") : ставка.имя)
                                .font(.system(size: 14, weight: .bold))
                            Text(ставка.срок.isEmpty ? т("dlv_eta_tbd") : ставка.срок)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        Spacer(minLength: 6)
                        Text(ЗапросыКабинета.деньги(ставка.цена) + " ₸")
                            .font(.system(size: 14, weight: .heavy))
                            .monospacedDigit()
                        Button(т("dlv_pick_btn")) { действие("logistics_pick", ставка.id) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.акцент)
                            .disabled(занято)
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            Button(т("dlv_cancel_req")) { действие("logistics_cancel", nil) }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .disabled(занято)
        case "assigned":
            ЗаметкаБизнеса("\(т("dlv_asg_a")) \(доставка.перевозчик) \(т("dlv_asg_b")) \(сумма) ₸. \(т("dlv_asg_c"))",
                           тон: .предупреждение, значок: "clock")
        case "accepted":
            ЗаметкаБизнеса("\(доставка.перевозчик) \(т("dlv_acc_a")) \(сумма) \(т("dlv_acc_b"))",
                           тон: .хорошо, значок: "checkmark.circle")
            КнопкаРаздела(подпись: т("dlv_confirm_btn"), значок: "checkmark", вид: .главная, занято: занято) {
                действие("logistics_confirm", nil)
            }
        default:
            ЗаметкаБизнеса("\(т("dlv_carrying")) \(доставка.перевозчик) · \(сумма) ₸\(доставлено)",
                           тон: .хорошо, значок: "truck.box")
        }
    }

    @ViewBuilder
    private var действияПродавца: some View {
        switch доставка.статус {
        case "open":
            ЗаметкаБизнеса(т("dlv_wait_seeking"), тон: .серый, значок: "clock")
        case "assigned":
            ЗаметкаБизнеса("\(т("dlv_sel_a")) \(доставка.перевозчик) \(т("dlv_sel_b"))",
                           тон: .предупреждение, значок: "clock")
        case "accepted":
            if доставка.просрочено {
                ЗаметкаБизнеса(т("dlv_late"), тон: .плохо, значок: "exclamationmark.circle")
            } else if let осталось = осталосьДоПередачи {
                ЗаметкаБизнеса("\(т("dlv_hand_a")) \(доставка.перевозчик) \(т("dlv_hand_b")) \(осталось)\(т("dlv_hand_c"))",
                               тон: .предупреждение, значок: "timer")
            } else {
                ЗаметкаБизнеса("\(т("dlv_sel_a")) \(доставка.перевозчик) \(т("dlv_ready_b"))",
                               тон: .инфо, значок: "clock")
            }
            КнопкаРаздела(подпись: т("dlv_handover_btn"), значок: "checkmark", вид: .главная, занято: занято) {
                действие("logistics_handover", nil)
            }
        default:
            ЗаметкаБизнеса("\(т("dlv_at_carrier")) \(доставка.перевозчик)\(т(доставка.статус == "delivered" ? "dlv_sfx_delivered" : "dlv_sfx_transit"))",
                           тон: .хорошо, значок: "truck.box")
        }
    }

    private var сумма: String { ЗапросыКабинета.деньги(доставка.ценаНазначения) }
    private var доставлено: String { доставка.статус == "delivered" ? т("dlv_delivered_sfx") : "" }

    /// dlvRemain: «5 ч 12 мин» до срока передачи; срок прошёл или не пришёл — nil.
    private var осталосьДоПередачи: String? {
        guard let срок = СделкиФормат.дата(доставка.срокПередачи) else { return nil }
        let секунд = Int(срок.timeIntervalSinceNow)
        guard секунд > 0 else { return nil }
        let часы = секунд / 3600
        let минуты = (секунд % 3600) / 60
        let начало = часы > 0 ? "\(часы) \(т("h_short")) " : ""
        return "\(начало)\(минуты) \(т("min_full"))"
    }

    private func названиеСобытия(_ событие: String) -> String {
        let ключ = "dlv_ev_" + событие
        let текст = т(ключ)
        return текст == ключ ? событие : текст
    }
}
