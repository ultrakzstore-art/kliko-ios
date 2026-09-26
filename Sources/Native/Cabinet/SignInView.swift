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

 «или войдите через»: eGov — листом поверх (ОкноEgov), Apple — страницей сайта (callback Apple в файлах сайта не виден, §1.2.6); Telegram сайт
 скрыл по правилу App Store 4.8 — его нет и здесь.
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
                    способы
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
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

    private var формы: some View {
        VStack(alignment: .leading, spacing: 14) {
            ВкладкиВхода(выбрана: вкладка, выбрать: { куда in выбратьВкладку(куда) })
            if вкладка == .вход {
                формаВхода
            } else {
                формаРегистрации
            }
        }
        .padding(18)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var формаВхода: some View {
        VStack(alignment: .leading, spacing: 12) {
            ПолеВхода(подпись: т("auth_phone"), ошибка: ошибкаНомера, вФокусе: фокус == .телефон) {
                TextField(т("auth_phone"), text: $телефон, prompt: Text(verbatim: "+7 (700) 000-00-00"))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($фокус, equals: .телефон)
            }
            ПолеВхода(подпись: т("auth_pass"), ошибка: nil, вФокусе: фокус == .пароль) {
                полеПароля
            }
            Button(т("auth_forgot")) { окно = .восстановление }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
            if let ошибка = ошибкаВхода { ОшибкаФормы(текст: ошибка) }
            КнопкаСайта(подпись: т("auth_login"), идёт: идёт) { войти() }
            ПереходФормы(вопрос: т("auth_no_acc"), ссылка: т("auth_do_register")) { выбратьВкладку(.регистрация) }
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
        VStack(alignment: .leading, spacing: 12) {
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
            ПереходФормы(вопрос: т("auth_have_acc"), ссылка: т("auth_do_login")) { выбратьВкладку(.вход) }
        }
    }

    // MARK: - Вход через сервисы

    /// «или войдите через»: eGov — листом поверх (ОкноEgov), Apple — страницей сайта; ниже — согласие и примечание о номере, как у сайта.
    private var способы: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.линия).frame(height: 1)
                Text(т("auth_or_via"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize()
                Rectangle().fill(Theme.линия).frame(height: 1)
            }
            Text(ТекстСогласия.строка(т("auth_agree_soc")))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            КнопкаСервиса(подпись: т("auth_via_egov"), значок: "checkmark.shield", тёмная: false) {
                eGov("cabinet.php?egov=1")
            }
            КнопкаСервиса(подпись: т("auth_via_apple"), значок: "apple.logo", тёмная: true) {
                наСайт(Config.url("/apple_auth.php?action=start"))
            }
            Text(т("auth_phone_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
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
            Button(т("deleted_support")) { наСайт(Config.url("/support.php?topic=access")) }
            Button(т("close"), role: .cancel) {}
        case .восстановление:
            if eGovВключён {
                Button(т("reg_recover_egov")) { eGov("cabinet.php?egov=1") }
            } else {
                Button(т("rec_support")) { наСайт(Config.url("/support.php?topic=access")) }
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

    /// Страница сайта вместо этого листа.
    private func наСайт(_ адрес: URL?) {
        guard let адрес else { return }
        закрыть()
        открыть(адрес)
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

/// Ворота #auth-gate: «С чего начнём?», две роли, «Уже есть аккаунт? Войти», «Чем отличаются пути».
private struct ВоротаВхода: View {
    let выбрать: (String) -> Void
    let войти: () -> Void
    let сравнить: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ВходText.т("gate_role_t"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            КнопкаРоли(заголовок: ВходText.т("gate_role_buyer"), подпись: ВходText.т("gate_role_buyer_s"),
                       значок: "bag") { выбрать("buyer") }
            КнопкаРоли(заголовок: ВходText.т("gate_role_seller"), подпись: ВходText.т("gate_role_seller_s"),
                       значок: "checkmark.shield") { выбрать("seller") }
            ПереходФормы(вопрос: ВходText.т("gate_have"), ссылка: ВходText.т("auth_login"), действие: войти)
            Text(ВходText.т("gate_role_note"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
            Button(ВходText.т("gate_role_cmp"), action: сравнить)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
        }
        .padding(18)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

private struct КнопкаРоли: View {
    let заголовок: String
    let подпись: String
    let значок: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 40, height: 40)
                    .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityElement(children: .combine)
    }
}

/// Вкладки «Войти» / «Регистрация».
private struct ВкладкиВхода: View {
    let выбрана: ЭкранВхода.Вкладка
    let выбрать: (ЭкранВхода.Вкладка) -> Void

    var body: some View {
        HStack(spacing: 4) {
            вкладка(.вход, ВходText.т("auth_login"))
            вкладка(.регистрация, ВходText.т("auth_register"))
        }
        .padding(4)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private func вкладка(_ какая: ЭкранВхода.Вкладка, _ подпись: String) -> some View {
        let выбран = какая == выбрана
        return Button {
            выбрать(какая)
        } label: {
            Text(подпись)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(выбран ? Theme.зелёный : Theme.текстВторой)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(выбран ? Theme.поверхность : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Поле формы: подпись сверху, рамка 1,5 (в фокусе — зелёная), причина у поля красным (.kzph-err).
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
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(Theme.поверхность, in: форма)
                .overlay {
                    форма.strokeBorder(ошибка != nil ? Theme.ценаСкидка : (вФокусе ? Theme.зелёный2 : Theme.линия),
                                       lineWidth: 1.5)
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

private struct ОшибкаФормы: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.скидкаТекст)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.скидкаФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Главная зелёная кнопка формы; в пути — колесо вместо подписи (спиннер сайта).
struct КнопкаСайта: View {
    let подпись: String
    let идёт: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            ZStack {
                if идёт {
                    ProgressView()
                        .tint(Color.white)
                } else {
                    Text(подпись)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(идёт)
        .accessibilityLabel(подпись)
    }
}

private struct КнопкаСервиса: View {
    let подпись: String
    let значок: String
    let тёмная: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(тёмная ? Color.white : Theme.текст)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(тёмная ? Color.black : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(тёмная ? Color.clear : Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }
}

/// «Нет аккаунта? Зарегистрируйтесь» и подобные.
private struct ПереходФормы: View {
    let вопрос: String
    let ссылка: String
    let действие: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(вопрос)
                .foregroundStyle(Theme.текстВторой)
            Button(ссылка, action: действие)
                .fontWeight(.bold)
                .foregroundStyle(Theme.зелёный2)
        }
        .font(.system(size: 14))
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
            Text(ТекстСогласия.строка(ВходText.т("auth_agree")))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Текст согласия со ссылками: %@ и %@ — «Пользовательское соглашение» (/soglashenie.php) и «Политику
/// конфиденциальности» (/privacy.php), как у сайта. Ссылки открывает система (Safari) — форма со введённым остаётся.
enum ТекстСогласия {
    static func строка(_ шаблон: String) -> AttributedString {
        let соглашение = "[" + ВходText.т("auth_terms_link") + "](https://kliko.kz/soglashenie.php)"
        let политика = "[" + ВходText.т("auth_privacy_link") + "](https://kliko.kz/privacy.php)"
        let разметка = String(format: шаблон, соглашение, политика)
        return (try? AttributedString(markdown: разметка)) ?? AttributedString(String(format: шаблон,
                                                                                    ВходText.т("auth_terms_link"),
                                                                                    ВходText.т("auth_privacy_link")))
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(т("cr_t"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Text(т("cr_s"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
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
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $делимся) {
            ЛистПоделиться(предметы: [файл]) { сохранили in
                делимся = false
                if сохранили { продолжить() }
            }
        }
    }

    private var данные: some View {
        VStack(alignment: .leading, spacing: 10) {
            строка(т("cr_phone"), доступ.телефон)
            Rectangle().fill(Theme.линия).frame(height: 1)
            строка(т("cr_pass"), доступ.пароль)
        }
        .padding(14)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private func строка(_ подпись: String, _ значение: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(подпись)
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            Text(значение)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.текст)
                .textSelection(.enabled)
        }
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
                VStack(alignment: .leading, spacing: 14) {
                    Text(ВходText.т("gate_why_t"))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(ВходText.т("gate_why_s"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Self.строки, id: \.self) { ключ in
                        строка(ключ)
                    }
                    КнопкаСайта(подпись: ВходText.т("gate_go"), идёт: false) { выбрать("seller") }
                    Button(ВходText.т("gate_anyway")) { выбрать("buyer") }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .padding(20)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ВходText.т("close")) { закрыть() }
                }
            }
        }
    }

    private func строка(_ ключ: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ячейка(ВходText.т("gate_col_n"), ВходText.т("gate_r_" + ключ + "_n"), да: false)
            ячейка(ВходText.т("gate_col_y"), ВходText.т("gate_r_" + ключ + "_y"), да: true)
        }
    }

    private func ячейка(_ колонка: String, _ текст: String, да: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(колонка, systemImage: да ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(да ? Theme.зелёный2 : Theme.текстВторой)
            Text(текст)
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(да ? Theme.мята : Theme.поверхность,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
