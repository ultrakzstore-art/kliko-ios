import Foundation

/**
 Тексты входа через Google, добавка 14.10.2026 (ultra-site, «Вход через Google», пункт 5: лимиты native и phone —
 ответ rate_limited). Свой словарь, чтобы не задевать ВходGoogleText. Языки: ru, kk, en, ar; прочие — русский.
 */
enum ВходGoogleДопText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "g_rate": "Слишком много попыток — подождите немного и попробуйте снова"
    ]

    private static let kk: [String: String] = [
        "g_rate": "Тым көп әрекет — біраз күтіп, қайталап көріңіз"
    ]

    private static let en: [String: String] = [
        "g_rate": "Too many attempts — wait a little and try again"
    ]

    private static let ar: [String: String] = [
        "g_rate": "محاولات كثيرة جدًا — انتظر قليلًا وحاول مرة أخرى"
    ]
}
