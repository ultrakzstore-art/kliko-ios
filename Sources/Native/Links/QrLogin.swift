import AVFoundation
import SwiftUI
import UIKit

/**
 ВХОД НА КОМПЬЮТЕРЕ ПО QR (владелец 29.09.2026: камера iPhone открывала код «Войти по QR» в приложении, а приложение
 отвечало «Страница недоступна в приложении»).

 Код на экране входа сайта — адрес https://kliko.kz/qr_login.php?t=<64 hex> (сервер: inc/app_qr_login.php, патч 75 в
 private/INTEGRATION.md). Универсальная ссылка приходит в WebBridge.открытьСнаружи / перейти — там её забирает
 ВходПоQR.перехватить раньше всех прочих разборов и показывает своё окно:
   1. КабинетСайта.состояние — вошёл ли человек и токен формы (KlikoCsrf). Не вошёл — «Войдите, чтобы подтвердить вход»:
      свой ЭкранВхода (ВходПоверх), после входа окно открывается снова с тем же кодом.
   2. POST /api/app_qr_login.php {action:'info', t} — какое устройство просит вход (браузер и система, город, IP, время) и
      в какой аккаунт. Компьютер в это время видит «Код отсканирован».
   3. «Подтвердить вход» — {action:'confirm', t, csrf}; «Отмена» — {action:'cancel'} и окно закрывается. Без нажатия
      ничего не подтверждается. Ответ «csrf» — токен перечитывается и запрос повторяется один раз.
 Ошибки сервера — своими словами: код устарел, уже использован, отменён, аккаунт недоступен, слишком часто.

 Второй вход — «Сканировать QR для входа» в «Кабинет → Безопасность» (СтрокаСканераВхода): тот же сканер, что у встречи
 сделки (КамераQRСделки), и то же окно.
 */
@MainActor
enum ВходПоQR {
    /// Последний перехваченный код: одна ссылка, пришедшая дважды (холодный старт и continue), не ставит два окна.
    private static var последний: (токен: String, когда: Date)? = nil

    /// Код из адреса «Войти по QR» (…/qr_login.php?t=<64 hex>, с языком в пути /kz/ru/ или без) или nil.
    static func токен(из адрес: URL) -> String? {
        let полный = адрес.absoluteURL
        guard let схема = полный.scheme?.lowercased(), схема == "https" || схема == "http",
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: false) else { return nil }
        let путь = части.path.lowercased()
        guard путь.range(of: "^(/[a-z]{2}/[a-z]{2})?/qr_login(\\.php)?/?$", options: .regularExpression) != nil else {
            return nil
        }
        let код = (части.queryItems?.first(where: { $0.name == "t" })?.value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard код.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return nil }
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

    /// POST /api/app_qr_login.php с куками сессии приложения. Точки нет (404 без JSON) — {ok:false, error:"off"}.
    static func запрос(_ тело: [String: Any]) async throws -> [String: Any] {
        let ответ = try await КабинетСайта.вызвать("/api/app_qr_login.php", метод: "POST", тело: тело, отКорня: true)
        if let json = ответ.json { return json }
        if ответ.код == 404 || ответ.код == 405 { return ["ok": false, "error": "off"] }
        throw КабинетСайта.Сбой.приложение
    }

    /// Текст ошибки сервера и можно ли повторить.
    static func ошибка(_ код: String) -> (текст: String, повтор: Bool) {
        switch код {
        case "expired", "not_found": return (ВходПоQRText.т("e_expired"), false)
        case "used": return (ВходПоQRText.т("e_used"), false)
        case "denied": return (ВходПоQRText.т("e_denied"), false)
        case "account": return (ВходПоQRText.т("e_account"), false)
        case "rate": return (ВходПоQRText.т("e_rate"), true)
        case "bad_token": return (ВходПоQRText.т("e_bad"), false)
        case "off", "method", "action": return (ВходПоQRText.т("e_off"), false)
        default: return (ВходПоQRText.т("e_app"), true)
        }
    }

    /// Сбой транспорта: нет связи — «Нет соединения», прочее — «Не получилось».
    static func сбой(_ ошибка: Error) -> String {
        (ошибка as? КабинетСайта.Сбой) == .сеть ? ВходПоQRText.т("e_net") : ВходПоQRText.т("e_app")
    }
}

/// Что сервер сказал об устройстве, которое просит вход ({action:'info'}).
struct СведенияВходаПоQR: Equatable {
    var устройство: String = ""
    var город: String = ""
    var ip: String = ""
    var когда: String = ""
    var аккаунт: String = ""

    init(_ j: [String: Any]) {
        устройство = (j["dev"] as? String) ?? ""
        город = (j["city"] as? String) ?? ""
        ip = (j["ip"] as? String) ?? ""
        когда = (j["when"] as? String) ?? ""
        аккаунт = (j["name"] as? String) ?? ""
    }

    /// Строки карточки: подпись и значение, пустые — прочь.
    var строки: [(String, String)] {
        let все: [(String, String)] = [
            (ВходПоQRText.т("dev"), устройство),
            (ВходПоQRText.т("city"), город),
            (ВходПоQRText.т("ip"), ip),
            (ВходПоQRText.т("when"), когда),
            (ВходПоQRText.т("acc"), аккаунт)
        ]
        return все.filter { !$0.1.isEmpty }
    }

    static func == (a: СведенияВходаПоQR, b: СведенияВходаПоQR) -> Bool {
        a.устройство == b.устройство && a.город == b.город && a.ip == b.ip && a.когда == b.когда && a.аккаунт == b.аккаунт
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
        case готово(eGov: Bool)
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
        case .готово(let eGov):
            шапка(значок: "checkmark.circle.fill", заголовок: т("done_t"), текст: eGov ? т("done_egov") : т("done_s"))
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
            шапка(значок: "desktopcomputer", заголовок: т("ask_t"), текст: т("ask_s"))
            карточка(сведения)
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

    private func загрузить() async {
        шаг = .загрузка
        do {
            let состояние = try await КабинетСайта.состояние()
            if состояние.вошёл == false {
                шаг = .нуженВход
                return
            }
            csrf = состояние.csrf
            let j = try await ВходПоQR.запрос(["action": "info", "t": токен])
            if (j["ok"] as? Bool) == true {
                шаг = .вопрос(СведенияВходаПоQR(j))
                return
            }
            let код = (j["error"] as? String) ?? ""
            if код == "auth" {
                шаг = .нуженВход
            } else {
                let о = ВходПоQR.ошибка(код)
                шаг = .ошибка(текст: о.текст, повтор: о.повтор)
            }
        } catch {
            шаг = .ошибка(текст: ВходПоQR.сбой(error), повтор: true)
        }
    }

    /// «Подтвердить вход» — ждём ответа; «Отмена» — окно закрывается сразу, отказ уходит следом.
    private func ответить(_ да: Bool) {
        guard case .вопрос(let сведения) = шаг else { return }
        let код = токен
        if !да {
            let токенФормы = csrf
            закрыть()
            Task { @MainActor in
                _ = try? await ВходПоQR.запрос(["action": "cancel", "t": код, "csrf": токенФормы])
            }
            return
        }
        шаг = .отправка(сведения)
        Task { @MainActor in
            do {
                var j = try await ВходПоQR.запрос(["action": "confirm", "t": код, "csrf": csrf])
                if (j["error"] as? String) == "csrf" {
                    let состояние = try await КабинетСайта.состояние()
                    csrf = состояние.csrf
                    j = try await ВходПоQR.запрос(["action": "confirm", "t": код, "csrf": csrf])
                }
                if (j["ok"] as? Bool) == true {
                    шаг = .готово(eGov: (j["egov"] as? Bool) ?? false)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
                let ошибка = (j["error"] as? String) ?? ""
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
            "done_egov": "В аккаунте включена защита входа: осталось подтвердить вход через eGov на компьютере.",
            "ok": "Готово", "close": "Закрыть", "retry": "Повторить",
            "need_t": "Войдите, чтобы подтвердить вход",
            "need_s": "Вход на компьютере подтверждает телефон, на котором вы уже вошли в Kliko. Войдите — и окно откроется снова.",
            "sign_in": "Войти",
            "err_t": "Не получилось подтвердить вход",
            "e_expired": "Код устарел. Обновите QR-код на компьютере и отсканируйте его ещё раз.",
            "e_used": "Этот код уже использован. Обновите QR-код на компьютере.",
            "e_denied": "Вход по этому коду уже отменён. Обновите QR-код на компьютере.",
            "e_account": "Этот аккаунт сейчас недоступен для входа. Напишите в поддержку.",
            "e_rate": "Слишком много попыток. Подождите пару минут.",
            "e_bad": "Ссылка из QR-кода неполная. Отсканируйте код ещё раз.",
            "e_off": "Вход по QR сейчас недоступен. Войдите на компьютере по номеру и паролю.",
            "e_net": "Нет соединения. Проверьте интернет и попробуйте ещё раз.",
            "e_app": "Не получилось. Попробуйте ещё раз.",
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
            "done_egov": "Аккаунтта кіруді қорғау қосулы: компьютерде eGov арқылы кіруді растау қалды.",
            "ok": "Дайын", "close": "Жабу", "retry": "Қайталау",
            "need_t": "Кіруді растау үшін аккаунтқа кіріңіз",
            "need_s": "Компьютерде кіруді Kliko-ға кірген телефон растайды. Кіріңіз — терезе қайта ашылады.",
            "sign_in": "Кіру",
            "err_t": "Кіруді растау мүмкін болмады",
            "e_expired": "Кодтың мерзімі өтті. Компьютерде QR-кодты жаңартып, қайта сканерлеңіз.",
            "e_used": "Бұл код қолданылған. Компьютерде QR-кодты жаңартыңыз.",
            "e_denied": "Бұл код бойынша кіру тоқтатылған. Компьютерде QR-кодты жаңартыңыз.",
            "e_account": "Бұл аккаунтқа қазір кіру мүмкін емес. Қолдауға жазыңыз.",
            "e_rate": "Әрекет тым көп. Бірнеше минут күтіңіз.",
            "e_bad": "QR-кодтағы сілтеме толық емес. Кодты қайта сканерлеңіз.",
            "e_off": "QR арқылы кіру қазір қолжетімсіз. Компьютерде нөмір мен құпиясөз арқылы кіріңіз.",
            "e_net": "Байланыс жоқ. Интернетті тексеріп, қайталап көріңіз.",
            "e_app": "Болмады. Қайталап көріңіз.",
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
            "done_egov": "Sign-in protection is on for this account: confirm the sign-in with eGov on the computer.",
            "ok": "Done", "close": "Close", "retry": "Try again",
            "need_t": "Sign in to confirm",
            "need_s": "A sign-in on the computer is confirmed by a phone that's already signed in to Kliko. Sign in and this window will open again.",
            "sign_in": "Sign in",
            "err_t": "Couldn't confirm the sign-in",
            "e_expired": "The code has expired. Refresh the QR code on the computer and scan it again.",
            "e_used": "This code has already been used. Refresh the QR code on the computer.",
            "e_denied": "Sign-in with this code was cancelled. Refresh the QR code on the computer.",
            "e_account": "This account can't be signed in to right now. Please contact support.",
            "e_rate": "Too many attempts. Please wait a couple of minutes.",
            "e_bad": "The link in the QR code is incomplete. Scan the code again.",
            "e_off": "QR sign-in isn't available right now. Sign in on the computer with your number and password.",
            "e_net": "No connection. Check the internet and try again.",
            "e_app": "Something went wrong. Please try again.",
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
            "done_egov": "حماية الدخول مفعّلة في هذا الحساب: أكّد الدخول عبر eGov على الحاسوب.",
            "ok": "تم", "close": "إغلاق", "retry": "إعادة المحاولة",
            "need_t": "سجّل الدخول للتأكيد",
            "need_s": "يؤكَّد الدخول على الحاسوب من هاتف مسجَّل الدخول في Kliko. سجّل الدخول وستُفتح هذه النافذة من جديد.",
            "sign_in": "تسجيل الدخول",
            "err_t": "تعذّر تأكيد الدخول",
            "e_expired": "انتهت صلاحية الرمز. حدّث رمز QR على الحاسوب وامسحه من جديد.",
            "e_used": "استُخدم هذا الرمز من قبل. حدّث رمز QR على الحاسوب.",
            "e_denied": "أُلغي الدخول بهذا الرمز. حدّث رمز QR على الحاسوب.",
            "e_account": "لا يمكن الدخول إلى هذا الحساب حاليًا. راسل الدعم.",
            "e_rate": "محاولات كثيرة جدًا. انتظر بضع دقائق.",
            "e_bad": "الرابط في رمز QR غير مكتمل. امسح الرمز مرة أخرى.",
            "e_off": "الدخول عبر QR غير متاح الآن. سجّل الدخول على الحاسوب برقمك وكلمة المرور.",
            "e_net": "لا يوجد اتصال. تحقّق من الإنترنت وحاول مجددًا.",
            "e_app": "لم ينجح ذلك. حاول مجددًا.",
            "row": "مسح QR لتسجيل الدخول",
            "scan_t": "الدخول عبر QR", "scan_h": "وجّه الكاميرا إلى رمز «الدخول عبر QR» على شاشة الحاسوب",
            "scan_wrong": "هذا ليس رمز دخول Kliko. افتح على الحاسوب «تسجيل الدخول» ← «الدخول عبر QR».",
            "no_cam": "لا يوجد إذن للكاميرا. اسمح به في الإعدادات لمسح الرمز.",
            "settings": "فتح الإعدادات"
        ]
    ]
}
