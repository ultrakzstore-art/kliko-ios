import SwiftUI
import UIKit

/**
 «МОИ СДЕЛКИ» — ЭКРАН СПИСКА, ЭТАП 43 (владелец 26.09.2026: «всё одно и то же, просто код разный»; Config.нативныеСделки).

 Экран сделок сайта (#deals-screen, карта §4.2) сверху вниз: подзаголовок «Гарант-сервис · деньги защищены платформой»,
 вкладки «Я продавец» / «Я покупатель», карточки сделок (картинка, название, «номер · дата · роль · имя», плашка статуса,
 строка денег, таймер авто-подтверждения, подсказка по статусу). Нажатие — карточка сделки (ЭкранСделки) в том же стеке.
 Вход — строка «Мои сделки» во вкладке «Кабинет» и ссылки ?go=deals, ?s=deals, ?deal=<id>.
 Сделки с подписью eGov без гаранта — блок «Сделки с подписью eGov» над сделками гаранта (edsListInject сайта,
 СекцияСделокEDS) по выбранной вкладке; нажатие — своё окно сделки (ЭкранСделкиEDS) листом.
 */
struct МоиСделкиЭкран: View {
    @ObservedObject private var модель = СделкиМодель.shared
    let открыть: (URL) -> Void

    @State private var входОткрыт = false
    /// showDeals сайта — один раз на открытие экрана: возврат из карточки сделки вкладку не сбрасывает (список
    /// перечитывает сама карточка, уходя, — как closeDealModal).
    @State private var показан = false
    /// Открытая сделка с подписью eGov (edsOpen) — лист поверх списка.
    @State private var сделкаEDS: ОткрытаяСделкаEDS? = nil
    /// «Подарки мне» (DealGifts.swift): сделки, где вошедший — получатель подарка; пусто — раздела нет.
    @StateObject private var подарки = ПодаркиМнеМодель()

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: т("deals_title")))
            .task {
                guard !показан else { return }
                показан = true
                await модель.открыт()
                await подарки.загрузить()
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task {
                        await модель.загрузить()
                        await подарки.загрузить()
                    }
                })
            }
            /* Этап 44: ?start_deal=, ?start_service=, ?meet=, ?parcel= — окна создания и кода (Config.деньгиСделок). */
            .modifier(СлойЗаданийСделок(открыть: открыть))
            /* Сделка с подписью eGov из блока над списком — своё окно (edsOpen), не страница кабинета. */
            .sheet(item: $сделкаEDS) { открытая in
                ЭкранСделкиEDS(id: открытая.id, закрыть: { сделкаEDS = nil })
            }
            /* edsClose → loadDeals(role): окно сделки eGov закрыли — оба списка вкладки заново. */
            .onReceive(NotificationCenter.default.publisher(for: .klikoСделкаEDSЗакрыта)) { _ in
                Task {
                    await модель.загрузить()
                    await СписокСделокEDS.shared.загрузить(модель.роль)
                }
            }
            .onChange(of: модель.загрузка) { _, новая in
                if новая == .нуженВход {
                    СписокСделокEDS.shared.забыть()
                    подарки.стереть()
                }
            }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.загрузка {
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        default:
            список
        }
    }

    private var список: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(т("deals_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.bottom, 2)
                /* Подарки, отправленные вошедшему, — над вкладками: они не «продавец» и не «покупатель». */
                СекцияПодарковМне(модель: подарки)
                ВкладкиСделок(выбрана: модель.роль, выбрать: { модель.выбрать($0) })
                    .padding(.bottom, 2)
                    /* edsListInject(role): сделки с подписью eGov выбранной вкладки. */
                    .task(id: модель.роль) { await СписокСделокEDS.shared.загрузить(модель.роль) }
                /* Незакрытые сверху: сделки с подписью eGov в работе, затем свои (незакрытые уже первыми),
                   а закончившиеся сделки eGov — в самом конце. */
                СекцияСделокEDS(роль: модель.роль, открыть: { сделкаEDS = ОткрытаяСделкаEDS(id: $0) })
                /* Скорость: список с диска, а связи нет — плашка над ним. */
                if модель.сКопии && модель.загрузка == .готово { ПлашкаСохранённогоСписка() }
                строки
                СекцияСделокEDS(роль: модель.роль, закрытые: true, открыть: { сделкаEDS = ОткрытаяСделкаEDS(id: $0) })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .refreshable {
            await модель.загрузить()
            await СписокСделокEDS.shared.загрузить(модель.роль)
            await подарки.загрузить()
        }
    }

    @ViewBuilder
    private var строки: some View {
        switch модель.загрузка {
        case .ошибка(let текст):
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                       действие: { Task { await модель.загрузить() } })
                .padding(.top, 24)
        case .нет, .идёт:
            if модель.сделки.isEmpty {
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                карточки
            }
        case .готово, .нуженВход:
            if модель.сделки.isEmpty { пусто } else { карточки }
        }
    }

    private var карточки: some View {
        ForEach(модель.сделки) { с in
            NavigationLink(value: КабинетЦель.сделка(с.id)) {
                КарточкаВСпискеСделок(сделка: с)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        }
    }

    /// Пустой список (loadDeals): продавцу «Сделок от покупателей пока нет», покупателю — ещё подсказка «Купить безопасно».
    private var пусто: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(т(модель.роль == .seller ? "deal_empty_seller" : "deal_empty_buyer"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
            if модель.роль == .buyer {
                Text(т("deal_empty_hint"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .padding(.top, -2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let адрес = Config.страницаСайта("cabinet.php") {
            открыть(адрес)
        }
    }
}

/// Шапка: в виде сайта — панель сайта, иначе системная.
struct ШапкаСделок: ViewModifier {
    let заголовок: String

    func body(content: Content) -> some View {
        if Config.дизайнКакНаСайте {
            content
                .шапкаЭкранаСайта(заголовок)
        } else {
            content
                .navigationTitle(заголовок)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Вкладки

/// #dtab-seller / #dtab-buyer — две отдельные кнопки (dealsTab): выбранная — зелёный градиент, другая — серая в рамке.
struct ВкладкиСделок: View {
    let выбрана: РольСделок
    let выбрать: (РольСделок) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(РольСделок.allCases, id: \.self) { роль in
                кнопка(роль)
            }
        }
    }

    private func кнопка(_ роль: РольСделок) -> some View {
        let активна = выбрана == роль
        return Button {
            выбрать(роль)
        } label: {
            Text(роль.название)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(активна ? Color.white : Theme.текстВторой)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 37)
                .background {
                    if активна {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .shadow(color: КраскаСделокКабинета.теньКнопки, radius: 4, x: 0, y: 5)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(Theme.поверхность2)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                    .strokeBorder(Theme.линия, lineWidth: 1.5)
                            }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: СделкиText.т("a11y_tab"), роль.название))
        .accessibilityAddTraits(активна ? .isSelected : [])
    }
}

// MARK: - Карточка в списке

/// Вид плашки статуса: краски --tint-… и --on-… сайта.
enum ВидСтатусаСделки {
    case предупреждение
    case инфо
    case хорошо
    case плохо
    case серый

    var фон: Color {
        switch self {
        case .предупреждение: return КраскаСделокКабинета.предупреждениеФон
        case .инфо:           return КраскаСделокКабинета.инфоФон
        case .хорошо:         return КраскаСделокКабинета.хорошоФон
        case .плохо:          return КраскаСделокКабинета.плохоФон
        case .серый:          return Theme.поверхность2
        }
    }

    var текст: Color {
        switch self {
        case .предупреждение: return КраскаСделокКабинета.предупреждениеТекст
        case .инфо:           return КраскаСделокКабинета.инфоТекст
        case .хорошо:         return КраскаСделокКабинета.хорошоТекст
        case .плохо:          return КраскаСделокКабинета.плохоТекст
        case .серый:          return Theme.текстВторой
        }
    }

    /// Таблица r в loadDeals: значок, текст и краска по статусу.
    static func для(_ статус: String) -> (вид: ВидСтатусаСделки, символ: String, текст: String) {
        let т = СделкиText.т
        switch статус {
        case "proposed":  return (.предупреждение, "hourglass", т("deal_st_proposed"))
        case "accepted":  return (.инфо, "checkmark.circle", т("deal_st_accepted"))
        case "pending":   return (.предупреждение, "hourglass", т("deal_st_pending"))
        case "held":      return (.инфо, "lock", т("deal_st_held"))
        case "shipped":   return (.предупреждение, "square.and.arrow.up", т("deal_st_shipped"))
        case "delivered": return (.хорошо, "shippingbox", т("deal_st_delivered"))
        case "confirmed": return (.серый, "checkmark.circle", т("deal_st_confirmed"))
        case "disputed":  return (.плохо, "exclamationmark.triangle", т("deal_st_disputed"))
        case "resolved":  return (.серый, "scale.3d", т("deal_st_resolved"))
        case "cancelled": return (.серый, "xmark", т("deal_st_cancelled"))
        case "expired":   return (.серый, "checkmark.circle", т("deal_st_expired"))
        default:          return (.серый, "questionmark", т("deal_st_unknown"))
        }
    }
}

/// .ulx-card сделки в списке (loadDeals сайта).
struct КарточкаВСпискеСделок: View {
    let сделка: СделкаКратко

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            /* Владелец 06.10.2026 («схема должна быть ровной везде»): карточки сделок одной формы — строка 1 название и
               статус справа (по верху), строка 2 «KLK-… · дата», строка 3 роль и ник; каждая ровно в одну строку, как
               бы длинно ни было. Миниатюра одна на всех, нет фото — та же плашка. */
            HStack(alignment: .top, spacing: 12) {
                фото
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(сделка.название.isEmpty ? т("deals_item_fallback") : сделка.название)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                        плашкаСтатуса
                    }
                    Text(номерИДата)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(роль)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            /* Статус доставки из кэша отслеживания (без сети); нет данных — ничего. */
            ПилюляТрекаСделки(сделка: сделка.id, сНазванием: true)
            строкаДенег
            if let строкаТаймера = таймер {
                строкаТаймера
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                    .padding(.top, -4)
            }
            подсказка
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// «KLK-… · 5 окт.».
    private var номерИДата: String {
        var части: [String] = [сделка.id]
        let дата = СделкиФормат.деньМесяц(сделка.создана)
        if !дата.isEmpty { части.append(дата) }
        return части.joined(separator: " · ")
    }

    /// «Я продаю · ник».
    private var роль: String {
        СтрокаРолиСделки.текст(продавец: сделка.продавец, услуга: сделка.услуга, аренда: сделка.аренда,
                               имя: сделка.продавец ? сделка.имяПокупателя : сделка.имяПродавца)
    }

    private var фото: some View {
        КартинкаЛенты(Config.url(сделка.фото), пунктов: 56) {
            ZStack {
                Theme.поверхность2
                Image(systemName: "shippingbox")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityHidden(true)
    }

    private var плашкаСтатуса: some View {
        let с = ВидСтатусаСделки.для(сделка.статус)
        let вид: ВидСтатусаСделки = сделка.идётВозврат ? .предупреждение : с.вид
        let текст = сделка.идётВозврат ? т("deal_st_return") : с.текст
        let символ = сделка.идётВозврат ? "arrow.uturn.backward" : с.символ
        /* У «Отправлено» сайт красит плашку --edge-warn, а не --tint-warn (карта r.shipped в loadDeals). */
        let отправлено = сделка.статус == "shipped" && !сделка.идётВозврат
        /* Ровная схема: плашка в одну строку и не шире 150 — длинный статус ужимается, а не переносится, и строка
           названия у всех карточек одной высоты. */
        return HStack(spacing: 5) {
            Image(systemName: символ)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
        }
        .foregroundStyle(вид.текст)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(отправлено ? КраскаСделокКабинета.предупреждениеКромка : вид.фон, in: Capsule())
        .frame(maxWidth: 150, alignment: .trailing)
    }

    /**
     Строка денег — таблица в три колонки: подпись мелко сверху, число под ней в одну строку. Продавцу «Сумма · Комиссия
     −seller_fee · Получите seller_get», покупателю «Цена · Комиссия +сбор · Оплата total_pay»; не состоялась — сумма и
     «сделка не состоялась». Сбор покупателя — buyer_fee сервера (у сайта здесь NaN и всегда 620 ₸, §4.1); нет его — разница.
     */
    private var строкаДенег: some View {
        let сумма = СделкиФормат.тенге(сделка.сумма)
        let перваяПодпись = т(сделка.продавец ? "deal_sum" : "deal_price")
        return HStack(alignment: .top, spacing: 12) {
            if сделка.несостоялась {
                ячейкаДенег(перваяПодпись, сумма, краска: Theme.текст)
                ячейкаДенег(" ", т("deal_nodeal"), краска: Theme.текстВторой, жирно: false)
                ячейкаДенег(" ", " ", краска: Theme.текст)
            } else if сделка.продавец {
                ячейкаДенег(перваяПодпись, сумма, краска: Theme.текст)
                ячейкаДенег(т("deal_fee"), "−" + СделкиФормат.тенге(сделка.сборПродавца), краска: Theme.текст, жирно: false)
                ячейкаДенег(т("deal_get"), СделкиФормат.тенге(сделка.продавецПолучит),
                            краска: КраскаСделокКабинета.хорошоТекст)
            } else {
                let сбор = сделка.сборПокупателя > 0 ? сделка.сборПокупателя : max(0, сделка.кОплате - сделка.сумма)
                ячейкаДенег(перваяПодпись, сумма, краска: Theme.текст)
                ячейкаДенег(т("deal_fee"), "+" + СделкиФормат.тенге(сбор), краска: Theme.текст, жирно: false)
                ячейкаДенег(т("deal_pay"), СделкиФормат.тенге(сделка.кОплате), краска: Theme.текст)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
        }
    }

    /// Ячейка таблицы денег: подпись без двоеточия мелко, число под ней — одной строкой, длинное ужимается.
    private func ячейкаДенег(_ подпись: String, _ значение: String, краска: Color, жирно: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(подпись.hasSuffix(":") ? String(подпись.dropLast()) : подпись)
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(значение)
                .font(.system(size: 13, weight: жирно ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(краска)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// «Авто-подтверждение через Hч Mм» — delivered, время есть, возврата нет.
    private var таймер: Text? {
        guard сделка.статус == "delivered", сделка.осталосьСек > 0, !сделка.возврат else { return nil }
        return Text(Image(systemName: "alarm")) + Text(" " + т("deal_autoconfirm") + " " + СделкиФормат.часыМинуты(сделка.осталосьСек))
    }

    /// Подсказки deal_hint_* — в том же порядке и при тех же условиях, что у сайта.
    @ViewBuilder
    private var подсказка: some View {
        if сделка.статус == "held" {
            строкаПодсказки(т(сделка.продавец ? "deal_hint_held_seller" : "deal_hint_held_buyer"),
                            вид: сделка.продавец ? .хорошо : .инфо, символ: сделка.продавец ? "shippingbox" : "lock")
        }
        if сделка.статус == "shipped" {
            строкаПодсказки(т(сделка.продавец ? "deal_hint_shipped_seller" : "deal_hint_shipped_buyer"),
                            вид: .предупреждение, символ: "square.and.arrow.up")
        }
        if сделка.статус == "delivered" && !сделка.продавец && !сделка.идётВозврат {
            строкаПодсказки(т("deal_hint_delivered_buyer"), вид: .предупреждение, символ: "exclamationmark.triangle")
        }
        if сделка.идётВозврат {
            строкаПодсказки(т("deal_hint_return"), вид: .предупреждение, символ: "arrow.uturn.backward")
        }
        if сделка.статус == "disputed" {
            строкаПодсказки(т("deal_hint_disputed"), вид: .плохо, символ: "exclamationmark.triangle")
        }
    }

    private func строкаПодсказки(_ текст: String, вид: ВидСтатусаСделки, символ: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: символ)
                .font(.system(size: 15))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(вид.текст)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
        .padding(.top, -2)
    }
}
