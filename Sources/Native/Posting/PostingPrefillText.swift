import Foundation

/// Тексты заготовки подачи «Продать своё» (PostingPrefill.swift) на языке телефона (kk/ru/en/ar) — тем же способом,
/// что тексты подачи (ПодачаText): свой словарь, ключи prf_*, чтобы не пересекаться с другими направлениями.
enum ЗаготовкаПодачиText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "prf_filled": "Заполнили из «Моего» — добавьте фото и цену",
            "prf_filled_photo": "Заполнили из «Моего» — фото вещи добавит кнопка ниже, останется цена",
            "prf_add_photo": "Добавить фото вещи из «Моего»"
        ],
        "kk": [
            "prf_filled": "«Менікі» бөлімінен толтырдық — сурет пен баға қосыңыз",
            "prf_filled_photo": "«Менікі» бөлімінен толтырдық — заттың суретін төмендегі түйме қосады, бағасы қалды",
            "prf_add_photo": "«Менікі» бөлімінен заттың суретін қосу"
        ],
        "en": [
            "prf_filled": "Filled in from My Things — add photos and a price",
            "prf_filled_photo": "Filled in from My Things — add the item photo with the button below, then the price",
            "prf_add_photo": "Add the item photo from My Things"
        ],
        "ar": [
            "prf_filled": "تمت التعبئة من «أشيائي» — أضف صورًا وسعرًا",
            "prf_filled_photo": "تمت التعبئة من «أشيائي» — أضف صورة الغرض بالزر أدناه، ثم السعر",
            "prf_add_photo": "أضف صورة الغرض من «أشيائي»"
        ]
    ]
}
