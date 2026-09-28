import SwiftUI
import UIKit

/**
 eGov НАТИВНО — ВХОДНАЯ ТОЧКА (владелец: «флоу eGov так же сделай в SwiftUI»).

 Раньше eGov был страницами сайта в листе WKWebView (ОкноEgov: cabinet.php?egov=1, ?go=verify, ?egov_confirm=1) и
 узнавал конец чтением переменных страницы. Теперь всё своё — SwiftUI (ЭкранПотокаEgov): форма, сверка, отсчёт, опрос
 тех же запросов сайта, успех и ошибка. Чужая страница осталась одна — remote.biometric.kz (код из SMS и лицо), в
 компактном листе поверх потока; её конец узнаёт опрос kliko, а не страница.

 Вызовы:
   · ПотокEgov.верификация(готово:)                — «Пройти верификацию» (requestVerification → bioKycOpen);
   · ПотокEgov.вход(телефон:готово:)               — гость: вход, регистрация, восстановление по ИИН (egovAuthOpen);
   · ПотокEgov.подтверждениеВхода(готово:)         — защита входа после пароля или Apple (egovLoginConfirmOpen);
   · ПотокEgov.шаг(назначение:ссылка:заголовок:подсказка:готово:) — otpStepOpen: деньги сделки, печать, вывод, гарантия,
     sec_login off, удаление аккаунта;
   · ЛистПотокаEgov(...)                            — то же для .sheet вызывающего экрана.
 ОкноEgov.открыть / открытьПоток идут сюда сами, пока нативныйEgov = true; выключить — вернётся прежний лист сайта.
 */
@MainActor
enum ПотокEgov {
    /// Рубильник: false — прежний путь, страница сайта в листе (ОкноEgov).
    static let нативныйEgov = true

    private static weak var показан: UIViewController?
    private static var открывается = false

    // MARK: - Вызовы

    static func верификация(сделка: String = "", готово: (() -> Void)? = nil, закрыто: (() -> Void)? = nil) {
        открыть(.верификация(сделка: сделка), готово: готово, закрыто: закрыто)
    }

    static func вход(телефон: String = "", готово: (() -> Void)? = nil, закрыто: (() -> Void)? = nil) {
        открыть(.вход(телефон: телефон), готово: готово, закрыто: закрыто)
    }

    static func подтверждениеВхода(готово: (() -> Void)? = nil, закрыто: (() -> Void)? = nil) {
        открыть(.подтверждениеВхода, готово: готово, закрыто: закрыто)
    }

    /// Шаг опасного действия: готово — сервер подтвердил (otp_step_check verified), повторите исходное действие.
    static func шаг(назначение: String, ссылка: String, заголовок: String = "", подсказка: String = "",
                    готово: @escaping () -> Void, закрыто: (() -> Void)? = nil) {
        открыть(.шаг(назначение: назначение, ссылка: ссылка, заголовок: заголовок, подсказка: подсказка),
                готово: готово, закрыто: закрыто)
    }

    /// Поток поверх верхнего экрана. готово — после удачи и того, что за ней делает сайт; закрыто — лист закрылся
    /// чем бы то ни было.
    static func открыть(_ вид: ВидПотокаEgov, готово: (() -> Void)? = nil, закрыто: (() -> Void)? = nil) {
        guard показан == nil, !открывается else { return }
        открывается = true
        Task { @MainActor in
            defer { ПотокEgov.открывается = false }
            /* Вызывающий мог только что закрыть свой лист или алерт: ждём, пока UIKit его уберёт. */
            try? await Task.sleep(nanoseconds: 300_000_000)
            for _ in 0..<12 {
                if let верх = ПотокEgov.верхний() {
                    ПотокEgov.показать(вид, над: верх, готово: готово, закрыто: закрыто)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    // MARK: - Адрес сайта → вид потока

    /**
     Кнопки и ссылки приложения всё ещё говорят адресами сайта (ОкноEgov.этоEgov): ?egov_confirm=1 — подтверждение входа,
     ?egov=1 — вход гостя, ?go=verify и ?go=egov — верификация (return_deal — объявление, куда вернуться). Прочее — nil,
     и ОкноEgov открывает страницу сайта, как раньше.
     */
    nonisolated static func вид(адреса адрес: URL) -> ВидПотокаEgov? {
        guard ОкноEgov.этоEgov(адрес),
              let части = URLComponents(url: адрес.absoluteURL, resolvingAgainstBaseURL: false) else { return nil }
        let параметры = части.queryItems ?? []
        func есть(_ имя: String, _ значения: [String]) -> Bool {
            параметры.contains { $0.name == имя && значения.contains(($0.value ?? "").lowercased()) }
        }
        if есть("egov_confirm", ["1"]) { return .подтверждениеВхода }
        if есть("go", ["verify", "egov"]) {
            let сделка = параметры.first(where: { $0.name == "return_deal" })?.value ?? ""
            return .верификация(сделка: сделка)
        }
        if есть("egov", ["1"]) { return .вход(телефон: "") }
        return nil
    }

    // MARK: - Показ

    private static func верхний() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first,
              var верх = окно.rootViewController else { return nil }
        while let следующий = верх.presentedViewController {
            if следующий.isBeingDismissed || следующий.isBeingPresented { return nil }
            верх = следующий
        }
        if верх.isBeingDismissed { return nil }
        return верх
    }

    private static func показать(_ вид: ВидПотокаEgov, над верх: UIViewController, готово: (() -> Void)?,
                                 закрыто: (() -> Void)?) {
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let экран = ЭкранПотокаEgov(вид: вид, конец: { [weak хост] удача in
            let лист: UIViewController? = хост
            Task { @MainActor in
                лист?.dismiss(animated: true)
                ПотокEgov.показан = nil
                if удача {
                    await ПотокEgov.послеУдачи(вид)
                    готово?()
                }
                /* Чем бы ни кончилось — общее состояние входа сверяется с кабинетом (СессияПриложения). */
                СессияПриложения.shared.запросить(кабинет: true)
                закрыто?()
            }
        })
        хост.rootView = AnyView(экран)
        хост.modalPresentationStyle = .pageSheet
        /* Смахнуть посреди проверки — потерять её: закрывается кнопкой. */
        хост.isModalInPresentation = true
        if let лист = хост.sheetPresentationController {
            лист.detents = [.large()]
            лист.prefersGrabberVisible = true
        }
        показан = хост
        верх.present(хост, animated: true)
    }

    // MARK: - После удачи — то, что сайт делает дальше

    /**
     Вход и подтверждение входа: сервер открыл сессию, сайт перезагружает страницу (afterRegUrl или reload) — здесь
     ulx_me_id и перезагрузка страницы под слоем, как после входа паролем. Верификация — bioAfterOk: return_deal ведёт на
     объявление, иначе перезагрузка кабинета. Шаг — ничего: исходное действие повторяет вызывающий.
     */
    static func послеУдачи(_ вид: ВидПотокаEgov) async {
        switch вид {
        case .шаг:
            return
        case .вход, .подтверждениеВхода:
            ИнбоксAPI.забыть()
            МоиОбъявленияAPI.забыть()
            let uid = (try? await КабинетСайта.состояние())?.uid ?? ""
            await КабинетСайта.послеВхода(uid: uid)
        case .верификация(let сделка):
            if сделка.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil,
               let адрес = Config.url("/marketplace.php?item=" + сделка) {
                WebBridge.shared.pendingURL = адрес
            } else {
                let uid = (try? await КабинетСайта.состояние())?.uid ?? ""
                await КабинетСайта.послеВхода(uid: uid)
            }
        }
        NotificationCenter.default.post(name: ОкноEgov.завершено, object: nil)
    }
}

/**
 Поток eGov для .sheet вызывающего экрана (вместо ОкноEGov в сделках, кошельке, печати, аренде, настройках): готово —
 после удачи (для шага — повторить действие), закрыть — закрыли без удачи.
 */
struct ЛистПотокаEgov: View {
    let вид: ВидПотокаEgov
    let готово: () -> Void
    let закрыть: () -> Void

    init(вид: ВидПотокаEgov, готово: @escaping () -> Void, закрыть: @escaping () -> Void) {
        self.вид = вид
        self.готово = готово
        self.закрыть = закрыть
    }

    /// otpStepOpen(purpose, ref, onOk, {title, hint}).
    init(назначение: String, ссылка: String, заголовок: String = "", подсказка: String = "",
         готово: @escaping () -> Void, закрыть: @escaping () -> Void) {
        self.init(вид: .шаг(назначение: назначение, ссылка: ссылка, заголовок: заголовок, подсказка: подсказка),
                  готово: готово, закрыть: закрыть)
    }

    var body: some View {
        ЭкранПотокаEgov(вид: вид, конец: { удача in
            guard удача else {
                закрыть()
                return
            }
            let вид = self.вид
            let готово = self.готово
            Task { @MainActor in
                await ПотокEgov.послеУдачи(вид)
                готово()
            }
        })
    }
}
