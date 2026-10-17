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

/**
 Тексты ОПИСАНИЯ «Продать своё» (владелец 17.10.2026: «подача с моих должен знать описание и прочее, чтобы связка
 работала как надо»; сборка — ЗаготовкаПодачи.описаниеИзМоего, PostingPrefill.swift). Ключи: prf_d_* — фразы, prf_l_* —
 подписи строк «Подпись: значение», prf_u_* — единицы, prf_v_* — значения словами. Язык — тот же, что у названия
 заготовки (ПримерочнаяText.язык: ru, kk, en, ar; прочие — русский), чтобы название и описание были на одном языке.
 Фразы с двумя значениями — номерами %1$@ и %2$@: порядок слов у языков разный.
 */
enum ТекстОписанияЗаготовки {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Строка с подстановкой: «Штатный размер для %@.», «Комплект из %1$@ шин %2$@».
    static func ф(_ ключ: String, _ аргументы: String...) -> String {
        let значения: [CVarArg] = аргументы.map { (а: String) -> CVarArg in а }
        return String(format: т(ключ), arguments: значения)
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
        "prf_d_ask": "Пишите в чат — отвечу на вопросы.",
        "prf_d_fits": "Штатный размер для %@.",
        "prf_d_size": "размер %@",
        "prf_d_tyres": "Комплект из %1$@ шин %2$@",
        "prf_d_rims": "Комплект из %1$@ дисков %2$@",
        "prf_d_kit": "%1$@, комплект %2$@",
        "prf_d_phone": "Смартфон %@",
        "prf_l_color": "Цвет",
        "prf_l_season": "Сезон",
        "prf_l_cpu": "Процессор",
        "prf_l_ram": "Оперативная память",
        "prf_l_storage": "Накопитель",
        "prf_l_gpu": "Видеокарта",
        "prf_l_diag": "Диагональ",
        "prf_l_socket": "Сокет",
        "prf_l_board": "Материнская плата",
        "prf_l_psu": "Блок питания",
        "prf_l_freq": "Частота",
        "prf_l_form": "Форм-фактор",
        "prf_l_iface": "Интерфейс",
        "prf_l_vram": "Видеопамять",
        "prf_l_length": "Длина",
        "prf_l_power": "Разъём питания",
        "prf_l_cert": "Сертификат",
        "prf_l_watts": "Мощность",
        "prf_l_dia": "Центральное отверстие (DIA)",
        "prf_l_width_j": "Ширина обода",
        "prf_l_vesa": "Крепление VESA",
        "prf_l_weight": "Вес",
        "prf_l_supply": "Расходники",
        "prf_l_bed": "Спальное место",
        "prf_l_mattress_h": "Высота матраса",
        "prf_l_mattress": "Тип матраса",
        "prf_u_gb": "ГБ",
        "prf_u_tb": "ТБ",
        "prf_u_mhz": "МГц",
        "prf_u_w": "Вт",
        "prf_u_mm": "мм",
        "prf_u_cm": "см",
        "prf_u_kg": "кг",
        "prf_v_igpu": "встроенная",
        "prf_v_soldered": "распаяна на плате"
    ]

    private static let kk: [String: String] = [
        "prf_d_ask": "Сұрақтарыңыз болса, чатқа жазыңыз.",
        "prf_d_fits": "%@ үшін зауыттық өлшем.",
        "prf_d_size": "өлшемі %@",
        "prf_d_tyres": "%2$@ шиналар жиынтығы, %1$@ дана",
        "prf_d_rims": "%2$@ дискілер жиынтығы, %1$@ дана",
        "prf_d_kit": "%1$@, жиынтық: %2$@",
        "prf_d_phone": "Смартфон %@",
        "prf_l_color": "Түсі",
        "prf_l_season": "Маусымы",
        "prf_l_cpu": "Процессор",
        "prf_l_ram": "Жедел жады",
        "prf_l_storage": "Жинақтағыш",
        "prf_l_gpu": "Бейнекарта",
        "prf_l_diag": "Диагоналі",
        "prf_l_socket": "Сокет",
        "prf_l_board": "Аналық плата",
        "prf_l_psu": "Қуат блогы",
        "prf_l_freq": "Жиілігі",
        "prf_l_form": "Форм-фактор",
        "prf_l_iface": "Интерфейс",
        "prf_l_vram": "Бейнежады",
        "prf_l_length": "Ұзындығы",
        "prf_l_power": "Қуат қосқышы",
        "prf_l_cert": "Сертификаты",
        "prf_l_watts": "Қуаты",
        "prf_l_dia": "Орталық тесік (DIA)",
        "prf_l_width_j": "Шеңбер ені",
        "prf_l_vesa": "VESA бекітпесі",
        "prf_l_weight": "Салмағы",
        "prf_l_supply": "Шығын материалдары",
        "prf_l_bed": "Ұйықтайтын орын",
        "prf_l_mattress_h": "Матрас биіктігі",
        "prf_l_mattress": "Матрас түрі",
        "prf_u_gb": "ГБ",
        "prf_u_tb": "ТБ",
        "prf_u_mhz": "МГц",
        "prf_u_w": "Вт",
        "prf_u_mm": "мм",
        "prf_u_cm": "см",
        "prf_u_kg": "кг",
        "prf_v_igpu": "кіріктірілген",
        "prf_v_soldered": "платаға дәнекерленген"
    ]

    private static let en: [String: String] = [
        "prf_d_ask": "Questions? Message me in the chat.",
        "prf_d_fits": "Factory size for %@.",
        "prf_d_size": "size %@",
        "prf_d_tyres": "Set of %1$@ tires %2$@",
        "prf_d_rims": "Set of %1$@ wheels %2$@",
        "prf_d_kit": "%1$@, kit of %2$@",
        "prf_d_phone": "Smartphone %@",
        "prf_l_color": "Color",
        "prf_l_season": "Season",
        "prf_l_cpu": "Processor",
        "prf_l_ram": "RAM",
        "prf_l_storage": "Storage",
        "prf_l_gpu": "Graphics card",
        "prf_l_diag": "Screen size",
        "prf_l_socket": "Socket",
        "prf_l_board": "Motherboard",
        "prf_l_psu": "Power supply",
        "prf_l_freq": "Speed",
        "prf_l_form": "Form factor",
        "prf_l_iface": "Interface",
        "prf_l_vram": "Video memory",
        "prf_l_length": "Length",
        "prf_l_power": "Power connector",
        "prf_l_cert": "Certification",
        "prf_l_watts": "Wattage",
        "prf_l_dia": "Center bore (DIA)",
        "prf_l_width_j": "Rim width",
        "prf_l_vesa": "VESA mount",
        "prf_l_weight": "Weight",
        "prf_l_supply": "Consumables",
        "prf_l_bed": "Sleeping area",
        "prf_l_mattress_h": "Mattress height",
        "prf_l_mattress": "Mattress type",
        "prf_u_gb": "GB",
        "prf_u_tb": "TB",
        "prf_u_mhz": "MHz",
        "prf_u_w": "W",
        "prf_u_mm": "mm",
        "prf_u_cm": "cm",
        "prf_u_kg": "kg",
        "prf_v_igpu": "integrated",
        "prf_v_soldered": "soldered to the board"
    ]

    private static let ar: [String: String] = [
        "prf_d_ask": "لأي استفسار، راسلني في المحادثة.",
        "prf_d_fits": "المقاس الأصلي لـ %@.",
        "prf_d_size": "المقاس %@",
        "prf_d_tyres": "طقم من %1$@ إطارات %2$@",
        "prf_d_rims": "طقم من %1$@ جنوط %2$@",
        "prf_d_kit": "%1$@، طقم %2$@",
        "prf_d_phone": "هاتف ذكي %@",
        "prf_l_color": "اللون",
        "prf_l_season": "الموسم",
        "prf_l_cpu": "المعالج",
        "prf_l_ram": "الذاكرة العشوائية",
        "prf_l_storage": "التخزين",
        "prf_l_gpu": "بطاقة الرسوميات",
        "prf_l_diag": "قياس الشاشة",
        "prf_l_socket": "المقبس",
        "prf_l_board": "اللوحة الأم",
        "prf_l_psu": "مزود الطاقة",
        "prf_l_freq": "التردد",
        "prf_l_form": "عامل الشكل",
        "prf_l_iface": "الواجهة",
        "prf_l_vram": "ذاكرة الفيديو",
        "prf_l_length": "الطول",
        "prf_l_power": "موصل الطاقة",
        "prf_l_cert": "الشهادة",
        "prf_l_watts": "القدرة",
        "prf_l_dia": "الثقب المركزي (DIA)",
        "prf_l_width_j": "عرض الجنط",
        "prf_l_vesa": "تثبيت VESA",
        "prf_l_weight": "الوزن",
        "prf_l_supply": "المستهلكات",
        "prf_l_bed": "مقاس السرير",
        "prf_l_mattress_h": "ارتفاع المرتبة",
        "prf_l_mattress": "نوع المرتبة",
        "prf_u_gb": "غيغابايت",
        "prf_u_tb": "تيرابايت",
        "prf_u_mhz": "ميغاهرتز",
        "prf_u_w": "واط",
        "prf_u_mm": "مم",
        "prf_u_cm": "سم",
        "prf_u_kg": "كغ",
        "prf_v_igpu": "مدمجة",
        "prf_v_soldered": "ملحومة باللوحة"
    ]
}
