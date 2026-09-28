import SwiftUI

/**
 «УСТРОЙСТВА И ВХОДЫ» — ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»), cabSecDevices сайта
 (карта §1.4).

 sec_devices {csrf} → {sessions[{k, dev, ip, last, via, cur}], log[{dev, at, ip, via}], one_session, egov_can, egov_login}.
 Экран — как лист сайта: «Только одно устройство», «Подтверждать вход через eGov» (если он доступен или включён),
 «Сейчас вошли» с «Завершить» у чужих сеансов, «Выйти на всех других устройствах», «Последние входы».

 Запись — только по нажатию, как у сайта: переключатель «Только одно устройство» — sec_set {one_session} сразу;
 «Завершить» — sec_end {which: k}, «Выйти на всех других» — sec_end {which: "others"}. Не вышло — переключатель назад и
 текст сервера плашкой.
 🔴 Вход через eGov: включить — sec_set {egov_login: true}, но сначала вопрос с пояснением сайта (sec_egov_s: выключить
 можно только через eGov) — у сайта вопроса нет, а на тестовом аккаунте включать его карта запрещает (§8.8). Выключить —
 как _secEgov сайта: сначала шаг eGov otpStepOpen("sec_login", "off") — своё окно ОкноEGov (otp_step_create →
 remote.biometric.kz → otp_step_check), после удачи sec_set {egov_login: false} и список перечитывается. Кабинет сайта
 для этого больше не открывается.
 */
struct ЛистУстройств: View {
    let открыть: (URL) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var данные: Данные? = nil
    @State private var ошибка: String? = nil
    @State private var грузится = false
    @State private var занято = false
    @State private var спроситьВключение = false
    /// Окно шага eGov перед выключением входа через eGov.
    @State private var шагEgov = false

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    struct Сеанс: Identifiable {
        let id: String
        let устройство: String
        let ip: String
        let последний: Double
        let способ: String
        let это: Bool
    }

    struct Вход: Identifiable {
        let id: Int
        let устройство: String
        let когда: Double
        let ip: String
        let способ: String
    }

    struct Данные {
        var сеансы: [Сеанс]
        var журнал: [Вход]
        var одно: Bool
        var eGovДоступен: Bool
        var eGovВход: Bool
    }

    var body: some View {
        ЛистНастройки(заголовок: тН("sec_devices")) {
            содержимое
        }
        .task { await загрузить() }
        .confirmationDialog(тН("sec_egov_t"), isPresented: $спроситьВключение, titleVisibility: .visible) {
            Button(тН("sec_egov_on_btn")) { поставитьEgov(true) }
            Button(тН("cancel"), role: .cancel) {}
        } message: {
            Text(тН("sec_egov_s"))
        }
        .sheet(isPresented: $шагEgov) {
            ОкноEGov(запрос: Self.запросВыключения, готово: {
                шагEgov = false
                поставитьEgov(false)
            }, закрыть: {
                шагEgov = false
            })
        }
    }

    /// otpStepOpen("sec_login", "off") сайта: заголовок и подсказка — окна по умолчанию, как у сайта. «после» окно не
    /// читает (его читает только карточка сделки) — здесь оно формальное.
    private static let запросВыключения = ЗапросEGov(назначение: "sec_login", ссылка: "off", заголовок: "",
                                                     подсказка: "", после: .оплатить)

    @ViewBuilder
    private var содержимое: some View {
        if let д = данные {
            Form {
                переключатели(д)
                сейчас(д)
                if !д.журнал.isEmpty { журнал(д) }
            }
        } else if let ошибка {
            ПустоСайта(значок: "exclamationmark.triangle", заголовок: ошибка, кнопка: тН("capp_ok"),
                       действие: { Task { await загрузить() } })
        } else {
            VStack(spacing: 10) {
                SiteSpinner()
                Text(тН("loading")).foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы)
        }
    }

    private func переключатели(_ д: Данные) -> some View {
        Section {
            Toggle(isOn: Binding(get: { д.одно }, set: { поставитьОдно($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(тН("sec_one_t")).font(.system(size: 16, weight: .semibold))
                    Text(тН("sec_one_s")).font(.system(size: 13)).foregroundStyle(Theme.текстВторой)
                }
            }
            .tint(Theme.зелёныйЯркий)
            .disabled(занято)
            if д.eGovДоступен || д.eGovВход {
                Toggle(isOn: Binding(get: { д.eGovВход }, set: { хочет in
                    if хочет { спроситьВключение = true } else { шагEgov = true }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(тН("sec_egov_t")).font(.system(size: 16, weight: .semibold))
                        Text(тН("sec_egov_s")).font(.system(size: 13)).foregroundStyle(Theme.текстВторой)
                    }
                }
                .tint(Theme.зелёныйЯркий)
                .disabled(занято)
            }
        }
    }

    private func сейчас(_ д: Данные) -> some View {
        Section {
            ForEach(д.сеансы) { с in
                HStack(spacing: 12) {
                    значок(с.устройство)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(с.устройство).font(.system(size: 15, weight: .semibold))
                            if с.это {
                                Text(тН("sec_this"))
                                    .font(.system(size: 12, weight: .semibold).italic())
                                    .foregroundStyle(Theme.акцент)
                            }
                        }
                        Text(подписьСеанса(с))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    Spacer(minLength: 6)
                    if !с.это {
                        Button(тН("sec_end")) { завершить(с.id) }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.скидкаТекст)
                            .buttonStyle(.borderless)
                            .disabled(занято)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if д.сеансы.contains(where: { !$0.это }) {
                Button(role: .destructive) {
                    завершить("others")
                } label: {
                    Text(тН("sec_end_all")).font(.system(size: 15, weight: .semibold))
                }
                .disabled(занято)
            } else {
                Text(тН("sec_none_others"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
        } header: {
            Text(тН("sec_now"))
        }
    }

    private func журнал(_ д: Данные) -> some View {
        Section {
            ForEach(д.журнал) { в in
                HStack(spacing: 12) {
                    значок(в.устройство)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(в.устройство).font(.system(size: 15, weight: .semibold))
                        Text([Self.время(в.когда), "IP " + (в.ip.isEmpty ? "—" : в.ip), Self.способ(в.способ)]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(тН("sec_log"))
        }
    }

    /// _secЗначок: iPhone / Android / iPad — телефон, остальное — компьютер.
    private func значок(_ устройство: String) -> some View {
        let телефон = устройство.range(of: "iPhone|Android|iPad", options: [.regularExpression, .caseInsensitive]) != nil
        return Image(systemName: телефон ? "iphone" : "desktopcomputer")
            .font(.system(size: 18))
            .foregroundStyle(Theme.акцент)
            .frame(width: 28)
            .accessibilityHidden(true)
    }

    /// «IP x · активен сейчас · пароль» — ["IP "+ip, _secАктивность(last), _secСпособ(via)].filter(Boolean).
    private func подписьСеанса(_ с: Сеанс) -> String {
        ["IP " + (с.ip.isEmpty ? "—" : с.ip), Self.активность(с.последний), Self.способ(с.способ)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Запросы

    private func загрузить() async {
        guard !грузится else { return }
        грузится = true
        defer { грузится = false }
        do {
            let j = try await НастройкиAPI.отправить("cabinet.php?action=sec_devices", [:])
            if МоиОбъявленияAPI.да(j["ok"]) {
                данные = Self.разобрать(j)
                ошибка = nil
            } else {
                ошибка = НастройкиAPI.ошибка(j)
            }
        } catch {
            ошибка = НастройкиAPI.сбой(error)
        }
    }

    private func поставитьОдно(_ значение: Bool) {
        guard !занято, var д = данные else { return }
        д.одно = значение
        данные = д
        занято = true
        Task { @MainActor in
            defer { занято = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=sec_set", ["one_session": значение])
                if !МоиОбъявленияAPI.да(j["ok"]) {
                    откатитьОдно(!значение)
                    НастройкиМодель.shared.показать(НастройкиAPI.ошибка(j))
                }
            } catch {
                откатитьОдно(!значение)
                НастройкиМодель.shared.показать(тН("err_no_conn"))
            }
        }
    }

    private func откатитьОдно(_ значение: Bool) {
        guard var д = данные else { return }
        д.одно = значение
        данные = д
    }

    /// Включение — после вопроса; выключение — после шага eGov (окно ОкноEGov), как _secEgov сайта.
    private func поставитьEgov(_ значение: Bool) {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { занято = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=sec_set", ["egov_login": значение])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    if var д = данные {
                        д.eGovВход = значение
                        данные = д
                    }
                    НастройкиМодель.shared.показать(тН(значение ? "sec_egov_on" : "sec_egov_off"))
                    занято = false
                    await загрузить()
                } else {
                    НастройкиМодель.shared.показать(НастройкиAPI.ошибка(j))
                }
            } catch {
                НастройкиМодель.shared.показать(тН("err_no_conn"))
            }
        }
    }

    private func завершить(_ какой: String) {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            defer { занято = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=sec_end", ["which": какой])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let сколько = МоиОбъявленияAPI.целое(j["ended"])
                    НастройкиМодель.shared.показать(тН("sec_ended").replacingOccurrences(of: "{n}",
                                                                                      with: String(сколько)))
                    занято = false
                    await загрузить()
                } else {
                    НастройкиМодель.shared.показать(НастройкиAPI.ошибка(j))
                }
            } catch {
                НастройкиМодель.shared.показать(тН("err_no_conn"))
            }
        }
    }

    // MARK: - Разбор и подписи

    private static func разобрать(_ j: [String: Any]) -> Данные {
        typealias A = МоиОбъявленияAPI
        let сеансы: [Сеанс] = ((j["sessions"] as? [[String: Any]]) ?? []).enumerated().map { пара -> Сеанс in
            let с = пара.element
            let ключ = A.строка(с["k"])
            return Сеанс(id: ключ.isEmpty ? "s" + String(пара.offset) : ключ, устройство: A.строка(с["dev"]),
                         ip: A.строка(с["ip"]), последний: A.число(с["last"]), способ: A.строка(с["via"]),
                         это: A.да(с["cur"]))
        }
        let журнал: [Вход] = ((j["log"] as? [[String: Any]]) ?? []).enumerated().map { пара -> Вход in
            let в = пара.element
            return Вход(id: пара.offset, устройство: A.строка(в["dev"]), когда: A.число(в["at"]), ip: A.строка(в["ip"]),
                        способ: A.строка(в["via"]))
        }
        return Данные(сеансы: сеансы, журнал: журнал, одно: A.да(j["one_session"]), eGovДоступен: A.да(j["egov_can"]),
                      eGovВход: A.да(j["egov_login"]))
    }

    /// _secВремя: «дд.мм.гггг, чч:мм».
    static func время(_ секунды: Double) -> String {
        guard секунды > 0 else { return "" }
        let дата = Date(timeIntervalSince1970: секунды)
        let к = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: дата)
        return String(format: "%02d.%02d.%d, %02d:%02d", к.day ?? 0, к.month ?? 0, к.year ?? 0, к.hour ?? 0,
                      к.minute ?? 0)
    }

    /// _secАктивность: до 10 мин — «активен сейчас», до часа — «N мин назад», до суток — «N ч назад», дальше — дата.
    static func активность(_ секунды: Double) -> String {
        guard секунды > 0 else { return "" }
        let прошло = Int(Date().timeIntervalSince1970 - секунды)
        if прошло < 600 { return тН("sec_active_now") }
        if прошло < 3600 { return тН("sec_ago_min").replacingOccurrences(of: "{n}", with: String(прошло / 60)) }
        if прошло < 86400 { return тН("sec_ago_h").replacingOccurrences(of: "{n}", with: String(прошло / 3600)) }
        return время(секунды)
    }

    /// _secСпособ: известные — словом, прочее — как пришло.
    static func способ(_ via: String) -> String {
        switch via {
        case "password": return тН("sec_via_password")
        case "egov": return тН("sec_via_egov")
        case "telegram": return "Telegram"
        case "apple": return "Apple"
        case "register": return тН("sec_via_register")
        case "legacy": return тН("sec_via_legacy")
        case "dev": return тН("sec_via_dev")
        default: return via
        }
    }
}
