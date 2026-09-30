import SwiftUI
import UIKit

/**
 АДРЕСА САЙТА, КОТОРЫЕ ТЕПЕРЬ ОТКРЫВАЮТСЯ СВОИМИ ОКНАМИ (этап 50, владелец: «всё приложение нативным»).

 Нативные экраны открывают адреса через одно корневое «открыть» (RootWebView → WebBridge.перейти: свой экран или окно
 «недоступно», страницы сайта на экране больше нет). Здесь, как у ОкноEgov, адрес перехватывается раньше и показывается своим окном поверх того экрана, где его
 нажали (лист над верхним контроллером — встаёт и поверх другого листа или мастера подачи):
   · /kz/<язык>/help[#якорь], статьи справки help/<раздел> и help?…, soglashenie, oferta, privacy, oplata, tarify (и
     *.php) — ОкноСтраницСайта: статья страницы сайта своими блоками (подвал, «Справочный центр» кабинета, ссылки из
     статей, вопросы-ответы);
   · cabinet?go=import | go=aiimport — перенос объявлений по ссылке и через Kliko AI (МастерИмпорта; слайд «Перенесите
     объявления» главной, «Перенести по ссылке» на старте подачи);
   · cabinet?s=analytics | go=analytics — «Аналитика магазина»; cabinet?s=kp — «Предложения покупателям»;
   · cabinet?add=jobs — «Работа»: выбор «Резюме / Вакансия» и мастер (МастерРезюме).
 Остальное идёт прежним путём. Выключить — НативныеОкна.включено = false.
 */
@MainActor
enum НативныеОкна {
    static let включено = true

    enum Цель {
        case страница(СтраницаСайта)
        case импорт(СпособИмпорта)
        case аналитика
        case кп
        case работа(вид: ВидРаботы?, номер: String?)
    }

    /// Для корневого «открыть»: свой экран — окно поверх, true; иначе false.
    static func перехватить(_ адрес: URL) -> Bool {
        guard включено, let цель = распознать(адрес) else { return false }
        return показать(цель)
    }

    static func распознать(_ адрес: URL) -> Цель? {
        if let страница = СтраницаСайта.из(адрес) { return .страница(страница) }
        let полный = адрес.absoluteURL
        guard Config.deepLink(полный) != nil,
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false),
              (части.fragment ?? "").isEmpty,
              части.path.range(of: "^(/[a-z]{2}/[a-z]{2})?/cabinet(\\.php)?/?$", options: .regularExpression) != nil
        else { return nil }
        let параметры = (части.queryItems ?? []).filter { !$0.name.lowercased().hasPrefix("utm_") }
        guard параметры.count == 1, let п = параметры.first else { return nil }
        let значение = (п.value ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        switch (п.name, значение) {
        case ("go", "import"):
            guard Config.нативнаяПодача else { return nil }
            return .импорт(.ссылка)
        case ("go", "aiimport"):
            guard Config.нативнаяПодача else { return nil }
            return .импорт(.каталог)
        case ("s", "analytics"), ("go", "analytics"): return .аналитика
        case ("s", "kp"), ("go", "kp"): return .кп
        case ("add", "jobs"): return .работа(вид: nil, номер: nil)
        default: return nil
        }
    }

    // MARK: - Показ

    /// Окно поверх верхнего контроллера. false — показать некуда (вызывающий откроет адрес прежним путём).
    @discardableResult
    static func показать(_ цель: Цель) -> Bool {
        Task { @MainActor in
            /* Вызывающий мог только что закрыть свой лист (мастер подачи закрывается перед переходом): ждём UIKit. */
            for _ in 0..<12 {
                if let верх = верхний() {
                    представить(цель, над: верх)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return true
    }

    private static func представить(_ цель: Цель, над верх: UIViewController) {
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let закрыть: () -> Void = { [weak хост] in
            хост?.dismiss(animated: true)
        }
        let дальше: (URL) -> Void = { [weak хост] адрес in
            let лист: UIViewController? = хост
            лист?.dismiss(animated: true)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                НативныеОкна.открытьДальше(адрес)
            }
        }
        хост.rootView = AnyView(корень(цель, дальше: дальше, закрыть: закрыть))
        хост.modalPresentationStyle = .pageSheet
        switch цель {
        case .импорт, .работа:
            /* Смахнуть вниз посреди разбора или заполнения — потерять введённое: закрывается кнопкой. */
            хост.isModalInPresentation = true
        default:
            break
        }
        if let лист = хост.sheetPresentationController {
            лист.detents = [.large()]
            лист.prefersGrabberVisible = true
        }
        верх.present(хост, animated: true)
    }

    @ViewBuilder
    private static func корень(_ цель: Цель, дальше: @escaping (URL) -> Void, закрыть: @escaping () -> Void) -> some View {
        switch цель {
        case .страница(let страница):
            ОкноСтраницСайта(первая: страница, открыть: дальше, написать: {
                закрыть()
                /* Слоя вкладок нет — форма поверх верхнего экрана, а не пустое нажатие. */
                ПоддержкаПоверх.показать(тема: "other", задержка: 500_000_000)
            }, закрыть: закрыть)
        case .импорт(let способ):
            МастерИмпорта(способ: способ, открыть: дальше, закрыть: закрыть)
        case .аналитика:
            ОкноБизнесРаздела(закрыть: закрыть) {
                ЭкранАналитики(открыть: дальше)
            }
        case .кп:
            ОкноБизнесРаздела(закрыть: закрыть) {
                ЭкранКП(открыть: дальше)
            }
        case .работа(let вид, let номер):
            МастерРезюме(вид: вид, номер: номер, открыть: дальше, закрыть: закрыть)
        }
    }

    /// Адрес из окна — после его закрытия: eGov, другое своё окно, нативный экран вкладок; своего нет — окно
    /// «недоступно» (WebBridge.перейти), не страница сайта.
    static func открытьДальше(_ адрес: URL) {
        if ОкноEgov.перехватить(адрес) { return }
        if перехватить(адрес) { return }
        WebBridge.shared.открытьСнаружи(адрес)
    }

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
}

/// Бизнес-раздел отдельным окном (по ссылке ?s=analytics, ?s=kp): свой стек и «Закрыть».
struct ОкноБизнесРаздела<Содержимое: View>: View {
    let закрыть: () -> Void
    let содержимое: Содержимое

    init(закрыть: @escaping () -> Void, @ViewBuilder содержимое: () -> Содержимое) {
        self.закрыть = закрыть
        self.содержимое = содержимое()
    }

    var body: some View {
        NavigationStack {
            содержимое
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(БизнесText.т("close")) { закрыть() }
                    }
                }
        }
        .tint(Theme.акцент)
    }
}
