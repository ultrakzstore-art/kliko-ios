import Foundation

/**
 Тексты пачки 83 «Новинки для моего» (docs/SERVER_NEW_FOR_MINE.md §3.5, §9, §10.3): «N новых» у полки «Для вас» и рядов
 «Подходит вам», чип «Новые», ряд «Проверьте» (вещи раздела, где размер или параметры не указаны), «Сверьте размер с
 продавцом» сверки по полю продавца, переключатель «Сообщать о новом» с согласием одной строкой, действие push
 «Не присылать для этого», вступление экрана при подборе на сервере. Ключи nm_*; языки ru, kk, en, ar, прочие — русский
 (язык — тот же, что у примерочной: ПримерочнаяText.язык). Прежние тексты «Для вас» — ДляВасText (ForYouText.swift),
 ряда — РядМоегоText (MyThingsFitRowText.swift): здесь не повторяются.
 */
enum НовинкиМоегоText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static func ф(_ ключ: String, _ аргументы: String...) -> String {
        String(format: т(ключ), arguments: аргументы.map { $0 as CVarArg })
    }

    /// «3 новых», «1 новое», «21 новое» (по-русски — число решает окончание); kk, en, ar — одна форма.
    static func сколькоНовых(_ число: Int) -> String {
        let остаток10: Int = число % 10
        let остаток100: Int = число % 100
        let одно: Bool = остаток10 == 1 && остаток100 != 11
        return ф(одно ? "nm_new_1" : "nm_new_n", String(число))
    }

    /// Согласие у переключателя: «не чаще раза в день» при одном push в сутки, иначе — «не чаще N раз в день».
    static func согласие(_ вСутки: Int) -> String {
        guard вСутки > 1 else { return т("nm_watch_consent_1") }
        return ф("nm_watch_consent_n", String(вСутки))
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
        "nm_new_1": "%@ новое",
        "nm_new_n": "%@ новых",
        "nm_new_chip": "Новые",
        "nm_new_a11y": "Новых с прошлого просмотра: %@",
        "nm_check_size": "Размер не указан — уточните у продавца",
        "nm_check_params": "Параметры не указаны — уточните у продавца",
        "nm_size_ask": "Сверьте размер с продавцом",
        "nm_row_check": "Может подойти",
        "nm_row_check_a11y": "В этих объявлениях размер или параметры не указаны — уточните у продавца",
        "nm_end_check": "Точных совпадений пока нет — размер уточните у продавца",
        "nm_watch": "Сообщать о новом",
        "nm_watch_consent_1": "Сообщать о новом, что подходит вашему «Моему», — не чаще раза в день и не ночью. На сервер уйдут только значения стандартов, город и адрес для уведомлений — без имени и аккаунта.",
        "nm_watch_consent_n": "Сообщать о новом, что подходит вашему «Моему», — не чаще %@ раз в день и не ночью. На сервер уйдут только значения стандартов, город и адрес для уведомлений — без имени и аккаунта.",
        "nm_watch_empty": "Пока не о чем сообщать — дополните «Моё»",
        "nm_watch_denied": "Уведомления выключены — включите их в Настройках iPhone",
        "nm_watch_dropped": "Часть «Моего» сервер пока не принимает — о ней не сообщим",
        "nm_watch_fail": "Не удалось сохранить — попробуем при следующем открытии",
        "nm_watch_stored": "Что хранится на сервере",
        "nm_watch_stored_t": "Хранится на сервере",
        "nm_watch_stored_none": "Ничего не хранится",
        "nm_watch_stored_exp": "Хранится до %@",
        "nm_ok": "Готово",
        "nm_st_car": "Машина",
        "nm_st_phone": "Телефон",
        "nm_st_laptop": "Ноутбук",
        "nm_st_size": "Размеры",
        "nm_st_std": "Стандарты",
        "nm_st_city": "Город",
        "nm_push_off": "Не присылать для этого",
        "nm_lead_server": "Сверили с тем, что вы указали в «Моём». На сервер уходят только значения стандартов, без имени. Реклама — только подходящая и с пометкой."
    ]

    private static let kk: [String: String] = [
        "nm_new_1": "%@ жаңа",
        "nm_new_n": "%@ жаңа",
        "nm_new_chip": "Жаңа",
        "nm_new_a11y": "Соңғы қараудан бері жаңасы: %@",
        "nm_check_size": "Өлшемі көрсетілмеген — сатушыдан нақтылаңыз",
        "nm_check_params": "Параметрлері көрсетілмеген — сатушыдан нақтылаңыз",
        "nm_size_ask": "Өлшемді сатушымен нақтылаңыз",
        "nm_row_check": "Сай келуі мүмкін",
        "nm_row_check_a11y": "Бұл хабарландыруларда өлшем не параметрлер көрсетілмеген — сатушыдан нақтылаңыз",
        "nm_end_check": "Дәл сәйкестік әзірге жоқ — өлшемді сатушыдан нақтылаңыз",
        "nm_watch": "Жаңасы туралы хабарлау",
        "nm_watch_consent_1": "«Менікі» бөліміне сай жаңасы туралы хабарлау — күніне бір реттен жиі емес және түнде емес. Серверге тек стандарт мәндері, қала және хабарлама мекенжайы жіберіледі — атыңыз бен аккаунтсыз.",
        "nm_watch_consent_n": "«Менікі» бөліміне сай жаңасы туралы хабарлау — күніне %@ реттен жиі емес және түнде емес. Серверге тек стандарт мәндері, қала және хабарлама мекенжайы жіберіледі — атыңыз бен аккаунтсыз.",
        "nm_watch_empty": "Әзірге хабарлайтын ештеңе жоқ — «Менікі» бөлімін толықтырыңыз",
        "nm_watch_denied": "Хабарламалар өшірулі — оларды iPhone баптауларында қосыңыз",
        "nm_watch_dropped": "«Менікі» бөлімінің бір бөлігін сервер әзірге қабылдамайды — ол туралы хабарламаймыз",
        "nm_watch_fail": "Сақтау мүмкін болмады — келесі ашқанда қайталаймыз",
        "nm_watch_stored": "Серверде не сақталады",
        "nm_watch_stored_t": "Серверде сақталғаны",
        "nm_watch_stored_none": "Ештеңе сақталмаған",
        "nm_watch_stored_exp": "%@ дейін сақталады",
        "nm_ok": "Дайын",
        "nm_st_car": "Көлік",
        "nm_st_phone": "Телефон",
        "nm_st_laptop": "Ноутбук",
        "nm_st_size": "Өлшемдер",
        "nm_st_std": "Стандарттар",
        "nm_st_city": "Қала",
        "nm_push_off": "Бұл үшін жібермеу",
        "nm_lead_server": "«Менікі» бөлімінде көрсеткеніңізбен салыстырдық. Серверге тек стандарт мәндері жіберіледі, атыңызсыз. Жарнама — тек сай келетіні және белгісімен."
    ]

    private static let en: [String: String] = [
        "nm_new_1": "%@ new",
        "nm_new_n": "%@ new",
        "nm_new_chip": "New",
        "nm_new_a11y": "New since your last visit: %@",
        "nm_check_size": "Size not listed — ask the seller",
        "nm_check_params": "Specs not listed — ask the seller",
        "nm_size_ask": "Check the size with the seller",
        "nm_row_check": "Might fit",
        "nm_row_check_a11y": "These listings don’t state a size or specs — ask the seller",
        "nm_end_check": "No exact matches yet — check the size with the seller",
        "nm_watch": "Notify me about new items",
        "nm_watch_consent_1": "Notify me about new items that fit My Things — at most once a day and never at night. Only standard values, your city and a notification address go to the server — no name or account.",
        "nm_watch_consent_n": "Notify me about new items that fit My Things — at most %@ times a day and never at night. Only standard values, your city and a notification address go to the server — no name or account.",
        "nm_watch_empty": "Nothing to notify you about yet — add to My Things",
        "nm_watch_denied": "Notifications are off — turn them on in iPhone Settings",
        "nm_watch_dropped": "The server doesn’t accept part of My Things yet — we won’t notify you about it",
        "nm_watch_fail": "Couldn’t save — we’ll try again next time you open the app",
        "nm_watch_stored": "What’s stored on the server",
        "nm_watch_stored_t": "Stored on the server",
        "nm_watch_stored_none": "Nothing is stored",
        "nm_watch_stored_exp": "Stored until %@",
        "nm_ok": "Done",
        "nm_st_car": "Car",
        "nm_st_phone": "Phone",
        "nm_st_laptop": "Laptop",
        "nm_st_size": "Sizes",
        "nm_st_std": "Standards",
        "nm_st_city": "City",
        "nm_push_off": "Don’t send for this",
        "nm_lead_server": "Checked against what you added to My Things. Only standard values go to the server, without your name. Ads — only ones that fit, and labelled."
    ]

    private static let ar: [String: String] = [
        "nm_new_1": "%@ جديد",
        "nm_new_n": "%@ جديد",
        "nm_new_chip": "الجديدة",
        "nm_new_a11y": "الجديد منذ آخر زيارة: %@",
        "nm_check_size": "المقاس غير مذكور — اسأل البائع",
        "nm_check_params": "المواصفات غير مذكورة — اسأل البائع",
        "nm_size_ask": "تحقق من المقاس مع البائع",
        "nm_row_check": "قد يناسب",
        "nm_row_check_a11y": "لا تذكر هذه الإعلانات المقاس أو المواصفات — اسأل البائع",
        "nm_end_check": "لا توجد مطابقات دقيقة بعد — تحقّق من المقاس مع البائع",
        "nm_watch": "أبلغني بالجديد",
        "nm_watch_consent_1": "أبلغني بالجديد الذي يناسب «أشيائي» — مرة في اليوم على الأكثر وليس ليلًا. لا يُرسل إلى الخادم إلا قيم المعايير والمدينة وعنوان الإشعارات — بلا اسم ولا حساب.",
        "nm_watch_consent_n": "أبلغني بالجديد الذي يناسب «أشيائي» — %@ مرات في اليوم على الأكثر وليس ليلًا. لا يُرسل إلى الخادم إلا قيم المعايير والمدينة وعنوان الإشعارات — بلا اسم ولا حساب.",
        "nm_watch_empty": "لا شيء للإبلاغ عنه بعد — أكمل «أشيائي»",
        "nm_watch_denied": "الإشعارات متوقفة — فعّلها في إعدادات iPhone",
        "nm_watch_dropped": "لا يقبل الخادم جزءًا من «أشيائي» بعد — لن نبلغك عنه",
        "nm_watch_fail": "تعذّر الحفظ — سنحاول عند الفتح التالي",
        "nm_watch_stored": "ما المحفوظ على الخادم",
        "nm_watch_stored_t": "المحفوظ على الخادم",
        "nm_watch_stored_none": "لا شيء محفوظ",
        "nm_watch_stored_exp": "محفوظ حتى %@",
        "nm_ok": "تم",
        "nm_st_car": "السيارة",
        "nm_st_phone": "الهاتف",
        "nm_st_laptop": "الحاسوب المحمول",
        "nm_st_size": "المقاسات",
        "nm_st_std": "المعايير",
        "nm_st_city": "المدينة",
        "nm_push_off": "لا ترسل لهذا",
        "nm_lead_server": "طابقنا مع ما أضفته إلى «أشيائي». لا يُرسل إلى الخادم إلا قيم المعايير، بلا اسم. الإعلانات — المناسبة فقط ومع علامة."
    ]
}
