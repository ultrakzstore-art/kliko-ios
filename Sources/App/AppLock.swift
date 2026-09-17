import SwiftUI
import LocalAuthentication

/// ВХОД ПО FACE ID (владелец 17.09.2026: «и Face ID в iOS»).
///
/// Защита входа в приложение, включается самим человеком: сайт показывает строку «Вход по Face ID» в Настройках
/// кабинета только внутри приложения (мост klikoLock). Включено — Kliko просит Face ID (Touch ID, Optic ID; нет биометрии
/// или она не прошла — код телефона) при запуске и при возврате, если приложение пробыло в фоне дольше минуты. Пока
/// приложение неактивно, содержимое закрыто: в переключателе приложений не видно переписки и сделок.
///
/// ГДЕ ХРАНИТСЯ ВЫБОР. На телефоне (UserDefaults), а не на аккаунте: защищается это устройство, а на другом телефоне
/// биометрия своя. Включение и выключение подтверждаются той же проверкой — иначе защиту снял бы любой, кто взял
/// разблокированный телефон.
///
/// СЕССИЯ НЕ МЕНЯЕТСЯ. Куки WebView живут как раньше; замок — экран поверх, а не выход. Сайт ничего не узнаёт о
/// биометрии: мост отдаёт только «что умеет устройство» и «включено ли».
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private let ключ = "kliko.applock.enabled"
    /// Вернулся раньше — без повторной проверки: сбегать за кодом из SMS или в WhatsApp не должно стоить Face ID.
    private let запас: TimeInterval = 60

    @Published private(set) var enabled: Bool
    @Published private(set) var locked: Bool
    /// Закрыть содержимое, пока приложение не активно (переключатель приложений, системные окна).
    @Published private(set) var cover = false

    private var ушёлВ: Date?
    private var проверяем = false
    /// Человек отменил проверку — сами не переспрашиваем, пока он не нажмёт кнопку или не вернётся в приложение.
    private var можноСпроситьСамим = true

    private init() {
        let вкл = UserDefaults.standard.bool(forKey: ключ)
        enabled = вкл
        locked = вкл
    }

    /// Что умеет устройство: faceID / touchID / opticID / passcode / none.
    func kind() -> String {
        let ctx = LAContext()
        var ошибка: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &ошибка) {
            switch ctx.biometryType {
            case .faceID:  return "faceID"
            case .touchID: return "touchID"
            case .opticID: return "opticID"
            default: break
            }
        }
        return ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &ошибка) ? "passcode" : "none"
    }

    /// Проверка владельца: биометрия, при неудаче — код телефона. Код ответа: cancel / lockout / unavailable / failed.
    func authenticate(reason: String, completion: @escaping (Bool, String?) -> Void) {
        let ctx = LAContext()
        ctx.localizedCancelTitle = AppLock.т("cancel")
        var ошибка: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &ошибка) else {
            completion(false, "unavailable")
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, err in
            let код: String?
            if ok {
                код = nil
            } else {
                switch (err as? LAError)?.code {
                case .some(.userCancel), .some(.systemCancel), .some(.appCancel): код = "cancel"
                case .some(.biometryLockout): код = "lockout"
                default: код = "failed"
                }
            }
            DispatchQueue.main.async { completion(ok, код) }
        }
    }

    /// Снять замок. force — по нажатию кнопки: спрашиваем, даже если прошлую проверку человек отменил.
    func unlock(force: Bool = false) {
        guard enabled, locked, !проверяем else { return }
        if !force && !можноСпроситьСамим { return }
        проверяем = true
        authenticate(reason: AppLock.т("reason_open")) { [weak self] ok, _ in
            guard let self else { return }
            self.проверяем = false
            if ok {
                self.locked = false
                self.можноСпроситьСамим = true
            } else {
                self.можноСпроситьСамим = false
            }
        }
    }

    /// Включить или выключить защиту — только после проверки владельца. completion(прошло, код).
    func setEnabled(_ on: Bool, completion: @escaping (Bool, String?) -> Void) {
        guard !проверяем else { completion(false, "busy"); return }
        проверяем = true
        authenticate(reason: AppLock.т(on ? "reason_on" : "reason_off")) { [weak self] ok, код in
            guard let self else { return }
            self.проверяем = false
            if ok {
                self.enabled = on
                UserDefaults.standard.set(on, forKey: self.ключ)
                self.locked = false
            }
            completion(ok, код)
        }
    }

    // MARK: - Жизненный цикл сцены (SceneDelegate)

    func sceneWillResignActive() {
        /* Окно проверки Face ID тоже делает приложение неактивным — закрывать содержимое во время своей же проверки
           незачем: под окном и так замок или настройки. */
        if enabled && !проверяем { cover = true }
    }

    func sceneDidEnterBackground() {
        guard enabled else { return }
        cover = true
        if ушёлВ == nil { ушёлВ = Date() }
    }

    func sceneWillEnterForeground() {
        guard enabled else { return }
        if let когда = ушёлВ, Date().timeIntervalSince(когда) >= запас { locked = true }
        ушёлВ = nil
        можноСпроситьСамим = true
    }

    func sceneDidBecomeActive() {
        cover = false
        if enabled && locked { unlock() }
    }

    // MARK: - Тексты на языке телефона (kk/ru/en/ar)

    static func имяСпособа(_ kind: String) -> String {
        switch kind {
        case "faceID":  return "Face ID"
        case "touchID": return "Touch ID"
        case "opticID": return "Optic ID"
        default:        return т("passcode")
        }
    }

    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Kliko защищён", "sub": "Откройте, чтобы увидеть переписку, сделки и кошелёк",
               "open": "Открыть по %@", "passcode": "коду телефона", "cancel": "Отмена",
               "reason_open": "Откройте Kliko", "reason_on": "Подтвердите, чтобы включить защиту входа",
               "reason_off": "Подтвердите, чтобы выключить защиту входа"],
        "kk": ["title": "Kliko қорғалған", "sub": "Хаттарды, мәмілелерді және әмиянды көру үшін ашыңыз",
               "open": "%@ арқылы ашу", "passcode": "телефон коды", "cancel": "Бас тарту",
               "reason_open": "Kliko-ны ашыңыз", "reason_on": "Кіру қорғанысын қосу үшін растаңыз",
               "reason_off": "Кіру қорғанысын өшіру үшін растаңыз"],
        "en": ["title": "Kliko is locked", "sub": "Unlock to see your chats, deals and wallet",
               "open": "Unlock with %@", "passcode": "passcode", "cancel": "Cancel",
               "reason_open": "Unlock Kliko", "reason_on": "Confirm to turn on sign-in protection",
               "reason_off": "Confirm to turn off sign-in protection"],
        "ar": ["title": "‏Kliko مقفل", "sub": "افتح القفل لرؤية المحادثات والصفقات والمحفظة",
               "open": "فتح باستخدام %@", "passcode": "رمز الهاتف", "cancel": "إلغاء",
               "reason_open": "افتح Kliko", "reason_on": "أكّد لتفعيل حماية الدخول",
               "reason_off": "أكّد لإيقاف حماية الدخول"]
    ]
}

/// Экран замка: поверх страницы, пока защита включена и приложение заперто или неактивно.
struct LockView: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer()
                KlikoLogoIcon(size: 84)
                Text(AppLock.т("title"))
                    .font(.title3.weight(.bold))
                    .padding(.top, 10)
                Text(AppLock.т("sub"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                if lock.locked {
                    Button {
                        lock.unlock(force: true)
                    } label: {
                        Label(String(format: AppLock.т("open"), AppLock.имяСпособа(lock.kind())), systemImage: значок)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .foregroundStyle(.white)
                            .background(Theme.green2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private var значок: String {
        switch lock.kind() {
        case "faceID":  return "faceid"
        case "touchID": return "touchid"
        case "opticID": return "opticid"
        default:        return "lock.fill"
        }
    }
}
