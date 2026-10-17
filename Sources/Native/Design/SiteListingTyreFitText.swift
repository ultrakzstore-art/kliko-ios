import Foundation

/**
 Тексты строки «Подойдут ли?» окна объявления шин и дисков (пачка 83, D2, SiteListingTyreFit.swift). Ключи tf_*; языки
 ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной и окна «Подойдут ли?»: ПримерочнаяText.язык). Строки
 с %@ идут через String(format:). Итог сверки («Подходят», «Нужны параметры колёс…») — тексты сверки «Моего»
 (МоёСверкаText), здесь только то, что до неё.
 */
enum ПодойдутЛиText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var словарь: [String: String] {
        switch ПримерочнаяText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "tf_title": "Подойдут ли?",
        "tf_pick": "Выберите машину — сверим размер, разболтовку и вылет",
        "tf_with": "Сверим с вашей машиной: %@",
        "tf_hint": "Откроет «Подойдут ли?» — там же можно выбрать или сменить машину"
    ]

    private static let kk: [String: String] = [
        "tf_title": "Сәйкес келе ме?",
        "tf_pick": "Көлікті таңдаңыз — өлшемді, PCD мен ET-ні салыстырамыз",
        "tf_with": "Көлігіңізбен салыстырамыз: %@",
        "tf_hint": "«Сәйкес келе ме?» ашылады — көлікті сонда таңдауға не ауыстыруға болады"
    ]

    private static let en: [String: String] = [
        "tf_title": "Will they fit?",
        "tf_pick": "Choose your car — we’ll check size, bolt pattern and offset",
        "tf_with": "We’ll check against your car: %@",
        "tf_hint": "Opens “Will they fit?” — you can choose or change the car there"
    ]

    private static let ar: [String: String] = [
        "tf_title": "هل تناسب سيارتي؟",
        "tf_pick": "اختر سيارتك — سنطابق المقاس وتوزيع البراغي والإزاحة",
        "tf_with": "سنطابقها مع سيارتك: %@",
        "tf_hint": "يفتح «هل تناسب سيارتي؟» — ويمكنك هناك اختيار السيارة أو تغييرها"
    ]
}
