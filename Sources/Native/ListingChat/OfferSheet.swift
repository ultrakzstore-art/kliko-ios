import Foundation
import SwiftUI

/**
 ОКНО «ПРЕДЛОЖИТЬ ЦЕНУ» — ЭТАП 38 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Как #mk-offer-sheet страницы объявления сайта (mkOfferOpen, _mkOfferSync, mkOfferSlide, mkOfferAmt в
 js/marketplace.min.js; .mk-offer-* и .mk-od-* в css/marketplace.min.css): лист снизу с полоской, «×» в круге --mk-surf2,
 заголовок, пилюля «Цена продавца: <b>…</b>», пояснение, круг выбора .mk-offer-dial — «Ваша цена» и «−N%», ползунок
 0…35 % (MK_OFFER_MAX_PCT), шкала «0%» / «−35%», подсказка, пока ничего не выбрано, сумма и «экономия …»; ниже «Или своя
 сумма» с полем «₸» (ползунок встаёт по ней, а движение ползунка стирает её, как у сайта); своя сумма выше цены или
 скидка больше 35 % — пояснение сайта, и отправить нельзя. «Чем подкрепить просьбу» — только «Заберу сам» («Заберу или
 оплачу доставку сам» при бесплатной доставке): «Подкреплю деньгами» замораживает деньги — это на сайте. Кнопка
 «Отправить предложение» краснеет со скидкой — цвет _mkOfferColor: зелёный → золото → красный.

 Способ оплаты не спрашиваем: рассрочка и кредит у сайта считаются по условиям объявления (payment), которых у приложения
 нет, — уходит «cash», выбранный сайтом по умолчанию. Окно закрывается сразу, как mkOfferClose() до запроса; отправляет
 МодельЧатаОбъявления.

 Своё предложение уже ждёт ответа (TestFlight, владелец 26.09.2026: «отозвать предложение нет») — над ползунком строка
 «Ваше предложение · N ₸ · Ждём ответа продавца» и «Отозвать предложение»: окно подтверждения и запрос — у чата
 (ЭкранЧатаОбъявления), лист только закрывается. Новое предложение и так заменит прежнее («Заменено новым предложением»).
 */
struct ЛистПредложенияЦены: View {
    let товар: Listing
    /// Цена, процент для текста («(-N%)» — только если выбран ползунком) и «Заберу сам».
    let отправить: (Int, Int, Bool) -> Void
    /// Своё предложение, которое ещё ждёт ответа продавца; nil — строки нет.
    let ждущее: ЖдущееПредложениеЦены?
    /// «Отозвать предложение» у строки ждущего; nil — кнопки нет.
    let отозвать: (() -> Void)?
    @State private var процент: Double = 0
    @State private var своя = ""
    @State private var забрать = false
    @FocusState private var вПоле: Bool
    @Environment(\.dismiss) private var закрыть

    init(товар: Listing, ждущее: ЖдущееПредложениеЦены? = nil, отозвать: (() -> Void)? = nil,
         отправить: @escaping (Int, Int, Bool) -> Void) {
        self.товар = товар
        self.ждущее = ждущее
        self.отозвать = отозвать
        self.отправить = отправить
    }

    /// MK_OFFER_MAX_PCT сайта: больше 35 % скидки предложить нельзя.
    static let предел = 35

    // MARK: - Расчёт (_mkOfferPrice, _mkOfferOut, _mkOfferSync)

    private var база: Int { Int((товар.price ?? 0).rounded()) }

    /// Своя сумма из поля: только цифры (и арабские тоже — wholeNumberValue), не больше триллиона.
    private var свояСумма: Int {
        var n = 0
        for знак in своя {
            guard let цифра = знак.wholeNumberValue, цифра < 10 else { continue }
            n = n * 10 + цифра
            if n > 1_000_000_000_000 { return 1_000_000_000_000 }
        }
        return n
    }

    private var ползунок: Int { Int(процент.rounded()) }

    private var цена: Int {
        if свояСумма > 0 { return свояСумма }
        guard база > 0 else { return 0 }
        return Int((Double(база) * (1 - Double(ползунок) / 100)).rounded())
    }

    /// _mkOfferOut: своя сумма выше цены продавца или ниже её на больше чем 35 %.
    private var вне: Bool {
        guard база > 0, свояСумма > 0 else { return false }
        let нижняя = Int((Double(база) * (1 - Double(Self.предел) / 100)).rounded(.up))
        return свояСумма > база || свояСумма < нижняя
    }

    /// Скидка на экране: −N % от цены продавца.
    private var скидка: Int {
        guard база > 0, цена > 0 else { return 0 }
        return max(0, Int((100 * (1 - Double(цена) / Double(база))).rounded()))
    }

    private var изменено: Bool { свояСумма > 0 || ползунок > 0 }
    private var можно: Bool { цена > 0 && !вне }

    /// Ползунок, двинутый рукой, стирает свою сумму (mkOfferSlide); своя сумма ставит ползунок, не стирая себя.
    private var привязкаПолзунка: Binding<Double> {
        Binding(get: { процент }, set: { новое in
            процент = новое
            if !своя.isEmpty { своя = "" }
        })
    }

    // MARK: - Вид

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                if let ждущее, let отозвать {
                    СтрокаЖдущегоПредложения(ждущее: ждущее, отозвать: отозвать)
                        .padding(.top, 10)
                }
                if база > 0 {
                    ценаПродавца
                        .padding(.top, 10)
                }
                Text(ListingChatText.т("offer_sub"))
                    .font(.system(size: 13))
                    .lineSpacing(6.5)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                круг
                    .padding(.top, 16)
                свояСтрока
                    .padding(.top, 12)
                if вне {
                    Text(пояснениеВне)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.малиновый)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                доводы
                    .padding(.top, 16)
                кнопка
                    .padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        .листПоВысоте()
        .onChange(of: своя) { _, _ in
            /* mkOfferAmt: своя сумма двигает ползунок — на сколько процентов она ниже цены продавца (0…35). */
            let сумма = свояСумма
            guard сумма > 0, база > 0 else { return }
            let доля = Int((100 * (1 - Double(сумма) / Double(база))).rounded())
            процент = Double(max(0, min(Self.предел, доля)))
        }
    }

    /// Заголовок и «×» (.mk-offer-h, .mk-offer-close).
    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(ListingPageText.т("offer"))
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.19)
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
            .padding(.top, -8)
            .padding(.trailing, -8)
            .accessibilityLabel(ListingChatText.т("close"))
        }
    }

    /// .mk-offer-cur: серая пилюля «Цена продавца: <b>…</b>».
    private var ценаПродавца: some View {
        HStack(spacing: 6) {
            Text(ListingChatText.т("offer_seller_price"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            Text(ListingCard.тенге(Double(база)))
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.поверхность2, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// .mk-offer-dial: «Ваша цена», «−N%», ползунок, шкала, подсказка, сумма и экономия.
    private var круг: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ListingChatText.т("offer_dial"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                /* .mk-od-pct: белым на пилюле цвета скидки. Строкой, а не ключом перевода: «%» в ключе SwiftUI понял
                   бы как формат. */
                Text(verbatim: "−" + String(скидка) + "%")
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(цветСкидки, in: Capsule())
            }
            ПолосаСкидкиПредложения(значение: привязкаПолзунка, предел: Double(Self.предел), цвет: цветСкидки)
                .disabled(база <= 0)
                .accessibilityLabel(ListingChatText.т("offer_dial"))
                .accessibilityValue("−" + String(скидка) + "%, " + (цена > 0 ? ListingCard.тенге(Double(цена)) : "—"))
            HStack {
                Text(verbatim: "0%")
                Spacer(minLength: 8)
                Text(verbatim: "−" + String(Self.предел) + "%")
            }
            .font(.system(size: 11))
            .environment(\.layoutDirection, .leftToRight)
            .foregroundStyle(Theme.текстВторой)
            .accessibilityHidden(true)
            if !изменено {
                Text(ListingChatText.т("offer_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(цена > 0 ? ListingCard.тенге(Double(цена)) : "—")
                    .font(.system(size: 19, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if цена > 0 && база > цена {
                    Text(String(format: ListingChatText.т("offer_save"), ListingCard.тенге(Double(база - цена))))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(14)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.зелёный.opacity(0.26), lineWidth: 1.5)
        }
    }

    /// .mk-offer-own: «Или своя сумма» и поле с «₸».
    private var свояСтрока: some View {
        HStack(spacing: 12) {
            Text(ListingChatText.т("offer_own"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                TextField(база > 0 ? String(база) : "", text: $своя)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .frame(width: 120)
                    .focused($вПоле)
                    .accessibilityLabel(ListingChatText.т("offer_own"))
                Text(verbatim: "₸")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(вПоле ? Theme.зелёный2 : Color.clear, lineWidth: 2)
            }
        }
    }

    private var пояснениеВне: String {
        if свояСумма > база { return ListingChatText.т("offer_over") }
        return ListingChatText.т("offer_under").replacingOccurrences(of: "{n}", with: String(Self.предел))
    }

    /// .mk-offer-args: «Чем подкрепить просьбу» и переключатель «Заберу сам».
    private var доводы: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
            Text(ListingChatText.т("offer_args"))
                .font(.system(size: 13, weight: .bold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(Theme.текстВторой)
                .padding(.top, 14)
            Toggle(isOn: $забрать) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ListingChatText.т(товар.доставкаБесплатно ? "arg_take_both" : "arg_pickup"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(забрать ? Theme.текст : Theme.текстВторой)
                    Text(ListingChatText.т("arg_pickup_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.зелёный2)
            .padding(.vertical, 12)
        }
    }

    /// .mk-offer-send: на всю ширину, градиент цвета скидки, самолётик.
    private var кнопка: some View {
        Button {
            guard можно else { return }
            let итоговая = цена
            let вТексте = свояСумма == 0 && ползунок > 0 ? ползунок : 0
            let сам = забрать
            закрыть()
            отправить(итоговая, вТексте, сам)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "paperplane")
                    .font(.system(size: 18, weight: .semibold))
                    .accessibilityHidden(true)
                Text(ListingChatText.т("offer_send"))
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(
                LinearGradient(colors: [цветСкидки, тёмныйЦветСкидки], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            /* box-shadow 0 8px 20px -10px цветом скидки. */
            .shadow(color: цветСкидки.opacity(можно ? 0.5 : 0), radius: 10, x: 0, y: 8)
            .opacity(можно ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!можно)
    }

    // MARK: - Цвет скидки (_mkOfferColor)

    private var цветСкидки: Color { Self.цвет(скидка, доля: 1) }
    private var тёмныйЦветСкидки: Color { Self.цвет(скидка, доля: 0.78) }

    /// Зелёный rgb(29,125,74) → золото rgb(191,146,42) → красный rgb(192,57,43) по (скидка / 35)^1,6, как у сайта;
    /// доля < 1 — тот же цвет темнее (color-mix с чёрным у второй точки градиента кнопки).
    static func цвет(_ скидка: Int, доля: Double) -> Color {
        let e = pow(max(0, min(1, Double(скидка) / Double(предел))), 1.6)
        let зелёный: [Double] = [29, 125, 74]
        let золото: [Double] = [191, 146, 42]
        let красный: [Double] = [192, 57, 43]
        let от: [Double]
        let до: [Double]
        let t: Double
        if e < 0.5 {
            от = зелёный
            до = золото
            t = e / 0.5
        } else {
            от = золото
            до = красный
            t = (e - 0.5) / 0.5
        }
        let r = (от[0] + (до[0] - от[0]) * t) * доля / 255
        let g = (от[1] + (до[1] - от[1]) * t) * доля / 255
        let b = (от[2] + (до[2] - от[2]) * t) * доля / 255
        return Color(red: r, green: g, blue: b)
    }
}

/// Строка своего ждущего предложения в окне «Предложить цену»: сумма, «Ждём ответа продавца» (или «Подкреплено · …»)
/// и «Отозвать предложение» (.mk-ofc-x). Светлая и тёмная — краски Theme.
private struct СтрокаЖдущегоПредложения: View {
    let ждущее: ЖдущееПредложениеЦены
    let отозвать: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ТекстыОтзываПредложения.т("mine") + " · " + ListingCard.тенге(Double(ждущее.цена)))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.текст)
            Text(ждущее.подкреплено > 0
                 ? ТекстыОтзываПредложения.т("held") + " · " + ListingCard.тенге(Double(ждущее.подкреплено))
                 : ТекстыОтзываПредложения.т("wait"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            КнопкаОтозватьПредложение(занято: false, нажать: отозвать)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// Ползунок скидки .mk-od-range: дорожка 6 градиентом зелёный → золото → красный, белый бегунок 22 с кромкой 2,5 цвета
/// скидки и тенью. Двигается пальцем (шаг 1 %), VoiceOver — «больше / меньше». Бегунок у 0 — слева.
struct ПолосаСкидкиПредложения: View {
    @Binding var значение: Double
    let предел: Double
    let цвет: Color
    @Environment(\.isEnabled) private var доступна

    private static let бегунок: CGFloat = 22

    var body: some View {
        GeometryReader { мерка in
            let ширина = max(1, мерка.size.width - Self.бегунок)
            let доля = CGFloat(max(0, min(предел, значение)) / max(предел, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(uiColor: Theme.hex(0x1D7D4A)), Color(uiColor: Theme.hex(0xBF922A)),
                                                  Color(uiColor: Theme.hex(0xC0392B))],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .padding(.horizontal, Self.бегунок / 2)
                Circle()
                    .fill(Color.white)
                    .overlay { Circle().strokeBorder(цвет, lineWidth: 2.5) }
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    .frame(width: Self.бегунок, height: Self.бегунок)
                    .offset(x: ширина * доля)
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { жест in
                        guard доступна else { return }
                        let x = жест.location.x - Self.бегунок / 2
                        let новое = (Double(max(0, min(ширина, x)) / ширина) * предел).rounded()
                        if новое != значение { значение = новое }
                    }
            )
        }
        .frame(height: 30)
        /* Шкала «0% … −35%» и градиент — слева направо и в арабском, как у поля range сайта с его подписями. */
        .environment(\.layoutDirection, .leftToRight)
        .opacity(доступна ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityAdjustableAction { куда in
            guard доступна else { return }
            switch куда {
            case .increment: значение = min(предел, значение + 1)
            case .decrement: значение = max(0, значение - 1)
            @unknown default: break
            }
        }
    }
}
