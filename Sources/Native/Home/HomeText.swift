import Foundation

/**
 Тексты главной одним запросом (этап 34) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта (js/i18n-marketplace-ru.js): «VIP-объявления» — mh_vip_h, «Размещены в ТОП» — mh_vip_s,
 «Показано, как было в последний раз» — mh_stale, «Показать все объявления» — mh_show_all; «Повторить» (mh_retry) и
 «N предложений» (mh_offers_*) уже есть в DesignText.
 Упрощённая главная: «Все объявления» над лентой под рядами, «Фильтры», «О компании» и «Язык приложения» кабинета.
 */
enum HomeText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["vip_h": "VIP-объявления", "vip_s": "Размещены в ТОП",
               "stale": "Показано, как было в последний раз", "show_all": "Показать все объявления",
               "all_h": "Все объявления", "filters": "Фильтры", "about_co": "О компании",
               "app_lang": "Язык приложения"],
        "kk": ["vip_h": "VIP-хабарландырулар", "vip_s": "ТОП-та орналастырылған",
               "stale": "Соңғы рет қалай болса, солай көрсетілді", "show_all": "Барлық хабарландыруларды көрсету",
               "all_h": "Барлық хабарландырулар", "filters": "Сүзгілер", "about_co": "Компания туралы",
               "app_lang": "Қосымша тілі"],
        "en": ["vip_h": "VIP listings", "vip_s": "Placed in TOP",
               "stale": "Showing what was here last time", "show_all": "Show all listings",
               "all_h": "All listings", "filters": "Filters", "about_co": "About the company",
               "app_lang": "App language"],
        "ar": ["vip_h": "إعلانات VIP", "vip_s": "منشورة ضمن المميزة",
               "stale": "نعرض ما كان هنا في المرة الأخيرة", "show_all": "عرض كل الإعلانات",
               "all_h": "كل الإعلانات", "filters": "الفلاتر", "about_co": "عن الشركة",
               "app_lang": "لغة التطبيق"]
    ]
}
