import SwiftUI

/// Глобальное состояние сессии. Инжектится как @EnvironmentObject.
/// Разовый пароль после регистрации (показываем один раз, потом не восстановить).
struct OneTimeSecret: Identifiable { let id = UUID(); let password: String }

@MainActor
final class AppState: ObservableObject {
    @Published var user: AuthUser?
    @Published var booting = true          // пока проверяем сохранённый токен на старте
    @Published var pendingPassword: OneTimeSecret?   // показать сразу после регистрации

    var isAuthed: Bool { user != nil }

    /// Старт приложения: если токен в Keychain есть — валидируем через /me.
    func bootstrap() async {
        defer { booting = false }
        guard TokenStore.shared.token != nil else { return }
        if let r = try? await API.shared.me(), r.ok, let u = r.user {
            user = u
        } else {
            TokenStore.shared.clear()      // токен протух / отозван — забываем
        }
    }

    /// Вход. Возвращает nil при успехе, иначе текст ошибки для UI.
    func login(phone: String, password: String) async -> String? {
        do {
            let r = try await API.shared.login(phone: phone, password: password)
            guard r.ok, let t = r.token, let u = r.user else { return r.displayError }
            TokenStore.shared.save(t); user = u
            return nil
        } catch { return "Нет связи с сервером. Проверьте интернет." }
    }

    /// Регистрация. При успехе логинит, публикует разовый пароль (pendingPassword) и
    /// возвращает nil. Иначе возвращает текст ошибки.
    func register(phone: String, name: String) async -> String? {
        do {
            let r = try await API.shared.register(phone: phone, name: name)
            guard r.ok, let t = r.token, let u = r.user else { return r.displayError }
            TokenStore.shared.save(t)
            if let pw = r.password { pendingPassword = OneTimeSecret(password: pw) }
            user = u
            return nil
        } catch { return "Нет связи с сервером. Проверьте интернет." }
    }

    func logout() async {
        await API.shared.logout()
        TokenStore.shared.clear()
        user = nil
    }
}
