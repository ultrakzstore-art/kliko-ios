import Foundation
import Observation
import Security
import UIKit
import UserNotifications

/// Состояние приложения: настройки сервера, лента, поиски, статус. Одно на всё приложение.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let defaultEndpoint = "https://kliko.kz/olx-watch/api.php"

    var endpoint: String = UserDefaults.standard.string(forKey: "endpoint") ?? ""
    var token: String = Keychain.read("api_token") ?? ""

    var ads: [Ad] = []
    var subs: [Sub] = []
    var status: ServerStatus?
    var error: String?
    var loadingMore = false
    var reachedEnd = false
    /// Объявление, открытое из пуша, — лента подсветит его.
    var highlightedAdId: Int?

    private var deviceToken: String? = UserDefaults.standard.string(forKey: "device_token")

    var api: API? {
        guard !token.isEmpty, let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        return API(endpoint: url, token: token)
    }

    var configured: Bool { api != nil }

    func saveSettings(endpoint: String, token: String) async -> Bool {
        let e = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: e), url.scheme == "https" || url.scheme == "http" else {
            error = "Адрес должен начинаться с https://"
            return false
        }
        do {
            _ = try await API(endpoint: url, token: t).status()
        } catch {
            self.error = "Сервер не принял: \(error.localizedDescription)"
            return false
        }
        self.endpoint = e
        self.token = t
        UserDefaults.standard.set(e, forKey: "endpoint")
        Keychain.write("api_token", t)
        error = nil
        await sendDeviceToken()
        await refreshAll()
        return true
    }

    // MARK: — загрузка

    func refreshAll() async {
        async let a: Void = refreshFeed()
        async let s: Void = refreshSubs()
        async let st: Void = refreshStatus()
        _ = await (a, s, st)
    }

    func refreshFeed() async {
        guard let api else { return }
        do {
            let fresh = try await api.feed()
            ads = fresh
            reachedEnd = fresh.count < 50
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard let api, !loadingMore, !reachedEnd, let last = ads.last else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let more = try await api.feed(before: last.foundAt)
            let known = Set(ads.map(\.id))
            ads += more.filter { !known.contains($0.id) }
            reachedEnd = more.count < 50
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refreshSubs() async {
        guard let api else { return }
        do { subs = try await api.subs() } catch { self.error = error.localizedDescription }
    }

    func refreshStatus() async {
        guard let api else { return }
        status = try? await api.status()
    }

    // MARK: — поиски

    func addSub(url: String, name: String) async -> Bool {
        guard let api else { return false }
        do {
            let sub = try await api.addSub(url: url.trimmingCharacters(in: .whitespacesAndNewlines), name: name)
            subs.append(sub)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func togglePause(_ sub: Sub) async {
        guard let api else { return }
        do {
            try await api.setPaused(sub.id, !sub.paused)
            await refreshSubs()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ sub: Sub) async {
        guard let api else { return }
        do {
            try await api.deleteSub(sub.id)
            subs.removeAll { $0.id == sub.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setTurbo(_ on: Bool) async {
        guard let api else { return }
        do {
            try await api.setTurbo(on)
            await refreshStatus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func testPush() async {
        guard let api else { return }
        do { try await api.testPush() } catch { self.error = error.localizedDescription }
    }

    // MARK: — пуши

    func requestPushPermission() async {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    func didReceiveDeviceToken(_ data: Data) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        UserDefaults.standard.set(hex, forKey: "device_token")
        await sendDeviceToken()
    }

    private func sendDeviceToken() async {
        guard let api, let deviceToken else { return }
        try? await api.registerDevice(deviceToken)
    }
}

/// Ключ доступа к серверу — в Связке ключей, а не в настройках приложения.
enum Keychain {
    private static let service = "kz.kliko.olxwatch"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
