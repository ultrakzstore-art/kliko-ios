import Foundation

/**
 Тексты карты объявлений (этап 39) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта (js/i18n-marketplace-ru.js и сам mkMapOpen в js/marketplace.min.js): «Карта» — mk_map,
 «Закрыть» — close, «Все» — cat_all, «Загружаем карту…» — mk_map_loading, «Карта недоступна — проверьте интернет» —
 mk_map_fail, «Повторить» — mh_retry, «Приблизьте карту, чтобы увидеть объявления» — mk_map_zoom_hint, «Нет объявлений в
 этой области — отдалите карту» — mk_map_none, «в этой области» — mk_map_found, «Схема» и «Спутник» — mk_map_scheme и
 mk_map_sat, «Рядом» — mk_map_here, «Не удалось определить местоположение» — geo_denied, «Открыть» — mk_map_open, «ТОП» —
 top_badge, «Договорная» — price_negotiable. Сокращения цены и числа — как их пишет скрипт сайта (_mkPrice, _mkPriceShort,
 _mkCountShort): «1.2 млн ₸», «15 тыс ₸», «15к», «1.2м»; расстояние — «350 м», «1.2 км». Подписей для VoiceOver у сайта
 нет (у него значки и title) — их слова наши.
 */
enum MapText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["map": "Карта", "close": "Закрыть", "all": "Все", "loading": "Загружаем карту…",
               "fail": "Карта недоступна — проверьте интернет", "retry": "Повторить",
               "zoom_hint": "Приблизьте карту, чтобы увидеть объявления",
               "none": "Нет объявлений в этой области — отдалите карту", "found": "в этой области",
               "scheme": "Схема", "sat": "Спутник", "here": "Рядом",
               "geo_denied": "Не удалось определить местоположение", "open": "Открыть", "top": "ТОП",
               "negotiable": "Договорная", "mln": "млн", "thous": "тыс", "short_m": "м", "short_k": "к",
               "meters": "м", "km": "км",
               "city_hint": "Приблизить и показать объявления города", "cluster": "Объявлений здесь: %@",
               "cluster_hint": "Приблизить карту", "me": "Вы здесь", "open_hint": "Откроется объявление",
               "sections": "Разделы на карте"],
        "kk": ["map": "Карта", "close": "Жабу", "all": "Барлығы", "loading": "Карта жүктелуде…",
               "fail": "Карта қолжетімсіз — интернетті тексеріңіз", "retry": "Қайталау",
               "zoom_hint": "Хабарландыруларды көру үшін картаны жақындатыңыз",
               "none": "Бұл аймақта хабарландыру жоқ — картаны алыстатыңыз", "found": "осы аймақта",
               "scheme": "Сызба", "sat": "Жерсерік", "here": "Жақын жерде",
               "geo_denied": "Орныңызды анықтау мүмкін болмады", "open": "Ашу", "top": "ТОП",
               "negotiable": "Келісімді", "mln": "млн", "thous": "мың", "short_m": "м", "short_k": "к",
               "meters": "м", "km": "км",
               "city_hint": "Жақындатып, қаланың хабарландыруларын көрсету", "cluster": "Мұнда хабарландыру: %@",
               "cluster_hint": "Картаны жақындату", "me": "Сіз осындасыз", "open_hint": "Хабарландыру ашылады",
               "sections": "Картадағы бөлімдер"],
        "en": ["map": "Map", "close": "Close", "all": "All", "loading": "Loading the map…",
               "fail": "Map unavailable — check your connection", "retry": "Retry",
               "zoom_hint": "Zoom in to see listings",
               "none": "No listings in this area — zoom out", "found": "in this area",
               "scheme": "Map", "sat": "Satellite", "here": "Nearby",
               "geo_denied": "Couldn't determine your location", "open": "Open", "top": "TOP",
               "negotiable": "Negotiable", "mln": "M", "thous": "K", "short_m": "M", "short_k": "K",
               "meters": "m", "km": "km",
               "city_hint": "Zoom in and show the city's listings", "cluster": "Listings here: %@",
               "cluster_hint": "Zoom in", "me": "You are here", "open_hint": "Opens the listing",
               "sections": "Sections on the map"],
        "ar": ["map": "الخريطة", "close": "إغلاق", "all": "الكل", "loading": "جارٍ تحميل الخريطة…",
               "fail": "الخريطة غير متاحة — تحقّق من الإنترنت", "retry": "إعادة المحاولة",
               "zoom_hint": "قرّب الخريطة لرؤية الإعلانات",
               "none": "لا إعلانات في هذه المنطقة — بعّد الخريطة", "found": "في هذه المنطقة",
               "scheme": "مخطط", "sat": "قمر صناعي", "here": "بالقرب",
               "geo_denied": "تعذّر تحديد موقعك", "open": "فتح", "top": "مميّز",
               "negotiable": "قابل للتفاوض", "mln": "مليون", "thous": "ألف", "short_m": "M", "short_k": "K",
               "meters": "م", "km": "كم",
               "city_hint": "تقريب الخريطة وعرض إعلانات المدينة", "cluster": "إعلانات هنا: %@",
               "cluster_hint": "تقريب الخريطة", "me": "أنت هنا", "open_hint": "سيفتح الإعلان",
               "sections": "الأقسام على الخريطة"]
    ]
}
