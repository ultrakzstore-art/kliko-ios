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
            .modifier(ШапкаСделок(заголовок: т("topup_title")))
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

    /// --g3 кабинета: третий цвет градиентов шапки формы и кнопки.
    private static let зелёный3 = Theme.цвет(0x22A05B, 0x5CD39A)
    /// rgba(52,201,151,.15): кольцо выбранной суммы.
    private static let кольцо = Color(red: 52 / 255, green: 201 / 255, blue: 151 / 255).opacity(0.15)

    /// .wal-pay: --card, рамка 1.5 --line, радиус 18, мягкая зелёная тень; шапка — градиент, тело — поля 16/20/20.
    private var форма: some View {
        VStack(alignment: .leading, spacing: 0) {
            шапкаФормы
            VStack(alignment: .leading, spacing: 12) {
                чипы
                своя
                Text(т("topup_limits"))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -2)
                кнопкаОплаты
                Text(согласие)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.текстВторой)
                    .tint(Theme.акцент)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .shadow(color: Color(red: 52 / 255, green: 201 / 255, blue: 151 / 255).opacity(0.3), radius: 12, x: 0, y: 12)
    }

    /// .wal-pay-head: градиент --g → --g2 60% → --g3, белый текст, поля 16/20.
    private var шапкаФормы: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(т("topup_pick"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer(minLength: 8)
            Text(модель.выбрано > 0 ? КошелёкФормат.тенге(модель.выбрано) : "—")
                .font(.system(size: 21, weight: .black))
                .tracking(-0.3)
                .foregroundStyle(Color.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(LinearGradient(stops: [.init(color: Theme.зелёный, location: 0), .init(color: Theme.зелёный2, location: 0.6),
                                           .init(color: Self.зелёный3, location: 1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .combine)
    }

    /// .wal-cta: градиент --g2 → --g3, радиус 14, 16/800; выключена — --surf2 и серый текст, без прозрачности.
    private var кнопкаОплаты: some View {
        let можно = модель.выбрано > 0 && модель.идёт == nil
        return Button {
            полеВФокусе = false
            модель.пополнить()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text(модель.подписьКнопки)
                    .font(.system(size: 16, weight: .heavy))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(можно ? Color.white : Theme.текстВторой)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if можно {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.зелёный2, Self.зелёный3], startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                } else {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .fill(Theme.поверхность2)
                }
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!можно)
    }

    /// Согласие со ссылками: «Условия оплаты и возврата» (oplata.php на языке сайта) и Freedom Pay.
    private var согласие: AttributedString {
        let условия = Config.страницаСайта("oplata.php")?.absoluteString ?? "https://kliko.kz/oplata.php"
        let текст = КошелёкText.т("topup_consent", ["u": условия])
        return (try? AttributedString(markdown: текст)) ?? AttributedString(текст)
    }

    private var чипы: some View {
        let колонки: [GridItem] = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10),
                                   GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: колонки, spacing: 10) {
            ForEach(ПополнениеМодель.суммы, id: \.self) { сумма in
                let выбран = модель.выбрано == сумма && !модель.своёПоле
                Button {
                    полеВФокусе = false
                    модель.выбрать(сумма)
                } label: {
                    /* .wal-amt: 13/700 --on-ok, «₸» мельче и бледнее; .on — --tint-ok, рамка --acc-on и кольцо 3px. */
                    (Text(КошелёкФормат.деньги(сумма))
                        + Text(" ₸").font(.system(size: 11, weight: .bold))
                            .foregroundColor(КраскаСделокКабинета.хорошоТекст.opacity(0.6)))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 41)
                        .background(выбран ? КраскаСделокКабинета.хорошоФон : Theme.поверхность,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(выбран ? КраскаСделокКабинета.акцент : Theme.линия, lineWidth: 1.5)
                        }
                        .background {
                            if выбран {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms + 3, style: .continuous)
                                    .fill(Self.кольцо)
                                    .padding(-3)
                            }
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
                .font(.system(size: 16, weight: .heavy))
                .monospacedDigit()
            Text("₸")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            кнопкаШага("minus", подпись: т("topup_less"), шаг: -1000)
            кнопкаШага("plus", подпись: т("topup_more"), шаг: 1000)
        }
        /* .wal-custom input: высота 48, --surf2, радиус 12, рамка 1.5. */
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(модель.своёПоле && модель.выбрано > 0 ? КраскаСделокКабинета.акцент : Theme.линия,
                              lineWidth: 1.5)
        }
    }

    private func кнопкаШага(_ значок: String, подпись: String, шаг: Int) -> some View {
        Button {
            модель.шаг(шаг)
        } label: {
            /* .wc-sb: 30×30, радиус 8, рамка 1.5 --line на --card, --on-ok 16/700. */
            Image(systemName: значок)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                .frame(width: 30, height: 30)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
    }

    /// .wal-trust.
    private var плашки: some View {
        HStack(alignment: .top, spacing: 10) {
            плашка("checkmark.circle", т("topup_t1"))
            плашка("bolt", т("topup_t2"))
            плашка("shield", т("topup_t3"))
        }
    }

    /// .wal-trust: плитка --card, рамка 1.5, радиус 14, поля 12/8, значок 19 --acc-on, 11/700.
    private func плашка(_ значок: String, _ подпись: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 17))
                .foregroundStyle(КраскаСделокКабинета.акцент)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
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
