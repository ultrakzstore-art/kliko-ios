import SwiftUI
import UIKit

/**
 ЛИСТЫ НИЖНЕЙ ПАНЕЛИ ОКНА ОБЪЯВЛЕНИЯ (ultra-site 13.10.2026: «Окно объявления: новая раскладка кнопок», «Аренда, вторая
 часть», «Аренда проще: одна дата и срок»).

 «Связаться с продавцом» (mkContactSheet сайта): чат, WhatsApp, звонок — только каналы, которые продавец открыл (has_phone
 и contact.call / contact.wa). Гостю все строки под замком «Нужна регистрация» и одна «Войти или зарегистрироваться».
 Номер, tel: и wa.me по-прежнему отдаёт только marketplace.php?contact= по нажатию (КонтактыПродавца) — лист лишь выбирает.

 «Арендовать» (mkRentSheet сайта): условия (ставка, залог, мин. срок, комплект) и заявка — одна дата начала и срок
 числом с «−» / «+»; дату конца, сумму и залог показывает расчёт; сообщение — по «Добавить сообщение». Заявка — тот же
 rentals.php?action=request (start_date и end_date), деньги на этом шаге не двигаются. После отправки — «Владелец ответит
 до…» (respond_by) и «Открыть мои аренды». rent_bookable: false или отказ owner_not_bookable — вместо формы «Написать
 владельцу» (чат). Свои листы поверх листа не открываются: что сделать после — говорит панели (ПослеЛистаОкна).
 */
struct ЛистСвязиСПродавцомОкна: View {
    let товар: Listing
    /// Гость — строки под замком и «Войти или зарегистрироваться».
    let гость: Bool
    /// Есть куда написать (нативный чат и продавец).
    let чатЕсть: Bool
    /// Закрыть лист; не nil — что сделать панели после.
    let готово: (ПослеЛистаОкна?) -> Void
    @State private var видно = false

    init(товар: Listing, гость: Bool, чатЕсть: Bool, готово: @escaping (ПослеЛистаОкна?) -> Void) {
        self.товар = товар
        self.гость = гость
        self.чатЕсть = чатЕсть
        self.готово = готово
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                шапка
                    .padding(.bottom, 6)
                if чатЕсть {
                    строка(0, вид: .чат, заголовок: ТекстыДействийОкна.т("ma_cc_chat"),
                           подпись: ТекстыДействийОкна.т("ma_cc_chat_sub"), после: .чат(текст: ""))
                }
                if товар.whatsApp {
                    строка(1, вид: .whatsApp, заголовок: ТекстыДействийОкна.т("ma_cc_wa"),
                           подпись: ТекстыДействийОкна.т("ma_cc_wa_sub"), после: .whatsApp)
                }
                if товар.звонок {
                    строка(2, вид: .звонок, заголовок: ТекстыДействийОкна.т("ma_cc_call"), подпись: подписьЗвонка,
                           после: .звонок)
                }
                if гость {
                    кнопкаВойти
                        .padding(.top, 8)
                }
                Button { готово(nil) } label: {
                    Text(ТекстыДействийОкна.т("ma_cc_close"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .мерятьВысотуЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 560)
        .листПоСодержимому()
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .onAppear { видно = true }
    }

    private var шапка: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 48, height: 48)
                .background(Theme.зелёный.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ТекстыДействийОкна.т("ma_cc_title"))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(товар.продавец.map { $0.isEmpty ? ТекстыДействийОкна.т("ma_cc_sub") : $0 }
                     ?? ТекстыДействийОкна.т("ma_cc_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// «Принимает звонки 09:00–18:00» при расписании; без него — «Номер откроется по нажатию».
    private var подписьЗвонка: String {
        if товар.часыРежим == "range", let часы = товар.текстЧасов {
            return String(format: ТекстыДействийОкна.т("ma_cc_hours"), часы)
        }
        return ТекстыДействийОкна.т("ma_cc_call_sub")
    }

    private func строка(_ номер: Int, вид: СтрокаСвязиОкна.Вид, заголовок: String, подпись: String,
                        после: ПослеЛистаОкна) -> some View {
        СтрокаСвязиОкна(вид: вид, заголовок: заголовок, подпись: подпись, замок: гость) {
            готово(гость ? .вход : после)
        }
        .opacity(видно ? 1 : 0)
        .offset(y: видно ? 0 : 10)
        .animation(ДвижениеСайта.мягко(.spring(response: 0.4, dampingFraction: 0.82).delay(0.05 * Double(номер))),
                   value: видно)
    }

    private var кнопкаВойти: some View {
        Button { готово(.вход) } label: {
            Text(ТекстыДействийОкна.т("ma_cc_login"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// Строка канала связи: круг со знаком канала, заголовок и подпись (гостю — замок «Нужна регистрация»), стрелка.
private struct СтрокаСвязиОкна: View {
    enum Вид { case чат, whatsApp, звонок }

    let вид: Вид
    let заголовок: String
    let подпись: String
    let замок: Bool
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 12) {
                знак
                    .frame(width: 44, height: 44)
                    .background(фон, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    if замок {
                        Label(ТекстыДействийОкна.т("ma_cc_locked"), systemImage: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                    } else {
                        Text(подпись)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: замок ? "lock" : "chevron.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .opacity(замок ? 0.78 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.98))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var знак: some View {
        switch вид {
        case .чат:
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
        case .whatsApp:
            ЗнакWhatsApp()
        case .звонок:
            Image(systemName: "phone.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    private var фон: Color {
        switch вид {
        case .чат: return Theme.зелёный2
        case .whatsApp: return Theme.whatsApp
        case .звонок: return Theme.панельСвязиКонец
        }
    }
}

// MARK: - «Арендовать»

struct ЛистАрендыОкна: View {
    let товар: Listing
    let готово: (ПослеЛистаОкна?) -> Void
    @ObservedObject private var сессия = СессияПриложения.shared
    @State private var начало = Calendar.current.startOfDay(for: Date())
    @State private var срок = 1
    @State private var сообщение = ""
    @State private var сСообщением = false
    @State private var отправляем = false
    /// Сервер ответил owner_not_bookable — как rent_bookable: false.
    @State private var неПринимает = false
    @State private var текстОтказа: String? = nil
    @State private var ошибка: String? = nil
    /// Принятый запрос: номер аренды и respond_by.
    @State private var принят: (номер: String, ответДо: String)? = nil
    @State private var видно = false

    init(товар: Listing, готово: @escaping (ПослеЛистаОкна?) -> Void) {
        self.товар = товар
        self.готово = готово
    }

    private var месяцы: Bool { товар.периодАренды == "month" }
    private var ставка: Double { товар.rentPriceDay ?? 0 }
    private var залог: Double { товар.поляВида.залогАренды ?? 0 }
    private var минимум: Int { max(1, товар.поляВида.минСрокАренды ?? 1) }
    private var максимум: Int { месяцы ? 24 : 365 }
    private var своё: Bool { !сессия.id.isEmpty && сессия.id == товар.продавецID }

    /// Дата конца из срока: сутки или календарные месяцы от даты начала.
    private var конец: Date {
        Calendar.current.date(byAdding: месяцы ? .month : .day, value: срок, to: начало) ?? начало
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                шапка
                    .появлениеЛистаАренды(видно, 0)
                условия
                    .появлениеЛистаАренды(видно, 1)
                низ
                    .появлениеЛистаАренды(видно, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxWidth: 620)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .onAppear {
            if срок < минимум { срок = минимум }
            видно = true
        }
    }

    // MARK: Шапка и условия

    private var шапка: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .shadow(color: Theme.зелёный.opacity(0.35), radius: 8, x: 0, y: 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ТекстыДействийОкна.т("rs_title"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(товар.title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var условия: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                if ставка > 0 {
                    плитка(ListingKindsText.т(месяцы ? "rent_per_month" : "rent_per_day"),
                           БлокАрендыСайта.сумма(ставка) + " ₸")
                }
                if залог > 0 {
                    плитка(ListingKindsText.т("rent_deposit"), БлокАрендыСайта.сумма(залог) + " ₸")
                }
                плитка(ListingKindsText.т("rent_min_term"), единиц(минимум))
            }
            if let комплект = товар.поляВида.комплектАренды {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(ListingKindsText.т("rent_kit") + ":")
                        .foregroundStyle(Theme.текстВторой)
                    Text(комплект)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func плитка(_ подпись: String, _ значение: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(подпись.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(Theme.зелёный2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(значение)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    // MARK: Низ: своё, в чат, вход, верификация, форма, итог

    @ViewBuilder
    private var низ: some View {
        if своё {
            заметка(ТекстыДействийОкна.т("rs_own"), значок: "person.crop.circle")
        } else if let принят {
            итог(принят.ответДо, номер: принят.номер)
        } else if товар.арендаЗаявкой == false || неПринимает {
            VStack(alignment: .leading, spacing: 12) {
                заметка(текстОтказа ?? ТекстыДействийОкна.т("rs_not_bookable"), значок: "bubble.left.and.bubble.right")
                кнопка(ТекстыДействийОкна.т("rs_write_owner"), значок: "bubble.left.fill") {
                    готово(.чат(текст: String(format: ТекстыДействийОкна.т("rs_hello"), товар.title)))
                }
            }
        } else if сессия.вошёл != true {
            VStack(alignment: .leading, spacing: 12) {
                заметка(ТекстыДействийОкна.т("rs_guest"), значок: "person.crop.circle")
                кнопка(ТекстыДействийОкна.т("rs_login"), значок: "person.fill") { готово(.вход) }
            }
        } else if !сессия.продавецПодтверждён {
            VStack(alignment: .leading, spacing: 12) {
                заметка(ТекстыДействийОкна.т("rs_unver"), значок: "checkmark.shield")
                кнопка(ТекстыДействийОкна.т("rs_verify"), значок: "checkmark.shield.fill") { готово(.верификация) }
            }
        } else {
            форма
        }
    }

    private var форма: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .accessibilityHidden(true)
                Text(ТекстыДействийОкна.т("rs_start"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                DatePicker(ТекстыДействийОкна.т("rs_start"), selection: $начало,
                           in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.зелёный2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            выборСрока
            расчёт
            сообщениеВладельцу
            if let ошибка {
                Text(ошибка)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ценаСкидка)
                    .fixedSize(horizontal: false, vertical: true)
            }
            кнопка(ТекстыДействийОкна.т(отправляем ? "rs_sending" : "rs_request"), значок: "paperplane.fill",
                   ждём: отправляем) { отправить() }
            Label(ТекстыДействийОкна.т("rs_free"), systemImage: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
        }
    }

    private var выборСрока: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .accessibilityHidden(true)
            Text(ТекстыДействийОкна.т("rs_term"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
            кнопкаСрока("minus", подпись: ТекстыДействийОкна.т("rs_less"), можно: срок > минимум) {
                срок = max(минимум, срок - 1)
            }
            Text(единиц(срок))
                .font(.system(size: 15, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 72)
                .contentTransition(.numericText())
            кнопкаСрока("plus", подпись: ТекстыДействийОкна.т("rs_more"), можно: срок < максимум) {
                срок = min(максимум, срок + 1)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func кнопкаСрока(_ значок: String, подпись: String, можно: Bool,
                             нажать: @escaping () -> Void) -> some View {
        Button {
            withAnimation(ДвижениеСайта.выбор) { нажать() }
            ОткликСайта.выбор()
        } label: {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(можно ? Theme.зелёный2 : Theme.текстВторой.opacity(0.4))
                .frame(width: 36, height: 36)
                .background(Theme.поверхность, in: Circle())
                .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.9))
        .disabled(!можно)
        .accessibilityLabel(подпись)
    }

    /// Расчёт: «15 окт — 18 окт», «3 суток × 5 000 ₸», залог и итог за срок.
    private var расчёт: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: ТекстыДействийОкна.т("rs_period"), Self.дата(начало), Self.дата(конец)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                Spacer(minLength: 0)
            }
            if ставка > 0 {
                строкаРасчёта(единиц(срок) + " × " + БлокАрендыСайта.сумма(ставка) + " ₸",
                              БлокАрендыСайта.сумма(ставка * Double(срок)) + " ₸")
            }
            if залог > 0 {
                строкаРасчёта(ТекстыДействийОкна.т("rs_deposit"), БлокАрендыСайта.сумма(залог) + " ₸")
            }
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack {
                Text(ТекстыДействийОкна.т("rs_total"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 8)
                Text(БлокАрендыСайта.сумма(ставка * Double(срок) + залог) + " ₸")
                    .font(.system(size: 18, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
                    .contentTransition(.numericText())
            }
        }
        .padding(14)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func строкаРасчёта(_ слева: String, _ справа: String) -> some View {
        HStack(spacing: 10) {
            Text(слева)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(справа)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Theme.текст)
        }
        .font(.system(size: 13))
    }

    @ViewBuilder
    private var сообщениеВладельцу: some View {
        if сСообщением {
            TextField(ТекстыДействийОкна.т("rs_msg_ph"), text: $сообщение, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(2...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .onChange(of: сообщение) { _, стало in
                    if стало.count > 300 { сообщение = String(стало.prefix(300)) }
                }
                .transition(.opacity)
        } else {
            Button {
                withAnimation(ДвижениеСайта.смена) { сСообщением = true }
            } label: {
                Label(ТекстыДействийОкна.т("rs_msg_add"), systemImage: "plus.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Итог

    private func итог(_ ответДо: String, номер: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .symbolEffect(.bounce, value: принят != nil)
                .accessibilityHidden(true)
            Text(ТекстыДействийОкна.т("rs_sent_t"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(подписьИтога(ответДо))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            кнопка(ТекстыДействийОкна.т("rs_my"), значок: "list.bullet.rectangle") { готово(.мояАренда(номер)) }
                .padding(.top, 4)
            Button { готово(nil) } label: {
                Text(ТекстыДействийОкна.т("rs_done"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    /// «Владелец получил уведомление. Владелец ответит до 15:00, 14.10» — срок, если сервер его прислал.
    private func подписьИтога(_ ответДо: String) -> String {
        var строки = [ТекстыДействийОкна.т("rs_sent_s")]
        if let дата = СрокОтветаАренды.дата(ответДо) {
            строки.append(String(format: ТекстыДействийОкна.т("rs_answer_by"), СрокОтветаАренды.текст(дата)))
        }
        строки.append(ТекстыДействийОкна.т("rs_free"))
        return строки.joined(separator: "\n")
    }

    // MARK: Части

    private func заметка(_ текст: String, значок: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay(alignment: .leading) {
            Theme.зелёный2
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func кнопка(_ заголовок: String, значок: String, ждём: Bool = false,
                        нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(spacing: 10) {
                if ждём {
                    SiteSpinner.белый
                } else {
                    Image(systemName: значок)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(заголовок)
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Theme.панельСвязиКонец.opacity(0.35), radius: 10, x: 0, y: 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.97))
        .disabled(ждём)
    }

    /// «3 суток», «2 месяца» — слова мин. срока страницы (rent_min_*).
    private func единиц(_ н: Int) -> String {
        let ключ: String
        if месяцы {
            ключ = н % 10 == 1 && н % 100 != 11 ? "rent_min_m1"
                : ((2...4).contains(н % 10) && !(12...14).contains(н % 100) ? "rent_min_m2" : "rent_min_m5")
        } else {
            ключ = н == 1 ? "rent_min_d1" : (н < 5 ? "rent_min_d2" : "rent_min_d5")
        }
        return String(format: ListingKindsText.т(ключ), н)
    }

    /// «15 окт.» — день и месяц коротко по языку телефона.
    private static func дата(_ дата: Date) -> String {
        дата.formatted(.dateTime.day().month(.abbreviated))
    }

    // MARK: Запрос

    private func отправить() {
        guard !отправляем else { return }
        guard срок >= минимум else {
            ошибка = String(format: ТекстыДействийОкна.т("rs_err_min"), единиц(минимум))
            return
        }
        ошибка = nil
        отправляем = true
        let текст = сСообщением ? сообщение.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let номер = товар.id
        let с = начало
        let по = конец
        Task { @MainActor in
            let итог = await АрендаОбъявленияAPI.запросить(объявление: номер, начало: с, конец: по, сообщение: текст)
            отправляем = false
            switch итог {
            case .готово(let аренда, let ответДо):
                ОткликСайта.успех()
                withAnimation(ДвижениеСайта.смена) { принят = (номер: аренда, ответДо: ответДо) }
            case .владелецНеПринимает(let текстСервера):
                текстОтказа = текстСервера
                withAnimation(ДвижениеСайта.смена) { неПринимает = true }
            case .ошибка(let текстОшибки):
                ошибка = текстОшибки ?? ТекстыДействийОкна.т("rs_err")
            case .нетСессии:
                готово(.вход)
            case .сеть:
                ошибка = ТекстыДействийОкна.т("rs_no_conn")
            }
        }
    }
}

private extension View {
    /// Каскад листа аренды: блок n встаёт снизу через 0,06 с после предыдущего; без движения — сразу.
    func появлениеЛистаАренды(_ видно: Bool, _ номер: Int) -> some View {
        self
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 12)
            .animation(ДвижениеСайта.мягко(.spring(response: 0.45, dampingFraction: 0.84).delay(0.06 * Double(номер))),
                       value: видно)
    }
}
