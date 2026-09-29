import SwiftUI
import UIKit

/**
 ЭКРАН ВХОДА — ЭТАП 40 (владелец 26.09.2026), упрощён по «пути новичка» (владелец 29.09.2026).

 Гостевая страница /kz/ru/cabinet.php (карта кабинета §1.1), но без ворот «С чего начнём? Я покупатель / Я продавец»
 и без таблицы «Без eGov / С eGov»: сразу вкладки «Войти» / «Регистрация». Роль и зачем нужен eGov объясняются позже —
 при первой публикации объявления (шаг eGov после публикации). «Войти через eGov» остаётся второй кнопкой под формами.

 Вход: номер с маской +7 (7XX) XXX-XX-XX и проверкой кода оператора (НомерКЗ = klkFmt/klkPhoneCheck), пароль, «Забыли
 пароль?» — окно «Восстановить доступ» (eGov по ИИН на странице сайта или поддержка: SMS-восстановления у сайта нет).
 Номер помечен .username, пароль — .password: система подставляет доступ из Связки ключей (webcredentials:kliko.kz).
 Ответы — как у doLogin: вошёл → лист закрывается, кабинет перечитывает сеанс; need_egov → окно «Подтвердите вход через
 eGov» на странице сайта (?egov_confirm=1); deleted → «Аккаунт удалён» с причиной и «Обратиться в поддержку»; иначе —
 текст сервера или «Ошибка входа»; нет сети — «Нет соединения», прочее — «Ошибка приложения…».

 Регистрация: номер и согласие с соглашением. ИИН не спрашиваем: register_quick принимает пустой iin (карта §2.2,
 окно регистрации витрины iin не шлёт вовсе) — ИИН попросит проверка eGov. «Создать аккаунт» → окно «Подтвердите
 номер» → register_quick только по «Всё верно, создать» → окно «Аккаунт создан» с паролем, показанным один раз.
 Пароль сразу предлагаем сохранить в Связку ключей системным окном (SecAddSharedWebCredential, СвязкаКлючей); рядом —
 «Копировать» и запасной путь «Сохранить файлом» (лист «Поделиться», как у сайта). Сам пароль никуда больше не пишется.

 «или войдите через» (в карточке под формами): eGov — листом поверх (ОкноEgov), Apple — нативным листом Apple (ВходApple,
 apple_auth.php?action=native); пока сервер его не умеет — прежней страницей сайта apple_auth.php?action=start (§1.2.6).
 Telegram сайт скрыл по правилу App Store 4.8 — его нет и здесь.
 */
struct ЭкранВхода: View {
    enum Вкладка: Equatable { case вход, регистрация }
    enum Поле: Hashable { case телефон, пароль, номерРег }

    /// const BIO_ON страницы: от него зависит окно «Восстановить доступ».
    let eGovВключён: Bool
    /// Открыть страницу сайта (лист перед этим закрывается).
    let открыть: (URL) -> Void
    /// Вошли — кабинет перечитает сеанс.
    let вошли: () -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var вкладка: Вкладка = .вход
    @State private var телефон = ""
    @State private var пароль = ""
    @State private var парольВиден = false
    @State private var номерРег = ""
    @State private var согласие = false
    @State private var ошибкаНомера: String? = nil
    @State private var ошибкаНомераРег: String? = nil
    @State private var ошибкаВхода: String? = nil
    @State private var ошибкаРег: String? = nil
    /// Ошибка входа через Apple — у кнопки Apple (под формами карточки, как .soc-btns сайта).
    @State private var ошибкаApple: String? = nil
    @State private var идёт = false
    @State private var окно: ОкноВхода? = nil
    @State private var доступ: ДоступАккаунта? = nil
    /// С этого мгновения считается ft регистрации — сколько человек пробыл на экране.
    @State private var открыт = Date()
    @FocusState private var фокус: Поле?

    init(eGovВключён: Bool, открыть: @escaping (URL) -> Void, вошли: @escaping () -> Void) {
        self.eGovВключён = eGovВключён
        self.открыть = открыть
        self.вошли = вошли
    }

    private func т(_ ключ: String) -> String { ВходText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                формы
                    .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(КраскаВходаСайта.фон.ignoresSafeArea())
            .navigationTitle(т("seller_cab"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                        .disabled(идёт)
                }
            }
        }
        .tint(Theme.акцент)
        .interactiveDismissDisabled(идёт)
        .onChange(of: фокус) { было, стало in префиксНомера(было: было, стало: стало) }
        .onChange(of: телефон) { было, стало in
            let верное = Self.ввод(было: было, стало: стало)
            if верное != стало { телефон = верное }
            ошибкаНомера = Self.ошибкаКода(верное)
        }
        .onChange(of: номерРег) { было, стало in
            let верное = Self.ввод(было: было, стало: стало)
            if верное != стало { номерРег = верное }
            ошибкаНомераРег = Self.ошибкаКода(верное)
        }
        .alert(окно?.заголовок ?? "", isPresented: окноПоказано, presenting: окно) { о in
            кнопкиОкна(о)
        } message: { о in
            Text(текстОкна(о))
        }
        .sheet(item: $доступ) { д in
            ЛистДоступа(доступ: д, продолжить: { продолжитьПослеРегистрации() })
        }
    }

    // MARK: - Формы

    /// #auth-card: вкладки вплотную к верху карточки (.tabs2 margin -22px -18px, ниже 20), формы, под ними «или войдите через».
    private var формы: some View {
        VStack(alignment: .leading, spacing: 0) {
            ВкладкиВхода(выбрана: вкладка, выбрать: { куда in выбратьВкладку(куда) })
                .padding(.horizontal, -18)
                .padding(.top, -22)
                .padding(.bottom, 20)
            if вкладка == .вход {
                формаВхода
            } else {
                формаРегистрации
            }
            способы
                .padding(.top, 20)
        }
        .карточкаВходаСайта()
    }

    private var формаВхода: some View {
        VStack(alignment: .leading, spacing: 14) {
            ПолеВхода(подпись: т("auth_phone"), ошибка: ошибкаНомера, вФокусе: фокус == .телефон) {
                /* .username, а не .telephoneNumber: номер — логин, система подставит его в паре с паролем из Связки. */
                TextField(т("auth_phone"), text: $телефон, prompt: Text(verbatim: "+7 (700) 000-00-00"))
                    .keyboardType(.phonePad)
                    .textContentType(.username)
                    .focused($фокус, equals: .телефон)
            }
            ПолеВхода(подпись: т("auth_pass"), ошибка: nil, вФокусе: фокус == .пароль) {
                полеПароля
            }
            /* Как у сайта: справа, 13 обычным серым, margin -6px 0 var(--m-2). */
            Button(т("auth_forgot")) { окно = .восстановление }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, -6)
                .padding(.bottom, -6)
            if let ошибка = ошибкаВхода { ОшибкаФормы(текст: ошибка) }
            КнопкаСайта(подпись: т("auth_login"), идёт: идёт) { войти() }
            ПереходФормы(вопрос: т("auth_no_acc"), ссылка: т("auth_do_register"), жирная: false) {
                выбратьВкладку(.регистрация)
            }
        }
    }

    private var полеПароля: some View {
        HStack(spacing: 8) {
            Group {
                if парольВиден {
                    TextField(т("auth_pass"), text: $пароль)
                } else {
                    SecureField(т("auth_pass"), text: $пароль)
                }
            }
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.go)
            .focused($фокус, equals: .пароль)
            .onSubmit { войти() }
            Button {
                парольВиден.toggle()
            } label: {
                Image(systemName: парольВиден ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т(парольВиден ? "hide_pass" : "show_pass"))
        }
    }

    private var формаРегистрации: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(т("auth_reg_hint"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ПолеВхода(подпись: т("auth_phone"), ошибка: ошибкаНомераРег, вФокусе: фокус == .номерРег) {
                TextField(т("auth_phone"), text: $номерРег, prompt: Text(verbatim: "+7 (700) 000-00-00"))
                    .keyboardType(.phonePad)
                    .textContentType(.username)
                    .focused($фокус, equals: .номерРег)
            }
            СогласиеВхода(принято: $согласие)
            if let ошибка = ошибкаРег { ОшибкаФормы(текст: ошибка) }
            КнопкаСайта(подпись: т("auth_create"), идёт: идёт) { создать() }
            ПереходФормы(вопрос: т("auth_have_acc"), ссылка: т("auth_do_login"), жирная: false) {
                выбратьВкладку(.вход)
            }
        }
    }

    // MARK: - Вход через сервисы

    /// «или войдите через» (.soc-btns — в карточке под формами): eGov — листом поверх (ОкноEgov),
    /// Apple — нативно (откат — страница сайта); ниже — согласие и примечание о номере, как у сайта.
    private var способы: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().fill(КраскаВходаСайта.линия).frame(height: 1)
                Text(т("auth_or_via"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize()
                Rectangle().fill(КраскаВходаСайта.линия).frame(height: 1)
            }
            .padding(.bottom, -6)
            /* .soc-agree: 12, lh 1.45, по центру, ссылки --on-ok 600 — открываются своим окном поверх. */
            Text(ТекстСогласия.строка(т("auth_agree_soc")))
                .font(.system(size: 12))
                .lineSpacing(5)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .tint(КраскаВходаСайта.наЗелёный)
                .environment(\.openURL, ТекстСогласия.открыватель)
            КнопкаСервиса(подпись: т("auth_via_egov"), значок: "checkmark.shield", тёмная: false) {
                eGov("cabinet.php?egov=1")
            }
            if let ошибка = ошибкаApple { ОшибкаФормы(текст: ошибка) }
            КнопкаСервиса(подпись: т("auth_via_apple"), значок: "apple.logo", тёмная: true) {
                черезApple()
            }
            Text(т("auth_phone_note"))
                .font(.system(size: 11))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Окна

    private var окноПоказано: Binding<Bool> {
        Binding(get: { окно != nil }, set: { показано in if !показано { окно = nil } })
    }

    /// «Восстановить доступ» зависит от BIO_ON страницы: eGov по ИИН или «напишите в поддержку» (openPwRecover сайта).
    private func текстОкна(_ о: ОкноВхода) -> String {
        if о == .восстановление { return т(eGovВключён ? "rec_s_bio" : "rec_s_off") }
        return о.текст
    }

    @ViewBuilder
    private func кнопкиОкна(_ о: ОкноВхода) -> some View {
        switch о {
        case .подтвердитьНомер:
            Button(т("reg_confirm_ok")) { отправитьРегистрацию() }
            Button(т("reg_confirm_edit"), role: .cancel) { фокус = .номерРег }
        case .номерЗанят, .иинЗанят:
            Button(т("reg_recover_egov")) { eGov("cabinet.php?egov=1") }
            Button(т("reg_recover_pass")) {
                телефон = номерРег
                выбратьВкладку(.вход)
            }
            Button(т("close"), role: .cancel) {}
        case .удалён:
            Button(т("deleted_support")) { вПоддержку("access") }
            Button(т("close"), role: .cancel) {}
        case .восстановление:
            if eGovВключён {
                Button(т("reg_recover_egov")) { eGov("cabinet.php?egov=1") }
            } else {
                Button(т("rec_support")) { вПоддержку("access") }
            }
            Button(т("close"), role: .cancel) {}
        }
    }

    // MARK: - Действия

    /// switchTab сайта, но без ворот ролей: регистрация открывается сразу (роль спросим при первой публикации).
    private func выбратьВкладку(_ куда: Вкладка) {
        ошибкаВхода = nil
        ошибкаРег = nil
        if куда == .регистрация && !Config.нативнаяРегистрация {
            наСайт(Config.страницаСайта("cabinet.php"))
            return
        }
        вкладка = куда
    }

    /// Сайт при фокусе пустого номера ставит «+7 », при уходе без номера — очищает поле.
    private func префиксНомера(было: Поле?, стало: Поле?) {
        if стало == .телефон && телефон.isEmpty { телефон = "+7 " }
        if стало == .номерРег && номерРег.isEmpty { номерРег = "+7 " }
        if было == .телефон && стало != .телефон && НомерКЗ.цифры(телефон).count <= 1 { телефон = "" }
        if было == .номерРег && стало != .номерРег && НомерКЗ.цифры(номерРег).count <= 1 { номерРег = "" }
    }

    /// doLogin: сначала номер (код оператора и длина — у поля), потом один запрос. Только по нажатию.
    private func войти() {
        guard !идёт else { return }
        ошибкаВхода = nil
        if let ошибка = НомерКЗ.ошибка(телефон) {
            ошибкаНомера = ошибка
            фокус = .телефон
            return
        }
        фокус = nil
        идёт = true
        let номер = телефон
        let секрет = пароль
        Task { @MainActor in
            defer { идёт = false }
            do {
                let итог = try await КабинетСайта.войти(телефон: номер, пароль: секрет)
                switch итог {
                case .вошёл:
                    пароль = ""
                    вошли()
                    закрыть()
                case .нуженEgov:
                    eGov("cabinet.php?egov_confirm=1")
                case .удалён(let причина):
                    окно = .удалён(причина: причина)
                case .ошибка(let текст):
                    ошибкаВхода = текст
                }
            } catch {
                ошибкаВхода = Self.текстСбоя(error)
            }
        }
    }

    /// doQuickRegister: номер и согласие — потом окно «Подтвердите номер». ИИН не спрашиваем (сервер его не требует).
    private func создать() {
        guard !идёт else { return }
        ошибкаРег = nil
        if let ошибка = НомерКЗ.ошибка(номерРег) {
            ошибкаНомераРег = ошибка
            фокус = .номерРег
            return
        }
        guard согласие else {
            ошибкаРег = т("need_agree")
            return
        }
        фокус = nil
        окно = .подтвердитьНомер(номерРег.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// «Всё верно, создать» — один запрос register_quick, без повторов.
    private func отправитьРегистрацию() {
        guard !идёт else { return }
        идёт = true
        let номер = номерРег
        let мс = Int(max(0, Date().timeIntervalSince(открыт)) * 1000)
        Task { @MainActor in
            defer { идёт = false }
            do {
                let итог = try await КабинетСайта.зарегистрировать(телефон: номер, иин: "", мсНаЭкране: мс)
                switch итог {
                case .создан(let тел, let секрет):
                    доступ = ДоступАккаунта(телефон: НомерКЗ.дляДоступа(тел), пароль: секрет)
                case .номерЗанят:
                    окно = .номерЗанят
                case .иинЗанят:
                    окно = .иинЗанят
                case .ошибка(let текст):
                    ошибкаРег = текст
                }
            } catch {
                ошибкаРег = Self.текстСбоя(error)
            }
        }
    }

    /// «Продолжить» из окна «Аккаунт создан» — как у сайта, перезагрузка уже вошедшим.
    private func продолжитьПослеРегистрации() {
        доступ = nil
        Task { @MainActor in
            await КабинетСайта.послеВхода(uid: "")
            вошли()
            /* Сначала уходит лист «Аккаунт создан», потом этот: два листа разом SwiftUI закрывает ненадёжно. */
            try? await Task.sleep(nanoseconds: 400_000_000)
            закрыть()
        }
    }

    /**
     Вход через Apple: нативный лист Apple и apple_auth.php?action=native (ВходApple). Вошёл — как вход паролем (сеанс уже
     перечитан в ВходApple через КабинетСайта.послеВхода); сервер ещё не умеет — прежняя страница сайта.
     */
    private func черезApple() {
        guard !идёт else { return }
        ошибкаApple = nil
        ошибкаВхода = nil
        идёт = true
        Task { @MainActor in
            let итог = await ВходApple.войти()
            идёт = false
            switch итог {
            case .вошёл:
                вошли()
                закрыть()
            case .отменено:
                break
            case .удалён(let причина):
                окно = .удалён(причина: причина)
            case .нуженEgov:
                eGov("cabinet.php?egov_confirm=1")
            case .ошибка(let текст):
                ошибкаApple = текст
            case .наСайт:
                наСайт(Config.url("/apple_auth.php?action=start"))
            }
        }
    }

    /// Страница сайта вместо этого листа.
    private func наСайт(_ адрес: URL?) {
        guard let адрес else { return }
        закрыть()
        открыть(адрес)
    }

    /// Своя форма обращения (support.php?topic=) — после того, как этот экран закроется.
    private func вПоддержку(_ тема: String) {
        закрыть()
        ПоддержкаПоверх.показать(тема: тема, задержка: 450_000_000)
    }

    /// TestFlight 1.10: eGov — листом поверх этого экрана (ОкноEgov), а не вкладкой сайта; удача — как вход паролем.
    private func eGov(_ хвост: String) {
        guard ОкноEgov.включено else {
            наСайт(Config.страницаСайта(хвост))
            return
        }
        let вошлиСюда = вошли
        let закрытьЛист = закрыть
        ОкноEgov.открыть(Config.страницаСайта(хвост)) {
            вошлиСюда()
            закрытьЛист()
        }
    }

    // MARK: - Помощники

    /// Ошибка кода оператора видна, как только набраны три цифры; «не хватает цифр» — только при отправке (как у сайта).
    static func ошибкаКода(_ номер: String) -> String? {
        if case .нетКода = НомерКЗ.проверить(номер) { return НомерКЗ.ошибка(номер) }
        return nil
    }

    static func текстСбоя(_ ошибка: Error) -> String {
        (ошибка as? КабинетСайта.Сбой) == .сеть ? ВходText.т("no_conn") : ВходText.т("app_err")
    }

    /**
     Маска номера при вводе (обработчик input сайта): формат klkFmt; стёрли знак маски «)» — стирается и цифра перед ним,
     иначе маска вернула бы знак и стереть было бы нельзя; номер уже полный — лишняя цифра не входит; одна цифра (код
     страны) — «+7 », как у сайта при фокусе. Результат ввода, поданный снова, не меняется — onChange не зацикливается.
     */
    static func ввод(было: String, стало: String) -> String {
        if стало.isEmpty { return "" }
        let цифрыБыло = НомерКЗ.цифры(было)
        let цифрыСтало = НомерКЗ.цифры(стало)
        if цифрыСтало.count <= 1 { return "+7 " }
        let канон = НомерКЗ.формат(стало)
        if стало.count < было.count && цифрыСтало == цифрыБыло && канон != стало {
            let меньше = String(цифрыСтало.dropLast())
            return меньше.count <= 1 ? "+7 " : НомерКЗ.формат("+" + меньше)
        }
        if цифрыБыло.count >= 11 && цифрыСтало.count == цифрыБыло.count + 1 && стало.count == было.count + 1 {
            return было
        }
        return канон
    }
}

/// Окна экрана входа — alert с текстами сайта.
enum ОкноВхода: Equatable {
    case подтвердитьНомер(String)
    case номерЗанят
    case иинЗанят
    case удалён(причина: String)
    case восстановление

    var заголовок: String {
        switch self {
        case .подтвердитьНомер: return ВходText.т("reg_confirm_title")
        case .номерЗанят: return ВходText.т("reg_exists_title")
        case .иинЗанят: return ВходText.т("reg_iin_title")
        case .удалён: return ВходText.т("deleted_t")
        case .восстановление: return ВходText.т("rec_t")
        }
    }

    var текст: String {
        switch self {
        case .подтвердитьНомер(let номер):
            return номер + "\n\n" + ВходText.т("reg_confirm_text")
        case .номерЗанят:
            return ВходText.т("reg_exists_text")
        case .иинЗанят:
            return ВходText.т("reg_iin_text")
        case .удалён(let причина):
            let основа = ВходText.т("deleted_s")
            return причина.isEmpty ? основа : основа + "\n\n" + ВходText.т("deleted_reason") + ": " + причина
        case .восстановление:
            return ""
        }
    }
}

/// Доступ нового аккаунта для окна «Аккаунт создан».
struct ДоступАккаунта: Identifiable, Equatable {
    let id = UUID()
    let телефон: String
    let пароль: String
}

// MARK: - Части экрана

/// Краски страницы входа: у кабинета своя палитра (тёмная карточка #1c1c26 на странице #101017, а не как в ленте).
private enum КраскаВходаСайта {
    /// body: #eef3f0 и #101017.
    static let фон = Theme.цвет(0xEEF3F0, 0x101017)
    /// --card: #fff и #1c1c26.
    static let карточка = Theme.цвет(0xFFFFFF, 0x1C1C26)
    /// --line: #e6efe9 и белый 10 %.
    static let линия = Theme.цвет(светлый: Theme.hex(0xE6EFE9), тёмный: Theme.hex(0xFFFFFF, 0.10))
    /// --g: #0f5132 и #22a05b (вкладки, ссылки форм).
    static let зелёный = Theme.цвет(0x0F5132, 0x22A05B)
    /// --on-ok: #0f7a44 и #5cd39a (ссылки согласия, значок «Аккаунт создан»).
    static let наЗелёный = Theme.цвет(0x0F7A44, 0x5CD39A)
    /// --acc-on: #0f5132 и #5cd39a (кнопка eGov).
    static let акцент = Theme.цвет(0x0F5132, 0x5CD39A)
    /// --tint-ok: #e7f6ee и rgba(52,201,151,.14).
    static let тинт = Theme.цвет(светлый: Theme.hex(0xE7F6EE), тёмный: Theme.hex(0x34C997, 0.14))
    /// --red ошибок формы: #c0392b и #ff6168.
    static let ошибка = Theme.цвет(0xC0392B, 0xFF6168)
    /// Тень карточки и кнопки: rgba(15,81,50,…).
    static let тень = Color(red: 15 / 255, green: 81 / 255, blue: 50 / 255)
}

private extension View {
    /// #auth-card: padding 24px 20px, радиус 14, рамка 1px --line, тень 0 8px 30px -16px rgba(15,81,50,.15).
    func карточкаВходаСайта() -> some View {
        let форма = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return self
            .padding(.vertical, 24)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                форма.fill(КраскаВходаСайта.карточка)
                    .shadow(color: КраскаВходаСайта.тень.opacity(0.15), radius: 15, y: 8)
            }
            .overlay { форма.strokeBorder(КраскаВходаСайта.линия, lineWidth: 1) }
    }
}

/// Вкладки .tabs2 «Войти» / «Регистрация»: подчёркнутые, 14/700, выбранная — --g с чертой 2,5 внизу.
private struct ВкладкиВхода: View {
    let выбрана: ЭкранВхода.Вкладка
    let выбрать: (ЭкранВхода.Вкладка) -> Void

    var body: some View {
        HStack(spacing: 0) {
            вкладка(.вход, ВходText.т("auth_login"))
            вкладка(.регистрация, ВходText.т("auth_register"))
        }
        .background(alignment: .bottom) {
            Rectangle().fill(КраскаВходаСайта.линия).frame(height: 1)
        }
    }

    private func вкладка(_ какая: ЭкранВхода.Вкладка, _ подпись: String) -> some View {
        let выбран = какая == выбрана
        return Button {
            выбрать(какая)
        } label: {
            Text(подпись)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(выбран ? КраскаВходаСайта.зелёный : Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(выбран ? КраскаВходаСайта.зелёный : Color.clear)
                        .frame(height: 2.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Поле формы .inp: подпись сверху, 46 высотой, 14 по бокам, рамка 1,5 (в фокусе — зелёная с кольцом 3), причина у поля красным.
private struct ПолеВхода<Содержимое: View>: View {
    let подпись: String
    let ошибка: String?
    let вФокусе: Bool
    @ViewBuilder let содержимое: () -> Содержимое

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text(подпись)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            содержимое()
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(КраскаВходаСайта.карточка, in: форма)
                .overlay {
                    форма.strokeBorder(ошибка != nil ? Theme.ценаСкидка : (вФокусе ? Theme.зелёный2 : КраскаВходаСайта.линия),
                                       lineWidth: 1.5)
                }
                .overlay {
                    if вФокусе && ошибка == nil {
                        /* box-shadow 0 0 0 3px rgba(15,81,50,.12) — кольцо снаружи рамки. */
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms + 1.5, style: .continuous)
                            .stroke(КраскаВходаСайта.тень.opacity(0.12), lineWidth: 3)
                            .padding(-1.5)
                            .allowsHitTesting(false)
                    }
                }
            if let ошибка {
                Text(ошибка)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.скидкаТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// .err: 13 обычным, --red, без подложки, margin -6px 0 12px.
private struct ОшибкаФормы: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 13))
            .foregroundStyle(КраскаВходаСайта.ошибка)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -6)
    }
}

/// Главная зелёная кнопка .btn.btn-g: 46, радиус 12, 15/700, градиент --g → --g2, тень, нажатие 0,97; в пути — колесо.
struct КнопкаСайта: View {
    let подпись: String
    let идёт: Bool
    let действие: () -> Void

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        Button(action: действие) {
            ZStack {
                if идёт {
                    ProgressView()
                        .tint(Color.white)
                } else {
                    Text(подпись)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                форма.fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: КраскаВходаСайта.тень.opacity(0.35), radius: 6, y: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(идёт)
        .accessibilityLabel(подпись)
    }
}

/// .soc-btn: 48, радиус 14, 14/700; eGov — на карточке с рамкой, текст --acc-on; Apple — чёрная.
private struct КнопкаСервиса: View {
    let подпись: String
    let значок: String
    let тёмная: Bool
    let действие: () -> Void

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(тёмная ? Color.white : КраскаВходаСайта.акцент)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(тёмная ? Color.black : КраскаВходаСайта.карточка, in: форма)
            .overlay {
                форма.strokeBorder(тёмная ? Color.clear : КраскаВходаСайта.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// «Нет аккаунта? Зарегистрируйтесь» и подобные: 13, по центру, ссылка --g (жирная — по выбору).
private struct ПереходФормы: View {
    let вопрос: String
    let ссылка: String
    let жирная: Bool
    let действие: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text(вопрос)
                    .foregroundStyle(Theme.текстВторой)
                кнопка
            }
            VStack(spacing: 2) {
                Text(вопрос)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                кнопка
            }
        }
        .font(.system(size: 13))
        .frame(maxWidth: .infinity)
    }

    private var кнопка: some View {
        Button(ссылка, action: действие)
            .fontWeight(жирная ? .bold : .regular)
            .foregroundStyle(КраскаВходаСайта.зелёный)
    }
}

/// Чекбокс #r-agree: «Я прочитал(а) и принимаю …» со ссылками на соглашение и политику.
private struct СогласиеВхода: View {
    @Binding var принято: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                принято.toggle()
            } label: {
                Image(systemName: принято ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(принято ? Theme.зелёный2 : Theme.текстВторой)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ВходText.т("auth_terms_link"))
            .accessibilityValue(принято ? Text(verbatim: "✓") : Text(verbatim: ""))
            .accessibilityAddTraits(принято ? .isSelected : [])
            Text(ТекстСогласия.строка(ВходText.т("auth_agree"), размер: 13))
                .font(.system(size: 13))
                .lineSpacing(6)
                .foregroundStyle(Theme.текст)
                .tint(КраскаВходаСайта.наЗелёный)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.openURL, ТекстСогласия.открыватель)
        }
    }
}

/// Текст согласия со ссылками: %@ и %@ — «Пользовательское соглашение» (/soglashenie.php) и «Политику
/// конфиденциальности» (/privacy.php), как у сайта: ссылки --on-ok, 600. Открываются своим окном поверх листа
/// (НативныеОкна → страница сайта своими блоками) — форма со введённым остаётся; не распознали — система.
enum ТекстСогласия {
    static func строка(_ шаблон: String, размер: CGFloat = 12) -> AttributedString {
        let соглашение = "[" + ВходText.т("auth_terms_link") + "](https://kliko.kz/soglashenie.php)"
        let политика = "[" + ВходText.т("auth_privacy_link") + "](https://kliko.kz/privacy.php)"
        let разметка = String(format: шаблон, соглашение, политика)
        guard var итог = try? AttributedString(markdown: разметка) else {
            return AttributedString(String(format: шаблон, ВходText.т("auth_terms_link"), ВходText.т("auth_privacy_link")))
        }
        let ссылки = итог.runs.filter { $0.link != nil }.map(\.range)
        let цвет: Color = КраскаВходаСайта.наЗелёный
        let шрифт: Font = .system(size: размер, weight: .semibold)
        for часть in ссылки {
            итог[часть].foregroundColor = цвет
            итог[часть].font = шрифт
        }
        return итог
    }

    /// Ссылки согласия: свой экран поверх (НативныеОкна), иначе — система.
    @MainActor
    static var открыватель: OpenURLAction {
        OpenURLAction { адрес in
            /* Соглашение и политика — своим окном; прочий адрес нашего домена — WebBridge.перейти (не Safari). */
            let своё = MainActor.assumeIsolated { () -> Bool in
                if НативныеОкна.перехватить(адрес) { return true }
                guard Config.deepLink(адрес.absoluteURL) != nil else { return false }
                WebBridge.shared.перейти(адрес)
                return true
            }
            return своё ? .handled : .systemAction
        }
    }
}

// MARK: - «Аккаунт создан»

/**
 Окно showCredsWindow сайта: телефон и пароль один раз. Пароль сразу предлагаем сохранить в Связку ключей системным
 окном (СвязкаКлючей) — вместо совета «сделайте скриншот»; под окном — итог («Сохранено в Связку ключей» или «не
 сохранилось»), у пароля — «Копировать» (буфер только на этом телефоне и на 2 минуты), запасной путь — «Сохранить
 файлом» через «Поделиться», как у сайта.
 */
private struct ЛистДоступа: View {
    let доступ: ДоступАккаунта
    let продолжить: () -> Void
    @State private var делимся = false
    @State private var связка: СвязкаКлючей.Итог = .идёт
    @State private var скопирован = false

    private func т(_ ключ: String) -> String { ВходText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                шапка
                данные
                итогСвязки
                Text(т("cr_change"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                КнопкаСайта(подпись: т("cr_go"), идёт: false, действие: продолжить)
                Button(т("cr_file_btn")) { делимся = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .padding(22)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        /* По высоте содержимого; смахнуть нельзя — без полоски. */
        .листПоВысоте(полоска: false)
        .interactiveDismissDisabled(true)
        .task {
            /* Один раз за показ окна: системное «Сохранить пароль?» поверх этого листа. */
            guard связка == .идёт else { return }
            связка = await СвязкаКлючей.сохранить(логин: НомерКЗ.формат(доступ.телефон), пароль: доступ.пароль)
        }
        .sheet(isPresented: $делимся) {
            ЛистПоделиться(предметы: [файл]) { сохранили in
                делимся = false
                if сохранили { продолжить() }
            }
        }
    }

    /// Шапка окна: круг 56 --tint-ok со значком --on-ok, заголовок 19/800, подпись 13 — по центру.
    private var шапка: some View {
        VStack(spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(КраскаВходаСайта.наЗелёный)
                .frame(width: 56, height: 56)
                .background(КраскаВходаСайта.тинт, in: Circle())
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(т("cr_t"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(т("cr_s"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// Итог Связки ключей: ждём ответа системного окна, сохранено (ключ, зелёным) или нет (подсказка скопировать).
    @ViewBuilder
    private var итогСвязки: some View {
        switch связка {
        case .идёт:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(т("cr_kc_wait"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .сохранено:
            Label {
                Text(т("cr_kc_ok"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "key.fill")
                    .foregroundStyle(КраскаВходаСайта.наЗелёный)
            }
        case .нет:
            Label {
                Text(т("cr_kc_no"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    /// Рамка с доступом: surf2, 1px --line, радиус 12, 12/14 внутри; строки «подпись слева — значение справа».
    private var данные: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            строка(т("cr_phone"), доступ.телефон, пароль: false)
            Rectangle().fill(КраскаВходаСайта.линия).frame(height: 1)
            строка(т("cr_pass"), доступ.пароль, пароль: true)
            кнопкаКопировать
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Theme.поверхность2, in: форма)
        .overlay { форма.strokeBorder(КраскаВходаСайта.линия, lineWidth: 1) }
        .padding(.top, 2)
    }

    private func строка(_ подпись: String, _ значение: String, пароль: Bool) -> some View {
        HStack(spacing: 10) {
            Text(подпись)
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: пароль ? 15 : 14, weight: пароль ? .bold : .semibold, design: .monospaced))
                .tracking(пароль ? 0.5 : 0)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    /// «Копировать» пароль: только этот телефон (без Универсального буфера) и на 2 минуты.
    private var кнопкаКопировать: some View {
        Button {
            UIPasteboard.general.setItems([["public.utf8-plain-text": доступ.пароль]],
                                          options: [.localOnly: true,
                                                    .expirationDate: Date().addingTimeInterval(120)])
            скопирован = true
        } label: {
            Label(т(скопирован ? "cr_copied" : "cr_copy"), systemImage: скопирован ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(КраскаВходаСайта.зелёный)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Файл kliko-dostup.txt сайта — текстом, лист «Поделиться» сохранит его в Файлы или отправит.
    private var файл: String {
        String(format: т("cr_file"), доступ.телефон, доступ.пароль)
    }
}

/// Системный лист «Поделиться» с ответом: сохранили (или отправили) или закрыли.
private struct ЛистПоделиться: UIViewControllerRepresentable {
    let предметы: [Any]
    let готово: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let лист = UIActivityViewController(activityItems: предметы, applicationActivities: nil)
        let ответ = готово
        лист.completionWithItemsHandler = { _, сделано, _, _ in
            DispatchQueue.main.async { ответ(сделано) }
        }
        return лист
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
