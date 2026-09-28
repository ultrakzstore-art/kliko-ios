import SwiftUI
import UIKit

/**
 «НАЛОГИ ИЗ ПРОДАЖ» — СВОИМ ЭКРАНОМ (#tax-card страницы кабинета и taxInit / taxPreview / taxDownload / taxSverka модуля
 js/cabinet-business.min.js; владелец: «кабинет полностью SwiftUI»). За PRO, как proGate("tax").

   · POST cabinet.php?action=tax_preview {csrf, period, type, regime, is_vat, turnover, commission, expenses, so_paid,
     payroll_gross, employees, sales_vat, credit_vat} → {ok, auto_turnover, total, payments[{name, kbk, knp, amount}],
     files[], c1_linked} | error. Первый вызов при открытии — только чтобы подставить оборот (auto_turnover), как taxInit;
   · «Скачать пакет (ZIP)» — GET cabinet.php?action=tax_package&<те же поля без csrf>[&confirm_1c=1]; при учёте в 1С
     (c1_linked) — только после «Понимаю — всё равно собрать пакет ФНО»;
   · «Скачать сверку (CSV)» — GET cabinet.php?action=tax_reconcile&period=.
 Файлы качаются своим запросом (ФайлыКабинета) и отдаются системным листом «Поделиться»: сохранить в «Файлы», отправить
 бухгалтеру. Поля и подписи — как у формы сайта: у ОУР — комиссия и расходы, у упрощёнки — уплаченные СО, у плательщика
 НДС — НДС с реализации и в зачёте.
 */
struct ПлатёжНалога: Identifiable, Equatable {
    let id: Int
    let назначение: String
    let кбк: String
    let кнп: String
    let сумма: Double
}

struct ИтогНалогов: Equatable {
    let всего: Double
    let платежи: [ПлатёжНалога]
    let файлы: [String]
    let учётВ1С: Bool
}

@MainActor
final class НалогиМодель: ObservableObject {
    enum Состояние: Equatable { case готово, нуженВход, нуженПРО }

    @Published var период: String
    @Published var тип = "ip"
    @Published var режим = "simpl"
    @Published var ндс = false
    @Published var оборот = ""
    @Published var комиссия = "0"
    @Published var расходы = "0"
    @Published var со = "0"
    @Published var фот = "0"
    @Published var сотрудников = "0"
    @Published var ндсПродаж = "0"
    @Published var ндсЗачёт = "0"
    @Published var понимаю = false
    @Published private(set) var состояние: Состояние = .готово
    @Published private(set) var итог: ИтогНалогов? = nil
    @Published private(set) var ошибка: String? = nil
    @Published private(set) var считаем = false
    @Published private(set) var качаем = false
    @Published var файл: ФайлДляЛиста? = nil
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    /// Периоды — как <select id="tax-period"> сайта: текущий и прошлый год, полугодия, кварталы, год.
    let периоды: [(ключ: String, подпись: String)]

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    init() {
        let год = Calendar(identifier: .gregorian).component(.year, from: Date())
        var список: [(ключ: String, подпись: String)] = []
        for г in [год, год - 1] {
            let y = String(г)
            список.append((y + "-1H", КабинетПлюсText.т("tax_1h") + " " + y))
            список.append((y + "-2H", КабинетПлюсText.т("tax_2h") + " " + y))
            for q in 1...4 {
                let номер = String(q)
                список.append((ключ: [y, "-Q", номер].joined(), подпись: [КабинетПлюсText.т("tax_q"), номер, " ", y].joined()))
            }
            список.append((y, КабинетПлюсText.т("tax_year") + " " + y))
        }
        периоды = список
        период = список.first?.ключ ?? String(год)
    }

    var оур: Bool { режим == "our" }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    /// _taxPayload без csrf (его кладёт транспорт).
    private var поля: [String: String] {
        ["period": период, "type": тип, "regime": режим, "is_vat": ндс ? "1" : "0", "turnover": оборот,
         "commission": комиссия, "expenses": расходы, "so_paid": со, "payroll_gross": фот, "employees": сотрудников,
         "sales_vat": ндсПродаж, "credit_vat": ндсЗачёт]
    }

    private func подставитьОборот(_ j: [String: Any]) {
        if оборот.isEmpty, j["auto_turnover"] != nil, !(j["auto_turnover"] is NSNull) {
            оборот = String(Int(МоиОбъявленияAPI.число(j["auto_turnover"]).rounded()))
        }
    }

    /// taxInit: оборот за период подставляет сервер.
    func начать() async {
        guard оборот.isEmpty else { return }
        do {
            let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=tax_preview", тело: поля)
            if МоиОбъявленияAPI.нетСессии(j) {
                состояние = .нуженВход
                return
            }
            if МоиОбъявленияAPI.да(j["need_pro"]) || МоиОбъявленияAPI.да(j["need_tier"]) {
                состояние = .нуженПРО
                return
            }
            подставитьОборот(j)
        } catch {}
    }

    /// taxPreview: «К оплате», квитанции (КБК/КНП), состав пакета.
    func рассчитать() async {
        guard !считаем else { return }
        считаем = true
        defer { считаем = false }
        ошибка = nil
        do {
            let j = try await ЗапросыКабинета.отправить("cabinet.php?action=tax_preview", поля)
            подставитьОборот(j)
            let платежи = ((j["payments"] as? [Any]) ?? []).enumerated().compactMap { пара -> ПлатёжНалога? in
                guard let п = пара.element as? [String: Any] else { return nil }
                return ПлатёжНалога(id: пара.offset, назначение: МоиОбъявленияAPI.строка(п["name"]),
                                    кбк: МоиОбъявленияAPI.строка(п["kbk"]), кнп: МоиОбъявленияAPI.строка(п["knp"]),
                                    сумма: МоиОбъявленияAPI.число(п["amount"]))
            }
            let файлы = ((j["files"] as? [Any]) ?? []).map { МоиОбъявленияAPI.строка($0) }.filter { !$0.isEmpty }
            итог = ИтогНалогов(всего: МоиОбъявленияAPI.число(j["total"]), платежи: платежи, файлы: файлы,
                                учётВ1С: МоиОбъявленияAPI.да(j["c1_linked"]))
            понимаю = false
        } catch let с as ЗапросыКабинета.Сбой {
            if с.нуженВход {
                состояние = .нуженВход
            } else if с.нуженПРО {
                состояние = .нуженПРО
            } else {
                итог = nil
                ошибка = с.текст
            }
        } catch {
            ошибка = т("no_conn")
        }
    }

    private static func код(_ s: String) -> String {
        var можно = CharacterSet.alphanumerics
        можно.insert(charactersIn: "-_.")
        return s.addingPercentEncoding(withAllowedCharacters: можно) ?? s
    }

    /// taxDownload: при учёте в 1С — только после «понимаю».
    func скачатьПакет() {
        if итог?.учётВ1С == true && !понимаю {
            показать(т("tax_1c_no"))
            return
        }
        let порядок = ["period", "type", "regime", "is_vat", "turnover", "commission", "expenses", "so_paid",
                       "payroll_gross", "employees", "sales_vat", "credit_vat"]
        let п = поля
        var запрос = порядок.map { $0 + "=" + Self.код(п[$0] ?? "") }.joined(separator: "&")
        if итог?.учётВ1С == true && понимаю { запрос += "&confirm_1c=1" }
        скачать("cabinet.php?action=tax_package&" + запрос, имя: "kliko-fno-" + период + ".zip")
    }

    /// taxSverka.
    func скачатьСверку() {
        скачать("cabinet.php?action=tax_reconcile&period=" + Self.код(период), имя: "kliko-sverka-" + период + ".csv")
    }

    private func скачать(_ хвост: String, имя: String) {
        guard !качаем else { return }
        качаем = true
        Task { @MainActor in
            defer { self.качаем = false }
            do {
                let адрес = try await ФайлыКабинета.скачать(хвост, запасноеИмя: имя)
                self.файл = ФайлДляЛиста(адрес: адрес)
            } catch let отказ as ФайлыКабинета.Отказ {
                self.показать(отказ.текст)
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }
}

struct ЭкранНалогов: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = НалогиМодель()
    @State private var входОткрыт = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        Group {
            switch модель.состояние {
            case .нуженВход:
                ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                           кнопка: CabinetText.т("login"), действие: { входОткрыт = true })
            case .нуженПРО:
                ScrollView {
                    КарточкаБизнеса(БизнесРазделыText.т("pro_need"), значок: "crown") {
                        Text(т("tax_sub"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                        ЦифроваяПокупка()
                    }
                    .padding(12)
                }
            case .готово:
                содержимое
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("tax_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await модель.начать() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(item: $модель.файл) { ф in
            ЛистПоделитьсяКабинета(предметы: [ф.адрес])
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.начать() }
            })
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                КарточкаБизнеса(т("tax_title"), значок: "percent") {
                    Text(т("tax_sub"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    Group {
                        выбор(т("tax_period"), выбрано: $модель.период, варианты: модель.периоды)
                        подпись(т("tax_type"))
                        ВкладкиРаздела(варианты: [("ip", т("tax_ip")), ("too", т("tax_too"))], выбрано: $модель.тип)
                        подпись(т("tax_regime"))
                        ВкладкиРаздела(варианты: [("simpl", т("tax_simpl")), ("our", т("tax_our"))], выбрано: $модель.режим)
                        Toggle(т("tax_vat"), isOn: $модель.ндс)
                            .tint(Theme.акцент)
                            .font(.system(size: 15))
                    }
                    ПолеРаздела(подпись: т("tax_turnover"), текст: $модель.оборот, подсказка: "—", цифры: true)
                    if модель.оур {
                        ПолеРаздела(подпись: т("tax_commission"), текст: $модель.комиссия, цифры: true)
                        ПолеРаздела(подпись: т("tax_expenses"), текст: $модель.расходы, цифры: true)
                    } else {
                        ПолеРаздела(подпись: т("tax_so_paid"), текст: $модель.со, цифры: true)
                    }
                    ПолеРаздела(подпись: т("tax_payroll"), текст: $модель.фот, цифры: true)
                    ПолеРаздела(подпись: т("tax_emp"), текст: $модель.сотрудников, цифры: true)
                    if модель.ндс {
                        ПолеРаздела(подпись: т("tax_sales_vat"), текст: $модель.ндсПродаж, цифры: true)
                        ПолеРаздела(подпись: т("tax_credit_vat"), текст: $модель.ндсЗачёт, цифры: true)
                    }
                    КнопкаБизнеса(подпись: т("tax_calc"), занято: модель.считаем) {
                        Task { await модель.рассчитать() }
                    }
                }
                if let ошибка = модель.ошибка {
                    ЗаметкаБизнеса(ошибка, тон: .плохо, значок: "exclamationmark.circle")
                }
                if let итог = модель.итог {
                    результат(итог)
                }
                ссылки
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Итог (tax-result)

    private func результат(_ итог: ИтогНалогов) -> some View {
        КарточкаБизнеса(т("tax_to_pay"), значок: "banknote") {
            Text("\(т("tax_to_pay")): \(ЗапросыКабинета.деньги(итог.всего)) ₸")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.текст)
            VStack(spacing: 0) {
                HStack {
                    Text(т("tax_purpose")).frame(maxWidth: .infinity, alignment: .leading)
                    Text("КБК").frame(width: 58)
                    Text("КНП").frame(width: 44)
                    Text(т("tax_amount")).frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .padding(.vertical, 6)
                if итог.платежи.isEmpty {
                    Text("—")
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                ForEach(итог.платежи) { п in
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text(п.назначение).frame(maxWidth: .infinity, alignment: .leading)
                        Text(п.кбк).frame(width: 58)
                        Text(п.кнп).frame(width: 44)
                        Text(ЗапросыКабинета.деньги(п.сумма) + " ₸")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текст)
                    .padding(.vertical, 7)
                    .accessibilityElement(children: .combine)
                }
            }
            if !итог.файлы.isEmpty {
                Text("\(т("tax_pkg")): \(итог.файлы.joined(separator: " · "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            if итог.учётВ1С {
                ЗаметкаБизнеса("\(т("tax_1c_h")). \(т("tax_1c_s"))", тон: .предупреждение, значок: "exclamationmark.circle")
                КнопкаРаздела(подпись: т("tax_sverka"), значок: "arrow.down.doc", занято: модель.качаем) {
                    модель.скачатьСверку()
                }
                Toggle(т("tax_1c_ok"), isOn: $модель.понимаю)
                    .font(.system(size: 13))
                    .tint(Theme.акцент)
            }
            КнопкаБизнеса(подпись: т("tax_download"), занято: модель.качаем) { модель.скачатьПакет() }
            Text(т("tax_disclaimer"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// .tax-links: МРП и кабинеты salyk / КГД.
    private var ссылки: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                if let салык = URL(string: "https://cabinet.salyk.kz") {
                    Link("cabinet.salyk.kz", destination: салык)
                }
                if let кгд = URL(string: "https://kgd.gov.kz") {
                    Link("kgd.gov.kz", destination: кгд)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Theme.акцент)
            Text(т("tax_mrp_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.horizontal, 4)
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(Theme.текстВторой)
    }

    private func выбор(_ заголовок: String, выбрано: Binding<String>,
                       варианты: [(ключ: String, подпись: String)]) -> some View {
        HStack {
            подпись(заголовок)
            Spacer(minLength: 8)
            Picker(заголовок, selection: выбрано) {
                ForEach(варианты, id: \.ключ) { в in
                    Text(в.подпись).tag(в.ключ)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.акцент)
        }
    }
}
