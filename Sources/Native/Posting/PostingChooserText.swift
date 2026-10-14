import Foundation

/**
 ТЕКСТЫ ЭКРАНА «БЫСТРО / ПОДРОБНО» (ЭкранВыбораПодачи, PostingChooser.swift) — ru / kk / en / ar.

 Владелец 14.10.2026: «окно „быстро или подробно“ суховато — подправь, чтобы чисто выглядело, а то снизу пустота».
 Без выдуманных цифр и обещаний: «~30 секунд» — то же, что уже обещала карточка «Быстро (30 секунд)»; схема шагов —
 настоящий путь (камера → Kliko AI → «Проверьте»; «Что размещаете?» → Фото → Данные → Цена); советы — общие, а
 «Безопасная сделка» показывается, только когда гарант работает по сверке (ПаузаГаранта.работаетПоСверке).
 */
enum ВыборПодачиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "ch_title": "Как подать объявление?",
        "ch_quick": "Быстро",
        "ch_quick_meta": "~30 секунд",
        "ch_quick_meta_ax": "около 30 секунд",
        "ch_quick_s": "Сфотографируйте — Kliko AI заполнит название, раздел и характеристики",
        "ch_full": "Подробно",
        "ch_full_meta": "все поля",
        "ch_full_s": "Всё по шагам: характеристики, цена, адрес, доставка",
        "ch_last": "В прошлый раз",
        "ch_q1": "Снимите",
        "ch_q2": "Kliko AI заполнит",
        "ch_q3": "Опубликуйте",
        "ch_f1": "Раздел",
        "ch_f2": "Фото",
        "ch_f3": "Данные",
        "ch_f4": "Цена",
        "ch_tips": "Как продать быстрее",
        "ch_tip_photo": "Светлые фото",
        "ch_tip_photo_s": "С разных сторон, на первом — вещь целиком",
        "ch_tip_price": "Честная цена",
        "ch_tip_price_s": "Подскажем цену по рынку",
        "ch_tip_chat": "Отвечайте быстро",
        "ch_tip_chat_s": "Покупатели пишут в чат — не заставляйте ждать",
        "ch_tip_safe": "Безопасная сделка",
        "ch_tip_safe_s": "Деньги у Kliko, пока покупатель не получит товар",
        "ch_tip_desc": "Честное описание",
        "ch_tip_desc_s": "Состояние, комплект, недостатки — меньше лишних вопросов",
        "ch_hint": "Быструю подачу можно продолжить подробно — ничего не потеряется"
    ]

    private static let kk: [String: String] = [
        "ch_title": "Хабарландыруды қалай беру керек?",
        "ch_quick": "Жылдам",
        "ch_quick_meta": "~30 секунд",
        "ch_quick_meta_ax": "шамамен 30 секунд",
        "ch_quick_s": "Суретке түсіріңіз — Kliko AI атауын, бөлімін және сипаттамаларын толтырады",
        "ch_full": "Толық",
        "ch_full_meta": "барлық өрістер",
        "ch_full_s": "Бәрі қадаммен: сипаттамалар, баға, мекенжай, жеткізу",
        "ch_last": "Өткен жолы",
        "ch_q1": "Түсіріңіз",
        "ch_q2": "Kliko AI толтырады",
        "ch_q3": "Жариялаңыз",
        "ch_f1": "Бөлім",
        "ch_f2": "Фото",
        "ch_f3": "Деректер",
        "ch_f4": "Баға",
        "ch_tips": "Қалай тезірек сатуға болады",
        "ch_tip_photo": "Жарық фото",
        "ch_tip_photo_s": "Әр жағынан, біріншісінде — зат толық",
        "ch_tip_price": "Әділ баға",
        "ch_tip_price_s": "Нарық бойынша баға ұсынамыз",
        "ch_tip_chat": "Тез жауап беріңіз",
        "ch_tip_chat_s": "Сатып алушылар чатқа жазады — күттірмеңіз",
        "ch_tip_safe": "Қауіпсіз мәміле",
        "ch_tip_safe_s": "Сатып алушы тауарды алғанша ақша Kliko-да тұрады",
        "ch_tip_desc": "Шынайы сипаттама",
        "ch_tip_desc_s": "Күйі, жиынтығы, кемшіліктері — артық сұрақ азаяды",
        "ch_hint": "Жылдам берілімді толық жалғастыруға болады — ештеңе жоғалмайды"
    ]

    private static let en: [String: String] = [
        "ch_title": "How do you want to post?",
        "ch_quick": "Quick",
        "ch_quick_meta": "~30 seconds",
        "ch_quick_meta_ax": "about 30 seconds",
        "ch_quick_s": "Take a photo — Kliko AI fills in the title, category and specs",
        "ch_full": "Detailed",
        "ch_full_meta": "all fields",
        "ch_full_s": "Step by step: specs, price, address, delivery",
        "ch_last": "Last time",
        "ch_q1": "Snap",
        "ch_q2": "Kliko AI fills in",
        "ch_q3": "Publish",
        "ch_f1": "Category",
        "ch_f2": "Photos",
        "ch_f3": "Details",
        "ch_f4": "Price",
        "ch_tips": "How to sell faster",
        "ch_tip_photo": "Bright photos",
        "ch_tip_photo_s": "From different sides, the first shows the whole item",
        "ch_tip_price": "Fair price",
        "ch_tip_price_s": "We'll suggest a market price",
        "ch_tip_chat": "Reply quickly",
        "ch_tip_chat_s": "Buyers write in chat — don't keep them waiting",
        "ch_tip_safe": "Safe deal",
        "ch_tip_safe_s": "Kliko holds the money until the buyer gets the item",
        "ch_tip_desc": "Honest description",
        "ch_tip_desc_s": "Condition, kit and flaws — fewer extra questions",
        "ch_hint": "A quick listing can be continued in detail — nothing gets lost"
    ]

    private static let ar: [String: String] = [
        "ch_title": "كيف تريد نشر الإعلان؟",
        "ch_quick": "سريع",
        "ch_quick_meta": "~30 ثانية",
        "ch_quick_meta_ax": "حوالي 30 ثانية",
        "ch_quick_s": "التقط صورة — سيملأ Kliko AI العنوان والقسم والمواصفات",
        "ch_full": "مفصّل",
        "ch_full_meta": "كل الحقول",
        "ch_full_s": "خطوة بخطوة: المواصفات والسعر والعنوان والتوصيل",
        "ch_last": "المرة السابقة",
        "ch_q1": "التقط",
        "ch_q2": "Kliko AI يملأ",
        "ch_q3": "انشر",
        "ch_f1": "القسم",
        "ch_f2": "الصور",
        "ch_f3": "البيانات",
        "ch_f4": "السعر",
        "ch_tips": "كيف تبيع أسرع",
        "ch_tip_photo": "صور مضيئة",
        "ch_tip_photo_s": "من جهات مختلفة، والأولى تُظهر السلعة كاملة",
        "ch_tip_price": "سعر عادل",
        "ch_tip_price_s": "سنقترح سعرًا حسب السوق",
        "ch_tip_chat": "ردّ بسرعة",
        "ch_tip_chat_s": "المشترون يكتبون في الدردشة — لا تجعلهم ينتظرون",
        "ch_tip_safe": "صفقة آمنة",
        "ch_tip_safe_s": "يحتفظ Kliko بالمال حتى يستلم المشتري السلعة",
        "ch_tip_desc": "وصف صادق",
        "ch_tip_desc_s": "الحالة والملحقات والعيوب — أسئلة أقل",
        "ch_hint": "يمكن متابعة الإعلان السريع بالتفصيل — لن يضيع شيء"
    ]
}
