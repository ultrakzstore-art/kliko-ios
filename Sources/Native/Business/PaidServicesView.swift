import SwiftUI
import UIKit

/**
 «ПЛАТНЫЕ УСЛУГИ» — ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Только показ.

 Что сайт показывает о платных услугах, собранное на одном экране (у сайта это окна поверх кабинета: showProOffer,
 openPromote, openUpgrade с вкладками «Слоты» / «Комбо» / «Kliko AI»), — только описание, без цен:
   · «Kliko PRO · Магазин» — «Активен ещё N дн. · до …», что входит (PRO_SLOTS, PRO_AI_DAYS, pro_t1_sub);
   · «Продвижение» — бесплатные авто-поднятия;
   · «Слоты объявлений» — slots из my_items: «Сейчас активно», бесплатный лимит;
   · «Комбо-пакеты» — COMBO_PACKS: что входит;
   · «Пакеты Kliko AI» — квота CAB_AI (как карточка «Доступно»), запуски глубокого разбора (ai_scan_credits).
 Покупка — только через App Store (правило 3.1.1) и только при Config.цифровыеПокупки: кнопка блока (ЦифроваяПокупка)
 открывает окно покупки ЛистУслугиApple (цена — Product.displayPrice), внизу — «Восстановить покупки» и «Управление
 подпиской» (КарточкаПокупокApple). Выключено — под каждым блоком только текст сайта «Эта возможность недоступна
 в приложении.», без кнопок и без ссылок на оплату на сайте.
 */
struct ЭкранПлатныхУслуг: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var входОткрыт = false

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("paid_title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await модель.загрузитьУслуги() }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузитьУслуги() }
                })
            }
            .overlay(alignment: .bottom) {
                if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
            }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.загрузка {
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        case .ошибка(let текст):
            if let с = модель.страница {
                список(с)
            } else {
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await модель.загрузитьУслуги() } })
            }
        case .нет, .идёт, .готово:
            if let с = модель.страница {
                список(с)
            } else {
                ЗагрузкаБизнеса()
            }
        }
    }

    private func список(_ с: СтраницаБизнеса) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                БлокПРО(с: с)
                if !модель.кредитыApple.isEmpty { БлокКредитовApple() }
                БлокПродвижения()
                БлокСлотов(с: с, слоты: модель.слоты, открыть: открыть)
                if !с.комбо.isEmpty { БлокКомбо(с: с) }
                БлокИИ(с: с, запусков: модель.запусков)
                if Config.цифровыеПокупки { КарточкаПокупокApple() }
            }
            .padding(12)
        }
        .refreshable { await модель.загрузитьУслуги() }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let u = Config.страницаСайта("cabinet.php") {
            открыть(u)
        }
    }
}

// MARK: - Kliko PRO

/// Окно showProOffer сайта сведениями: шапка, срок, что входит. Цены тарифов сайта не показываются: при
/// Config.цифровыеПокупки цена — в окне покупки App Store.
private struct БлокПРО: View {
    let с: СтраницаБизнеса

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// proTierFit(PRO_TIER_CUR > 0 ? PRO_TIER_CUR : 1) — тариф, который окно сайта открывает выбранным.
    private var выбранный: Int {
        let уровни = с.тарифыПРО.map { $0.уровень }
        let хочу = с.уровеньПРО > 0 ? с.уровеньПРО : 1
        return уровни.contains(хочу) ? хочу : (уровни.first ?? 1)
    }

    /// Уровень, по которому считаются слоты и дни Kliko AI (pxdRender: один тариф — PRO_BUY_TIER).
    private var уровеньСвойств: Int {
        if с.тарифыПРО.count <= 1 && с.уровеньПокупки >= 1 { return с.уровеньПокупки }
        return выбранный
    }

    /// «Активен ещё N дн. · до …» — только у купленного PRO (не бесплатного и не пробного), как pxdRender.
    private var строкаСрока: String? {
        guard с.уровеньПРО >= 1, !с.proБесплатно, !с.proПробный else { return nil }
        if с.тарифыПРО.count > 1 && с.уровеньПРО != выбранный { return nil }
        guard let дней = с.proДнейОсталось else { return т("pro_lifetime") }
        var строка = т("pxd_active_left").replacingOccurrences(of: "{n}", with: String(max(0, дней)))
        if let дата = СделкиФормат.дата(с.proДо) {
            let ф = DateFormatter()
            ф.locale = Locale(identifier: "ru_RU")
            ф.dateFormat = "dd.MM.yyyy"
            строка += " · " + т("pxd_until") + " " + ф.string(from: дата)
        }
        return строка
    }

    private var свойства: [String] {
        var список: [String] = []
        let слотов = с.слотыПРО[уровеньСвойств] ?? 0
        if слотов >= с.безлимитСлотов {
            список.append(т("pxd_slots_unlim"))
        } else {
            список.append(т("pxd_slots_upto").replacingOccurrences(of: "{n}",
                                                                   with: СделкиФормат.деньги(с.бесплатныхСлотовПРО + слотов)))
        }
        let дней = с.днейИИПРО[уровеньСвойств] ?? 0
        if дней > 0 {
            список.append(т("pxd_ai_days").replacingOccurrences(of: "{n}", with: String(дней)))
        }
        for кусок in т("pro_t1_sub").split(separator: "|") {
            let строка = кусок.trimmingCharacters(in: .whitespaces)
            if !строка.isEmpty { список.append(строка) }
        }
        return список
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            шапка
            if let срок = строкаСрока {
                Text(срок)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(свойства.enumerated()), id: \.offset) { номер, строка in
                    Label {
                        Text(строка)
                            .font(.system(size: 14, weight: номер < 2 ? .bold : .regular))
                            .foregroundStyle(Theme.текст)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: номер < 2 ? "star.fill" : "checkmark")
                            .foregroundStyle(номер < 2 ? Theme.золото : Theme.акцент)
                    }
                }
            }
            /* PRO по подписке App Store (PRO_SRC = "apple") — продлевает Apple: вместо покупки — управление подпиской.
               PRO бесплатный (PRO_FREE) — покупать нечего. */
            if с.proИсточник == "apple" {
                ПодпискаAppStoreПРО()
            } else if !(Config.цифровыеПокупки && с.proБесплатно) {
                ЦифроваяПокупка(услуга: .про, подпись: т("cab_get_pro"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.топРамка, lineWidth: 1.5)
        }
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(Theme.золото)
                    .accessibilityHidden(true)
                Text(т("pxd_eyebrow"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.золото)
                Spacer(minLength: 6)
                if с.proАктивен { МеткаБизнеса(текст: т("pxd_owned"), золото: true) }
            }
            (Text(т("pxd_h1a") + " ") + Text(т("pxd_h1b")).foregroundColor(Theme.золото))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(т("pxd_sub"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// «Подписка App Store — управлять в настройках iPhone» и кнопка на страницу подписок Apple ID (как в кабинете сайта).
private struct ПодпискаAppStoreПРО: View {
    static let адрес = URL(string: "https://apps.apple.com/account/subscriptions")

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("apl_pro_title"))
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Theme.текст)
            ЗаметкаБизнеса(т("apl_pro_sub"), тон: .инфо, значок: "apple.logo")
            КнопкаБизнеса(подпись: т("apl_pro_btn"), второстепенная: true) {
                guard let адрес = ПодпискаAppStoreПРО.адрес else { return }
                UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
            }
        }
    }
}

// MARK: - Оплачено в App Store, не применено

/// Покупки продвижения / ТОПа резюме, цель которых не подошла: выбрать объявление (резюме) и «Применить» — один раз.
private struct БлокКредитовApple: View {
    @ObservedObject private var модель = БизнесМодель.shared
    @State private var выбор: [String: String] = [:]
    @State private var идёт: String? = nil
    @State private var ошибка: [String: String] = [:]

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    private func название(_ к: КредитApple) -> String {
        if к.услуга == "resume_top" { return БизнесText.т("apl_cr_resume", ["d": String(к.дней)]) }
        if к.днейТоп > 0 && к.поднятий > 0 {
            return БизнесText.т("apl_cr_promo", ["d": String(к.днейТоп), "b": String(к.поднятий)])
        }
        if к.днейТоп > 0 { return БизнесText.т("apl_cr_top", ["d": String(к.днейТоп)]) }
        return т("apl_cr_bump")
    }

    private func цели(_ к: КредитApple) -> [ЦельКредитаApple] {
        модель.целиКредитов[к.услуга] ?? []
    }

    private func выбрано(_ к: КредитApple) -> String {
        if let своё = выбор[к.id] { return своё }
        let список = цели(к)
        return список.count == 1 ? список[0].id : ""
    }

    var body: some View {
        КарточкаБизнеса(т("apl_cr_title"), значок: "checkmark.seal") {
            Text(т("apl_cr_sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(модель.кредитыApple) { к in
                строка(к)
            }
        }
    }

    private func строка(_ к: КредитApple) -> some View {
        let список = цели(к)
        let подсказка = т(к.услуга == "resume_top" ? "apl_cr_pick_job" : "apl_cr_pick")
        return VStack(alignment: .leading, spacing: 8) {
            Text(название(к))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
            if список.isEmpty {
                Text(т("apl_cr_none"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                Picker(подсказка, selection: Binding<String>(
                    get: { выбрано(к) },
                    set: { выбор[к.id] = $0 }
                )) {
                    Text(подсказка).tag("")
                    ForEach(список) { ц in
                        Text(ц.название).tag(ц.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.акцент)
                if let текст = ошибка[к.id] {
                    ЗаметкаБизнеса(текст, тон: .предупреждение, значок: "exclamationmark.triangle")
                }
                КнопкаБизнеса(подпись: т("apl_cr_apply"), занято: идёт == к.id) {
                    применить(к)
                }
                .disabled(идёт != nil)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private func применить(_ к: КредитApple) {
        let цель = выбрано(к)
        guard !цель.isEmpty else {
            ошибка[к.id] = т(к.услуга == "resume_top" ? "apl_cr_pick_job" : "apl_cr_pick")
            return
        }
        ошибка[к.id] = nil
        идёт = к.id
        Task { @MainActor in
            let итог = await модель.применитьКредитApple(к, цель: цель)
            идёт = nil
            if let итог { ошибка[к.id] = итог }
        }
    }
}

// MARK: - Продвижение

/// Окно openPromote сайта сведениями: бесплатные авто-поднятия; покупка ТОПа — окно App Store (с выбором объявления).
private struct БлокПродвижения: View {
    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        КарточкаБизнеса(т("promo_title"), значок: "arrow.up.circle") {
            ЗаметкаБизнеса(т("promo_free_bumps"), тон: .хорошо, значок: "arrow.triangle.2.circlepath")
            ЦифроваяПокупка(услуга: .продвижение, подпись: т("promo_boost_v"))
        }
    }
}

// MARK: - Слоты

/// Вкладка «Слоты» окна openUpgrade сайта (upgSlotsPaneHTML) сведениями, без тарифов с ценами.
private struct БлокСлотов: View {
    let с: СтраницаБизнеса
    let слоты: СлотыТарифа?
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Окно «Стать продавцом» (ЛистВерификации); сама проверка eGov — страницей сайта из него.
    @MainActor
    private func пройтиВерификацию() {
        let u = Config.страницаСайта("cabinet?go=verify")
        if !ОкнаПриложения.shared.показать(.верификация, запасной: u), let u { открыть(u) }
    }

    var body: some View {
        КарточкаБизнеса(т("upg_slots_title"), значок: "square.stack.3d.up") {
            if let слоты {
                СтрокаЗначенияБизнеса(название: т("upg_now_active").trimmingCharacters(in: .whitespaces),
                                      значение: String(слоты.занято) + " " + т("slot_of") + " " + String(слоты.лимит))
                VStack(alignment: .leading, spacing: 2) {
                    СтрокаЗначенияБизнеса(название: т("upg_slots_free_lbl"), значение: String(слоты.бесплатно))
                    Text(т("upg_slots_note_hint"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                if !с.верифицирован {
                    КнопкаСайтаБизнеса(подпись: т("upg_verify_bonus"), главная: false) { пройтиВерификацию() }
                }
                ЦифроваяПокупка(услуга: .слоты, подпись: т("upg_choose"))
            } else {
                Text(т("upg_slots_in_section"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }
}

// MARK: - Комбо

/// Вкладка «Комбо» окна openUpgrade (upgComboPaneHTML) сведениями: что входит, без цен.
private struct БлокКомбо: View {
    let с: СтраницаБизнеса

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// _comboName: tt("combo_<key>") или label сервера.
    private func имя(_ пакет: КомбоПакет) -> String {
        let своё = т("combo_" + пакет.id)
        let название = своё == "combo_" + пакет.id ? (пакет.подпись.isEmpty ? пакет.id : пакет.подпись) : своё
        return т("upg_combo_name").replacingOccurrences(of: "{n}", with: название)
    }

    var body: some View {
        КарточкаБизнеса(т("upg_combo_t"), значок: "square.stack.3d.up.fill") {
            Text(т("upg_combo_sub"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Text(т("upg_combo_intro"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(с.комбо) { пакет in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(имя(пакет))
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        Text(БизнесText.т("upg_combo_feat", ["n": String(с.бесплатныхСлотов + пакет.слотов),
                                                             "d": String(пакет.днейИИ)]))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    Spacer(minLength: 6)
                }
                .padding(12)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            ЦифроваяПокупка(услуга: .комбо, подпись: т("bc_order"))
        }
    }
}

// MARK: - Kliko AI

/// Квота Kliko AI (сегмент карточки «Доступно», renderSlotBanner) и вкладка «Kliko AI» окна openUpgrade — без цен
/// сайта: пакеты Kliko AI — окно покупки App Store при Config.цифровыеПокупки.
private struct БлокИИ: View {
    let с: СтраницаБизнеса
    let запусков: Int?

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Строка квоты: бесплатно — free_t; оплачено — «Безлимит ✓»; иначе «Осталось N / M» или «Закончились».
    private var квота: String? {
        let к = с.квота
        guard к.показ else { return nil }
        if к.бесплатно { return к.подпись + ": " + к.бесплатноЗаголовок }
        if к.платно { return к.подпись + ": " + к.безлимит + " ✓" }
        if к.осталось > 0 {
            return к.подпись + ": " + к.осталосьСлово + " " + String(к.осталось) + " / " + String(к.лимит)
        }
        return к.подпись + ": " + т("ai_over")
    }

    var body: some View {
        КарточкаБизнеса(т("upg_ai_packs"), значок: "sparkles") {
            if let квота {
                ЗаметкаБизнеса(квота, тон: с.квота.платно || с.квота.бесплатно ? .хорошо : .инфо, значок: "sparkles")
            }
            if let запусков, запусков > 0 {
                Text(т("credits_left").replacingOccurrences(of: "{n}", with: String(запусков)))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            Text(с.иИБесплатно ? т("upg_ai_intro_free") : т("upg_ai_intro2"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ЦифроваяПокупка(услуга: .пакетИИ)
        }
    }
}
