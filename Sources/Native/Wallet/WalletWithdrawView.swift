import SwiftUI

/**
 ЭКРАН «ВЫВОД СРЕДСТВ» — ЭТАП 47 (владелец 26.09.2026). 🔴 Открывается только при Config.деньгиКошелька (false):
 выключено — кнопки «Вывести» ведут в кабинет сайта и этот лист не показывается.

 Разметка #withdraw-screen и модуль wallet сайта: двухшаговый мастер («1 Сумма — 2 Карта и проверка», комментарий
 владельца в HTML от 15.09.2026). Шаг 1: подзаголовок с комиссией, ступень доверия (wdLadderCard), «На удержании»
 (wdHeldCard), «Пополнение с карты» (wdTopupLockCard), «Доступно к выводу», пресеты и своя сумма, подсказка минимума,
 живой расчёт (сумма, банковский сбор, комиссия, к зачислению) и «Далее · N ₸». Шаг 2: «Сумма: N — Изменить», «Способ
 вывода» (карта — единственный способ разметки), «Проверьте данные» (wdChkRender), «Авто-вывод», условия и кнопка
 «Всё верно, вывести N ₸». Для карты сайт не задаёт второго вопроса (boostConfirm — только для счёта): сама кнопка со
 суммой и блок «Проверьте данные» над ней и есть подтверждение.
 */
struct ЭкранВывода: View {
    @ObservedObject var модель: ВыводМодель
    @ObservedObject private var кошелёк = КошелёкМодель.shared
    let открыть: (URL) -> Void
    let закрыть: () -> Void
    @FocusState private var полеВФокусе: Bool

    init(модель: ВыводМодель, открыть: @escaping (URL) -> Void, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.открыть = открыть
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    private var правила: ПравилаВывода { модель.правила }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    шаги
                    if модель.шаг == 1 {
                        ШагСуммыВывода(модель: модель, правила: правила, полеВФокусе: $полеВФокусе, открыть: открыть)
                    } else {
                        ШагКартыВывода(модель: модель, правила: правила, открыть: открыть, закрыть: закрыть)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            /* Плашки модели кошелька («Авто-вывод включён», ошибки) — лист закрывает экран кошелька, поэтому и здесь. */
            .overlay(alignment: .bottom) {
                if let текст = кошелёк.плашка { ПлашкаКошелька(текст: текст) }
            }
            .navigationTitle(т("wd_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button(т("ok")) { полеВФокусе = false }
                    }
                }
            }
        }
        .interactiveDismissDisabled(модель.идёт)
        .modifier(ОкнаВывода(модель: модель, открыть: открыть, закрыть: закрыть))
    }

    /// #wd-steps: «1 Сумма — 2 Карта и проверка» (на экране — только для глаз, у сайта aria-hidden).
    private var шаги: some View {
        HStack(spacing: 8) {
            точка(1, т("wd_step_amount"))
            Rectangle()
                .fill(модель.шаг > 1 ? Theme.зелёный2 : Theme.линия)
                .frame(height: 2)
            точка(2, т("wd_step_card"))
        }
        .accessibilityHidden(true)
    }

    private func точка(_ n: Int, _ подпись: String) -> some View {
        let вкл = модель.шаг >= n
        return HStack(spacing: 6) {
            Text(String(n))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(вкл ? Color.white : Theme.текстВторой)
                .frame(width: 22, height: 22)
                .background(вкл ? Theme.зелёный2 : Theme.поверхность2, in: Circle())
            Text(подпись)
                .font(.system(size: 13, weight: вкл ? .bold : .regular))
                .foregroundStyle(вкл ? Theme.текст : Theme.текстВторой)
                .lineLimit(1)
        }
    }
}

// MARK: - Шаг 1: сумма и расчёт

private struct ШагСуммыВывода: View {
    @ObservedObject var модель: ВыводМодель
    let правила: ПравилаВывода
    var полеВФокусе: FocusState<Bool>.Binding
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(КошелёкText.т("wd_sub", ["p": КошелёкФормат.процент(модель.сведения.комиссияПроц)])))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if let ступень = модель.сведения.ступень { КарточкаСтупени(ступень: ступень) }
            if модель.сведения.удержано > 0 {
                КарточкаУдержания(сумма: модель.сведения.удержано, удержания: модель.сведения.удержания)
            }
            if модель.сведения.пополнениеКартой > 0 {
                КарточкаПополненияКартой(сумма: модель.сведения.пополнениеКартой, поддержка: {
                    if let u = Config.url("/support.php?topic=payment") { открыть(u) }
                })
            }
            HStack {
                Label(т("wd_available"), systemImage: "wallet.pass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Text(КошелёкФормат.тенге(правила.доступно))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            сумма
            if модель.годна { расчёт }
            КнопкаСделки(модель.подписьДалее, вид: .главная, доступна: модель.годна) {
                полеВФокусе.wrappedValue = false
                модель.перейти(2)
            }
        }
    }

    /// .wal-pay: «Сумма вывода», пресеты, поле, подсказка минимума.
    private var сумма: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(т("wd_amount_label"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Text(модель.число > 0 ? КошелёкФормат.тенге(модель.число) : "—")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            let пресеты = правила.пресеты
            if пресеты.isEmpty {
                Text(КошелёкText.т("wd_nothing", n: КошелёкФормат.деньги(правила.доступно)))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                пресетыВид(пресеты)
            }
            if правила.предел < правила.доступно {
                Text(КошелёкText.т("wd_cap", n: КошелёкФормат.деньги(правила.потолок)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField(т("wd_amount_ph"), text: $модель.сумма)
                    .keyboardType(.numberPad)
                    .focused(полеВФокусе)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                Text("₸")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            Text(правила.подсказкаМинимума(строкаСтраницы: КошелёкМодель.shared.строкаМинимума))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    private func пресетыВид(_ пресеты: [Int]) -> some View {
        let колонки: [GridItem] = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: колонки, spacing: 8) {
            ForEach(пресеты, id: \.self) { n in
                let выбран = модель.число == n
                let подпись = КошелёкФормат.тенге(n) + (n == правила.предел ? " · " + т("wd_all") : "")
                Button {
                    полеВФокусе.wrappedValue = false
                    модель.поставить(n)
                } label: {
                    Text(подпись)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(выбран ? Color.white : Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(выбран ? Theme.зелёный2 : Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(выбран ? .isSelected : [])
            }
        }
    }

    /// #wd-fee-card: живой расчёт и подсказка (wdUpdateBtn).
    private var расчёт: some View {
        let р = правила.расчёт(модель.число)
        return VStack(alignment: .leading, spacing: 8) {
            СтрокаРасчёта(подпись: т("wd_sum_amt"), значение: КошелёкФормат.тенге(модель.число))
            if р.сборБанка > 0 {
                СтрокаРасчёта(подпись: т("wd_bank_fee"), значение: "−" + КошелёкФормат.тенге(р.сборБанка), сбор: true)
            }
            if р.комиссия > 0 {
                СтрокаРасчёта(подпись: КошелёкText.т("wd_fee_row", ["p": КошелёкФормат.процент(р.процент)]),
                              значение: "−" + КошелёкФормат.тенге(р.комиссия), сбор: true)
            }
            Divider()
            СтрокаРасчёта(подпись: т("wd_payout"), значение: КошелёкФормат.тенге(р.кЗачислению), итог: true)
            if let текстПодсказки = подсказка(р) {
                Text(текстПодсказки)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func подсказка(_ р: РасчётВывода) -> String? {
        if р.всего == 0 { return т("wd_free_ok") }
        if р.сборБанка > 0 && р.комиссия == 0 {
            let s = КошелёкМодель.shared.строкаБанка
            return s.isEmpty ? nil : s
        }
        if р.безКомиссии > 0 {
            return КошелёкText.т("wd_free_split", ["a": КошелёкФормат.деньги(р.безКомиссии),
                                                  "b": КошелёкФормат.деньги(р.подКомиссию)])
        }
        return nil
    }
}

// MARK: - Шаг 2: карта, проверка, авто-вывод, отправка

private struct ШагКартыВывода: View {
    @ObservedObject var модель: ВыводМодель
    let правила: ПравилаВывода
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                модель.перейти(1)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .accessibilityHidden(true)
                    Text(КошелёкText.т("wd_sum_is", n: КошелёкФормат.тенге(модель.число)))
                        .fontWeight(.bold)
                    Spacer(minLength: 6)
                    Text(т("wd_edit_amount"))
                        .foregroundStyle(Theme.акцент)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .padding(12)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            способ
            проверка
            авто
            условия
            if let подсказка = модель.подсказка {
                Text(подсказка)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            КнопкаСделки(модель.подписьВывести, вид: .главная, символ: "arrow.up.right", доступна: модель.можноВывести) {
                модель.вывести(закрыть: закрыть, открыть: открыть)
            }
        }
    }

    /// «Способ вывода»: в разметке страницы один способ — «Банковская карта / Любой банк Казахстана».
    private var способ: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("wd_method"))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 34, height: 34)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("wd_card"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(т("wd_card_note"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                Image(systemName: модель.способ == "card" ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(модель.способ == "card" ? Theme.зелёный2 : Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(модель.способ == "card" ? .isSelected : [])
            Label(т("wd_card_later"), systemImage: "lock")
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    /// «Проверьте данные» (wdChkRender): сумма, сборы, к зачислению и заметка для карты.
    @ViewBuilder
    private var проверка: some View {
        if модель.годна {
            let р = правила.расчёт(модель.число)
            VStack(alignment: .leading, spacing: 8) {
                Text(т("wd_check_t"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                СтрокаРасчёта(подпись: т("wd_sum_amt"), значение: КошелёкФормат.тенге(модель.число))
                if р.сборБанка > 0 {
                    СтрокаРасчёта(подпись: т("wd_bank_fee"), значение: "−" + КошелёкФормат.тенге(р.сборБанка), сбор: true)
                }
                if р.комиссия > 0 {
                    СтрокаРасчёта(подпись: КошелёкText.т("wd_fee_pct", ["p": КошелёкФормат.процент(р.процент)]),
                                  значение: "−" + КошелёкФормат.тенге(р.комиссия), сбор: true)
                }
                СтрокаРасчёта(подпись: т("wd_payout"), значение: КошелёкФормат.тенге(р.кЗачислению), итог: true)
                Text(т("wd_chk_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.зелёный2.opacity(0.4), lineWidth: 1.5)
            }
        }
    }

    /// «Авто-вывод» (wdAutoRender, wdAutoToggle): переключатель пишет только по нажатию.
    private var авто: some View {
        let с = модель.сведения
        var подпись = т("wd_auto_off")
        if с.автоВывод {
            /* «Включён · на счёт · маска» / «Включён · на карту» (маску сайт показывает только у счёта). */
            let счёт = с.автоСпособ == "bank"
            подпись = т(счёт ? "wd_auto_on_bank" : "wd_auto_on")
            if счёт && !с.автоМаска.isEmpty { подпись += " · " + с.автоМаска }
        }
        let привязка = Binding<Bool>(get: { модель.сведения.автоВывод }, set: { новое in модель.переключитьАвто(новое) })
        return VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: привязка) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("wd_auto_t"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .tint(Theme.green2)
            .disabled(модель.автоИдёт)
            if с.автоВывод {
                Text(КошелёкText.т("wd_auto_hint", n: "16 000"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    /// .wal-terms: три условия; второе со ставкой — строка T страницы.
    private var условия: some View {
        let комиссия = КошелёкМодель.shared.строкаКомиссии
        let второе = комиссия.isEmpty
            ? КошелёкText.т("wd_term2_s", ["p": КошелёкФормат.процент(модель.сведения.комиссияПроц)])
            : комиссия
        return VStack(alignment: .leading, spacing: 10) {
            условие("checkmark.shield", т("wd_term1_t"), т("wd_term1_s"))
            условие("percent", т("wd_term2_t"), второе)
            условие("bell", т("wd_term3_t"), т("wd_term3_s"))
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func условие(_ значок: String, _ заголовок: String, _ подпись: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(заголовок)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Строка расчёта (.wal-sum-row)

private struct СтрокаРасчёта: View {
    let подпись: String
    let значение: String
    var сбор = false
    var итог = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(подпись)
                .font(.system(size: 14, weight: итог ? .bold : .regular))
                .foregroundStyle(итог ? Theme.текст : Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: итог ? 16 : 14, weight: .heavy))
                .foregroundStyle(сбор ? КраскаОбъявлений.предупреждениеТекст : Theme.текст)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ступень доверия (wdLadderCard)

private struct КарточкаСтупени: View {
    let ступень: СтупеньДоверия

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    /// «До ступени «X»: N сделок, M ₸ оборота, D суток» / «Это верхняя ступень.» / ничего.
    private var следующая: String? {
        var части: [String] = []
        if ступень.нужноСделок > 0 { части.append(String(ступень.нужноСделок) + " " + т("lad_deals")) }
        if ступень.нужноОборота > 0 { части.append(КошелёкФормат.тенге(ступень.нужноОборота) + " " + т("lad_turnover")) }
        if ступень.нужноСуток > 0 { части.append(String(ступень.нужноСуток) + " " + т("lad_days")) }
        if ступень.естьСледующая && !части.isEmpty {
            return КошелёкText.т("lad_next", ["l": ступень.следующая, "m": части.joined(separator: ", ")])
        }
        return ступень.естьСледующая ? nil : т("lad_top")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Theme.золото)
                    .accessibilityHidden(true)
                Text(ступень.название)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if ступень.снижена {
                    Text(т("lad_penalty"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.плохоТекст)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(КраскаОбъявлений.плохоФон, in: Capsule())
                }
            }
            HStack(spacing: 10) {
                потолок(т("lad_op"), ступень.заОперацию)
                потолок(т("lad_month"), ступень.заМесяц)
            }
            if let следующая {
                Text(следующая)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func потолок(_ подпись: String, _ сумма: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(подпись)
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
            Text(КошелёкФормат.тенге(сумма))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }
}

// MARK: - Окна листа вывода

private struct ОкнаВывода: ViewModifier {
    @ObservedObject var модель: ВыводМодель
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    func body(content: Content) -> some View {
        content
            .sheet(item: $модель.eGov) { окно in
                ОкноEGov(запрос: окно.запрос, готово: { модель.eGovПройден() }, закрыть: { модель.eGov = nil })
            }
            .sheet(item: $модель.условия) { у in
                ОкноСоглашения(редакция: у.редакция, пункты: у.пункты, принято: { модель.условия = nil },
                               выйти: { модель.условия = nil }, нуженВход: { модель.условия = nil })
            }
            .sheet(item: $модель.банк) { б in
                ОкноБанкаКошелька(адрес: б.адрес, вернулись: { итог in
                    модель.банк = nil
                    if итог == .выплата {
                        закрыть()
                        КошелёкМодель.shared.вернулисьСБанка()
                    }
                }, закрыть: {
                    модель.банк = nil
                    закрыть()
                    КошелёкМодель.shared.вернулисьСБанка()
                })
            }
            .alert(т("err_generic"), isPresented: ошибкаНаЭкране) {
                Button(т("ok"), role: .cancel) {}
            } message: {
                Text(модель.ошибка ?? "")
            }
            .alert(т("split_t"), isPresented: $модель.магазин) {
                Button(т("split_go")) {
                    if let u = ВыводМодель.адресМагазина {
                        закрыть()
                        открыть(u)
                    }
                }
                Button(т("cancel"), role: .cancel) {}
            } message: {
                Text(т("split_s"))
            }
            .overlay {
                if let итог = модель.итог { окноИтога(итог) }
            }
    }

    private var ошибкаНаЭкране: Binding<Bool> {
        Binding(get: { модель.ошибка != nil }, set: { if !$0 { модель.ошибка = nil } })
    }

    /// wdResultModal: «Заявка принята», к зачислению, строки, срок или «Осталось указать карту», кнопки.
    private func окноИтога(_ итог: ВыводМодель.Итог) -> some View {
        var строки: [(String, String)] = [(т("wd_res_amt"), КошелёкФормат.тенге(итог.сумма))]
        if итог.комиссия > 0 { строки.append((т("wd_res_fee"), "−" + КошелёкФормат.тенге(итог.комиссия))) }
        строки.append((т("wd_res_get"), КошелёкФормат.тенге(итог.кЗачислению)))
        let текст: String
        var кнопки: [ОкноИтогаКошелька.Кнопка] = []
        if let ссылка = итог.ссылка {
            текст = т("wd_res_now")
            кнопки.append(ОкноИтогаКошелька.Кнопка(подпись: т("wd_res_go"), главная: true, действие: {
                модель.итог = nil
                модель.банк = АдресБанка(адрес: ссылка)
            }))
            кнопки.append(ОкноИтогаКошелька.Кнопка(подпись: т("wd_res_later"), главная: false, действие: {
                модель.итог = nil
                закрыть()
            }))
        } else {
            текст = КошелёкText.т("wd_res_when", ["t": т("wd_term_card")]) + " " + т("wd_res_track")
            кнопки.append(ОкноИтогаКошелька.Кнопка(подпись: т("wd_res_ok"), главная: true, действие: {
                модель.итог = nil
                закрыть()
            }))
        }
        return ОкноИтогаКошелька(вид: .хорошо, заголовок: т("wd_res_t") + "\n" + т("wd_res_s"),
                                 сумма: КошелёкФормат.тенге(итог.кЗачислению), строки: строки, текст: текст,
                                 кнопки: кнопки)
    }
}
