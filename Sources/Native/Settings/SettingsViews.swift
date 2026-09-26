import SwiftUI
import PhotosUI
import UIKit

/**
 ПРОФИЛЬ И НАСТРОЙКИ ВО ВКЛАДКЕ «КАБИНЕТ» — ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Лист сайта «Настройки» (cabSettings, карта §1.5.2 и §6.2.0) не отдельным экраном, а разделами самого «Кабинета» —
 так прежние настройки приложения (этап 9: Face ID, уведомления, данные на телефоне; этап 15: оформление) остаются на
 своих местах, а группы сайта встают рядом, в его порядке:
   · шапка — карточка hero сайта: фото (нажатие — «Сменить фото»: upload_photo + set_avatar), имя, значок «Проверенный
     продавец», номер, «скрыт от покупателей · связь через чат», подписчики;
   · «Аккаунт»: «Профиль» (витрина SELLER_URL, если она есть), «Пароль», «Номер и контакты», «Чаты» и верификация
     (статус; пройти её — страницей сайта ?go=verify, eGov живёт там);
   · «Объявления»: «Мои категории», «Регион и адрес», «Режим работы», «Личные данные на фото»;
   · «Продажи и оплата»: «Гарант-сделка · вкл/выкл», «Рассрочка и кредит», «Бронь товара после оплаты»;
   · «Безопасность» (раздел этапа 9): к Face ID добавлена строка «Устройства и входы»;
   · «Приложение»: «Начало работы» (мастер), «Язык · Рус»; тема — раздел «Оформление» этапа 15, её выбор уходит и в
     аккаунт (ui_prefs), как у переключателя темы сайта;
   · «Удалить аккаунт» — страницей сайта (необратимо, сайт сам ведёт через eGov или пароль, §8.11).
 Рубильник Config.нативныеНастройки: false — разделов и шапки нет, кабинет как на этапе 45.
 */

// MARK: - Шапка профиля (hero)

struct ШапкаПрофиля: View {
    let профиль: ПрофильКабинета
    /// Этап 47: глаз карточки «Кошелёк» прячет и номер — как toggleHidePrivate сайта (баланс и телефон шапки).
    @ObservedObject private var кошелёк = КошелёкМодель.shared
    @State private var выбор: PhotosPickerItem? = nil
    @State private var грузится = false

    init(профиль: ПрофильКабинета) {
        self.профиль = профиль
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PhotosPicker(selection: $выбор, matching: .images) {
                аватар
            }
            .buttonStyle(.plain)
            .disabled(грузится)
            .accessibilityLabel(тН(грузится ? "a11y_uploading" : "a11y_avatar"))
            .accessibilityHint(тН("av_change"))
            сведения
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        )
        .overlay(alignment: .topLeading) {
            RadialGradient(colors: [Theme.шапкаБлик, Color.clear], center: .topLeading, startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .onChange(of: выбор) { _, новый in
            guard let новый else { return }
            загрузить(новый)
        }
    }

    private var сведения: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(профиль.имя.isEmpty ? CabinetText.т("signed_in") : профиль.имя)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                if профиль.верифицирован {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: Theme.hex(0x7FE6B0)))
                        .accessibilityLabel(тН("a11y_verified"))
                }
            }
            if !профиль.телефонПоказ.isEmpty {
                Text(кошелёк.скрыто && Config.нативныйКошелёк ? "•• ••• •• ••" : профиль.телефонПоказ)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .monospacedDigit()
            }
            if профиль.скрытНомер {
                Text(тН("phone_hidden"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            if !профиль.подписчики.isEmpty {
                Label(профиль.подписчики, systemImage: "person.2")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.86))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// #hero-av: фото или первая буква имени на зелёном, значок камеры в углу.
    private var аватар: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                Text(String(профиль.имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.white)
                if let адрес = Config.url(профиль.аватар), !профиль.аватар.isEmpty {
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 52, height: 52)
                    .clipped()
                }
                if грузится {
                    Color.black.opacity(0.35)
                    ProgressView().tint(Color.white)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(форма)
            .overlay { форма.strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5) }
            Image(systemName: "camera.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 18, height: 18)
                .background(Theme.поверхность, in: Circle())
                .offset(x: 3, y: 3)
                .accessibilityHidden(true)
        }
    }

    /// avatarUpload: больше 12 МБ — «Фото больше 12 МБ»; дальше — как фото объявления (1280 px, водяной знак, JPEG),
    /// upload_photo и set_avatar. Только по выбору фото человеком.
    private func загрузить(_ пункт: PhotosPickerItem) {
        guard !грузится else { return }
        грузится = true
        Task { @MainActor in
            defer {
                грузится = false
                выбор = nil
            }
            let модель = НастройкиМодель.shared
            guard let данные = try? await пункт.loadTransferable(type: Data.self) else {
                модель.показать(тН("err_generic"))
                return
            }
            guard данные.count <= 12_582_912 else {
                модель.показать(тН("av_big"))
                return
            }
            let готовое = await Task.detached(priority: .userInitiated) { () -> ГотовоеФото? in
                ОбработкаФото.подготовить(данные)
            }.value
            guard let готовое else {
                модель.показать(тН("err_generic"))
                return
            }
            do {
                let j = try await НастройкиAPI.сменитьАватар(картинка: готовое.картинка, миниатюра: готовое.миниатюра)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let адрес = МоиОбъявленияAPI.строка(j["_url"])
                    модель.изменить { п in
                        if !адрес.isEmpty { п.аватар = адрес }
                    }
                    модель.показать(тН("av_saved"))
                } else {
                    модель.показать(НастройкиAPI.ошибка(j))
                }
            } catch {
                модель.показать(тН("err_no_conn"))
            }
        }
    }
}

// MARK: - Разделы «Аккаунт», «Объявления», «Продажи и оплата»

struct РазделыНастроек: View {
    let профиль: ПрофильКабинета
    let открыть: (URL) -> Void

    init(профиль: ПрофильКабинета, открыть: @escaping (URL) -> Void) {
        self.профиль = профиль
        self.открыть = открыть
    }

    var body: some View {
        Group {
            разделАккаунта
            разделОбъявлений
            разделПродаж
        }
    }

    private var разделАккаунта: some View {
        Section {
            if !профиль.витрина.isEmpty {
                СтрокаНаСайт(название: тН("hero_profile"), значок: "storefront") {
                    /* Своя витрина (seller.php?id=) — свой экран; иной адрес магазина — как раньше. */
                    if let адрес = Config.url(профиль.витрина), !ОкноПродавца.перехватить(адрес) { открыть(адрес) }
                }
            }
            СтрокаНастройки(название: тН("hero_pass"), значок: "lock", окно: .пароль)
            СтрокаНастройки(название: тН("cabset_num"), значок: "phone", окно: .номер)
            СтрокаНастройки(название: тН("cabset_chat"), значок: "text.bubble", окно: .чаты)
            СтрокаВерификации(профиль: профиль, открыть: открыть)
        } header: {
            Text(тН("cabset_account"))
        }
    }

    private var разделОбъявлений: some View {
        Section {
            СтрокаНастройки(название: тН("cabset_cats"), значок: "square.grid.2x2", окно: .категории)
            СтрокаНастройки(название: тН("cabset_geo"), значок: "mappin.and.ellipse", окно: .регион)
            СтрокаНастройки(название: тН("cabset_hours"), значок: "clock", окно: .часы)
            СтрокаНастройки(название: тН("cabset_redact"), значок: "eye.slash", окно: .фото)
        } header: {
            Text(тН("cabset_listings"))
        }
    }

    private var разделПродаж: some View {
        Section {
            СтрокаНастройки(название: тН("cabset_escrow") + " · " + тН(профиль.гарантВыкл ? "esc_off_short" : "esc_on_short"),
                            значок: "checkmark.shield", окно: .гарант)
            СтрокаНастройки(название: тН("cabset_pay"), значок: "creditcard", окно: .оплата)
            СтрокаНастройки(название: тН("cabset_reserve"), значок: "hourglass", окно: .бронь)
        } header: {
            Text(тН("cabset_sales"))
        }
    }
}

/// Строка листа настроек сайта (.cabset-row): значок, название, стрелка — открывает окно этой настройки.
struct СтрокаНастройки: View {
    let название: String
    let значок: String
    let окно: НастройкиМодель.Окно

    var body: some View {
        Button {
            НастройкиМодель.shared.открыть(окно)
        } label: {
            HStack {
                Label {
                    Text(название).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: значок).foregroundStyle(Theme.green2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Строка, которая открывает страницу сайта, — со стрелкой «наружу», как у остальных таких строк кабинета.
struct СтрокаНаСайт: View {
    let название: String
    let значок: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack {
                Label {
                    Text(название).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: значок).foregroundStyle(Theme.green2)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Верификация: пройдена — «Проверенный продавец»; нет — «Верификация через eGov» (страница сайта ?go=verify, при
/// выключенном BIO_ON — текст сайта ver_off); «Отклонено» — если сервер нарисовал баннер отказа.
struct СтрокаВерификации: View {
    let профиль: ПрофильКабинета
    let открыть: (URL) -> Void

    var body: some View {
        if профиль.верифицирован {
            Label {
                Text(тН("ver_ok")).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.проверен)
            }
        } else {
            Button {
                НастройкиВерификация.открыть(профиль: профиль, открыть: открыть)
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(тН("ver_row")).foregroundStyle(.primary)
                            Text(тН("ver_row_s"))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield").foregroundStyle(Theme.green2)
                    }
                    Spacer(minLength: 8)
                    if профиль.проверкаОтклонена {
                        Text(тН("ver_rejected"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(КраскаОбъявлений.плохоТекст)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(КраскаОбъявлений.плохоФон, in: Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// requestVerification сайта: BIO_ON выключен — «временно недоступно»; иначе окно «Стать продавцом» (verPromo сайта,
/// ЛистВерификации) — и уже из него страница /kz/<язык>/cabinet?go=verify (eGov живёт там). Слоя окон нет — страница
/// сразу, как раньше. задержка — вызывающий лист или алерт ещё уезжает.
@MainActor
enum НастройкиВерификация {
    static func открыть(профиль: ПрофильКабинета?, открыть: (URL) -> Void, задержка: UInt64 = 0) {
        if let п = профиль, !п.eGovВкл {
            НастройкиМодель.shared.показать(тН("ver_off"))
            return
        }
        let адрес = Config.страницаСайта("cabinet?go=verify")
        if ОкнаПриложения.shared.показать(.верификация, задержка: задержка, запасной: адрес) { return }
        if let адрес { открыть(адрес) }
    }
}

/// «Устройства и входы» в разделе «Безопасность» этапа 9.
struct СтрокаУстройств: View {
    var body: some View {
        СтрокаНастройки(название: тН("sec_devices"), значок: "laptopcomputer.and.iphone", окно: .устройства)
    }
}

/// «Приложение»: «Начало работы» и «Язык · Рус».
struct РазделПриложения: View {
    let профиль: ПрофильКабинета

    var body: some View {
        Section {
            Button {
                НастройкиМодель.shared.открытьМастер()
            } label: {
                HStack {
                    Label {
                        Text(тН("cabwiz_t")).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "flag").foregroundStyle(Theme.green2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            if !профиль.языки.isEmpty {
                СтрокаНастройки(название: названиеЯзыка, значок: "globe", окно: .язык)
            }
        } header: {
            Text(тН("cabset_app"))
        }
    }

    /// «Язык · Рус» — имя текущего из LANG_OPTS.
    private var названиеЯзыка: String {
        let имя = профиль.языки.first(where: { $0.код == профиль.язык })?.имя ?? ""
        return тН("cabset_lang") + (имя.isEmpty ? "" : " · " + имя)
    }
}

/// «Удалить аккаунт» — свой лист шагов acctDelOpen сайта (ЛистУдаленияАккаунта, карта §1.5.7): account_delete_send и
/// account_delete_confirm; подтверждение eGov — страницей сайта. Слоя окон нет — кабинет сайта, как раньше.
struct РазделУдаленияАккаунта: View {
    let открыть: (URL) -> Void

    var body: some View {
        Section {
            Button(role: .destructive) {
                let сайт = Config.страницаСайта("cabinet.php")
                if !ОкнаПриложения.shared.показать(.удалениеАккаунта, запасной: сайт), let адрес = сайт { открыть(адрес) }
            } label: {
                HStack {
                    Label(тН("cabset_del"), systemImage: "trash")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

// MARK: - Окна поверх кабинета

/// Окна настроек, вопрос «Применить к объявлениям?», мастер и плашка — на вкладке «Кабинет».
struct НастройкиКабинета: ViewModifier {
    let открыть: (URL) -> Void
    @ObservedObject private var модель = НастройкиМодель.shared

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $модель.окно) { окно in
                ЛистОкнаНастроек(окно: окно, открыть: открыть)
            }
            .sheet(item: $модель.применить) { поле in
                ОкноПрименения(поле: поле)
                    .presentationDetents([.medium])
            }
            .sheet(item: $модель.мастер) { мастер in
                ЛистНачалаРаботы(авто: мастер.авто, открыть: открыть)
            }
            .alert(тН("ph_changed_t"), isPresented: $модель.номерЖдётВерификации) {
                Button(тН("ph_go")) {
                    НастройкиВерификация.открыть(профиль: модель.профиль, открыть: открыть, задержка: 450_000_000)
                }
                Button(тН("later"), role: .cancel) {}
            } message: {
                Text(тН("ph_changed_m"))
            }
            .overlay(alignment: .bottom) { плашка }
            .onAppear { ОткрытьСтраницуНастроек.действие = открыть }
    }

    @ViewBuilder
    private var плашка: some View {
        if let текст = модель.плашка {
            Text(текст)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.зелёный, in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 96)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}

/// Лист одного окна настроек: профиль ещё не прочитан (ссылка ?open=password на холодном старте) — сначала страница.
struct ЛистОкнаНастроек: View {
    let окно: НастройкиМодель.Окно
    let открыть: (URL) -> Void
    @ObservedObject private var модель = НастройкиМодель.shared
    @Environment(\.dismiss) private var закрыть

    init(окно: НастройкиМодель.Окно, открыть: @escaping (URL) -> Void) {
        self.окно = окно
        self.открыть = открыть
    }

    var body: some View {
        if окно == .устройства {
            ЛистУстройств(открыть: открыть)
        } else {
            ЛистНастройки(заголовок: заголовок) {
                if let п = модель.профиль {
                    форма(п)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(тН("loading")).foregroundStyle(Theme.текстВторой)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await модель.загрузить() }
                }
            }
        }
    }

    private var заголовок: String {
        guard окно == .пароль else { return окно.заголовок }
        return тН((модель.профиль?.парольСвой ?? true) ? "pw_title_change" : "pw_title_set")
    }

    /// Закрыть лист; было что применить к объявлениям — вопрос после закрытия (cabApplyPrefAsk).
    private func готово(_ поле: ПолеПрименения?) {
        закрыть()
        if let поле { модель.спроситьПрименить(поле) }
    }

    @ViewBuilder
    private func форма(_ п: ПрофильКабинета) -> some View {
        switch окно {
        case .пароль:
            ФормаПароля(свой: п.парольСвой, готово: { готово(nil) })
        case .номер:
            ФормаНомера(профиль: п, готово: { готово(nil) })
        case .чаты:
            ФормаЧатов(профиль: п, готово: { готово(nil) })
        case .категории:
            ФормаКатегорий(профиль: п, кнопка: тН("save"), готово: { готово(nil) })
        case .регион:
            ФормаРегиона(профиль: п, кнопка: тН("save"), готово: { поле in готово(поле) })
        case .часы:
            ФормаЧасов(профиль: п, кнопка: тН("save"), готово: { поле in готово(поле) })
        case .фото:
            ФормаФото(профиль: п, кнопка: тН("save"), готово: { готово(nil) })
        case .гарант:
            ФормаГаранта(профиль: п, готово: { поле in готово(поле) })
        case .оплата:
            ФормаОплаты(профиль: п, готово: { готово(nil) })
        case .бронь:
            ФормаБрони(профиль: п, готово: { готово(nil) })
        case .язык:
            ФормаЯзыка(профиль: п, готово: { готово(nil) })
        case .устройства:
            EmptyView()
        }
    }
}

/// «Применить … к объявлениям?» (cabApplyPrefAsk → cabApplyRun → cabApplyDone): «Пропустить» / «Применить», затем
/// «Применяем…» и итог: «Готово» + «Применено к N объявлениям.» или «Не вышло» + причина, «Понятно».
struct ОкноПрименения: View {
    let поле: ПолеПрименения
    @Environment(\.dismiss) private var закрыть
    @State private var этап: Этап = .вопрос

    enum Этап: Equatable {
        case вопрос
        case идёт
        case итог(удачно: Bool, текст: String)
    }

    init(поле: ПолеПрименения) {
        self.поле = поле
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: значок)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(цветЗначка)
                .frame(width: 60, height: 60)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if этап == .идёт {
                ProgressView()
                    .padding(.vertical, 6)
            } else {
                Text(пояснение)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            кнопки
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.фонСтраницы)
        .interactiveDismissDisabled(этап == .идёт)
    }

    private var значок: String {
        switch этап {
        case .вопрос, .идёт: return поле.значок
        case .итог(let удачно, _): return удачно ? "checkmark" : "exclamationmark.triangle"
        }
    }

    private var цветЗначка: Color {
        if case .итог(let удачно, _) = этап, !удачно { return КраскаОбъявлений.предупреждениеТекст }
        return Theme.акцент
    }

    private var заголовок: String {
        switch этап {
        case .вопрос: return поле.заголовок
        case .идёт: return тН("capp_running")
        case .итог(let удачно, _): return тН(удачно ? "capp_done" : "capp_fail_t")
        }
    }

    private var пояснение: String {
        switch этап {
        case .итог(_, let текст): return текст
        default: return поле.пояснение
        }
    }

    @ViewBuilder
    private var кнопки: some View {
        switch этап {
        case .вопрос:
            HStack(spacing: 10) {
                Button {
                    закрыть()
                } label: {
                    Text(тН("capp_skip"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                             style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                КнопкаСайта(подпись: тН("capp_run"), идёт: false) { применить() }
            }
        case .идёт:
            EmptyView()
        case .итог:
            КнопкаСайта(подпись: тН("capp_ok"), идёт: false) { закрыть() }
        }
    }

    /// apply_pref_field {field} — только по «Применить». Ошибка — msg || error || «Не удалось применить».
    private func применить() {
        этап = .идёт
        let имя = поле.поле
        Task { @MainActor in
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=apply_pref_field", ["field": имя])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let сколько = МоиОбъявленияAPI.целое(j["count"])
                    этап = .итог(удачно: true, текст: сколько > 0 ? НастройкиText.применено(сколько) : тН("capp_zero"))
                } else {
                    let msg = МоиОбъявленияAPI.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let причина = msg.isEmpty ? НастройкиAPI.ошибка(j) : msg
                    этап = .итог(удачно: false, текст: причина == тН("err_generic") ? тН("capp_fail") : причина)
                }
            } catch {
                этап = .итог(удачно: false, текст: тН("err_net"))
            }
        }
    }
}
