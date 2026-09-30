import AVFoundation
import SwiftUI
import UIKit

/**
 ВХОД НА КОМПЬЮТЕРЕ ПО QR (владелец 29.09.2026: камера iPhone открывала код «Войти по QR» в приложении, а приложение
 отвечало «Страница недоступна в приложении»). 30.09.2026 — под механизм самого сайта (свой серверный патч не ставится).

 Код на экране входа сайта — адрес https://kliko.kz/qr/<код> (код — 24 знака base64url, живёт 120 с; на всякий случай
 принимается и путь с языком /kz/<язык>/qr/<код>). Универсальная ссылка приходит в WebBridge.открытьСнаружи / перейти —
 там её забирает ВходПоQR.перехватить раньше всех прочих разборов и показывает своё окно:
   1. КабинетСайта.состояние — вошёл ли человек и токен кабинета (KlikoCsrf = csrf_cab сессии kliko_cab). Не вошёл —
      «Войдите, чтобы подтвердить вход»: свой ЭкранВхода (ВходПоверх), после входа окно открывается снова с тем же кодом.
   2. POST /qr.php?action=info {csrf, i} — какое устройство просит вход (dev, city, ip, time, len). Точки может не быть
      (404, неизвестное действие, сбой) — окно всё равно спрашивает, общей строкой «Компьютер запросил вход в ваш аккаунт».
   3. «Подтвердить вход» — POST /qr.php?action=approve {csrf, i}; «Отмена» — action=deny с тем же телом, окно
      закрывается сразу. Без нажатия ничего не подтверждается. Ответ «csrf» — токен перечитывается, запрос один раз снова.

 🔴 Сервер принимает только сессию куки kliko_cab (Bearer — нет) и User-Agent с меткой KlikoApp. Поэтому все три запроса —
 КабинетСайта.вызвать(толькоСтраницей: true): fetch изнутри страницы сайта под слоем (WKWebView с
 applicationNameForUserAgent «KlikoApp/<версия>», куки WebKit, настоящие Origin и Referer), мимо URLSession-транспорта.

 Второй вход — «Сканировать QR для входа» в «Кабинет → Безопасность» (СтрокаСканераВхода): тот же сканер, что у встречи
 сделки (КамераQRСделки), и то же окно.
 */
@MainActor
enum ВходПоQR {
    /// Последний перехваченный код: одна ссылка, пришедшая дважды (холодный старт и continue), не ставит два окна.
    private static var последний: (токен: String, когда: Date)? = nil

    /// Код из адреса «Войти по QR» (…/qr/<24 знака base64url>, с /kz/<язык> в начале или без) или nil.
    static func токен(из адрес: URL) -> String? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        /* Код различает регистр — путь целиком не приводим к нижнему. */
        var куски = части.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0) }
        if куски.count == 4, куски[0].lowercased() == "kz", куски[1].count == 2 {
            куски.removeFirst(2)
        }
        guard куски.count == 2, куски[0].lowercased() == "qr" else { return nil }
        let код = куски[1]
        guard код.range(of: "^[A-Za-z0-9_-]{24}$", options: .regularExpression) != nil else { return nil }
        return код
    }

    /// Адрес нашего домена с кодом входа — своё окно; true — забрали.
    static func перехватить(_ адрес: URL) -> Bool {
        guard Config.deepLink(адрес.absoluteURL) != nil, let код = токен(из: адрес) else { return false }
        let сейчас = Date()
        if let было = последний, было.токен == код, сейчас.timeIntervalSince(было.когда) < 3 { return true }
        последний = (код, сейчас)
        показать(токен: код)
        return true
    }

    /// Окно «Войти на другом устройстве?». Холодный старт — ждём, пока уйдёт заставка и появится верхний экран (до 10 с).
    static func показать(токен: String) {
        Task { @MainActor in
            for _ in 0..<40 {
                if WebBridge.shared.splashDone && ПоверхВсего.верхний() != nil { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            ПоверхВсего.показать(большой: false) { закрыть in
                ОкноВходаПоQR(токен: токен, закрыть: закрыть)
            }
        }
    }

    /// Сканер кода «Войти по QR» — из «Кабинет → Безопасность».
    static func сканировать() {
        ПоверхВсего.показать(большой: true) { закрыть in
            СканерВходаПоQR(закрыть: закрыть)
        }
    }

    /**
     POST /qr.php?action=<действие> {csrf, i} — только страницей сайта (кука kliko_cab и User-Agent с KlikoApp).
     Без JSON: 429 — «rate», 404 — «off» (действия или всей точки нет), 405 — «method».
     */
    static func запрос(_ действие: String, код: String, csrf: String) async throws -> [String: Any] {
        let тело: [String: Any] = ["csrf": csrf, "i": код]
        let ответ = try await КабинетСайта.вызвать("/qr.php?action=" + действие, метод: "POST", тело: тело,
                                                   отКорня: true, толькоСтраницей: true)
        if let json = ответ.json { return json }
        switch ответ.код {
        case 429: return ["ok": false, "error": "rate"]
        case 404: return ["ok": false, "error": "off"]
        case 405: return ["ok": false, "error": "method"]
        default: throw КабинетСайта.Сбой.приложение
        }
    }

    /// ok ответа: true, 1 или «1».
    static func да(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue != 0 }
        if let текст = значение as? String { return текст == "1" || текст == "true" }
        return false
    }

    /// Код ошибки ответа: для «exp» — уточнение why, если сервер его прислал (expired | used | denied | approved).
    static func кодОшибки(_ j: [String: Any]) -> String {
        let ошибка = ((j["error"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if ошибка == "exp" {
            let почему = ((j["why"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if ["expired", "used", "denied", "approved"].contains(почему) { return почему }
        }
        return ошибка
    }

    /// Текст ошибки сервера и можно ли повторить.
    static func ошибка(_ код: String) -> (текст: String, повтор: Bool) {
        switch код {
        case "exp": return (ВходПоQRText.т("e_exp"), false)
        case "expired": return (ВходПоQRText.т("e_expired"), false)
        case "used": return (ВходПоQRText.т("e_used"), false)
        case "denied": return (ВходПоQRText.т("e_denied"), false)
        case "approved": return (ВходПоQRText.т("e_approved"), false)
        case "rate": return (ВходПоQRText.т("e_rate"), true)
        case "bad": return (ВходПоQRText.т("e_bad"), false)
        case "imp": return (ВходПоQRText.т("e_imp"), false)
        case "app": return (ВходПоQRText.т("e_ua"), false)
        case "off": return (ВходПоQRText.т("e_off"), false)
        default: return (ВходПоQRText.т("e_app"), true)
        }
    }

    /// Сбой транспорта: нет связи — «Нет соединения», прочее — «Не получилось».
    static func сбой(_ ошибка: Error) -> String {
        (ошибка as? КабинетСайта.Сбой) == .сеть ? ВходПоQRText.т("e_net") : ВходПоQRText.т("e_app")
    }
}

/// Что сервер сказал об устройстве, которое просит вход (action=info), и чей аккаунт. Пусто — общая строка.
struct СведенияВходаПоQR: Equatable {
    var устройство: String = ""
    var город: String = ""
    var ip: String = ""
    var когда: String = ""
    /// len — длина сеанса на компьютере в секундах (1800 или 43200); 0 — не сказали.
    var сеанс: Int = 0
    var аккаунт: String = ""

    /// Без info — только аккаунт из страницы кабинета.
    init(аккаунт: String) {
        self.аккаунт = аккаунт
    }

    init(_ j: [String: Any], аккаунт: String) {
        устройство = Self.строка(j["dev"])
        город = Self.строка(j["city"])
        ip = Self.строка(j["ip"])
        когда = Self.строка(j["time"])
        if let число = j["len"] as? NSNumber {
            сеанс = число.intValue
        } else if let текст = j["len"] as? String {
            сеанс = Int(текст) ?? 0
        }
        self.аккаунт = аккаунт
    }

    private static func строка(_ значение: Any?) -> String {
        ((значение as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Сервер рассказал об устройстве — можно показывать «По QR-коду просят войти… на этом устройстве:».
    var есть: Bool { !устройство.isEmpty || !город.isEmpty || !ip.isEmpty }

    /// «30 мин» / «12 ч».
    private var длинаСеанса: String {
        guard сеанс > 0 else { return "" }
        if сеанс >= 3600 && сеанс % 3600 == 0 {
            return ВходПоQRText.т("u_h").replacingOccurrences(of: "{n}", with: String(сеанс / 3600))
        }
        return ВходПоQRText.т("u_min").replacingOccurrences(of: "{n}", with: String(max(1, сеанс / 60)))
    }

    /// Строки карточки: подпись и значение, пустые — прочь.
    var строки: [(String, String)] {
        let все: [(String, String)] = [
            (ВходПоQRText.т("dev"), устройство),
            (ВходПоQRText.т("city"), город),
            (ВходПоQRText.т("ip"), ip),
            (ВходПоQRText.т("when"), когда),
            (ВходПоQRText.т("sess"), длинаСеанса),
            (ВходПоQRText.т("acc"), аккаунт)
        ]
        return все.filter { !$0.1.isEmpty }
    }
}

// MARK: - Окно «Войти на другом устройстве?»

struct ОкноВходаПоQR: View {
    let токен: String
    let закрыть: () -> Void

    enum Шаг: Equatable {
        case загрузка
        case нуженВход
        case вопрос(СведенияВходаПоQR)
        case отправка(СведенияВходаПоQR)
        case готово
        case ошибка(текст: String, повтор: Bool)
    }

    @State private var шаг: Шаг = .загрузка
    @State private var csrf = ""

    /// Явный init: у окна есть private-состояние, а открывает его ВходПоQR.
    init(токен: String, закрыть: @escaping () -> Void) {
        self.токен = токен
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ВходПоQRText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                содержимое
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .task { await загрузить() }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch шаг {
        case .загрузка:
            VStack(spacing: 14) {
                SiteSpinner(размер: 28, толщина: 3)
                    .padding(.top, 30)
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
        case .нуженВход:
            шапка(значок: "person.crop.circle.badge.questionmark", заголовок: т("need_t"), текст: т("need_s"))
            кнопка(т("sign_in"), главная: true) { войти() }
            кнопка(т("cancel"), главная: false) { закрыть() }
        case .вопрос(let сведения):
            вопрос(сведения, идёт: false)
        case .отправка(let сведения):
            вопрос(сведения, идёт: true)
        case .готово:
            шапка(значок: "checkmark.circle.fill", заголовок: т("done_t"), текст: т("done_s"))
            кнопка(т("ok"), главная: true) { закрыть() }
        case .ошибка(let текст, let повтор):
            шапка(значок: "exclamationmark.triangle", заголовок: т("err_t"), текст: текст)
            if повтор {
                кнопка(т("retry"), главная: true) { Task { await загрузить() } }
            }
            кнопка(т("close"), главная: !повтор) { закрыть() }
        }
    }

    private func вопрос(_ сведения: СведенияВходаПоQR, идёт: Bool) -> some View {
        VStack(spacing: 14) {
            шапка(значок: "desktopcomputer", заголовок: т("ask_t"), текст: сведения.есть ? т("ask_s") : т("ask_g"))
            if !сведения.строки.isEmpty {
                карточка(сведения)
            }
            Text(т("warn"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            кнопка(т("confirm"), главная: true, идёт: идёт) { ответить(true) }
                .disabled(идёт)
            кнопка(т("cancel"), главная: false) { ответить(false) }
                .disabled(идёт)
        }
    }

    private func шапка(значок: String, заголовок: String, текст: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(текст)
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func карточка(_ сведения: СведенияВходаПоQR) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(сведения.строки.enumerated()), id: \.offset) { номер, строка in
                if номер > 0 {
                    Divider().overlay(Theme.линия)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(строка.0)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                    Spacer(minLength: 8)
                    Text(строка.1)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous).stroke(Theme.линия, lineWidth: 1))
    }

    private func кнопка(_ название: String, главная: Bool, идёт: Bool = false,
                        _ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            ZStack {
                Text(название)
                    .font(.system(size: главная ? 16 : 15, weight: главная ? .bold : .semibold))
                    .foregroundStyle(главная ? Color.white : Theme.зелёный2)
                    .opacity(идёт ? 0 : 1)
                if идёт {
                    SiteSpinner(дорожка: Color.white.opacity(0.35), верх: Color.white)
                }
            }
            .frame(maxWidth: .infinity, minHeight: главная ? 50 : 44)
            .background(главная ? Theme.зелёный : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Действия

    /**
     Вошёл ли человек, токен кабинета и сведения об устройстве. info не обязателен: нет точки, неизвестное действие,
     сбой — окно всё равно спрашивает, общей строкой. Решают только ясные ответы: код мёртв, нужен вход, чужой вход.
     */
    private func загрузить() async {
        шаг = .загрузка
        let состояние: КабинетСайта.Состояние
        do {
            состояние = try await КабинетСайта.состояние()
        } catch {
            шаг = .ошибка(текст: ВходПоQR.сбой(error), повтор: true)
            return
        }
        if состояние.вошёл == false {
            шаг = .нуженВход
            return
        }
        csrf = состояние.csrf
        let аккаунт = состояние.имя.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let j = try? await ВходПоQR.запрос("info", код: токен, csrf: csrf) else {
            шаг = .вопрос(СведенияВходаПоQR(аккаунт: аккаунт))
            return
        }
        if ВходПоQR.да(j["ok"]) {
            let st = ((j["st"] as? String) ?? "").lowercased()
            if ["expired", "used", "denied", "approved"].contains(st) {
                let о = ВходПоQR.ошибка(st)
                шаг = .ошибка(текст: о.текст, повтор: о.повтор)
                return
            }
            шаг = .вопрос(СведенияВходаПоQR(j, аккаунт: аккаунт))
            return
        }
        let код = ВходПоQR.кодОшибки(j)
        switch код {
        case "auth":
            шаг = .нуженВход
        case "exp", "expired", "used", "denied", "approved", "bad", "imp":
            let о = ВходПоQR.ошибка(код)
            шаг = .ошибка(текст: о.текст, повтор: о.повтор)
        default:
            шаг = .вопрос(СведенияВходаПоQR(аккаунт: аккаунт))
        }
    }

    /// «Подтвердить вход» — ждём ответа; «Отмена» — окно закрывается сразу, отказ (deny) уходит следом.
    private func ответить(_ да: Bool) {
        guard case .вопрос(let сведения) = шаг else { return }
        let код = токен
        if !да {
            let токенФормы = csrf
            закрыть()
            Task { @MainActor in
                _ = try? await ВходПоQR.запрос("deny", код: код, csrf: токенФормы)
            }
            return
        }
        шаг = .отправка(сведения)
        Task { @MainActor in
            do {
                var j = try await ВходПоQR.запрос("approve", код: код, csrf: csrf)
                if !ВходПоQR.да(j["ok"]) && ВходПоQR.кодОшибки(j) == "csrf" {
                    let состояние = try await КабинетСайта.состояние()
                    if состояние.вошёл == false {
                        шаг = .нуженВход
                        return
                    }
                    csrf = состояние.csrf
                    j = try await ВходПоQR.запрос("approve", код: код, csrf: csrf)
                }
                if ВходПоQR.да(j["ok"]) {
                    шаг = .готово
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                let ошибка = ВходПоQR.кодОшибки(j)
                if ошибка == "auth" {
                    шаг = .нуженВход
                } else {
                    let о = ВходПоQR.ошибка(ошибка)
                    шаг = .ошибка(текст: о.текст, повтор: о.повтор)
                }
            } catch {
                шаг = .ошибка(текст: ВходПоQR.сбой(error), повтор: true)
            }
        }
    }

    /// Не вошёл: окно уходит, свой экран входа; вошёл — окно с тем же кодом снова.
    private func войти() {
        let код = токен
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ВходПоверх.показать(готово: {
                Task { @MainActor in
                    /* Экран входа сперва закрывается сам — окно встаёт уже после него. */
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    ВходПоQR.показать(токен: код)
                }
            })
        }
    }
}

// MARK: - Сканер кода входа

/// Камера «Сканировать QR для входа»: код «Войти по QR» — окно подтверждения; другой код — подсказка.
struct СканерВходаПоQR: View {
    let закрыть: () -> Void

    @State private var проверили = false
    @State private var прочитан = false
    @State private var подсказка: String? = nil

    init(закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ВходПоQRText.т(ключ) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                if проверили {
                    if КамераQRСделки.можно {
                        КамераQRСделки(найден: { прочитать($0) })
                            .ignoresSafeArea()
                    } else {
                        нетКамеры
                    }
                } else {
                    SiteSpinner()
                }
                if проверили && КамераQRСделки.можно {
                    Text(подсказка ?? т("scan_h"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.62),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(т("scan_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
        .task {
            /* Доступ к камере спрашиваем здесь: без него VisionKit считает сканер недоступным. */
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            проверили = true
        }
    }

    private var нетКамеры: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(т("no_cam"))
                .font(.system(size: 15))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button(т("settings")) {
                if let адрес = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
                }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.зелёныйЯркий)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func прочитать(_ текст: String) {
        guard !прочитан else { return }
        let строка = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let адрес = URL(string: строка), Config.deepLink(адрес) != nil,
              let код = ВходПоQR.токен(из: адрес) else {
            подсказка = т("scan_wrong")
            return
        }
        прочитан = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            ВходПоQR.показать(токен: код)
        }
    }
}

/// «Сканировать QR для входа» в разделе «Безопасность» кабинета.
struct СтрокаСканераВхода: View {
    var body: some View {
        Button {
            ВходПоQR.сканировать()
        } label: {
            HStack {
                ПодписьСтрокиКабинета(ВходПоQRText.т("row"), значок: "qrcode.viewfinder")
                Spacer(minLength: 8)
                СтрелкаСтрокиКабинета()
            }
        }
        .полямиСтрокиКабинета()
    }
}

// MARK: - Тексты

/// Тексты входа по QR на языке телефона (kk/ru/en/ar) — тем же способом, что БезСайтаText.
enum ВходПоQRText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "loading": "Проверяем код…",
            "ask_t": "Войти на другом устройстве?",
            "ask_s": "По QR-коду просят войти в ваш аккаунт Kliko на этом устройстве:",
            "warn": "Подтверждайте, только если код на экране показали вы сами. Никому не пересылайте QR-код входа.",
            "dev": "Устройство", "city": "Город", "ip": "IP-адрес", "when": "Время", "acc": "Аккаунт",
            "confirm": "Подтвердить вход", "cancel": "Отмена",
            "done_t": "Готово — вход на компьютере выполнен",
            "done_s": "Компьютер откроет ваш кабинет сам. Если это были не вы — завершите чужой сеанс в «Устройства и входы».",
            "ok": "Готово", "close": "Закрыть", "retry": "Повторить",
            "need_t": "Войдите, чтобы подтвердить вход",
            "need_s": "Вход на компьютере подтверждает телефон, на котором вы уже вошли в Kliko. Войдите — и окно откроется снова.",
            "sign_in": "Войти",
            "err_t": "Не получилось подтвердить вход",
            "e_expired": "Код истёк — он действует 2 минуты. Обновите QR-код на компьютере и отсканируйте его ещё раз.",
            "e_used": "Этот код уже использован. Обновите QR-код на компьютере.",
            "e_denied": "Вход по этому коду отклонён. Обновите QR-код на компьютере.",
            "e_rate": "Слишком часто. Подождите минуту и попробуйте ещё раз.",
            "e_bad": "Неверный код. Отсканируйте QR-код на компьютере ещё раз.",
            "e_off": "Вход по QR сейчас недоступен. Войдите на компьютере по номеру и паролю.",
            "e_net": "Нет соединения. Проверьте интернет и попробуйте ещё раз.",
            "e_app": "Не получилось. Попробуйте ещё раз.",
            "e_exp": "Код истёк или уже использован. Обновите QR-код на компьютере и отсканируйте его ещё раз.",
            "e_approved": "Вход по этому коду уже подтверждён.",
            "e_imp": "Вход под пользователем недоступен: подтверждать вход по QR можно только из своего аккаунта.",
            "e_ua": "Подтвердить вход можно только в приложении Kliko. Обновите приложение и попробуйте ещё раз.",
            "ask_g": "Компьютер запросил вход в ваш аккаунт.",
            "sess": "Сеанс", "u_min": "{n} мин", "u_h": "{n} ч",
            "row": "Сканировать QR для входа",
            "scan_t": "Вход по QR", "scan_h": "Наведите камеру на QR-код «Войти по QR» на экране компьютера",
            "scan_wrong": "Это не код входа Kliko. Откройте на компьютере «Войти» → «Войти по QR».",
            "no_cam": "Нет доступа к камере. Разрешите его в Настройках, чтобы сканировать код.",
            "settings": "Открыть Настройки"
        ],
        "kk": [
            "loading": "Кодты тексеріп жатырмыз…",
            "ask_t": "Басқа құрылғыда кіру керек пе?",
            "ask_s": "QR-код арқылы Kliko аккаунтыңызға мына құрылғыда кіруді сұрап тұр:",
            "warn": "Экрандағы кодты өзіңіз ашқан болсаңыз ғана растаңыз. Кіру QR-кодын ешкімге жібермеңіз.",
            "dev": "Құрылғы", "city": "Қала", "ip": "IP-мекенжай", "when": "Уақыт", "acc": "Аккаунт",
            "confirm": "Кіруді растау", "cancel": "Бас тарту",
            "done_t": "Дайын — компьютерде кіру орындалды",
            "done_s": "Компьютер кабинетіңізді өзі ашады. Бұл сіз болмасаңыз — «Құрылғылар мен кірулер» бөлімінде бөгде сеансты аяқтаңыз.",
            "ok": "Дайын", "close": "Жабу", "retry": "Қайталау",
            "need_t": "Кіруді растау үшін аккаунтқа кіріңіз",
            "need_s": "Компьютерде кіруді Kliko-ға кірген телефон растайды. Кіріңіз — терезе қайта ашылады.",
            "sign_in": "Кіру",
            "err_t": "Кіруді растау мүмкін болмады",
            "e_expired": "Кодтың мерзімі өтті — ол 2 минут жарамды. Компьютерде QR-кодты жаңартып, қайта сканерлеңіз.",
            "e_used": "Бұл код қолданылып қойған. Компьютерде QR-кодты жаңартыңыз.",
            "e_denied": "Бұл код бойынша кіру қабылданбады. Компьютерде QR-кодты жаңартыңыз.",
            "e_rate": "Тым жиі. Бір минут күтіп, қайталап көріңіз.",
            "e_bad": "Код қате. Компьютердегі QR-кодты қайта сканерлеңіз.",
            "e_off": "QR арқылы кіру қазір қолжетімсіз. Компьютерде нөмір мен құпиясөз арқылы кіріңіз.",
            "e_net": "Байланыс жоқ. Интернетті тексеріп, қайталап көріңіз.",
            "e_app": "Болмады. Қайталап көріңіз.",
            "e_exp": "Кодтың мерзімі өтті немесе ол қолданылып қойған. Компьютерде QR-кодты жаңартып, қайта сканерлеңіз.",
            "e_approved": "Бұл код бойынша кіру расталып қойған.",
            "e_imp": "Пайдаланушы атынан кіру режимінде бұл қолжетімсіз: QR арқылы кіруді тек өз аккаунтыңыздан растауға болады.",
            "e_ua": "Кіруді тек Kliko қосымшасында растауға болады. Қосымшаны жаңартып, қайталап көріңіз.",
            "ask_g": "Компьютер аккаунтыңызға кіруді сұрады.",
            "sess": "Сеанс", "u_min": "{n} мин", "u_h": "{n} сағ",
            "row": "Кіру үшін QR сканерлеу",
            "scan_t": "QR арқылы кіру", "scan_h": "Камераны компьютер экранындағы «QR арқылы кіру» кодына бағыттаңыз",
            "scan_wrong": "Бұл Kliko кіру коды емес. Компьютерде «Кіру» → «QR арқылы кіру» бөлімін ашыңыз.",
            "no_cam": "Камераға рұқсат жоқ. Кодты сканерлеу үшін оны Параметрлерде рұқсат етіңіз.",
            "settings": "Параметрлерді ашу"
        ],
        "en": [
            "loading": "Checking the code…",
            "ask_t": "Sign in on another device?",
            "ask_s": "A QR code is asking to sign in to your Kliko account on this device:",
            "warn": "Confirm only if you opened the code on the screen yourself. Never forward a sign-in QR code to anyone.",
            "dev": "Device", "city": "City", "ip": "IP address", "when": "Time", "acc": "Account",
            "confirm": "Confirm sign-in", "cancel": "Cancel",
            "done_t": "Done — you're signed in on the computer",
            "done_s": "The computer will open your account by itself. If it wasn't you, end that session in “Devices and sign-ins”.",
            "ok": "Done", "close": "Close", "retry": "Try again",
            "need_t": "Sign in to confirm",
            "need_s": "A sign-in on the computer is confirmed by a phone that's already signed in to Kliko. Sign in and this window will open again.",
            "sign_in": "Sign in",
            "err_t": "Couldn't confirm the sign-in",
            "e_expired": "The code has expired — it is valid for 2 minutes. Refresh the QR code on the computer and scan it again.",
            "e_used": "This code has already been used. Refresh the QR code on the computer.",
            "e_denied": "Sign-in with this code was declined. Refresh the QR code on the computer.",
            "e_rate": "Too often. Wait a minute and try again.",
            "e_bad": "Invalid code. Scan the QR code on the computer again.",
            "e_off": "QR sign-in isn't available right now. Sign in on the computer with your number and password.",
            "e_net": "No connection. Check the internet and try again.",
            "e_app": "Something went wrong. Please try again.",
            "e_exp": "The code has expired or was already used. Refresh the QR code on the computer and scan it again.",
            "e_approved": "Sign-in with this code has already been confirmed.",
            "e_imp": "Not available while signed in as another user: QR sign-in can only be confirmed from your own account.",
            "e_ua": "Sign-in can only be confirmed in the Kliko app. Update the app and try again.",
            "ask_g": "A computer has requested to sign in to your account.",
            "sess": "Session", "u_min": "{n} min", "u_h": "{n} h",
            "row": "Scan QR to sign in",
            "scan_t": "QR sign-in", "scan_h": "Point the camera at the “Sign in with QR” code on the computer screen",
            "scan_wrong": "This isn't a Kliko sign-in code. On the computer open “Sign in” → “Sign in with QR”.",
            "no_cam": "No camera access. Allow it in Settings to scan the code.",
            "settings": "Open Settings"
        ],
        "ar": [
            "loading": "جارٍ التحقق من الرمز…",
            "ask_t": "تسجيل الدخول على جهاز آخر؟",
            "ask_s": "يطلب رمز QR تسجيل الدخول إلى حسابك في Kliko على هذا الجهاز:",
            "warn": "أكّد فقط إذا كنت أنت من فتح الرمز على الشاشة. لا ترسل رمز QR لتسجيل الدخول إلى أي أحد.",
            "dev": "الجهاز", "city": "المدينة", "ip": "عنوان IP", "when": "الوقت", "acc": "الحساب",
            "confirm": "تأكيد الدخول", "cancel": "إلغاء",
            "done_t": "تم — سُجّل الدخول على الحاسوب",
            "done_s": "سيفتح الحاسوب حسابك تلقائيًا. إذا لم تكن أنت، فأنهِ تلك الجلسة من «الأجهزة وعمليات الدخول».",
            "ok": "تم", "close": "إغلاق", "retry": "إعادة المحاولة",
            "need_t": "سجّل الدخول للتأكيد",
            "need_s": "يؤكَّد الدخول على الحاسوب من هاتف مسجَّل الدخول في Kliko. سجّل الدخول وستُفتح هذه النافذة من جديد.",
            "sign_in": "تسجيل الدخول",
            "err_t": "تعذّر تأكيد الدخول",
            "e_expired": "انتهت صلاحية الرمز — فهو صالح لمدة دقيقتين. حدّث رمز QR على الحاسوب وامسحه من جديد.",
            "e_used": "استُخدم هذا الرمز من قبل. حدّث رمز QR على الحاسوب.",
            "e_denied": "رُفض الدخول بهذا الرمز. حدّث رمز QR على الحاسوب.",
            "e_rate": "محاولات متكررة جدًا. انتظر دقيقة وحاول مجددًا.",
            "e_bad": "رمز غير صحيح. امسح رمز QR على الحاسوب مرة أخرى.",
            "e_off": "الدخول عبر QR غير متاح الآن. سجّل الدخول على الحاسوب برقمك وكلمة المرور.",
            "e_net": "لا يوجد اتصال. تحقّق من الإنترنت وحاول مجددًا.",
            "e_app": "لم ينجح ذلك. حاول مجددًا.",
            "e_exp": "انتهت صلاحية الرمز أو استُخدم من قبل. حدّث رمز QR على الحاسوب وامسحه من جديد.",
            "e_approved": "تم تأكيد الدخول بهذا الرمز من قبل.",
            "e_imp": "غير متاح أثناء الدخول باسم مستخدم آخر: لا يمكن تأكيد الدخول عبر QR إلا من حسابك.",
            "e_ua": "لا يمكن تأكيد الدخول إلا في تطبيق Kliko. حدّث التطبيق وحاول مجددًا.",
            "ask_g": "طلب حاسوب تسجيل الدخول إلى حسابك.",
            "sess": "الجلسة", "u_min": "{n} دقيقة", "u_h": "{n} ساعة",
            "row": "مسح QR لتسجيل الدخول",
            "scan_t": "الدخول عبر QR", "scan_h": "وجّه الكاميرا إلى رمز «الدخول عبر QR» على شاشة الحاسوب",
            "scan_wrong": "هذا ليس رمز دخول Kliko. افتح على الحاسوب «تسجيل الدخول» ← «الدخول عبر QR».",
            "no_cam": "لا يوجد إذن للكاميرا. اسمح به في الإعدادات لمسح الرمز.",
            "settings": "فتح الإعدادات"
        ]
    ]
}
