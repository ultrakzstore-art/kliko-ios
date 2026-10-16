import Foundation

/**
 Тексты сканера маркировки колёс (СканерКолёс, WheelScan.swift; владелец 16.10.2026: «камерой узнать размеры»). Ключи
 ws_*; языки ru, kk, en, ar, прочие — русский (язык — тот же, что у примерочной: ПримерочнаяText.язык). Свой файл и свой
 словарь — чтобы не пересекаться с «Подойдут ли?» (АвтоподборText) и «Моё». Сами значения на чипах («205/55 R16»,
 «ET45», «5x114.3») — как на колесе, без перевода. Строки с %@ идут через String(format:).
 */
enum СканерКолёсText {
    static func т(_ ключ: String) -> String {
        словарь[ключ] ?? ru[ключ] ?? ключ
    }

    /// Строка с подстановкой одного значения (%@).
    static func т(_ ключ: String, _ значение: String) -> String {
        String(format: т(ключ), значение)
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
        "ws_title_tire": "Сканировать шину",
        "ws_title_rim": "Сканировать диск",
        "ws_sub": "Размеры по маркировке",
        "ws_hint_tire": "Наведите на боковину шины — надпись вида 205/55 R16",
        "ws_hint_rim": "Наведите на внутреннюю сторону диска — 6.5Jx16 ET45 5x114.3",
        "ws_dark": "Темно? Включите фонарик",
        "ws_searching": "Ищем надпись…",
        "ws_found": "Проверьте и нажмите «Готово». Неверно — коснитесь значения",
        "ws_shot_hint": "Наведите и нажмите «Снять» — прочитаем надпись",
        "ws_reading": "Читаем надпись…",
        "ws_not_read": "Не прочитали — подойдите ближе, включите фонарик и снимите ещё раз",
        "ws_done": "Готово",
        "ws_done_a11y": "Перенести размеры в поля",
        "ws_close": "Закрыть",
        "ws_torch_on": "Включить фонарик",
        "ws_torch_off": "Выключить фонарик",
        "ws_shot": "Снять",
        "ws_shot_a11y": "Снять и прочитать надпись",
        "ws_f_tire": "Размер шины",
        "ws_f_r": "Диаметр",
        "ws_f_j": "Ширина обода",
        "ws_f_et": "Вылет",
        "ws_f_pcd": "Разболтовка",
        "ws_f_dia": "Отверстие",
        "ws_remove_hint": "Уберёт значение, если оно прочитано неверно",
        "ws_wait_a11y": "%@: ещё ищем",
        "ws_found_a11y": "Найдено: %@",
        "ws_removed_a11y": "Убрано: %@",
        "ws_no_access_t": "Нет доступа к камере",
        "ws_no_access_s": "Разрешите камеру в Настройках — прочитаем маркировку шины или диска. Снимки не сохраняются и никуда не отправляются.",
        "ws_settings": "Открыть Настройки",
        "ws_no_cam_t": "Камера недоступна",
        "ws_no_cam_s": "Не удалось включить камеру — введите размеры вручную или выберите из шаблонов.",
        "ws_private": "Снимки не сохраняются и никуда не отправляются"
    ]

    private static let kk: [String: String] = [
        "ws_title_tire": "Шинаны сканерлеу",
        "ws_title_rim": "Дискіні сканерлеу",
        "ws_sub": "Таңбалау бойынша өлшемдер",
        "ws_hint_tire": "Шинаның бүйіріне бағыттаңыз — 205/55 R16 сияқты жазу",
        "ws_hint_rim": "Дискінің ішкі жағына бағыттаңыз — 6.5Jx16 ET45 5x114.3",
        "ws_dark": "Қараңғы ма? Шамды қосыңыз",
        "ws_searching": "Жазуды іздеп жатырмыз…",
        "ws_found": "Тексеріп, «Дайын» басыңыз. Қате болса — мәнді түртіңіз",
        "ws_shot_hint": "Бағыттап, «Түсіру» басыңыз — жазуды оқимыз",
        "ws_reading": "Жазуды оқып жатырмыз…",
        "ws_not_read": "Оқи алмадық — жақынырақ келіп, шамды қосып, қайта түсіріңіз",
        "ws_done": "Дайын",
        "ws_done_a11y": "Өлшемдерді өрістерге көшіру",
        "ws_close": "Жабу",
        "ws_torch_on": "Шамды қосу",
        "ws_torch_off": "Шамды өшіру",
        "ws_shot": "Түсіру",
        "ws_shot_a11y": "Түсіріп, жазуды оқу",
        "ws_f_tire": "Шина өлшемі",
        "ws_f_r": "Диаметр",
        "ws_f_j": "Құрсау ені",
        "ws_f_et": "Шығыңқылық",
        "ws_f_pcd": "Бұрандалар",
        "ws_f_dia": "Тесік",
        "ws_remove_hint": "Қате оқылса, мәнді алып тастайды",
        "ws_wait_a11y": "%@: әлі іздеп жатырмыз",
        "ws_found_a11y": "Табылды: %@",
        "ws_removed_a11y": "Алынды: %@",
        "ws_no_access_t": "Камераға рұқсат жоқ",
        "ws_no_access_s": "Баптауларда камераға рұқсат беріңіз — шина не диск таңбалауын оқимыз. Суреттер сақталмайды және ешқайда жіберілмейді.",
        "ws_settings": "Баптауларды ашу",
        "ws_no_cam_t": "Камера қолжетімсіз",
        "ws_no_cam_s": "Камераны қосу мүмкін болмады — өлшемдерді қолмен енгізіңіз немесе үлгіден таңдаңыз.",
        "ws_private": "Суреттер сақталмайды және ешқайда жіберілмейді"
    ]

    private static let en: [String: String] = [
        "ws_title_tire": "Scan tire",
        "ws_title_rim": "Scan wheel",
        "ws_sub": "Sizes from the marking",
        "ws_hint_tire": "Point at the tire sidewall — text like 205/55 R16",
        "ws_hint_rim": "Point at the inner side of the wheel — 6.5Jx16 ET45 5x114.3",
        "ws_dark": "Too dark? Turn on the flashlight",
        "ws_searching": "Looking for the marking…",
        "ws_found": "Check and tap “Done”. Wrong? Tap the value",
        "ws_shot_hint": "Aim and tap “Capture” — we’ll read the text",
        "ws_reading": "Reading the text…",
        "ws_not_read": "Couldn’t read it — move closer, turn on the flashlight and capture again",
        "ws_done": "Done",
        "ws_done_a11y": "Put the sizes into the fields",
        "ws_close": "Close",
        "ws_torch_on": "Turn on flashlight",
        "ws_torch_off": "Turn off flashlight",
        "ws_shot": "Capture",
        "ws_shot_a11y": "Capture and read the text",
        "ws_f_tire": "Tire size",
        "ws_f_r": "Diameter",
        "ws_f_j": "Rim width",
        "ws_f_et": "Offset",
        "ws_f_pcd": "Bolt pattern",
        "ws_f_dia": "Center bore",
        "ws_remove_hint": "Removes the value if it was read wrong",
        "ws_wait_a11y": "%@: still looking",
        "ws_found_a11y": "Found: %@",
        "ws_removed_a11y": "Removed: %@",
        "ws_no_access_t": "No camera access",
        "ws_no_access_s": "Allow the camera in Settings to read the tire or wheel marking. Photos aren’t saved or sent anywhere.",
        "ws_settings": "Open Settings",
        "ws_no_cam_t": "Camera unavailable",
        "ws_no_cam_s": "Couldn’t turn on the camera — enter the sizes manually or pick a template.",
        "ws_private": "Photos aren’t saved or sent anywhere"
    ]

    private static let ar: [String: String] = [
        "ws_title_tire": "مسح الإطار",
        "ws_title_rim": "مسح الجنط",
        "ws_sub": "المقاسات من العلامة",
        "ws_hint_tire": "وجّه الكاميرا إلى جانب الإطار — نص مثل 205/55 R16",
        "ws_hint_rim": "وجّه الكاميرا إلى الجهة الداخلية للجنط — 6.5Jx16 ET45 5x114.3",
        "ws_dark": "الإضاءة ضعيفة؟ شغّل المصباح",
        "ws_searching": "نبحث عن العلامة…",
        "ws_found": "تحقق واضغط «تم». خطأ؟ اضغط على القيمة",
        "ws_shot_hint": "وجّه الكاميرا واضغط «التقاط» — سنقرأ النص",
        "ws_reading": "نقرأ النص…",
        "ws_not_read": "لم نتمكن من القراءة — اقترب وشغّل المصباح والتقط مرة أخرى",
        "ws_done": "تم",
        "ws_done_a11y": "نقل المقاسات إلى الحقول",
        "ws_close": "إغلاق",
        "ws_torch_on": "تشغيل المصباح",
        "ws_torch_off": "إطفاء المصباح",
        "ws_shot": "التقاط",
        "ws_shot_a11y": "التقاط وقراءة النص",
        "ws_f_tire": "مقاس الإطار",
        "ws_f_r": "القطر",
        "ws_f_j": "عرض الجنط",
        "ws_f_et": "الإزاحة",
        "ws_f_pcd": "توزيع البراغي",
        "ws_f_dia": "الثقب المركزي",
        "ws_remove_hint": "يزيل القيمة إن قُرئت بشكل خاطئ",
        "ws_wait_a11y": "%@: ما زلنا نبحث",
        "ws_found_a11y": "تم العثور: %@",
        "ws_removed_a11y": "أُزيل: %@",
        "ws_no_access_t": "لا يوجد وصول إلى الكاميرا",
        "ws_no_access_s": "اسمح بالكاميرا في الإعدادات لقراءة علامة الإطار أو الجنط. لا تُحفظ الصور ولا تُرسل إلى أي مكان.",
        "ws_settings": "فتح الإعدادات",
        "ws_no_cam_t": "الكاميرا غير متاحة",
        "ws_no_cam_s": "تعذّر تشغيل الكاميرا — أدخل المقاسات يدويًا أو اختر قالبًا.",
        "ws_private": "لا تُحفظ الصور ولا تُرسل إلى أي مكان"
    ]
}
