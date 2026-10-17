import Foundation

/**
 Тексты «Для вас» — полка на главной и экран целиком (ForYouViews.swift), причины плашек, которых нет у стандартов
 (fv_laptop). Ключи fv_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной:
 ПримерочнаяText.язык). Строки с %@ идут через String(format:) — ф(_:_:). Причины по «Моему» («Для вашей %@», «Ваш
 размер %@», «Для кровати %@») — у стандартов (fy_*, StandardsText.swift), здесь не повторяются. Ни цен, ни покупок.
 */
enum ДляВасText {
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
        "fv_title": "Для вас",
        "fv_line": "Подобрано на телефоне по «Моему»",
        "fv_hide": "Скрыть",
        "fv_hidden_a11y": "Подборка «Для вас» скрыта. Вернётся, когда в «Моём» появится новое",
        "fv_lead": "Сверили на этом телефоне с тем, что вы указали в «Моём». Данные «Моего» никуда не уходят, реклама сюда не подмешивается.",
        "fv_lead_server": "Подобрали по тому, что вы указали в «Моём»: для отбора на сервер ушли только значения стандартов — без имени и аккаунта, там они не сохраняются. Реклама сюда не подмешивается.",
        "fv_all": "Все",
        "fv_g_car": "Машина",
        "fv_g_devices": "Устройства",
        "fv_g_home": "Дом",
        "fv_g_pc": "Компьютер",
        "fv_g_wear": "Одежда",
        "fv_end": "Это всё, что подходит сейчас",
        "fv_end_sub": "Обновим через 15 минут — или сразу, когда добавите новое в «Моё»",
        "fv_more": "Дополнить «Моё»",
        "fv_menu": "Ещё",
        "fv_menu_hide": "Скрыть с главной",
        "fv_hide_t": "Скрыть «Для вас» с главной?",
        "fv_hide_m": "Подборка вернётся, когда в «Моём» появится новое.",
        "fv_cancel": "Отмена",
        "fv_close": "Закрыть",
        "fv_loading": "Подбираем…",
        "fv_none": "Пока ничего не подошло",
        "fv_none_sub": "Сверили свежие объявления — подходящих нет. Заглянем снова через 15 минут.",
        "fv_fail": "Не удалось загрузить — потяните вниз, чтобы повторить",
        "fv_laptop": "Для ноутбука %@",
        "fv_part": "Нужна деталь: %@",
        "fv_color_a11y": "сочетается с вашими вещами цвета «%@»"
    ]

    private static let kk: [String: String] = [
        "fv_title": "Сізге",
        "fv_line": "«Менікі» бойынша телефонда іріктелді",
        "fv_hide": "Жасыру",
        "fv_hidden_a11y": "«Сізге» іріктемесі жасырылды. «Менікі» бөлімінде жаңа нәрсе пайда болғанда қайтады",
        "fv_lead": "«Менікі» бөлімінде көрсеткеніңізбен осы телефонда салыстырдық. «Менікі» деректері ешқайда жіберілмейді, мұнда жарнама қосылмайды.",
        "fv_lead_server": "«Менікі» бөлімінде көрсеткеніңіз бойынша іріктедік: іріктеу үшін серверге тек стандарт мәндері жіберілді — атыңыз бен аккаунтыңызсыз, онда сақталмайды. Мұнда жарнама қосылмайды.",
        "fv_all": "Барлығы",
        "fv_g_car": "Көлік",
        "fv_g_devices": "Құрылғылар",
        "fv_g_home": "Үй",
        "fv_g_pc": "Компьютер",
        "fv_g_wear": "Киім",
        "fv_end": "Қазір сай келетіннің бәрі осы",
        "fv_end_sub": "15 минуттан кейін жаңартамыз — не «Менікі» бөліміне жаңа нәрсе қосқанда бірден",
        "fv_more": "«Менікі» бөлімін толықтыру",
        "fv_menu": "Тағы",
        "fv_menu_hide": "Басты беттен жасыру",
        "fv_hide_t": "«Сізге» іріктемесін басты беттен жасыру керек пе?",
        "fv_hide_m": "«Менікі» бөлімінде жаңа нәрсе пайда болғанда іріктеме қайтады.",
        "fv_cancel": "Бас тарту",
        "fv_close": "Жабу",
        "fv_loading": "Іріктеп жатырмыз…",
        "fv_none": "Әзірге ештеңе сай келмеді",
        "fv_none_sub": "Жаңа хабарландыруларды салыстырдық — сайы жоқ. 15 минуттан кейін қайта қараймыз.",
        "fv_fail": "Жүктеу мүмкін болмады — қайталау үшін төмен тартыңыз",
        "fv_laptop": "%@ ноутбукқа",
        "fv_part": "Бөлшек керек: %@",
        "fv_color_a11y": "«%@» түсті заттарыңызбен үйлеседі"
    ]

    private static let en: [String: String] = [
        "fv_title": "For you",
        "fv_line": "Picked on your phone from My Things",
        "fv_hide": "Hide",
        "fv_hidden_a11y": "For you is hidden. It comes back when you add something new to My Things",
        "fv_lead": "Checked on this phone against what you added to My Things. Nothing from My Things leaves your phone, and no ads are mixed in.",
        "fv_lead_server": "Picked using what you added to My Things: only standard values were sent to the server for matching — without your name or account, and they aren’t stored there. No ads are mixed in.",
        "fv_all": "All",
        "fv_g_car": "Car",
        "fv_g_devices": "Devices",
        "fv_g_home": "Home",
        "fv_g_pc": "Computer",
        "fv_g_wear": "Clothes",
        "fv_end": "That’s everything that fits right now",
        "fv_end_sub": "We’ll refresh in 15 minutes — or right away when you add something to My Things",
        "fv_more": "Add to My Things",
        "fv_menu": "More",
        "fv_menu_hide": "Hide from Home",
        "fv_hide_t": "Hide For you from Home?",
        "fv_hide_m": "It comes back when you add something new to My Things.",
        "fv_cancel": "Cancel",
        "fv_close": "Close",
        "fv_loading": "Picking…",
        "fv_none": "Nothing fits yet",
        "fv_none_sub": "We checked the latest listings — none fit. We’ll look again in 15 minutes.",
        "fv_fail": "Couldn’t load — pull down to retry",
        "fv_laptop": "For a %@ laptop",
        "fv_part": "Needs a part: %@",
        "fv_color_a11y": "goes with your “%@” items"
    ]

    private static let ar: [String: String] = [
        "fv_title": "لك",
        "fv_line": "اختيرت على هاتفك وفق «أشيائي»",
        "fv_hide": "إخفاء",
        "fv_hidden_a11y": "أُخفيت «لك». ستعود عند إضافة شيء جديد إلى «أشيائي»",
        "fv_lead": "طابقنا على هذا الهاتف مع ما أضفته إلى «أشيائي». لا تغادر بيانات «أشيائي» هاتفك، ولا تُضاف إعلانات هنا.",
        "fv_lead_server": "اخترنا وفق ما أضفته إلى «أشيائي»: لم يُرسل إلى الخادم للمطابقة إلا قيم المعايير — بلا اسمك أو حسابك، ولا تُحفظ هناك. ولا تُضاف إعلانات هنا.",
        "fv_all": "الكل",
        "fv_g_car": "السيارة",
        "fv_g_devices": "الأجهزة",
        "fv_g_home": "المنزل",
        "fv_g_pc": "الحاسوب",
        "fv_g_wear": "الملابس",
        "fv_end": "هذا كل ما يناسب الآن",
        "fv_end_sub": "سنحدّث بعد 15 دقيقة — أو فورًا عند إضافة شيء جديد إلى «أشيائي»",
        "fv_more": "أكمل «أشيائي»",
        "fv_menu": "المزيد",
        "fv_menu_hide": "إخفاء من الرئيسية",
        "fv_hide_t": "إخفاء «لك» من الرئيسية؟",
        "fv_hide_m": "ستعود عند إضافة شيء جديد إلى «أشيائي».",
        "fv_cancel": "إلغاء",
        "fv_close": "إغلاق",
        "fv_loading": "نختار…",
        "fv_none": "لا شيء مناسب بعد",
        "fv_none_sub": "طابقنا أحدث الإعلانات — لا يوجد ما يناسب. سنعيد البحث بعد 15 دقيقة.",
        "fv_fail": "تعذّر التحميل — اسحب للأسفل لإعادة المحاولة",
        "fv_laptop": "لحاسوب %@",
        "fv_part": "يلزم جزء: %@",
        "fv_color_a11y": "يتناسق مع أغراضك بلون «%@»"
    ]
}
