import Foundation

/**
 Тексты меток фото в «Моих объявлениях» (ultra-site 14.10.2026, «Картинка по описанию, часть 2»): метка «ИИ» на
 обложке карточки (img_ai) и строка «Добавьте настоящие фото — они станут главными» (photos_real = 0). Свой словарь —
 чтобы не пересекаться с МоиОбъявленияText. Языки ru, kk, en, ar; прочие — русский.
 */
enum ФотоМоихОбъявленийText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "mlp_ai_badge": "ИИ",
        "mlp_ai_badge_a11y": "Обложка создана ИИ — не фото товара",
        "mlp_real_add": "Добавьте настоящие фото — они станут главными"
    ]

    private static let kk: [String: String] = [
        "mlp_ai_badge": "ЖИ",
        "mlp_ai_badge_a11y": "Мұқабаны ЖИ жасаған — тауардың фотосы емес",
        "mlp_real_add": "Нақты фото қосыңыз — олар басты болады"
    ]

    private static let en: [String: String] = [
        "mlp_ai_badge": "AI",
        "mlp_ai_badge_a11y": "Cover made by AI — not a photo of the item",
        "mlp_real_add": "Add real photos — they will become the main ones"
    ]

    private static let ar: [String: String] = [
        "mlp_ai_badge": "AI",
        "mlp_ai_badge_a11y": "الغلاف من إنشاء الذكاء الاصطناعي — ليس صورة للمنتج",
        "mlp_real_add": "أضف صورًا حقيقية — ستصبح هي الصور الرئيسية"
    ]
}
