import Foundation

/// Тексты сравнения объявлений (этап 20) на языке телефона (kk/ru/en/ar) — тем же способом, что избранное.
enum CompareText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["compare": "Сравнить", "done": "Готово", "pick": "Выберите 2–3 объявления",
               "picked": "Выбрано: %d из 3", "max": "Сравнить можно не больше трёх",
               "show": "Показать сравнение", "select_hint": "Выбрать для сравнения",
               "title": "Сравнение", "price": "Цена", "old_price": "Старая цена", "city": "Город",
               "condition": "Состояние", "warranty": "Гарантия", "days": "%d дн.",
               "note": "Характеристики и гарантия — из сохранённых на телефоне карточек. У объявления без сохранённой карточки их нет: откройте его, и они появятся."],
        "kk": ["compare": "Салыстыру", "done": "Дайын", "pick": "2–3 хабарландыру таңдаңыз",
               "picked": "Таңдалды: %d / 3", "max": "Үштен артық салыстыруға болмайды",
               "show": "Салыстыруды көрсету", "select_hint": "Салыстыру үшін таңдау",
               "title": "Салыстыру", "price": "Бағасы", "old_price": "Бұрынғы бағасы", "city": "Қала",
               "condition": "Күйі", "warranty": "Кепілдік", "days": "%d күн",
               "note": "Сипаттамалар мен кепілдік телефонда сақталған карточкалардан алынады. Сақталған карточкасы жоқ хабарландыруда олар жоқ: оны ашыңыз, сонда пайда болады."],
        "en": ["compare": "Compare", "done": "Done", "pick": "Select 2–3 listings",
               "picked": "Selected: %d of 3", "max": "You can compare up to three",
               "show": "Show comparison", "select_hint": "Select for comparison",
               "title": "Comparison", "price": "Price", "old_price": "Old price", "city": "City",
               "condition": "Condition", "warranty": "Warranty", "days": "%d days",
               "note": "Specifications and warranty come from listings saved on this phone. A listing that hasn't been saved has none yet — open it and they'll appear."],
        "ar": ["compare": "مقارنة", "done": "تم", "pick": "اختر إعلانين أو ثلاثة",
               "picked": "المحدد: %d من 3", "max": "يمكن مقارنة ثلاثة إعلانات كحد أقصى",
               "show": "عرض المقارنة", "select_hint": "تحديد للمقارنة",
               "title": "المقارنة", "price": "السعر", "old_price": "السعر السابق", "city": "المدينة",
               "condition": "الحالة", "warranty": "الضمان", "days": "%d يوم",
               "note": "المواصفات والضمان مأخوذة من الإعلانات المحفوظة على هذا الهاتف. الإعلان غير المحفوظ ليست له مواصفات بعد — افتحه وستظهر."]
    ]
}
