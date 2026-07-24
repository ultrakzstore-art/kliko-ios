import Foundation

/// Профиль вошедшего пользователя (ответ api/mobile_auth.php → mob_public()).
struct AuthUser: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let phone: String
    let verified: Bool
    let isPro: Bool          // is_pro → convertFromSnakeCase

    /// Телефон в читаемом виде: 77015553322 → +7 701 555 33 22
    var phonePretty: String {
        let d = phone.filter(\.isNumber)
        guard d.count == 11 else { return phone }
        func seg(_ lo: Int, _ hi: Int) -> String {
            let s = d.index(d.startIndex, offsetBy: lo)
            let e = d.index(d.startIndex, offsetBy: hi)
            return String(d[s..<e])
        }
        return "+\(seg(0,1)) \(seg(1,4)) \(seg(4,7)) \(seg(7,9)) \(seg(9,11))"
    }
}

/// Универсальный ответ токен-эндпоинта (login/register/me/logout/ошибки/техработы).
struct AuthResponse: Decodable {
    let ok: Bool
    let token: String?
    let password: String?    // только при register — показываем один раз
    let user: AuthUser?
    let error: String?
    let message: String?
    let maintenance: Bool?

    /// Текст для показа пользователю при неуспехе.
    var displayError: String {
        if maintenance == true { return message ?? error ?? "Платформа обновляется — зайдите чуть позже" }
        return message ?? error ?? "Что-то пошло не так"
    }
}
