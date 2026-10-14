import Foundation

/**
 Тексты «Разбора объявления» (кнопка под ценой, метка «Ниже рынка», лист разбора, доводы Kliko AI) на языке телефона
 (kk/ru/en/ar). Слова — из изменений сайта ultra-site 07–14.10.2026 (br_* словаря сайта: «Ниже рынка на X%», «На уровне
 рынка», подписи шкалы); числа «похожих» — через двоеточие, чтобы не склонять.
 */
enum ТекстыРазбора {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    /// Язык текстов и поле lang запроса доводов: первый язык телефона; незнакомый — русский.
    static var язык: String {
        let код = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        return ["ru", "kk", "en", "ar"].contains(код) ? код : "ru"
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "br_btn": "Разбор объявления", "br_btn_sub": "Цена по рынку, плюсы, минусы и что спросить продавца",
            "br_title": "Разбор объявления", "br_close": "Закрыть",
            "br_low": "Ниже рынка на %d%%", "br_low_plain": "Ниже рынка", "br_same": "На уровне рынка",
            "br_price": "Цена по рынку", "br_this": "Эта цена", "br_mid": "Середина рынка",
            "br_m_n": "Похожих объявлений на площадке: %d", "br_m_n_mkt": "Похожих предложений на рынке: %d",
            "br_m_n_flat": "Похожих квартир: %d", "br_m_mid_m2": "середина %@ за м²",
            "br_m_area": "шкала пересчитана на %@ м²",
            "br_m_none": "Похожих объявлений пока мало, чтобы честно сравнить цену.",
            "br_ai": "Доводы Kliko AI", "br_ai_sub": "ИИ прочитает объявление и соберёт плюсы, минусы и вопросы продавцу.",
            "br_ai_go": "Разобрать с ИИ", "br_ai_wait": "ИИ читает объявление…", "br_retry": "Повторить",
            "br_pros": "Что говорит за", "br_cons": "На что посмотреть", "br_ask": "Что спросить продавца",
            "br_ask_hint": "Вопрос встанет в чат с продавцом", "br_verdict": "Итог",
            "br_ai_note": "ИИ может ошибаться — проверяйте вещь при встрече.",
            "br_ai_login": "Войдите, чтобы получить разбор ИИ.", "br_login": "Войти",
            "br_ai_fail": "Не удалось собрать разбор. Попробуйте ещё раз.",
            "br_ai_net": "Нет соединения. Попробуйте ещё раз.",
            "br_ai_paid": "Разбор ИИ сейчас недоступен для вашего аккаунта.",
            "br_check": "Что проверить", "br_seller": "Продавец", "br_safe": "Как купить безопасно",
            "br_safe_chat": "Договоритесь в чате и осмотрите вещь до оплаты. Не переводите предоплату незнакомцам.",
            "br_safe_deposit": "Задаток вносится через Безопасную сделку — сумма и условия брони видны в окне сделки до оплаты."
        ],
        "kk": [
            "br_btn": "Хабарландыру талдауы", "br_btn_sub": "Нарықтағы баға, артықшылықтар, кемшіліктер және сатушыға сұрақтар",
            "br_title": "Хабарландыру талдауы", "br_close": "Жабу",
            "br_low": "Нарықтан %d%% төмен", "br_low_plain": "Нарықтан төмен", "br_same": "Нарық деңгейінде",
            "br_price": "Нарықтағы баға", "br_this": "Осы баға", "br_mid": "Нарықтың ортасы",
            "br_m_n": "Алаңдағы ұқсас хабарландырулар: %d", "br_m_n_mkt": "Нарықтағы ұқсас ұсыныстар: %d",
            "br_m_n_flat": "Ұқсас пәтерлер: %d", "br_m_mid_m2": "м² үшін ортасы %@",
            "br_m_area": "шкала %@ м²-ге қайта есептелген",
            "br_m_none": "Бағаны әділ салыстыру үшін ұқсас хабарландырулар әзірге аз.",
            "br_ai": "Kliko AI дәлелдері", "br_ai_sub": "ЖИ хабарландыруды оқып, артықшылықтарды, кемшіліктерді және сатушыға сұрақтарды жинайды.",
            "br_ai_go": "ЖИ-мен талдау", "br_ai_wait": "ЖИ хабарландыруды оқып жатыр…", "br_retry": "Қайталау",
            "br_pros": "Пайдасына не айтады", "br_cons": "Неге назар аудару керек", "br_ask": "Сатушыдан не сұрау керек",
            "br_ask_hint": "Сұрақ сатушымен чатқа қойылады", "br_verdict": "Қорытынды",
            "br_ai_note": "ЖИ қателесуі мүмкін — затты кездескенде тексеріңіз.",
            "br_ai_login": "ЖИ талдауын алу үшін кіріңіз.", "br_login": "Кіру",
            "br_ai_fail": "Талдау жинау мүмкін болмады. Қайталап көріңіз.",
            "br_ai_net": "Байланыс жоқ. Қайталап көріңіз.",
            "br_ai_paid": "ЖИ талдауы қазір аккаунтыңыз үшін қолжетімсіз.",
            "br_check": "Нені тексеру керек", "br_seller": "Сатушы", "br_safe": "Қауіпсіз қалай сатып алуға болады",
            "br_safe_chat": "Чатта келісіп, затты төлемге дейін қараңыз. Бейтаныс адамдарға алдын ала төлем жібермеңіз.",
            "br_safe_deposit": "Кепілақы Қауіпсіз мәміле арқылы салынады — брондау сомасы мен шарттары төлемге дейін мәміле терезесінде көрінеді."
        ],
        "en": [
            "br_btn": "Listing breakdown", "br_btn_sub": "Market price, pros, cons and what to ask the seller",
            "br_title": "Listing breakdown", "br_close": "Close",
            "br_low": "%d%% below market", "br_low_plain": "Below market", "br_same": "At market level",
            "br_price": "Market price", "br_this": "This price", "br_mid": "Market middle",
            "br_m_n": "Similar listings on Kliko: %d", "br_m_n_mkt": "Similar offers on the market: %d",
            "br_m_n_flat": "Similar flats: %d", "br_m_mid_m2": "middle %@ per m²",
            "br_m_area": "scale recalculated for %@ m²",
            "br_m_none": "There are too few similar listings yet to compare the price fairly.",
            "br_ai": "Kliko AI arguments", "br_ai_sub": "AI will read the listing and gather pros, cons and questions for the seller.",
            "br_ai_go": "Break it down with AI", "br_ai_wait": "AI is reading the listing…", "br_retry": "Try again",
            "br_pros": "What speaks for it", "br_cons": "What to look at", "br_ask": "What to ask the seller",
            "br_ask_hint": "The question goes to the chat with the seller", "br_verdict": "Verdict",
            "br_ai_note": "AI can make mistakes — check the item when you meet.",
            "br_ai_login": "Sign in to get the AI breakdown.", "br_login": "Sign in",
            "br_ai_fail": "Couldn't put the breakdown together. Please try again.",
            "br_ai_net": "No connection. Please try again.",
            "br_ai_paid": "The AI breakdown isn't available for your account right now.",
            "br_check": "What to check", "br_seller": "Seller", "br_safe": "How to buy safely",
            "br_safe_chat": "Agree in the chat and inspect the item before paying. Never send a prepayment to strangers.",
            "br_safe_deposit": "The deposit goes through the Safe deal — the amount and reservation terms are shown in the deal window before you pay."
        ],
        "ar": [
            "br_btn": "تحليل الإعلان", "br_btn_sub": "سعر السوق والمزايا والعيوب وما تسأل البائع عنه",
            "br_title": "تحليل الإعلان", "br_close": "إغلاق",
            "br_low": "أقل من السوق بنسبة %d%%", "br_low_plain": "أقل من السوق", "br_same": "بمستوى السوق",
            "br_price": "سعر السوق", "br_this": "هذا السعر", "br_mid": "منتصف السوق",
            "br_m_n": "إعلانات مشابهة على المنصة: %d", "br_m_n_mkt": "عروض مشابهة في السوق: %d",
            "br_m_n_flat": "شقق مشابهة: %d", "br_m_mid_m2": "المنتصف %@ للمتر²",
            "br_m_area": "المقياس محسوب لمساحة %@ م²",
            "br_m_none": "الإعلانات المشابهة قليلة حتى الآن لمقارنة السعر بإنصاف.",
            "br_ai": "حجج Kliko AI", "br_ai_sub": "سيقرأ الذكاء الاصطناعي الإعلان ويجمع المزايا والعيوب والأسئلة للبائع.",
            "br_ai_go": "حلّل بالذكاء الاصطناعي", "br_ai_wait": "الذكاء الاصطناعي يقرأ الإعلان…", "br_retry": "أعد المحاولة",
            "br_pros": "ما يصب في صالحه", "br_cons": "ما يجب الانتباه إليه", "br_ask": "ما تسأل البائع عنه",
            "br_ask_hint": "يُضاف السؤال إلى الدردشة مع البائع", "br_verdict": "الخلاصة",
            "br_ai_note": "قد يخطئ الذكاء الاصطناعي — افحص الشيء عند اللقاء.",
            "br_ai_login": "سجّل الدخول للحصول على تحليل الذكاء الاصطناعي.", "br_login": "تسجيل الدخول",
            "br_ai_fail": "تعذّر إعداد التحليل. حاول مرة أخرى.",
            "br_ai_net": "لا يوجد اتصال. حاول مرة أخرى.",
            "br_ai_paid": "تحليل الذكاء الاصطناعي غير متاح لحسابك الآن.",
            "br_check": "ما الذي يجب فحصه", "br_seller": "البائع", "br_safe": "كيف تشتري بأمان",
            "br_safe_chat": "اتفق في الدردشة وافحص الشيء قبل الدفع. لا ترسل دفعة مقدمة لغرباء.",
            "br_safe_deposit": "يُدفع العربون عبر الصفقة الآمنة — يظهر المبلغ وشروط الحجز في نافذة الصفقة قبل الدفع."
        ]
    ]
}
