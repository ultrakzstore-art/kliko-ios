import SwiftUI
import UIKit

/**
 ОКНА НАСТРОЕК — ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Каждое — лист сайта .cabset-sheet
 с теми же полями, текстами и порядком: пароль (openChangePassword), номер и контакты (openChangePhone + ppSave), чаты
 (cabPrefChat), мои категории (cabPrefCats), режим работы (cabPrefHours), личные данные на фото (cabPrefRedact), гарант
 (cabPrefEscrow), бронь (cabPrefReserve), язык (cabLangPick). Регион и адрес, рассрочка — SettingsGeoPay.swift.

 Каждая форма — отдельный вид без своей навигации: её показывает и лист настройки (ЛистНастройки), и мастер «Начало
 работы» (там кнопка «Сохранить» становится «Далее», как у сайта — _cabWizДалее). Успех — готово(поле): поле — что
 предложить применить к объявлениям (адрес, режим, гарант) или nil. Запись — только по кнопке; ошибка — текст сервера
 или «Ошибка», обрыв — «Нет соединения», как у сайта; окно при ошибке не закрывается.
 */

func тН(_ ключ: String) -> String { НастройкиText.т(ключ) }

// MARK: - Общие части

/// Лист настройки (.cabset-sheet): полоска сверху, заголовок .cabset-hd b (19/800, разрядка -0,3), крестик .cabset-x
/// плиткой (surf2, радиус 10), содержимое на фоне страницы сайта.
struct ЛистНастройки<Содержимое: View>: View {
    let заголовок: String
    let содержимое: Содержимое
    @Environment(\.dismiss) private var закрыть

    init(заголовок: String, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.содержимое = содержимое()
    }

    var body: some View {
        NavigationStack {
            содержимое
                .scrollContentBackground(.hidden)
                .background(Theme.фонСтраницы)
                .tint(Theme.акцент)
                .navigationTitle(заголовок)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(заголовок)
                            .font(.system(size: 19, weight: .heavy))
                            .tracking(-0.3)
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            закрыть()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.текстВторой)
                                .frame(width: 36, height: 36)
                                .background(Theme.поверхность2,
                                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(тН("close"))
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Нижняя зелёная кнопка листа (.prefcat-save) — строкой без фона.
struct КнопкаНастройки: View {
    let подпись: String
    let идёт: Bool
    let действие: () -> Void

    var body: some View {
        Section {
            КнопкаСайта(подпись: подпись, идёт: идёт, действие: действие)
        }
        .listRowBackground(Color.clear)
        /* Снизу 10 — тень зелёной кнопки не обрезается строкой списка. */
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
    }
}

extension View {
    /// Поле окна настроек сайта: 16, 14 внутри, карточка, рамка 1,5 --line, радиус 12 (openChangePassword).
    func полеНастройкиСайта() -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return self
            .font(.system(size: 16))
            .padding(14)
            .background(Theme.поверхность, in: форма)
            .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1.5) }
    }
}

/// Ошибка под полями (#pw-err, #cp-err сайта).
struct ОшибкаНастройки: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.скидкаТекст)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Подсказка сайта с **жирным** (в словаре — <b>…</b>).
func текстСЖирным(_ строка: String) -> Text {
    if let размеченный = try? AttributedString(markdown: строка) { return Text(размеченный) }
    return Text(строка.replacingOccurrences(of: "**", with: ""))
}

/// Цифры любой клавиатуры — латиницей (цифровая клавиатура арабского телефона даёт «٧٧٧»), остальное как есть.
func цифрыЛатиницей(_ текст: String) -> String {
    var итог = ""
    for символ in текст {
        if !символ.isASCII, let значение = символ.wholeNumberValue, значение >= 0, значение <= 9 {
            итог.append(String(значение))
        } else {
            итог.append(символ)
        }
    }
    return итог
}

/// 20000 → «20 000» (как replace(/\B(?=(\d{3})+(?!\d))/g," ") сайта).
func тысячиНастройки(_ n: Int) -> String {
    let цифры = Array(String(abs(n)))
    var итог = ""
    for (i, ц) in цифры.enumerated() {
        if i > 0 && (цифры.count - i) % 3 == 0 { итог.append(" ") }
        итог.append(ц)
    }
    return (n < 0 ? "-" : "") + итог
}

// MARK: - Пароль (openChangePassword, change_password)

struct ФормаПароля: View {
    let свой: Bool
    let готово: () -> Void
    @State private var старый = ""
    @State private var новый = ""
    @State private var повтор = ""
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(свой: Bool, готово: @escaping () -> Void) {
        self.свой = свой
        self.готово = готово
    }

    /// Как окно сайта: подсказка, три поля столбиком через 10, кнопка, ошибка по центру под ней. «Отмена» — крестик листа.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(тН(свой ? "pw_hint_change" : "pw_hint_set"))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                if свой {
                    SecureField(тН("pw_old_ph"), text: $старый)
                        .textContentType(.password)
                        .полеНастройкиСайта()
                }
                SecureField(тН("pw_new_ph"), text: $новый)
                    .textContentType(.newPassword)
                    .полеНастройкиСайта()
                SecureField(тН("pw_new2_ph"), text: $повтор)
                    .textContentType(.newPassword)
                    .submitLabel(.done)
                    .onSubmit { сохранить() }
                    .полеНастройкиСайта()
                КнопкаСайта(подпись: тН("save"), идёт: идёт) { сохранить() }
                if let ошибка {
                    Text(ошибка)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.скидкаТекст)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Проверки сайта: длина не меньше 6, совпадение; потом {old, new, new2} как есть (сайт пароли не обрезает).
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        guard новый.count >= 6 else {
            ошибка = тН("pw_short")
            return
        }
        guard новый == повтор else {
            ошибка = тН("pw_mismatch")
            return
        }
        идёт = true
        let тело: [String: Any] = ["old": свой ? старый : "", "new": новый, "new2": повтор]
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=change_password", тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    НастройкиМодель.shared.изменить { $0.парольСвой = true }
                    НастройкиМодель.shared.показать(тН("pw_saved"))
                    готово()
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

// MARK: - Номер и контакты (openChangePhone, change_phone → set_contacts; ppSave → set_phone_policy)

struct ФормаНомера: View {
    let профиль: ПрофильКабинета
    let готово: () -> Void
    @State private var номер: String
    @State private var политика: String
    @State private var whatsApp: Bool
    @State private var telegram: String
    @State private var ошибка: String? = nil
    @State private var идёт = false
    @State private var политикаИдёт = false

    init(профиль: ПрофильКабинета, готово: @escaping () -> Void) {
        self.профиль = профиль
        self.готово = готово
        let цифры = НомерКЗ.цифры(профиль.телефон)
        _номер = State(initialValue: цифры.count >= 10 ? НомерКЗ.формат(профиль.телефон) : профиль.телефонПоказ)
        _политика = State(initialValue: профиль.политика)
        let закрыт = профиль.политика == "chat_only" || профиль.политика == "none"
        _whatsApp = State(initialValue: !закрыт && !профиль.whatsAppВыкл)
        _telegram = State(initialValue: профиль.telegram.isEmpty ? "" : "@" + профиль.telegram)
    }

    /// При «Только чат» (и «none») WhatsApp выключен и заблокирован — u() сайта.
    private var whatsAppЗакрыт: Bool { политика == "chat_only" || политика == "none" }

    var body: some View {
        Form {
            Section {
                TextField("+7 (700) 000-00-00", text: номерВвод)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .полеНастройкиСайта()
                    .disabled(профиль.верифицирован)
                    .opacity(профиль.верифицирован ? 0.65 : 1)
                    .accessibilityLabel(тН("ph_title"))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if профиль.верифицирован {
                    Button {
                        перейтиКВерификации()
                    } label: {
                        Label(тН("ph_egov_change"), systemImage: "checkmark.shield")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            } header: {
                (профиль.верифицирован ? Text(тН("ph_hint_v")) : текстСЖирным(тН("ph_hint")))
                    .textCase(nil)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !профиль.варианты.isEmpty {
                Section {
                    /* У сайта под заголовком — только select со значением (#cp-pol), без второй подписи. */
                    Picker(тН("phv_title"), selection: политикаВыбор) {
                        ForEach(профиль.варианты) { вариант in
                            Text(вариант.подпись).tag(вариант.ключ)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(политикаИдёт)
                } header: {
                    Text(тН("phv_title"))
                } footer: {
                    /* Две строки .cpc-hint сайта: пояснение и под ним, через 4 pt, счётчик недели (#cp-polstat) —
                       один шрифт и цвет; снизу отступ до «Способы связи», как margin-top у .cpc-eyebrow. */
                    VStack(alignment: .leading, spacing: 4) {
                        Text(тН("phv_hint"))
                        Text(статистика)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
                }
            }
            Section {
                Toggle(тН("cc_wa_on"), isOn: $whatsApp)
                    .tint(Theme.зелёныйЯркий)
                    .disabled(whatsAppЗакрыт)
                    .opacity(whatsAppЗакрыт ? 0.5 : 1)
                if профиль.telegramВкл {
                    TextField(тН("cc_tg_ph"), text: $telegram)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
            } header: {
                Text(тН("cc_ways_title"))
            } footer: {
                if профиль.telegramВкл { Text(тН("cc_tg_hint")) }
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: тН("save"), идёт: идёт) { сохранить() }
        }
    }

    /// ppStatText: сколько человек за неделю не увидели номер.
    private var статистика: String {
        профиль.неУвидели > 0
            ? тН("phv_blocked_week").replacingOccurrences(of: "{n}", with: String(профиль.неУвидели))
            : тН("phv_blocked_none")
    }

    /// Маска номера — та же, что на экране входа (klkFmt сайта).
    private var номерВвод: Binding<String> {
        Binding(get: { номер }, set: { новое in
            номер = ЭкранВхода.ввод(было: номер, стало: цифрыЛатиницей(новое))
        })
    }

    /// ppSave: выбор уходит сразу, без «Сохранить»; не вышло — выбор назад.
    private var политикаВыбор: Binding<String> {
        Binding(get: { политика }, set: { новая in
            guard новая != политика, !политикаИдёт else { return }
            let была = политика
            политика = новая
            whatsApp = !(новая == "chat_only" || новая == "none") && !профиль.whatsAppВыкл
            сохранитьПолитику(новая, была: была)
        })
    }

    private func сохранитьПолитику(_ новая: String, была: String) {
        политикаИдёт = true
        Task { @MainActor in
            defer { политикаИдёт = false }
            do {
                let j = try await НастройкиAPI.отправить("/cabinet.php?action=set_phone_policy", ["policy": новая],
                                                        отКорня: true)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    НастройкиМодель.shared.изменить { $0.политика = новая }
                    НастройкиМодель.shared.показать(тН("phv_saved"))
                } else {
                    политика = была
                    НастройкиМодель.shared.показать(НастройкиAPI.ошибка(j))
                }
            } catch {
                политика = была
                НастройкиМодель.shared.показать(тН("err_net"))
            }
        }
    }

    /**
     «Сменить номер через eGov» — как у сайта: лист номера закрывается (cpmClose), затем requestVerification() →
     bioKycOpen: форма ИИН и номера из CAB_USER → kyc.php flow_create → окно biometric.kz → flow_result; после удачи
     сервер берёт номер из eGov, bioAfterOk перезагружает кабинет. Окно «Стать продавцом» (ЛистВерификации) здесь не
     годится: верифицированному оно лишь показывает статус. Поэтому сразу окно eGov с ровно этим потоком сайта
     (cabinet.php?go=verify), а после его закрытия профиль перечитывается — в настройках уже новый номер.
     */
    private func перейтиКВерификации() {
        guard профиль.eGovВкл else {
            НастройкиМодель.shared.показать(тН("ver_off"))
            return
        }
        guard let адрес = Config.страницаСайта("cabinet.php?go=verify") else {
            НастройкиМодель.shared.показать(тН("err_net"))
            return
        }
        готово()
        ОкноEgov.открытьПоток(.адрес(адрес), закрыто: {
            Task { @MainActor in
                await НастройкиМодель.shared.загрузить()
            }
        })
    }

    /**
     Порядок сайта: верифицированному change_phone не шлётся (номер меняют через eGov). need_confirm / need_verify —
     номер сохранён, окно «Номер сохранён» с «Пройти», и WhatsApp с Telegram НЕ сохраняются (сайт выходит раньше, §1.5.3).
     Иначе — set_contacts {wa_off, tg}: tg из поля, только если канал Telegram включён, иначе прежний юзернейм.
     */
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        if !профиль.верифицирован, let плохо = НомерКЗ.ошибка(номер) {
            ошибка = плохо.isEmpty ? тН("ph_bad") : плохо
            return
        }
        идёт = true
        let поле = номер
        let whatsAppВыкл = !whatsApp
        let юзернейм = профиль.telegramВкл ? telegram : профиль.telegram
        let верифицирован = профиль.верифицирован
        Task { @MainActor in
            defer { идёт = false }
            do {
                if !верифицирован {
                    let j = try await НастройкиAPI.отправить("cabinet.php?action=change_phone", ["phone": поле])
                    guard МоиОбъявленияAPI.да(j["ok"]) else {
                        ошибка = НастройкиAPI.ошибка(j)
                        return
                    }
                    if МоиОбъявленияAPI.да(j["need_confirm"]) || МоиОбъявленияAPI.да(j["need_verify"]) {
                        let новый = МоиОбъявленияAPI.строка(j["phone"])
                        НастройкиМодель.shared.изменить { п in
                            if !новый.isEmpty { п.телефон = новый }
                        }
                        готово()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            НастройкиМодель.shared.номерЖдётВерификации = true
                        }
                        return
                    }
                    let новый = МоиОбъявленияAPI.строка(j["phone"])
                    let скрыт = МоиОбъявленияAPI.да(j["hide"])
                    НастройкиМодель.shared.изменить { п in
                        if !новый.isEmpty {
                            п.телефон = новый
                            п.телефонПоказ = НомерКЗ.дляДоступа(новый)
                        }
                        п.скрытНомер = скрыт
                    }
                }
                let тело: [String: Any] = ["wa_off": whatsAppВыкл, "tg": юзернейм]
                let к = try await НастройкиAPI.отправить("cabinet.php?action=set_contacts", тело)
                if МоиОбъявленияAPI.да(к["ok"]) {
                    let выкл = МоиОбъявленияAPI.да(к["wa_off"])
                    let tg = МоиОбъявленияAPI.строка(к["tg"])
                    НастройкиМодель.shared.изменить { п in
                        п.whatsAppВыкл = выкл
                        п.telegram = tg
                    }
                    НастройкиМодель.shared.показать(тН("ph_saved"))
                    готово()
                } else {
                    ошибка = НастройкиAPI.ошибка(к)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

/// Страница сайта из окна настроек: тот же «открыть», что у вкладки (CabinetView кладёт его сюда при показе).
@MainActor
enum ОткрытьСтраницуНастроек {
    static var действие: ((URL) -> Void)? = nil

    static func открыть(_ адрес: URL) {
        действие?(адрес)
    }
}

// MARK: - Чаты (cabPrefChat, save_pref_chat)

struct ФормаЧатов: View {
    let профиль: ПрофильКабинета
    let готово: () -> Void
    @State private var ии: Bool
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, готово: @escaping () -> Void) {
        self.профиль = профиль
        self.готово = готово
        _ии = State(initialValue: профиль.чатИИ)
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $ии) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(тН("chat_ai_t"))
                            .font(.system(size: 16, weight: .semibold))
                        Text(тН("chat_ai_s"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .tint(Theme.зелёныйЯркий)
            } header: {
                Text(тН("chat_hint")).textCase(nil)
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    текстСЖирным(тН("chat_ai_note"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                    /* openUpgrade('ai') — цифровая покупка: в приложении не продаётся, ссылки на оплату нет. */
                    ЗаметкаБизнеса(БизнесText.т("no_digital"), тон: .серый, значок: "lock")
                }
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: тН("save"), идёт: идёт) { сохранить() }
        }
    }

    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        идёт = true
        let значение = ии
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_chat", ["ai": значение])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let итог = ((j["chat"] as? [String: Any]).map { МоиОбъявленияAPI.да($0["ai"]) }) ?? значение
                    НастройкиМодель.shared.изменить { $0.чатИИ = итог }
                    НастройкиМодель.shared.показать(тН("cabset_chat_saved"))
                    готово()
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

// MARK: - Мои категории (cabPrefCats, save_pref_cats)

struct ФормаКатегорий: View {
    let профиль: ПрофильКабинета
    let кнопка: String
    let готово: () -> Void
    @State private var отмечены: Set<String>
    @State private var корни: [ПараНастройки] = []
    @State private var грузится = true
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, кнопка: String, готово: @escaping () -> Void) {
        self.профиль = профиль
        self.кнопка = кнопка
        self.готово = готово
        _отмечены = State(initialValue: Set(профиль.категории))
    }

    var body: some View {
        Form {
            Section {
                if грузится {
                    HStack(spacing: 10) {
                        SiteSpinner()
                        Text(тН("loading")).foregroundStyle(Theme.текстВторой)
                    }
                }
                ForEach(корни) { раздел in
                    Button {
                        if отмечены.contains(раздел.ключ) {
                            отмечены.remove(раздел.ключ)
                        } else {
                            отмечены.insert(раздел.ключ)
                        }
                    } label: {
                        HStack {
                            Text(раздел.подпись).foregroundStyle(Theme.текст)
                            Spacer(minLength: 8)
                            Image(systemName: отмечены.contains(раздел.ключ) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20))
                                .foregroundStyle(отмечены.contains(раздел.ключ) ? Theme.зелёныйЯркий : Theme.текстВторой)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityAddTraits(отмечены.contains(раздел.ключ) ? [.isSelected] : [])
                }
            } header: {
                Text(тН("cabset_cats_hint")).textCase(nil)
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: кнопка, идёт: идёт) { сохранить() }
        }
        .task { await загрузить() }
    }

    /// CAB_CATS = MK_CATS: корни дерева разделов (js/cats-<язык>.js) — тот же файл, что у мастера подачи (этап 42).
    private func загрузить() async {
        guard корни.isEmpty else { return }
        var страница = СтраницаПодачи()
        страница.путьРазделов = профиль.путьРазделов
        страница.путьСправочников = профиль.путьСправочников
        do {
            let справочники = try await ЗагрузкаСправочников.загрузить(страница)
            корни = справочники.корни.map { ПараНастройки(ключ: $0, подпись: справочники.имя($0)) }
        } catch {
            ошибка = НастройкиAPI.сбой(error)
        }
        грузится = false
    }

    private func сохранить() {
        guard !идёт, !грузится else { return }
        ошибка = nil
        идёт = true
        /* Порядок — как галочки на экране (порядок разделов сайта). */
        let выбранные = корни.map { $0.ключ }.filter { отмечены.contains($0) }
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_cats", ["cats": выбранные])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let итог = (j["cats"] as? [Any])?.compactMap { $0 as? String } ?? выбранные
                    НастройкиМодель.shared.изменить { $0.категории = итог }
                    НастройкиМодель.shared.показать(тН("cabset_cats_saved"))
                    готово()
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

// MARK: - Режим работы (cabPrefHours, save_pref_hours)

struct ФормаЧасов: View {
    let кнопка: String
    let готово: (ПолеПрименения?) -> Void
    @State private var режим: String
    @State private var с: Date
    @State private var до: Date
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, кнопка: String, готово: @escaping (ПолеПрименения?) -> Void) {
        self.кнопка = кнопка
        self.готово = готово
        let m = профиль.часы
        _режим = State(initialValue: m == "247" ? "247" : (m == "range" ? "range" : "none"))
        _с = State(initialValue: Self.время(профиль.часыС) ?? Self.время("09:00") ?? Date())
        _до = State(initialValue: Self.время(профиль.часыДо) ?? Self.время("18:00") ?? Date())
    }

    var body: some View {
        Form {
            Section {
                Picker(тН("cabset_hours"), selection: $режим) {
                    Text(тН("hours_247")).tag("247")
                    Text(тН("cabset_hours_range")).tag("range")
                    Text(тН("cabset_hours_none")).tag("none")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if режим == "range" {
                    DatePicker(тН("hours_from"), selection: $с, displayedComponents: .hourAndMinute)
                    DatePicker(тН("hours_to"), selection: $до, displayedComponents: .hourAndMinute)
                }
            } header: {
                Text(тН("cabset_hours_hint")).textCase(nil)
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: кнопка, идёт: идёт) { сохранить() }
        }
    }

    /// «Не указывать» — mode пустой; не «Своё время» — оба времени пустые (cabPrefHoursSave).
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        идёт = true
        let mode = режим == "247" ? "247" : (режим == "range" ? "range" : "")
        let from = mode == "range" ? Self.строка(с) : ""
        let to = mode == "range" ? Self.строка(до) : ""
        Task { @MainActor in
            defer { идёт = false }
            do {
                let тело: [String: Any] = ["mode": mode, "from": from, "to": to]
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_hours", тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    НастройкиМодель.shared.изменить { п in
                        п.часы = mode
                        if !from.isEmpty { п.часыС = from }
                        if !to.isEmpty { п.часыДо = to }
                    }
                    НастройкиМодель.shared.показать(тН("cabset_hours_saved"))
                    готово(.часы)
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }

    /// «HH:MM» ↔ время сегодняшнего дня (поле type=time сайта).
    static func время(_ текст: String) -> Date? {
        let части = текст.split(separator: ":")
        guard части.count >= 2, let ч = Int(части[0]), let м = Int(части[1]), (0...23).contains(ч), (0...59).contains(м)
        else { return nil }
        return Calendar.current.date(bySettingHour: ч, minute: м, second: 0, of: Date())
    }

    static func строка(_ дата: Date) -> String {
        let к = Calendar.current.dateComponents([.hour, .minute], from: дата)
        return String(format: "%02d:%02d", к.hour ?? 0, к.minute ?? 0)
    }
}

// MARK: - Личные данные на фото (cabPrefRedact, save_pref_redact)

struct ФормаФото: View {
    let кнопка: String
    let готово: () -> Void
    @State private var скрывать: Bool
    @State private var идёт = false

    init(профиль: ПрофильКабинета, кнопка: String, готово: @escaping () -> Void) {
        self.кнопка = кнопка
        self.готово = готово
        _скрывать = State(initialValue: профиль.скрыватьДанные)
    }

    var body: some View {
        Form {
            Section {
                пример
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text(тН("pr_hint")).textCase(nil)
            }
            Section {
                вариант(false, заголовок: тН("pr_off_t"), подпись: тН("pr_off_s"), значок: "eye")
                вариант(true, заголовок: тН("pr_on_t"), подпись: тН("pr_on_s"), значок: "checkmark.shield")
            } footer: {
                Text(тН("pr_note"))
            }
            КнопкаНастройки(подпись: кнопка, идёт: идёт) { сохранить() }
        }
    }

    /// Демо сайта: /img/demo/redact-before.webp и -after.webp, подпись «Пример: номера скрыты / видны».
    private var пример: some View {
        let путь = скрывать ? "/img/demo/redact-after.webp" : "/img/demo/redact-before.webp"
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: Config.url(путь)) { картинка in
                картинка.resizable().scaledToFit()
            } placeholder: {
                Theme.поверхность2
                    .frame(height: 140)
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityHidden(true)
            Text(тН(скрывать ? "pr_demo_on" : "pr_demo_off"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    private func вариант(_ значение: Bool, заголовок: String, подпись: String, значок: String) -> some View {
        Button {
            скрывать = значение
        } label: {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 8)
                Image(systemName: скрывать == значение ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(скрывать == значение ? Theme.зелёныйЯркий : Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(скрывать == значение ? [.isSelected] : [])
    }

    /// sniAutoSet: save_pref_redact {on}; ok — дубль в localStorage.kliko_photo_redact («1»/«0»), как у сайта.
    private func сохранить() {
        guard !идёт else { return }
        идёт = true
        let включить = скрывать
        Task { @MainActor in
            defer { идёт = false }
            let j = try? await НастройкиAPI.отправить("cabinet.php?action=save_pref_redact", ["on": включить])
            guard let j, МоиОбъявленияAPI.да(j["ok"]) else {
                НастройкиМодель.shared.показать(тН("pr_fail"))
                return
            }
            await КабинетСайта.положитьВХранилище("kliko_photo_redact", включить ? "1" : "0")
            НастройкиМодель.shared.изменить { $0.скрыватьДанные = включить }
            НастройкиМодель.shared.показать(тН(включить ? "pr_saved_on" : "pr_saved_off"))
            готово()
        }
    }
}

// MARK: - Гарант по умолчанию (cabPrefEscrow, save_pref_escrow)

struct ФормаГаранта: View {
    let профиль: ПрофильКабинета
    let готово: (ПолеПрименения?) -> Void
    @State private var включён: Bool
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, готово: @escaping (ПолеПрименения?) -> Void) {
        self.профиль = профиль
        self.готово = готово
        _включён = State(initialValue: !профиль.гарантВыкл)
    }

    var body: some View {
        Form {
            Section {
                Toggle(тН("esc_pref_t"), isOn: $включён)
                    .tint(Theme.зелёныйЯркий)
                    .font(.system(size: 16, weight: .semibold))
                if включён {
                    ForEach(["pc_esc_g1", "pc_esc_g2", "pc_esc_g3"], id: \.self) { ключ in
                        Label {
                            Text(тН(ключ)).font(.system(size: 14))
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(Theme.зелёныйЯркий)
                        }
                    }
                    if !профиль.верифицирован {
                        Text(тН("pc_esc_verify"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    }
                } else {
                    Text(тН("pc_esc_off"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                }
            } header: {
                Text(тН("esc_pref_hint")).textCase(nil)
            } footer: {
                if профиль.минимумГаранта > 0 {
                    Text(тН("esc_pref_auto").replacingOccurrences(of: "{n}",
                                                                  with: тысячиНастройки(профиль.минимумГаранта) + " ₸"))
                }
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: тН("save"), идёт: идёт) { сохранить() }
        }
    }

    /// {off: !checked}; значение изменилось — вопрос «Включить / Выключить гарант во всех объявлениях?».
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        идёт = true
        let выкл = !включён
        let было = профиль.гарантВыкл
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_escrow", ["off": выкл])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let итог = j["off"] == nil ? выкл : МоиОбъявленияAPI.да(j["off"])
                    НастройкиМодель.shared.изменить { $0.гарантВыкл = итог }
                    НастройкиМодель.shared.показать(тН("esc_pref_saved"))
                    готово(итог != было ? .гарант(включён: !итог) : nil)
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

// MARK: - Бронь товара (cabPrefReserve, save_pref_reserve)

struct ФормаБрони: View {
    let готово: () -> Void
    @State private var минуты: Int
    @State private var ошибка: String? = nil
    @State private var идёт = false

    /// _RVW_OPTS: 15…120 с шагом 5.
    private static let варианты: [Int] = Array(stride(from: 15, through: 120, by: 5))

    init(профиль: ПрофильКабинета, готово: @escaping () -> Void) {
        self.готово = готово
        _минуты = State(initialValue: Self.варианты.contains(профиль.бронь) ? профиль.бронь : 60)
    }

    var body: some View {
        Form {
            Section {
                Picker(тН("cabset_reserve"), selection: $минуты) {
                    ForEach(Self.варианты, id: \.self) { m in
                        Text(String(m) + " " + тН("min_short")).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            } header: {
                Text(тН("cabset_reserve_hint")).textCase(nil)
            }
            Section {
                ForEach(["cabset_reserve_why1", "cabset_reserve_why2", "cabset_reserve_why3"], id: \.self) { ключ in
                    Label {
                        Text(тН(ключ)).font(.system(size: 14))
                    } icon: {
                        Image(systemName: "checkmark.circle").foregroundStyle(Theme.акцент)
                    }
                }
            } header: {
                Text(тН("cabset_reserve_why_t"))
            }
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: тН("save"), идёт: идёт) { сохранить() }
        }
    }

    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        идёт = true
        let значение = минуты
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_reserve",
                                                        ["reserve_hold_min": значение])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let итог = МоиОбъявленияAPI.целое(j["reserve_hold_min"])
                    НастройкиМодель.shared.изменить { $0.бронь = итог > 0 ? итог : значение }
                    НастройкиМодель.shared.показать(тН("cabset_reserve_saved"))
                    готово()
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

// MARK: - Язык (cabLangPick, save_pref_lang)

struct ФормаЯзыка: View {
    let профиль: ПрофильКабинета
    let готово: () -> Void
    @State private var идёт = false

    init(профиль: ПрофильКабинета, готово: @escaping () -> Void) {
        self.профиль = профиль
        self.готово = готово
    }

    var body: some View {
        Form {
            Section {
                ForEach(профиль.языки) { язык in
                    Button {
                        выбрать(язык)
                    } label: {
                        HStack {
                            Label {
                                Text(язык.имя).foregroundStyle(Theme.текст)
                            } icon: {
                                Image(systemName: "globe").foregroundStyle(Theme.акцент)
                            }
                            Spacer(minLength: 8)
                            if язык.код == профиль.язык {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.акцент)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .disabled(идёт)
                    .accessibilityAddTraits(язык.код == профиль.язык ? [.isSelected] : [])
                }
            } footer: {
                Text(тН("lang_note"))
            }
        }
    }

    /**
     cabLangSet: другой язык — save_pref_lang {lang}, ответ сайт не читает. Дальше сайт уходит на /kz/<язык>/…; экраны
     приложения и адреса страниц сайта в нём следуют языку iPhone (Config.страницаСайта), поэтому здесь выбор только
     сохраняется в аккаунте — об этом строка под списком.
     */
    private func выбрать(_ язык: ЯзыкСайта) {
        guard язык.код != профиль.язык else {
            готово()
            return
        }
        идёт = true
        let код = язык.код
        Task { @MainActor in
            defer { идёт = false }
            _ = try? await НастройкиAPI.отправить("cabinet.php?action=save_pref_lang", ["lang": код])
            НастройкиМодель.shared.изменить { $0.язык = код }
            НастройкиМодель.shared.показать(тН("lang_note"))
            готово()
        }
    }
}
