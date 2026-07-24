import Foundation
import Security

/// Хранилище bearer-токена в Keychain (безопаснее UserDefaults: шифруется системой,
/// не попадает в бэкапы iTunes в открытом виде). Один токен на устройство.
final class TokenStore {
    static let shared = TokenStore()
    private init() {}

    private let service = "kz.kliko.app"
    private let account = "bearer_token"

    /// Текущий токен (nil — не вошли).
    var token: String? { read() }

    func save(_ token: String) {
        let data = Data(token.utf8)
        let base: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)   // перезапись: удалить старый, добавить новый
        var add = base
        add[kSecValueData as String]      = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock   // доступен в фоне после разблокировки
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }
}
