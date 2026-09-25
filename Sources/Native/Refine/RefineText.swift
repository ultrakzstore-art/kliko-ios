import Foundation

/// Тексты уточнения ленты (этап 18) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).
enum RefineText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["refine": "Уточнить", "title": "Уточнить ленту",
               "note": "Уточнение отбирает только уже загруженные объявления (%d), а не весь сайт. Листайте ленту дальше — подгруженные тоже пройдут отбор.",
               "city": "Город", "any_city": "Любой", "price": "Цена, ₸", "from": "от", "to": "до",
               "price_swapped": "«от» больше, чем «до», — ничего не подойдёт.",
               "only_new": "Только новые", "reset": "Сбросить", "done": "Готово",
               "chip": "Уточнено по загруженным: %d из %d", "reset_a11y": "Сбросить уточнение",
               "none": "Среди загруженных ничего не подходит",
               "none_sub": "Подгружаем следующие страницы ленты. Можно смягчить условия или сбросить уточнение.",
               "more": "Искать дальше", "more_sub": "На последних страницах ленты подходящих не нашлось."],
        "kk": ["refine": "Нақтылау", "title": "Лентаны нақтылау",
               "note": "Нақтылау бүкіл сайтты емес, тек жүктелген хабарландыруларды (%d) іріктейді. Лентаны әрі қарай парақтаңыз — жаңа жүктелгендер де іріктеледі.",
               "city": "Қала", "any_city": "Кез келген", "price": "Бағасы, ₸", "from": "бастап", "to": "дейін",
               "price_swapped": "«бастап» мәні «дейін» мәнінен үлкен — ештеңе сәйкес келмейді.",
               "only_new": "Тек жаңалары", "reset": "Тазалау", "done": "Дайын",
               "chip": "Жүктелгендер бойынша нақтыланды: %d / %d", "reset_a11y": "Нақтылауды тазалау",
               "none": "Жүктелгендердің ішінде сәйкес келетіні жоқ",
               "none_sub": "Лентаның келесі беттерін жүктеп жатырмыз. Шарттарды жұмсартуға немесе нақтылауды тазалауға болады.",
               "more": "Әрі қарай іздеу", "more_sub": "Лентаның соңғы беттерінде сәйкес келетіні табылмады."],
        "en": ["refine": "Refine", "title": "Refine feed",
               "note": "Refining only filters listings already loaded (%d), not the whole website. Keep scrolling — newly loaded listings are filtered too.",
               "city": "City", "any_city": "Any", "price": "Price, ₸", "from": "from", "to": "to",
               "price_swapped": "“from” is higher than “to”, so nothing will match.",
               "only_new": "New only", "reset": "Reset", "done": "Done",
               "chip": "Refined among loaded: %d of %d", "reset_a11y": "Reset refinement",
               "none": "Nothing loaded matches",
               "none_sub": "Loading more pages of the feed. You can loosen the conditions or reset the refinement.",
               "more": "Keep searching", "more_sub": "No matches on the last pages of the feed."],
        "ar": ["refine": "تصفية", "title": "تصفية الإعلانات",
               "note": "تُصفّي التصفية الإعلانات المحمّلة فقط (%d)، لا الموقع كله. واصل التمرير — ستخضع الإعلانات المحمّلة لاحقًا للتصفية أيضًا.",
               "city": "المدينة", "any_city": "أي مدينة", "price": "السعر، ₸", "from": "من", "to": "إلى",
               "price_swapped": "قيمة «من» أكبر من «إلى»، لذا لن يطابق شيء.",
               "only_new": "الجديد فقط", "reset": "إعادة الضبط", "done": "تم",
               "chip": "تمت التصفية بين المحمّل: %d من %d", "reset_a11y": "إعادة ضبط التصفية",
               "none": "لا شيء مما تم تحميله يطابق",
               "none_sub": "نحمّل الصفحات التالية من الإعلانات. يمكنك تخفيف الشروط أو إعادة ضبط التصفية.",
               "more": "متابعة البحث", "more_sub": "لم يتم العثور على نتائج مطابقة في آخر صفحات الإعلانات."]
    ]
}
