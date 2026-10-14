import Foundation

/**
 Тексты режима «Вещь» в «Поместится ли?» (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ — 5 разных фото, и ИИ
 сам собрал 3D любой вещи или авто»; раньше: «чтобы по-настоящему по камере показывал объект в примерке»). Ключи fi_*;
 языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык). Свой файл и свой
 словарь: коробка живёт в ГабаритыText (FitBoxText.swift), линейка — в ЛинейкаГабаритовText (FitBoxRulerText.swift).

 вместоКоробки(_:) — подмена строк коробки в режиме «Вещь»: сообщения сцены («Коробка поставлена», «Прижать к стене…»)
 говорят «вещь», а не «коробка». Ключа в подмене нет — строка коробки как есть («см», «Снимок», «Размеры»).
 */
enum ВещьГабаритовText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Строка с подстановкой одного значения (%@).
    static func т(_ ключ: String, _ значение: String) -> String {
        String(format: т(ключ), значение)
    }

    /// Строка коробки (fb_*) в режиме «Вещь»: своя, если есть, иначе — коробки (ГабаритыText).
    static func вместоКоробки(_ ключ: String) -> String {
        guard let свой = подмена[ключ] else { return ГабаритыText.т(ключ) }
        return т(свой)
    }

    /// fb_* коробки → fi_* вещи: только там, где в тексте сказано «коробка».
    private static let подмена: [String: String] = [
        "fb_relocal": "fi_relocal",
        "fb_wall_hint": "fi_wall_hint",
        "fb_wall_far": "fi_wall_far",
        "fb_wall_on": "fi_wall_on",
        "fb_placed_done": "fi_placed_done",
        "fb_removed": "fi_removed",
        "fb_reset_a11y": "fi_reset_a11y",
        "fb_place_center": "fi_place_center",
        "fb_scene_a11y": "fi_scene_a11y",
        "fb_shot_a11y": "fi_shot_a11y"
    ]

    private static var словарь: [String: String] {
        switch ПримерочнаяText.язык {
        case "kk": return kk
        case "en": return en
        case "ar": return ar
        default: return ru
        }
    }

    private static let ru: [String: String] = [
        "fi_mode": "Вещь",
        "fi_mode_on": "Вещь: фото или 3D-модель в настоящем размере",
        "fi_loading_model": "Загружаем 3D-модель…",
        "fi_loading_photo": "Вырезаем вещь с фото…",
        "fi_model": "3D-модель ИИ",
        "fi_model_3d": "3D-модель",
        "fi_photo": "Фото вещи в реальном размере",
        "fi_failed": "Вещь с фото не вырезалась — показана коробка",
        "fi_ai_note": "3D-модель создана ИИ по фото — детали могут отличаться",
        "fi_photo_note": "Плоское фото стоя, по бокам — глубина вещи",
        "fi_model_fallback": "3D-модель не загрузилась — показано фото",
        "fi_ready_model": "3D-модель готова",
        "fi_ready_photo": "Фото вещи готово",
        "fi_placed_done": "Вещь поставлена",
        "fi_removed": "Вещь убрана",
        "fi_reset_a11y": "Убрать вещь",
        "fi_place_center": "Поставить вещь в центр экрана",
        "fi_scene_a11y": "Камера с вещью настоящего размера",
        "fi_state": "Вещь стоит в кадре. Размеры в сантиметрах: %@",
        "fi_relocal": "Наведите камеру туда, где стояла вещь",
        "fi_wall_hint": "Вещь встанет задней стороной к ближайшей стене",
        "fi_wall_far": "Стена далеко — подвиньте вещь ближе к ней",
        "fi_wall_on": "Вещь прижата к стене",
        "fi_shot_a11y": "Сохранить или отправить кадр с вещью",
        "fi_shot_img": "Снимок комнаты с вещью. Размеры в сантиметрах: %@"
    ]

    private static let kk: [String: String] = [
        "fi_mode": "Зат",
        "fi_mode_on": "Зат: фото немесе 3D-модель нақты өлшемде",
        "fi_loading_model": "3D-модельді жүктеп жатырмыз…",
        "fi_loading_photo": "Затты фотодан қиып жатырмыз…",
        "fi_model": "ЖИ 3D-моделі",
        "fi_model_3d": "3D-модель",
        "fi_photo": "Заттың нақты өлшемдегі фотосы",
        "fi_failed": "Затты фотодан қию сәтсіз — қорап көрсетілді",
        "fi_ai_note": "3D-модельді ЖИ фото бойынша жасады — бөлшектері өзгеше болуы мүмкін",
        "fi_photo_note": "Тік тұрған жалпақ фото, бүйірлері — заттың тереңдігі",
        "fi_model_fallback": "3D-модель жүктелмеді — фото көрсетілді",
        "fi_ready_model": "3D-модель дайын",
        "fi_ready_photo": "Зат фотосы дайын",
        "fi_placed_done": "Зат қойылды",
        "fi_removed": "Зат алынды",
        "fi_reset_a11y": "Затты алып тастау",
        "fi_place_center": "Затты экран ортасына қою",
        "fi_scene_a11y": "Нақты өлшемдегі заты бар камера",
        "fi_state": "Зат кадрда тұр. Өлшемдері сантиметрмен: %@",
        "fi_relocal": "Камераны зат тұрған жерге бағыттаңыз",
        "fi_wall_hint": "Зат артқы жағымен ең жақын қабырғаға тұрады",
        "fi_wall_far": "Қабырға алыс — затты оған жақындатыңыз",
        "fi_wall_on": "Зат қабырғаға тығыздалды",
        "fi_shot_a11y": "Заты бар кадрды сақтау немесе жіберу",
        "fi_shot_img": "Заты бар бөлменің суреті. Өлшемдері сантиметрмен: %@"
    ]

    private static let en: [String: String] = [
        "fi_mode": "Item",
        "fi_mode_on": "Item: photo or 3D model at real size",
        "fi_loading_model": "Loading 3D model…",
        "fi_loading_photo": "Cutting the item out of the photo…",
        "fi_model": "AI 3D model",
        "fi_model_3d": "3D model",
        "fi_photo": "Item photo at real size",
        "fi_failed": "Couldn't cut the item out of the photo — showing a box",
        "fi_ai_note": "The 3D model was made by AI from photos — details may differ",
        "fi_photo_note": "A flat standing photo; the sides show the item's depth",
        "fi_model_fallback": "The 3D model didn't load — showing the photo",
        "fi_ready_model": "3D model ready",
        "fi_ready_photo": "Item photo ready",
        "fi_placed_done": "Item placed",
        "fi_removed": "Item removed",
        "fi_reset_a11y": "Remove the item",
        "fi_place_center": "Place the item in the center of the screen",
        "fi_scene_a11y": "Camera with the item at real size",
        "fi_state": "The item is in view. Size in centimeters: %@",
        "fi_relocal": "Point the camera where the item was",
        "fi_wall_hint": "The item will stand with its back to the nearest wall",
        "fi_wall_far": "The wall is far — move the item closer to it",
        "fi_wall_on": "Item pushed against the wall",
        "fi_shot_a11y": "Save or send a shot with the item",
        "fi_shot_img": "Photo of the room with the item. Size in centimeters: %@"
    ]

    private static let ar: [String: String] = [
        "fi_mode": "القطعة",
        "fi_mode_on": "القطعة: صورة أو نموذج ثلاثي الأبعاد بالحجم الحقيقي",
        "fi_loading_model": "جارٍ تحميل النموذج ثلاثي الأبعاد…",
        "fi_loading_photo": "جارٍ قص القطعة من الصورة…",
        "fi_model": "نموذج 3D بالذكاء الاصطناعي",
        "fi_model_3d": "نموذج ثلاثي الأبعاد",
        "fi_photo": "صورة القطعة بالحجم الحقيقي",
        "fi_failed": "تعذّر قص القطعة من الصورة — يُعرض صندوق",
        "fi_ai_note": "أنشأ الذكاء الاصطناعي النموذج ثلاثي الأبعاد من الصور — قد تختلف التفاصيل",
        "fi_photo_note": "صورة مسطحة قائمة، والجانبان يُظهران عمق القطعة",
        "fi_model_fallback": "لم يُحمَّل النموذج ثلاثي الأبعاد — تُعرض الصورة",
        "fi_ready_model": "النموذج ثلاثي الأبعاد جاهز",
        "fi_ready_photo": "صورة القطعة جاهزة",
        "fi_placed_done": "تم وضع القطعة",
        "fi_removed": "تمت إزالة القطعة",
        "fi_reset_a11y": "إزالة القطعة",
        "fi_place_center": "ضع القطعة في وسط الشاشة",
        "fi_scene_a11y": "كاميرا مع القطعة بالحجم الحقيقي",
        "fi_state": "القطعة ظاهرة في الإطار. المقاسات بالسنتيمتر: %@",
        "fi_relocal": "وجّه الكاميرا إلى حيث كانت القطعة",
        "fi_wall_hint": "ستقف القطعة وظهرها إلى أقرب جدار",
        "fi_wall_far": "الجدار بعيد — قرّب القطعة منه",
        "fi_wall_on": "القطعة ملاصقة للجدار",
        "fi_shot_a11y": "احفظ أو أرسل لقطة مع القطعة",
        "fi_shot_img": "صورة الغرفة مع القطعة. المقاسات بالسنتيمتر: %@"
    ]
}
