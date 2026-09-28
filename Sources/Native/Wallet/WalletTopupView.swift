import SwiftUI

/**
 ЭКРАН «ПОПОЛНИТЬ КОШЕЛЁК» — ЭТАП 47 (владелец 26.09.2026). 🔴 Открывается только при Config.деньгиКошелька (false):
 выключено — кнопки «Пополнить» ведут в кабинет сайта и этот лист не показывается вовсе.

 Разметка #topup-screen сайта: подзаголовок, «Выберите сумму» с суммой справа, чипы 500…50 000 ₸, своя сумма с «−»/«+»
 по 1000, «Любая сумма от 100 ₸ до 1 000 000 ₸ за раз», кнопка «Пополнить на N ₸», согласие с условиями оплаты и
 Freedom Pay, плашки «Без комиссии · Зачисление сразу · Под защитой». Страница банка — лист внутри (ОкноБанкаКошелька),
 возврат ?topup= перехватывается; окна итога — tpmOpen сайта.
 */
struct ЭкранПополнения: View {
    @ObservedObject var модель: ПополнениеМодель
    let открыть: (URL) -> Void
    let закрыть: () -> Void
    @FocusState private var полеВФокусе: Bool

    init(модель: ПополнениеМодель, открыть: @escaping (URL) -> Void, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.открыть = открыть
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(LocalizedStringKey(т("topup_sub_app")))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    форма
                    плашки
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("topup_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                        .disabled(модель.идёт != nil || модель.сверяем)
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button(т("ok")) { полеВФокусе = false }
                    }
                }
            }
        }
        /* Пока идёт create (кнопка «Обработка…») или сверка «Проверяем оплату…», лист не смахнуть: страница банка и итог
           должны появиться поверх него, а не пропасть вместе с ним. */
        .interactiveDismissDisabled(модель.идёт != nil || модель.сверяем)
        .modifier(ОкнаПополнения(модель: модель, открыть: открыть, закрыть: закрыть))
    }

    // MARK: - Форма (.wal-pay)

    private var форма: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(т("topup_pick"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Text(модель.выбрано > 0 ? КошелёкФормат.тенге(модель.выбрано) : "—")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            чипы
            своя
            Text(т("topup_limits"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            КнопкаСделки(модель.подписьКнопки, вид: .главная, символ: "creditcard",
                         доступна: модель.выбрано > 0 && модель.идёт == nil) {
                полеВФокусе = false
                модель.пополнить()
            }
            Text(согласие)
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .tint(Theme.акцент)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    /// Согласие со ссылками: «Условия оплаты и возврата» (oplata.php на языке сайта) и Freedom Pay.
    private var согласие: AttributedString {
        let условия = Config.страницаСайта("oplata.php")?.absoluteString ?? "https://kliko.kz/oplata.php"
        let текст = КошелёкText.т("topup_consent", ["u": условия])
        return (try? AttributedString(markdown: текст)) ?? AttributedString(текст)
    }

    private var чипы: some View {
        let колонки: [GridItem] = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                                   GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: колонки, spacing: 8) {
            ForEach(ПополнениеМодель.суммы, id: \.self) { сумма in
                let выбран = модель.выбрано == сумма && !модель.своёПоле
                Button {
                    полеВФокусе = false
                    модель.выбрать(сумма)
                } label: {
                    Text(КошелёкФормат.тенге(сумма))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(выбран ? Color.white : Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(выбран ? Theme.зелёный2 : Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(выбран ? Theme.зелёный2 : Theme.линия, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(выбран ? .isSelected : [])
            }
        }
    }

    /// .wal-custom: своё поле, «₸», «−» и «+».
    private var своя: some View {
        HStack(spacing: 8) {
            TextField(т("topup_custom_ph"), text: $модель.своя)
                .keyboardType(.numberPad)
                .focused($полеВФокусе)
                .font(.system(size: 16, weight: .semibold))
                .monospacedDigit()
            Text("₸")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            кнопкаШага("minus", подпись: т("topup_less"), шаг: -1000)
            кнопкаШага("plus", подпись: т("topup_more"), шаг: 1000)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(модель.своёПоле && модель.выбрано > 0 ? Theme.зелёный2 : Theme.линия, lineWidth: 1.5)
        }
    }

    private func кнопкаШага(_ значок: String, подпись: String, шаг: Int) -> some View {
        Button {
            модель.шаг(шаг)
        } label: {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 36, height: 36)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
    }

    /// .wal-trust.
    private var плашки: some View {
        HStack(spacing: 8) {
            плашка("percent", т("topup_t1"))
            плашка("bolt", т("topup_t2"))
            плашка("lock.shield", т("topup_t3"))
        }
    }

    private func плашка(_ значок: String, _ подпись: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Окна листа пополнения

private struct ОкнаПополнения: ViewModifier {
    @ObservedObject var модель: ПополнениеМодель
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    func body(content: Content) -> some View {
        content
            .sheet(item: $модель.банк) { б in
                ОкноБанкаКошелька(адрес: б.адрес, вернулись: { итог in
                    switch итог {
                    case .пополнение(let оплачено): модель.вернулисьСБанка(оплачено: оплачено)
                    case .выплата: модель.банк = nil
                    }
                }, закрыть: { модель.листБанкаЗакрыт() })
            }
            .alert(т("err_generic"), isPresented: ошибкаНаЭкране) {
                Button(т("ok"), role: .cancel) {}
            } message: {
                Text(модель.ошибка ?? "")
            }
            .alert(т("topup_again_q"), isPresented: безБанкаНаЭкране, presenting: модель.безБанка) { сумма in
                Button(КошелёкText.т("topup_btn", n: КошелёкФормат.деньги(сумма))) {
                    модель.пополнитьБезБанка(сумма, готово: закрыть)
                }
                Button(т("cancel"), role: .cancel) {}
            } message: { _ in
                Text(т("topup_off"))
            }
            .alert(т("verify_t"), isPresented: верификацияНаЭкране) {
                Button(т("verify_go")) {
                    if let u = Config.страницаСайта("cabinet.php?go=verify") {
                        закрыть()
                        открыть(u)
                    }
                }
                Button(т("later"), role: .cancel) {}
            } message: {
                Text(модель.верификация ?? "")
            }
            .overlay {
                if let итог = модель.итог { окноИтога(итог) }
            }
    }

    private var ошибкаНаЭкране: Binding<Bool> {
        Binding(get: { модель.ошибка != nil }, set: { if !$0 { модель.ошибка = nil } })
    }

    private var безБанкаНаЭкране: Binding<Bool> {
        Binding(get: { модель.безБанка != nil }, set: { if !$0 { модель.безБанка = nil } })
    }

    private var верификацияНаЭкране: Binding<Bool> {
        Binding(get: { модель.верификация != nil }, set: { if !$0 { модель.верификация = nil } })
    }

    /// tpmOpen: processing (закрыть нельзя), ok («Отлично» — лист закрывается, как showMain сайта), pending, fail.
    @ViewBuilder
    private func окноИтога(_ итог: ПополнениеМодель.Итог) -> some View {
        switch итог {
        case .проверяем:
            ОкноИтогаКошелька(вид: .ждём, заголовок: т("tpm_proc_t"), текст: т("tpm_proc_s"))
        case .пополнен(let сумма, let баланс):
            ОкноИтогаКошелька(вид: .хорошо, заголовок: т("tpm_ok_t"),
                              сумма: сумма > 0 ? "+" + КошелёкФормат.тенге(сумма) : nil,
                              строки: строкаБаланса(баланс),
                              текст: т("tpm_ok_s_app"),
                              кнопки: [ОкноИтогаКошелька.Кнопка(подпись: т("tpm_ok_btn"), главная: true, действие: {
                                  модель.итог = nil
                                  закрыть()
                              })])
        case .принята(let баланс):
            ОкноИтогаКошелька(вид: .хорошо, заголовок: т("tpm_pend_t"), строки: строкаБаланса(баланс),
                              текст: т("tpm_pend_s"),
                              кнопки: [ОкноИтогаКошелька.Кнопка(подпись: т("ok"), главная: true, действие: {
                                  модель.итог = nil
                              })])
        case .неПрошла:
            ОкноИтогаКошелька(вид: .плохо, заголовок: т("tpm_fail_t"), текст: т("tpm_fail_s"),
                              кнопки: [ОкноИтогаКошелька.Кнопка(подпись: т("retry"), главная: true, действие: {
                                  модель.итог = nil
                              }), ОкноИтогаКошелька.Кнопка(подпись: т("close"), главная: false, действие: {
                                  модель.итог = nil
                                  закрыть()
                              })])
        }
    }

    private func строкаБаланса(_ баланс: Int?) -> [(String, String)] {
        guard let баланс else { return [] }
        return [(т("balance"), КошелёкФормат.тенге(баланс))]
    }
}
