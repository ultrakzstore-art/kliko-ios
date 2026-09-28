import SwiftUI
import UIKit
import WebKit

/**
 ДЕНЬГИ СДЕЛКИ — ОКНА И БЛОКИ КАРТОЧКИ (этап 44, владелец 26.09.2026: «всё одно и то же, просто код разный»).

 🔴 Только за Config.деньгиСделок (false): слой вешается на карточку всегда, но без рубильника модель не открывает ни
 одного окна, а блоки ниже карточка не рисует — на их месте кнопки страницы сделки сайта (этап 43).

 Окна — те же, что у js/cabinet.min.js: «Применить баллы?» (showPointsModal), «Отмена сделки» с причиной (dealCancel
 → cabPrompt), «Всё в порядке, претензий нет?» (dealAcceptAsk) со звёздами в delivered, окно eGov (otpStepOpen:
 ИИН, телефон, remote.biometric.kz, otp_step_check), ход «Оформляем безопасную сделку» (escrowProgress) и страница банка.

 СТРАНИЦА БАНКА. redirect_url сайт открывает в той же вкладке (location.href), и банк возвращает человека на
 …/cabinet…?topup=ok|fail&deal=<id>. Здесь она открывается в листе приложения — своим WKWebView с общим хранилищем
 куки (WKWebsiteDataStore.default()), а не SFSafariViewController: из Safari-листа адрес возврата не поймать (его
 навигация закрыта от приложения), а универсальная ссылка внутри него приложение не откроет. ОкноБанка отменяет переход
 на свой домен с topup= и отдаёт итог модели (ВозвратСоШлюза) — страница кабинета под нативным слоем при этом не
 трогается. Ссылки на приложения банков (не http/https) уходят в систему. Если сервер вернёт человека на другой адрес
 (карта §8.12.5 — проверить вживую), лист закроет сам человек: сделка перечитается, повторного списания не будет.
 */

// MARK: - Слой карточки: листы, окна, ход

struct СлойДенегСделки: ViewModifier {
    @ObservedObject var деньги: ДеньгиСделкиМодель
    @Binding var спор: Bool
    let открыть: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $деньги.лист, onDismiss: { деньги.листЗакрыт() }) { лист in
                листДенег(лист)
            }
            /* Вопросы о деньгах — оформленным листом по высоте (cabConfirm сайта), а не системным окном. */
            .background {
                Color.clear
                    .sheet(item: $деньги.вопрос) { в in
                        ОкноВопросаДенег(вопрос: в, слова: деньги.текст(в), подтвердить: { подтвердитьПозже(в) },
                                         отмена: { деньги.вопрос = nil })
                    }
            }
            .background {
                Color.clear
                    .sheet(item: $деньги.тарифы) { цена in
                        ОкноТарифовКурьера(цена: цена, выбрать: { вариант in выбратьТарифПозже(вариант) },
                                           отмена: { деньги.тарифы = nil })
                    }
            }
            .overlay {
                if let ход = деньги.ход {
                    ХодДенегВид(ход: ход, закрыть: { деньги.закрытьХод() })
                } else if деньги.идёт {
                    /* Денежный запрос в пути (или сверка после банка): кнопки карточки под прозрачной крышкой — второе
                       нажатие не доходит ни до модели, ни до сервера. Шапка с «назад» остаётся доступной. */
                    ЗанятоДеньгиВид()
                }
            }
            .onChange(of: деньги.нуженСпор) { _, нужен in
                guard нужен else { return }
                деньги.нуженСпор = false
                /* Лист приёмки ещё уезжает — окно спора после него, иначе SwiftUI его не покажет. */
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { спор = true }
            }
            .onAppear {
                деньги.открытьСайт = { хвост in
                    if let адрес = Config.страницаСайта(хвост) { открыть(адрес) }
                }
                забратьВозврат()
            }
            .onReceive(NotificationCenter.default.publisher(for: ЗаданияДенегСделок.пришло)) { _ in
                забратьВозврат()
            }
    }

    /// Лист вопроса сперва уезжает, потом — действие: следом может открыться лист банка или eGov.
    @MainActor
    private func подтвердитьПозже(_ в: ДеньгиСделкиМодель.Вопрос) {
        let м = деньги
        м.вопрос = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            м.подтвердить(в)
        }
    }

    @MainActor
    private func выбратьТарифПозже(_ вариант: ЦенаКурьера.Вариант) {
        let м = деньги
        м.тарифы = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            м.выбратьТариф(вариант)
        }
    }

    /// Возврат со страницы банка по ссылке (?topup=…&deal=<эта сделка>) — задание из ящика.
    private func забратьВозврат() {
        guard Config.деньгиСделок else { return }
        let номер = деньги.id
        let задание = ЗаданияДенегСделок.shared.забрать { з in
            if case .шлюз(let итог) = з { return итог.сделка == номер }
            return false
        }
        if case .шлюз(let итог)? = задание {
            деньги.вернулисьСоШлюза(итог)
        }
    }

    @ViewBuilder
    private func листДенег(_ лист: ДеньгиСделкиМодель.Лист) -> some View {
        switch лист {
        case .баллы(let сумма, let баллов, let максимум):
            ОкноБаллов(сумма: сумма, баллов: баллов, максимум: максимум,
                       применить: { деньги.заморозить(баллами: $0) }, отмена: { деньги.лист = nil })
        case .отмена(let после):
            ОкноОтменыСделки(послеОтправки: после, отменить: { деньги.отменить(причина: $0) },
                             закрыть: { деньги.лист = nil })
        case .приёмка(let звёзды):
            ОкноПриёмки(звёзды: звёзды, принять: { деньги.принять(звёзд: $0, отзыв: $1) },
                        спор: { деньги.претензия() }, позже: { деньги.лист = nil })
        case .eGov(let запрос):
            ОкноEGov(запрос: запрос, готово: { деньги.eGovПройден(запрос) }, закрыть: { деньги.лист = nil })
        case .банк(let адрес, _):
            ОкноБанка(адрес: адрес, вернулись: { итог in вернулисьСБанка(итог) }, закрыть: { деньги.лист = nil })
        case .пополнение:
            ЛистПополненияКошелька(открыть: открыть, закрыть: { деньги.лист = nil })
        }
    }

    /// Банк вернул на другую сделку (не должен, но адрес пишет сервер) — туда, через ящик и роутер.
    private func вернулисьСБанка(_ итог: ВозвратСоШлюза.Итог) {
        if итог.сделка == деньги.id {
            деньги.вернулисьСоШлюза(итог)
            return
        }
        деньги.лист = nil
        ЗаданияДенегСделок.shared.положить(.шлюз(итог))
        NativeRouter.shared.цель = .сделка(id: итог.сделка)
    }
}

// MARK: - Вопрос о деньгах (cabConfirm сайта: значок, заголовок, текст, «Возврат и обратная доставка», две кнопки)

struct ОкноВопросаДенег: View {
    let вопрос: ДеньгиСделкиМодель.Вопрос
    let слова: ДеньгиСделкиМодель.ТекстВопроса
    let подтвердить: () -> Void
    let отмена: () -> Void

    init(вопрос: ДеньгиСделкиМодель.Вопрос, слова: ДеньгиСделкиМодель.ТекстВопроса,
         подтвердить: @escaping () -> Void, отмена: @escaping () -> Void) {
        self.вопрос = вопрос
        self.слова = слова
        self.подтвердить = подтвердить
        self.отмена = отмена
    }

    /// Сумма заморозки — только у «Заморозить средства?».
    private var суммаЗаморозки: Int? {
        if case .заморозить(let сумма) = вопрос { return сумма }
        return nil
    }

    private var символ: String {
        switch вопрос {
        case .заморозить: return "lock.fill"
        case .договорились, .возврат: return "checkmark.shield.fill"
        case .вернуть, .платнаяОтмена: return "exclamationmark.triangle.fill"
        case .код: return "number"
        case .курьер, .заберуСам: return "car.fill"
        case .картойЗаКурьера: return "creditcard.fill"
        case .ожидание: return "clock.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                шапка
                текст
                if суммаЗаморозки != nil { УсловияВозврата() }
                кнопки
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }

    private var шапка: some View {
        /* .confirm-icon + .confirm-title: значок в круглой плашке, заголовок 20/800. */
        HStack(spacing: 12) {
            Image(systemName: символ)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(слова.опасная ? КраскаСделокКабинета.плохоТекст : КраскаСделокКабинета.хорошоТекст)
                .frame(width: 40, height: 40)
                .background(слова.опасная ? КраскаСделокКабинета.плохоФон : КраскаСделокКабинета.хорошоФон, in: Circle())
                .accessibilityHidden(true)
            Text(слова.заголовок)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var текст: some View {
        if let сумма = суммаЗаморозки {
            /* «Заморозим <b>N ₸</b> на платформе…» — сумма жирным, правила возврата — отдельным блоком ниже. */
            ТекстСделки.сЖирным(ДеньгиСделкиText.т("fz_m", n: СделкиФормат.тенге(сумма)))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        } else if !слова.текст.isEmpty {
            Text(слова.текст)
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var кнопки: some View {
        VStack(spacing: 8) {
            if слова.толькоПонятно {
                КнопкаСделки(слова.кнопка, вид: .главная) { отмена() }
            } else {
                if let сумма = суммаЗаморозки {
                    КнопкаСделки(слова.кнопка, вид: .главная, символ: "lock", сумма: СделкиФормат.тенге(сумма)) {
                        подтвердить()
                    }
                } else {
                    КнопкаСделки(слова.кнопка, вид: слова.опасная ? .опасная : .главная) { подтвердить() }
                }
                КнопкаСделки(СделкиText.т("btn_cancel"), вид: .вторая) { отмена() }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Выбор тарифа курьера (shpTariffChoice сайта)

struct ОкноТарифовКурьера: View {
    let цена: ЦенаКурьера
    let выбрать: (ЦенаКурьера.Вариант) -> Void
    let отмена: () -> Void

    init(цена: ЦенаКурьера, выбрать: @escaping (ЦенаКурьера.Вариант) -> Void, отмена: @escaping () -> Void) {
        self.цена = цена
        self.выбрать = выбрать
        self.отмена = отмена
    }

    private var варианты: [ЦенаКурьера.Вариант] {
        var список = [цена.основной]
        if let другой = цена.другой { список.append(другой) }
        return список
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(ДеньгиСделкиText.т("shp_add_t"), systemImage: "car.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(ДеньгиСделкиText.т("shp_tariff_m"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(варианты, id: \.q) { в in
                    Button { выбрать(в) } label: { строка(в) }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
                КнопкаСделки(СделкиText.т("btn_cancel"), вид: .вторая) { отмена() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }

    private func строка(_ в: ЦенаКурьера.Вариант) -> some View {
        let пеший = в.тариф == "courier"
        return HStack(spacing: 12) {
            Image(systemName: пеший ? "figure.walk" : "car.fill")
                .font(.system(size: 16))
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                .frame(width: 38, height: 38)
                .background(КраскаСделокКабинета.хорошоФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            Text(ДеньгиСделкиText.т(пеший ? "co_ship_walk" : "co_ship_exp"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
            Text(СделкиФормат.тенге(в.цена))
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.зелёный)
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .accessibilityElement(children: .combine)
    }
}

extension ЦенаКурьера: Identifiable {
    var id: String { основной.q + "|" + (другой?.q ?? "") }
}

// MARK: - Крышка «запрос в пути»

struct ЗанятоДеньгиВид: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.06)
            SiteSpinner.крупный
                .padding(18)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ДеньгиСделкиText.т("ep_wait"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Ход (escrowProgress)

struct ХодДенегВид: View {
    let ход: ХодДенег
    let закрыть: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                значок
                Text(ход.заголовок)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(ход.подпись)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(ход.процент), total: 100)
                    .tint(краска)
                Text(String(ход.процент) + "%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if ход.итог == .занято { закрыть() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var краска: Color {
        switch ход.итог {
        case .идёт, .готово: return Theme.зелёный
        case .занято: return Theme.оранжевый
        case .ошибка: return КраскаСделокКабинета.плохоТекст
        }
    }

    private var имяЗначка: String {
        switch ход.итог {
        case .идёт: return "lock.shield"
        case .готово: return "checkmark.shield.fill"
        case .занято: return "exclamationmark.triangle.fill"
        case .ошибка: return "xmark.octagon.fill"
        }
    }

    private var значок: some View {
        Image(systemName: имяЗначка)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(краска)
            .accessibilityHidden(true)
    }
}

// MARK: - «Применить баллы?» (showPointsModal)

struct ОкноБаллов: View {
    let сумма: Int
    let баллов: Int
    let максимум: Int
    let применить: (Int) -> Void
    let отмена: () -> Void

    @State private var значение: Double

    init(сумма: Int, баллов: Int, максимум: Int, применить: @escaping (Int) -> Void, отмена: @escaping () -> Void) {
        self.сумма = сумма
        self.баллов = баллов
        self.максимум = максимум
        self.применить = применить
        self.отмена = отмена
        _значение = State(initialValue: Double(максимум))
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }
    private var скидка: Int { Int(значение.rounded()) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(т("pt_t"), systemImage: "star.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(т("pt_m").replacingOccurrences(of: "{p}", with: СделкиФормат.деньги(баллов))
                    .replacingOccurrences(of: "{n}", with: СделкиФормат.тенге(максимум)))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                VStack(spacing: 6) {
                    строка(т("pt_sum"), СделкиФормат.тенге(сумма))
                    строка(т("pt_disc"), "−" + СделкиФормат.тенге(скидка))
                    Divider()
                    строка(т("pt_total"), СделкиФормат.тенге(max(0, сумма - скидка)))
                        .font(.system(size: 17, weight: .heavy))
                }
                .padding(12)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                Slider(value: $значение, in: 0...Double(max(1, максимум)), step: 1)
                    .tint(Theme.акцент)
                    .accessibilityLabel(т("a11y_pts"))
                    .accessibilityValue(СделкиФормат.деньги(скидка))
                HStack {
                    Text(т("pt_zero"))
                    Spacer()
                    Text(т("pt_max").replacingOccurrences(of: "{p}", with: СделкиФормат.деньги(максимум)))
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                УсловияВозврата()
                КнопкаСделки(т("pt_apply"), вид: .главная, символ: "lock") { применить(скидка) }
                КнопкаСделки(т("pt_none"), вид: .вторая) { применить(0) }
                КнопкаСделки(СделкиText.т("btn_cancel"), вид: .тихая) { отмена() }
            }
            .padding(20)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }

    private func строка(_ подпись: String, _ значение: String) -> some View {
        HStack {
            Text(подпись)
            Spacer(minLength: 8)
            Text(значение).bold()
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.текст)
    }
}

/// dealReturnNote: «Возврат и обратная доставка».
struct УсловияВозврата: View {
    var body: some View {
        let т: (String) -> String = ДеньгиСделкиText.т
        VStack(alignment: .leading, spacing: 4) {
            Label(т("ret_pol_title"), systemImage: "arrow.uturn.backward")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            ForEach(["ret_pol_defect", "ret_pol_asis", "ret_pol_fwd"], id: \.self) { ключ in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                        .foregroundStyle(Theme.зелёный)
                        .accessibilityHidden(true)
                    Text(т(ключ))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

// MARK: - «Отмена сделки» (dealCancel → cabPrompt)

struct ОкноОтменыСделки: View {
    let послеОтправки: Bool
    let отменить: (String) -> Void
    let закрыть: () -> Void

    @State private var причина = ""

    init(послеОтправки: Bool, отменить: @escaping (String) -> Void, закрыть: @escaping () -> Void) {
        self.послеОтправки = послеОтправки
        self.отменить = отменить
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(т("cn_t"), systemImage: "xmark.circle")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if послеОтправки {
                    ЗаметкаСделки(ТекстСделки.сЖирным(т("cn_after")), вид: .предупреждение, символ: "exclamationmark.triangle")
                } else {
                    Text(т("cn_full"))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текстВторой)
                }
                TextField(т("cn_ph"), text: $причина, axis: .vertical)
                    .lineLimit(2...4)
                    .modifier(ПолеДенегСделки())
                КнопкаСделки(т(послеОтправки ? "cn_btn_fee" : "cn_btn"), вид: .опасная, символ: "xmark") { отменить(причина) }
                КнопкаСделки(СделкиText.т("btn_cancel"), вид: .тихая) { закрыть() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        /* Лист по высоте содержимого — без пустоты снизу (владелец, TestFlight: «Отмена сделки»). */
        .листПоВысоте()
    }
}

// MARK: - «Всё в порядке, претензий нет?» (dealAcceptAsk + звёзды delivered)

struct ОкноПриёмки: View {
    let звёзды: Bool
    let принять: (Int, String) -> Void
    let спор: () -> Void
    let позже: () -> Void

    @State private var оценка = 0
    @State private var отзыв = ""

    init(звёзды: Bool, принять: @escaping (Int, String) -> Void, спор: @escaping () -> Void, позже: @escaping () -> Void) {
        self.звёзды = звёзды
        self.принять = принять
        self.спор = спор
        self.позже = позже
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.зелёный)
                    .accessibilityHidden(true)
                Text(т("acc_t"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                Text(т("acc_m"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if звёзды {
                    VStack(spacing: 8) {
                        Text(т("dl_rate_seller"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                        ЗвёздыСделки(звёзд: оценка, размер: 30, выбрать: { оценка = $0 })
                        TextField(т("dl_review_ph"), text: $отзыв, axis: .vertical)
                            .lineLimit(2...4)
                            .modifier(ПолеДенегСделки())
                    }
                }
                КнопкаСделки(т("acc_yes"), вид: .главная, символ: "checkmark.circle") { принять(оценка, отзыв) }
                КнопкаСделки(т("acc_no"), вид: .опасная, символ: "exclamationmark.triangle") { спор() }
                КнопкаСделки(т("acc_later"), вид: .тихая) { позже() }
            }
            .padding(20)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .листПоВысоте()
    }
}

/// Поле ввода в краске сайта (рамка 1.5, поверхность).
struct ПолеДенегСделки: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .padding(10)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
    }
}

// MARK: - Страница банка (redirect_url) и страница eGov — общий WKWebView

/**
 WKWebView листа денег. перехват(адрес) → true — переход отменён (возврат со шлюза пойман). Схемы не http/https (приложения
 банков, tel:) — в систему. target=_blank — в этом же окне. Камера — только странице eGov (разрешённыйХост).
 */
struct ВебСтраницаДенег: UIViewRepresentable {
    let адрес: URL
    var разрешённыйХост: String? = nil
    let перехват: (URL) -> Bool

    func makeCoordinator() -> Координатор {
        Координатор(разрешённыйХост: разрешённыйХост, перехват: перехват)
    }

    func makeUIView(context: Context) -> WKWebView {
        let настройка = WKWebViewConfiguration()
        настройка.websiteDataStore = .default()
        настройка.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: настройка)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.accessibilityLabel = разрешённыйХост == nil ? ДеньгиСделкиText.т("a11y_gw") : ДеньгиСделкиText.т("a11y_egov")
        web.load(URLRequest(url: адрес))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Координатор: NSObject, WKNavigationDelegate, WKUIDelegate {
        let разрешённыйХост: String?
        let перехват: (URL) -> Bool

        init(разрешённыйХост: String?, перехват: @escaping (URL) -> Bool) {
            self.разрешённыйХост = разрешённыйХост
            self.перехват = перехват
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if перехват(url) {
                decisionHandler(.cancel)
                return
            }
            let схема = (url.scheme ?? "").lowercased()
            if схема != "http" && схема != "https" && схема != "about" && схема != "data" && схема != "blob" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            if let хост = разрешённыйХост, origin.host.lowercased() == хост {
                decisionHandler(.grant)
            } else {
                decisionHandler(.prompt)
            }
        }
    }
}

/// Страница банка сделки (pay_card, ship_add_card): общий лист ЛистШлюза (Wallet/MoneyGatewaySheet.swift) — возврат
/// ?topup=…&deal= ловит ВозвратСоШлюза, уход на свой домен без итога и «Закрыть» — закрыть (сделка перечитается).
struct ОкноБанка: View {
    let адрес: URL
    let вернулись: (ВозвратСоШлюза.Итог) -> Void
    let закрыть: () -> Void

    var body: some View {
        ЛистШлюза(адрес: адрес, заголовок: ДеньгиСделкиText.т("gw_title"), подписьЗакрыть: СделкиText.т("close"),
                  перехват: { url in
                      guard let итог = ВозвратСоШлюза.разобрать(url) else { return false }
                      DispatchQueue.main.async { вернулись(итог) }
                      return true
                  }, закрыть: закрыть)
    }
}

// MARK: - Окно eGov (otpStepOpen, otp_step_create, otp_step_check)

@MainActor
final class ПроверкаEGovМодель: ObservableObject {
    enum Этап: Equatable {
        case форма
        case запуск
        case виджет(URL)
        case ошибка(String)
    }

    let запрос: ЗапросEGov
    @Published var иин = ""
    @Published var телефон = ""
    @Published private(set) var этап: Этап = .форма
    @Published private(set) var осталось = 300
    @Published private(set) var подсказка: String? = nil

    private var опрос: Task<Void, Never>? = nil
    private var готово: (() -> Void)? = nil

    init(запрос: ЗапросEGov) {
        self.запрос = запрос
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    /// CAB_USER.iin и CAB_USER.phone страницы кабинета — как сайт подставляет их в окно.
    func заполнить() async {
        guard иин.isEmpty && телефон.isEmpty,
              let страница = try? await КабинетСайта.страницаКабинета() else { return }
        let html = страница.html
        guard let начало = html.range(of: "const CAB_USER = {") else { return }
        let хвост = String(html[начало.upperBound...].prefix(4000))
        if let r = хвост.range(of: #"\biin:\s*"[0-9]{12}""#, options: .regularExpression) {
            иин = String(хвост[r].filter { $0.isNumber }.suffix(12))
        }
        if let r = хвост.range(of: #"\bphone:\s*"[+0-9 ()\-]{10,20}""#, options: .regularExpression) {
            let кусок = String(хвост[r])
            if let кавычка = кусок.firstIndex(of: "\"") {
                телефон = String(кусок[кусок.index(after: кавычка)...]).replacingOccurrences(of: "\"", with: "")
            }
        }
    }

    /// otpStepStart: ИИН — 12 цифр, телефон — не меньше 10 цифр; otp_step_create → окно remote.biometric.kz.
    func начать(пройден: @escaping () -> Void) {
        готово = пройден
        let цифрыИИН = иин.compactMap { $0.wholeNumberValue }.map { String($0) }.joined()
        let номер = телефон.compactMap { с -> String? in
            if с == "+" { return "+" }
            return с.wholeNumberValue.map { String($0) }
        }.joined()
        guard цифрыИИН.count == 12 else {
            подсказка = т("cmp_err_iin")
            return
        }
        guard номер.filter({ $0 != "+" }).count >= 10 else {
            подсказка = т("bio_need_phone")
            return
        }
        подсказка = nil
        этап = .запуск
        Task { @MainActor in
            do {
                let j = try await СделкиAPI.отправить("cabinet.php?action=otp_step_create",
                                                      тело: ["purpose": self.запрос.назначение, "ref": self.запрос.ссылка,
                                                             "iin": цифрыИИН, "phone": номер])
                let сессия = СделкиAPI.строка(j["session_id"])
                guard СделкиAPI.да(j["ok"]), !сессия.isEmpty,
                      let адрес = URL(string: "https://remote.biometric.kz/flow/" + СделкиAPI.вАдрес(сессия)
                                      + "?locale=" + Self.язык) else {
                    let m = СделкиAPI.строка(j["message"])
                    self.этап = .ошибка(m.isEmpty ? self.т("bio_start_fail") : m)
                    return
                }
                self.этап = .виджет(адрес)
                self.запуститьОпрос()
            } catch {
                self.этап = .ошибка(self.т("bio_start_fail"))
            }
        }
    }

    /// locale окна: kz / ru / en (как у сайта; арабского у eGov нет — ru).
    private static var язык: String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        switch язык {
        case "kk": return "kz"
        case "en": return "en"
        default: return "ru"
        }
    }

    /// Отсчёт 5 минут; опрос otp_step_check раз в 3 с, с последних 4 минут — раз в 6 с (_osTick, _osPollTick).
    private func запуститьОпрос() {
        опрос?.cancel()
        осталось = 300
        опрос = Task { @MainActor [weak self] in
            var доОпроса = 3
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.осталось -= 1
                if self.осталось <= 0 {
                    self.этап = .ошибка(self.т("bio_timeout"))
                    return
                }
                доОпроса -= 1
                if доОпроса > 0 { continue }
                доОпроса = self.осталось > 240 ? 3 : 6
                if await self.проверить() { return }
            }
        }
    }

    /// true — опрос окончен (прошёл или ошибка).
    private func проверить() async -> Bool {
        guard let j = try? await СделкиAPI.отправить("cabinet.php?action=otp_step_check",
                                                     тело: ["purpose": запрос.назначение, "ref": запрос.ссылка]) else {
            return false
        }
        let ok = СделкиAPI.да(j["ok"])
        if ok && СделкиAPI.да(j["verified"]) {
            готово?()
            return true
        }
        let m = СделкиAPI.строка(j["message"])
        if ok && СделкиAPI.да(j["final"]) {
            этап = .ошибка(m.isEmpty ? т("bio_start_fail") : m)
            return true
        }
        if !ok && !СделкиAPI.да(j["pending"]) {
            этап = .ошибка(m.isEmpty ? ТекстыОшибокСделки.ulx(j) : m)
            return true
        }
        return false
    }

    /// «Ещё раз» после ошибки — снова форма.
    func заново() {
        опрос?.cancel()
        этап = .форма
    }

    func остановить() {
        опрос?.cancel()
        опрос = nil
    }
}

struct ОкноEGov: View {
    let готово: () -> Void
    let закрыть: () -> Void
    @StateObject private var модель: ПроверкаEGovМодель

    init(запрос: ЗапросEGov, готово: @escaping () -> Void, закрыть: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: ПроверкаEGovМодель(запрос: запрос))
        self.готово = готово
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    var body: some View {
        NavigationStack {
            содержимое
                .background(Theme.фонСтраницы.ignoresSafeArea())
                .modifier(ШапкаСделок(заголовок: модель.запрос.заголовок.isEmpty ? т("otp_title") : модель.запрос.заголовок))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(СделкиText.т("close")) { закрыть() }
                    }
                }
        }
        .interactiveDismissDisabled(true)
        .task { await модель.заполнить() }
        .onDisappear { модель.остановить() }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.этап {
        case .форма, .запуск:
            форма
        case .виджет(let адрес):
            VStack(spacing: 0) {
                Text(т("bio_confirm_wait") + " " + String(модель.осталось / 60) + ":"
                     + String(format: "%02d", модель.осталось % 60))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.поверхность2)
                ВебСтраницаДенег(адрес: адрес, разрешённыйХост: "remote.biometric.kz", перехват: { _ in false })
            }
        case .ошибка(let текст):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                КнопкаСделки(СделкиText.т("retry"), вид: .главная) { модель.заново() }
                КнопкаСделки(СделкиText.т("close"), вид: .тихая) { закрыть() }
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var форма: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ЗаметкаСделки(Text(модель.запрос.подсказка.isEmpty ? т("otp_hint") : модель.запрос.подсказка), вид: .инфо,
                              символ: "faceid")
                Text(т("bio_iin"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                TextField("000000000000", text: $модель.иин)
                    .keyboardType(.numberPad)
                    .modifier(ПолеДенегСделки())
                    .accessibilityLabel(т("bio_iin"))
                Text(т("bio_phone"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                TextField("+7 (7__) ___-__-__", text: $модель.телефон)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .modifier(ПолеДенегСделки())
                    .accessibilityLabel(т("bio_phone"))
                if let подсказка = модель.подсказка {
                    Text(подсказка)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(КраскаСделокКабинета.плохоТекст)
                }
                КнопкаСделки(модель.этап == .запуск ? т("bio_starting") : т("bio_continue"), вид: .главная,
                             доступна: модель.этап == .форма) {
                    модель.начать(пройден: готово)
                }
                Label(т("bio_sec_note"), systemImage: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(20)
        }
    }
}

// MARK: - Блоки карточки за рубильником

/// dealPinBlock: продавцу — свой код и «меняется каждую минуту»; покупателю — «Код продавца» и «Я получил вещь».
struct БлокКодаПродавца: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            застой
            if сделка.продавец {
                продавцу
            } else {
                покупателю
            }
        }
    }

    /// stale_left ≤ 6 ч: «Сделка стоит на месте. Xч Yм — и она уйдёт на разбор к модератору…».
    @ViewBuilder
    private var застой: some View {
        let сек = сделка.деньги.застойСек
        if сек > 0 && сек <= 21600 {
            let часы = сек / 3600
            let минуты = (сек % 3600) / 60
            let время = (часы > 0 ? String(часы) + СделкиText.т("h_short") + " " : "") + String(минуты) + СделкиText.т("m_short")
            let хвост = т(сделка.продавец ? "stale_warn_s" : "stale_warn_b")
            ЗаметкаСделки(Text(т("stale_warn") + " " + время + " — " + хвост), вид: .предупреждение, символ: "clock")
        }
    }

    @ViewBuilder
    private var продавцу: some View {
        if сделка.кодПринят {
            ПодписьСделки(т("pin_s_money2"))
        } else {
            ПодписьСделки(т(сделка.способПередачи == "self" ? "pin_s_say" : "pin_s_say_far"))
            Text(сделка.деньги.пин.isEmpty ? "····" : сделка.деньги.пин)
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityLabel(т("pin_b_in"))
                .accessibilityValue(сделка.деньги.пин)
            let через = сделка.деньги.пинСек > 0
                ? " · " + т("pin_tick_l") + " " + String(сделка.деньги.пинСек) + " " + т("sec_short") : ""
            Text(т("pin_tick") + через)
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
            ПодписьСделки(т("pin_s_wait2"))
        }
    }

    @ViewBuilder
    private var покупателю: some View {
        if сделка.кодПринят {
            ЗаметкаСделки(Text(т("pin_b_done")), вид: .хорошо, символ: "checkmark.circle")
            ПодписьСделки(т("pin_b_after"))
        } else {
            ЗаметкаСделки(Text(т("pin_b_warn")), вид: .предупреждение, символ: "hand.raised")
            Text(т("pin_b_in"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
            TextField("····", text: $модель.кодПродавца)
                .keyboardType(.numberPad)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .modifier(ПолеДенегСделки())
                .accessibilityLabel(т("pin_b_in"))
            КнопкаСделки(т("pin_b_btn"), вид: .главная, символ: "checkmark.circle",
                         доступна: !модель.деньги.идёт) { действие(.деньги(.кодПродавца)) }
            ПодписьСделки(т(сделка.способПередачи == "self" ? "pin_b_hint" : "pin_b_hint_far"))
        }
    }
}

/// clocalReturnPanel для продавца: причина, кто платит обратную доставку, «Товар вернулся ко мне — вернуть деньги».
struct БлокВозвратаПродавцу: View {
    let сделка: Сделка
    let статус: String
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ДеньгиСделкиText.т(ключ) }

    /// Названия причин (ret_r_*): неизвестная причина — «не назвал».
    private var названиеПричины: String? {
        let известные: Set<String> = ["defect", "wrong", "notdesc", "size", "changed"]
        let код = сделка.деньги.причинаВозврата
        return известные.contains(код) ? т("ret_r_" + код) : nil
    }

    var body: some View {
        let д = сделка.деньги
        let оплачено = сделка.оплачено > 0 ? сделка.оплачено : (сделка.кОплате > 0 ? сделка.кОплате : сделка.сумма)
        let заявкаЖива = !д.заявкаКурьера.isEmpty && д.отменаЗаявки != "free" && !д.заявкаСорвалась
        let туда = заявкаЖива ? (сделка.доставка > 0 ? сделка.доставка : сделка.доставкаЗаСчётПродавца) : 0
        let дорога = д.яндексВключён ? туда + д.обратнаяДоставка : 0
        let винаПродавца = названиеПричины != nil && д.винаВозврата == "seller"
        let покупателю = винаПродавца ? оплачено : max(0, оплачено - дорога)
        let где = т(статус == "returned_to_seller" ? "ret_s_back" : "ret_s_way")
        return БлокСделки {
            ЗаголовокБлокаСделки(текст: СделкиText.т("ret_h"), символ: "arrow.uturn.backward")
            if let причина = названиеПричины {
                (Text(т("ret_reason") + ": ") + Text(причина).bold())
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
            }
            if дорога > 0 && винаПродавца {
                ЗаметкаСделки(Text(где + " " + ДеньгиСделкиText.т("ret_s_fault", n: СделкиФормат.тенге(дорога))),
                              вид: .предупреждение)
                КнопкаСделки(т("ret_s_agree"), вид: .главная, символ: "arrow.uturn.backward") {
                    действие(.деньги(.возвратПринят(сВиной: true)))
                }
                /* Не согласен с причиной — спор return_fault своим запросом (денег не двигает). */
                КнопкаСделки(СделкиText.т("ret_s_disagree"), вид: .вторая, символ: "person.badge.shield.checkmark") {
                    действие(.спорВозврата)
                }
            } else {
                let безПричины = названиеПричины == nil ? т("ret_s_noreason") + " " : ""
                let кто = дорога > 0 ? безПричины + ДеньгиСделкиText.т("ret_s_bpays", n: СделкиФормат.тенге(дорога)) + " " : ""
                ЗаметкаСделки(Text(где + " " + кто + ДеньгиСделкиText.т("ret_s_go", n: СделкиФормат.тенге(покупателю))),
                              вид: .предупреждение)
                КнопкаСделки(т("ret_s_confirm"), вид: .главная, символ: "arrow.uturn.backward") {
                    действие(.деньги(.возвратПринят(сВиной: false)))
                }
            }
        }
    }
}
