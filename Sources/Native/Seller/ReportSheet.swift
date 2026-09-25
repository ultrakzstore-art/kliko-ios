import SwiftUI

/**
 ОКНО ЖАЛОБЫ — ЭТАП 37 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Как #mk-report-scrim страницы объявления сайта (.mk-report-box в css/marketplace.min.css): «Пожаловаться» 21 pt жирным
 и «×» в квадрате 34 на --mk-surf2; «Выберите причину — жалоба уйдёт модераторам.»; причины — пилюли .mk-rr (рамка 1,5
 --mk-line, выбранная — зелёная заливка и белый текст); поле «Комментарий — по желанию» на три строки (рамка 1,5, в фокусе
 --mk-green2, до 600 знаков, как maxlength); красная «Отправить жалобу» (#dc2626) на всю ширину, в пути — «Отправляю…»
 и бледнее. Без причины — «Выберите причину» внизу, как toast сайта. С причиной — сначала вопрос «Отправить жалобу?»
 (владелец: действие для другого человека — только после подтверждения), потом один POST report.php?action=submit.
 Сайт принял — окно закрывается, внизу «Жалоба отправлена модераторам» или «Вы уже жаловались на это»; отказ — окно
 остаётся, внизу причина.
 */
struct ЛистЖалобы: View {
    let продавецID: String
    let объявление: String
    @ObservedObject private var действия = ДействияСПродавцом.shared
    @State private var причина: ПричинаЖалобы?
    @State private var комментарий = ""
    @State private var вопрос = false
    @FocusState private var вПоле: Bool
    @Environment(\.dismiss) private var закрыть

    /// Явный init: окно открывает блок продавца из другого файла.
    init(продавецID: String, объявление: String) {
        self.продавецID = продавецID
        self.объявление = объявление
    }

    /// maxlength поля сайта.
    private static let предел = 600

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                Text(SellerText.т("report_sub"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                причины
                    .padding(.top, 14)
                поле
                    .padding(.top, 12)
                кнопка
                    .padding(.top, 14)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.поверхность.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            ПлашкиВЛистеПродавца(закрытьЛист: { закрыть() })
        }
        .presentationBackground(Theme.поверхность)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(действия.жалобаВПути)
        .alert(SellerText.т("report_q"), isPresented: $вопрос) {
            Button(SellerText.т("cancel"), role: .cancel) {}
            Button(SellerText.т("report_send"), role: .destructive) {
                отправить()
            }
        } message: {
            Text(String(format: SellerText.т("report_q_msg"), причина?.подпись ?? ""))
        }
        .onChange(of: комментарий) { _, новое in
            if новое.count > Self.предел { комментарий = String(новое.prefix(Self.предел)) }
        }
    }

    /// .mk-report-head: заголовок и «×».
    private var шапка: some View {
        HStack(spacing: 12) {
            Text(SellerText.т("report"))
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button {
                закрыть()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
            .disabled(действия.жалобаВПути)
            .accessibilityLabel(SellerText.т("close"))
        }
    }

    /// .mk-report-reasons: пилюли с переносом строк, в порядке сайта.
    private var причины: some View {
        ПереносСтрок(промежуток: 8, междуСтрок: 8) {
            ForEach(ПричинаЖалобы.allCases) { вариант in
                ЧипПричины(подпись: вариант.подпись, выбран: причина == вариант) {
                    причина = вариант
                }
            }
        }
    }

    /// .mk-report-ta: три строки, растёт до шести.
    private var поле: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return TextField(SellerText.т("comment"), text: $комментарий, axis: .vertical)
            .lineLimit(3...6)
            .font(.system(size: 15))
            .foregroundStyle(Theme.текст)
            .focused($вПоле)
            .padding(12)
            .background(Theme.поверхность, in: форма)
            .overlay {
                форма.strokeBorder(вПоле ? Theme.зелёный2 : Theme.линия, lineWidth: 1.5)
            }
    }

    /// .mk-report-send: красная на всю ширину, в пути — «Отправляю…» и прозрачность 0,6.
    private var кнопка: some View {
        let идёт = действия.жалобаВПути
        return Button {
            нажалиОтправить()
        } label: {
            Text(SellerText.т(идёт ? "report_sending" : "report_send"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(КраскиЖалобы.кнопка,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .opacity(идёт ? 0.6 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(идёт)
    }

    /// mkReportSubmit: без причины — «Выберите причину»; с причиной — вопрос перед отправкой.
    private func нажалиОтправить() {
        guard причина != nil else {
            действия.показать(текст: SellerText.т("report_pick"), войти: false)
            return
        }
        вПоле = false
        вопрос = true
    }

    /// Ответили «Отправить жалобу» на вопрос — один запрос; принял сайт — окно закрывается.
    private func отправить() {
        guard let выбранная = причина else { return }
        let текст = String(комментарий.prefix(Self.предел))
        Task { @MainActor in
            let ушла = await действия.пожаловаться(на: продавецID, объявление: объявление, причина: выбранная,
                                                   комментарий: текст)
            if ушла { закрыть() }
        }
    }
}

/// .mk-rr: пилюля, рамка 1,5; выбранная — зелёная заливка и белый текст.
private struct ЧипПричины: View {
    let подпись: String
    let выбран: Bool
    let выбрать: () -> Void

    var body: some View {
        Button(action: выбрать) {
            Text(подпись)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(выбран ? Color.white : Theme.текст)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(выбран ? Theme.зелёный : Theme.поверхность, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(выбран ? Theme.зелёный : Theme.линия, lineWidth: 1.5)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// .mk-report-send сайта: #dc2626 в обеих темах.
private enum КраскиЖалобы {
    static let кнопка = Color(uiColor: Theme.hex(0xDC2626))
}
