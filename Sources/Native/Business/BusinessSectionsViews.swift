import SwiftUI
import UIKit
import Charts

/**
 БИЗНЕС-РАЗДЕЛЫ КАБИНЕТА — СВОИ ЭКРАНЫ (этап 50). Данные и вызовы — BusinessSectionsAPI.swift.

 · «Аналитика магазина» (showAnalytics / renderAnalytics): плитки «Просмотры», «Сделки», «Выручка», «Конверсия»,
   «Рейтинг» с подписями сайта; «Топ по просмотрам» — график Swift Charts (у сайта — полосы той же длины), сделки по
   статусу — кольцо. За PRO, как proGate("analytics");
 · «Журнал счетов» (jrnLoad): «Счета» · «Склад» · «Действия», период как в #jrn-period, итоги «Выписано» / «Проведено
   (доход)» / «НДС с продаж» / «Отменено», график по месяцам, строки; ссылку на документ счёта — «Поделиться»;
 · «Счета и заказы»: заказы B2B с кнопками продавца, как _b2bRow (Подтвердить → Оплата пришла → Отгрузить / Завершить,
   «Отменить» с вопросом сайта), и «Полученные счета» (invLoad);
 · «Предложения покупателям» (kpLoad): входящие запросы — «Сформировать КП» (шаблоны и Kliko AI, правка текста,
   «Отправить покупателю») и «Отклонить» с вопросом сайта; отправленные; полученные КП — текстом, «Поделиться» и
   свой PDF (КнопкаPDFКП, CabinetPlus/OfferPdfButton.swift);
 · «Разделы магазина» (shopSecOpen): список, добавить, переименовать, порядок, удалить, «Сохранить». За PRO.
 Печать PDF — свой документ (CabinetPlus/BusinessDocs.swift); печать и подпись, прайс-лист, налоги и интеграции — свои
 экраны (CabinetPlus).
 */

private func тР(_ ключ: String) -> String { БизнесРазделыText.т(ключ) }
private func тР(_ ключ: String, _ замены: [String: String]) -> String { БизнесРазделыText.т(ключ, замены) }

// MARK: - Общие детали

/// Плитка показателя (renderAnalytics: подпись, крупное значение в краске, строка под ним).
struct ПлиткаПоказателя: View {
    let заголовок: String
    let значение: String
    let подпись: String
    var краска: Color = Theme.текст

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            Text(значение)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(краска)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
            if !подпись.isEmpty {
                Text(подпись)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Состояние загрузки раздела.
enum СостояниеРаздела: Equatable {
    case идёт
    case готово
    case нуженВход
    case нуженПРО
    case ошибка(String)
}

/// Общая рамка раздела: колесо, «войдите», PRO, ошибка с «Повторить» или содержимое.
struct РамкаРаздела<Содержимое: View>: View {
    let состояние: СостояниеРаздела
    let открыть: (URL) -> Void
    let повторить: () -> Void
    let содержимое: Содержимое

    @State private var входОткрыт = false

    init(состояние: СостояниеРаздела, открыть: @escaping (URL) -> Void, повторить: @escaping () -> Void,
         @ViewBuilder содержимое: () -> Содержимое) {
        self.состояние = состояние
        self.открыть = открыть
        self.повторить = повторить
        self.содержимое = содержимое()
    }

    var body: some View {
        Group {
            switch состояние {
            case .идёт:
                ЗагрузкаБизнеса()
            case .нуженВход:
                ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                           подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                           действие: { войти() })
            case .нуженПРО:
                ScrollView {
                    КарточкаБизнеса(тР("pro_need"), значок: "crown") {
                        Text(тР("pro_need_s"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                        ЦифроваяПокупка()
                    }
                    .padding(12)
                }
            case .ошибка(let текст):
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: БизнесText.т("retry"),
                           действие: повторить)
            case .готово:
                содержимое
            }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: { повторить() })
        }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let u = Config.страницаСайта("cabinet.php") {
            открыть(u)
        }
    }
}

/// Заголовок группы внутри экрана.
private struct ЗаголовокГруппы: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Theme.текст)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Пустой список: серый текст в карточке.
private struct ПустоРаздела: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 13.5))
            .foregroundStyle(Theme.текстВторой)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

/// Сбой запроса → состояние раздела.
@MainActor
private func состояние(_ ошибка: Error) -> СостояниеРаздела {
    if let с = ошибка as? БизнесРазделыAPI.Сбой {
        if с.нуженВход { return .нуженВход }
        if с.нуженПРО { return .нуженПРО }
        return .ошибка(с.текст)
    }
    return .ошибка(БизнесText.т("no_conn"))
}

/// Есть ли у магазина функция тарифа (proGate сайта): страница кабинета не прочиталась — пусть решит сервер.
@MainActor
private func естьФункция(_ ключ: String) async -> Bool {
    let модель = БизнесМодель.shared
    if модель.страница == nil { await модель.загрузитьСтраницу() }
    guard let с = модель.страница else { return true }
    return с.естьФункция(ключ)
}

// MARK: - Аналитика

struct ЭкранАналитики: View {
    let открыть: (URL) -> Void

    @State private var данные: АналитикаМагазина? = nil
    @State private var состояниеЭкрана: СостояниеРаздела = .идёт

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        РамкаРаздела(состояние: состояниеЭкрана, открыть: открыть, повторить: { Task { await загрузить() } }) {
            if let данные { содержимое(данные) }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тР("an_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await загрузить() }
    }

    private func загрузить() async {
        if данные == nil { состояниеЭкрана = .идёт }
        guard await естьФункция("analytics") else {
            состояниеЭкрана = .нуженПРО
            return
        }
        do {
            данные = try await БизнесРазделыAPI.аналитика()
            состояниеЭкрана = .готово
        } catch {
            if данные == nil { состояниеЭкрана = состояние(error) }
        }
    }

    private func содержимое(_ д: АналитикаМагазина) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(тР("an_sub"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.текстВторой)
                плитки(д)
                if д.сделокВсего > 0 {
                    КарточкаБизнеса(тР("an_deals_chart"), значок: "chart.pie") {
                        кольцо(д)
                    }
                }
                КарточкаБизнеса(тР("an_top_views"), значок: "chart.bar") {
                    if д.топ.isEmpty {
                        Text(тР("an_no_data"))
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ГрафикТопа(топ: д.топ)
                    }
                }
            }
            .padding(12)
        }
        .refreshable { await загрузить() }
    }

    private func плитки(_ д: АналитикаМагазина) -> some View {
        let сделкиПодпись = д.вПроцессе > 0
            ? тР("an_in_progress", ["n": String(д.вПроцессе)])
            : тР("an_total", ["n": String(д.сделокВсего)])
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
            ПлиткаПоказателя(заголовок: тР("an_views"), значение: СделкиФормат.деньги(д.просмотры),
                             подпись: тР("an_active_listings", ["n": String(д.активных)]), краска: Theme.акцент)
            ПлиткаПоказателя(заголовок: тР("an_deals"), значение: СделкиФормат.деньги(д.сделокЗавершено),
                             подпись: сделкиПодпись, краска: Theme.проверен)
            ПлиткаПоказателя(заголовок: тР("an_revenue"), значение: СделкиФормат.тенге(д.выручка),
                             подпись: тР("an_revenue_sub"), краска: Theme.акцент)
            ПлиткаПоказателя(заголовок: тР("an_conversion"), значение: д.конверсия + "%", подпись: тР("an_conv_sub"))
            ПлиткаПоказателя(заголовок: тР("an_rating"), значение: д.рейтинг,
                             подпись: тР("an_reviews", ["n": String(д.отзывов)]), краска: Theme.звезда)
        }
    }

    private struct Доля: Identifiable {
        let имя: String
        let число: Int
        var id: String { имя }
    }

    private func кольцо(_ д: АналитикаМагазина) -> some View {
        let прочие = max(0, д.сделокВсего - д.сделокЗавершено - д.вПроцессе)
        let доли: [Доля] = [
            Доля(имя: тР("an_done"), число: д.сделокЗавершено),
            Доля(имя: тР("an_progress"), число: д.вПроцессе),
            Доля(имя: тР("an_other"), число: прочие)
        ].filter { $0.число > 0 }
        let имена: [String] = [тР("an_done"), тР("an_progress"), тР("an_other")]
        let краски: [Color] = [Theme.акцент, Theme.проверен, Theme.текстВторой.opacity(0.45)]
        return Chart(доли) { доля in
            SectorMark(angle: .value(тР("an_deals"), доля.число), innerRadius: .ratio(0.62), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value(тР("an_deals"), доля.имя))
        }
        .chartForegroundStyleScale(domain: имена, range: краски)
        .chartLegend(position: .trailing, alignment: .center)
        .frame(height: 170)
        .accessibilityLabel(тР("an_deals_chart"))
    }
}

/// «Топ по просмотрам»: горизонтальные полосы, название и число — над полосой (как у сайта).
private struct ГрафикТопа: View {
    let топ: [АналитикаМагазина.Товар]

    var body: some View {
        Chart(топ) { товар in
            BarMark(x: .value(тР("an_views"), товар.просмотры), y: .value("#", String(товар.id)), height: .fixed(10))
                .foregroundStyle(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный],
                                                startPoint: .leading, endPoint: .trailing))
                .cornerRadius(5)
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    ПодписьТопа(товар: товар)
                }
                .accessibilityLabel(Text(товар.название))
                .accessibilityValue(Text(СделкиФормат.деньги(товар.просмотры)))
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .frame(height: CGFloat(топ.count) * 46)
    }
}

/// Подпись полосы: название, «ОПТ» и число просмотров.
private struct ПодписьТопа: View {
    let товар: АналитикаМагазина.Товар

    var body: some View {
        HStack(spacing: 6) {
            Text(товар.название)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            if товар.опт {
                Text(тР("an_opt"))
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(КраскаОбъявлений.инфоТекст)
                    .padding(.horizontal, 4)
                    .background(КраскаОбъявлений.инфоФон, in: RoundedRectangle(cornerRadius: 4))
            }
            Image(systemName: "eye")
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(СделкиФормат.деньги(товар.просмотры))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .monospacedDigit()
        }
    }
}

// MARK: - Журнал счетов

struct ЭкранЖурнала: View {
    let открыть: (URL) -> Void

    enum Вид: String, CaseIterable, Identifiable {
        case счета = "inv"
        case склад = "stock"
        case действия = "log"
        var id: String { rawValue }
        var название: String {
            switch self {
            case .счета: return тР("jrn_v_inv")
            case .склад: return тР("jrn_v_stock")
            case .действия: return тР("jrn_v_log")
            }
        }
    }

    @State private var вид: Вид = .счета
    @State private var период: String
    @State private var журнал: ЖурналСчетов? = nil
    @State private var события: [СобытиеЖурнала]? = nil
    @State private var состояниеЭкрана: СостояниеРаздела = .идёт

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
        _период = State(initialValue: String(Calendar.current.component(.year, from: Date())))
    }

    /// Период #jrn-period: значение для сервера и подпись.
    struct Период: Identifiable {
        let id: String
        let имя: String
    }

    /// Периоды #jrn-period: год, полугодия, кварталы — этот год и прошлый.
    private var периоды: [Период] {
        let год = Calendar.current.component(.year, from: Date())
        var итог: [Период] = []
        for y in [год, год - 1] {
            let г = String(y)
            итог.append(Период(id: г, имя: тР("jrn_year", ["y": г])))
            итог.append(Период(id: г + "-1H", имя: тР("jrn_h1", ["y": г])))
            итог.append(Период(id: г + "-2H", имя: тР("jrn_h2", ["y": г])))
            for q in 1...4 {
                итог.append(Период(id: г + "-Q" + String(q), имя: тР("jrn_q", ["q": String(q), "y": г])))
            }
        }
        return итог
    }

    private var подписьПериода: String {
        периоды.first(where: { $0.id == период })?.имя ?? период
    }

    var body: some View {
        РамкаРаздела(состояние: состояниеЭкрана, открыть: открыть, повторить: { Task { await загрузить() } }) {
            содержимое
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тР("jrn_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await загрузить() }
        .onChange(of: вид) { _, _ in Task { await загрузить() } }
        .onChange(of: период) { _, _ in Task { await загрузить() } }
    }

    private func загрузить() async {
        let мой = вид.rawValue + "|" + период
        do {
            switch вид {
            case .счета:
                let готовый = try await БизнесРазделыAPI.журнал(период: период)
                guard мой == вид.rawValue + "|" + период else { return }
                журнал = готовый
            case .склад, .действия:
                let готовые = try await БизнесРазделыAPI.действия(период: период, склад: вид == .склад)
                guard мой == вид.rawValue + "|" + период else { return }
                события = готовые
            }
            состояниеЭкрана = .готово
        } catch {
            guard мой == вид.rawValue + "|" + период else { return }
            состояниеЭкрана = состояние(error)
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(тР("jrn_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                Picker(тР("jrn_title"), selection: $вид) {
                    ForEach(Вид.allCases) { в in
                        Text(в.название).tag(в)
                    }
                }
                .pickerStyle(.segmented)
                Menu {
                    ForEach(периоды) { п in
                        Button(п.имя) { период = п.id }
                    }
                } label: {
                    HStack {
                        Text(тР("jrn_period"))
                            .foregroundStyle(Theme.текстВторой)
                        Spacer()
                        Text(подписьПериода)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.текст)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(Theme.текстВторой)
                    }
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                switch вид {
                case .счета:
                    if let журнал { счета(журнал) }
                case .склад, .действия:
                    if let события { действия(события) }
                }
            }
            .padding(12)
        }
        .refreshable { await загрузить() }
    }

    // MARK: Счета

    @ViewBuilder
    private func счета(_ ж: ЖурналСчетов) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 10)], spacing: 10) {
            ПлиткаПоказателя(заголовок: тР("jrn_issued"), значение: СделкиФормат.тенге(ж.выписаноСумма),
                             подпись: String(ж.выписано))
            ПлиткаПоказателя(заголовок: тР("jrn_paid"), значение: СделкиФормат.тенге(ж.проведеноСумма),
                             подпись: String(ж.проведено), краска: Theme.акцент)
            if ж.ндс > 0 {
                ПлиткаПоказателя(заголовок: тР("jrn_vat"), значение: СделкиФормат.тенге(ж.ндс), подпись: "")
            }
            if ж.отменено > 0 {
                ПлиткаПоказателя(заголовок: тР("jrn_cancelled"), значение: String(ж.отменено), подпись: "",
                                 краска: КраскаОбъявлений.плохоТекст)
            }
        }
        let месяцы = ж.поМесяцам(выписано: тР("jrn_issued"), оплачено: тР("jrn_paid"))
        if !месяцы.isEmpty {
            КарточкаБизнеса(тР("jrn_chart"), значок: "chart.bar.xaxis") {
                ГрафикМесяцев(месяцы: месяцы)
            }
        }
        if ж.строки.isEmpty {
            ПустоРаздела(текст: тР("jrn_empty"))
        } else {
            ForEach(ж.строки) { строка in
                СтрокаЖурнала(строка: строка)
            }
        }
    }

    // MARK: Склад и действия

    @ViewBuilder
    private func действия(_ список: [СобытиеЖурнала]) -> some View {
        if список.isEmpty {
            ПустоРаздела(текст: тР("jrn_log_empty"))
        } else {
            ForEach(список) { событие in
                СтрокаСобытия(событие: событие, склад: вид == .склад)
            }
        }
    }
}

/// Суммы по месяцам: «Выписано» и «Проведено» рядом.
private struct ГрафикМесяцев: View {
    let месяцы: [ЖурналСчетов.Месяц]

    /// «2026-03» → «03.26».
    private func подпись(_ м: String) -> String {
        let части = м.split(separator: "-")
        guard части.count == 2 else { return м }
        return String(части[1]) + "." + String(части[0].suffix(2))
    }

    var body: some View {
        Chart(месяцы) { м in
            BarMark(x: .value("m", подпись(м.месяц)), y: .value("₸", м.сумма))
                .foregroundStyle(by: .value("v", м.вид))
                .position(by: .value("v", м.вид))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: [тР("jrn_issued"), тР("jrn_paid")],
                                   range: [Theme.проверен, Theme.акцент])
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { значение in
                AxisGridLine()
                AxisValueLabel {
                    if let n = значение.as(Int.self) {
                        Text(ГрафикМесяцев.коротко(n))
                    }
                }
            }
        }
        .frame(height: 200)
    }

    /// 1 250 000 → «1,3 млн»-подобно без слов: «1.3M» нечитаемо по-русски, поэтому тысячи — «1 250к».
    static func коротко(_ n: Int) -> String {
        if n >= 1_000_000 { return СделкиФормат.дробь(Double(n) / 1_000_000) + "M" }
        if n >= 1_000 { return СделкиФормат.деньги(n / 1_000) + "k" }
        return String(n)
    }
}

private struct СтрокаЖурнала: View {
    let строка: СчётЖурнала

    private var статус: String {
        switch строка.статус {
        case "new", "confirmed", "paid", "shipped", "done", "cancelled": return тР("b2b_st_" + строка.статус)
        default: return строка.статус
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("№" + строка.номер)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(строка.дата)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 6)
                Text(СделкиФормат.тенге(строка.сумма))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(строка.статус == "cancelled" ? Theme.текстВторой : Theme.текст)
                    .strikethrough(строка.статус == "cancelled")
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(строка.покупатель.isEmpty ? "—" : строка.покупатель)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                if строка.гость {
                    МеткаБизнеса(текст: тР("b2b_guest_tag"))
                } else if !строка.бин.isEmpty {
                    Text(строка.бин)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                Text(статус)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(строка.статус == "cancelled" ? КраскаОбъявлений.плохоТекст : Theme.акцент)
            }
            if !строка.оплачен.isEmpty || строка.ндс > 0 {
                HStack(spacing: 10) {
                    if !строка.оплачен.isEmpty {
                        Text(тР("jrn_paid_at") + строка.оплачен)
                    }
                    if строка.ндс > 0 {
                        Text(тР("jrn_incl_vat") + СделкиФормат.тенге(строка.ндс))
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            }
            if let адрес = ссылкаДокумента {
                ShareLink(item: адрес) {
                    Label(тР("share_doc"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                }
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .opacity(строка.статус == "cancelled" ? 0.7 : 1)
    }

    private var ссылкаДокумента: URL? {
        guard !строка.документ.isEmpty else { return nil }
        return Config.url(строка.документ)?.absoluteURL
    }
}

private struct СтрокаСобытия: View {
    let событие: СобытиеЖурнала
    let склад: Bool

    /// _jrnEv сайта.
    private var подпись: String {
        switch событие.событие {
        case "reserve": return тР("jrn_e_reserve")
        case "release": return тР("jrn_e_release")
        case "manual": return тР("jrn_e_manual")
        case "issued": return тР("jrn_e_issued")
        case "shared_opened": return тР("jrn_e_opened")
        case "confirmed", "paid", "shipped", "done", "cancelled": return тР("b2b_st_" + событие.событие)
        default: return событие.событие
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(событие.время)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .monospacedDigit()
                if склад {
                    Text(событие.название.isEmpty ? "—" : событие.название)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    HStack(spacing: 6) {
                        if !событие.было.isEmpty {
                            Text(событие.было + " → " + событие.стало)
                        }
                        Text((событие.изменение > 0 ? "+" : "") + String(событие.изменение))
                            .fontWeight(.bold)
                            .foregroundStyle(событие.изменение < 0 ? КраскаОбъявлений.плохоТекст : Theme.акцент)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
                } else {
                    Text(событие.номер.isEmpty ? событие.покупатель : "№\(событие.номер) \(событие.покупатель)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    if событие.сумма > 0 {
                        Text(СделкиФормат.тенге(событие.сумма))
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .multilineTextAlignment(.trailing)
                if склад && !событие.номер.isEmpty {
                    Text("№" + событие.номер)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Счета и заказы B2B

struct ЭкранСчетов: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var полученные: [ПолученныйДокумент]? = nil
    @State private var состояниеЭкрана: СостояниеРаздела = .идёт
    @State private var отменить: ЗаказB2B? = nil
    @State private var занят: String? = nil
    @State private var плашка: String? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        РамкаРаздела(состояние: состояниеЭкрана, открыть: открыть, повторить: { Task { await загрузить() } }) {
            содержимое
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тР("inv_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await загрузить() }
        .alert(заголовокОтмены,
               isPresented: Binding(get: { отменить != nil }, set: { if !$0 { отменить = nil } })) {
            Button(тР("b2b_cancel_yes"), role: .destructive) {
                if let заказ = отменить { сменить(заказ, "cancelled") }
            }
            Button(тР("b2b_cancel_no"), role: .cancel) {}
        } message: {
            Text(тР("b2b_cancel_h"))
        }
        .overlay(alignment: .bottom) {
            if let плашка { ПлашкаКошелька(текст: плашка) }
        }
    }

    /// «Отменить счёт №12?»
    private var заголовокОтмены: String {
        guard let заказ = отменить else { return "" }
        let номер = заказ.номер.isEmpty ? "" : " №\(заказ.номер)"
        return "\(тР("b2b_cancel_q"))\(номер)?"
    }

    private func загрузить() async {
        if модель.заказыПродаю == nil && полученные == nil { состояниеЭкрана = .идёт }
        await модель.загрузитьСтраницу()
        if модель.загрузка == .нуженВход {
            состояниеЭкрана = .нуженВход
            return
        }
        await модель.загрузитьЗаказы()
        do {
            полученные = try await БизнесРазделыAPI.полученныеСчета()
            состояниеЭкрана = .готово
        } catch {
            if модель.заказыПродаю != nil {
                полученные = полученные ?? []
                состояниеЭкрана = .готово
            } else {
                состояниеЭкрана = состояние(error)
            }
        }
    }

    private var содержимое: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                NavigationLink {
                    ЭкранЖурнала(открыть: открыть)
                } label: {
                    СтрокаПереходаБизнеса(название: тР("jrn_title"), значок: "list.number")
                }
                .buttonStyle(.plain)
                ЗаголовокГруппы(текст: тР("b2b_orders_in"))
                заказы(модель.заказыПродаю, пусто: тР("b2b_no_incoming"))
                ЗаголовокГруппы(текст: тР("b2b_orders_out"))
                заказы(модель.заказыПокупаю, пусто: тР("b2b_no_mine"))
                ЗаголовокГруппы(текст: тР("inv_received_lbl"))
                if let полученные, !полученные.isEmpty {
                    ForEach(полученные) { документ in
                        Button {
                            ОкнаДокументов.показать(ДокументКабинета(заголовок: ДокументыБизнеса.заголовок(документ.данные),
                                                                     источник: .разметка(ДокументыБизнеса.разметка(документ.данные))))
                        } label: {
                            СтрокаДокумента(документ: документ)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(КабинетПлюсText.т("doc_open_hint"))
                    }
                } else {
                    ПустоРаздела(текст: "—")
                }
            }
            .padding(12)
        }
        .refreshable { await загрузить() }
    }

    @ViewBuilder
    private func заказы(_ список: [ЗаказB2B]?, пусто: String) -> some View {
        if let список, !список.isEmpty {
            ForEach(список) { заказ in
                КарточкаЗаказа(заказ: заказ, занят: занят == заказ.id, действие: { статус in
                    if статус == "cancelled" { отменить = заказ } else { сменить(заказ, статус) }
                })
                /* Счёт, накладная, акт, договор — свой PDF с «Поделиться» и «Печать» (CabinetPlus/BusinessDocs.swift). */
                КнопкиДокументовЗаказа(заказ: заказ)
            }
        } else {
            ПустоРаздела(текст: пусто)
        }
    }

    /// b2bStatus: запись → «Статус обновлён» и список заново.
    private func сменить(_ заказ: ЗаказB2B, _ статус: String) {
        guard занят == nil else { return }
        занят = заказ.id
        Task {
            let ошибка = await БизнесРазделыAPI.статусЗаказа(заказ.id, статус)
            занят = nil
            показать(ошибка ?? тР("b2b_status_updated"))
            if ошибка == nil { await модель.загрузитьЗаказы() }
        }
    }

    private func показать(_ текст: String) {
        withAnimation { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if плашка == текст { withAnimation { плашка = nil } }
        }
    }
}

/// Строка перехода к своему экрану (со стрелкой «вглубь», не «наружу»).
struct СтрокаПереходаБизнеса: View {
    let название: String
    let значок: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .foregroundStyle(Theme.акцент)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(название)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Заказ B2B (_b2bRow): контрагент, сумма, позиции, статус и кнопка следующего шага продавца.
private struct КарточкаЗаказа: View {
    let заказ: ЗаказB2B
    let занят: Bool
    let действие: (String) -> Void

    private var статус: String {
        switch заказ.статус {
        case "new", "confirmed", "paid", "shipped", "done", "cancelled": return тР("b2b_st_" + заказ.статус)
        default: return заказ.статус
        }
    }

    /// Следующий шаг продавца: new → confirmed, confirmed → paid, paid → shipped (товары) / done (услуги), shipped → done.
    private var шаг: (String, String)? {
        guard заказ.продаю else { return nil }
        switch заказ.статус {
        case "new": return ("confirmed", тР("b2b_confirm"))
        case "confirmed": return ("paid", тР("b2b_mark_paid"))
        case "paid": return заказ.вид != "services" ? ("shipped", тР("b2b_ship")) : ("done", тР("b2b_finish"))
        case "shipped": return ("done", тР("b2b_finish"))
        default: return nil
        }
    }

    private var можноОтменить: Bool { заказ.статус == "new" || заказ.статус == "confirmed" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(заказ.номер.isEmpty ? имяКонтрагента : "№\(заказ.номер) · \(имяКонтрагента)")
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Text(СделкиФормат.тенге(заказ.сумма))
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            if заказ.гость {
                HStack(spacing: 8) {
                    МеткаБизнеса(текст: тР("b2b_guest_tag"))
                    if !заказ.телефон.isEmpty, let тел = URL(string: "tel:" + заказ.телефон.filter { $0.isNumber || $0 == "+" }) {
                        Link(заказ.телефон, destination: тел)
                    }
                    if !заказ.почта.isEmpty, let почта = URL(string: "mailto:" + заказ.почта) {
                        Link(заказ.почта, destination: почта)
                    }
                }
                .font(.system(size: 12.5))
                .tint(Theme.акцент)
            }
            ForEach(Array(заказ.позиции.enumerated()), id: \.offset) { _, позиция in
                Text(позиция.0 + " × " + String(позиция.1))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(статус)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(заказ.статус == "cancelled" ? КраскаОбъявлений.плохоТекст : Theme.акцент)
                if !заказ.до.isEmpty {
                    Text("\(тР("b2b_until")) \(заказ.до)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            if шаг != nil || можноОтменить {
                HStack(spacing: 8) {
                    if let шаг {
                        КнопкаБизнеса(подпись: шаг.1, занято: занят) { действие(шаг.0) }
                    }
                    if можноОтменить {
                        КнопкаБизнеса(подпись: тР("b2b_cancel"), второстепенная: true) { действие("cancelled") }
                            .disabled(занят)
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var имяКонтрагента: String {
        if !заказ.контрагент.isEmpty { return заказ.контрагент }
        return заказ.продаю ? тР("b2b_buyer_word") : тР("b2b_supplier")
    }
}

private struct СтрокаДокумента: View {
    let документ: ПолученныйДокумент

    private var вид: String {
        switch документ.вид {
        case "act": return тР("doc_t_act")
        case "waybill": return тР("doc_t_waybill")
        case "contract": return тР("doc_t_contract")
        case "poa": return тР("doc_t_poa")
        case "pricelist": return тР("doc_t_pricelist")
        default: return тР("doc_t_invoice")
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(документ.продавец.isEmpty ? "—" : документ.продавец)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(документ.вид == "pricelist" ? вид : "\(вид) № \(документ.номер)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                if документ.вид != "pricelist" {
                    Text(СделкиФормат.тенге(документ.сумма))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .monospacedDigit()
                }
                Text(документ.дата)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Коммерческие предложения

struct ЭкранКП: View {
    let открыть: (URL) -> Void

    @State private var входящие: [ЗапросКП] = []
    @State private var полученные: [ЗапросКП] = []
    @State private var квота: КвотаКП? = nil
    @State private var состояниеЭкрана: СостояниеРаздела = .идёт
    @State private var редактор: ЗапросКП? = nil
    @State private var отклонить: ЗапросКП? = nil
    @State private var плашка: String? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private var ждут: [ЗапросКП] { входящие.filter { $0.статус == "requested" } }
    private var отвечены: [ЗапросКП] { входящие.filter { $0.статус == "sent" || $0.статус == "declined" } }

    var body: some View {
        РамкаРаздела(состояние: состояниеЭкрана, открыть: открыть, повторить: { Task { await загрузить() } }) {
            содержимое
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тР("kp_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await загрузить() }
        .sheet(item: $редактор) { запрос in
            РедакторКП(запрос: запрос, квота: квота, открыть: открыть, отправлено: {
                показать(тР("kp_sent_ok"))
                Task { await загрузить() }
            })
        }
        .alert(тР("kp_decline_confirm"),
               isPresented: Binding(get: { отклонить != nil }, set: { if !$0 { отклонить = nil } })) {
            Button(тР("kp_decline_ok"), role: .destructive) {
                if let запрос = отклонить { отклонитьЗапрос(запрос) }
            }
            Button(БизнесText.т("cancel"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let плашка { ПлашкаКошелька(текст: плашка) }
        }
    }

    private func загрузить() async {
        do {
            let продавец = try await БизнесРазделыAPI.запросыКП(роль: "seller")
            входящие = продавец.запросы
            квота = продавец.квота ?? квота
            let покупатель = try? await БизнесРазделыAPI.запросыКП(роль: "buyer")
            полученные = (покупатель?.запросы ?? []).filter { $0.статус == "sent" && !$0.текст.isEmpty }
            состояниеЭкрана = .готово
        } catch {
            if входящие.isEmpty { состояниеЭкрана = состояние(error) }
        }
    }

    private var содержимое: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(тР("kp_sub"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.текстВторой)
                if let квота {
                    ЗаметкаБизнеса("\(тР("kp_ai_left")): \(квота.осталось)/\(квота.лимит)",
                                   тон: .инфо, значок: "sparkles")
                }
                ЗаголовокГруппы(текст: тР("kp_incoming"))
                if ждут.isEmpty {
                    ПустоРаздела(текст: тР("kp_none_incoming"))
                } else {
                    ForEach(ждут) { запрос in
                        КарточкаКП(запрос: запрос, имя: запрос.покупатель.isEmpty ? тР("b2b_buyer_word") : запрос.покупатель,
                                   дата: запрос.создан) {
                            HStack(spacing: 8) {
                                КнопкаБизнеса(подпись: тР("kp_generate_btn")) { редактор = запрос }
                                КнопкаБизнеса(подпись: тР("kp_decline"), второстепенная: true) { отклонить = запрос }
                            }
                        }
                    }
                }
                ЗаголовокГруппы(текст: тР("kp_sent_lbl"))
                if отвечены.isEmpty {
                    ПустоРаздела(текст: "—")
                } else {
                    ForEach(отвечены) { запрос in
                        КарточкаКП(запрос: запрос, имя: запрос.покупатель, дата: запрос.отправлен.isEmpty ? запрос.создан : запрос.отправлен) {
                            HStack {
                                МеткаБизнеса(текст: запрос.статус == "sent" ? тР("kp_status_sent") : тР("kp_status_declined"))
                                Spacer()
                                if запрос.статус == "sent" && !запрос.текст.isEmpty {
                                    КнопкаPDFКП(текст: запрос.текст, кому: запрос.покупатель,
                                                позиции: запрос.позиции.map { ($0.название, $0.количество, $0.цена) })
                                    ShareLink(item: запрос.текст) {
                                        Label(тР("kp_share"), systemImage: "square.and.arrow.up")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                    .tint(Theme.акцент)
                                }
                            }
                        }
                    }
                }
                if !полученные.isEmpty {
                    ЗаголовокГруппы(текст: тР("kp_received_lbl"))
                    ForEach(полученные) { запрос in
                        КарточкаКП(запрос: запрос, имя: запрос.продавец.isEmpty ? тР("kp_from_seller") : запрос.продавец,
                                   дата: запрос.отправлен.isEmpty ? запрос.создан : запрос.отправлен) {
                            ПолученноеКП(текст: запрос.текст, от: запрос.продавец,
                                         позиции: запрос.позиции.map { ($0.название, $0.количество, $0.цена) })
                        }
                    }
                }
            }
            .padding(12)
        }
        .refreshable { await загрузить() }
    }

    private func отклонитьЗапрос(_ запрос: ЗапросКП) {
        Task {
            if let ошибка = await БизнесРазделыAPI.отклонитьКП(запрос.id) {
                показать(ошибка)
            } else {
                await загрузить()
            }
        }
    }

    private func показать(_ текст: String) {
        withAnimation { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if плашка == текст { withAnimation { плашка = nil } }
        }
    }
}

/// Карточка запроса КП (kpCardIncoming / kpCardDone): кто, когда, позиции, заметка, итог и низ.
private struct КарточкаКП<Низ: View>: View {
    let запрос: ЗапросКП
    let имя: String
    let дата: String
    let низ: Низ

    init(запрос: ЗапросКП, имя: String, дата: String, @ViewBuilder низ: () -> Низ) {
        self.запрос = запрос
        self.имя = имя
        self.дата = дата
        self.низ = низ()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(имя)
                    .font(.system(size: 14.5, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 6)
                Text(дата)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(запрос.позиции) { позиция in
                HStack(alignment: .firstTextBaseline) {
                    Text(позиция.название)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text("× " + String(позиция.количество))
                        .foregroundStyle(Theme.текстВторой)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
            }
            if !запрос.заметка.isEmpty {
                Text(запрос.заметка)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if запрос.сумма > 0 {
                Text("\(тР("cmp_items_total")) \(СделкиФормат.тенге(запрос.сумма))")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Theme.текст)
            }
            низ
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// Полученное КП: текст раскрывается, «Поделиться».
private struct ПолученноеКП: View {
    let текст: String
    var от: String = ""
    var позиции: [(String, Int, Int)] = []
    @State private var открыт = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(текст)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.текст)
                .lineLimit(открыт ? nil : 4)
                .textSelection(.enabled)
            HStack {
                Button {
                    withAnimation { открыт.toggle() }
                } label: {
                    Image(systemName: открыт ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                }
                Spacer()
                КнопкаPDFКП(текст: текст, от: от, позиции: позиции)
                ShareLink(item: текст) {
                    Label(тР("kp_share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .tint(Theme.акцент)
        }
    }
}

/// kpOpenGen сайта: шаблоны и Kliko AI, правка текста, «Отправить покупателю».
private struct РедакторКП: View {
    let запрос: ЗапросКП
    let открыть: (URL) -> Void
    let отправлено: () -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var текст = ""
    @State private var квота: КвотаКП?
    @State private var занят = false
    @State private var пишетИИ = false
    @State private var сообщение: String? = nil
    @State private var нужно: String? = nil

    init(запрос: ЗапросКП, квота: КвотаКП?, открыть: @escaping (URL) -> Void, отправлено: @escaping () -> Void) {
        self.запрос = запрос
        self.открыть = открыть
        self.отправлено = отправлено
        _квота = State(initialValue: квота)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(тР("kp_for")): \(запрос.покупатель) · \(СделкиФормат.тенге(запрос.сумма))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            кнопкаРежима(тР("kp_tpl_formal"), значок: "doc.text") { сформировать(ии: false, шаблон: "formal") }
                            кнопкаРежима(тР("kp_tpl_short"), значок: "text.alignleft") { сформировать(ии: false, шаблон: "short") }
                            кнопкаРежима(подписьИИ, значок: "sparkles") { сформировать(ии: true, шаблон: "") }
                        }
                    }
                    if let нужно {
                        ЗаметкаБизнеса(нужно, тон: .предупреждение, значок: "exclamationmark.triangle")
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $текст)
                            .font(.system(size: 14))
                            .frame(minHeight: 260)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Theme.поверхность,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                    .strokeBorder(Theme.линия, lineWidth: 1)
                            }
                            .disabled(пишетИИ)
                        if текст.isEmpty || пишетИИ {
                            Text(пишетИИ ? тР("kp_ai_wait") : тР("kp_gen_ph"))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.текстВторой)
                                .padding(16)
                                .allowsHitTesting(false)
                        }
                    }
                    if let сообщение {
                        ЗаметкаБизнеса(сообщение, тон: .плохо, значок: "exclamationmark.circle")
                    }
                    КнопкаБизнеса(подпись: тР("kp_send_btn"), занято: занят) { отправить() }
                }
                .padding(12)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(тР("kp_gen_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(БизнесText.т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    private var подписьИИ: String {
        guard let квота else { return тР("kp_ai_btn") }
        return "\(тР("kp_ai_btn")) (\(квота.осталось)/\(квота.лимит))"
    }

    private func кнопкаРежима(_ подпись: String, значок: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Label(подпись, systemImage: значок)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстПункта)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.фонПункта, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(пишетИИ || занят)
    }

    private func сформировать(ии: Bool, шаблон: String) {
        сообщение = nil
        нужно = nil
        if ии { пишетИИ = true }
        Task {
            let итог = await БизнесРазделыAPI.сформироватьКП(запрос.id, ии: ии, шаблон: шаблон)
            пишетИИ = false
            switch итог {
            case .текст(let готовый, let новая):
                текст = готовый
                if let новая { квота = новая }
            case .нужныРеквизиты:
                нужно = тР("kp_need_company")
            case .нуженПРО:
                нужно = тР("kp_need_pro")
            case .ошибка(let ошибка, let новая):
                сообщение = ошибка
                if let новая { квота = новая }
            }
        }
    }

    private func отправить() {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else {
            сообщение = тР("kp_empty")
            return
        }
        занят = true
        Task {
            let ошибка = await БизнесРазделыAPI.отправитьКП(запрос.id, текст: чистый)
            занят = false
            if let ошибка {
                сообщение = ошибка
            } else {
                закрыть()
                отправлено()
            }
        }
    }
}

// MARK: - Разделы магазина

struct ЭкранРазделовМагазина: View {
    let открыть: (URL) -> Void

    @State private var разделы: [РазделМагазина] = []
    @State private var состояниеЭкрана: СостояниеРаздела = .идёт
    @State private var сохраняем = false
    @State private var сообщение: String? = nil
    @State private var хорошо = false
    @FocusState private var поле: UUID?

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        РамкаРаздела(состояние: состояниеЭкрана, открыть: открыть, повторить: { Task { await загрузить() } }) {
            содержимое
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тР("sec_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await загрузить() }
    }

    private func загрузить() async {
        guard await естьФункция("sections") else {
            состояниеЭкрана = .нуженПРО
            return
        }
        do {
            разделы = try await БизнесРазделыAPI.разделы()
            состояниеЭкрана = .готово
        } catch {
            состояниеЭкрана = состояние(error)
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ЗаметкаБизнеса(тР("sec_help"), тон: .инфо, значок: "square.grid.2x2")
                if разделы.isEmpty {
                    ПустоРаздела(текст: тР("sec_empty"))
                }
                ForEach(Array(разделы.enumerated()), id: \.element.строка) { номер, раздел in
                    строка(номер, раздел)
                }
                Button {
                    guard разделы.count < 40 else {
                        сообщение = тР("sec_max")
                        хорошо = false
                        return
                    }
                    let новый = РазделМагазина(id: "", название: "")
                    разделы.append(новый)
                    поле = новый.строка
                } label: {
                    Label(тР("sec_add"), systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.оттенокАкцента,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                if let сообщение {
                    ЗаметкаБизнеса(сообщение, тон: хорошо ? .хорошо : .плохо,
                                   значок: хорошо ? "checkmark.circle" : "exclamationmark.circle")
                }
                КнопкаБизнеса(подпись: тР("save"), занято: сохраняем) { сохранить() }
            }
            .padding(12)
        }
    }

    private func строка(_ номер: Int, _ раздел: РазделМагазина) -> some View {
        HStack(spacing: 8) {
            TextField(тР("sec_name_ph"), text: Binding(
                get: { номер < разделы.count ? разделы[номер].название : "" },
                set: { новое in
                    if номер < разделы.count { разделы[номер].название = String(новое.prefix(60)) }
                }))
                .focused($поле, equals: раздел.строка)
                .font(.system(size: 15))
                .padding(10)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            Button {
                guard номер > 0 else { return }
                разделы.swapAt(номер, номер - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(номер == 0)
            .accessibilityLabel(тР("a11y_up"))
            Button {
                guard номер + 1 < разделы.count else { return }
                разделы.swapAt(номер, номер + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(номер + 1 >= разделы.count)
            .accessibilityLabel(тР("a11y_down"))
            Button(role: .destructive) {
                if номер < разделы.count { разделы.remove(at: номер) }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel(тР("delete"))
        }
        .buttonStyle(.borderless)
        .tint(Theme.акцент)
    }

    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        сообщение = nil
        Task {
            do {
                разделы = try await БизнесРазделыAPI.сохранитьРазделы(разделы)
                сообщение = тР("sec_saved")
                хорошо = true
                UIAccessibility.post(notification: .announcement, argument: тР("sec_saved"))
            } catch let с as БизнесРазделыAPI.Сбой {
                сообщение = с.текст
                хорошо = false
            } catch {
                сообщение = БизнесText.т("no_conn")
                хорошо = false
            }
            сохраняем = false
        }
    }
}
