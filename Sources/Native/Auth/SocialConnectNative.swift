import AuthenticationServices
import Foundation
import UIKit

/**
 ПОДКЛЮЧЕНИЕ СОЦСЕТЕЙ ДЛЯ АВТОПОСТИНГА — НАТИВНО, С ОТКАТОМ НА СТРАНИЦУ САЙТА.

 Страница social_connect.php?platform=&do=start требует вход, а ASWebAuthenticationSession ходит с куками Safari, где
 человек не вошёл. Поэтому сначала приложение со своей сессией (fetch страницы сайта под слоем, МоиОбъявленияAPI.отправить
 с csrf) просит одноразовую ссылку: POST /social_connect.php?action=app_link {platform} → {ok:true, url:"https://kliko.kz/
 social_connect.php?platform=..&do=start&ott=..."}. Её открывает ASWebAuthenticationSession (эфемерная, без куков Safari);
 сервер по ott узнаёт человека, проводит OAuth соцсети и возвращает kliko://social_connected?platform=..&ok=1 (или
 &error=...). Потом экран перечитывает social_status.

 Сервер ещё не умеет app_link (404, не JSON, ok:false, чужой адрес) — .наСайт: экран делает прежнее (страница сайта
 поверх). Договор — docs/SERVER_NATIVE_AUTH.md. Одноразовый токен в журнал не пишется.
 */
@MainActor
enum ПодключениеСоцсети {

    enum Итог: Equatable {
        case подключено
        /// Сервер вернул error= (слова уже для человека или общий текст).
        case ошибка(String)
        /// Лист закрыли или уже идёт другое подключение.
        case отменено
        /// Сервер не готов — прежняя страница сайта.
        case наСайт
    }

    private static var занято = false
    /// Сессия и якорь живут, пока открыт лист входа соцсети.
    private static var сессия: ASWebAuthenticationSession? = nil
    private static var якорь: ЯкорьПодключенияСоцсети? = nil

    static func подключить(_ платформа: String, имя: String) async -> Итог {
        guard !занято else { return .отменено }
        занято = true
        defer { занято = false }
        guard let адрес = await одноразоваяСсылка(платформа) else { return .наСайт }
        guard let окно = ключевоеОкно() else { return .наСайт }
        let ответ = await пройти(адрес, окно: окно)
        сессия = nil
        якорь = nil
        switch ответ {
        case .отменено:
            return .отменено
        case .сбой:
            return .ошибка(String(format: т("fail"), имя))
        case .адрес(let возврат):
            return разобрать(возврат, имя: имя)
        }
    }

    /// Текст тоста «Instagram подключён ✓».
    static func текстУспеха(_ имя: String) -> String {
        String(format: т("ok"), имя)
    }

    // MARK: Шаги

    private static func одноразоваяСсылка(_ платформа: String) async -> URL? {
        typealias A = МоиОбъявленияAPI
        guard let j = try? await A.отправить("/social_connect.php?action=app_link", тело: ["platform": платформа],
                                             отКорня: true),
              A.да(j["ok"]) else { return nil }
        guard let адрес = URL(string: A.строка(j["url"])),
              адрес.scheme?.lowercased() == "https",
              let хост = адрес.host?.lowercased(),
              хост == "kliko.kz" || хост == "www.kliko.kz" else { return nil }
        return адрес
    }

    private static func пройти(_ адрес: URL, окно: UIWindow) async -> ОтветЛистаСоцсети {
        await withCheckedContinuation { (п: CheckedContinuation<ОтветЛистаСоцсети, Never>) in
            let ящик = ЯщикОтветаСоцсети(п)
            let лист = ASWebAuthenticationSession(url: адрес, callbackURLScheme: "kliko",
                                                  completionHandler: обработчик(ящик))
            let я = ЯкорьПодключенияСоцсети(окно: окно)
            лист.presentationContextProvider = я
            лист.prefersEphemeralWebBrowserSession = true
            сессия = лист
            якорь = я
            if !лист.start() { ящик.ответить(.сбой) }
        }
    }

    /// Обработчик вне главного актора: система может позвать его с любой нити, ответ — через ящик, один раз.
    nonisolated private static func обработчик(_ ящик: ЯщикОтветаСоцсети) -> @Sendable (URL?, Error?) -> Void {
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

    /// kliko://social_connected?platform=..&ok=1 или &error=...
    private static func разобрать(_ возврат: URL, имя: String) -> Итог {
        let общий = String(format: т("fail"), имя)
        guard возврат.host?.lowercased() == "social_connected",
              let части = URLComponents(url: возврат, resolvingAgainstBaseURL: false) else { return .ошибка(общий) }
        let поля = части.queryItems ?? []
        let ok = поля.first(where: { $0.name == "ok" })?.value ?? ""
        if ok == "1" || ok == "true" { return .подключено }
        let слова = (поля.first(where: { $0.name == "error" })?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if слова == "cancel" || слова == "cancelled" || слова == "access_denied" { return .отменено }
        if слова.isEmpty || КабинетСайта.машинныйКод(слова) { return .ошибка(общий) }
        return .ошибка(слова)
    }

    private static func ключевоеОкно() -> UIWindow? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return окна.first(where: { $0.isKeyWindow }) ?? окна.first
    }

    // MARK: Тексты

    private static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["ok": "%@ подключён ✓", "fail": "Не удалось подключить %@"],
        "kk": ["ok": "%@ қосылды ✓", "fail": "%@ қосу мүмкін болмады"],
        "en": ["ok": "%@ connected ✓", "fail": "Could not connect %@"],
        "ar": ["ok": "تم ربط %@ ✓", "fail": "تعذّر ربط %@"]
    ]
}

/// Что вернул лист входа соцсети.
enum ОтветЛистаСоцсети: Sendable {
    case адрес(URL)
    case отменено
    case сбой
}

/// Продолжение, которое отвечает ровно один раз (обработчик сессии и неудачный start не столкнутся).
final class ЯщикОтветаСоцсети: @unchecked Sendable {
    private let замок = NSLock()
    private var продолжение: CheckedContinuation<ОтветЛистаСоцсети, Never>?

    init(_ продолжение: CheckedContinuation<ОтветЛистаСоцсети, Never>) {
        self.продолжение = продолжение
    }

    func ответить(_ ответ: ОтветЛистаСоцсети) {
        замок.lock()
        let п = продолжение
        продолжение = nil
        замок.unlock()
        п?.resume(returning: ответ)
    }
}

/// Окно, над которым встаёт лист входа соцсети.
final class ЯкорьПодключенияСоцсети: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let окно: UIWindow

    init(окно: UIWindow) {
        self.окно = окно
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        окно
    }
}
