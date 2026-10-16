import Foundation

/**
 Тексты «Подходит моему» — плашка на странице объявления и чип «Для моего» в ленте (MyThingsMatch.swift). Ключи mf_*;
 языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык). Строки с %@ идут
 через String(format:) — ф(_:_:). Ни цен, ни покупок.
 */
enum МоёСверкаText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static func ф(_ ключ: String, _ аргументы: String...) -> String {
        String(format: т(ключ), arguments: аргументы.map { $0 as CVarArg })
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
        "mf_car_sub": "Сверили с вашей машиной: %@",
        "mf_car_need": "Нужны параметры колёс вашей машины",
        "mf_car_add": "Добавьте машину в «Моё»",
        "mf_car_add_sub": "Сразу покажем, подойдут ли эти шины или диски",
        "mf_phone_ok": "Подходит вашему телефону ✓",
        "mf_phone_check": "Проверьте модель телефона",
        "mf_phone_sub": "Ваш телефон: %@",
        "mf_phone_check_sub": "В названии нет «%@» — уточните у продавца",
        "mf_phone_add": "Укажите свой телефон в «Моё»",
        "mf_phone_add_sub": "Сверим чехлы и стёкла с вашей моделью",
        "mf_laptop_ok": "Ваш ноутбук поместится ✓",
        "mf_laptop_bad": "Ваш ноутбук не поместится",
        "mf_laptop_sub": "Здесь — на %@, ваш ноутбук — %@",
        "mf_laptop_add": "Укажите ноутбук в «Моё»",
        "mf_laptop_add_sub": "Сверим, поместится ли он в эту сумку или рюкзак",
        "mf_size_ok": "Ваш размер ✓",
        "mf_size_half": "Отличается на полразмера",
        "mf_size_bad": "Не ваш размер",
        "mf_size_check": "Основной размер совпал — сверьте второй",
        "mf_size_sub": "Здесь %@ — ваш %@",
        "mf_size_add": "Укажите свой размер в «Моё»",
        "mf_size_add_sub": "Покажем, ваш ли это размер, — в вашей системе",
        "mf_by_desc": "Проверили по описанию объявления",
        "mf_open": "Откроет подробности",
        "mf_chip": "Для моего",
        "mf_chip_a11y": "Показать то, что подходит вашему из «Моего»: проверяем по описанию загруженных объявлений"
    ]

    private static let kk: [String: String] = [
        "mf_car_sub": "Көлігіңізбен салыстырдық: %@",
        "mf_car_need": "Көлігіңіздің дөңгелек параметрлері керек",
        "mf_car_add": "Көлікті «Менікі» бөліміне қосыңыз",
        "mf_car_add_sub": "Бұл шиналар мен дискілер келетінін бірден көрсетеміз",
        "mf_phone_ok": "Телефоныңызға сәйкес келеді ✓",
        "mf_phone_check": "Телефон үлгісін тексеріңіз",
        "mf_phone_sub": "Телефоныңыз: %@",
        "mf_phone_check_sub": "Атауында «%@» жоқ — сатушыдан нақтылаңыз",
        "mf_phone_add": "Телефоныңызды «Менікі» бөлімінде көрсетіңіз",
        "mf_phone_add_sub": "Қаптар мен шыныларды үлгіңізбен салыстырамыз",
        "mf_laptop_ok": "Ноутбугыңыз сыяды ✓",
        "mf_laptop_bad": "Ноутбугыңыз сыймайды",
        "mf_laptop_sub": "Мұнда — %@ үшін, ноутбугыңыз — %@",
        "mf_laptop_add": "Ноутбукты «Менікі» бөлімінде көрсетіңіз",
        "mf_laptop_add_sub": "Оның осы сөмкеге не рюкзакқа сыятынын тексереміз",
        "mf_size_ok": "Сіздің өлшеміңіз ✓",
        "mf_size_half": "Жарты өлшемге өзгеше",
        "mf_size_bad": "Сіздің өлшеміңіз емес",
        "mf_size_check": "Негізгі өлшем сәйкес — екіншісін тексеріңіз",
        "mf_size_sub": "Мұнда %@ — сіздікі %@",
        "mf_size_add": "Өлшеміңізді «Менікі» бөлімінде көрсетіңіз",
        "mf_size_add_sub": "Бұл сіздің өлшеміңіз бе — өз жүйеңізде көрсетеміз",
        "mf_by_desc": "Хабарландыру сипаттамасы бойынша тексердік",
        "mf_open": "Толығырақ ашылады",
        "mf_chip": "Маған лайық",
        "mf_chip_a11y": "«Менікі» бойынша сізге келетінін көрсету: жүктелген хабарландырулардың сипаттамасы бойынша тексереміз"
    ]

    private static let en: [String: String] = [
        "mf_car_sub": "Checked against your car: %@",
        "mf_car_need": "Your car's wheel specs are needed",
        "mf_car_add": "Add your car to My Things",
        "mf_car_add_sub": "We'll show right away whether these tires or wheels fit",
        "mf_phone_ok": "Fits your phone ✓",
        "mf_phone_check": "Check the phone model",
        "mf_phone_sub": "Your phone: %@",
        "mf_phone_check_sub": "The title doesn't mention “%@” — ask the seller",
        "mf_phone_add": "Add your phone to My Things",
        "mf_phone_add_sub": "We'll check cases and screen protectors against your model",
        "mf_laptop_ok": "Your laptop will fit ✓",
        "mf_laptop_bad": "Your laptop won't fit",
        "mf_laptop_sub": "This one is for %@, your laptop is %@",
        "mf_laptop_add": "Add your laptop to My Things",
        "mf_laptop_add_sub": "We'll check whether it fits this bag or backpack",
        "mf_size_ok": "Your size ✓",
        "mf_size_half": "Half a size off",
        "mf_size_bad": "Not your size",
        "mf_size_check": "The main size matches — check the second one",
        "mf_size_sub": "This is %@ — yours is %@",
        "mf_size_add": "Add your size to My Things",
        "mf_size_add_sub": "We'll show whether it's your size — in your own system",
        "mf_by_desc": "Checked against the listing's description",
        "mf_open": "Opens details",
        "mf_chip": "Fits mine",
        "mf_chip_a11y": "Show what fits your My Things: we check the descriptions of loaded listings"
    ]

    private static let ar: [String: String] = [
        "mf_car_sub": "تمت المقارنة مع سيارتك: %@",
        "mf_car_need": "نحتاج مواصفات عجلات سيارتك",
        "mf_car_add": "أضف سيارتك إلى «أشيائي»",
        "mf_car_add_sub": "سنُظهر فورًا ما إذا كانت هذه الإطارات أو الجنوط مناسبة",
        "mf_phone_ok": "يناسب هاتفك ✓",
        "mf_phone_check": "تحقّق من طراز الهاتف",
        "mf_phone_sub": "هاتفك: %@",
        "mf_phone_check_sub": "لا يذكر العنوان «%@» — اسأل البائع",
        "mf_phone_add": "أضف هاتفك إلى «أشيائي»",
        "mf_phone_add_sub": "سنطابق الأغطية وواقيات الشاشة مع طرازك",
        "mf_laptop_ok": "سيتسع حاسوبك المحمول ✓",
        "mf_laptop_bad": "لن يتسع حاسوبك المحمول",
        "mf_laptop_sub": "هذه لمقاس %@، وحاسوبك %@",
        "mf_laptop_add": "أضف حاسوبك المحمول إلى «أشيائي»",
        "mf_laptop_add_sub": "سنتحقق مما إذا كان يتسع في هذه الحقيبة أو حقيبة الظهر",
        "mf_size_ok": "مقاسك ✓",
        "mf_size_half": "يختلف بنصف مقاس",
        "mf_size_bad": "ليس مقاسك",
        "mf_size_check": "المقاس الأساسي مطابق — تحقّق من الثاني",
        "mf_size_sub": "هنا %@ — ومقاسك %@",
        "mf_size_add": "أضف مقاسك إلى «أشيائي»",
        "mf_size_add_sub": "سنُظهر ما إذا كان هذا مقاسك — بنظامك أنت",
        "mf_by_desc": "تحققنا وفق وصف الإعلان",
        "mf_open": "يفتح التفاصيل",
        "mf_chip": "يناسب ما لدي",
        "mf_chip_a11y": "عرض ما يناسب «أشيائي»: نتحقق من أوصاف الإعلانات المحمّلة"
    ]
}
