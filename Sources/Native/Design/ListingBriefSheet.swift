import SwiftUI
import UIKit

/**
 ЛИСТ «РАЗБОР ОБЪЯВЛЕНИЯ» — слайды сайта («Главное / Цена», «Что это за вещь», «Что проверить», «Продавец», «Как купить
 безопасно») одним листом сверху вниз, с мощной, но лёгкой подачей: блоки встают снизу каскадом, метка этой цены
 доезжает по шкале рынка, доводы ИИ появляются пункт за пунктом. «Уменьшение движения» — всё сразу, без полёта.

 Данные — из уже отданной карточки и api/brief.php (МодельРазбораОбъявления); доводы Kliko AI — по нажатию «Разобрать с
 ИИ». Кнопки внизу жмут кнопки самого окна (главная и «Связаться»), «Что спросить продавца» — вопрос в строку ввода чата:
 новых путей к оплате нет.
 */
struct ЛистРазбораОбъявления: View {
    let товар: Listing
    @ObservedObject private var модель: МодельРазбораОбъявления
    /// Закрыть лист; не nil — что сделать окну после.
    let готово: (ПослеРазбора?) -> Void
    @State private var видно = false

    init(товар: Listing, модель: МодельРазбораОбъявления, готово: @escaping (ПослеРазбора?) -> Void) {
        self.товар = товар
        _модель = ObservedObject(wrappedValue: модель)
        self.готово = готово
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                шапка
                    .появлениеРазбора(видно, 0)
                РазделРазбора(значок: "chart.bar.xaxis", заголовок: ТекстыРазбора.т("br_price")) {
                    блокРынка
                }
                .появлениеРазбора(видно, 1)
                if !модель.доводыВыключены {
                    РазделРазбора(значок: "sparkles", заголовок: ТекстыРазбора.т("br_ai")) {
                        блокДоводов
                    }
                    .появлениеРазбора(видно, 2)
                }
                if let совет = товар.ключСовета {
                    РазделРазбора(значок: "checklist", заголовок: ТекстыРазбора.т("br_check")) {
                        СписокСовета(ключ: совет)
                    }
                    .появлениеРазбора(видно, 3)
                }
                if товар.продавец != nil {
                    РазделРазбора(значок: "person.crop.circle.badge.checkmark", заголовок: ТекстыРазбора.т("br_seller")) {
                        блокПродавца
                    }
                    .появлениеРазбора(видно, 4)
                }
                РазделРазбора(значок: "checkmark.shield", заголовок: ТекстыРазбора.т("br_safe")) {
                    блокБезопасно
                }
                .появлениеРазбора(видно, 5)
                Button { готово(nil) } label: {
                    Text(ТекстыРазбора.т("br_close"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .мерятьВысотуЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 680)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоСодержимому()
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.фонСтраницы)
        .onAppear { видно = true }
    }

    // MARK: Шапка

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .symbolEffect(.bounce, value: видно)
                    .accessibilityHidden(true)
                Text(ТекстыРазбора.т("br_title"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button { готово(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.18), in: Circle())
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеСПружинкой(сжатие: 0.9))
                .accessibilityLabel(ТекстыРазбора.т("br_close"))
            }
            Text(товар.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let метка = ЧипРынкаОбъявления.текст(чип: модель.чип, разница: модель.рынок?.разница) {
                    Text(метка)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.панельСвязиКонец)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.92), in: Capsule())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .shadow(color: Theme.панельСвязиКонец.opacity(0.35), radius: 14, x: 0, y: 8)
    }

    // MARK: Цена по рынку

    @ViewBuilder
    private var блокРынка: some View {
        if let рынок = модель.рынок {
            VStack(alignment: .leading, spacing: 12) {
                ШкалаРынкаРазбора(рынок: рынок, цена: (товар.price ?? 0) > 0 ? товар.price : nil)
                Text(подписьРынка(рынок))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(ТекстыРазбора.т("br_m_none"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// «Похожих объявлений на площадке: 12» (рынок — «предложений на рынке», квартиры — «квартир» и цена за м²).
    private func подписьРынка(_ р: РынокРазбора) -> String {
        var части: [String] = []
        if р.заМетр {
            части.append(String(format: ТекстыРазбора.т("br_m_n_flat"), р.похожих))
            if let заМетр = р.серединаЗаМетр, заМетр > 0 {
                части.append(String(format: ТекстыРазбора.т("br_m_mid_m2"), ListingCard.тенге(заМетр)))
            }
            if let площадь = р.площадь, площадь > 0 {
                let число = площадь == площадь.rounded() ? String(Int(площадь)) : String(format: "%.1f", площадь)
                части.append(String(format: ТекстыРазбора.т("br_m_area"), число))
            }
        } else {
            части.append(String(format: ТекстыРазбора.т(р.внешний ? "br_m_n_mkt" : "br_m_n"), р.похожих))
        }
        return части.joined(separator: " · ")
    }

    // MARK: Доводы ИИ

    @ViewBuilder
    private var блокДоводов: some View {
        switch модель.доводы {
        case .нет:
            VStack(alignment: .leading, spacing: 12) {
                Text(ТекстыРазбора.т("br_ai_sub"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                кнопкаИИ(ТекстыРазбора.т("br_ai_go"))
            }
        case .грузим:
            ЗаготовкаДоводов()
        case .готово(let доводы):
            СписокДоводовРазбора(доводы: доводы) { вопрос in готово(.вопрос(вопрос)) }
        case .вход:
            VStack(alignment: .leading, spacing: 12) {
                Text(ТекстыРазбора.т("br_ai_login"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                кнопкаЗелёная(ТекстыРазбора.т("br_login"), значок: "person.fill") { готово(.вход) }
            }
        case .отказ(let текст):
            VStack(alignment: .leading, spacing: 12) {
                Label(текст, systemImage: "exclamationmark.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                кнопкаИИ(ТекстыРазбора.т("br_retry"))
            }
        }
    }

    private func кнопкаИИ(_ заголовок: String) -> some View {
        кнопкаЗелёная(заголовок, значок: "sparkles") { модель.попроситьДоводы() }
    }

    private func кнопкаЗелёная(_ заголовок: String, значок: String, нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.system(size: 15, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.97))
    }

    // MARK: Продавец

    private var блокПродавца: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(товар.продавец ?? "")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                if товар.продавецПроверен {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.проверен)
                        .accessibilityHidden(true)
                }
            }
            ForEach(строкиПродавца, id: \.self) { строка in
                Label(строка.текст, systemImage: строка.значок)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .accessibilityElement(children: .combine)
    }

    fileprivate struct СтрокаПродавца: Hashable {
        let текст: String
        let значок: String
    }

    /// «Проверен через eGov» или «Новый продавец», оценка и отзывы, сделки, «с 2024 г.» — только то, что пришло.
    private var строкиПродавца: [СтрокаПродавца] {
        var строки: [СтрокаПродавца] = []
        строки.append(СтрокаПродавца(текст: ListingPageText.т(товар.продавецПроверен ? "verified" : "new_seller"),
                                     значок: товар.продавецПроверен ? "checkmark.shield" : "person"))
        if let оценка = товар.рейтингПродавца {
            var текст = "★ " + String(format: "%.1f", оценка).replacingOccurrences(of: ".", with: ",")
            if let отзывы = товар.отзывыПродавца { текст += " · " + ListingPageText.число(отзывы, "reviews") }
            строки.append(СтрокаПродавца(текст: текст, значок: "star"))
        }
        if let сделки = товар.сделкиПродавца {
            строки.append(СтрокаПродавца(текст: ListingPageText.число(сделки, "deals"), значок: "bag"))
        }
        if let с = товар.продавецС {
            строки.append(СтрокаПродавца(текст: String(format: ListingPageText.т("since"), с), значок: "calendar"))
        }
        return строки
    }

    // MARK: Как купить безопасно

    private var главное: ГлавноеДействиеОкна {
        ГлавноеДействиеОкна.для(товар, eds: РежимСделокСайта.edsСейчас)
    }

    private var своё: Bool {
        let мой = СессияПриложения.shared.id
        return !мой.isEmpty && мой == товар.продавецID
    }

    /// Сделка через гаранта у этого объявления есть и гарант работает по сверке — обещание «деньги у Kliko» честное.
    private var сделкаЕсть: Bool {
        switch главное {
        case .купить, .задаток, .заказать:
            return ПаузаГаранта.работаетПоСверке
        case .аренда, .подписьEDS, .связаться:
            return false
        }
    }

    /// Товар — «деньги у Kliko до получения, затем срок проверки» (как fz_m сделки); услуга — оплата после приёмки;
    /// задаток — бронь через сделку; без сделки — договориться в чате и осмотреть до оплаты.
    private var текстБезопасно: String {
        guard сделкаЕсть else { return ТекстыРазбора.т("br_safe_chat") }
        switch главное {
        case .заказать: return ListingPageText.т("t_guarantor_d")
        case .задаток: return ТекстыРазбора.т("br_safe_deposit")
        case .купить, .аренда, .подписьEDS, .связаться: return ListingPageText.т("cov_w2_d")
        }
    }

    private var блокБезопасно: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(текстБезопасно)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            if !своё {
                if главное != .связаться {
                    кнопкаЗелёная(главное.заголовок, значок: главное.значок) { готово(.главное) }
                }
                Button { готово(.связаться) } label: {
                    Text(ТекстыДействийОкна.т("ma_contact"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеСПружинкой(сжатие: 0.97))
            }
        }
    }
}

// MARK: - Раздел листа

/// Карточка раздела: значок в мятном квадрате и заголовок, под ними содержимое; поверхность со скруглением.
private struct РазделРазбора<Содержимое: View>: View {
    let значок: String
    let заголовок: String
    let содержимое: Содержимое

    init(значок: String, заголовок: String, @ViewBuilder содержимое: () -> Содержимое) {
        self.значок = значок
        self.заголовок = заголовок
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 30, height: 30)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            содержимое
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

// MARK: - Шкала рынка

/**
 Шкала цен похожих: от «дешевле» к «дороже», черта середины и метка этой цены — она доезжает на своё место по
 появлении. Числа — слева направо при любом языке (шкала денег, как на сайте).
 */
private struct ШкалаРынкаРазбора: View {
    let рынок: РынокРазбора
    let цена: Double?
    @State private var готово = false

    /// Явный init: private @State прячет готовый.
    init(рынок: РынокРазбора, цена: Double?) {
        self.рынок = рынок
        self.цена = цена
    }

    private func доля(_ значение: Double) -> CGFloat {
        let ширина = рынок.максимум - рынок.минимум
        guard ширина > 0 else { return 0.5 }
        return CGFloat(min(1, max(0, (значение - рынок.минимум) / ширина)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { г in
                let ширина = г.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.золото, Theme.оранжевый],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 8)
                        .opacity(0.85)
                    Capsule()
                        .fill(Theme.текст.opacity(0.55))
                        .frame(width: 2, height: 18)
                        .offset(x: доля(рынок.середина) * ширина - 1)
                    if let цена {
                        Circle()
                            .fill(Theme.поверхность)
                            .overlay { Circle().strokeBorder(Theme.зелёный, lineWidth: 4) }
                            .frame(width: 20, height: 20)
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            .offset(x: (готово ? доля(цена) : 0) * (ширина - 20))
                    }
                }
                .frame(width: ширина, height: 24)
            }
            .frame(height: 24)
            HStack {
                Text(ListingCard.тенге(рынок.минимум))
                Spacer(minLength: 8)
                Text(ListingCard.тенге(рынок.максимум))
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.текстВторой)
            VStack(alignment: .leading, spacing: 4) {
                if let цена {
                    легенда(цвет: Theme.зелёный, текст: ТекстыРазбора.т("br_this"), сумма: цена)
                }
                легенда(цвет: Theme.текст.opacity(0.55), текст: ТекстыРазбора.т("br_mid"), сумма: рынок.середина)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.9, dampingFraction: 0.72).delay(0.35))) { готово = true }
        }
        .accessibilityElement(children: .combine)
    }

    private func легенда(цвет: Color, текст: String, сумма: Double) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(цвет)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(текст)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(ListingCard.тенге(сумма))
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Доводы ИИ

/// Пока ИИ думает: мерцающие строки и подпись «ИИ читает объявление…» с пульсирующей искрой.
private struct ЗаготовкаДоводов: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .symbolEffect(.pulse, options: .repeating, isActive: !ДвижениеСайта.тихо)
                    .accessibilityHidden(true)
                Text(ТекстыРазбора.т("br_ai_wait"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(0..<4, id: \.self) { номер in
                МерцаниеСайта(радиус: Theme.Радиус.xxs)
                    .frame(height: 14)
                    .padding(.trailing, CGFloat(номер % 2) * 48)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Доводы: «Что говорит за», «На что посмотреть», «Что спросить продавца» (нажатие — вопрос в чат) и «Итог» —
/// пункт за пунктом, каскадом.
private struct СписокДоводовРазбора: View {
    let доводы: ДоводыРазбора
    let спросить: (String) -> Void
    @State private var видно = false

    /// Явный init: private @State прячет готовый.
    init(доводы: ДоводыРазбора, спросить: @escaping (String) -> Void) {
        self.доводы = доводы
        self.спросить = спросить
    }

    fileprivate struct Пункт: Identifiable {
        let id: Int
        let вид: Вид
        let текст: String
    }

    fileprivate enum Вид {
        case плюс, минус, вопрос
    }

    /// Все пункты по порядку групп — номер для задержки каскада.
    private var пункты: [Пункт] {
        var итог: [Пункт] = []
        for текст in доводы.плюсы { итог.append(Пункт(id: итог.count, вид: .плюс, текст: текст)) }
        for текст in доводы.минусы { итог.append(Пункт(id: итог.count, вид: .минус, текст: текст)) }
        for текст in доводы.вопросы { итог.append(Пункт(id: итог.count, вид: .вопрос, текст: текст)) }
        return итог
    }

    var body: some View {
        let все = пункты
        VStack(alignment: .leading, spacing: 14) {
            группа(ТекстыРазбора.т("br_pros"), все.filter { $0.вид == .плюс })
            группа(ТекстыРазбора.т("br_cons"), все.filter { $0.вид == .минус })
            группа(ТекстыРазбора.т("br_ask"), все.filter { $0.вид == .вопрос })
            if !доводы.вывод.isEmpty {
                вывод
                    .появлениеРазбора(видно, все.count)
            }
            МеткаСвоегоИИ(видна: доводы.своимИИ)
            Text(ТекстыРазбора.т("br_ai_note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { видно = true }
    }

    @ViewBuilder
    private func группа(_ заголовок: String, _ пункты: [Пункт]) -> some View {
        if !пункты.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(заголовок.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityAddTraits(.isHeader)
                ForEach(пункты) { пункт in
                    строка(пункт)
                        .появлениеРазбора(видно, пункт.id)
                }
            }
        }
    }

    @ViewBuilder
    private func строка(_ пункт: Пункт) -> some View {
        switch пункт.вид {
        case .плюс:
            ПунктДоводаРазбора(значок: "checkmark.circle.fill", цвет: Theme.зелёный2, текст: пункт.текст)
        case .минус:
            ПунктДоводаРазбора(значок: "exclamationmark.triangle.fill", цвет: Theme.оранжевый, текст: пункт.текст)
        case .вопрос:
            Button { спросить(пункт.текст) } label: {
                HStack(alignment: .top, spacing: 10) {
                    ПунктДоводаРазбора(значок: "questionmark.bubble.fill", цвет: Theme.проверен, текст: пункт.текст)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.проверен)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }
                .padding(10)
                .background(Theme.проверен.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеСПружинкой(сжатие: 0.98))
            .accessibilityHint(ТекстыРазбора.т("br_ask_hint"))
        }
    }

    private var вывод: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.зелёный2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ТекстыРазбора.т("br_verdict").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.зелёный2)
                Text(доводы.вывод)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.оттенокАкцента, Theme.поверхность2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.зелёный2.opacity(0.25), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Пункт довода: значок цвета группы и текст.
private struct ПунктДоводаРазбора: View {
    let значок: String
    let цвет: Color
    let текст: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(цвет)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private extension View {
    /// Каскад листа разбора: блок n встаёт снизу через 0,07 с после предыдущего; без движения — сразу.
    func появлениеРазбора(_ видно: Bool, _ номер: Int) -> some View {
        self
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 14)
            .animation(ДвижениеСайта.мягко(.spring(response: 0.5, dampingFraction: 0.84)
                                            .delay(0.07 * Double(min(номер, 10)))),
                       value: видно)
    }
}
