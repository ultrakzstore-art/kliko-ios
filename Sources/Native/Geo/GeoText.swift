import Foundation

/**
 Тексты выбора города (этап 32) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта (js/i18n-marketplace-ru.js): «Где ищете?» — region_ph, «вся область» — oblast_all, «Крупные
 города» — af_big_cities, «Регион» — af_region, «Определить автоматически» — detect_auto, «Определяем…» —
 af_city_geo_wait, «Не удалось определить город — выберите из списка» — af_city_geo_fail, «Такого места не нашли» и
 «Проверьте написание…» — geo_none и geo_none_h, «Очистить» — geo_clear, «Закрыть» — close; «По всей стране» — all_kz
 (DesignText). Подписей для VoiceOver у сайта нет (у него значки и aria-expanded) — их слова наши. Названия мест —
 русские, как в справочнике и в объявлениях.
 */
enum GeoText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["placeholder": "Где ищете?", "oblast_all": "вся область", "big_cities": "Крупные города", "regions": "Регион",
               "detect": "Определить автоматически", "detecting": "Определяем…",
               "detect_fail": "Не удалось определить город — выберите из списка",
               "none": "Такого места не нашли", "none_hint": "Проверьте написание или выберите область из списка",
               "clear": "Очистить", "close": "Закрыть", "recent": "Недавний выбор",
               "show_cities": "Города: %@", "show_districts": "Районы: %@", "expanded": "Развёрнуто", "collapsed": "Свёрнуто",
               "chip_hint": "Выбрать город или район"],
        "kk": ["placeholder": "Қайда іздейсіз?", "oblast_all": "бүкіл облыс", "big_cities": "Ірі қалалар", "regions": "Өңір",
               "detect": "Автоматты түрде анықтау", "detecting": "Анықтап жатырмыз…",
               "detect_fail": "Қаланы анықтау мүмкін болмады — тізімнен таңдаңыз",
               "none": "Мұндай жер табылмады", "none_hint": "Жазылуын тексеріңіз немесе тізімнен облысты таңдаңыз",
               "clear": "Тазалау", "close": "Жабу", "recent": "Жақында таңдалған",
               "show_cities": "Қалалар: %@", "show_districts": "Аудандар: %@", "expanded": "Ашық", "collapsed": "Жабық",
               "chip_hint": "Қаланы немесе ауданды таңдау"],
        "en": ["placeholder": "Where are you looking?", "oblast_all": "whole region", "big_cities": "Major cities", "regions": "Region",
               "detect": "Detect automatically", "detecting": "Detecting…",
               "detect_fail": "Couldn't detect your city — choose it from the list",
               "none": "No such place found", "none_hint": "Check the spelling or choose a region from the list",
               "clear": "Clear", "close": "Close", "recent": "Recent choice",
               "show_cities": "Cities: %@", "show_districts": "Districts: %@", "expanded": "Expanded", "collapsed": "Collapsed",
               "chip_hint": "Choose a city or district"],
        "ar": ["placeholder": "أين تبحث؟", "oblast_all": "المقاطعة كلها", "big_cities": "المدن الكبرى", "regions": "المنطقة",
               "detect": "تحديد تلقائي", "detecting": "جارٍ التحديد…",
               "detect_fail": "تعذّر تحديد مدينتك — اخترها من القائمة",
               "none": "لم نجد هذا المكان", "none_hint": "تحقّق من الإملاء أو اختر مقاطعة من القائمة",
               "clear": "مسح", "close": "إغلاق", "recent": "اختيار سابق",
               "show_cities": "المدن: %@", "show_districts": "الأحياء: %@", "expanded": "موسّع", "collapsed": "مطويّ",
               "chip_hint": "اختر مدينة أو حيًّا"]
    ]
}
