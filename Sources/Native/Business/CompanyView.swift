import SwiftUI

/**
 «КОМПАНИЯ И МАГАЗИН» — ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Пункт «Счета» меню
 «Для бизнеса» кабинета.

 Что здесь своим экраном (карта §6.6, код js/cabinet.min.js и докачанный js/cabinet-business.min.js):
   · «Станьте магазином» — карточка splitCard по CAB_SPLIT.status: «Статус: Магазин», «Заявка на проверке», три шага
     («Верификация продавца», «Реквизиты юр. лица», «Выплаты на счёт компании»), «Заявка отклонена: …». Кнопка — как у
     сайта: нет верификации (CAB_IS_VERIFIED) — «Пройти верификацию» (страница ?go=verify, eGov живёт там); нет
     реквизитов (_splitReqsOk) — «Заполнить реквизиты»; иначе «Стать магазином» → split_submit {csrf} за
     Config.заявкаМагазина. Сайт шлёт заявку сразу по нажатию; здесь сначала вопрос со словами сайта (шаг 3 — «Платёжная
     система проверит реквизиты…»): заявка уходит эквайеру, её не отозвать;
   · «Реквизиты компании» — CAB_COMPANY сведениями и мастер «Реквизиты юр. лица» (openReqWizard): шаг 1 — БИН и «Найти»
     (company_lookup_bin, только чтение реестра), шаг 2 — банк из CMP_BANKS (БИК подставится сам) и ИИК по маске сайта,
     шаг 3 — проверка и «Сохранить реквизиты» (save_company за Config.реквизитыКомпании). Мастер за PRO, как proGate("reqs");
   · «Документы» — заказы B2B (b2b_orders_list): «Заказы от покупателей» и «Мои заказы у поставщиков» — номер,
     контрагент, сумма, позиции, статус (_b2bStName) и срок. Только чтение: подтвердить, отгрузить, отменить, счёт,
     накладная, акт, счёт-фактура и доверенность — страница кабинета сайта (печать документов живёт в браузере).
 Остальное меню «Для бизнеса» — строки на страницы сайта (модуль business целиком: «Счёт» 1С, журнал, печать и подпись
 с eGov, прайс-лист, разделы магазина, интеграции, аналитика, КП). Ошибки — тостом, словами сервера, как у сайта.
 */
struct ЭкранКомпании: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var входОткрыт = false
    @State private var мастерОткрыт = false
    @State private var спроситьЗаявку = false
    @State private var подаём = false
    @State private var нуженПРО = false

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("cmp_title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await загрузить() }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await загрузить() }
                })
            }
            .sheet(isPresented: $мастерОткрыт) {
                МастерРеквизитов(исходные: модель.страница?.реквизиты ?? РеквизитыКомпании())
            }
            .alert(т("split_cta_go"), isPresented: $спроситьЗаявку) {
                Button(т("split_cta_go")) { подать() }
                Button(т("cancel"), role: .cancel) {}
            } message: {
                Text(т("split_s3_d"))
            }
            .alert(т("pxd_eyebrow"), isPresented: $нуженПРО) {
                /* PRO в приложении не продаётся: только сведения, без перехода на оплату. */
                Button(т("close"), role: .cancel) {}
            } message: {
                Text(т("pro_h2") + "\n" + т("no_digital"))
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
                           действие: { Task { await загрузить() } })
            }
        case .нет, .идёт, .готово:
            if let с = модель.страница {
                список(с)
            } else {
                ЗагрузкаБизнеса()
            }
        }
    }

    private func загрузить() async {
        await модель.загрузитьСтраницу()
        guard модель.страница != nil else { return }
        await модель.загрузитьЗаказы()
    }

    private func список(_ с: СтраницаБизнеса) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                КарточкаМагазина(с: с, подаём: подаём, действие: { действиеМагазина(с) })
                реквизиты(с)
                ЗаказыБизнеса(продаю: модель.заказыПродаю, покупаю: модель.заказыПокупаю, наСайт: {
                    наСайт("cabinet.php?s=company")
                })
                инструменты
            }
            .padding(12)
        }
        .refreshable { await загрузить() }
    }

    // MARK: - Реквизиты

    private func реквизиты(_ с: СтраницаБизнеса) -> some View {
        let р = с.реквизиты
        let строки: [(String, String)] = [
            (т("cmp_f_name"), р.название), (т("cmp_f_bin"), р.бин), (т("cmp_f_director"), р.руководитель),
            (т("cmp_f_addr"), р.адрес), (т("cmp_f_bank"), р.банк), (т("cmp_f_bik"), р.бик), (т("cmp_f_iik"), р.иик),
            (т("cmp_f_kbe"), р.кбе), (т("cmp_f_acctype"), р.типСчёта), (т("cmp_f_phone"), р.телефон)
        ]
        let заполненные = строки.filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }
        return КарточкаБизнеса(т("cmp_card_t"), значок: "building.2") {
            if заполненные.isEmpty {
                Text(т("rw_empty"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                ForEach(Array(заполненные.enumerated()), id: \.offset) { _, строка in
                    СтрокаЗначенияБизнеса(название: строка.0, значение: строка.1)
                }
            }
            КнопкаБизнеса(подпись: заполненные.isEmpty ? т("split_cta_reqs") : т("cmp_edit"), второстепенная: true) {
                открытьМастер()
            }
        }
    }

    // MARK: - Инструменты магазина — страницы сайта

    /// Этап 50: счета, журнал, КП, аналитика и разделы магазина — свои экраны (BusinessSectionsViews); печать и
    /// подпись (eGov), прайс-лист (PDF) и интеграции — страницей сайта.
    private var инструменты: some View {
        КарточкаБизнеса(т("biz_title"), значок: "briefcase") {
            строкаЭкрана(т("biz_invoices"), значок: "doc.text") { ЭкранСчетов(открыть: открыть) }
            строкаЭкрана(БизнесРазделыText.т("jrn_title"), значок: "list.number") { ЭкранЖурнала(открыть: открыть) }
            строкаЭкрана(т("biz_kp"), значок: "doc.richtext") { ЭкранКП(открыть: открыть) }
            строкаЭкрана(т("biz_analytics"), значок: "chart.bar") { ЭкранАналитики(открыть: открыть) }
            строкаЭкрана(т("biz_sections"), значок: "square.grid.2x2") { ЭкранРазделовМагазина(открыть: открыть) }
            /* «Кабинет полностью SwiftUI»: печать и подпись, прайс-лист, налоги, интеграции и прайс по ссылке — свои экраны. */
            строкаЭкрана(т("biz_seal"), значок: "signature") { ЭкранПечатиИПодписи(открыть: открыть) }
            строкаЭкрана(т("biz_pricelist"), значок: "list.bullet.rectangle") { ЭкранПрайсЛиста(открыть: открыть) }
            строкаЭкрана(КабинетПлюсText.т("tax_title"), значок: "percent") { ЭкранНалогов(открыть: открыть) }
            строкаЭкрана(т("biz_integrations"), значок: "arrow.triangle.branch") { ЭкранИнтеграций(открыть: открыть) }
            строкаЭкрана(КабинетПлюсText.т("feed_title"), значок: "arrow.triangle.2.circlepath") {
                ЭкранПрайсаПоСсылке(открыть: открыть)
            }
        }
    }

    private func строкаЭкрана<Экран: View>(_ название: String, значок: String,
                                          @ViewBuilder экран: @escaping () -> Экран) -> some View {
        NavigationLink {
            экран()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(название)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func строкаСайта(_ название: String, значок: String, путь: String) -> some View {
        Button {
            наСайт(путь)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(название)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(т("a11y_site"))
    }

    // MARK: - Действия

    /// Кнопка карточки «Станьте магазином» — ветки splitCard сайта.
    private func действиеМагазина(_ с: СтраницаБизнеса) {
        if !с.верифицированМагазин {
            наСайт("cabinet?go=verify")
        } else if !с.реквизиты.заполнены {
            открытьМастер()
        } else if Config.заявкаМагазина {
            спроситьЗаявку = true
        } else {
            наСайт("cabinet.php?s=company")
        }
    }

    /// openReqWizard: сначала proGate("reqs"); свой мастер — только при Config.реквизитыКомпании.
    private func открытьМастер() {
        guard let с = модель.страница else { return }
        guard с.естьФункция("reqs") else {
            нуженПРО = true
            return
        }
        if Config.реквизитыКомпании {
            мастерОткрыт = true
        } else {
            наСайт("cabinet.php?s=company")
        }
    }

    /// split_submit — только после вопроса. Ответы — как splitSubmit сайта.
    private func подать() {
        guard !подаём else { return }
        подаём = true
        Task {
            let итог = await модель.податьЗаявкуМагазина()
            подаём = false
            switch итог {
            case .отправлена:
                break
            case .нужнаВерификация(let текст):
                модель.показать(текст)
                наСайт("cabinet?go=verify")
            case .нужныРеквизиты(let текст):
                модель.показать(текст)
                открытьМастер()
            case .ошибка(let текст):
                модель.показать(текст)
            }
        }
    }

    private func наСайт(_ путь: String) {
        if let u = Config.страницаСайта(путь) { открыть(u) }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else {
            наСайт("cabinet.php")
        }
    }
}

// MARK: - «Станьте магазином» (splitCard)

private struct КарточкаМагазина: View {
    let с: СтраницаБизнеса
    let подаём: Bool
    let действие: () -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        switch с.статусМагазина {
        case "active":
            шапка(т("split_active_t"), т("split_active_s"), значок: "checkmark.seal.fill", тон: .хорошо) {
                ЗаметкаБизнеса(т("split_active_note"), тон: .хорошо, значок: "checkmark.shield")
            }
        case "pending":
            шапка(т("split_pend_t"), т("split_pend_s"), значок: "clock", тон: .предупреждение) {
                ЗаметкаБизнеса(т("split_pend_note"), тон: .серый, значок: "clock")
            }
        default:
            шапка(т("split_none_t"), т("split_none_s"), значок: "storefront", тон: .инфо) {
                шаги
                if с.статусМагазина == "rejected" {
                    ЗаметкаБизнеса(отказ, тон: .плохо, значок: "exclamationmark.triangle")
                }
                КнопкаБизнеса(подпись: подписьКнопки, занято: подаём, действие: действие)
                ЗаметкаБизнеса(т("split_none_note"), тон: .серый, значок: "checkmark")
            }
        }
    }

    /// «Заявка отклонена: <reason>. Проверьте реквизиты и подайте снова.»
    private var отказ: String {
        var текст = т("split_rej")
        if !с.причинаОтказа.isEmpty { текст += ": " + с.причинаОтказа }
        return текст + ". " + т("split_rej2")
    }

    private var подписьКнопки: String {
        if !с.верифицированМагазин { return т("split_cta_verify") }
        if !с.реквизиты.заполнены { return т("split_cta_reqs") }
        return т("split_cta_go")
    }

    private var шаги: some View {
        let верифицирован = с.верифицированМагазин
        let реквизиты = с.реквизиты.заполнены
        return VStack(alignment: .leading, spacing: 10) {
            шаг(1, готово: верифицирован, сейчас: !верифицирован, т("split_s1_t"),
                верифицирован ? т("split_s1_done") : т("split_s1_d"))
            шаг(2, готово: реквизиты, сейчас: верифицирован && !реквизиты, т("split_s2_t"),
                реквизиты ? т("split_s2_done") : т("split_s2_d"))
            шаг(3, готово: false, сейчас: верифицирован && реквизиты, т("split_s3_t"), т("split_s3_d"))
        }
    }

    private func шаг(_ номер: Int, готово: Bool, сейчас: Bool, _ заголовок: String, _ подпись: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(готово ? Theme.акцент : (сейчас ? Theme.оттенокАкцента : Theme.поверхность2))
                if готово {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color.white)
                } else {
                    Text(String(номер))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(сейчас ? Theme.акцент : Theme.текстВторой)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(заголовок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(готово ? т("a11y_done") : "")
    }

    private func шапка<Низ: View>(_ заголовок: String, _ подпись: String, значок: String, тон: ЗаметкаБизнеса.Тон,
                                  @ViewBuilder низ: () -> Низ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(тон == .предупреждение ? Theme.оранжевый : Theme.акцент,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(заголовок)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            низ()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

// MARK: - Заказы B2B (b2b_orders_list, _b2bRow модуля business)

private struct ЗаказыБизнеса: View {
    let продаю: [ЗаказB2B]?
    let покупаю: [ЗаказB2B]?
    let наСайт: () -> Void

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        КарточкаБизнеса(т("docs_t"), значок: "doc.on.doc") {
            Text(т("docs_s"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            раздел(т("b2b_orders_in"), заказы: продаю, пусто: т("b2b_no_incoming"))
            раздел(т("b2b_orders_out"), заказы: покупаю, пусто: т("b2b_no_mine"))
        }
    }

    @ViewBuilder
    private func раздел(_ заголовок: String, заказы: [ЗаказB2B]?, пусто: String) -> some View {
        Text(заголовок)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(Theme.текст)
            .padding(.top, 4)
        if let заказы {
            if заказы.isEmpty {
                Text(пусто)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                ForEach(заказы) { заказ in
                    СтрокаЗаказаB2B(заказ: заказ)
                    КнопкиДокументовЗаказа(заказ: заказ)
                }
            }
        } else {
            Text(т("loading"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
        }
    }
}

private struct СтрокаЗаказаB2B: View {
    let заказ: ЗаказB2B

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// _b2bStName: подпись статуса; незнакомый — как пришёл.
    private var статус: String {
        switch заказ.статус {
        case "new", "confirmed", "paid", "shipped", "done", "cancelled": return т("b2b_st_" + заказ.статус)
        default: return заказ.статус
        }
    }

    /// Точка: cancelled — bad, done — ok, paid / shipped — go, прочее — wait.
    private var краска: Color {
        switch заказ.статус {
        case "cancelled": return КраскаОбъявлений.плохоТекст
        case "done": return КраскаОбъявлений.хорошоТекст
        case "paid", "shipped": return КраскаОбъявлений.инфоТекст
        default: return КраскаОбъявлений.предупреждениеТекст
        }
    }

    /// Первые три позиции «название × кол-во» и «+N».
    private var позиции: String {
        let первые = заказ.позиции.prefix(3).map { $0.0 + " × " + String($0.1) }
        var текст = первые.joined(separator: ", ")
        if заказ.позиции.count > 3 { текст += " +" + String(заказ.позиции.count - 3) }
        return текст
    }

    /// « · до dd.mm.yyyy» — только у new и confirmed.
    private var срок: String {
        guard заказ.статус == "new" || заказ.статус == "confirmed", let дата = СделкиФормат.дата(заказ.до) else { return "" }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "ru_RU")
        ф.dateFormat = "dd.MM.yyyy"
        return " · " + т("b2b_until") + " " + ф.string(from: дата)
    }

    private var имя: String {
        if !заказ.контрагент.isEmpty { return заказ.контрагент }
        /* "seller"===e ? buyer.name||«Покупатель» : seller.name||«Поставщик». */
        return т(заказ.продаю ? "b2b_buyer_word" : "b2b_supplier")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("№" + заказ.номер + " · " + имя)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Text(СделкиФормат.тенге(заказ.сумма))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            if заказ.гость {
                HStack(spacing: 6) {
                    МеткаБизнеса(текст: т("b2b_guest_tag"))
                    let связь = [заказ.телефон, заказ.почта].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !связь.isEmpty {
                        Text(связь)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .textSelection(.enabled)
                    }
                }
            }
            if !позиции.isEmpty {
                Text(позиции)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(краска)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(статус + срок)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(краска)
            }
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Мастер «Реквизиты юр. лица» (openReqWizard)

/// CMP_BANKS сайта: банк — БИК (подставится сам).
enum БанкиКазахстана {
    static let список: [(String, String)] = [
        ("АО «Kaspi Bank»", "CASPKZKA"), ("АО «Народный банк Казахстана» (Halyk)", "HSBKKZKX"),
        ("АО «Bank CenterCredit»", "KCJBKZKX"), ("АО «ForteBank»", "IRTYKZKA"), ("АО «Jusan Bank»", "TSESKZKA"),
        ("АО «Евразийский банк»", "EURIKZKA"), ("АО «Bank RBK»", "KINCKZKA"), ("АО «Home Credit Bank»", "INLMKZKA"),
        ("АО «Altyn Bank»", "ATYNKZKA"), ("АО «Нурбанк»", "NURSKZKX"), ("АО «Freedom Bank Kazakhstan»", "KSNVKZKA"),
        ("АО «Bereke Bank»", "BRKEKZKA"), ("АО «Otbasy bank»", "HCSKKZKA"), ("АО «Ситибанк Казахстан»", "CITIKZKA")
    ]
}

struct МастерРеквизитов: View {
    let исходные: РеквизитыКомпании

    @ObservedObject private var модель = БизнесМодель.shared
    @Environment(\.dismiss) private var закрыть
    @State private var шаг = 0
    @State private var р: РеквизитыКомпании
    @State private var банк: Int
    @State private var найдено: Bool
    @State private var ищем = false
    @State private var сохраняем = false
    @State private var сообщение: String? = nil

    init(исходные: РеквизитыКомпании) {
        self.исходные = исходные
        _р = State(initialValue: исходные)
        let номер = БанкиКазахстана.список.firstIndex(where: { $0.0 == исходные.банк }) ?? -1
        _банк = State(initialValue: номер)
        _найдено = State(initialValue: !исходные.название.isEmpty)
    }

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    полоса
                    switch шаг {
                    case 0: шагКомпания
                    case 1: шагБанк
                    default: шагПроверка
                    }
                    if let сообщение {
                        ЗаметкаБизнеса(сообщение, тон: .предупреждение, значок: "exclamationmark.circle")
                    }
                    кнопки
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("rw_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .interactiveDismissDisabled(сохраняем)
    }

    /// Три полоски шагов (.rw-steps i.on).
    private var полоса: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("rw_sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { номер in
                    Capsule()
                        .fill(номер <= шаг ? Theme.акцент : Theme.линия)
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(т("a11y_step").replacingOccurrences(of: "{n}", with: String(шаг + 1)))
        }
    }

    // MARK: Шаг 1 · Компания

    private var шагКомпания: some View {
        VStack(alignment: .leading, spacing: 10) {
            заголовокШага(т("rw_s1"))
            подписьПоля(т("cmp_f_bin"))
            HStack(spacing: 8) {
                TextField(т("rw_bin_ph"), text: Binding(get: { р.бин }, set: { р.бин = БизнесФорма.цифры($0, до: 12) }))
                    .keyboardType(.numberPad)
                    .modifier(ПолеБизнеса())
                КнопкаБизнеса(подпись: ищем ? т("rw_finding") : т("rw_find"), занято: ищем) { найти() }
                    .frame(width: 110)
            }
            Text(т("rw_hint_bin"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if найдено && !р.название.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(р.название)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    let мета = [р.руководитель, р.адрес].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !мета.isEmpty {
                        Text(мета)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(КраскаОбъявлений.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            подписьПоля(т("cmp_f_name"))
            TextField(т("cmp_f_name"), text: $р.название)
                .modifier(ПолеБизнеса())
        }
    }

    // MARK: Шаг 2 · Банк и счёт

    private var шагБанк: some View {
        VStack(alignment: .leading, spacing: 10) {
            заголовокШага(т("rw_s2"))
            подписьПоля(т("cmp_f_bank"))
            Picker(т("cmp_f_bank"), selection: $банк) {
                Text(р.банк.isEmpty || банк >= 0 ? т("cmp_bank_pick") : р.банк).tag(-1)
                ForEach(0..<БанкиКазахстана.список.count, id: \.self) { номер in
                    Text(БанкиКазахстана.список[номер].0).tag(номер)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.текст)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ПолеБизнеса())
            .onChange(of: банк) { _, номер in
                /* _rwBank: банк из списка — название и БИК. */
                guard номер >= 0 && номер < БанкиКазахстана.список.count else { return }
                р.банк = БанкиКазахстана.список[номер].0
                р.бик = БанкиКазахстана.список[номер].1
            }
            подписьПоля(т("cmp_f_bik"))
            TextField("KCJBKZKX", text: Binding(get: { р.бик }, set: { р.бик = String($0.prefix(11)) }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .modifier(ПолеБизнеса())
            подписьПоля(т("cmp_f_iik"))
            TextField("KZ…", text: Binding(get: { р.иик }, set: { р.иик = БизнесФорма.иик($0) }))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .modifier(ПолеБизнеса())
            Text(т("rw_hint_iik"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Шаг 3 · Проверка

    private var шагПроверка: some View {
        let строки: [(String, String)] = [
            (т("cmp_f_name"), р.название), (т("cmp_f_bin"), р.бин), (т("cmp_f_director"), р.руководитель),
            (т("cmp_f_addr"), р.адрес), (т("cmp_f_bank"), р.банк), (т("cmp_f_bik"), р.бик), (т("cmp_f_iik"), р.иик)
        ]
        let заполненные = строки.filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            заголовокШага(т("rw_s3"))
            VStack(alignment: .leading, spacing: 8) {
                if заполненные.isEmpty {
                    Text(т("rw_empty"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                } else {
                    ForEach(Array(заполненные.enumerated()), id: \.offset) { _, строка in
                        СтрокаЗначенияБизнеса(название: строка.0, значение: строка.1)
                    }
                }
            }
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            ЗаметкаБизнеса(т("rw_hint_save"), тон: .инфо, значок: "lock.shield")
        }
    }

    // MARK: Кнопки

    private var кнопки: some View {
        HStack(spacing: 10) {
            if шаг > 0 {
                КнопкаБизнеса(подпись: т("rw_back"), второстепенная: true) {
                    сообщение = nil
                    шаг -= 1
                }
                .disabled(сохраняем)
            }
            if шаг < 2 {
                КнопкаБизнеса(подпись: т("rw_next")) { далее() }
            } else {
                КнопкаБизнеса(подпись: сохраняем ? т("rw_saving") : т("rw_save"), занято: сохраняем) { сохранить() }
            }
        }
    }

    private func заголовокШага(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Theme.текст)
            .accessibilityAddTraits(.isHeader)
    }

    private func подписьПоля(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
    }

    // MARK: Действия

    /// _rwNext: проверки шагов словами сайта.
    private func далее() {
        сообщение = nil
        if шаг == 0 {
            р.название = р.название.trimmingCharacters(in: .whitespacesAndNewlines)
            if !р.бин.isEmpty && р.бин.count != 12 {
                сообщение = т("cmp_err_bin")
                return
            }
            if р.название.isEmpty {
                сообщение = т("rw_need_name")
                return
            }
        } else if шаг == 1 {
            р.бик = р.бик.trimmingCharacters(in: .whitespaces)
            if р.иик.range(of: "^KZ[0-9A-Z]{13,18}$", options: .regularExpression) == nil {
                сообщение = т("cmp_err_iik")
                return
            }
            if р.банк.isEmpty {
                сообщение = т("rw_need_bank")
                return
            }
        }
        шаг += 1
    }

    /// _rwLookup: «Найти» по 12 цифрам БИН — только чтение реестра.
    private func найти() {
        сообщение = nil
        let бин = р.бин
        guard бин.count == 12 else {
            сообщение = т("cmp_err_bin")
            return
        }
        guard !ищем else { return }
        ищем = true
        Task {
            let итог = await модель.найтиПоБИН(бин)
            ищем = false
            switch итог {
            case .найдено(let название, let руководитель, let адрес):
                if !название.isEmpty { р.название = название }
                if !руководитель.isEmpty { р.руководитель = руководитель }
                if !адрес.isEmpty { р.адрес = адрес }
                найдено = true
                сообщение = nil
                модель.показать(т("rw_found_ok"))
            case .ненайдено(let текст):
                сообщение = текст
            }
        }
    }

    /// _rwSave: save_company — только по нажатию «Сохранить реквизиты».
    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        сообщение = nil
        let данные = р
        Task {
            let ошибка = await модель.сохранитьРеквизиты(данные)
            сохраняем = false
            if let ошибка {
                сообщение = ошибка
            } else {
                закрыть()
            }
        }
    }
}

/// Поле ввода мастера (.rw-in сайта).
private struct ПолеБизнеса: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .padding(10)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
    }
}

/// Правила полей сайта: БИН — только цифры (и восточно-арабские цифры клавиатуры арабского iPhone), ИИК — A–Z0–9.
enum БизнесФорма {
    static func цифры(_ текст: String, до предела: Int) -> String {
        let только = текст.compactMap { $0.wholeNumberValue }.map { String($0) }.joined()
        return String(только.prefix(предела))
    }

    /// oninput сайта: toUpperCase().replace(/[^A-Z0-9]/g,''), maxlength 20.
    static func иик(_ текст: String) -> String {
        let верх = текст.uppercased()
        let годные = верх.filter { ch in
            guard ch.isASCII else { return false }
            return ch.isNumber || (ch >= "A" && ch <= "Z")
        }
        return String(String(годные).prefix(20))
    }
}
