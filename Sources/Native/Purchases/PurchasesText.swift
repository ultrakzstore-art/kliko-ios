import Foundation

/**
 Тексты покупок через App Store (платные услуги за Config.цифровыеПокупки). Языки: kk/ru/en; прочие — русский.
 Ни цен сайта, ни ссылок и слов об оплате на сайте здесь нет (правила 3.1.1 и 3.1.3).

 Слова сайта о самих услугах (пакеты, тарифы, «Слоты объявлений», «Пакеты Kliko AI», «Kliko PRO · Магазин») берутся
 из БизнесText — там они слово в слово с js/i18n-cabinet-ru.js. Здесь — только то, чего у сайта нет, потому что сайт
 продаёт за кошелёк, а приложение — через App Store: цена из App Store, «Восстановить покупки», отложенное зачисление,
 условия автопродления подписки (правило App Store 3.1.2), выбор объявления для продвижения.
 */
enum ПокупкиAppleText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
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

    /// Подпись кнопки, которая открывает окно покупки услуги.
    static func подписьУслуги(_ вид: ВидУслугиApple) -> String {
        switch вид {
        case .продвижение: return т("cta_promo")
        case .про: return т("cta_pro")
        case .слоты: return т("cta_slots")
        case .комбо: return т("cta_combo")
        case .пакетИИ: return т("cta_ai")
        case .топРезюме: return т("cta_resume")
        }
    }

    private static let ru: [String: String] = [
        "buy": "Купить",
        "buy_for": "Купить за {p}",
        "subscribe_for": "Оформить за {p}",
        "price_loading": "Цена загружается…",
        "not_in_store": "Эта услуга пока не продаётся в App Store.",
        "store_unavailable": "App Store сейчас недоступен. Попробуйте позже.",
        "store_error": "Покупка не прошла. Деньги не списаны.",
        "unverified": "App Store не подтвердил покупку. Если деньги списаны, нажмите «Восстановить покупки».",
        "done": "Готово — услуга подключена.",
        "saved_later": "Покупка сохранится и применится позже.",
        "saved_later_sub": "Оплата прошла, но сервер Kliko пока не ответил. Приложение повторит при следующем запуске — деньги не потеряются.",
        "ask_to_buy": "Покупка ждёт одобрения. Применим, как только App Store её подтвердит.",
        "need_login": "Войдите в кабинет, чтобы купить: услуга привязывается к вашему аккаунту Kliko.",
        "login": "Войти",
        "restore": "Восстановить покупки",
        "restore_done": "Покупки проверены. Всё оплаченное применено.",
        "restore_pending": "Покупок, которые ещё ждут подтверждения сервера Kliko: {n}. Применим позже.",
        "restore_fail": "Не удалось связаться с App Store. Попробуйте позже.",
        "pay_note": "Оплата через App Store: цена — в валюте вашего App Store, списание — с вашего Apple ID.",
        "sub_terms": "Подписка продлевается автоматически каждый месяц, если не отменить её хотя бы за 24 часа до конца периода. Деньги списываются с Apple ID при подтверждении покупки и при каждом продлении. Управлять подпиской и отменить её можно кнопкой «Управление подпиской» или в настройках Apple ID.",
        "manage_subs": "Управление подпиской",
        "offer": "Публичная оферта",
        "store_card": "Покупки через App Store",
        "cancelled": "Покупка отменена. Деньги не списаны.",
        "not_allowed": "Покупки запрещены на этом устройстве (Экранное время → Ограничения).",
        "one_time": "Разовая покупка",
        "sub_period": "Подписка · {n} · продлевается автоматически",
        "unit_day": "дн.",
        "unit_week": "нед.",
        "unit_month": "мес.",
        "unit_year": "г.",
        "ai_pack_btn": "Пакет Kliko AI",
        "cta_promo": "Продвинуть",
        "cta_pro": "Оформить PRO",
        "cta_slots": "Выбрать тариф слотов",
        "cta_combo": "Выбрать комбо-пакет",
        "cta_ai": "Выбрать пакет Kliko AI",
        "cta_resume": "Резюме в ТОП",
        "terms": "Пользовательское соглашение",
        "privacy": "Политика конфиденциальности",
        "apple_eula": "Условия использования (EULA)",
        "pick_listing": "Какое объявление продвинуть",
        "pick_listing_none": "Нет опубликованных объявлений — продвигать можно только опубликованное.",
        "pick_listing_first": "Сначала выберите объявление.",
        "promo_detail": "ТОП {d} дн. · поднятий: {b}",
        "promo_detail_top": "ТОП {d} дн.",
        "bump_title": "Поднятие",
        "bump_detail": "Поднимет объявление наверх выдачи один раз",
        "resume_top_title": "Резюме в ТОП",
        "resume_top_detail": "Резюме в ТОПе на 7 дней",
        "pro_month": "{n} · в месяц",
        "slots_row": "{n} объявлений",
        "slots_row_sub": "+{n} к бесплатным · тариф на 30 дней",
        "ai_row_sub": "Все Kliko AI-функции на {d} дн.",
        "promote_now": "Продвинуть объявление",
        "close": "Закрыть",
        "pending_banner": "Есть оплаченные покупки, которые ещё не применены. Применим автоматически.",
    ]

    private static let kk: [String: String] = [
        "buy": "Сатып алу",
        "buy_for": "{p} сатып алу",
        "subscribe_for": "{p} рәсімдеу",
        "price_loading": "Баға жүктелуде…",
        "not_in_store": "Бұл қызмет App Store-да әзірге сатылмайды.",
        "store_unavailable": "App Store қазір қолжетімсіз. Кейінірек көріңіз.",
        "store_error": "Сатып алу өтпеді. Ақша алынбады.",
        "unverified": "App Store сатып алуды растамады. Ақша алынса, «Сатып алуларды қалпына келтіру» басыңыз.",
        "done": "Дайын — қызмет қосылды.",
        "saved_later": "Сатып алу сақталады және кейінірек қолданылады.",
        "saved_later_sub": "Төлем өтті, бірақ Kliko сервері әлі жауап бермеді. Қосымша келесі іске қосқанда қайталайды — ақша жоғалмайды.",
        "ask_to_buy": "Сатып алу мақұлдауды күтуде. App Store растаған соң қолданамыз.",
        "need_login": "Сатып алу үшін кабинетке кіріңіз: қызмет Kliko аккаунтыңызға байланады.",
        "login": "Кіру",
        "restore": "Сатып алуларды қалпына келтіру",
        "restore_done": "Сатып алулар тексерілді. Төленгеннің бәрі қолданылды.",
        "restore_pending": "Kliko серверін күтіп тұрған сатып алулар: {n}. Кейінірек қолданамыз.",
        "restore_fail": "App Store-мен байланыс болмады. Кейінірек көріңіз.",
        "pay_note": "Төлем App Store арқылы: баға — App Store валютасында, ақша Apple ID-ден алынады.",
        "sub_terms": "Жазылым кезең аяқталуына кемінде 24 сағат қалғанда тоқтатылмаса, ай сайын автоматты түрде ұзартылады. Ақша сатып алуды растағанда және әр ұзартуда Apple ID-ден алынады. Жазылымды Apple ID баптауларында басқаруға және тоқтатуға болады.",
        "manage_subs": "Жазылымды басқару",
        "offer": "Жария оферта",
        "store_card": "App Store арқылы сатып алу",
        "cancelled": "Сатып алу тоқтатылды. Ақша алынбады.",
        "not_allowed": "Бұл құрылғыда сатып алуға тыйым салынған (Экран уақыты → Шектеулер).",
        "one_time": "Бір реттік сатып алу",
        "sub_period": "Жазылым · {n} · автоматты түрде ұзартылады",
        "unit_day": "күн",
        "unit_week": "апта",
        "unit_month": "ай",
        "unit_year": "жыл",
        "ai_pack_btn": "Kliko AI пакеті",
        "cta_promo": "Жарнамалау",
        "cta_pro": "PRO рәсімдеу",
        "cta_slots": "Слот тарифін таңдау",
        "cta_combo": "Комбо-пакет таңдау",
        "cta_ai": "Kliko AI пакетін таңдау",
        "cta_resume": "Түйіндеме ТОП-қа",
        "terms": "Пайдаланушы келісімі",
        "privacy": "Құпиялылық саясаты",
        "apple_eula": "Пайдалану шарттары (EULA)",
        "pick_listing": "Қай хабарландыруды жарнамалау",
        "pick_listing_none": "Жарияланған хабарландыру жоқ — тек жарияланғанды жарнамалауға болады.",
        "pick_listing_first": "Алдымен хабарландыруды таңдаңыз.",
        "promo_detail": "ТОП {d} күн · көтеру: {b}",
        "promo_detail_top": "ТОП {d} күн",
        "bump_title": "Көтеру",
        "bump_detail": "Хабарландыруды бір рет тізім басына көтереді",
        "resume_top_title": "Түйіндеме ТОП-қа",
        "resume_top_detail": "Түйіндеме 7 күн ТОП-та",
        "pro_month": "{n} · айына",
        "slots_row": "{n} хабарландыру",
        "slots_row_sub": "тегінге +{n} · 30 күндік тариф",
        "ai_row_sub": "Kliko AI-дың барлық мүмкіндігі {d} күнге",
        "promote_now": "Хабарландыруды жарнамалау",
        "close": "Жабу",
        "pending_banner": "Төленген, бірақ әлі қолданылмаған сатып алулар бар. Автоматты түрде қолданамыз.",
    ]

    private static let en: [String: String] = [
        "buy": "Buy",
        "buy_for": "Buy for {p}",
        "subscribe_for": "Subscribe for {p}",
        "price_loading": "Loading price…",
        "not_in_store": "This service is not on sale in the App Store yet.",
        "store_unavailable": "The App Store is unavailable right now. Please try later.",
        "store_error": "The purchase did not go through. You were not charged.",
        "unverified": "The App Store did not confirm the purchase. If you were charged, tap “Restore purchases”.",
        "done": "Done — the service is active.",
        "saved_later": "Your purchase is saved and will be applied later.",
        "saved_later_sub": "Payment went through, but the Kliko server has not answered yet. The app will retry on next launch — nothing is lost.",
        "ask_to_buy": "The purchase is waiting for approval. We will apply it once the App Store confirms it.",
        "need_login": "Sign in to your account to buy: the service is linked to your Kliko account.",
        "login": "Sign in",
        "restore": "Restore purchases",
        "restore_done": "Purchases checked. Everything paid has been applied.",
        "restore_pending": "Purchases still waiting for Kliko server confirmation: {n}. They will be applied later.",
        "restore_fail": "Could not reach the App Store. Please try later.",
        "pay_note": "Paid through the App Store: the price is in your App Store currency and is charged to your Apple ID.",
        "sub_terms": "The subscription renews automatically every month unless cancelled at least 24 hours before the end of the period. Payment is charged to your Apple ID at confirmation of purchase and at each renewal. You can manage or cancel it in your Apple ID settings.",
        "manage_subs": "Manage subscription",
        "offer": "Public offer",
        "store_card": "App Store purchases",
        "cancelled": "Purchase cancelled. You were not charged.",
        "not_allowed": "Purchases are not allowed on this device (Screen Time → Restrictions).",
        "one_time": "One-time purchase",
        "sub_period": "Subscription · {n} · renews automatically",
        "unit_day": "d.",
        "unit_week": "wk.",
        "unit_month": "mo.",
        "unit_year": "yr.",
        "ai_pack_btn": "Kliko AI pack",
        "cta_promo": "Promote",
        "cta_pro": "Get PRO",
        "cta_slots": "Choose a slots plan",
        "cta_combo": "Choose a combo pack",
        "cta_ai": "Choose a Kliko AI pack",
        "cta_resume": "Résumé to TOP",
        "terms": "Terms of service",
        "privacy": "Privacy policy",
        "apple_eula": "Terms of Use (EULA)",
        "pick_listing": "Which listing to promote",
        "pick_listing_none": "No published listings — only published ones can be promoted.",
        "pick_listing_first": "Choose a listing first.",
        "promo_detail": "TOP {d} days · bumps: {b}",
        "promo_detail_top": "TOP {d} days",
        "bump_title": "Bump",
        "bump_detail": "Moves the listing to the top of results once",
        "resume_top_title": "Résumé to TOP",
        "resume_top_detail": "Résumé in TOP for 7 days",
        "pro_month": "{n} · per month",
        "slots_row": "{n} listings",
        "slots_row_sub": "+{n} to the free ones · 30-day plan",
        "ai_row_sub": "All Kliko AI features for {d} days",
        "promote_now": "Promote the listing",
        "close": "Close",
        "pending_banner": "Some paid purchases are not applied yet. They will be applied automatically.",
    ]
}
