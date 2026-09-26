import SwiftUI

/**
 «БАЛЛЫ» — ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Только чтение.

 Экран #points-screen страницы кабинета, который заполняет showPoints модуля deals: GET escrow.php?action=points →
 «БАЛАНС БАЛЛОВ», строка кэшбэка («Ваш кэшбэк N% · 1 балл = 1 ₸ · до M% сделки можно оплатить баллами»), уровень,
 «До уровня «X»: ещё N баллов» с полосой (или «Максимальный уровень достигнут!»), «Как получить баллы», «Как потратить»,
 «Уровни участника» (0 / 100 / 500 / 1 000 / 5 000 — разметка страницы; кэшбэк ступени — из tiers) и «История
 начислений» со ссылкой «→ сделка». Ошибка — «Ошибка», как у сайта. Сюда ведёт ссылка ?s=points и строка «Баллы»
 вкладки «Кабинет». Тратятся баллы только при оплате сделки (окно «Применить баллы?» — этап 44, деньги сделок).
 */
struct ЭкранБаллов: View {
    let открыть: (URL) -> Void

    @State private var баллы: БаллыКошелька? = nil
    @State private var ошибка = false
    @State private var нуженВход = false
    @State private var входОткрыт = false
    @State private var сделкаОткрыть: String? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    /// Фиолетовый баллов сайта (#7c3aed) в светлой и тёмной теме.
    static let фиолетовый = Theme.цвет(0x7C3AED, 0xA78BFA)
    static let фиолетовыйФон = Theme.цвет(0xF5F3FF, 0x2A1F45)
    /// Уровни разметки #ps-levels: порог — ключ названия.
    static let уровни: [Int] = [0, 100, 500, 1000, 5000]

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("points"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await загрузить() }
            .navigationDestination(item: $сделкаОткрыть) { номер in
                ЭкранСделки(id: номер, открыть: открыть)
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await загрузить() }
                })
            }
    }

    @ViewBuilder
    private var содержимое: some View {
        if нуженВход {
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        } else if let баллы {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    карточка(баллы)
                    какПолучить(баллы)
                    какПотратить(баллы)
                    уровни(баллы)
                    история(баллы)
                }
                .padding(12)
            }
            .refreshable { await загрузить() }
        } else if ошибка {
            ПустоСайта(значок: "exclamationmark.triangle", заголовок: т("err_generic"), кнопка: т("retry"),
                       действие: { Task { await загрузить() } })
        } else {
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func загрузить() async {
        do {
            guard let j = try await КошелёкAPI.получить("escrow.php?action=points") else {
                ошибка = баллы == nil
                return
            }
            if let новые = БаллыКошелька(j) {
                баллы = новые
                ошибка = false
                нуженВход = false
            } else if МоиОбъявленияAPI.нетСессии(j) {
                баллы = nil
                нуженВход = true
            } else {
                ошибка = баллы == nil
            }
        } catch {
            ошибка = баллы == nil
        }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let u = Config.страницаСайта("cabinet.php") {
            открыть(u)
        }
    }

    // MARK: - Карточка баланса

    private func карточка(_ б: БаллыКошелька) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("ps_balance"))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.8))
            Text(КошелёкФормат.деньги(б.баллы))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Color.white)
                .monospacedDigit()
            Text(КошелёкText.т("ps_cashline", ["c": КошелёкФормат.процент(б.кэшбэк),
                                               "m": КошелёкФормат.процент(б.максимум)]))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if !б.уровень.isEmpty {
                    Text(б.уровень)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(ЭкранБаллов.фиолетовый)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white, in: Capsule())
                }
                Text(подсказкаУровня(б))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if б.доСледующего > 0 {
                let доля = min(1, Double(б.баллы) / Double(б.доСледующего))
                GeometryReader { гео in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: гео.size.width * доля)
                    }
                }
                .frame(height: 6)
                .accessibilityElement()
                .accessibilityLabel(т("a11y_bar"))
                .accessibilityValue(String(Int((доля * 100).rounded())) + "%")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [ЭкранБаллов.фиолетовый, Color(uiColor: Theme.hex(0x4F46E5))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
    }

    /// «До уровня «X»: ещё N баллов» или «Максимальный уровень достигнут!».
    private func подсказкаУровня(_ б: БаллыКошелька) -> String {
        guard б.доСледующего > 0 else { return т("ps_max") }
        return КошелёкText.т("ps_next", ["l": б.следующийУровень,
                                        "n": КошелёкФормат.деньги(б.доСледующего - б.баллы)])
    }

    // MARK: - Как получить, как потратить

    private func какПолучить(_ б: БаллыКошелька) -> some View {
        блок(т("ps_earn_t"), значок: "plus.circle") {
            VStack(alignment: .leading, spacing: 8) {
                строкаДохода("cart", т("ps_buyer_b"), КошелёкText.т("ps_buyer_s", n: КошелёкФормат.процент(б.кэшбэк)))
                /* У сайта строка продавца по умолчанию из разметки — «0.5% от суммы»; сервер прислал seller_pct —
                   его число. */
                строкаДохода("tag", т("ps_seller_b"), КошелёкText.т("ps_seller_s", n: КошелёкФормат.процент(б.продавцу ?? 0.5)))
            }
        }
    }

    private func строкаДохода(_ значок: String, _ жирное: String, _ хвост: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: значок)
                .foregroundStyle(ЭкранБаллов.фиолетовый)
                .frame(width: 20)
                .accessibilityHidden(true)
            (Text(жирное).bold() + Text(хвост))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func какПотратить(_ б: БаллыКошелька) -> some View {
        блок(т("ps_spend_t"), значок: "creditcard") {
            Text(КошелёкText.т("ps_spend", n: КошелёкФормат.процент(б.максимум)))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Уровни (#ps-levels)

    private func уровни(_ б: БаллыКошелька) -> some View {
        блок(т("ps_levels_t"), значок: "trophy") {
            VStack(spacing: 8) {
                ForEach(ЭкранБаллов.уровни, id: \.self) { порог in
                    строкаУровня(порог, б)
                }
            }
        }
    }

    private func строкаУровня(_ порог: Int, _ б: БаллыКошелька) -> some View {
        let достигнут = порог <= б.баллы
        let подпись: String
        if let кэшбэк = б.ступени[порог] {
            подпись = КошелёкText.т("ps_pts_tier", ["n": КошелёкФормат.деньги(порог), "c": КошелёкФормат.процент(кэшбэк)])
        } else {
            подпись = КошелёкText.т("ps_pts", n: КошелёкФормат.деньги(порог))
        }
        return HStack {
            Label(т("lvl_" + String(порог)), systemImage: достигнут ? "star.fill" : "star")
                .font(.system(size: 14, weight: достигнут ? .bold : .regular))
                .foregroundStyle(достигнут ? ЭкранБаллов.фиолетовый : Theme.текстВторой)
            Spacer(minLength: 8)
            Text(подпись)
                .font(.system(size: 13, weight: достигнут ? .bold : .regular))
                .foregroundStyle(достигнут ? ЭкранБаллов.фиолетовый : Theme.текстВторой)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(достигнут ? т("a11y_reached") : "")
    }

    // MARK: - История начислений (#points-log)

    private func история(_ б: БаллыКошелька) -> some View {
        блок(т("ps_log_t"), значок: "clock.arrow.circlepath") {
            if б.история.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.золото)
                        .accessibilityHidden(true)
                    Text(т("ps_log_none"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(б.история) { запись in
                        строкаИстории(запись)
                        if запись.id != б.история.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func строкаИстории(_ з: ЗаписьБаллов) -> some View {
        let плюс = з.баллы > 0
        return HStack(spacing: 10) {
            Image(systemName: з.тип == "earn" ? "star.fill" : (з.тип == "spend" ? "cart" : "circle.fill"))
                .font(.system(size: з.тип == "earn" || з.тип == "spend" ? 15 : 6))
                .foregroundStyle(плюс ? ЭкранБаллов.фиолетовый : КраскаОбъявлений.предупреждениеТекст)
                .frame(width: 36, height: 36)
                .background(плюс ? ЭкранБаллов.фиолетовыйФон : КраскаОбъявлений.предупреждениеФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(з.причина.isEmpty ? т("tx_generic") : з.причина)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    if !з.сделка.isEmpty && СделкиAPI.годныйНомер(з.сделка) {
                        Button(т("ps_deal")) { открытьСделку(з.сделка) }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(КраскаОбъявлений.индиго)
                            .buttonStyle(.borderless)
                    }
                }
                let когда = СделкиФормат.сВременем(з.когда)
                if !когда.isEmpty {
                    Text(когда)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 6)
            Text((плюс ? "+" : "") + КошелёкФормат.деньги(з.баллы))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(плюс ? ЭкранБаллов.фиолетовый : КраскаОбъявлений.плохоТекст)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func открытьСделку(_ номер: String) {
        if Config.нативныеСделки {
            сделкаОткрыть = номер
        } else if let u = Config.страницаСайта("cabinet.php?deal=" + СделкиAPI.вАдрес(номер)) {
            открыть(u)
        }
    }

    // MARK: - Карточка раздела

    private func блок<Содержимое: View>(_ заголовок: String, значок: String,
                                        @ViewBuilder содержимое: () -> Содержимое) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(заголовок, systemImage: значок)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            содержимое()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}
