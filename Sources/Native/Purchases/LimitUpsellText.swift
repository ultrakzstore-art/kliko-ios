import Foundation

/**
 Тексты «Расширить» в окнах лимита (LimitUpsell.swift, владелец 16.10.2026: «в окне предлагать расширить сразу»).
 Языки: kk/ru/en/ar; прочие — русский. Ни цен, ни ссылок и слов об оплате на сайте (правила 3.1.1 и 3.1.3): лимит
 поднимает только покупка App Store, верификация — бесплатно. Числа «сколько с пакетом» не пишем: это предложение
 сервера, решает владелец.
 */
enum ЛимитText {
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

    static func т(_ ключ: String, _ замены: [String: String]) -> String {
        var итог = т(ключ)
        for (имя, значение) in замены {
            итог = итог.replacingOccurrences(of: "{" + имя + "}", with: значение)
        }
        return итог
    }

    private static let ru: [String: String] = [
        "lu_expand": "Расширить лимит",
        "lu_more_ai": "Больше Kliko AI",
        "lu_anyway": "Заполнить — опубликую позже",
        "lu_done": "Готово — услуга подключена. Продолжаем…",
        "lu_used": "Занято {n} из {m}",
        "lu_slots_d": "Сейчас у вас максимум объявлений. Расширьте лимит — и объявление сразу уйдёт на публикацию, или освободите место.",
        "lu_slots_d_verify": "Сейчас у вас максимум объявлений. Расширьте лимит — и объявление сразу уйдёт на публикацию, или подтвердите личность: это ещё 5 мест.",
        "lu_slots_photo_d": "Сейчас у вас максимум объявлений. Расширьте лимит — и Kliko AI продолжит разбор фото, или освободите место.",
        "lu_slots_photo_d_verify": "Сейчас у вас максимум объявлений. Расширьте лимит — и Kliko AI продолжит разбор фото, или подтвердите личность: это ещё 5 мест.",
        "lu_held_d": "Объявление сохранено, но сейчас у вас максимум объявлений. Расширьте лимит — и оно сразу уйдёт на проверку и публикацию, или освободите место.",
        "lu_held_d_verify": "Объявление сохранено, но сейчас у вас максимум объявлений. Расширьте лимит — и оно сразу уйдёт на проверку и публикацию, или подтвердите личность: это ещё 5 мест.",
        "lu_gate_d": "Сейчас у вас максимум объявлений. Расширьте лимит или освободите место — тогда новое объявление сразу уйдёт на публикацию. Можно и заполнить его сейчас, а опубликовать позже.",
        "lu_gate_d_free": "Сейчас у вас максимум объявлений. Освободите место — тогда новое объявление сразу уйдёт на публикацию. Можно и заполнить его сейчас, а опубликовать позже.",
        "lu_ai_t": "Лимит Kliko AI исчерпан",
        "lu_ai_photo_d": "Лимит Kliko AI исчерпан. Возьмите больше Kliko AI — и он снова заполнит поля по фото, или заполните их вручную.",
        "lu_ai_svc_d": "Лимит Kliko AI исчерпан. Возьмите больше Kliko AI — и он соберёт объявление по описанию, или заполните его вручную. Черновик уже собран из ваших слов.",
        "lu_manual": "Заполню сам",
        "lu_imp_ai_d": "Kliko AI-разборы на этот период закончились. Возьмите больше Kliko AI — и разбор каталога продолжится.",
        "lu_imp_ai_none": "Kliko AI-разборы на этот период закончились. Попробуйте позже.",
        "lu_imp_verify_d": "Пройдите верификацию — лимит вырастет до 50 в месяц. Или возьмите больше Kliko AI.",
        "lu_imp_verify_only": "Пройдите верификацию — лимит вырастет до 50 в месяц.",
        "lu_tryon_note": "С пакетом Kliko AI примерок в сутки больше.",
        "lu_more_tryon": "Больше примерок с Kliko AI",
        "lu_3d_note": "Возьмите больше Kliko AI — и сборок 3D в сутки станет больше.",
        "lu_more_3d": "Больше сборок с Kliko AI",
    ]

    private static let kk: [String: String] = [
        "lu_expand": "Лимитті кеңейту",
        "lu_more_ai": "Көбірек Kliko AI",
        "lu_anyway": "Толтыру — кейін жариялаймын",
        "lu_done": "Дайын — қызмет қосылды. Жалғастырамыз…",
        "lu_used": "Бос емес: {n} / {m}",
        "lu_slots_d": "Қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — хабарландыру бірден жариялауға жіберіледі, немесе орын босатыңыз.",
        "lu_slots_d_verify": "Қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — хабарландыру бірден жариялауға жіберіледі, немесе жеке басыңызды растаңыз: бұл тағы 5 орын.",
        "lu_slots_photo_d": "Қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — Kliko AI фотоны талдауды жалғастырады, немесе орын босатыңыз.",
        "lu_slots_photo_d_verify": "Қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — Kliko AI фотоны талдауды жалғастырады, немесе жеке басыңызды растаңыз: бұл тағы 5 орын.",
        "lu_held_d": "Хабарландыру сақталды, бірақ қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — ол бірден тексеруге және жариялауға жіберіледі, немесе орын босатыңыз.",
        "lu_held_d_verify": "Хабарландыру сақталды, бірақ қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз — ол бірден тексеруге және жариялауға жіберіледі, немесе жеке басыңызды растаңыз: бұл тағы 5 орын.",
        "lu_gate_d": "Қазір хабарландыруларыңыз ең көп мөлшерде. Лимитті кеңейтіңіз немесе орын босатыңыз — сонда жаңа хабарландыру бірден жариялауға жіберіледі. Оны қазір толтырып, кейін жариялауға да болады.",
        "lu_gate_d_free": "Қазір хабарландыруларыңыз ең көп мөлшерде. Орын босатыңыз — сонда жаңа хабарландыру бірден жариялауға жіберіледі. Оны қазір толтырып, кейін жариялауға да болады.",
        "lu_ai_t": "Kliko AI лимиті таусылды",
        "lu_ai_photo_d": "Kliko AI лимиті таусылды. Көбірек Kliko AI алыңыз — ол өрістерді фото бойынша қайта толтырады, немесе оларды қолмен толтырыңыз.",
        "lu_ai_svc_d": "Kliko AI лимиті таусылды. Көбірек Kliko AI алыңыз — ол хабарландыруды сипаттама бойынша жинайды, немесе оны қолмен толтырыңыз. Жоба сіздің сөздеріңізден жиналып қойды.",
        "lu_manual": "Өзім толтырамын",
        "lu_imp_ai_d": "Осы кезеңге Kliko AI талдаулары таусылды. Көбірек Kliko AI алыңыз — каталог талдауы жалғасады.",
        "lu_imp_ai_none": "Осы кезеңге Kliko AI талдаулары таусылды. Кейінірек көріңіз.",
        "lu_imp_verify_d": "Верификациядан өтіңіз — шек айына 50-ге дейін өседі. Немесе көбірек Kliko AI алыңыз.",
        "lu_imp_verify_only": "Верификациядан өтіңіз — шек айына 50-ге дейін өседі.",
        "lu_tryon_note": "Kliko AI пакетімен тәулігіне көбірек өлшеп көруге болады.",
        "lu_more_tryon": "Kliko AI-мен көбірек өлшеп көру",
        "lu_3d_note": "Көбірек Kliko AI алыңыз — тәулігіне 3D көбірек құрастыруға болады.",
        "lu_more_3d": "Kliko AI-мен көбірек құрастыру",
    ]

    private static let en: [String: String] = [
        "lu_expand": "Raise the limit",
        "lu_more_ai": "More Kliko AI",
        "lu_anyway": "Fill it in — I'll publish later",
        "lu_done": "Done — the service is on. Continuing…",
        "lu_used": "Used {n} of {m}",
        "lu_slots_d": "You're at your listing maximum. Raise the limit and the listing goes straight to publishing, or free up space.",
        "lu_slots_d_verify": "You're at your listing maximum. Raise the limit and the listing goes straight to publishing, or confirm your identity for 5 more spots.",
        "lu_slots_photo_d": "You're at your listing maximum. Raise the limit and Kliko AI will continue reading your photos, or free up space.",
        "lu_slots_photo_d_verify": "You're at your listing maximum. Raise the limit and Kliko AI will continue reading your photos, or confirm your identity for 5 more spots.",
        "lu_held_d": "Listing saved, but you're at your listing maximum. Raise the limit and it goes straight to review and publishing, or free up space.",
        "lu_held_d_verify": "Listing saved, but you're at your listing maximum. Raise the limit and it goes straight to review and publishing, or confirm your identity for 5 more spots.",
        "lu_gate_d": "You're at your listing maximum. Raise the limit or free up space and the new listing goes straight to publishing. You can also fill it in now and publish later.",
        "lu_gate_d_free": "You're at your listing maximum. Free up space and the new listing goes straight to publishing. You can also fill it in now and publish later.",
        "lu_ai_t": "Kliko AI limit reached",
        "lu_ai_photo_d": "Kliko AI limit reached. Get more Kliko AI and it will fill in the fields from your photos again, or fill them in yourself.",
        "lu_ai_svc_d": "Kliko AI limit reached. Get more Kliko AI and it will build the listing from your description, or fill it in yourself. A draft has already been made from your words.",
        "lu_manual": "I'll fill it in",
        "lu_imp_ai_d": "Kliko AI parsing for this period is used up. Get more Kliko AI and the catalog parsing will continue.",
        "lu_imp_ai_none": "Kliko AI parsing for this period is used up. Please try again later.",
        "lu_imp_verify_d": "Get verified — the limit grows to 50 a month. Or get more Kliko AI.",
        "lu_imp_verify_only": "Get verified — the limit grows to 50 a month.",
        "lu_tryon_note": "With a Kliko AI pack you get more try-ons per day.",
        "lu_more_tryon": "More try-ons with Kliko AI",
        "lu_3d_note": "Get more Kliko AI for more 3D builds per day.",
        "lu_more_3d": "More 3D builds with Kliko AI",
    ]

    private static let ar: [String: String] = [
        "lu_expand": "توسيع الحد",
        "lu_more_ai": "المزيد من Kliko AI",
        "lu_anyway": "املأ الآن — سأنشر لاحقًا",
        "lu_done": "تم — الخدمة مفعّلة. نتابع…",
        "lu_used": "مستخدم {n} من {m}",
        "lu_slots_d": "لديك الحد الأقصى من الإعلانات. وسّع الحد ليُرسَل الإعلان إلى النشر فورًا، أو أفرغ مكانًا.",
        "lu_slots_d_verify": "لديك الحد الأقصى من الإعلانات. وسّع الحد ليُرسَل الإعلان إلى النشر فورًا، أو أكّد هويتك لتحصل على 5 أماكن إضافية.",
        "lu_slots_photo_d": "لديك الحد الأقصى من الإعلانات. وسّع الحد ليتابع Kliko AI تحليل الصور، أو أفرغ مكانًا.",
        "lu_slots_photo_d_verify": "لديك الحد الأقصى من الإعلانات. وسّع الحد ليتابع Kliko AI تحليل الصور، أو أكّد هويتك لتحصل على 5 أماكن إضافية.",
        "lu_held_d": "تم حفظ الإعلان، لكن لديك الحد الأقصى من الإعلانات. وسّع الحد ليُرسَل فورًا إلى المراجعة والنشر، أو أفرغ مكانًا.",
        "lu_held_d_verify": "تم حفظ الإعلان، لكن لديك الحد الأقصى من الإعلانات. وسّع الحد ليُرسَل فورًا إلى المراجعة والنشر، أو أكّد هويتك لتحصل على 5 أماكن إضافية.",
        "lu_gate_d": "لديك الحد الأقصى من الإعلانات. وسّع الحد أو أفرغ مكانًا ليُرسَل الإعلان الجديد إلى النشر فورًا. يمكنك أيضًا ملؤه الآن ونشره لاحقًا.",
        "lu_gate_d_free": "لديك الحد الأقصى من الإعلانات. أفرغ مكانًا ليُرسَل الإعلان الجديد إلى النشر فورًا. يمكنك أيضًا ملؤه الآن ونشره لاحقًا.",
        "lu_ai_t": "تم بلوغ حد Kliko AI",
        "lu_ai_photo_d": "تم بلوغ حد Kliko AI. احصل على المزيد من Kliko AI ليملأ الحقول من الصور مجددًا، أو املأها بنفسك.",
        "lu_ai_svc_d": "تم بلوغ حد Kliko AI. احصل على المزيد من Kliko AI ليجمع الإعلان من وصفك، أو املأه بنفسك. تم إعداد مسودة من كلماتك.",
        "lu_manual": "سأملأ بنفسي",
        "lu_imp_ai_d": "انتهت تحليلات Kliko AI لهذه الفترة. احصل على المزيد من Kliko AI ليستمر تحليل الكتالوج.",
        "lu_imp_ai_none": "انتهت تحليلات Kliko AI لهذه الفترة. حاول لاحقًا.",
        "lu_imp_verify_d": "أكمل التحقق — سيرتفع الحد إلى 50 شهريًا. أو احصل على المزيد من Kliko AI.",
        "lu_imp_verify_only": "أكمل التحقق — سيرتفع الحد إلى 50 شهريًا.",
        "lu_tryon_note": "مع باقة Kliko AI تحصل على تجارب قياس أكثر يوميًا.",
        "lu_more_tryon": "تجارب قياس أكثر مع Kliko AI",
        "lu_3d_note": "احصل على المزيد من Kliko AI لعمليات تجميع ثلاثية الأبعاد أكثر يوميًا.",
        "lu_more_3d": "تجميع ثلاثي الأبعاد أكثر مع Kliko AI",
    ]
}
