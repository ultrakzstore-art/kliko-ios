import SwiftUI
import UIKit
import StoreKit

/**
 ОКНО ПОКУПКИ УСЛУГИ ЧЕРЕЗ APP STORE — только при Config.цифровыеПокупки (правило 3.1.1).

 Одно окно на все платные услуги сайта; открывается поверх любого экрана (ПоверхВсего): из «Платных услуг» (кнопки блоков
 PRO, «Продвижение», «Слоты объявлений», «Комбо-пакеты», «Пакеты Kliko AI»), из «Моих объявлений» («Продвинуть»,
 «Расширить», «В ТОП» у резюме), из мастера подачи (окно лимита слотов, «Продвинуть объявление» на экране «Опубликовано»).

 Что есть что — слова сайта (БизнесText: PROMO_CFG, COMBO_PACKS, AI_PACKS, PRO_TIERS и slots.tiers со страницы
 кабинета и из my_items). Цена — ТОЛЬКО product.displayPrice из App Store: валюта и формат витрины человека, тенге
 сайта здесь не показываются. Товара нет в App Store (не заведён в App Store Connect) — строки нет.
 Для продвижения без готового объявления окно само предлагает выбрать одно из опубликованных (my_items, approved) —
 сайт продвигает только опубликованные.
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

    private static let соглашение = URL(string: "https://kliko.kz/soglashenie.php")
    private static let политика = URL(string: "https://kliko.kz/privacy.php")
    private static let условияApple = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    private static let подпискиApple = URL(string: "https://apps.apple.com/account/subscriptions")

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
                    if let итог {
                        ЗаметкаБизнеса(итог, тон: итогТон, значок: "info.circle")
                    }
                    if нуженВход {
                        КнопкаБизнеса(подпись: т("login")) { войти() }
                    }
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
                }
            }
        }
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
        }
    }

    @ViewBuilder
    private var шапка: some View {
        VStack(alignment: .leading, spacing: 6) {
            if вид == .про {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Theme.золото)
                        .accessibilityHidden(true)
                    Text(сайт("pxd_eyebrow"))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.золото)
                    Spacer(minLength: 6)
                    if бизнес.страница?.proАктивен == true && бизнес.страница?.proБесплатно == false {
                        МеткаБизнеса(текст: сайт("pxd_owned"), золото: true)
                    }
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

    @ViewBuilder
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
                ProgressView()
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

    @ViewBuilder
    private var товарыБлок: some View {
        let видимые = строки.filter { покупки.товары[$0.товар.id] != nil }
        if !покупки.загружено {
            HStack(spacing: 10) {
                ProgressView()
                Text(т("price_loading"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if видимые.isEmpty {
            ЗаметкаБизнеса(покупки.магазинНедоступен ? т("store_unavailable") : т("not_in_store"),
                           тон: .предупреждение, значок: "bag")
        } else {
            ForEach(видимые) { строка in
                строкаТовара(строка)
            }
        }
    }

    /// Что показать по каждому товару услуги — словами сайта, если страница кабинета их отдала.
    private var строки: [СтрокаТовараApple] {
        let с = бизнес.страница
        switch вид {
        case .продвижение:
            return ПродуктыApple.товары(.продвижение).map { товар -> СтрокаТовараApple in
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
            let бесплатно = с?.бесплатныхСлотов ?? 5
            return ПродуктыApple.товары(.комбо).map { товар -> СтрокаТовараApple in
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
        }
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
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.золото)
                }
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
            КнопкаБизнеса(подпись: подписьКнопки(строка.товар, продукт), занято: занято) {
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
            let цена = продукт.displayPrice + " " + сайт("pro_per_month")
            return ПокупкиAppleText.т("subscribe_for", ["p": цена])
        }
        return ПокупкиAppleText.т("buy_for", ["p": продукт.displayPrice])
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
                ссылка(т("manage_subs"), Self.подпискиApple)
                ссылка(т("apple_eula"), Self.условияApple)
            }
            ссылка(т("terms"), Self.соглашение)
            ссылка(т("privacy"), Self.политика)
            КнопкаБизнеса(подпись: т("restore"), занято: покупки.восстанавливаем, второстепенная: true) {
                восстановить()
            }
        }
        .padding(.top, 4)
    }

    private func ссылка(_ подпись: String, _ адрес: URL?) -> some View {
        Button {
            открыть(адрес)
        } label: {
            Text(подпись)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .underline()
        }
        .buttonStyle(.plain)
    }

    /// Страница сайта — своим путём (окно закрывается, страница открывается в приложении); Apple — системой.
    private func открыть(_ адрес: URL?) {
        guard let адрес else { return }
        if let хост = адрес.host?.lowercased(), хост == "kliko.kz" || хост == "www.kliko.kz" {
            закрыть()
            ПоверхВсего.открытьАдрес(адрес)
        } else {
            UIApplication.shared.open(адрес)
        }
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
        объявления = готовые.filter { $0.статус == "approved" && !$0.образец }
        if цель.isEmpty, let единственное = объявления?.first, объявления?.count == 1 {
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
            Task { @MainActor in await БизнесМодель.shared.загрузитьСтраницу() }
        case .отложено:
            итог = т("saved_later") + "\n" + т("saved_later_sub")
            итогТон = .предупреждение
        case .ждётОдобрения:
            итог = т("ask_to_buy")
            итогТон = .инфо
        case .отменено:
            итог = nil
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
