import SwiftUI

/**
 «ПЛАТНЫЕ УСЛУГИ» — ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Только показ.

 Что сайт показывает о платных услугах, собранное на одном экране (у сайта это окна поверх кабинета: showProOffer,
 openPromote, openUpgrade с вкладками «Слоты» / «Комбо» / «Kliko AI»):
   · «Kliko PRO · Магазин» — тарифы PRO_TIERS, цена (PRO_FREE — «Бесплатно», AI_DISC — зачёркнутая), «Активен ещё N дн. ·
     до …», что входит (PRO_SLOTS, PRO_AI_DAYS, pro_t1_sub) — как pxdRender;
   · «Продвижение» — бесплатные авто-поднятия, скидка, четыре пакета PROMO_CFG: цена — серверная котировка promo_quote,
     пока её нет — формула сайта (promoDisc) со старой зачёркнутой; нехватка на балансе — текст сайта;
   · «Слоты объявлений» — slots из my_items: «Сейчас активно», бесплатный лимит, тарифы со скидкой (upgSlotsPaneHTML);
   · «Комбо-пакеты» — COMBO_PACKS (upgComboPaneHTML);
   · «Пакеты Kliko AI» — квота CAB_AI (как карточка «Доступно»), AI_PACKS с ценой в день и «Выгоднее всего»
     (upgAiPaneHTML), запуски глубокого разбора (ai_scan_credits).
 🔴 Купить здесь нельзя (Config.цифровыеПокупки = false, правило 3.1.1): под каждым блоком — текст сайта «Эта возможность
 недоступна в приложении.» и кнопка в кабинет сайта (ЦифроваяПокупка). Запросов покупки в этом экране нет вовсе.
 Свои слова приложения — только заголовок экрана и «Открыть в кабинете на сайте»; остальное — слова сайта.
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
                БлокПРО(с: с, открыть: открыть)
                БлокПродвижения(с: с, котировки: модель.котировки, безОтвета: модель.котировкиБезОтвета,
                                открыть: открыть)
                БлокСлотов(с: с, слоты: модель.слоты, открыть: открыть)
                if !с.комбо.isEmpty { БлокКомбо(с: с, открыть: открыть) }
                БлокИИ(с: с, запусков: модель.запусков, открыть: открыть)
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

/// Окно showProOffer сайта сведениями: шапка, тарифы, срок, что входит, pro_note.
private struct БлокПРО: View {
    let с: СтраницаБизнеса
    let открыть: (URL) -> Void

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
            ForEach(с.тарифыПРО) { тариф in
                строкаТарифа(тариф)
            }
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
            ЗаметкаБизнеса(т("pro_note"), тон: .серый, значок: "checkmark.shield")
            ЦифроваяПокупка(подпись: с.proБесплатно ? т("pro_activate_free") : т("cab_get_pro"), путь: "cabinet.php",
                            открыть: открыть)
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

    /// Цена тарифа: PRO_FREE — «Бесплатно»; AI_DISC — зачёркнутая и со скидкой (pxdEff); «/ мес».
    private func строкаТарифа(_ тариф: ТарифПРО) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(тариф.название)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            if с.уровеньПРО == тариф.уровень { МеткаБизнеса(текст: т("pro_your_tier")) }
            Spacer(minLength: 6)
            ЦенаБизнеса(старая: с.скидкаИИ > 0 ? тариф.цена : nil, цена: с.соСкидкойИИ(тариф.цена),
                        бесплатно: с.proБесплатно ? т("pro_free") : nil)
            if !с.proБесплатно {
                Text(т("pro_per_month"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Продвижение

/// Окно openPromote сайта сведениями: факты, «Готовые пакеты», баланс. Своих ползунков нет — они собирают покупку.
private struct БлокПродвижения: View {
    let с: СтраницаБизнеса
    let котировки: [String: КотировкаТопа]
    let безОтвета: Set<String>
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Лента «Максимум» — у самого дорогого пакета (promo_max_rib).
    private var самыйДорогой: String {
        с.пакеты.max(by: { $0.цена < $1.цена })?.id ?? ""
    }

    /// «Баланс кошелька» — из первой пришедшей котировки (у сайта — walletInfo.balance).
    private var баланс: Int? {
        for пакет in с.пакеты {
            if let к = котировки[пакет.id] { return к.баланс }
        }
        return nil
    }

    var body: some View {
        КарточкаБизнеса(т("promo_title"), значок: "arrow.up.circle") {
            ЗаметкаБизнеса(т("promo_free_bumps"), тон: .хорошо, значок: "arrow.triangle.2.circlepath")
            if с.скидкаПродвижения > 0 {
                СтрокаЗначенияБизнеса(название: т("promo_your_disc").replacingOccurrences(of: ":", with: ""),
                                      значение: "−" + String(с.скидкаПродвижения) + "%")
            }
            if с.ценаДняТоп > 0 {
                Text(т("top_from").replacingOccurrences(of: "{n}", with: СделкиФормат.деньги(с.ценаДняТоп)))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !с.пакеты.isEmpty {
                Text(т("promo_packages"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текстВторой)
                ForEach(с.пакеты) { пакет in
                    строкаПакета(пакет)
                }
            }
            if let баланс {
                Label(т("promo_wallet_bal") + СделкиФормат.тенге(баланс), systemImage: "wallet.pass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            ЦифроваяПокупка(подпись: т("promo_boost_v"), путь: "cabinet.php?go=promote", открыть: открыть)
        }
    }

    private func строкаПакета(_ пакет: ПакетПродвижения) -> some View {
        let котировка = котировки[пакет.id]
        let цена = котировка?.цена ?? с.соСкидкойПродвижения(пакет.цена)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(пакет.подпись)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if пакет.id == самыйДорогой && с.пакеты.count > 1 { МеткаБизнеса(текст: т("promo_max_rib"), золото: true) }
                Spacer(minLength: 6)
                ЦенаБизнеса(старая: пакет.цена, цена: цена)
            }
            if let котировка, !котировка.хватает {
                ЗаметкаБизнеса(БизнесText.т("q_short", ["b": СделкиФормат.деньги(котировка.баланс),
                                                         "l": котировка.подпись,
                                                         "p": СделкиФормат.деньги(котировка.цена),
                                                         "n": СделкиФормат.деньги(котировка.нехватка)]),
                               тон: .предупреждение, значок: "wallet.pass")
            } else if котировка == nil && безОтвета.contains(пакет.id) {
                Text(т("q_fail"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .padding(12)
        .background(Theme.топФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Слоты

/// Вкладка «Слоты» окна openUpgrade сайта (upgSlotsPaneHTML) сведениями.
private struct БлокСлотов: View {
    let с: СтраницаБизнеса
    let слоты: СлотыТарифа?
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

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
                if слоты.скидка > 0 {
                    СтрокаЗначенияБизнеса(название: т("upg_your_tariff_disc").replacingOccurrences(of: ":", with: ""),
                                          значение: "−" + String(слоты.скидка) + "%")
                }
                ForEach(слоты.тарифы) { тариф in
                    строкаТарифа(тариф, слоты)
                }
                if !с.верифицирован {
                    КнопкаСайтаБизнеса(подпись: т("upg_verify_bonus"), главная: false) {
                        if let u = Config.страницаСайта("cabinet?go=verify") { открыть(u) }
                    }
                }
                ЦифроваяПокупка(подпись: т("upg_choose"), путь: "cabinet?go=items", открыть: открыть)
            } else {
                Text(т("upg_slots_in_section"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    private func строкаТарифа(_ тариф: ТарифСлотов, _ слоты: СлотыТарифа) -> some View {
        let базовый = тариф.цена <= 0
        let сколько = базовый ? с.бесплатныхСлотов : с.бесплатныхСлотов + тариф.слотов
        let текущий = сколько == слоты.лимит
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(текущий ? Theme.акцент : Theme.текстВторой)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    (Text(String(сколько)).bold() + Text(" " + т("upg_listings_word")))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                    if текущий { МеткаБизнеса(текст: т("upg_current")) }
                }
                if базовый {
                    Text(т("upg_base_limit"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                } else {
                    HStack(spacing: 4) {
                        ЦенаБизнеса(старая: тариф.цена, цена: слоты.соСкидкой(тариф.цена))
                        Text(т("upg_per_month") + " · " + String(с.бесплатныхСлотов) + "+" + String(тариф.слотов))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
            }
            Spacer(minLength: 6)
            if базовый && текущий { МеткаБизнеса(текст: т("upg_included")) }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Комбо

/// Вкладка «Комбо» окна openUpgrade (upgComboPaneHTML) сведениями.
private struct БлокКомбо: View {
    let с: СтраницаБизнеса
    let открыть: (URL) -> Void

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
            if с.скидкаИИ > 0 {
                ЗаметкаБизнеса(т("upg_disc_note").replacingOccurrences(of: "{n}", with: String(с.скидкаИИ)),
                               тон: .предупреждение, значок: "tag")
            }
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
                    ЦенаБизнеса(старая: пакет.цена, цена: с.соСкидкойИИ(пакет.цена))
                }
                .padding(12)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            ЦифроваяПокупка(подпись: т("bc_order"), путь: "cabinet?go=items", открыть: открыть)
        }
    }
}

// MARK: - Kliko AI

/// Квота Kliko AI (сегмент карточки «Доступно», renderSlotBanner) и вкладка «Kliko AI» окна openUpgrade.
private struct БлокИИ: View {
    let с: СтраницаБизнеса
    let запусков: Int?
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Цена пакета: AI_FREE — 0, иначе Math.round(price*(100-AI_DISC)/100).
    private func цена(_ п: ПакетИИ) -> Int { с.иИБесплатно ? 0 : с.соСкидкойИИ(п.цена) }

    private func вДень(_ п: ПакетИИ) -> Double {
        п.дней > 0 ? Double(цена(п)) / Double(п.дней) : 0
    }

    /// «Выгоднее всего» — самый дешёвый в день, если это не первый пакет (как у сайта).
    private var лучший: String {
        guard !с.иИБесплатно, с.пакетыИИ.count > 1 else { return "" }
        var мин = Double.infinity
        var ключ = ""
        for п in с.пакетыИИ {
            let д = вДень(п)
            if д > 0 && д < мин {
                мин = д
                ключ = п.id
            }
        }
        return ключ == с.пакетыИИ.first?.id ? "" : ключ
    }

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
            if с.иИБесплатно {
                ЗаметкаБизнеса(т("upg_ai_free_note"), тон: .хорошо, значок: "sparkles")
            } else if с.скидкаИИ > 0 {
                ЗаметкаБизнеса(т("upg_ai_disc_note").replacingOccurrences(of: "{n}", with: String(с.скидкаИИ)),
                               тон: .предупреждение, значок: "tag")
            }
            ForEach(с.пакетыИИ) { пакет in
                строкаПакета(пакет)
            }
            ЦифроваяПокупка(подпись: т("bc_ai_pack"), путь: "cabinet?go=items", открыть: открыть)
        }
    }

    private func строкаПакета(_ п: ПакетИИ) -> some View {
        let первый = с.пакетыИИ.first.map { вДень($0) } ?? 0
        let день = вДень(п)
        let выгода = !с.иИБесплатно && первый > 0 && день > 0 ? Int((100 * (1 - день / первый)).rounded()) : 0
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(т("upg_ai_pack").replacingOccurrences(of: "{d}", with: String(п.дней)))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    if п.id == лучший { МеткаБизнеса(текст: т("upg_ai_best"), золото: true) }
                }
                HStack(spacing: 6) {
                    Text(с.иИБесплатно ? т("upg_unlimited_ai")
                         : т("upg_ai_perday").replacingOccurrences(of: "{n}", with: СделкиФормат.деньги(Int(день.rounded()))))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                    if выгода >= 5 {
                        Text("−" + String(выгода) + "%")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                    }
                }
            }
            Spacer(minLength: 6)
            ЦенаБизнеса(старая: с.иИБесплатно ? nil : п.цена, цена: цена(п),
                        бесплатно: с.иИБесплатно ? т("upg_free_word") : nil)
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
