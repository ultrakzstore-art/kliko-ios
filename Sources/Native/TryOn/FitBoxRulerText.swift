import Foundation

/**
 Тексты линейки в «Поместится ли?» (владелец 14.10.2026: «добавь линейку для габаритных вещей и главное чтобы он
 работал»). Ключи fr_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык).
 Свой файл и свой словарь — коробка живёт в ГабаритыText (FitBoxText.swift), общие слова («см», «Ширина», «Снимок»)
 берутся оттуда. Здесь же — запись длины: «62 см», «1 м 25 см», «2 м».
 */
enum ЛинейкаГабаритовText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Строка с подстановкой одного значения (%@).
    static func т(_ ключ: String, _ значение: String) -> String {
        String(format: т(ключ), значение)
    }

    /// Строка с подстановкой двух значений (%@ и %@).
    static func т(_ ключ: String, _ первое: String, _ второе: String) -> String {
        String(format: т(ключ), первое, второе)
    }

    /// Длина целыми сантиметрами: до метра — «62 см», от метра — «1 м 25 см» («2 м» без сантиметров).
    static func длина(_ см: Int) -> String {
        let всего = max(0, см)
        if всего < 100 { return String(всего) + " " + ГабаритыText.т("fb_cm") }
        let метры = всего / 100
        let остаток = всего % 100
        if остаток == 0 { return т("fr_m", String(метры)) }
        return т("fr_m_cm", String(метры), String(остаток))
    }

    /// Длина размера вещи: целое — как у замера; дробное до метра — одна цифра после запятой («60,5 см»).
    static func длина(_ см: Double) -> String {
        let округлено = (abs(см) * 10).rounded() / 10
        if округлено == округлено.rounded() || округлено >= 100 { return длина(Int(округлено.rounded())) }
        return ГабаритыВещи.число(округлено) + " " + ГабаритыText.т("fb_cm")
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
        "fr_mode_box": "Коробка",
        "fr_mode_ruler": "Линейка",
        "fr_mode_a11y": "Режим",
        "fr_mode_box_on": "Коробка: вещь настоящего размера в комнате",
        "fr_mode_ruler_on": "Линейка: наведите прицел и нажмите «+»",
        "fr_scan": "Медленно ведите телефоном",
        "fr_no_surface": "Наведите прицел на пол, стену или мебель",
        "fr_aim": "Наведите прицел на начало и нажмите «+»",
        "fr_aim_end": "Наведите на конец и нажмите «+»",
        "fr_aim_more": "Ещё отрезок: наведите на начало и нажмите «+»",
        "fr_add": "Поставить точку",
        "fr_add_end": "Поставить конец отрезка",
        "fr_start_done": "Начало отрезка поставлено",
        "fr_seg_done": "Отрезок: %@",
        "fr_too_short": "Слишком коротко — отведите прицел дальше",
        "fr_limit": "Отрезков слишком много — очистите лишние",
        "fr_undo": "Отменить",
        "fr_undo_a11y": "Отменить последнее",
        "fr_undone": "Начало отрезка убрано",
        "fr_seg_undone": "Отрезок %@ убран",
        "fr_clear": "Очистить",
        "fr_clear_a11y": "Убрать все отрезки",
        "fr_cleared": "Отрезки убраны",
        "fr_acc_lidar": "Точность ±1 см (лидар)",
        "fr_acc": "Точность ±2–4 см — оставьте запас",
        "fr_compare": "Сравнить с вещью",
        "fr_compare_hint": "Последний отрезок сравнится с размером вещи",
        "fr_auto": "Авто",
        "fr_door": "Проём двери",
        "fr_door_note": "Вещь можно пронести боком — сравниваем с меньшим из ширины и глубины",
        "fr_auto_note": "Авто: ближайший к замеру размер вещи — %@",
        "fr_dim_w": "ширина",
        "fr_dim_h": "высота",
        "fr_dim_d": "глубина",
        "fr_niche": "Ниша %@",
        "fr_opening": "Проём %@",
        "fr_item": "вещь %@",
        "fr_spare": "запас %@",
        "fr_short": "не хватает %@",
        "fr_fits": "Поместится",
        "fr_no_fit": "Не поместится",
        "fr_tight": "Впритык — запас меньше погрешности замера",
        "fr_measure_first": "Измерьте нишу или проём — сравним с вещью",
        "fr_scene_a11y": "Камера с линейкой",
        "fr_state_none": "Отрезков пока нет",
        "fr_state": "Отрезков: %@. Последний — %@",
        "fr_shot_a11y": "Сохранить или отправить кадр с отрезками",
        "fr_shot_img": "Снимок с замерами: %@",
        "fr_m": "%@ м",
        "fr_m_cm": "%@ м %@ см",
        "fr_item_dim": "вещь (%@) %@",
        "fr_no_dims": "Размеров вещи нет — работает линейка: померьте место",
        "fr_meas_title": "Измерить вещь",
        "fr_meas_w": "Ширина: наведите на один бок вещи и нажмите «+»",
        "fr_meas_h": "Высота: наведите на низ вещи (пол) и нажмите «+»",
        "fr_meas_d": "Глубина: наведите на переднюю сторону вещи и нажмите «+»",
        "fr_meas_ready": "Ширина, высота и глубина есть — нажмите «Готово»",
        "fr_meas_done_a11y": "Перенести замеры в объявление"
    ]

    private static let kk: [String: String] = [
        "fr_mode_box": "Қорап",
        "fr_mode_ruler": "Сызғыш",
        "fr_mode_a11y": "Режим",
        "fr_mode_box_on": "Қорап: бөлмедегі заттың нақты өлшемі",
        "fr_mode_ruler_on": "Сызғыш: көздеуішті бағыттап, «+» басыңыз",
        "fr_scan": "Телефонды баяу жылжытыңыз",
        "fr_no_surface": "Көздеуішті еденге, қабырғаға немесе жиһазға бағыттаңыз",
        "fr_aim": "Көздеуішті басына бағыттап, «+» басыңыз",
        "fr_aim_end": "Соңына бағыттап, «+» басыңыз",
        "fr_aim_more": "Тағы бір кесінді: басына бағыттап, «+» басыңыз",
        "fr_add": "Нүкте қою",
        "fr_add_end": "Кесінді соңын қою",
        "fr_start_done": "Кесінді басы қойылды",
        "fr_seg_done": "Кесінді: %@",
        "fr_too_short": "Тым қысқа — көздеуішті әрі апарыңыз",
        "fr_limit": "Кесінді тым көп — артығын тазалаңыз",
        "fr_undo": "Болдырмау",
        "fr_undo_a11y": "Соңғы әрекетті болдырмау",
        "fr_undone": "Кесінді басы алынды",
        "fr_seg_undone": "%@ кесінді алынды",
        "fr_clear": "Тазалау",
        "fr_clear_a11y": "Барлық кесіндіні алу",
        "fr_cleared": "Кесінділер алынды",
        "fr_acc_lidar": "Дәлдігі ±1 см (лидар)",
        "fr_acc": "Дәлдігі ±2–4 см — қор қалдырыңыз",
        "fr_compare": "Затпен салыстыру",
        "fr_compare_hint": "Соңғы кесінді зат өлшемімен салыстырылады",
        "fr_auto": "Авто",
        "fr_door": "Есік ойығы",
        "fr_door_note": "Затты бүйірімен өткізуге болады — ені мен тереңдігінің кішісімен салыстырамыз",
        "fr_auto_note": "Авто: өлшеуге ең жақын зат өлшемі — %@",
        "fr_dim_w": "ені",
        "fr_dim_h": "биіктігі",
        "fr_dim_d": "тереңдігі",
        "fr_niche": "Орын %@",
        "fr_opening": "Ойық %@",
        "fr_item": "зат %@",
        "fr_spare": "қор %@",
        "fr_short": "жетпейді %@",
        "fr_fits": "Сыяды",
        "fr_no_fit": "Сыймайды",
        "fr_tight": "Тап-тақ — қор өлшеу қателігінен аз",
        "fr_measure_first": "Орынды немесе ойықты өлшеңіз — затпен салыстырамыз",
        "fr_scene_a11y": "Сызғышы бар камера",
        "fr_state_none": "Әзірге кесінді жоқ",
        "fr_state": "Кесінділер: %@. Соңғысы — %@",
        "fr_shot_a11y": "Кесінділері бар кадрды сақтау немесе жіберу",
        "fr_shot_img": "Өлшемдері бар сурет: %@",
        "fr_m": "%@ м",
        "fr_m_cm": "%@ м %@ см",
        "fr_item_dim": "зат (%@) %@",
        "fr_no_dims": "Зат өлшемдері жоқ — сызғыш қосылды: орынды өлшеңіз",
        "fr_meas_title": "Затты өлшеу",
        "fr_meas_w": "Ені: заттың бір бүйіріне бағыттап, «+» басыңыз",
        "fr_meas_h": "Биіктігі: заттың төменгі жағына (еденге) бағыттап, «+» басыңыз",
        "fr_meas_d": "Тереңдігі: заттың алдыңғы жағына бағыттап, «+» басыңыз",
        "fr_meas_ready": "Ені, биіктігі және тереңдігі бар — «Дайын» басыңыз",
        "fr_meas_done_a11y": "Өлшемдерді хабарландыруға көшіру"
    ]

    private static let en: [String: String] = [
        "fr_mode_box": "Box",
        "fr_mode_ruler": "Ruler",
        "fr_mode_a11y": "Mode",
        "fr_mode_box_on": "Box: the item at true size in your room",
        "fr_mode_ruler_on": "Ruler: aim the crosshair and tap +",
        "fr_scan": "Move your phone slowly",
        "fr_no_surface": "Aim the crosshair at the floor, a wall or furniture",
        "fr_aim": "Aim at the start and tap +",
        "fr_aim_end": "Aim at the end and tap +",
        "fr_aim_more": "Another line: aim at the start and tap +",
        "fr_add": "Add point",
        "fr_add_end": "Add end point",
        "fr_start_done": "Start point added",
        "fr_seg_done": "Line: %@",
        "fr_too_short": "Too short — move the crosshair further",
        "fr_limit": "Too many lines — clear some",
        "fr_undo": "Undo",
        "fr_undo_a11y": "Undo the last step",
        "fr_undone": "Start point removed",
        "fr_seg_undone": "Line %@ removed",
        "fr_clear": "Clear",
        "fr_clear_a11y": "Remove all lines",
        "fr_cleared": "Lines removed",
        "fr_acc_lidar": "Accuracy ±1 cm (LiDAR)",
        "fr_acc": "Accuracy ±2–4 cm — leave some room",
        "fr_compare": "Compare with item",
        "fr_compare_hint": "The last line is compared with the item's size",
        "fr_auto": "Auto",
        "fr_door": "Doorway",
        "fr_door_note": "The item can be carried sideways — we compare with the smaller of width and depth",
        "fr_auto_note": "Auto: the item's dimension closest to the measurement — %@",
        "fr_dim_w": "width",
        "fr_dim_h": "height",
        "fr_dim_d": "depth",
        "fr_niche": "Space %@",
        "fr_opening": "Doorway %@",
        "fr_item": "item %@",
        "fr_spare": "%@ to spare",
        "fr_short": "%@ short",
        "fr_fits": "It fits",
        "fr_no_fit": "It won't fit",
        "fr_tight": "Tight — the margin is smaller than the measuring error",
        "fr_measure_first": "Measure the space or doorway to compare it with the item",
        "fr_scene_a11y": "Camera with a ruler",
        "fr_state_none": "No lines yet",
        "fr_state": "Lines: %@. Last — %@",
        "fr_shot_a11y": "Save or send a shot with the lines",
        "fr_shot_img": "Photo with measurements: %@",
        "fr_m": "%@ m",
        "fr_m_cm": "%@ m %@ cm",
        "fr_item_dim": "item (%@) %@",
        "fr_no_dims": "No item size — the ruler is on: measure the space",
        "fr_meas_title": "Measure the item",
        "fr_meas_w": "Width: aim at one side of the item and tap +",
        "fr_meas_h": "Height: aim at the bottom of the item (the floor) and tap +",
        "fr_meas_d": "Depth: aim at the front of the item and tap +",
        "fr_meas_ready": "Width, height and depth are measured — tap Done",
        "fr_meas_done_a11y": "Put the measurements into the listing"
    ]

    private static let ar: [String: String] = [
        "fr_mode_box": "الصندوق",
        "fr_mode_ruler": "المسطرة",
        "fr_mode_a11y": "الوضع",
        "fr_mode_box_on": "الصندوق: القطعة بحجمها الحقيقي في غرفتك",
        "fr_mode_ruler_on": "المسطرة: وجّه علامة التصويب واضغط +",
        "fr_scan": "حرّك هاتفك ببطء",
        "fr_no_surface": "وجّه علامة التصويب إلى الأرضية أو الجدار أو الأثاث",
        "fr_aim": "وجّه إلى نقطة البداية واضغط +",
        "fr_aim_end": "وجّه إلى نقطة النهاية واضغط +",
        "fr_aim_more": "خط آخر: وجّه إلى البداية واضغط +",
        "fr_add": "إضافة نقطة",
        "fr_add_end": "إضافة نقطة النهاية",
        "fr_start_done": "تمت إضافة نقطة البداية",
        "fr_seg_done": "الخط: %@",
        "fr_too_short": "قصير جدًا — حرّك علامة التصويب أبعد",
        "fr_limit": "الخطوط كثيرة — امسح بعضها",
        "fr_undo": "تراجع",
        "fr_undo_a11y": "التراجع عن آخر خطوة",
        "fr_undone": "تمت إزالة نقطة البداية",
        "fr_seg_undone": "تمت إزالة الخط %@",
        "fr_clear": "مسح",
        "fr_clear_a11y": "إزالة كل الخطوط",
        "fr_cleared": "تمت إزالة الخطوط",
        "fr_acc_lidar": "الدقة ±1 سم (ليدار)",
        "fr_acc": "الدقة ±2–4 سم — اترك هامشًا",
        "fr_compare": "قارن بالقطعة",
        "fr_compare_hint": "يُقارن آخر خط بمقاس القطعة",
        "fr_auto": "تلقائي",
        "fr_door": "فتحة الباب",
        "fr_door_note": "يمكن إدخال القطعة على جانبها — نقارن بالأصغر من العرض والعمق",
        "fr_auto_note": "تلقائي: أقرب مقاس للقطعة إلى القياس — %@",
        "fr_dim_w": "العرض",
        "fr_dim_h": "الارتفاع",
        "fr_dim_d": "العمق",
        "fr_niche": "المكان %@",
        "fr_opening": "الفتحة %@",
        "fr_item": "القطعة %@",
        "fr_spare": "هامش %@",
        "fr_short": "ينقص %@",
        "fr_fits": "ستتسع",
        "fr_no_fit": "لن تتسع",
        "fr_tight": "ضيق — الهامش أصغر من خطأ القياس",
        "fr_measure_first": "قِس المكان أو الفتحة لنقارنها بالقطعة",
        "fr_scene_a11y": "كاميرا مع مسطرة",
        "fr_state_none": "لا توجد خطوط بعد",
        "fr_state": "الخطوط: %@. الأخير — %@",
        "fr_shot_a11y": "احفظ أو أرسل لقطة مع الخطوط",
        "fr_shot_img": "صورة مع القياسات: %@",
        "fr_m": "%@ م",
        "fr_m_cm": "%@ م %@ سم",
        "fr_item_dim": "القطعة (%@) %@",
        "fr_no_dims": "لا توجد مقاسات للقطعة — المسطرة تعمل: قِس المكان",
        "fr_meas_title": "قياس القطعة",
        "fr_meas_w": "العرض: وجّه إلى أحد جانبي القطعة واضغط +",
        "fr_meas_h": "الارتفاع: وجّه إلى أسفل القطعة (الأرضية) واضغط +",
        "fr_meas_d": "العمق: وجّه إلى واجهة القطعة واضغط +",
        "fr_meas_ready": "تم قياس العرض والارتفاع والعمق — اضغط «تم»",
        "fr_meas_done_a11y": "نقل القياسات إلى الإعلان"
    ]
}
