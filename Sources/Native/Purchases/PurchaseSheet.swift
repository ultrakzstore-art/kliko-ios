import SwiftUI
import UIKit
import StoreKit

/**
 ОКНО ПОКУПКИ УСЛУГИ ЧЕРЕЗ APP STORE — только при Config.цифровыеПокупки (правило 3.1.1).

 Одно окно на все платные услуги; открывается поверх любого экрана (ПоверхВсего): из «Платных услуг» (кнопки блоков
 PRO, «Продвижение», «Слоты объявлений», «Комбо-пакеты», «Пакеты Kliko AI»), из «Моих объявлений» («Продвинуть»,
 «Расширить», «Пакет Kliko AI», «В ТОП» у резюме), из мастера подачи (лимит слотов, «Продвинуть объявление» после
 публикации), из «Поделиться» и студии роликов (PRO для автопостинга), из «Компании» (PRO для реквизитов).

 Для App Review (правила 3.1.1 и 3.1.2): у каждого товара — название, цена (Product.displayPrice — валюта и формат
 витрины человека), срок (разовая покупка или период подписки) и что входит. У подписки PRO — условия автопродления,
 «Управление подпиской» (системный лист manageSubscriptionsSheet), условия Apple (EULA). Всегда — «Восстановить
 покупки» (AppStore.sync), «Пользовательское соглашение», «Публичная оферта» и «Политика конфиденциальности» —
 страницы сайта своими окнами приложения (НативныеОкна), без браузера. Итог покупки: готово, ждёт одобрения
 («Попросить купить»), отменено, отложено (сайт не ответил — транзакция не закрыта), ошибка.
 Ни цен сайта в тенге, ни ссылок на оплату на сайте здесь нет. Товара нет в App Store (не заведён) — строки нет.
 Продвижение без готового объявления — выбор одного из опубликованных (my_items, approved).
 Краски — кабинета сайта: карточки Theme.поверхность с рамкой Theme.линия, значки .cabset-ic, зелёная кнопка .club-btn.pri.
 */
@MainActor
enum ЛистУслугиApple {
    /// Открыть окно покупки. цель — id объявления (продвижение) или резюме (ТОП резюме). Выключен рубильник — ничего.
    static func показать(_ вид: ВидУслугиApple, цель: String? = nil) {
        guard Config.цифровыеПокупки else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранПокупкиApple(вид: вид, цель: цель, закрыть: закрыть)
        }
    }
}

/// Строка товара в окне: товар App Store и слова сайта о том, что он даёт.
struct СтрокаТовараApple: Identifiable {
    let товар: ТоварApple
    let заголовок: String
    let подробно: [String]
    var id: String { товар.id }
}

// MARK: - Общие части (кнопка, ссылки, восстановление)

/// Кнопка покупки — .club-btn.pri кабинета: зелёный градиент, белые значок и подпись, тень --acc-on.
struct КнопкаПокупкиApple: View {
    let подпись: String
    var значок: String? = nil
    var занято = false
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занято {
                    ProgressView()
                        .tint(Color.white)
                } else if let значок {
                    Image(systemName: значок)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 12)
            .background(КраскаБизнеса.градиентКнопки,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: КраскаСтрокКабинета.тень.opacity(0.22), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(занято)
    }
}

/// «Покупки временно недоступны» — точка входа без загруженного товара (ДоступПокупкиApple.нет). Без ссылок на сайт.
struct НетПокупокApple: View {
    var body: some View {
        ЗаметкаБизнеса(ПокупкиAppleText.т("iap_off"), тон: .серый, значок: "bag")
    }
}

/// Кнопка входа в покупку по единому правилу (ДоступПокупкиApple): товар загружен — кнопка; грузится — та же кнопка
/// с колесом, не нажимается; нет — «Покупки временно недоступны». Пока товара нет, ещё раз спрашивает App Store.
struct ВходПокупкиApple: View {
    let услуга: ВидУслугиApple
    let подпись: String
    let действие: () -> Void
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(услуга: ВидУслугиApple, подпись: String, действие: @escaping () -> Void) {
        self.услуга = услуга
        self.подпись = подпись
        self.действие = действие
    }

    var body: some View {
        switch покупки.доступ(услуга) {
        case .есть:
            КнопкаПокупкиApple(подпись: подпись, значок: услуга.значок, действие: действие)
        case .грузится:
            КнопкаПокупкиApple(подпись: подпись, значок: услуга.значок, занято: true, действие: {})
                .task { await ПокупкиApple.shared.подгрузить() }
        case .нет:
            НетПокупокApple()
                .task { await ПокупкиApple.shared.подгрузить() }
        }
    }
}

/// Документы под окном покупки: страницы сайта своими окнами приложения; EULA Apple — системой.
enum ДокументыПокупокApple {
    static let условияApple = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// soglashenie, oferta, privacy — СтраницаСайта своим окном поверх (НативныеОкна), без браузера.
    @MainActor
    static func открыть(_ слаг: String) {
        НативныеОкна.показать(.страница(СтраницаСайта(слаг: слаг, якорь: nil)))
    }

    @MainActor
    static func открытьEULA() {
        guard let адрес = условияApple else { return }
        UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
    }
}

/// Ссылка-строка документа: подчёркнутая, цветом акцента.
struct СсылкаДокументаApple: View {
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .underline()
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
    }
}

/// Все ссылки на условия: соглашение, оферта, конфиденциальность и (для подписки) EULA Apple.
struct СсылкиУсловийApple: View {
    var подписка = false

    private func т(_ ключ: String) -> String { ПокупкиAppleText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            СсылкаДокументаApple(подпись: т("terms")) { ДокументыПокупокApple.открыть("soglashenie") }
            СсылкаДокументаApple(подпись: т("offer")) { ДокументыПокупокApple.открыть("oferta") }
            СсылкаДокументаApple(подпись: т("privacy")) { ДокументыПокупокApple.открыть("privacy") }
            if подписка {
                СсылкаДокументаApple(подпись: т("apple_eula")) { ДокументыПокупокApple.открытьEULA() }
            }
        }
    }
}

/**
 Карточка «Покупки App Store» внизу «Платных услуг» (только при Config.цифровыеПокупки): «Восстановить покупки»,
 «Управление подпиской» (manageSubscriptionsSheet — системный лист подписок Apple ID), условия и документы.
 */
struct КарточкаПокупокApple: View {
    @ObservedObject private var покупки = ПокупкиApple.shared
    @State private var итог: String? = nil
    @State private var подпискиОткрыты = false

    init() {}

    private func т(_ ключ: String) -> String { ПокупкиAppleText.т(ключ) }

    /// Единое правило (ДоступПокупкиApple): карточка — только когда из App Store загружен хоть один товар, или есть
    /// оплаченные, но ещё не применённые покупки (им нужно «Восстановить покупки»). Иначе её нет вовсе.
    var body: some View {
        if покупки.естьЛюбойТовар || покупки.естьОтложенные {
            карточка
        } else {
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
                .task { await ПокупкиApple.shared.подгрузить() }
        }
    }

    private var карточка: some View {
        КарточкаБизнеса(т("store_card"), значок: "apple.logo") {
            Text(т("pay_note"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if покупки.естьОтложенные {
                ЗаметкаБизнеса(т("pending_banner"), тон: .предупреждение, значок: "clock.arrow.circlepath")
            }
            if let итог {
                ЗаметкаБизнеса(итог, тон: .инфо, значок: "info.circle")
            }
            КнопкаБизнеса(подпись: т("restore"), занято: покупки.восстанавливаем, второстепенная: true) {
                восстановить()
            }
            КнопкаБизнеса(подпись: т("manage_subs"), второстепенная: true) {
                подпискиОткрыты = true
            }
            СсылкиУсловийApple(подписка: true)
        }
        .manageSubscriptionsSheet(isPresented: $подпискиОткрыты)
    }

    private func восстановить() {
        итог = nil
        Task { @MainActor in
            итог = await ПокупкиApple.shared.восстановить()
        }
    }
}

// MARK: - Окно покупки

struct ЭкранПокупкиApple: View {
    let вид: ВидУслугиApple
    let закрыть: () -> Void
    /// Продвижение открыто без объявления — выбрать его здесь.
    private let выбиратьОбъявление: Bool

    @ObservedObject private var покупки = ПокупкиApple.shared
    @ObservedObject private var бизнес = БизнесМодель.shared
    @State private var цель: String
    @State private var объявления: [МоёОбъявление]? = nil
    @State private var итог: String? = nil
    @State private var итогТон: ЗаметкаБизнеса.Тон = .серый
    @State private var нуженВход = false
    @State private var подпискиОткрыты = false

    init(вид: ВидУслугиApple, цель: String?, закрыть: @escaping () -> Void) {
        self.вид = вид
        self.закрыть = закрыть
        let готовая = (цель ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.выбиратьОбъявление = вид == .продвижение && готовая.isEmpty
        _цель = State(initialValue: готовая)
    }

    private func т(_ ключ: String) -> String { ПокупкиAppleText.т(ключ) }
    private func сайт(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    шапка
                    if выбиратьОбъявление { выборОбъявления }
                    if покупки.естьОтложенные {
                        ЗаметкаБизнеса(т("pending_banner"), тон: .предупреждение, значок: "clock.arrow.circlepath")
                    }
                    товарыБлок
                    итогБлок
                    подвал
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                        .tint(Theme.акцент)
                }
            }
        }
        .manageSubscriptionsSheet(isPresented: $подпискиОткрыты)
        .task { await загрузить() }
    }

    // MARK: Шапка

    private var заголовок: String {
        switch вид {
        case .продвижение: return сайт("promo_title")
        case .про: return "Kliko PRO"
        case .слоты: return сайт("upg_slots_title")
        case .комбо: return сайт("upg_combo_t")
        case .пакетИИ: return сайт("upg_ai_packs")
        case .топРезюме: return т("resume_top_title")
        case .свойИИ: return т("own_ai_title")
        }
    }

    private var подзаголовок: String? {
        switch вид {
        case .про: return сайт("pxd_sub")
        case .слоты: return сайт("upg_slots_note_hint")
        case .комбо: return сайт("upg_combo_intro")
        case .пакетИИ: return сайт("upg_ai_intro2")
        case .продвижение: return сайт("promo_free_bumps")
        case .топРезюме: return nil
        case .свойИИ: return т("own_ai_intro")
        }
    }

    /// .cabset: значок-плитка, название услуги и пояснение сайта.
    private var шапка: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ЗначокСтрокиСайта(значок: вид.значок, цвет: вид == .про ? Theme.золото : КраскаСтрокКабинета.значок)
                Text(заголовок)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                if вид == .про && бизнес.страница?.proАктивен == true && бизнес.страница?.proБесплатно == false {
                    МеткаБизнеса(текст: сайт("pxd_owned"), золото: true)
                }
            }
            if let подзаголовок {
                Text(подзаголовок)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Выбор объявления (продвижение без готового)

    private var выборОбъявления: some View {
        КарточкаБизнеса(т("pick_listing"), значок: "megaphone") {
            if let объявления {
                if объявления.isEmpty {
                    Text(т("pick_listing_none"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(объявления) { объявление in
                        строкаОбъявления(объявление)
                    }
                }
            } else {
                SiteSpinner()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func строкаОбъявления(_ объявление: МоёОбъявление) -> some View {
        let выбрано = цель == объявление.id
        let имя = объявление.название.isEmpty ? объявление.бренд : объявление.название
        return Button {
            цель = объявление.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: выбрано ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(имя)
                    .font(.system(size: 14, weight: выбрано ? .bold : .regular))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if объявление.топ { МеткаБизнеса(текст: "ТОП", золото: true) }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрано ? .isSelected : [])
    }

    // MARK: Товары

    /// Единое правило (ДоступПокупкиApple): есть загруженные товары — строки; ещё грузятся (не дольше срока загрузки) —
    /// короткий индикатор; не загрузилось или товаров нет — «Покупки временно недоступны», без кнопок.
    @ViewBuilder
    private var товарыБлок: some View {
        let видимые = строки.filter { покупки.товары[$0.товар.id] != nil }
        if !видимые.isEmpty {
            ForEach(видимые) { строка in
                строкаТовара(строка)
            }
        } else if покупки.грузится || !покупки.загружено {
            HStack(spacing: 10) {
                SiteSpinner()
                Text(т("price_loading"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            НетПокупокApple()
        }
    }

    /// Что показать по каждому товару услуги — словами сайта, если страница кабинета их отдала.
    private var строки: [СтрокаТовараApple] {
        let с = бизнес.страница
        switch вид {
        case .продвижение:
            return ПродуктыApple.товары(.продвижение).map { товар -> СтрокаТовараApple in
                строкаПродвижения(товар, с)
            }
        case .про:
            return ПродуктыApple.товары(.про).map { товар -> СтрокаТовараApple in
                let тариф = с?.тарифыПРО.first(where: { $0.уровень == 1 })
                return СтрокаТовараApple(товар: товар, заголовок: тариф?.название ?? имяИзМагазина(товар),
                                         подробно: свойстваПРО(с, уровень: тариф?.уровень ?? 1))
            }
        case .слоты:
            let бесплатно = с?.бесплатныхСлотов ?? 5
            let тарифы = (бизнес.слоты?.тарифы ?? []).filter { $0.цена > 0 }
            let товары: [ТоварApple] = тарифы.isEmpty
                ? ПродуктыApple.товары(.слоты)
                : тарифы.map { ПродуктыApple.товарСлотов($0.слотов) }
            return товары.map { товар -> СтрокаТовараApple in
                let слотов = Int(товар.ключ) ?? 0
                let заголовок = ПокупкиAppleText.т("slots_row", ["n": String(бесплатно + слотов)])
                let подробно = ПокупкиAppleText.т("slots_row_sub", ["n": String(слотов)])
                return СтрокаТовараApple(товар: товар, заголовок: заголовок, подробно: [подробно])
            }
        case .комбо:
            return ПродуктыApple.товары(.комбо).map { товар -> СтрокаТовараApple in
                строкаКомбо(товар, с)
            }
        case .пакетИИ:
            return ПродуктыApple.товары(.пакетИИ).map { товар -> СтрокаТовараApple in
                guard let пакет = с?.пакетыИИ.first(where: { $0.id == товар.ключ }) else {
                    return СтрокаТовараApple(товар: товар, заголовок: имяИзМагазина(товар), подробно: [])
                }
                let дни = String(пакет.дней)
                return СтрокаТовараApple(товар: товар,
                                         заголовок: сайт("upg_ai_pack").replacingOccurrences(of: "{d}", with: дни),
                                         подробно: [ПокупкиAppleText.т("ai_row_sub", ["d": дни])])
            }
        case .топРезюме:
            return ПродуктыApple.товары(.топРезюме).map { товар -> СтрокаТовараApple in
                СтрокаТовараApple(товар: товар, заголовок: т("resume_top_title"), подробно: [т("resume_top_detail")])
            }
        case .свойИИ:
            /* Цена сайта (990 ₸) здесь не показывается: только displayPrice App Store; пробного периода в приложении нет. */
            return ПродуктыApple.товары(.свойИИ).map { товар -> СтрокаТовараApple in
                СтрокаТовараApple(товар: товар, заголовок: т("own_ai_row"), подробно: [т("own_ai_row_sub")])
            }
        }
    }

    private func строкаПродвижения(_ товар: ТоварApple, _ с: СтраницаБизнеса?) -> СтрокаТовараApple {
        if товар.ключ == "bump1" {
            return СтрокаТовараApple(товар: товар, заголовок: т("bump_title"), подробно: [т("bump_detail")])
        }
        guard let пакет = с?.пакеты.first(where: { $0.id == товар.ключ }) else {
            return СтрокаТовараApple(товар: товар, заголовок: имяИзМагазина(товар), подробно: [])
        }
        let дни = String(пакет.днейТоп)
        let строка = пакет.поднятий > 0
            ? ПокупкиAppleText.т("promo_detail", ["d": дни, "b": String(пакет.поднятий)])
            : ПокупкиAppleText.т("promo_detail_top", ["d": дни])
        return СтрокаТовараApple(товар: товар, заголовок: пакет.подпись, подробно: [строка])
    }

    private func строкаКомбо(_ товар: ТоварApple, _ с: СтраницаБизнеса?) -> СтрокаТовараApple {
        let бесплатно = с?.бесплатныхСлотов ?? 5
        guard let пакет = с?.комбо.first(where: { $0.id == товар.ключ }) else {
            return СтрокаТовараApple(товар: товар, заголовок: имяИзМагазина(товар), подробно: [])
        }
        let своё = сайт("combo_" + пакет.id)
        let название = своё == "combo_" + пакет.id ? (пакет.подпись.isEmpty ? пакет.id : пакет.подпись) : своё
        let заголовок = сайт("upg_combo_name").replacingOccurrences(of: "{n}", with: название)
        let подробно = БизнесText.т("upg_combo_feat", ["n": String(бесплатно + пакет.слотов),
                                                       "d": String(пакет.днейИИ)])
        return СтрокаТовараApple(товар: товар, заголовок: заголовок, подробно: [подробно])
    }

    /// Что входит в PRO — как pxdRender сайта: слоты, дни Kliko AI, pro_t1_sub.
    private func свойстваПРО(_ с: СтраницаБизнеса?, уровень: Int) -> [String] {
        var список: [String] = []
        if let с {
            let слотов = с.слотыПРО[уровень] ?? 0
            if слотов >= с.безлимитСлотов {
                список.append(сайт("pxd_slots_unlim"))
            } else if слотов > 0 {
                список.append(сайт("pxd_slots_upto").replacingOccurrences(of: "{n}",
                                                                         with: String(с.бесплатныхСлотовПРО + слотов)))
            }
            let дней = с.днейИИПРО[уровень] ?? 0
            if дней > 0 {
                список.append(сайт("pxd_ai_days").replacingOccurrences(of: "{n}", with: String(дней)))
            }
        }
        for кусок in сайт("pro_t1_sub").split(separator: "|") {
            let строка = кусок.trimmingCharacters(in: .whitespaces)
            if !строка.isEmpty { список.append(строка) }
        }
        return список
    }

    /// Имя товара из App Store, если страница кабинета не отдала своё.
    private func имяИзМагазина(_ товар: ТоварApple) -> String {
        let имя = покупки.товары[товар.id]?.displayName ?? ""
        return имя.isEmpty ? товар.ключ : имя
    }

    /// Срок подписки словами: «1 мес.», «3 мес.», «1 г.» (Product.SubscriptionPeriod).
    private func период(_ продукт: Product) -> String? {
        guard let п = продукт.subscription?.subscriptionPeriod else { return nil }
        let единица: String
        switch п.unit {
        case .day: единица = т("unit_day")
        case .week: единица = т("unit_week")
        case .month: единица = т("unit_month")
        case .year: единица = т("unit_year")
        @unknown default: единица = т("unit_month")
        }
        return String(п.value) + " " + единица
    }

    /// Строка «срок»: подписка — «Подписка · 1 мес. · продлевается автоматически», иначе «Разовая покупка».
    private func строкаСрока(_ товар: ТоварApple, _ продукт: Product) -> String {
        if товар.тип == .подписка, let срок = период(продукт) {
            return ПокупкиAppleText.т("sub_period", ["n": срок])
        }
        return т("one_time")
    }

    private func строкаТовара(_ строка: СтрокаТовараApple) -> some View {
        let продукт = покупки.товары[строка.товар.id]
        let занято = покупки.покупается == строка.товар.id
        let нельзя = продукт == nil || покупки.покупается != nil || (выбиратьОбъявление && цель.isEmpty)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(строка.заголовок)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let продукт {
                    Text(продукт.displayPrice)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(строка.товар.тип == .подписка ? Theme.золото : Theme.акцент)
                        .monospacedDigit()
                }
            }
            if let продукт {
                Text(строкаСрока(строка.товар, продукт))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(Array(строка.подробно.enumerated()), id: \.offset) { _, текст in
                Label {
                    Text(текст)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            КнопкаПокупкиApple(подпись: подписьКнопки(строка.товар, продукт), занято: занято) {
                купить(строка.товар)
            }
            .disabled(нельзя)
            .opacity(нельзя && !занято ? 0.55 : 1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(вид == .про ? Theme.топРамка : Theme.линия, lineWidth: 1.5)
        }
    }

    private func подписьКнопки(_ товар: ТоварApple, _ продукт: Product?) -> String {
        guard let продукт else { return т("buy") }
        if товар.тип == .подписка {
            let цена = продукт.displayPrice + " / " + (период(продукт) ?? т("unit_month"))
            return ПокупкиAppleText.т("subscribe_for", ["p": цена])
        }
        return ПокупкиAppleText.т("buy_for", ["p": продукт.displayPrice])
    }

    // MARK: Итог

    @ViewBuilder
    private var итогБлок: some View {
        if let итог {
            ЗаметкаБизнеса(итог, тон: итогТон, значок: значокИтога)
        }
        if нуженВход {
            КнопкаБизнеса(подпись: т("login")) { войти() }
        }
    }

    private var значокИтога: String {
        switch итогТон {
        case .хорошо: return "checkmark.circle"
        case .плохо: return "exclamationmark.triangle"
        case .предупреждение: return "clock.arrow.circlepath"
        case .инфо, .серый: return "info.circle"
        }
    }

    // MARK: Подвал: оплата, условия, восстановление

    private var подвал: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("pay_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if вид == .про {
                Text(т("sub_terms"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                КнопкаБизнеса(подпись: т("manage_subs"), второстепенная: true) { подпискиОткрыты = true }
            }
            КнопкаБизнеса(подпись: т("restore"), занято: покупки.восстанавливаем, второстепенная: true) {
                восстановить()
            }
            СсылкиУсловийApple(подписка: вид == .про)
        }
        .padding(.top, 4)
    }

    // MARK: Действия

    private func загрузить() async {
        var дополнительно: [String] = []
        if вид == .слоты {
            await бизнес.загрузитьУслуги()
            for тариф in (бизнес.слоты?.тарифы ?? []) where тариф.цена > 0 {
                дополнительно.append(ПродуктыApple.товарСлотов(тариф.слотов).id)
            }
        } else if бизнес.страница == nil {
            await бизнес.загрузитьСтраницу()
        }
        await покупки.загрузитьТовары(дополнительно: дополнительно)
        if выбиратьОбъявление { await загрузитьОбъявления() }
    }

    private func загрузитьОбъявления() async {
        guard let j = try? await МоиОбъявленияAPI.получить("cabinet.php?action=my_items") else {
            объявления = []
            return
        }
        let сырые = (j["items"] as? [[String: Any]]) ?? []
        let готовые = сырые.compactMap { МоёОбъявление($0) }
        let опубликованные = готовые.filter { $0.статус == "approved" && !$0.образец }
        объявления = опубликованные
        if цель.isEmpty, опубликованные.count == 1, let единственное = опубликованные.first {
            цель = единственное.id
        }
    }

    private func купить(_ товар: ТоварApple) {
        итог = nil
        нуженВход = false
        let объект = цель
        Task { @MainActor in
            let результат = await ПокупкиApple.shared.купить(товар, цель: объект)
            показатьИтог(результат)
        }
    }

    private func показатьИтог(_ результат: ПокупкиApple.Итог) {
        switch результат {
        case .куплено:
            итог = т("done")
            итогТон = .хорошо
            if вид == .свойИИ { Task { @MainActor in await СвойИИМодель.shared.обновить() } }
            Task { @MainActor in
                await БизнесМодель.shared.загрузитьСтраницу()
                await МоиОбъявленияМодель.shared.загрузить(страницу: false)
            }
        case .отложено:
            итог = т("saved_later") + "\n" + т("saved_later_sub")
            итогТон = .предупреждение
        case .ждётОдобрения:
            итог = т("ask_to_buy")
            итогТон = .инфо
        case .отменено:
            итог = т("cancelled")
            итогТон = .серый
        case .нуженВход:
            итог = т("need_login")
            итогТон = .инфо
            нуженВход = true
        case .ошибка(let текст):
            итог = текст
            итогТон = .плохо
        }
    }

    private func восстановить() {
        итог = nil
        Task { @MainActor in
            let текст = await ПокупкиApple.shared.восстановить()
            итог = текст
            итогТон = .инфо
        }
    }

    private func войти() {
        ВходПоверх.показать {
            нуженВход = false
            итог = nil
        }
    }
}
