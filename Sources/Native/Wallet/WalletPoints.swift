import SwiftUI

/**
 «БАЛЛЫ» — ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Только чтение.

 Экран #points-screen страницы кабинета, который заполняет showPoints модуля deals: GET escrow.php?action=points →
 «БАЛАНС БАЛЛОВ», строка кэшбэка («Ваш кэшбэк N% · 1 балл = 1 ₸ · до M% сделки можно оплатить баллами»), уровень,
 «До уровня «X»: ещё N баллов» с полосой (или «Максимальный уровень достигнут!»), «Как получить баллы», «Как потратить»,
 «Уровни участника» (0 / 100 / 500 / 1 000 / 5 000 — разметка страницы; кэшбэк ступени — из tiers) и «История
 начислений» со ссылкой «→ сделка». Ошибка — «Ошибка», как у сайта. Сюда ведёт ссылка ?s=points и строка «Баллы»
 вкладки «Кабинет». Тратятся баллы только при оплате сделки (окно «Применить баллы?» — этап 44, деньги сделок).

 Рубильник админки (СессияПриложения.баллыВключены): ответ этого экрана его и обновляет; выключены — экран закрывается
 сам, пустой заглушки нет.
 */
struct ЭкранБаллов: View {
    let открыть: (URL) -> Void

    @State private var баллы: БаллыКошелька? = nil
    @State private var ошибка = false
    @State private var нуженВход = false
    @State private var входОткрыт = false
    @State private var сделкаОткрыть: String? = nil
    @ObservedObject private var сессия = СессияПриложения.shared
    @Environment(\.dismiss) private var уйти

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    /// Фиолетовый баллов сайта (#7c3aed) в светлой и тёмной теме.
    static let фиолетовый = Theme.цвет(0x7C3AED, 0xA78BFA)
    static let фиолетовыйФон = Theme.цвет(0xF5F3FF, 0x2A1F45)
    /// Уровни разметки #ps-levels: порог — ключ названия.
    static let уровни: [Int] = [0, 100, 500, 1000, 5000]
    /// Точки уровней разметки: #9ca3af, #eab308, #f97316, #3b82f6, #a855f7.
    static let точкиУровней: [Int: UInt32] = [0: 0x9CA3AF, 100: 0xEAB308, 500: 0xF97316, 1000: 0x3B82F6, 5000: 0xA855F7]
    /// #374151 и #e5e7eb разметки; в тёмной теме — текст и линия приложения.
    static let текстБлока = Theme.цвет(0x374151, 0xEAF3EE)
    static let рамкаБлока = Theme.цвет(светлый: Theme.hex(0xE5E7EB), тёмный: Theme.hex(0xFFFFFF, 0.10))
    /// #f59e0b: кубок уровней и звезда начисления.
    static let янтарь = Color(uiColor: Theme.hex(0xF59E0B))
    /// #dc2626: списание баллов.
    static let красный = Theme.цвет(0xDC2626, 0xFF8A8F)

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: т("points")))
            .task { await загрузить() }
            .onChange(of: сессия.баллыВключены) { _, включены in
                if !включены && баллы != nil { уйти() }
            }
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
        } else if let баллы, сессия.баллыВключены {
            ScrollView {
                /* Поле 14; между блоками 14, после карточки баланса и уровней — 16 (разметка #points-screen). */
                LazyVStack(alignment: .leading, spacing: 14) {
                    карточка(баллы)
                        .padding(.bottom, 2)
                    какПолучить(баллы)
                    какПотратить(баллы)
                    уровни(баллы)
                        .padding(.bottom, 2)
                    история(баллы)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
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
            СессияПриложения.shared.принятьБаллы(j)
            if !МоиОбъявленияAPI.нетСессии(j) && !СессияПриложения.shared.баллыВключены {
                /* Баллы выключены в админке — экрана нет. */
                баллы = nil
                уйти()
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
        VStack(alignment: .leading, spacing: 0) {
            Text(т("ps_balance"))
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.48)
                .foregroundStyle(Color.white.opacity(0.8))
                .padding(.bottom, 4)
            Text(КошелёкФормат.деньги(б.баллы))
                .font(.system(size: 40, weight: .black))
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(КошелёкText.т("ps_cashline", ["c": КошелёкФормат.процент(б.кэшбэк),
                                               "m": КошелёкФормат.процент(б.максимум)]))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 10) {
                if !б.уровень.isEmpty {
                    Text(б.уровень)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.25), in: Capsule())
                }
                Text(подсказкаУровня(б))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
            if б.доСледующего > 0 {
                let доля = min(1, Double(б.баллы) / Double(б.доСледующего))
                GeometryReader { гео in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white).frame(width: гео.size.width * доля)
                    }
                }
                .frame(height: 7)
                .padding(.top, 12)
                .accessibilityElement()
                .accessibilityLabel(т("a11y_bar"))
                .accessibilityValue(String(Int((доля * 100).rounded())) + "%")
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x7C3AED)), Color(uiColor: Theme.hex(0xA855F7))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
    }

    /// «До уровня «X»: ещё N баллов» или «Максимальный уровень достигнут!».
    private func подсказкаУровня(_ б: БаллыКошелька) -> String {
        guard б.доСледующего > 0 else { return т("ps_max") }
        return КошелёкText.т("ps_next", ["l": б.следующийУровень,
                                        "n": КошелёкФормат.деньги(б.доСледующего - б.баллы)])
    }

    // MARK: - Как получить, как потратить

    private func какПолучить(_ б: БаллыКошелька) -> some View {
        блок(т("ps_earn_t"), значок: "lightbulb") {
            VStack(alignment: .leading, spacing: 8) {
                строкаДохода("cart", т("ps_buyer_b"), КошелёкText.т("ps_buyer_s", n: КошелёкФормат.процент(б.кэшбэк)))
                /* У сайта строка продавца по умолчанию из разметки — «0.5% от суммы»; сервер прислал seller_pct —
                   его число. */
                строкаДохода("shippingbox", т("ps_seller_b"), КошелёкText.т("ps_seller_s", n: КошелёкФормат.процент(б.продавцу ?? 0.5)))
            }
        }
    }

    private func строкаДохода(_ значок: String, _ жирное: String, _ хвост: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 17))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 20)
                .accessibilityHidden(true)
            (Text(жирное).bold() + Text(хвост))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func какПотратить(_ б: БаллыКошелька) -> some View {
        /* «Как потратить» — на --tint-ok с рамкой #86efac, заголовок --on-ok. */
        блок(т("ps_spend_t"), значок: "gift", отступ: 8, краскаЗаголовка: КраскаСделокКабинета.хорошоТекст,
             фон: КраскаСделокКабинета.хорошоФон, рамка: Theme.цвет(0x86EFAC, 0x1F5236)) {
            Text(КошелёкText.т("ps_spend", n: КошелёкФормат.процент(б.максимум)))
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(ЭкранБаллов.текстБлока)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Уровни (#ps-levels)

    private func уровни(_ б: БаллыКошелька) -> some View {
        блок(т("ps_levels_t"), значок: "trophy", краскаЗначка: ЭкранБаллов.янтарь, краскаЗаголовка: Theme.текст) {
            VStack(spacing: 6) {
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
        let краска = достигнут ? ЭкранБаллов.фиолетовый : Theme.цвет(0x6B7280, 0x90A499)
        return HStack(spacing: 4) {
            Circle()
                .fill(Color(uiColor: Theme.hex(ЭкранБаллов.точкиУровней[порог] ?? 0x9CA3AF)))
                .frame(width: 6, height: 6)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
            Text(т("lvl_" + String(порог)))
                .font(.system(size: 13, weight: достигнут ? .bold : .regular))
                .foregroundStyle(краска)
            Spacer(minLength: 8)
            Text(подпись)
                .font(.system(size: 13, weight: достигнут ? .bold : .regular))
                .foregroundStyle(Color(uiColor: Theme.hex(0x9CA3AF)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(достигнут ? т("a11y_reached") : "")
    }

    // MARK: - История начислений (#points-log)

    /// Заголовок «История начислений» и строки — прямо на странице, без карточки (#points-log).
    private func история(_ б: БаллыКошелька) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(т("ps_log_t"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ЭкранБаллов.текстБлока)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            if б.история.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "star")
                        .font(.system(size: 36))
                        .foregroundStyle(ЭкранБаллов.янтарь)
                        .accessibilityHidden(true)
                    Text(т("ps_log_none"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(б.история) { запись in
                        строкаИстории(запись)
                        Rectangle()
                            .fill(Theme.цвет(светлый: Theme.hex(0xF3F4F6), тёмный: Theme.hex(0xFFFFFF, 0.08)))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func строкаИстории(_ з: ЗаписьБаллов) -> some View {
        let плюс = з.баллы > 0
        return HStack(spacing: 10) {
            Image(systemName: з.тип == "earn" ? "star" : (з.тип == "spend" ? "gift" : "circle.fill"))
                .font(.system(size: з.тип == "earn" || з.тип == "spend" ? 15 : 6))
                .foregroundStyle(з.тип == "earn" ? ЭкранБаллов.янтарь : Theme.текст)
                .frame(width: 36, height: 36)
                .background(плюс ? ЭкранБаллов.фиолетовыйФон : КраскаСделокКабинета.предупреждениеФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(з.причина.isEmpty ? т("tx_generic") : з.причина)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    if !з.сделка.isEmpty && СделкиAPI.годныйНомер(з.сделка) {
                        Button(т("ps_deal")) { открытьСделку(з.сделка) }
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(КраскаСделокКабинета.иИТекст)
                            .buttonStyle(.borderless)
                    }
                }
                let когда = СделкиФормат.сВременем(з.когда)
                if !когда.isEmpty {
                    Text(когда)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 6)
            Text((плюс ? "+" : "") + КошелёкФормат.деньги(з.баллы))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(плюс ? ЭкранБаллов.фиолетовый : ЭкранБаллов.красный)
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

    /// Блок разметки: --card, рамка 1.5 #e5e7eb, радиус 18, поля 16; заголовок 13/700 со значком 14.
    private func блок<Содержимое: View>(_ заголовок: String, значок: String, отступ: CGFloat = 10,
                                        краскаЗначка: Color? = nil, краскаЗаголовка: Color = ЭкранБаллов.текстБлока,
                                        фон: Color = Theme.поверхность, рамка: Color = ЭкранБаллов.рамкаБлока,
                                        @ViewBuilder содержимое: () -> Содержимое) -> some View {
        VStack(alignment: .leading, spacing: отступ) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 13))
                    .foregroundStyle(краскаЗначка ?? краскаЗаголовка)
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(краскаЗаголовка)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            содержимое()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(рамка, lineWidth: 1.5)
        }
    }
}
