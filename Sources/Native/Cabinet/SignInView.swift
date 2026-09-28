import SwiftUI
import UIKit

/**
 ЭКРАН ВХОДА КАК У САЙТА — ЭТАП 40 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Гостевая страница /kz/ru/cabinet.php (карта кабинета §1.1): сначала ворота «С чего начнём?» — «Я покупатель» ведёт в
 форму регистрации по номеру, «Я продавец» — в окно eGov (оно живёт на странице сайта, cabinet.php?egov=1: там
 iframe biometric.kz с камерой, §1.2.4); «Уже есть аккаунт? Войти» — во вкладку входа. Дальше вкладки «Войти» /
 «Регистрация». Как у сайта (switchTab), путь к регистрации всегда идёт через ворота, пока человек не выбрал «Я
 покупатель»: «Зарегистрируйтесь» со вкладки входа тоже сначала показывает предложение eGov.

 Вход: номер с маской +7 (7XX) XXX-XX-XX и проверкой кода оператора (НомерКЗ = klkFmt/klkPhoneCheck), пароль, «Забыли
 пароль?» — окно «Восстановить доступ» (eGov по ИИН на странице сайта или поддержка: SMS-восстановления у сайта нет).
 Ответы — как у doLogin: вошёл → лист закрывается, кабинет перечитывает сеанс; need_egov → окно «Подтвердите вход через
 eGov» на странице сайта (?egov_confirm=1); deleted → «Аккаунт удалён» с причиной и «Обратиться в поддержку»; иначе —
 текст сервера или «Ошибка входа»; нет сети — «Нет соединения», прочее — «Ошибка приложения…».

 Регистрация: номер, ИИН (необязательно, 12 цифр), согласие с соглашением; «Создать аккаунт» → окно «Подтвердите
 номер» → register_quick только по «Всё верно, создать» → окно «Аккаунт создан» с паролем, показанным один раз.
 Пароль — чувствительные данные (§1.9): никуда не сохраняется сам, только по нажатию «Сохранить и продолжить» — в
 системном листе «Поделиться», как у сайта.

 «или войдите через» (в карточке под формами; на воротах, как у сайта, их нет): eGov — листом поверх (ОкноEgov), Apple — нативным листом Apple (ВходApple, apple_auth.php?action=native);
 пока сервер его не умеет — прежней страницей сайта apple_auth.php?action=start (§1.2.6). Telegram сайт скрыл по правилу
 App Store 4.8 — его нет и здесь.
 */
struct ЭкранВхода: View {
    enum Шаг: Equatable { case ворота, формы }
    enum Вкладка: Equatable { case вход, регистрация }
    enum Поле: Hashable { case телефон, пароль, номерРег, иин }

    /// const BIO_ON страницы: от него зависит окно «Восстановить доступ».
    let eGovВключён: Bool
    /// Открыть страницу сайта (лист перед этим закрывается).
    let открыть: (URL) -> Void
    /// Вошли — кабинет перечитает сеанс.
    let вошли: () -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var шаг: Шаг
    @State private var вкладка: Вкладка = .вход
    /// window.__gateDone сайта: «Я покупатель» выбран — ворота больше не встают перед регистрацией.
    @State private var решениеПринято = false
    @State private var телефон = ""
    @State private var пароль = ""
    @State private var парольВиден = false
    @State private var номерРег = ""
    @State private var иин = ""
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
    @State private var сравнение = false
    /// С этого мгновения считается ft регистрации — сколько человек пробыл на экране.
    @State private var открыт = Date()
    @FocusState private var фокус: Поле?

    init(eGovВключён: Bool, открыть: @escaping (URL) -> Void, вошли: @escaping () -> Void) {
        self.eGovВключён = eGovВключён
        self.открыть = открыть
        self.вошли = вошли
        _шаг = State(initialValue: Config.нативнаяРегистрация ? .ворота : .формы)
    }

    private func т(_ ключ: String) -> String { ВходText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if шаг == .ворота {
                        ВоротаВхода(выбрать: { роль in выбратьРоль(роль) },
                                    войти: { открытьФормы(.вход) },
                                    сравнить: { сравнение = true })
                    } else {
                        формы
                    }
                }
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
        .onChange(of: иин) { _, стало in
            let цифры = String(НомерКЗ.цифры(стало).prefix(12))
            if цифры != стало { иин = цифры }
        }
        .alert(окно?.заголовок ?? "", isPresented: окноПоказано, presenting: окно) { о in
            кнопкиОкна(о)
        } message: { о in
            Text(текстОкна(о))
        }
        .sheet(item: $доступ) { д in
            ЛистДоступа(доступ: д, продолжить: { продолжитьПослеРегистрации() })
        }
        .sheet(isPresented: $сравнение) {
            ЛистСравнения(выбрать: { роль in
                сравнение = false
                /* Сначала уходит лист сравнения: «Регистрация через eGov» закрывает и этот лист — два разом SwiftUI
                   закрывает ненадёжно. */
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    выбратьРоль(роль)
                }
            })
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
                TextField(т("auth_phone"), text: $телефон, prompt: Text(verbatim: "+7 (700) 000-00-00"))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
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
                    .textContentType(.telephoneNumber)
                    .focused($фокус, equals: .номерРег)
            }
            ПолеВхода(подпись: т("auth_iin_opt"), ошибка: nil, вФокусе: фокус == .иин) {
                TextField(т("auth_iin_opt"), text: $иин, prompt: Text(verbatim: "000000000000"))
                    .keyboardType(.numberPad)
                    .focused($фокус, equals: .иин)
            }
            Text(т("auth_iin_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            СогласиеВхода(принято: $согласие)
            if let ошибка = ошибкаРег { ОшибкаФормы(текст: ошибка) }
            КнопкаСайта(подпись: т("auth_create"), идёт: идёт) { создать() }
            ПереходФормы(вопрос: т("auth_have_acc"), ссылка: т("auth_do_login"), жирная: false) {
                выбратьВкладку(.вход)
            }
        }
    }

    // MARK: - Вход через сервисы

    /// «или войдите через» (.soc-btns — в карточке под формами, на воротах их нет): eGov — листом поверх (ОкноEgov),
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
                открытьФормы(.вход)
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

    /// authGateRole сайта: роль — в localStorage; продавец — окно eGov на странице сайта, покупатель — регистрация.
    private func выбратьРоль(_ роль: String) {
        Task { await КабинетСайта.запомнитьРоль(роль) }
        if роль == "seller" {
            eGov("cabinet.php?egov=1")
            return
        }
        guard Config.нативнаяРегистрация else {
            наСайт(Config.страницаСайта("cabinet.php"))
            return
        }
        решениеПринято = true
        открытьФормы(.регистрация)
    }

    private func открытьФормы(_ куда: Вкладка) {
        шаг = .формы
        вкладка = куда
    }

    /// switchTab сайта: к регистрации — через ворота, пока человек не выбрал «Я покупатель».
    private func выбратьВкладку(_ куда: Вкладка) {
        ошибкаВхода = nil
        ошибкаРег = nil
        if куда == .регистрация {
            guard Config.нативнаяРегистрация else {
                наСайт(Config.страницаСайта("cabinet.php"))
                return
            }
            if !решениеПринято {
                шаг = .ворота
                return
            }
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

    /// doQuickRegister: номер, ИИН (пусто или 12 цифр), согласие — потом окно «Подтвердите номер».
    private func создать() {
        guard !идёт else { return }
        ошибкаРег = nil
        if let ошибка = НомерКЗ.ошибка(номерРег) {
            ошибкаНомераРег = ошибка
            фокус = .номерРег
            return
        }
        let чистый = НомерКЗ.цифры(иин)
        if !чистый.isEmpty && чистый.count != 12 {
            ошибкаРег = т("auth_iin_bad")
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
        let чистый = НомерКЗ.цифры(иин)
        let мс = Int(max(0, Date().timeIntervalSince(открыт)) * 1000)
        Task { @MainActor in
            defer { идёт = false }
            do {
                let итог = try await КабинетСайта.зарегистрировать(телефон: номер, иин: чистый, мсНаЭкране: мс)
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

    /// «Сохранить и продолжить» / «Продолжить без сохранения» — как у сайта, перезагрузка уже вошедшим.
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
    /// --acc-on: #0f5132 и #5cd39a (значки ролей, кнопка eGov, колонка «С eGov»).
    static let акцент = Theme.цвет(0x0F5132, 0x5CD39A)
    /// --tint-ok: #e7f6ee и rgba(52,201,151,.14).
    static let тинт = Theme.цвет(светлый: Theme.hex(0xE7F6EE), тёмный: Theme.hex(0x34C997, 0.14))
    /// --edge-ok: #cdebd7 и rgba(52,201,151,.32).
    static let кромка = Theme.цвет(светлый: Theme.hex(0xCDEBD7), тёмный: Theme.hex(0x34C997, 0.32))
    /// surf2 плитки значка роли: #f6faf8 и #23232f.
    static let плитка = Theme.цвет(0xF6FAF8, 0x23232F)
    /// --red ошибок формы: #c0392b и #ff6168.
    static let ошибка = Theme.цвет(0xC0392B, 0xFF6168)
    /// --danger: #991b1b и #ff8a8f (крестик «Без eGov»).
    static let опасно = Theme.цвет(0x991B1B, 0xFF8A8F)
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

/// Ворота #auth-gate: «С чего начнём?», две роли, «Уже есть аккаунт? Войти», «Чем отличаются пути».
private struct ВоротаВхода: View {
    let выбрать: (String) -> Void
    let войти: () -> Void
    let сравнить: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(ВходText.т("gate_role_t"))
                .font(.system(size: 19, weight: .heavy))
                .lineSpacing(4)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 10) {
                КнопкаРоли(заголовок: ВходText.т("gate_role_buyer"), подпись: ВходText.т("gate_role_buyer_s"),
                           значок: "cart", главная: false) { выбрать("buyer") }
                КнопкаРоли(заголовок: ВходText.т("gate_role_seller"), подпись: ВходText.т("gate_role_seller_s"),
                           значок: "checkmark.shield", главная: true) { выбрать("seller") }
            }
            ПереходФормы(вопрос: ВходText.т("gate_have"), ссылка: ВходText.т("auth_login"), жирная: true,
                         действие: войти)
                .padding(.top, 16)
            /* Второй абзац: 12, по центру, lh 1.5; «Чем отличаются пути» — серая подчёркнутая (.auth-cmp). */
            VStack(spacing: 2) {
                Text(ВходText.т("gate_role_note"))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: сравнить) {
                    Text(ВходText.т("gate_role_cmp"))
                        .underline()
                        .foregroundStyle(Theme.текстВторой)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
        .карточкаВходаСайта()
    }
}

/// .auth-role: 14 внутри, радиус 18, плитка 42 (радиус 14), заголовок 15/800, подпись 13; продавец — .primary (тинт).
private struct КнопкаРоли: View {
    let заголовок: String
    let подпись: String
    let значок: String
    let главная: Bool
    let действие: () -> Void

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(КраскаВходаСайта.акцент)
                    .frame(width: 42, height: 42)
                    .background(главная ? КраскаВходаСайта.карточка : КраскаВходаСайта.плитка,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(главная ? КраскаВходаСайта.тинт : КраскаВходаСайта.карточка, in: форма)
            .overlay {
                форма.strokeBorder(главная ? КраскаВходаСайта.кромка : КраскаВходаСайта.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
        .accessibilityElement(children: .combine)
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

/// «Нет аккаунта? Зарегистрируйтесь» и подобные: 13, по центру, ссылка --g (на воротах — жирная).
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
            let своё = MainActor.assumeIsolated { () -> Bool in НативныеОкна.перехватить(адрес) }
            return своё ? .handled : .systemAction
        }
    }
}

// MARK: - «Аккаунт создан»

/// Окно showCredsWindow сайта: телефон и пароль один раз; сохранить — только по нажатию, через «Поделиться».
private struct ЛистДоступа: View {
    let доступ: ДоступАккаунта
    let продолжить: () -> Void
    @State private var делимся = false

    private func т(_ ключ: String) -> String { ВходText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                /* Шапка окна: круг 56 --tint-ok со значком --on-ok, заголовок 19/800, подпись 13 — по центру. */
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
                данные
                Text(т("cr_how"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Text(т("cr_shot"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                Text(т("cr_change"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                КнопкаСайта(подпись: т("cr_go"), идёт: false) { делимся = true }
                Button(т("cr_skip"), action: продолжить)
                    .font(.system(size: 16, weight: .semibold))
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
        .sheet(isPresented: $делимся) {
            ЛистПоделиться(предметы: [файл]) { сохранили in
                делимся = false
                if сохранили { продолжить() }
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

// MARK: - «Чем отличаются пути»

/// Сравнительная таблица сайта: «Без eGov» / «С eGov», пример карточки, «Регистрация через eGov» / «Всё равно продолжить».
private struct ЛистСравнения: View {
    let выбрать: (String) -> Void
    @Environment(\.dismiss) private var закрыть

    private static let строки: [String] = ["feed", "esc", "chat", "extra", "money", "trust"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Text(ВходText.т("gate_why_t"))
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(ВходText.т("gate_why_s"))
                        .font(.system(size: 13))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    шапкаТаблицы
                        .padding(.top, 16)
                    /* .gw-row: две равные колонки, 10 сверху и снизу, черта между строками (у первой — нет). */
                    VStack(spacing: 0) {
                        ForEach(Array(Self.строки.enumerated()), id: \.element) { номер, ключ in
                            строка(ключ)
                                .padding(.vertical, 10)
                                .overlay(alignment: .top) {
                                    if номер > 0 {
                                        Rectangle().fill(КраскаВходаСайта.линия).frame(height: 1)
                                    }
                                }
                        }
                    }
                    .padding(.top, 8)
                    КнопкаСайта(подпись: ВходText.т("gate_go"), идёт: false) { выбрать("seller") }
                        .padding(.top, 16)
                    Button(ВходText.т("gate_anyway")) { выбрать("buyer") }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .padding(.top, 6)
                }
                .padding(20)
                .мерилоФормы()
            }
            .background(КраскаВходаСайта.карточка.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ВходText.т("close")) { закрыть() }
                }
            }
        }
        /* По высоте таблицы и кнопок — без пустоты снизу. */
        .листПоВысоте()
    }

    /// .gw-head: 11/800 прописными, разрядка .06em, по центру; правая колонка — --acc-on.
    private var шапкаТаблицы: some View {
        HStack(spacing: 8) {
            Text(ВходText.т("gate_col_n").uppercased())
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
            Text(ВходText.т("gate_col_y").uppercased())
                .foregroundStyle(КраскаВходаСайта.акцент)
                .frame(maxWidth: .infinity)
        }
        .font(.system(size: 11, weight: .heavy))
        .tracking(0.66)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private func строка(_ ключ: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ячейка(ВходText.т("gate_r_" + ключ + "_n"), да: false)
            ячейка(ВходText.т("gate_r_" + ключ + "_y"), да: true)
        }
    }

    /// .gw-c: значок и текст через 6, 13 (lh 1.4); «Без eGov» — серым с красным крестом, «С eGov» — ink 600 с галочкой.
    private func ячейка(_ текст: String, да: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: да ? "checkmark" : "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(да ? КраскаВходаСайта.акцент : КраскаВходаСайта.опасно)
                .frame(width: 14, height: 18)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 13, weight: да ? .semibold : .regular))
                .lineSpacing(5)
                .foregroundStyle(да ? Theme.текст : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(ВходText.т(да ? "gate_col_y" : "gate_col_n") + ": " + текст))
    }
}
