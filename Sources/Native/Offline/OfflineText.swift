import Foundation

/// Тексты карточки без сети (этап 13) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
enum OfflineText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// «3 часа назад» — когда легла копия; на языке телефона, как остальные тексты, а не на языке региона.
    static func когда(_ дата: Date) -> String {
        относительно.localizedString(for: дата, relativeTo: Date())
    }

    private static let относительно: RelativeDateTimeFormatter = {
        let ф = RelativeDateTimeFormatter()
        ф.unitsStyle = .full
        ф.dateTimeStyle = .named
        ф.locale = Locale(identifier: Locale.preferredLanguages.first ?? "ru")
        return ф
    }()

    private static let тексты: [String: [String: String]] = [
        "ru": ["copy": "Сохранённая копия · %@",
               "copy_sub": "Нет связи с сайтом — цена и наличие могли измениться.",
               "list_copy": "Нет связи — показан сохранённый список"],
        "kk": ["copy": "Сақталған көшірме · %@",
               "copy_sub": "Сайтпен байланыс жоқ — бағасы мен бар-жоғы өзгеруі мүмкін.",
               "list_copy": "Байланыс жоқ — сақталған тізім көрсетілуде"],
        "en": ["copy": "Saved copy · %@",
               "copy_sub": "Can't reach the website — the price and availability may have changed.",
               "list_copy": "No connection — showing the saved list"],
        "ar": ["copy": "نسخة محفوظة · %@",
               "copy_sub": "تعذّر الاتصال بالموقع — ربما تغيّر السعر أو التوفر.",
               "list_copy": "لا يوجد اتصال — نعرض القائمة المحفوظة"]
    ]
}
