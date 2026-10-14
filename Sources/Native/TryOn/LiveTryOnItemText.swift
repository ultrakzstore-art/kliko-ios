import Foundation

/**
 Тексты шага «Вещь» живой примерки и рамки «Обрезать вручную» (владелец 14.10.2026: «через студию для примерочной должен
 обрезаться»). Ключи lw_*; языки ru, kk, en, ar, прочие — русский. Свой файл и свой словарь — общие строки экрана
 (закрыть, «Отделяем вещь от фона…», «Повторить», ошибки вырезки) берутся из ЖиваяПримеркаText.
 */
enum ВещьЖивойПримеркиText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var словарь: [String: String] {
        switch ЖиваяПримеркаText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "lw_title": "Вещь для примерки",
        "lw_ready": "Вещь отделена от фона — можно примерять",
        "lw_ready_manual": "Вещь вырезана по вашей рамке",
        "lw_fail_hint": "Выберите другое фото или обрежьте вещь вручную",
        "lw_fail_hint_one": "Обрежьте вещь вручную — рамкой по фото",
        "lw_try": "Примерить",
        "lw_crop": "Обрезать вручную",
        "lw_auto": "Автоматически",
        "lw_crop_hint": "Потяните за уголки, чтобы в рамке осталась только вещь. Фон внутри рамки уберём, если получится.",
        "lw_crop_apply": "Обрезать",
        "lw_cancel": "Отмена",
        "lw_frame": "Рамка обрезки",
        "lw_frame_value": "Ширина %d процентов, высота %d процентов",
        "lw_frame_hint": "Смахните вверх или вниз, чтобы увеличить или уменьшить рамку",
        "lw_move_left": "Сдвинуть влево",
        "lw_move_right": "Сдвинуть вправо",
        "lw_move_up": "Сдвинуть вверх",
        "lw_move_down": "Сдвинуть вниз",
        "lw_item_btn": "Фото вещи",
        "lw_card_a11y": "%@ без фона"
    ]

    private static let kk: [String: String] = [
        "lw_title": "Киіп көретін зат",
        "lw_ready": "Зат фоннан бөлінді — киіп көруге болады",
        "lw_ready_manual": "Зат сіздің жақтауыңыз бойынша қиылды",
        "lw_fail_hint": "Басқа фото таңдаңыз немесе затты қолмен қиыңыз",
        "lw_fail_hint_one": "Затты қолмен қиыңыз — фотодағы жақтаумен",
        "lw_try": "Киіп көру",
        "lw_crop": "Қолмен қию",
        "lw_auto": "Автоматты түрде",
        "lw_crop_hint": "Жақтауда тек зат қалатындай бұрыштарынан тартыңыз. Мүмкін болса, жақтау ішіндегі фонды алып тастаймыз.",
        "lw_crop_apply": "Қию",
        "lw_cancel": "Бас тарту",
        "lw_frame": "Қию жақтауы",
        "lw_frame_value": "Ені %d пайыз, биіктігі %d пайыз",
        "lw_frame_hint": "Жақтауды үлкейту не кішірейту үшін жоғары немесе төмен сырғытыңыз",
        "lw_move_left": "Солға жылжыту",
        "lw_move_right": "Оңға жылжыту",
        "lw_move_up": "Жоғары жылжыту",
        "lw_move_down": "Төмен жылжыту",
        "lw_item_btn": "Зат фотосы",
        "lw_card_a11y": "%@ фонсыз"
    ]

    private static let en: [String: String] = [
        "lw_title": "Item to try on",
        "lw_ready": "The item is separated from the background — ready to try on",
        "lw_ready_manual": "The item is cut out using your frame",
        "lw_fail_hint": "Choose another photo or crop the item manually",
        "lw_fail_hint_one": "Crop the item manually with a frame on the photo",
        "lw_try": "Try on",
        "lw_crop": "Crop manually",
        "lw_auto": "Automatic",
        "lw_crop_hint": "Drag the corners so that only the item stays inside the frame. We'll remove the background inside it if we can.",
        "lw_crop_apply": "Crop",
        "lw_cancel": "Cancel",
        "lw_frame": "Crop frame",
        "lw_frame_value": "Width %d percent, height %d percent",
        "lw_frame_hint": "Swipe up or down to enlarge or shrink the frame",
        "lw_move_left": "Move left",
        "lw_move_right": "Move right",
        "lw_move_up": "Move up",
        "lw_move_down": "Move down",
        "lw_item_btn": "Item photo",
        "lw_card_a11y": "%@ without background"
    ]

    private static let ar: [String: String] = [
        "lw_title": "القطعة للتجربة",
        "lw_ready": "تم فصل القطعة عن الخلفية — يمكنك تجربتها",
        "lw_ready_manual": "تم قص القطعة حسب إطارك",
        "lw_fail_hint": "اختر صورة أخرى أو قص القطعة يدويًا",
        "lw_fail_hint_one": "قص القطعة يدويًا بإطار على الصورة",
        "lw_try": "جرّب",
        "lw_crop": "قص يدويًا",
        "lw_auto": "تلقائيًا",
        "lw_crop_hint": "اسحب الزوايا لتبقى القطعة وحدها داخل الإطار. سنزيل الخلفية داخله إن أمكن.",
        "lw_crop_apply": "قص",
        "lw_cancel": "إلغاء",
        "lw_frame": "إطار القص",
        "lw_frame_value": "العرض %d بالمئة، الارتفاع %d بالمئة",
        "lw_frame_hint": "اسحب لأعلى أو لأسفل لتكبير الإطار أو تصغيره",
        "lw_move_left": "تحريك لليسار",
        "lw_move_right": "تحريك لليمين",
        "lw_move_up": "تحريك لأعلى",
        "lw_move_down": "تحريك لأسفل",
        "lw_item_btn": "صورة القطعة",
        "lw_card_a11y": "%@ بدون خلفية"
    ]
}
