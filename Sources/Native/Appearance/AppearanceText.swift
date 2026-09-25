import Foundation

/// Тексты выбора темы оформления (этап 15) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
/// Ключи system / light / dark — это rawValue ТемаОформления.
enum AppearanceText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Оформление", "theme": "Тема",
               "system": "Системная", "light": "Светлая", "dark": "Тёмная",
               "footer": "«Системная» — как в настройках iPhone. Тема действует во всём приложении, в том числе на страницах сайта, и хранится на этом телефоне."],
        "kk": ["title": "Сыртқы түрі", "theme": "Тақырып",
               "system": "Жүйелік", "light": "Ашық", "dark": "Қараңғы",
               "footer": "«Жүйелік» — iPhone баптауларындағыдай. Тақырып бүкіл қосымшада, соның ішінде сайт беттерінде қолданылады және осы телефонда сақталады."],
        "en": ["title": "Appearance", "theme": "Theme",
               "system": "System", "light": "Light", "dark": "Dark",
               "footer": "System follows your iPhone settings. The theme applies to the whole app, including website pages, and is stored on this phone."],
        "ar": ["title": "المظهر", "theme": "السمة",
               "system": "حسب النظام", "light": "فاتح", "dark": "داكن",
               "footer": "«حسب النظام» يتبع إعدادات iPhone. تنطبق السمة على التطبيق كله، ومنه صفحات الموقع، وتُحفظ على هذا الهاتف."]
    ]
}
