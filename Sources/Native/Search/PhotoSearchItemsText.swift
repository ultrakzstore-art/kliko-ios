import Foundation

/**
 Тексты карточек поиска по фото из ответа сайта (правка сайта 14.10.2026, PhotoSearchItems.swift) — на языке
 приложения (kk/ru/en/ar), тем же способом, что ПоискСайтаText: подписи уровня выдачи по написаниям («без раздела»,
 «по всему Казахстану и без раздела»), «Показать ещё» под сеткой похожих и отказ по частоте с числом из limit.
 Подпись «Рядом не нашли — показываем по всему Казахстану» — прежняя ps_lvl_country (ПоискСайтаText). Свои, переведены
 тем же тоном, что прежние тексты поиска по фото.
 */
enum ПохожиеПоФотоText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ПоискСайтаText.язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// Отказ по частоте: limit пришёл — «Не больше N поисков в час — попробуйте позже», нет — прежний текст
    /// «Много поисков подряд…» (ps_rate_limit). По-русски «21 поиска», «40 поисков», по-английски «1 search».
    static func часто(_ предел: Int?) -> String {
        guard let n = предел, n > 0 else { return ПоискСайтаText.т("ps_rate_limit") }
        let один: Bool
        switch ПоискСайтаText.язык {
        case "ru": один = n % 10 == 1 && n % 100 != 11
        case "en": один = n == 1
        default: один = false
        }
        return String(format: т(один ? "psi_rate_n1" : "psi_rate_n"), n)
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "psi_lvl_nocat": "В разделе «%@» не нашли — показываем из всех разделов",
            "psi_lvl_nocat_any": "В этом разделе не нашли — показываем из всех разделов",
            "psi_lvl_wide": "Рядом и в разделе не нашли — показываем по всему Казахстану из всех разделов",
            "psi_more": "Показать ещё",
            "psi_more_fail": "Не загрузилось — попробуйте ещё раз",
            "psi_loading_more": "Загружаем ещё…",
            "psi_rate_n": "Не больше %d поисков в час — попробуйте позже",
            "psi_rate_n1": "Не больше %d поиска в час — попробуйте позже"
        ],
        "kk": [
            "psi_lvl_nocat": "«%@» бөлімінен табылмады — барлық бөлімдерден көрсетеміз",
            "psi_lvl_nocat_any": "Бұл бөлімнен табылмады — барлық бөлімдерден көрсетеміз",
            "psi_lvl_wide": "Жақын жерден де, бөлімнен де табылмады — бүкіл Қазақстан бойынша барлық бөлімдерден көрсетеміз",
            "psi_more": "Тағы көрсету",
            "psi_more_fail": "Жүктелмеді — қайталап көріңіз",
            "psi_loading_more": "Тағы жүктеп жатырмыз…",
            "psi_rate_n": "Сағатына %d іздеуден артық емес — кейінірек көріңіз",
            "psi_rate_n1": "Сағатына %d іздеуден артық емес — кейінірек көріңіз"
        ],
        "en": [
            "psi_lvl_nocat": "Nothing in “%@” — showing results from all categories",
            "psi_lvl_nocat_any": "Nothing in this category — showing results from all categories",
            "psi_lvl_wide": "Nothing nearby or in the category — showing all of Kazakhstan, all categories",
            "psi_more": "Show more",
            "psi_more_fail": "Couldn't load — try again",
            "psi_loading_more": "Loading more…",
            "psi_rate_n": "No more than %d searches an hour — try again later",
            "psi_rate_n1": "No more than %d search an hour — try again later"
        ],
        "ar": [
            "psi_lvl_nocat": "لم نجد شيئًا في قسم «%@» — نعرض النتائج من كل الأقسام",
            "psi_lvl_nocat_any": "لم نجد شيئًا في هذا القسم — نعرض النتائج من كل الأقسام",
            "psi_lvl_wide": "لم نجد شيئًا بالقرب منك ولا في القسم — نعرض النتائج من كل كازاخستان ومن كل الأقسام",
            "psi_more": "عرض المزيد",
            "psi_more_fail": "تعذّر التحميل — حاول مجددًا",
            "psi_loading_more": "نحمّل المزيد…",
            "psi_rate_n": "لا يزيد عدد عمليات البحث عن %d في الساعة — حاول لاحقًا",
            "psi_rate_n1": "لا يزيد عدد عمليات البحث عن %d في الساعة — حاول لاحقًا"
        ]
    ]
}
