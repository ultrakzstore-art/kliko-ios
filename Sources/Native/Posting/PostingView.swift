import SwiftUI
import UIKit

/**
 ПОДАЧА И ПРАВКА — ЭКРАН, ЭТАП 42 (владелец 26.09.2026: «всё одно и то же, просто код разный»; Config.нативнаяПодача).

 Сверху вниз, как #add-screen сайта: шапка «Новое объявление / Сфотографируйте — Kliko AI заполнит всё сам» (в правке —
 «Редактировать объявление / После сохранения — повторная проверка»), плашка «Без верификации объявление не выйдет на
 витрину» (CAB_NEED_EGOV), полоса шагов «Фото · 1 / 7», сам шаг, внизу «Назад» и «Далее →»; на «Проверке» —
 «Выставить на продажу» (у аренды — «Сдать в аренду»), в правке — «Сохранить изменения».

 Открывается поверх вкладок (fullScreenCover в NativeTabsView) — камера нижней панели, «+ Добавить объявление»,
 «Изменить» в «Моих объявлениях», ссылки ?go=add и ?edit=<id>. Страницы сайта (верификация, «Работа», перенос по
 ссылке, покупки) открываются после закрытия мастера: слой сайта лежит под ним. Черновик при этом остаётся.
 */
struct ЭкранПодачи: View {
    @StateObject private var модель: ПодачаМодель
    let открыть: (URL) -> Void

    init(цель: ЦельПодачи, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: ПодачаМодель(цель: цель))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПодачи(правка: модель.правка, закрыть: { закрыть() })
            содержимое
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .task { await модель.начать() }
        .alert(модель.вопрос?.заголовок ?? "", isPresented: вопросНаЭкране, presenting: модель.вопрос) { в in
            Button(в.да) { в.действие() }
            if let ещё = в.ещё {
                Button(ещё) { в.ещёДействие?() }
            }
            Button(в.нет, role: .cancel) { в.отказ?() }
        } message: { в in
            Text(в.текст)
        }
        .alert(модель.сообщение?.заголовок ?? "", isPresented: сообщениеНаЭкране, presenting: модель.сообщение) { _ in
            Button(т("ok_btn"), role: .cancel) {}
        } message: { с in
            Text(с.текст)
        }
        .sheet(isPresented: $модель.подтверждение) {
            ОкноПроверкиПодачи(модель: модель)
        }
        .sheet(isPresented: $модель.войти) {
            ЭкранВхода(eGovВключён: модель.страница.состояние?.eGovВключён ?? true, открыть: { адрес in
                закрытьИОткрыть(адрес)
            }, вошли: {
                Task { @MainActor in
                    if модель.экран == .нуженВход { await модель.начать() }
                }
            })
        }
        .overlay {
            if модель.распознаём {
                ОкноРаспознавания(шаг: модель.шагРаспознавания)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let итог = модель.итог {
                if ЭкранПослеПодачи.берёт(итог) {
                    /* Опубликовано или на проверке — экран сайта после подачи: карточка, «Продвинуть», «Поделиться». */
                    ЭкранПослеПодачи(итог: итог, товар: модель.товарДляПревью, топПодключён: модель.топПослеПодачи,
                                     действие: { д in послеПодачиНажат(д, итог) })
                        .transition(.opacity)
                } else {
                    ОкноИтогаПодачи(итог: итог, заголовок: модель.форма.название, действие: { д in итогНажат(д, итог) })
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottom) { плашкаВнизу }
        .onChange(of: модель.открытьСтраницу) { _, хвост in
            guard let хвост else { return }
            модель.открытьСтраницу = nil
            /* Окна лимита слотов мастера ведут на cabinet.php?go=items; при покупках Apple — окно слотов App Store. */
            if Config.цифровыеПокупки && хвост == "cabinet.php?go=items" {
                ЛистУслугиApple.показать(.слоты)
                return
            }
            открытьСайт(хвост)
        }
    }

    private var вопросНаЭкране: Binding<Bool> {
        Binding(get: { модель.вопрос != nil }, set: { показан in
            if !показан { модель.вопрос = nil }
        })
    }

    private var сообщениеНаЭкране: Binding<Bool> {
        Binding(get: { модель.сообщение != nil }, set: { показан in
            if !показан { модель.сообщение = nil }
        })
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.экран {
        case .загрузка:
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .нуженВход:
            /* Гость на ?go=add у сайта видит тизер «Новое объявление» и регистрацию, а не форму. */
            ПустоСайта(значок: "camera", заголовок: т("guest_t"), подпись: т("guest_s"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        case .ошибка(let текст):
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                       действие: { Task { await модель.начать() } })
        case .старт:
            СтартПодачи(модель: модель, работа: { открытьСайт("cabinet?go=add") },
                        перенос: { открытьСайт("cabinet.php?go=import") })
        case .шаги:
            ШагиПодачи(модель: модель, открытьСайт: { хвост in открытьСайт(хвост) })
        }
    }

    private func войти() {
        if Config.нативныйВход {
            модель.войти = true
        } else {
            открытьСайт("cabinet.php")
        }
    }

    /// «✕»: черновик остаётся (сайт пишет его сам при каждом вводе), мастер закрывается.
    private func закрыть() {
        модель.записатьЧерновик()
        модель.остановить()
        ПодачаОкно.shared.цель = nil
    }

    /// Страница сайта /kz/<язык>/<хвост>: мастер закрыть, потом открыть её — слой сайта лежит под мастером.
    private func открытьСайт(_ хвост: String) {
        guard let адрес = Config.страницаСайта(хвост) else { return }
        /* TestFlight 1.10: «Пройти верификацию» — eGov листом поверх мастера (ОкноEgov): черновик остаётся на экране. */
        if ОкноEgov.включено && ОкноEgov.этоEgov(адрес) {
            ОкноEgov.открыть(адрес)
            return
        }
        закрытьИОткрыть(адрес)
    }

    private func закрытьИОткрыть(_ адрес: URL) {
        закрыть()
        let открытьСтраницу = открыть
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            открытьСтраницу(адрес)
        }
    }

    private func итогНажат(_ действие: ОкноИтогаПодачи.Действие, _ итог: ИтогПодачи) {
        switch действие {
        case .готово:
            модель.итог = nil
            switch итог {
            case .опубликовано, .ждётВерификации:
                модель.закрытьМастер(вкладка: .published)
            case .наПроверке, .отклонено, .сохраненоИИ, .неактивные, .лимит, .запрещено:
                модель.закрытьМастер(вкладка: .inactive)
            }
        case .верификация:
            модель.итог = nil
            модель.закрытьМастер(вкладка: nil)
            /* Окно «Стать продавцом» (ЛистВерификации), когда мастер уедет; сама проверка eGov — страницей сайта. */
            let адрес = Config.страницаСайта("cabinet.php?go=verify")
            if !ОкнаПриложения.shared.показать(.верификация, задержка: 800_000_000, запасной: адрес) {
                открытьСайтПозже("cabinet.php?go=verify")
            }
        case .слоты:
            /* 🔴 Слоты — деньги: при Config.цифровыеПокупки — окно App Store, иначе страница сайта. */
            модель.итог = nil
            модель.закрытьМастер(вкладка: .inactive)
            if Config.цифровыеПокупки {
                ЛистУслугиApple.показать(.слоты)
            } else {
                открытьСайтПозже("cabinet.php?go=items")
            }
        }
    }

    /// Экран после подачи (ЭкранПослеПодачи): опубликованное — вкладка «Опубликованные», на проверке — «Неактивные».
    private func послеПодачиНажат(_ действие: ЭкранПослеПодачи.Действие, _ итог: ИтогПодачи) {
        let id = ЭкранПослеПодачи.номер(итог)
        let вкладка: ВкладкаОбъявлений = ЭкранПослеПодачи.опубликовано(итог) ? .published : .inactive
        switch действие {
        case .продвинуть:
            /* 🔴 Деньги: продвижение — через App Store при Config.цифровыеПокупки (окно поверх мастера, экран остаётся),
               иначе страница сайта ?promote=<id>, как «Продвинуть» в «Моих объявлениях». */
            if Config.цифровыеПокупки {
                ЛистУслугиApple.показать(.продвижение, цель: id)
            } else {
                модель.итог = nil
                модель.закрытьМастер(вкладка: вкладка)
                let код = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
                открытьСайтПозже("cabinet.php?promote=" + код)
            }
        case .посмотреть:
            модель.открытьОбъявлениеПослеПодачи(id, запасной: открыть)
        case .мои, .закрыть:
            модель.итог = nil
            модель.закрытьМастер(вкладка: вкладка)
        case .ещё:
            модель.податьЕщё()
        }
    }

    /// После закрытия мастера «Мои объявления» открываются сами; страница сайта — поверх них.
    private func открытьСайтПозже(_ хвост: String) {
        guard let адрес = Config.страницаСайта(хвост) else { return }
        let открытьСтраницу = открыть
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            открытьСтраницу(адрес)
        }
    }

    @ViewBuilder
    private var плашкаВнизу: some View {
        if let текст = модель.плашка {
            Text(текст)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.зелёный, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Шапка

/// Шапка #add-screen: «✕», заголовок и подзаголовок.
struct ШапкаПодачи: View {
    let правка: Bool
    let закрыть: () -> Void

    init(правка: Bool, закрыть: @escaping () -> Void) {
        self.правка = правка
        self.закрыть = закрыть
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .frame(width: 40, height: 40)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ПодачаText.т("close"))
            VStack(alignment: .leading, spacing: 1) {
                Text(ПодачаText.т(правка ? "edit_title" : "form_title_new"))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(ПодачаText.т(правка ? "edit_sub" : "form_hero_sub"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }
}

// MARK: - Стартовый экран «Что размещаете?»

struct СтартПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let работа: () -> Void
    let перенос: () -> Void

    init(модель: ПодачаМодель, работа: @escaping () -> Void, перенос: @escaping () -> Void) {
        self.модель = модель
        self.работа = работа
        self.перенос = перенос
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Плитка: ключ, заголовок, подпись, значок.
    private struct Плитка: Identifiable {
        let id: String
        let заголовок: String
        let подпись: String
        let значок: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if модель.старт != .корень {
                    Button {
                        назад()
                    } label: {
                        Label(т("back"), systemImage: "chevron.backward")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.акцент)
                    }
                    .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(вопрос)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(подсказка)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if модель.старт == .аренда {
                    HStack(spacing: 8) {
                        ЧипПодачи(т("as_rent_day"), выбран: периодАренды == "day") { периодАренды = "day" }
                        ЧипПодачи(т("as_rent_month"), выбран: периодАренды == "month") { периодАренды = "month" }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                          spacing: 10) {
                    ForEach(плитки) { п in
                        плитка(п)
                    }
                }
                if модель.старт == .корень {
                    Button(action: перенос) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Theme.акцент)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(т("li_entry_t"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.текст)
                                Text(т("li_entry_s"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .flipsForRightToLeftLayoutDirection(true)
                                .foregroundStyle(Theme.текстВторой)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    @State private var периодАренды = "day"

    private func плитка(_ п: Плитка) -> some View {
        Button {
            нажата(п.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: п.значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 42, height: 42)
                    .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                Text(п.заголовок)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !п.подпись.isEmpty {
                    Text(п.подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .accessibilityElement(children: .combine)
    }

    private var вопрос: String {
        switch модель.старт {
        case .корень: return т("as_root_q")
        case .товар: return т("as_goods_q")
        case .одежда: return т("as_cloth_q")
        case .животные: return т("as_anim_q")
        case .аренда: return т("as_rent_q")
        case .сделка: return т("as_rl_deal_q")
        case .видНедвижимости: return т("as_rl_kind_q")
        case .транспорт: return т("as_auto_q")
        }
    }

    private var подсказка: String {
        switch модель.старт {
        case .корень: return т("as_root_s")
        case .товар, .одежда, .животные: return т("as_goods_s")
        case .аренда: return т("as_rent_s")
        case .сделка: return т("as_rl_deal_s")
        case .видНедвижимости: return т("as_rl_kind_s")
        case .транспорт: return т("as_auto_s")
        }
    }

    /// _ASTART, _ASTART_GOODS, _ASTART_CLOTH, _ASTART_ANIMALS, _ASTART_RENT, _ASTART_REALTY, _ASTART_AUTO сайта.
    private var плитки: [Плитка] {
        switch модель.старт {
        case .корень:
            return [
                Плитка(id: "clothing", заголовок: т("as_clothing"), подпись: т("as_clothing_s"), значок: "tshirt"),
                Плитка(id: "animals", заголовок: т("as_animals"), подпись: т("as_animals_s"), значок: "pawprint"),
                Плитка(id: "goods", заголовок: т("as_goods"), подпись: т("as_goods_sub"), значок: "shippingbox"),
                Плитка(id: "realty", заголовок: т("as_realty"), подпись: т("as_realty_s"), значок: "house"),
                Плитка(id: "auto", заголовок: т("as_auto"), подпись: т("as_auto_sub"), значок: "car"),
                Плитка(id: "services", заголовок: т("as_services"), подпись: т("as_services_s"), значок: "wrench.and.screwdriver"),
                Плитка(id: "jobs", заголовок: т("as_jobs"), подпись: т("as_jobs_s"), значок: "briefcase"),
                Плитка(id: "rentgood", заголовок: т("as_rentgood"), подпись: т("as_rentgood_s"), значок: "arrow.triangle.2.circlepath")
            ]
        case .товар:
            return [
                Плитка(id: "smartphones|phone", заголовок: т("g_phone"), подпись: т("g_phone_s"), значок: "iphone"),
                Плитка(id: "laptops|laptop", заголовок: т("g_laptop"), подпись: т("g_laptop_s"), значок: "laptopcomputer"),
                Плитка(id: "appliances|appliance", заголовок: т("g_appl"), подпись: т("g_appl_s"), значок: "washer"),
                Плитка(id: "tv-audio|appliance", заголовок: т("g_tv"), подпись: т("g_tv_s"), значок: "tv"),
                Плитка(id: "furniture|furniture", заголовок: т("g_furn"), подпись: т("g_furn_s"), значок: "sofa"),
                Плитка(id: "|other", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .одежда:
            return [
                Плитка(id: "womens-clothing|clothes", заголовок: т("c_women"), подпись: т("c_women_s"), значок: "tshirt"),
                Плитка(id: "mens-clothing|clothes", заголовок: т("c_men"), подпись: т("c_men_s"), значок: "tshirt"),
                Плитка(id: "kids-clothing|clothes", заголовок: т("c_kids"), подпись: т("c_kids_s"), значок: "figure.and.child.holdinghands"),
                Плитка(id: "shoes|shoes", заголовок: т("c_shoes"), подпись: т("c_shoes_s"), значок: "shoeprints.fill"),
                Плитка(id: "bags-accessories|clothes", заголовок: т("c_bags"), подпись: т("c_bags_s"), значок: "bag"),
                Плитка(id: "jewelry|other", заголовок: т("c_jewel"), подпись: т("c_jewel_s"), значок: "sparkles")
            ]
        case .животные:
            return [
                Плитка(id: "dogs|", заголовок: т("a_dogs"), подпись: т("a_dogs_s"), значок: "pawprint"),
                Плитка(id: "cats|", заголовок: т("a_cats"), подпись: т("a_cats_s"), значок: "cat"),
                Плитка(id: "birds|", заголовок: т("a_birds"), подпись: т("a_birds_s"), значок: "bird"),
                Плитка(id: "livestock|", заголовок: т("a_stock"), подпись: т("a_stock_s"), значок: "hare"),
                Плитка(id: "rodents|", заголовок: т("a_rod"), подпись: т("a_rod_s"), значок: "hare"),
                Плитка(id: "fish-aquariums|", заголовок: т("a_fish"), подпись: т("a_fish_s"), значок: "fish"),
                Плитка(id: "pet-food-care|", заголовок: т("a_food"), подпись: т("a_food_s"), значок: "takeoutbag.and.cup.and.straw"),
                Плитка(id: "animals|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "pawprint")
            ]
        case .аренда:
            return [
                Плитка(id: "power-tools|", заголовок: т("r_tools"), подпись: т("r_tools_s"), значок: "hammer"),
                Плитка(id: "electronics|", заголовок: т("r_tech"), подпись: т("r_tech_s"), значок: "camera"),
                Плитка(id: "sport|", заголовок: т("r_sport"), подпись: т("r_sport_s"), значок: "figure.hiking"),
                Плитка(id: "home-garden|", заголовок: т("r_home"), подпись: т("r_home_s"), значок: "leaf"),
                Плитка(id: "|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .сделка:
            return [
                Плитка(id: "sale", заголовок: т("as_rl_sale"), подпись: "", значок: "house"),
                Плитка(id: "rent", заголовок: т("as_rl_rent"), подпись: "", значок: "key")
            ]
        case .видНедвижимости:
            return [
                Плитка(id: "apartment|apartments", заголовок: т("rl_flat"), подпись: т("rl_flat_s"), значок: "building.2"),
                Плитка(id: "house|houses", заголовок: т("rl_house"), подпись: т("rl_house_s"), значок: "house"),
                Плитка(id: "commercial|commercial-realty", заголовок: т("rl_office"), подпись: т("rl_office_s"), значок: "building"),
                Плитка(id: "land|land", заголовок: т("rl_land"), подпись: т("rl_land_s"), значок: "map")
            ]
        case .транспорт:
            return [
                Плитка(id: "cars", заголовок: т("t_cars"), подпись: т("t_cars_s"), значок: "car"),
                Плитка(id: "motorcycles", заголовок: т("t_moto"), подпись: т("t_moto_s"), значок: "bicycle"),
                Плитка(id: "trucks-special", заголовок: т("t_truck"), подпись: т("t_truck_s"), значок: "truck.box"),
                Плитка(id: "auto-parts", заголовок: т("t_parts"), подпись: т("t_parts_s"), значок: "gearshape.2"),
                Плитка(id: "water-transport", заголовок: т("t_water"), подпись: т("t_water_s"), значок: "sailboat")
            ]
        }
    }

    /// ADD_HINTS сайта: подсказка Kliko AI по чипу — идёт на сервер как есть (по-русски, её читает модель).
    private static let подсказки: [String: String] = [
        "phone": "Это смартфон/мобильный телефон", "laptop": "Это ноутбук", "clothes": "Это одежда",
        "shoes": "Это обувь", "furniture": "Это мебель", "appliance": "Это бытовая техника"
    ]

    private func нажата(_ id: String) {
        switch модель.старт {
        case .корень:
            if id == "jobs" {
                /* Мастер «Работы» шлёт в /api/jobs.php свой набор полей (jobWizOpen) — он остаётся страницей сайта. */
                работа()
                return
            }
            модель.выбратьПлитку(id)
        case .товар, .одежда:
            let части = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let раздел = части.first ?? ""
            let чип = части.count > 1 ? части[1] : ""
            let тип = "goods"
            модель.применитьСтарт(тип: тип, раздел: раздел, плитка: подписьПлитки(id), подсказка: Self.подсказки[чип] ?? "")
        case .животные:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "goods", раздел: раздел, плитка: подписьПлитки(id), подсказка: "")
        case .аренда:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "rentgood", раздел: раздел, плитка: подписьПлитки(id), подсказка: "",
                                  период: периодАренды)
        case .сделка:
            модель.старт = .видНедвижимости(id)
        case .видНедвижимости(let сделка):
            let части = id.split(separator: "|").map(String.init)
            guard части.count == 2 else { return }
            модель.применитьНедвижимость(сделка: сделка, вид: части[0], раздел: части[1])
        case .транспорт:
            /* _asAutoGo: ADD_TYPE="" — тип «транспорт» без отдельного значения; уточнение кузова — на шаге «Данные». */
            модель.применитьСтарт(тип: "", раздел: id, плитка: подписьПлитки(id), подсказка: "")
        }
    }

    private func подписьПлитки(_ id: String) -> String {
        плитки.first(where: { $0.id == id })?.заголовок ?? ""
    }

    private func назад() {
        switch модель.старт {
        case .видНедвижимости:
            модель.старт = .сделка
        default:
            модель.старт = .корень
        }
    }
}

// MARK: - Окно «Kliko AI распознаёт товар»

struct ОкноРаспознавания: View {
    let шаг: Int

    init(шаг: Int) {
        self.шаг = шаг
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SiteSpinner()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ПодачаText.т(шаг >= 4 ? "airec_done_t" : "airec_t_light"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        Text(ПодачаText.т(шаг >= 4 ? "airec_done_l" : "airec_s_light"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                ForEach(1...4, id: \.self) { номер in
                    HStack(spacing: 8) {
                        Image(systemName: номер < шаг || шаг >= 4 ? "checkmark.circle.fill" : (номер == шаг ? "circle.dotted" : "circle"))
                            .foregroundStyle(номер <= шаг ? Theme.зелёныйЯркий : Theme.текстВторой)
                            .accessibilityHidden(true)
                        Text(ПодачаText.т("airec_l" + String(номер)))
                            .font(.system(size: 14, weight: номер == шаг ? Font.Weight.bold : Font.Weight.regular))
                            .foregroundStyle(номер <= шаг ? Theme.текст : Theme.текстВторой)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 360, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .padding(24)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Окно итога подачи (§2.5.2)

struct ОкноИтогаПодачи: View {
    enum Действие { case готово, верификация, слоты }

    let итог: ИтогПодачи
    let заголовок: String
    let действие: (Действие) -> Void

    init(итог: ИтогПодачи, заголовок: String, действие: @escaping (Действие) -> Void) {
        self.итог = итог
        self.заголовок = заголовок
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: значок)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(цвет)
                    .accessibilityHidden(true)
                Text(заглавие)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                кнопки
            }
            .padding(20)
            .frame(maxWidth: 400)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .padding(20)
        }
    }

    @ViewBuilder
    private var кнопки: some View {
        switch итог {
        case .опубликовано(let id):
            if let ссылка = Config.url("/marketplace.php?item=" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)),
               !id.isEmpty {
                ShareLink(item: ссылка, subject: Text(заголовок), message: Text(заголовок)) {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(Theme.акцент)
            }
            /* Продвижение через App Store — после публикации, уже для готового объявления (ПродуктыApple). */
            if Config.цифровыеПокупки && !id.isEmpty {
                КнопкаПодачиВторая(ПокупкиAppleText.т("promote_now")) { ЛистУслугиApple.показать(.продвижение, цель: id) }
            }
            КнопкаПодачи(т("done")) { действие(.готово) }
        case .ждётВерификации:
            КнопкаПодачи(т("held_verify_go")) { действие(.верификация) }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .неактивные(_, let верификация):
            if верификация {
                КнопкаПодачи(т("verify_plus5")) { действие(.верификация) }
                КнопкаПодачиВторая(т("limit_more")) { действие(.слоты) }
            } else {
                КнопкаПодачи(т("slots_more")) { действие(.слоты) }
            }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .лимит:
            КнопкаПодачи(т("limit_more")) { действие(.слоты) }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .наПроверке, .отклонено, .сохраненоИИ, .запрещено:
            КнопкаПодачи(т("ok_btn")) { действие(.готово) }
        }
    }

    private var значок: String {
        switch итог {
        case .опубликовано: return "checkmark.seal.fill"
        case .наПроверке: return "clock"
        case .отклонено, .запрещено: return "xmark.octagon"
        case .сохраненоИИ, .ждётВерификации: return "doc.badge.clock"
        case .неактивные, .лимит: return "square.stack.3d.up"
        }
    }

    private var цвет: Color {
        switch итог {
        case .опубликовано: return Theme.зелёныйЯркий
        case .отклонено, .запрещено: return КраскаОбъявлений.плохоТекст
        default: return КраскаОбъявлений.предупреждениеТекст
        }
    }

    private var заглавие: String {
        switch итог {
        case .опубликовано: return т("published")
        case .наПроверке: return т("mod_wait_t")
        case .отклонено: return т("mod_rej_t")
        case .сохраненоИИ: return т("mod_saved_t")
        case .ждётВерификации: return т("held_pub_t")
        case .неактивные: return т("held_t")
        case .лимит: return т("limit_t")
        case .запрещено(let з, _): return з
        }
    }

    private var текст: String {
        switch итог {
        case .опубликовано: return т("published_s")
        case .наПроверке: return т("mod_wait_b") + "\n" + т("mod_wait_b2") + " — " + т("mod_wait_b3")
        case .отклонено(let причина): return причина
        case .сохраненоИИ(let часы):
            return т("mod_blk_b") + " " + (часы.isEmpty ? "24" : часы) + " " + т("mod_h") + "\n" + т("mod_blk_b2")
        case .ждётВерификации(let ошибка): return ошибка.isEmpty ? т("held_pub_m") : т("held_pub_m") + "\n\n" + ошибка
        case .неактивные(let т1, _): return т1
        case .лимит(let т1): return т1
        case .запрещено(_, let т1): return т1
        }
    }
}
