import AuthenticationServices
import Foundation
import SwiftUI
import UIKit

/**
 «СВОЙ ИИ» — ВХОД ЧЕРЕЗ OPENROUTER ИЗ ПРИЛОЖЕНИЯ (ultra-site 14.10.2026, «Свой ИИ» во всех местах, пункт 5; рубильники
 сервера own_ai, own_ai_openrouter, own_ai_openrouter_app).

 1. Кнопка «Войти через OpenRouter» на экране «Свой ИИ» — только при own_ai.login_app == true (старый сервер поля не шлёт —
    кнопки нет, всё как раньше: ключ вручную).
 2. POST cabinet.php?action=own_ai_or_start {csrf, app:1} тем же транспортом, что прочие own_ai_* (СвойИИAPI: сессия
    кабинета) → {ok:true, url, app:true, return:"kliko://own-ai", ttl:600}. Без app:true в ответе (сервер не понял app) —
    лист не открываем: возврат ушёл бы на страницу кабинета сайта, а не в приложение. need_premium (в приложении с
    app_store:true) — своя фраза и блок Premium с покупкой App Store, как у прочих дверей.
 3. url открывает эфемерный ASWebAuthenticationSession со схемой возврата kliko: куки Safari не нужны, человека сервер
    узнаёт по одноразовой метке state (10 минут). OpenRouter возвращает на сайт, сайт сохраняет ключ и отвечает 302 на
    kliko://own-ai?ok=1 или kliko://own-ai?ok=0 — других данных в адресе нет.
 4. После возврата — own_ai_state заново; «подключено» говорим только тогда, когда это подтвердил сервер (connected).
 Возврат kliko://own-ai может прийти и мимо листа (ссылка из Safari, где человек начал вход на сайте): SceneDelegate
 отдаёт его сюда (перехватить) — перечитываем состояние и открываем экран «Свой ИИ» с итогом. Адрес kliko:// может
 вызвать кто угодно, поэтому ok=1 сам по себе ничего не значит: итог — по ответу сервера.
 Метка и ссылка в журнал не пишутся.
 */
@MainActor
enum ВходOpenRouterСвоегоИИ {

    enum Итог {
        case готово(ИтогВходаOpenRouter)
        /// Лист закрыли или уже идёт другой вход — ничего не показываем.
        case отменено
        /// own_ai_or_start отказал (Premium, сессия, сеть) — экран разбирает как прочие действия.
        case отказ(СвойИИAPI.Ответ)
    }

    private static var занято = false
    /// Сессия и якорь живут, пока открыт лист входа OpenRouter.
    private static var сессия: ASWebAuthenticationSession? = nil
    private static var якорь: ЯкорьВходаOpenRouter? = nil

    // MARK: Вход по кнопке

    static func войти() async -> Итог {
        guard !занято else { return .отменено }
        занято = true
        defer { занято = false }
        let ответ = await СвойИИAPI.выполнить("own_ai_or_start", ["app": 1])
        guard case .готово(let j) = ответ else { return .отказ(ответ) }
        typealias A = МоиОбъявленияAPI
        guard A.да(j["app"]), let адрес = надёжныйАдрес(A.строка(j["url"])) else {
            return .готово(ИтогВходаOpenRouter(текст: т("oair_old"), хорошо: false))
        }
        guard let окно = ключевоеОкно() else {
            return .готово(ИтогВходаOpenRouter(текст: т("oair_fail"), хорошо: false))
        }
        let лист = await пройти(адрес, окно: окно)
        сессия = nil
        якорь = nil
        switch лист {
        case .отменено:
            return .отменено
        case .сбой:
            return .готово(ИтогВходаOpenRouter(текст: т("oair_fail"), хорошо: false))
        case .адрес(let возврат):
            guard этоВозврат(возврат) else {
                return .готово(ИтогВходаOpenRouter(текст: т("oair_fail"), хорошо: false))
            }
            let итог = await итогВозврата(удача(возврат))
            return .готово(итог)
        }
    }

    // MARK: Возврат мимо листа (Safari)

    /// kliko://own-ai… пришёл в SceneDelegate — забираем себе (true), прочие адреса — нет (false).
    static func перехватить(_ адрес: URL) -> Bool {
        guard этоВозврат(адрес) else { return false }
        let ok = удача(адрес)
        Task { @MainActor in
            /* Холодный старт: ждём, пока уйдёт заставка и замок Face ID, — окно поверх замка его бы обошло. */
            let можно = await ВходOpenRouterСвоегоИИ.дождатьсяЭкрана()
            let итог = await ВходOpenRouterСвоегоИИ.итогВозврата(ok)
            let модель = СвойИИМодель.shared
            guard можно, модель.вкл else { return }
            модель.сообщитьИтогВхода(итог)
            if модель.открытоЭкранов == 0 { ОкноСвоегоИИ.открыть() }
        }
        return true
    }

    // MARK: Разбор

    /// kliko://own-ai (и own_ai — так звал договор раньше); kliko:///own-ai — тоже.
    static func этоВозврат(_ адрес: URL) -> Bool {
        guard адрес.scheme?.lowercased() == Config.scheme else { return false }
        let имена: Set<String> = ["own-ai", "own_ai"]
        if let хост = адрес.host?.lowercased(), !хост.isEmpty { return имена.contains(хост) }
        let путь = адрес.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return имена.contains(путь)
    }

    /// ok=1 — сервер сохранил ключ, ok=0 — нет, без поля — nil (судим по состоянию).
    static func удача(_ адрес: URL) -> Bool? {
        let поля = URLComponents(url: адрес, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let значение = (поля.first(where: { $0.name == "ok" })?.value ?? "").lowercased()
        if ["1", "true", "yes"].contains(значение) { return true }
        if ["0", "false", "no"].contains(значение) { return false }
        return nil
    }

    /// После возврата: own_ai_state заново. ok=0 — неудача; иначе удача только при connected от сервера.
    static func итогВозврата(_ ok: Bool?) async -> ИтогВходаOpenRouter {
        let модель = СвойИИМодель.shared
        await модель.обновить()
        if ok == false { return ИтогВходаOpenRouter(текст: т("oair_fail"), хорошо: false) }
        if модель.неЗагрузилось { return ИтогВходаOpenRouter(текст: СвойИИText.т("oai_load_fail"), хорошо: false) }
        if модель.состояние?.подключён == true {
            return ИтогВходаOpenRouter(текст: т("oair_ok"), хорошо: true)
        }
        return ИтогВходаOpenRouter(текст: т("oair_fail"), хорошо: false)
    }

    /// Адрес из own_ai_or_start: только https, только OpenRouter или наш сайт (сайт может вести через свою страницу).
    private static func надёжныйАдрес(_ строка: String) -> URL? {
        guard let адрес = URL(string: строка.trimmingCharacters(in: .whitespacesAndNewlines)),
              адрес.scheme?.lowercased() == "https",
              let хост = адрес.host?.lowercased() else { return nil }
        let свои: Set<String> = ["openrouter.ai", "kliko.kz", "www.kliko.kz"]
        guard свои.contains(хост) || хост.hasSuffix(".openrouter.ai") else { return nil }
        return адрес
    }

    // MARK: Лист

    private static func пройти(_ адрес: URL, окно: UIWindow) async -> ОтветЛистаOpenRouter {
        await withCheckedContinuation { (п: CheckedContinuation<ОтветЛистаOpenRouter, Never>) in
            let ящик = ЯщикОтветаOpenRouter(п)
            let лист = ASWebAuthenticationSession(url: адрес, callbackURLScheme: Config.scheme,
                                                  completionHandler: обработчик(ящик))
            let я = ЯкорьВходаOpenRouter(окно: окно)
            лист.presentationContextProvider = я
            /* Эфемерный: человека сервер узнаёт по метке state, куки Safari не нужны и не остаются. */
            лист.prefersEphemeralWebBrowserSession = true
            сессия = лист
            якорь = я
            if !лист.start() { ящик.ответить(.сбой) }
        }
    }

    /// Обработчик вне главного актора: система может позвать его с любой нити, ответ — через ящик, один раз.
    nonisolated private static func обработчик(_ ящик: ЯщикОтветаOpenRouter) -> @Sendable (URL?, Error?) -> Void {
        return { возврат, ошибка in
            if let ошибка {
                let отмена = (ошибка as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                ящик.ответить(отмена ? .отменено : .сбой)
            } else if let возврат {
                ящик.ответить(.адрес(возврат))
            } else {
                ящик.ответить(.сбой)
            }
        }
    }

    /// Заставка ушла, замка Face ID нет, приложение активно; до 30 с, иначе false — окно не показываем.
    private static func дождатьсяЭкрана() async -> Bool {
        for _ in 0..<60 {
            let замок = AppLock.shared
            let подЗамком = замок.enabled && (замок.locked || замок.cover)
            if WebBridge.shared.splashDone && !подЗамком && UIApplication.shared.applicationState == .active {
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private static func ключевоеОкно() -> UIWindow? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return окна.first(where: { $0.isKeyWindow }) ?? окна.first
    }

    private static func т(_ ключ: String) -> String { СвойИИВходText.т(ключ) }
}

/// Итог входа через OpenRouter для экрана «Свой ИИ»: текст и тон заметки.
struct ИтогВходаOpenRouter: Identifiable, Equatable {
    let id = UUID()
    let текст: String
    let хорошо: Bool

    init(текст: String, хорошо: Bool) {
        self.текст = текст
        self.хорошо = хорошо
    }
}

/// Что вернул лист входа OpenRouter.
enum ОтветЛистаOpenRouter: Sendable {
    case адрес(URL)
    case отменено
    case сбой
}

/// Продолжение, которое отвечает ровно один раз (обработчик сессии и неудачный start не столкнутся).
final class ЯщикОтветаOpenRouter: @unchecked Sendable {
    private let замок = NSLock()
    private var продолжение: CheckedContinuation<ОтветЛистаOpenRouter, Never>?

    init(_ продолжение: CheckedContinuation<ОтветЛистаOpenRouter, Never>) {
        self.продолжение = продолжение
    }

    func ответить(_ ответ: ОтветЛистаOpenRouter) {
        замок.lock()
        let п = продолжение
        продолжение = nil
        замок.unlock()
        п?.resume(returning: ответ)
    }
}

/// Окно, над которым встаёт лист входа OpenRouter.
final class ЯкорьВходаOpenRouter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let окно: UIWindow

    init(окно: UIWindow) {
        self.окно = окно
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        окно
    }
}

// MARK: - Пометка «через ваш ИИ»

/**
 Маленькая пометка «через ваш ИИ» под ответом ИИ-функции — когда в ответе сервера own_ai_run (ОтветСвоегоИИ.своим).
 С 14.10.2026 поле приходит у consult, ai_replies, ai_replies_dm, ai_service, photo_search, shot_read, ai_style,
 ai_import, ai_job_chunk, kp_generate, ai_resume, translate и распознавания реквизитов; нет поля — пометки нет.
 */
struct МеткаСвоегоИИ: View {
    let видна: Bool

    init(видна: Bool) {
        self.видна = видна
    }

    /// По ответу сервера: own_ai_run есть — пометка видна.
    init(ответ j: [String: Any]) {
        self.видна = ОтветСвоегоИИ.своим(j)
    }

    var body: some View {
        if видна {
            Label {
                Text(СвойИИText.т("oai_via"))
            } icon: {
                Image(systemName: "key")
                    .accessibilityHidden(true)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
            .accessibilityElement(children: .combine)
        }
    }
}
