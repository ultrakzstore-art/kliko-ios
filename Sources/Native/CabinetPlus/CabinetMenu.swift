import SwiftUI

/**
 МЕНЮ КАБИНЕТА САЙТА — СТРОКАМИ ВКЛАДКИ «КАБИНЕТ» (владелец: «и кабинет полностью SwiftUI сделай»).

 Боковое меню кабинета сайта (nav.cab-nav, карта §6.1.4): «Мои объявления», «Сделки», «Чат», «Доставки», «Заявки»,
 «Аренды», «Обмены», «Работа», «Акции», «Подписки»; группа «Для бизнеса» — «Счета», «Прайс-лист», «Разделы магазина»,
 «Интеграции», «Аналитика». Раньше у приложения не было «Доставок», «Аренд», «Обменов», «Работы», «Подписок», а бизнес-
 разделы жили только строками внутри «Счетов» — остальное открывала строка «Открыть кабинет» (весь кабинет сайта). Теперь
 каждый пункт — строка со своим экраном в стеке вкладки (КабинетЦель), строки «Открыть кабинет» нет.

 Упрощение для новичка (владелец 29.09.2026): «Подписки» — строкой «Избранное» среди главных; «Доставки» и «Аренды» —
 одной строкой «Доставки и аренды»; «Счета», «Счета и заказы» и «Журнал счетов» — одной строкой «Счета и документы».
 Экраны прежние, до каждого — на одно нажатие дальше.
 */

private func тК(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

/// Строка раздела: значок, название, стрелка списка — экран приложения.
private struct СтрокаРазделаКабинета: View {
    let название: String
    let значок: String
    let цель: КабинетЦель

    var body: some View {
        NavigationLink(value: цель) {
            ПодписьСтрокиКабинета(название, значок: значок)
        }
        .полямиСтрокиКабинета()
    }
}

/// «Избранное» — главная строка профиля: вкладка «Избранное» приложения (там же «Подписки» сайта ?s=subs — поиски и
/// продавцы), поэтому отдельной строки «Подписки» больше нет (упрощение для новичка).
struct СтрокаИзбранногоКабинета: View {
    var body: some View {
        Button {
            WebBridge.shared.открытьЭкран(.избранное, запасной: nil)
        } label: {
            HStack {
                ПодписьСтрокиКабинета(CabinetText.т("favorites"), значок: "heart")
                Spacer(minLength: 8)
                СтрелкаСтрокиКабинета()
            }
        }
        .полямиСтрокиКабинета()
    }
}

/// Второстепенные разделы меню сайта: «Доставки и аренды» (одна строка — экран с двумя пунктами), «Обмены», «Работа».
struct МенюРазделовКабинета: View {
    let открыть: (URL) -> Void

    var body: some View {
        Group {
            NavigationLink {
                ГруппаСтрокКабинета(заголовок: CabinetText.т("dlv_rent")) {
                    СтрокаРазделаКабинета(название: тК("dlv_title"), значок: "shippingbox", цель: .доставки)
                    СтрокаРазделаКабинета(название: тК("rent_title"), значок: "calendar.badge.clock", цель: .аренды)
                }
            } label: {
                ПодписьСтрокиКабинета(CabinetText.т("dlv_rent"), значок: "shippingbox")
            }
            .полямиСтрокиКабинета()
            СтрокаРазделаКабинета(название: тК("exch_title"), значок: "arrow.left.arrow.right", цель: .обмены)
            NavigationLink {
                ЭкранРаботыКабинета(открыть: открыть)
            } label: {
                ПодписьСтрокиКабинета(тК("jobs_title"), значок: "briefcase")
            }
            .полямиСтрокиКабинета()
        }
    }
}

/// Группа «Для бизнеса» меню сайта — кроме «Платных услуг» и «Акций», которые CabinetView рисует сам. Три строки счетов
/// («Счета» — компания и витрина, «Счета и заказы», «Журнал счетов») сведены в одну — «Счета и документы».
struct МенюБизнесаКабинета: View {
    var body: some View {
        Group {
            NavigationLink {
                ГруппаСтрокКабинета(заголовок: CabinetText.т("docs")) {
                    СтрокаРазделаКабинета(название: БизнесText.т("cmp_title"), значок: "building.2", цель: .компания)
                    СтрокаРазделаКабинета(название: тК("inv_orders_title"), значок: "doc.text", цель: .счета)
                    СтрокаРазделаКабинета(название: БизнесРазделыText.т("jrn_title"), значок: "list.number", цель: .журнал)
                }
            } label: {
                ПодписьСтрокиКабинета(CabinetText.т("docs"), значок: "doc.text")
            }
            .полямиСтрокиКабинета()
            СтрокаРазделаКабинета(название: тК("pl_title"), значок: "list.bullet.rectangle", цель: .прайсЛист)
            СтрокаРазделаКабинета(название: БизнесText.т("biz_sections"), значок: "square.grid.2x2", цель: .разделыМагазина)
            СтрокаРазделаКабинета(название: тК("intg_title"), значок: "arrow.triangle.branch", цель: .интеграции)
            СтрокаРазделаКабинета(название: БизнесText.т("biz_analytics"), значок: "chart.bar", цель: .аналитика)
            СтрокаРазделаКабинета(название: тК("tax_title"), значок: "percent", цель: .налоги)
            СтрокаРазделаКабинета(название: БизнесText.т("biz_kp"), значок: "doc.richtext", цель: .кп)
            СтрокаРазделаКабинета(название: тК("feed_title"), значок: "arrow.triangle.2.circlepath", цель: .прайсПоСсылке)
        }
    }
}

/// Экран-группа из нескольких строк профиля («Доставки и аренды», «Счета и документы»): тот же список, что у профиля.
struct ГруппаСтрокКабинета<Содержимое: View>: View {
    let заголовок: String
    @ViewBuilder let содержимое: () -> Содержимое

    var body: some View {
        List {
            if Config.дизайнКакНаСайте {
                Section { содержимое() }
                    .строкиСайта()
            } else {
                Section { содержимое() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(заголовок)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(СписокГруппыКабинета(заголовок: заголовок))
    }
}

/// Краска сайта у экрана-группы — как у самого профиля (КабинетКакНаСайте).
private struct СписокГруппыКабинета: ViewModifier {
    let заголовок: String

    func body(content: Content) -> some View {
        if Config.дизайнКакНаСайте {
            content
                .списокСайта()
                .шапкаЭкранаСайта(заголовок)
        } else {
            content
        }
    }
}

/// Экран раздела по цели стека «Кабинета» — для целей, добавленных этим модулем.
struct ЭкранРазделаКабинета: View {
    let цель: КабинетЦель
    let открыть: (URL) -> Void

    var body: some View {
        switch цель {
        case .доставки:
            ЭкранДоставок()
        case .аренды:
            ЭкранАренд(открыть: открыть)
        case .обмены:
            ЭкранОбменов(открыть: открыть)
        case .прайсЛист:
            ЭкранПрайсЛиста(открыть: открыть)
        case .налоги:
            ЭкранНалогов(открыть: открыть)
        case .интеграции:
            ЭкранИнтеграций(открыть: открыть)
        case .аналитика:
            ЭкранАналитики(открыть: открыть)
        case .кп:
            ЭкранКП(открыть: открыть)
        case .счета:
            ЭкранСчетов(открыть: открыть)
        case .журнал:
            ЭкранЖурнала(открыть: открыть)
        case .разделыМагазина:
            ЭкранРазделовМагазина(открыть: открыть)
        case .прайсПоСсылке:
            ЭкранПрайсаПоСсылке(открыть: открыть)
        default:
            ПустоСайта(значок: "questionmark.folder", заголовок: тК("not_found"))
        }
    }
}

// MARK: - «Работа» (cabJobsGo): мои вакансии и резюме

/// Пункт «Работа» меню сайта: блок «Работа» главной кабинета (jobsMineDraw) отдельным экраном — список своих вакансий и
/// резюме (/api/jobs.php?action=mine), «Изменить» — свой мастер (МастерРезюме), «Снять» / «Восстановить», «+ Резюме» и
/// «+ Вакансия». «В ТОП» (платно) в приложении не продаётся — кнопки нет.
struct ЭкранРаботыКабинета: View {
    let открыть: (URL) -> Void

    @State private var записи: [МояРабота] = []
    @State private var грузим = true
    @State private var ошибка: String? = nil
    @State private var занято: Set<String> = []
    @State private var плашка: String? = nil
    @State private var снять: МояРабота? = nil

    private func тМ(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    кнопкаНовой(РезюмеText.т("hov_resume"), значок: "person.text.rectangle", вид: .резюме)
                    кнопкаНовой(РезюмеText.т("hov_vacancy"), значок: "briefcase", вид: .вакансия)
                }
                if грузим && записи.isEmpty {
                    ЗагрузкаБизнеса().frame(height: 160)
                } else if let ошибка, записи.isEmpty {
                    ПустоСайта(значок: "wifi.exclamationmark", заголовок: ошибка, кнопка: тК("retry"),
                               действие: { Task { await загрузить() } })
                } else if записи.isEmpty {
                    Text(тК("jobs_empty"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ForEach(записи) { запись in
                        СтрокаРаботы(запись: запись, занято: занято.contains(запись.id)) { действие in
                            нажато(действие, запись)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(тК("jobs_title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await загрузить() }
        .task { await загрузить() }
        .overlay(alignment: .bottom) {
            if let плашка { ПлашкаКошелька(текст: плашка) }
        }
        .alert(тМ("jb_off_q"), isPresented: Binding(get: { снять != nil }, set: { if !$0 { снять = nil } })) {
            Button(тМ("jb_off"), role: .destructive) {
                if let запись = снять { действие("delete", запись) }
                снять = nil
            }
            Button(CabinetText.т("cancel"), role: .cancel) { снять = nil }
        } message: {
            Text(тМ("jb_off_s"))
        }
    }

    private func кнопкаНовой(_ подпись: String, значок: String, вид: ВидРаботы) -> some View {
        Button {
            НативныеОкна.показать(.работа(вид: вид, номер: nil))
        } label: {
            Label(подпись, systemImage: значок)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func загрузить() async {
        грузим = true
        defer { грузим = false }
        do {
            guard let j = try await МоиОбъявленияAPI.получить("/api/jobs.php?action=mine", отКорня: true) else {
                ошибка = тК("err_generic")
                return
            }
            if МоиОбъявленияAPI.нетСессии(j) {
                ошибка = CabinetText.т("signed_out")
                return
            }
            let сырые: [Any] = (j["jobs"] as? [Any]) ?? []
            записи = сырые.compactMap { запись -> МояРабота? in
                guard let словарь = запись as? [String: Any] else { return nil }
                return МояРабота(словарь)
            }
            ошибка = nil
        } catch {
            ошибка = тК("no_conn")
        }
    }

    private func нажато(_ действие: СтрокаРаботы.Действие, _ запись: МояРабота) {
        switch действие {
        case .изменить:
            НативныеОкна.показать(.работа(вид: запись.вакансия ? .вакансия : .резюме, номер: запись.id))
        case .снять:
            снять = запись
        case .восстановить:
            self.действие("restore", запись)
        case .вТоп:
            /* «В ТОП» резюме — окно покупки App Store (кнопка есть только при Config.цифровыеПокупки). */
            ЛистУслугиApple.показать(.топРезюме, цель: запись.id)
        }
    }

    private func действие(_ имя: String, _ запись: МояРабота) {
        guard !занято.contains(запись.id) else { return }
        занято.insert(запись.id)
        Task {
            defer { занято.remove(запись.id) }
            do {
                let j = try await МоиОбъявленияAPI.отправить("/api/jobs.php?action=" + имя, тело: ["id": запись.id],
                                                           отКорня: true)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    await загрузить()
                } else {
                    let текст = МоиОбъявленияAPI.строка(j["msg"])
                    показать(текст.isEmpty ? тМ("jw_fail") : текст)
                }
            } catch {
                показать(тК("no_conn"))
            }
        }
    }

    private func показать(_ текст: String) {
        withAnimation { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation { плашка = nil }
        }
    }
}
