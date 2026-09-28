import SwiftUI
import UIKit
import WebKit

/**
 ОКНА ПОВЕРХ ВКЛАДОК ВМЕСТО СТРАНИЦ САЙТА (владелец 26.09.2026, проверка TestFlight 1.10 на телефоне: «сделай все моменты
 что бы все нативно было»).

 Раньше эти нажатия открывали страницу сайта под нативным слоем — приложение целиком уходило на сайт:
   · «Войти» в переписке, чате объявления, списке сообщений и «Зарегистрироваться» панели связи — /cabinet.php;
   · «Пройти верификацию» — сразу /cabinet?go=verify; теперь сначала своё окно «Стать продавцом» (verPromo сайта:
     что даёт проверка, статус, «Отклонено»), и только сама проверка eGov — защищённой страницей сайта (государственный
     поток, так и остаётся);
   · «Удалить аккаунт» — кабинет сайта; теперь свой лист тех же шагов, что acctDelOpen сайта (карта §1.5.7):
     account_delete_send → пароль / код с экрана → account_delete_confirm → ВыходНачисто. Ветка need_egov — как
     acctDelConfirm сайта: account_delete_confirm отвечает need_egov → своё окно шага eGov ОкноEGov (otpStepOpen
     purpose || "delete", "account") → после удачи тот же account_delete_confirm ещё раз; запасное «Подтвердить
     паролем», если сервер разрешил (can_pass);
   · «Написать в поддержку» (support.php?topic=payment|other) — теперь своя форма: POST support.php?action=create, как
     dataReqSend сайта (тема та же, что в адресе), и после неё — переписка по обращению (?ticket=<id>, этап 45).

 Окна висят на слое вкладок (СлойОконПриложения в NativeTabsView) — одно на всё приложение, как лист у сайта. Пока
 открыт другой лист или окно (подача, карточка сделки, алерт), своё поверх не встанет: SwiftUI молча не покажет его. Поэтому
 показать() проверяет это в момент показа и тогда показывает окно поверх верхнего экрана (OverlayWindows.swift).
 */
@MainActor
final class ОкнаПриложения: ObservableObject {
    static let shared = ОкнаПриложения()

    enum Окно: Identifiable, Equatable {
        case вход
        case верификация
        case удалениеАккаунта
        /// Тема — как в адресе сайта support.php?topic=<тема>: payment, other, access.
        case поддержка(тема: String)

        var id: String {
            switch self {
            case .вход: return "login"
            case .верификация: return "verify"
            case .удалениеАккаунта: return "delete"
            case .поддержка(let тема): return "support:" + тема
            }
        }
    }

    /// Вход состоялся в окне входа — экраны, просившие войти, перечитывают себя.
    static let вошли = Notification.Name("kliko.okna.voshli")
    /// Аккаунт удалён — кабинет забывает вошедшего.
    static let аккаунтУдалён = Notification.Name("kliko.okna.akkaunt_udalen")

    @Published var окно: Окно? = nil
    /// Сколько слоёв вкладок на экране (при смене языка слой пересобирается: новый появляется раньше, чем уходит старый).
    private var слоёв = 0

    private init() {}

    func подключить() { слоёв += 1 }
    func отключить() { слоёв = max(0, слоёв - 1) }

    /**
     Показать окно. false — слоя вкладок нет (или вход не свой): вызывающий открывает страницу сайта, как раньше. true —
     окно встанет (через задержку, если её дали: лист или алерт вызывающего ещё уезжает); если в момент показа занято
     другим окном — поверх верхнего экрана (OverlayWindows.swift). запасной больше не открывается.
     */
    @discardableResult
    func показать(_ новое: Окно, задержка: UInt64 = 0, запасной: URL? = nil) -> Bool {
        guard слоёв > 0, WebBridge.shared.лентаВидна else { return false }
        if case .вход = новое, !(Config.нативныйВход && Config.нативныйКабинет) { return false }
        Task { @MainActor in
            if задержка > 0 { try? await Task.sleep(nanoseconds: задержка) }
            if Self.занятоОкном {
                /* Уже открыт лист или полноэкранное окно: вход и «Стать продавцом» — поверх него из верхнего
                   контроллера (OverlayWindows.swift), прочее — запасная страница сайта, как было. */
                switch новое {
                case .вход:
                    ВходПоверх.показать()
                case .верификация:
                    ВерификацияПоверх.показать()
                case .поддержка(let тема):
                    ПоддержкаПоверх.поверх(тема: тема)
                case .удалениеАккаунта:
                    /* Свой лист поверх верхнего экрана, не кабинет сайта; запасной больше не нужен. */
                    ПоверхВсего.показать(смахивается: false) { закрыть in
                        ЛистУдаленияАккаунта(открыть: { адрес in
                            закрыть()
                            ПоверхВсего.открытьАдрес(адрес)
                        })
                    }
                }
                return
            }
            self.окно = новое
        }
        return true
    }

    /// На экране уже есть лист, полноэкранное окно или алерт — у корневого контроллера что-то показано.
    private static var занятоОкном: Bool {
        for сцена in UIApplication.shared.connectedScenes {
            guard let окно = сцена as? UIWindowScene else { continue }
            for w in окно.windows where w.isKeyWindow {
                if w.rootViewController?.presentedViewController != nil { return true }
            }
        }
        return false
    }
}

/// Слой окон на вкладках: лист выбранного окна.
struct СлойОконПриложения: ViewModifier {
    @ObservedObject private var окна = ОкнаПриложения.shared
    let открыть: (URL) -> Void

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $окна.окно) { окно in
                лист(окно)
            }
            .onAppear { окна.подключить() }
            .onDisappear { окна.отключить() }
    }

    @ViewBuilder
    private func лист(_ окно: ОкнаПриложения.Окно) -> some View {
        switch окно {
        case .вход:
            ЭкранВхода(eGovВключён: НастройкиМодель.shared.профиль?.eGovВкл ?? true, открыть: открыть, вошли: {
                NotificationCenter.default.post(name: ОкнаПриложения.вошли, object: nil)
            })
        case .верификация:
            ЛистВерификации(открыть: открыть)
        case .удалениеАккаунта:
            ЛистУдаленияАккаунта(открыть: открыть)
        case .поддержка(let тема):
            ЛистОбращения(тема: тема, открыть: открыть)
        }
    }
}

private func тО(_ ключ: String) -> String { ОкнаКабинетаText.т(ключ) }

/// Закрыть лист и через паузу открыть страницу сайта: два перехода разом SwiftUI делает ненадёжно.
@MainActor
private func наСайтПослеЛиста(_ адрес: URL?, открыть: @escaping (URL) -> Void, закрыть: DismissAction) {
    закрыть()
    guard let адрес else { return }
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: 450_000_000)
        открыть(адрес)
    }
}

// MARK: - «Стать продавцом» перед верификацией (verPromo сайта)

@MainActor
struct ЛистВерификации: View {
    let открыть: (URL) -> Void
    @ObservedObject private var настройки = НастройкиМодель.shared
    @Environment(\.dismiss) private var закрыть

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private struct Выгода: Identifiable {
        let id: String
        let значок: String
    }

    private static let выгоды: [Выгода] = [
        Выгода(id: "vp_b1", значок: "lock.shield"),
        Выгода(id: "vp_b2", значок: "checkmark.seal"),
        Выгода(id: "vp_b3", значок: "phone"),
        Выгода(id: "vp_b4", значок: "storefront"),
        Выгода(id: "vp_b5", значок: "sparkles"),
    ]

    private var проверен: Bool { настройки.профиль?.верифицирован ?? false }
    private var отклонена: Bool { настройки.профиль?.проверкаОтклонена ?? false }
    private var eGovВкл: Bool { настройки.профиль?.eGovВкл ?? true }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if проверен {
                        готово
                    } else {
                        вступление
                        ForEach(Self.выгоды) { в in строкаВыгоды(в) }
                        кнопки
                    }
                }
                .padding(16)
                .мерилоФормы()
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(тО(проверен ? "ver_done_t" : "vp_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(тО("close")) { закрыть() }
                }
            }
        }
        /* По высоте содержимого — без пустоты снизу. */
        .листПоВысоте()
    }

    private var готово: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.проверен)
                .accessibilityHidden(true)
            Text(тО("ver_done_s"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var вступление: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(тО("vp_sub"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            if отклонена {
                Label(тО("ver_rej"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func строкаВыгоды(_ в: Выгода) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: в.значок)
                .font(.system(size: 18))
                .foregroundStyle(Theme.акцент)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(тО(в.id + "_t"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(тО(в.id + "_d"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var кнопки: some View {
        VStack(spacing: 10) {
            if eGovВкл {
                Button {
                    наСайтПослеЛиста(Config.страницаСайта("cabinet?go=verify"), открыть: открыть, закрыть: закрыть)
                } label: {
                    Text(тО("vp_go"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(.plain)
                Text(тО("ver_site_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(тО("ver_off"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(тО("vp_later")) { закрыть() }
                .font(.system(size: 15, weight: .semibold))
                .tint(Theme.акцент)
                .frame(minHeight: 44)
            Text(тО("vp_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }
}

// MARK: - Удаление аккаунта (acctDelOpen … acctDelDone сайта)

@MainActor
struct ЛистУдаленияАккаунта: View {
    private typealias A = МоиОбъявленияAPI

    private enum Шаг: Equatable {
        case вопрос
        case подтверждение(eGov: Bool, пароль: Bool)
        case готово
    }

    let открыть: (URL) -> Void
    @Environment(\.dismiss) private var закрыть

    @State private var шаг: Шаг = .вопрос
    /// window._adlCanPass сайта: при eGov можно подтвердить паролем.
    @State private var можноПаролем = false
    /// window._adlCode сайта: случайные 6 цифр, созданные здесь же (без eGov и пароля).
    @State private var код = ""
    @State private var введённыйКод = ""
    @State private var пароль = ""
    @State private var причина = ""
    @State private var идёт = false
    @State private var ошибка: String? = nil
    /// Окно шага eGov (otpStepOpen сайта), пока открыто.
    @State private var окноEgov: ОкноEGovУдаления? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if шаг == .готово {
                        итог
                    } else {
                        шапка
                        пункты
                        сохраняем
                        тело
                    }
                }
                .padding(16)
                .мерилоФормы()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(тО("adl_ok"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(тО(шаг == .готово ? "adl_bye" : "adl_cancel")) { закрыть() }
                        .disabled(идёт)
                }
            }
        }
        /* По высоте шага — без пустоты снизу. */
        .листПоВысоте()
        .interactiveDismissDisabled(идёт)
        .sheet(item: $окноEgov) { окно in
            ОкноEGov(запрос: окно.запрос, готово: {
                /* Как onOk сайта: eGov пройден — acctDelConfirm ещё раз с теми же полями. */
                окноEgov = nil
                удалить()
            }, закрыть: {
                окноEgov = nil
            })
        }
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "trash")
                .font(.system(size: 26))
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                .accessibilityHidden(true)
            Text(тО("adl_t"))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(тО("adl_s"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var пункты: some View {
        VStack(alignment: .leading, spacing: 8) {
            пункт("adl_l1")
            пункт("adl_l2")
            пункт("adl_l3")
        }
    }

    private func пункт(_ ключ: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(тО(ключ))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var сохраняем: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock")
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(тО("adl_keep"))
                Text(тО("adl_undo"))
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    @ViewBuilder
    private var тело: some View {
        switch шаг {
        case .вопрос:
            VStack(spacing: 10) {
                строкаОшибки
                главная(тО("adl_send")) { продолжить() }
            }
        case .подтверждение(let eGov, let нуженПароль):
            if eGov {
                шагEgov
            } else {
                шагПодтверждения(нуженПароль: нуженПароль)
            }
        case .готово:
            EmptyView()
        }
    }

    /// need_egov: «Подтвердить через eGov» — acctDelConfirm сайта, сервер ответит need_egov и откроется окно шага eGov.
    /// Разрешён пароль — можно им.
    private var шагEgov: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(тО("adl_egov"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            TextField(тО("adl_why"), text: $причина)
                .textFieldStyle(.roundedBorder)
            строкаОшибки
            главная(тО("adl_ok_egov")) { удалить() }
            if можноПаролем {
                ссылка(тО("adl_pass_alt")) { перейтиКоВторому(eGov: false, пароль: true) }
            } else {
                ссылка(тО("adl_sup_alt")) {
                    /* Лист меняется на форму обращения (тема other — как ссылка сайта). */
                    ОкнаПриложения.shared.окно = .поддержка(тема: "other")
                }
            }
        }
    }

    private func шагПодтверждения(нуженПароль: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if нуженПароль {
                Text(тО("adl_pass_h"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                SecureField(тО("adl_pass_ph"), text: $пароль)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
            }
            if !код.isEmpty {
                Text(String(format: тО("adl_code_h"), код))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(тО("adl_code_ph"), text: $введённыйКод)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .textFieldStyle(.roundedBorder)
            }
            TextField(тО("adl_why"), text: $причина)
                .textFieldStyle(.roundedBorder)
            строкаОшибки
            главная(тО("adl_ok"), опасная: true) { удалить() }
        }
    }

    private var итог: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(тО("adl_done"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            главная(тО("adl_bye")) { закрыть() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    @ViewBuilder
    private var строкаОшибки: some View {
        if let сообщение = ошибка {
            Text(сообщение)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func главная(_ подпись: String, опасная: Bool = false, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if идёт { ProgressView().tint(Color.white) }
                Text(подпись)
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(опасная ? Color.red : Theme.зелёный2,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(идёт)
    }

    private func ссылка(_ подпись: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(идёт)
    }

    // MARK: - Запросы

    /// Текст сервера, если это не машинный код; нет сессии — «войдите заново»; иначе запасной текст сайта.
    private func текстОшибки(_ j: [String: Any], запасной: String) -> String {
        if A.нетСессии(j) { return НастройкиText.т("auth") }
        let текст = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if текст.isEmpty || КабинетСайта.машинныйКод(текст) { return запасной }
        return текст
    }

    /// acctDelStep2 сайта: без eGov и пароля — код с экрана.
    private func перейтиКоВторому(eGov: Bool, пароль нуженПароль: Bool) {
        код = (eGov || нуженПароль) ? "" : String(Int.random(in: 100_000...999_999))
        введённыйКод = ""
        ошибка = nil
        шаг = .подтверждение(eGov: eGov, пароль: нуженПароль)
    }

    /// acctDelSend: POST account_delete_send {csrf}.
    private func продолжить() {
        guard !идёт else { return }
        идёт = true
        ошибка = nil
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=account_delete_send", [:])
                if A.да(j["ok"]) {
                    можноПаролем = A.да(j["can_pass"])
                    перейтиКоВторому(eGov: A.да(j["need_egov"]), пароль: A.да(j["need_pass"]))
                } else {
                    ошибка = текстОшибки(j, запасной: тО("adl_fail"))
                }
            } catch {
                ошибка = тО("phc_net")
            }
        }
    }

    /// acctDelConfirm: код сверяется здесь же; POST account_delete_confirm {csrf, reason, password}.
    private func удалить() {
        guard !идёт else { return }
        if !код.isEmpty {
            let цифры = введённыйКод.filter { $0.isASCII && $0.isNumber }
            guard цифры == код else {
                ошибка = тО("adl_code_bad")
                return
            }
        }
        идёт = true
        ошибка = nil
        let тело: [String: Any] = ["reason": String(причина.prefix(200)), "password": пароль]
        let былПароль: Bool
        if case .подтверждение(_, let п) = шаг { былПароль = п } else { былПароль = false }
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=account_delete_confirm", тело)
                if A.да(j["ok"]) {
                    завершить()
                    return
                }
                if A.да(j["need_pass"]) && !былПароль {
                    перейтиКоВторому(eGov: false, пароль: true)
                    let текст = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    ошибка = (текст.isEmpty || КабинетСайта.машинныйКод(текст)) ? nil : текст
                    return
                }
                if A.да(j["need_egov"]) {
                    /* acctDelConfirm сайта: otpStepOpen(purpose || "delete", "account") со своими заголовком и
                       подсказкой, после удачи — тот же запрос ещё раз. */
                    if шаг != .подтверждение(eGov: true, пароль: false) {
                        перейтиКоВторому(eGov: true, пароль: false)
                    }
                    let назначение = A.строка(j["purpose"])
                    let запрос = ЗапросEGov(назначение: назначение.isEmpty ? "delete" : назначение, ссылка: "account",
                                            заголовок: ТекстыEgovУдаления.т("adl_egov_t"),
                                            подсказка: ТекстыEgovУдаления.т("adl_egov_h"), после: .оплатить)
                    окноEgov = ОкноEGovУдаления(запрос: запрос)
                    return
                }
                ошибка = текстОшибки(j, запасной: тО("err_generic"))
            } catch {
                ошибка = тО("phc_net")
            }
        }
    }

    /// acctDelDone: сервер закрыл аккаунт и сессию — на телефоне стираем всё, как при выходе (КабинетСайта.выйти).
    private func завершить() {
        пароль = ""
        шаг = .готово
        if let web = WebBridge.shared.webView {
            web.evaluateJavaScript("try{window.webkit.messageHandlers.klikoLogout.postMessage({});}catch(e){};0",
                                   completionHandler: nil)
        }
        ВыходНачисто.стереть()
        if let гость = Config.страницаСайта("cabinet.php?bye=1") {
            WebBridge.shared.webView?.load(URLRequest(url: гость))
        }
        NotificationCenter.default.post(name: ОкнаПриложения.аккаунтУдалён, object: nil)
    }
}

/// Обёртка запроса eGov для .sheet(item:) листа удаления.
private struct ОкноEGovУдаления: Identifiable {
    let запрос: ЗапросEGov
    var id: String { запрос.назначение + ":" + запрос.ссылка }
}

/// Заголовок и подсказка окна eGov при удалении (opts otpStepOpen в acctDelConfirm сайта): русские — дословно сайта.
private enum ТекстыEgovУдаления {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["adl_egov_t": "Подтверждение удаления",
               "adl_egov_h": "Удаление аккаунта подтверждается через eGov — как вывод денег. Проверьте ИИН и номер."],
        "kk": ["adl_egov_t": "Жоюды растау",
               "adl_egov_h": "Аккаунтты жою eGov арқылы расталады — ақша шығару сияқты. ЖСН мен нөмірді тексеріңіз."],
        "en": ["adl_egov_t": "Confirm deletion",
               "adl_egov_h": "Account deletion is confirmed via eGov — like a withdrawal. Check your IIN and phone number."],
        "ar": ["adl_egov_t": "تأكيد الحذف",
               "adl_egov_h": "يُؤكَّد حذف الحساب عبر eGov — مثل سحب الأموال. تحقّق من رقم IIN والهاتف."]
    ]
}

// MARK: - Обращение в поддержку (dataReqSend сайта)

@MainActor
struct ЛистОбращения: View {
    private typealias A = МоиОбъявленияAPI

    let тема: String
    let открыть: (URL) -> Void
    @Environment(\.dismiss) private var закрыть

    @State private var текст = ""
    @State private var идёт = false
    @State private var ошибка: String? = nil
    /// Номер принятого обращения (ответ id).
    @State private var номер: String? = nil
    @FocusState private var вФокусе: Bool

    init(тема: String, открыть: @escaping (URL) -> Void) {
        self.тема = тема
        self.открыть = открыть
    }

    /// Тема только из букв — как в адресах сайта (payment, other, access).
    private var чистаяТема: String {
        let буквы = тема.lowercased().filter { $0.isASCII && $0.isLetter }
        return буквы.isEmpty ? "other" : буквы
    }

    private var подписьТемы: String? {
        switch чистаяТема {
        case "payment", "other", "access": return тО("sup_topic_" + чистаяТема)
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let принятый = номер {
                        принято(принятый)
                    } else {
                        форма
                    }
                }
                .padding(16)
                .мерилоФормы()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(тО("sup_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(тО("close")) { закрыть() }
                        .disabled(идёт)
                }
            }
        }
        /* По высоте формы обращения — без пустоты снизу. */
        .листПоВысоте()
        .interactiveDismissDisabled(идёт)
    }

    private var форма: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let подпись = подписьТемы {
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
            }
            Text(тО("sup_hint"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            TextField(тО("sup_ph"), text: $текст, axis: .vertical)
                .lineLimit(5...12)
                .focused($вФокусе)
                .padding(12)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
            if let сообщение = ошибка {
                Text(сообщение)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                отправить()
            } label: {
                HStack(spacing: 8) {
                    if идёт { ProgressView().tint(Color.white) }
                    Text(тО(идёт ? "sup_sending" : "sup_send"))
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(идёт)
            /* «Написать на сайте» после ошибки убран (владелец: всё нативно) — «Отправить» можно нажать ещё раз. */
        }
    }

    private func принято(_ номер: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(String(format: тО("sup_done"), номер))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if годныйНомер(номер) && NativeRouter.доступна(.обращение(id: номер)) {
                Button {
                    закрыть()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        NativeRouter.shared.цель = .обращение(id: номер)
                    }
                } label: {
                    Text(тО("sup_open"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button(тО("close")) { закрыть() }
                .font(.system(size: 15, weight: .semibold))
                .tint(Theme.акцент)
                .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Номер — как у ссылки ?ticket=<id> (АдресаКабинета): буквы, цифры, дефис, подчёркивание.
    private func годныйНомер(_ н: String) -> Bool {
        н.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    /// dataReqSend: не короче 10 знаков; POST support.php?action=create {topic, text, ref, website, ft} — без csrf.
    private func отправить() {
        guard !идёт else { return }
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard чистый.count >= 10 else {
            ошибка = тО("sup_min")
            return
        }
        вФокусе = false
        идёт = true
        ошибка = nil
        let тело: [String: Any] = ["topic": чистаяТема, "text": чистый, "ref": "", "website": "", "ft": 9999]
        Task { @MainActor in
            defer { идёт = false }
            do {
                let ответ = try await КабинетСайта.вызвать("support.php?action=create", метод: "POST", тело: тело)
                guard let j = ответ.json else {
                    ошибка = тО("sup_err")
                    return
                }
                if A.да(j["ok"]) {
                    let id = A.строка(j["id"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    номер = id.isEmpty ? "—" : id
                } else {
                    let текстОшибки = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    ошибка = (текстОшибки.isEmpty || КабинетСайта.машинныйКод(текстОшибки)) ? тО("sup_err") : текстОшибки
                }
            } catch {
                ошибка = тО("sup_no_conn")
            }
        }
    }
}
