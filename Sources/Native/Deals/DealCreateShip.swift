import SwiftUI
import CoreLocation

/**
 ДОСТАВКА В ОКНЕ «БЕЗОПАСНАЯ СДЕЛКА» (владелец, TestFlight: «в своём городе не нашёл расчёт курьера Яндекса, как на сайте»).

 Образец — окно _mkEcoGo сайта (js/marketplace.min.js): блок «Как получить» (mkEcoShipOptsHtml) и «Куда привезти».
   · Адрес по умолчанию — GET escrow.php?action=recv_default → addr, lat, lon, door{flat,porch,floor,code,out};
     «Изменить адрес» — своё окно карты (ЛистТочкиСделки без сделки).
   · Цена — GET /api/ship_quote.php?item=<pid>&lat=&lon=[&dd=out][&a=<адрес ≤200>] (mkEcoShipQuote, от корня):
       reason "off" — блока нет; mode "carriers" + offers — межгород: транспортные компании (СДЭК…) «до пункта
       выдачи» / «до двери», срок, цена, пункт выдачи (points); пусто или reason "intercity" — «Дальше 30 км
       доставляем только СДЭК…»; бесплатная доставка продавца — free + courier (Яндекс), free у СДЭК (price 0) или free + why (причина); иначе курьер Яндекса: tariff
       и alt — «Пеший курьер · дешевле» / «Экспресс — быстрее · на машине», или одна строка «Курьер Яндекса»
       с «~N мин в пути»; всегда рядом «Заберу сам · 0 ₸» (кроме межгорода — у сайта его там нет).
   · Цена выбранной доставки входит в «К заморозке» строкой «Доставка курьером» / «Доставка {name}».
   · create (mkEcoPay): to_addr, to_lat, to_lon; с доставкой — ship ("yandex" | "carrier"), ship_q, car_pvz (до
     пункта выдачи), to_door; ответ error "ship_quote" (reason "pvz") — «Цену доставки пересчитали…» и новый расчёт.
 Трек-номер межгорода выдаёт сама транспортная компания, когда продавец оформит отправку (car_order), — он появится
 в карточке сделки (БлокПеревозчика и «Отслеживание»).
 */

// MARK: - Тексты (i18n-marketplace-ru.js сайта; остальные языки — перевод)

enum ДоставкаСделкиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ДеньгиСделкиText.т(ключ)
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "co_ship_pick": "Как получить",
        "co_ship_ya": "Курьер Яндекса",
        "co_ship_ya_s": "оплата сейчас, в сумме покупки",
        "ship_eta": "~{n} мин в пути",
        "co_ship_free_b": "Бесплатно",
        "co_ship_free_s": "оплачивает продавец",
        "co_ship_self2": "Заберу сам",
        "co_ship_self2_s": "без доставки",
        "co_ship_walk_s": "дешевле",
        "co_ship_exp_s": "на машине",
        "co_car_pvz": "до пункта выдачи",
        "co_car_door": "до двери",
        "co_car_days": "{a}–{b} дн.",
        "co_car_days1": "{n} дн.",
        "co_car_pt": "Пункт выдачи",
        "co_ship_calc": "считаем цену…",
        "co_ship_calc2": "Считаем доставку…",
        "co_ship_addr_first": "Укажите адрес — покажем доставку и цену",
        "co_ship_house": "уточните дом на карте",
        "co_ship_none": "Доставку для этого объявления не посчитать — заберите сами или договоритесь с продавцом",
        "co_ship_retry2": "Не удалось посчитать доставку — нажмите, чтобы повторить",
        "co_ship_na": "сюда курьер не возит",
        "co_ship_why": "Ответ службы доставки: {r}",
        "co_ship_same": "Транспортные компании (СДЭК) — только в другой город. В своём городе — курьер Яндекса или «Заберу сам».",
        "co_ship_intercity": "В другой город отправляем через СДЭК, но сейчас он не смог рассчитать доставку этого товара. Выберите «Заберу сам» или напишите продавцу, чтобы договориться об отправке.",
        "co_ship_region": "Продавец не отправляет в ваш регион — можно договориться о встрече или забрать самому.",
        "co_ship_free": "Доставка бесплатно — оплачивает продавец",
        "co_ship_free_no_from": "Продавец не отметил точку, откуда забрать товар, поэтому курьера сейчас не посчитать. Выберите «Заберу сам» — после оплаты курьера Яндекса можно вызвать в сделке бесплатно, когда продавец отметит точку забора.",
        "co_ship_free_costly": "Доставка стоит дороже, чем продавец получит за товар, — бесплатно её так не оформить. Договоритесь с продавцом в чате или выберите «Заберу сам».",
        "co_ship_free_self": "Как привезти товар бесплатно, договоритесь с продавцом в чате сделки или выберите «Заберу сам».",
        "co_ship_row": "Доставка курьером",
        "co_ship_row_car": "Доставка {name}",
        "co_to": "Куда привезти",
        "co_addr_edit": "Изменить адрес",
        "co_addr_set": "Указать на карте",
        "co_addr_none": "Адрес не указан",
        "co_ship_wait": "Считаем цену курьера…",
        "co_ship_need": "Укажите адрес или выберите «Заберу сам».",
        "co_car_pvz_need": "Выберите пункт выдачи",
        "co_car_pvz_bad": "Этот пункт выдачи не подходит к цене — выбрали другой. Проверьте пункт и нажмите ещё раз.",
        "co_ship_changed": "Цену доставки пересчитали — проверьте сумму и нажмите ещё раз",
        "co_car_track": "Трек-номер выдаст транспортная компания, когда продавец сдаст посылку, — он появится в сделке.",
        "ship_estimating": "Оцениваем стоимость доставки…",
        "ship_estimating_ya": "Оцениваем стоимость курьера…",
        "ship_est_cdek": "СДЭК: цена, срок и пункты выдачи",
        "ship_est_ya": "Курьер Яндекса: цена и время в пути",
        "ship_est_any": "Подбираем способ доставки по вашему адресу",
        "co_ship_house_btn": "Уточнить дом на карте",
        "co_ship_house_why": "Без точного дома доставку не посчитать — поставьте точку на карте, и цена появится сразу.",
        "car_calc_h": "Сколько стоит доставка до вас",
        "car_go_hint": "Выбранный вариант СДЭК и пункт выдачи перейдут в сделку",
        "ship_other_city": "Это другой город — туда возит только СДЭК: посчитайте в блоке «Доставка в другой город»."
    ]

    private static let kk: [String: String] = [
        "co_ship_pick": "Қалай алу керек",
        "co_ship_ya": "Яндекс курьері",
        "co_ship_ya_s": "төлем қазір, сатып алу сомасында",
        "ship_eta": "Жолда ~{n} мин",
        "co_ship_free_b": "Тегін",
        "co_ship_free_s": "сатушы төлейді",
        "co_ship_self2": "Өзім алып кетемін",
        "co_ship_self2_s": "жеткізусіз",
        "co_ship_walk_s": "арзанырақ",
        "co_ship_exp_s": "көлікпен",
        "co_car_pvz": "беру пунктіне дейін",
        "co_car_door": "есікке дейін",
        "co_car_days": "{a}–{b} күн",
        "co_car_days1": "{n} күн",
        "co_car_pt": "Беру пункті",
        "co_ship_calc": "бағасын есептеп жатырмыз…",
        "co_ship_calc2": "Жеткізуді есептеп жатырмыз…",
        "co_ship_addr_first": "Мекенжайды көрсетіңіз — жеткізу мен бағасын көрсетеміз",
        "co_ship_house": "үйді картада нақтылаңыз",
        "co_ship_none": "Бұл хабарландыруға жеткізуді есептеу мүмкін емес — өзіңіз алыңыз немесе сатушымен келісіңіз",
        "co_ship_retry2": "Жеткізуді есептеу мүмкін болмады — қайталау үшін басыңыз",
        "co_ship_na": "мұнда курьер апармайды",
        "co_ship_why": "Жеткізу қызметінің жауабы: {r}",
        "co_ship_same": "Көлік компаниялары (СДЭК) — тек басқа қалаға. Өз қалаңызда — Яндекс курьері немесе «Өзім аламын».",
        "co_ship_intercity": "Басқа қалаға СДЭК арқылы жібереміз, бірақ қазір ол бұл тауардың жеткізуін есептей алмады. «Өзім аламын» таңдаңыз немесе жіберу туралы келісу үшін сатушыға жазыңыз.",
        "co_ship_region": "Сатушы сіздің өңіріңізге жібермейді — кездесуге келісуге немесе өзіңіз алып кетуге болады.",
        "co_ship_free": "Жеткізу тегін — сатушы төлейді",
        "co_ship_free_no_from": "Сатушы тауарды қайдан алу нүктесін белгілемеген, сондықтан курьерді қазір есептеу мүмкін емес. «Өзім алып кетемін» таңдаңыз — төлегеннен кейін сатушы алу нүктесін белгілегенде, Яндекс курьерін мәміледе тегін шақыруға болады.",
        "co_ship_free_costly": "Жеткізу сатушы тауар үшін алатын сомадан қымбат — тегін жеткізуді бұлай рәсімдеу мүмкін емес. Сатушымен чатта келісіңіз немесе «Өзім алып кетемін» таңдаңыз.",
        "co_ship_free_self": "Тауарды тегін қалай жеткізуді сатушымен мәміле чатында келісіңіз немесе «Өзім алып кетемін» таңдаңыз.",
        "co_ship_row": "Курьермен жеткізу",
        "co_ship_row_car": "Жеткізу: {name}",
        "co_to": "Қайда жеткізу",
        "co_addr_edit": "Мекенжайды өзгерту",
        "co_addr_set": "Картада көрсету",
        "co_addr_none": "Мекенжай көрсетілмеген",
        "co_ship_wait": "Курьер бағасын есептеп жатырмыз…",
        "co_ship_need": "Мекенжайды көрсетіңіз немесе «Өзім алып кетемін» таңдаңыз.",
        "co_car_pvz_need": "Беру пунктін таңдаңыз",
        "co_car_pvz_bad": "Бұл беру пункті бағаға сай емес — басқасын таңдадық. Пунктті тексеріп, қайта басыңыз.",
        "co_ship_changed": "Жеткізу бағасы қайта есептелді — соманы тексеріп, қайта басыңыз",
        "co_car_track": "Трек-нөмірді сатушы сәлемдемені тапсырғанда көлік компаниясы береді — ол мәміледе шығады.",
        "ship_estimating": "Жеткізу құнын бағалап жатырмыз…",
        "ship_estimating_ya": "Курьер құнын бағалап жатырмыз…",
        "ship_est_cdek": "СДЭК: баға, мерзім және беру пункттері",
        "ship_est_ya": "Яндекс курьері: баға және жолдағы уақыт",
        "ship_est_any": "Мекенжайыңыз бойынша жеткізу тәсілін таңдап жатырмыз",
        "co_ship_house_btn": "Үйді картада нақтылау",
        "co_ship_house_why": "Нақты үйсіз жеткізуді есептеу мүмкін емес — картада нүкте қойыңыз, баға бірден шығады.",
        "car_calc_h": "Сізге дейін жеткізу қанша тұрады",
        "car_go_hint": "Таңдалған СДЭК нұсқасы мен беру пункті мәмілеге өтеді",
        "ship_other_city": "Бұл басқа қала — онда тек СДЭК жеткізеді: «Басқа қалаға жеткізу» блогында есептеңіз."
    ]

    private static let en: [String: String] = [
        "co_ship_pick": "How to receive",
        "co_ship_ya": "Yandex courier",
        "co_ship_ya_s": "paid now, included in the total",
        "ship_eta": "~{n} min on the way",
        "co_ship_free_b": "Free",
        "co_ship_free_s": "paid by the seller",
        "co_ship_self2": "I'll pick it up",
        "co_ship_self2_s": "no delivery",
        "co_ship_walk_s": "cheaper",
        "co_ship_exp_s": "by car",
        "co_car_pvz": "to a pickup point",
        "co_car_door": "to the door",
        "co_car_days": "{a}–{b} days",
        "co_car_days1": "{n} days",
        "co_car_pt": "Pickup point",
        "co_ship_calc": "calculating…",
        "co_ship_calc2": "Calculating delivery…",
        "co_ship_addr_first": "Enter an address — we'll show delivery and the price",
        "co_ship_house": "pin the building on the map",
        "co_ship_none": "Delivery can't be calculated for this listing — pick it up or agree with the seller",
        "co_ship_retry2": "Couldn't calculate delivery — tap to retry",
        "co_ship_na": "couriers don't deliver here",
        "co_ship_why": "Delivery service reply: {r}",
        "co_ship_same": "Shipping companies (CDEK) are only for another city. Within your city — Yandex courier or pickup.",
        "co_ship_intercity": "We ship to other cities with CDEK, but it couldn't price delivery for this item right now. Choose pickup or message the seller to arrange shipping.",
        "co_ship_region": "The seller doesn't ship to your region — you can arrange a meeting or pick it up yourself.",
        "co_ship_free": "Free delivery — paid by the seller",
        "co_ship_free_no_from": "The seller hasn't marked where to pick the item up, so the courier can't be priced yet. Choose «I'll pick it up» — after payment you can call a Yandex courier in the deal for free once the seller sets the pickup point.",
        "co_ship_free_costly": "Delivery costs more than the seller gets for the item, so it can't be made free this way. Agree with the seller in the chat or choose «I'll pick it up».",
        "co_ship_free_self": "Agree with the seller in the deal chat on how to deliver the item for free, or choose «I'll pick it up».",
        "co_ship_row": "Courier delivery",
        "co_ship_row_car": "Delivery {name}",
        "co_to": "Deliver to",
        "co_addr_edit": "Change address",
        "co_addr_set": "Set on the map",
        "co_addr_none": "No address yet",
        "co_ship_wait": "Calculating the courier price…",
        "co_ship_need": "Enter an address or choose “I'll pick it up”.",
        "co_car_pvz_need": "Choose a pickup point",
        "co_car_pvz_bad": "That pickup point doesn't match the price — we picked another. Check it and tap again.",
        "co_ship_changed": "The delivery price was recalculated — check the total and tap again",
        "co_car_track": "The shipping company issues the tracking number when the seller drops off the parcel — it will appear in the deal.",
        "ship_estimating": "Estimating the delivery cost…",
        "ship_estimating_ya": "Estimating the courier cost…",
        "ship_est_cdek": "CDEK: price, time and pickup points",
        "ship_est_ya": "Yandex courier: price and travel time",
        "ship_est_any": "Choosing the delivery option for your address",
        "co_ship_house_btn": "Pin the building on the map",
        "co_ship_house_why": "Delivery can't be priced without the exact building — drop a pin on the map and the price appears right away.",
        "car_calc_h": "Delivery cost to you",
        "car_go_hint": "The chosen CDEK option and pickup point go into the deal",
        "ship_other_city": "That's another city — only CDEK delivers there: calculate it in the «Delivery to another city» block."
    ]

    private static let ar: [String: String] = [
        "co_ship_pick": "طريقة الاستلام",
        "co_ship_ya": "مندوب ياندكس",
        "co_ship_ya_s": "الدفع الآن ضمن المبلغ",
        "ship_eta": "~{n} دقيقة في الطريق",
        "co_ship_free_b": "مجانًا",
        "co_ship_free_s": "يدفعه البائع",
        "co_ship_self2": "سأستلمه بنفسي",
        "co_ship_self2_s": "بدون توصيل",
        "co_ship_walk_s": "أرخص",
        "co_ship_exp_s": "بالسيارة",
        "co_car_pvz": "إلى نقطة الاستلام",
        "co_car_door": "حتى الباب",
        "co_car_days": "{a}–{b} يوم",
        "co_car_days1": "{n} يوم",
        "co_car_pt": "نقطة الاستلام",
        "co_ship_calc": "نحسب السعر…",
        "co_ship_calc2": "نحسب التوصيل…",
        "co_ship_addr_first": "أدخل العنوان — وسنعرض التوصيل والسعر",
        "co_ship_house": "حدّد المبنى على الخريطة",
        "co_ship_none": "لا يمكن حساب التوصيل لهذا الإعلان — استلمه بنفسك أو اتفق مع البائع",
        "co_ship_retry2": "تعذّر حساب التوصيل — اضغط للمحاولة مجددًا",
        "co_ship_na": "المندوب لا يوصل إلى هنا",
        "co_ship_why": "رد خدمة التوصيل: {r}",
        "co_ship_same": "شركات الشحن (CDEK) للمدن الأخرى فقط. داخل مدينتك — مندوب Yandex أو الاستلام بنفسك.",
        "co_ship_intercity": "نشحن إلى المدن الأخرى عبر CDEK، لكنه لم يتمكن الآن من حساب توصيل هذه السلعة. اختر الاستلام بنفسك أو راسل البائع للاتفاق على الشحن.",
        "co_ship_region": "البائع لا يشحن إلى منطقتك — يمكنكما الاتفاق على لقاء أو الاستلام بنفسك.",
        "co_ship_free": "التوصيل مجاني — يدفعه البائع",
        "co_ship_free_no_from": "لم يحدّد البائع مكان استلام السلعة، لذا لا يمكن حساب المندوب الآن. اختر «سأستلمه بنفسي» — بعد الدفع يمكنك طلب مندوب Yandex في الصفقة مجانًا عندما يحدّد البائع نقطة الاستلام.",
        "co_ship_free_costly": "التوصيل أغلى مما سيحصل عليه البائع مقابل السلعة، لذا لا يمكن جعله مجانيًا هكذا. اتفق مع البائع في المحادثة أو اختر «سأستلمه بنفسي».",
        "co_ship_free_self": "اتفق مع البائع في محادثة الصفقة على طريقة توصيل السلعة مجانًا، أو اختر «سأستلمه بنفسي».",
        "co_ship_row": "توصيل بالمندوب",
        "co_ship_row_car": "توصيل {name}",
        "co_to": "عنوان التوصيل",
        "co_addr_edit": "تغيير العنوان",
        "co_addr_set": "حدّد على الخريطة",
        "co_addr_none": "لم يُحدَّد العنوان",
        "co_ship_wait": "نحسب سعر المندوب…",
        "co_ship_need": "أدخل العنوان أو اختر «سأستلمه بنفسي».",
        "co_car_pvz_need": "اختر نقطة الاستلام",
        "co_car_pvz_bad": "نقطة الاستلام هذه لا تناسب السعر — اخترنا غيرها. تحقّق واضغط مجددًا.",
        "co_ship_changed": "أُعيد حساب سعر التوصيل — تحقّق من المبلغ واضغط مجددًا",
        "co_car_track": "رقم التتبع تصدره شركة النقل عندما يسلّم البائع الطرد — وسيظهر في الصفقة.",
        "ship_estimating": "نقدّر تكلفة التوصيل…",
        "ship_estimating_ya": "نقدّر تكلفة المندوب…",
        "ship_est_cdek": "CDEK: السعر والمدة ونقاط الاستلام",
        "ship_est_ya": "مندوب ياندكس: السعر ووقت الطريق",
        "ship_est_any": "نختار طريقة التوصيل حسب عنوانك",
        "co_ship_house_btn": "حدّد المبنى على الخريطة",
        "co_ship_house_why": "لا يمكن حساب التوصيل دون المبنى بالضبط — ضع نقطة على الخريطة وسيظهر السعر فورًا.",
        "car_calc_h": "تكلفة التوصيل إليك",
        "car_go_hint": "سينتقل خيار CDEK ونقطة الاستلام المختاران إلى الصفقة",
        "ship_other_city": "هذه مدينة أخرى — يوصل إليها CDEK فقط: احسبها في قسم «التوصيل إلى مدينة أخرى»."
    ]
}

// MARK: - Данные

/// Вариант доставки: тариф курьера Яндекса (courier / express) или предложение транспортной компании.
struct ВариантДоставкиСделки: Identifiable, Equatable {
    /// Ключ offers сайта: courier, express или ключ предложения перевозчика.
    let id: String
    let цена: Int
    let минут: Int
    let q: String
    let бесплатно: Bool
    /// Код перевозчика (cdek…); пусто — курьер Яндекса.
    let перевозчик: String
    let имя: String
    let доПВЗ: Bool
    let днейОт: Int
    let днейДо: Int

    var транспортнаяКомпания: Bool { !перевозчик.isEmpty }
}

/// Пункт выдачи перевозчика (points ответа ship_quote).
struct ПунктВыдачиСделки: Identifiable, Equatable {
    let id: String
    let адрес: String
    let км: Double?
}

/// Что сейчас в блоке «Как получить».
enum РасчётДоставкиСделки: Equatable {
    case нетАдреса
    case считаем
    case нужнаТочка
    /// slow_down / net / unavailable — «нажмите, чтобы повторить».
    case сбой
    /// Прочий отказ: код причины сервера (no_courier, no…) и его пояснение для человека (пусто — нечего показать).
    case нельзя(String, String)
    case межгородНельзя
    case регион
    case курьер([ВариантДоставкиСделки])
    case перевозчики([ВариантДоставкиСделки], [String: [ПунктВыдачиСделки]])
}

// MARK: - Правило владельца: свой город — курьер Яндекса, другой город — только СДЭК

enum ПравилоДоставкиСДЭК {
    /// Предложение или компания — СДЭК: по коду (cdek) или названию.
    static func этоСДЭК(код: String, имя: String) -> Bool {
        let к = код.lowercased()
        let и = имя.lowercased()
        return к.contains("cdek") || к.contains("sdek") || и.contains("сдэк") || и.contains("сдек") || и.contains("cdek")
    }
}

/// Чей расчёт идёт: значок полосы прогресса.
enum ВидПеревозчикаРасчёта: Equatable {
    case любой, яндекс, сдэк
}

// MARK: - Адрес из листа «Курьер по городу»

/**
 Лист курьера объявления обещает «адрес уходит в сделку»: перед «Купить безопасно с доставкой» он кладёт сюда ваш
 адрес (и точку, если она определена), окно сделки того же объявления забирает его вместо recv_default. У сайта
 этого нет (его окно берёт только recv_default) — своё, чтобы обещание было правдой. Живёт 10 минут и один раз.
 */
@MainActor
enum АдресИзЛистаКурьера {
    struct Запись {
        let товар: String
        let текст: String
        let точка: ТочкаСделки?
        let когда: Date
        /// Выбранное в окне объявления («Доставка в другой город»): ключ предложения, код перевозчика, пункт выдачи.
        var тариф: String = ""
        var перевозчик: String = ""
        var пункт: String = ""
        var дверь: [String: Any] = [:]
        var уПодъезда = false
    }

    private static var запись: Запись? = nil

    static func положить(товар: String, текст: String, широта: Double?, долгота: Double?,
                         тариф: String = "", перевозчик: String = "", пункт: String = "",
                         дверь: [String: Any] = [:], уПодъезда: Bool = false) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else {
            запись = nil
            return
        }
        запись = Запись(товар: товар, текст: чистый, точка: ТочкаСделки(широта, долгота), когда: Date(),
                        тариф: тариф, перевозчик: перевозчик, пункт: пункт, дверь: дверь, уПодъезда: уПодъезда)
    }

    static func забрать(товар: String) -> Запись? {
        guard let есть = запись else { return nil }
        запись = nil
        guard есть.товар == товар, Date().timeIntervalSince(есть.когда) < 600 else { return nil }
        return есть
    }
}

// MARK: - Модель доставки окна

@MainActor
final class ДоставкаНовойСделки: ObservableObject {
    struct Адрес {
        var текст: String
        var точка: ТочкаСделки?
        /// to_door: {flat, porch, floor, code, note?} или {out:true, note?}.
        var дверь: [String: Any]
        var уПодъезда: Bool
    }

    @Published private(set) var адрес: Адрес? = nil
    @Published private(set) var расчёт: РасчётДоставкиСделки = .нетАдреса
    /// reason "off" или бесплатная доставка без курьера — блока «Как получить» нет.
    @Published private(set) var скрыт = false
    /// Бесплатная доставка продавца (ship_free) — строка «Доставка за счёт продавца».
    @Published private(set) var бесплатная = false
    @Published private(set) var самЗаберу = false
    @Published private(set) var тариф = ""
    /// Выбранный пункт выдачи по коду перевозчика (_mkEcoPvz).
    @Published private(set) var пункты: [String: String] = [:]
    /// Блок включён (товар, не задаток и не аренда).
    @Published private(set) var включена = false
    /// Чей расчёт ждём — значок в полосе «Оцениваем стоимость доставки…».
    @Published private(set) var видРасчёта: ВидПеревозчикаРасчёта = .любой

    private var товар = ""
    private var номерРасчёта = 0

    private func т(_ ключ: String) -> String { ДоставкаСделкиText.т(ключ) }

    /// Окно открыто: адрес по умолчанию и расчёт, как _mkEcoGo сайта.
    func начать(товар: String, бесплатная: Bool) async {
        self.товар = товар
        self.бесплатная = бесплатная
        /* _mkEcoTariff = "courier" сайта: из двух тарифов сначала отмечен пеший. */
        тариф = "courier"
        скрыт = бесплатная
        включена = true
        /* «Купить безопасно с доставкой» из листа курьера: адрес оттуда — вместо адреса по умолчанию. */
        if let изЛиста = АдресИзЛистаКурьера.забрать(товар: товар) {
            /* Из «Доставка в другой город»: выбранное там предложение СДЭК и пункт выдачи — сразу отмечены. */
            if !изЛиста.тариф.isEmpty { тариф = изЛиста.тариф }
            if !изЛиста.перевозчик.isEmpty {
                видРасчёта = .сдэк
                if !изЛиста.пункт.isEmpty { пункты[изЛиста.перевозчик] = изЛиста.пункт }
            }
            применить(Адрес(текст: изЛиста.текст, точка: изЛиста.точка, дверь: изЛиста.дверь,
                            уПодъезда: изЛиста.уПодъезда))
            return
        }
        guard let j = try? await ДеньгиСделкиAPI.получить("escrow.php?action=recv_default"),
              СделкиAPI.да(j["ok"]) else { return }
        let текст = СделкиAPI.строка(j["addr"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !текст.isEmpty, адрес == nil else { return }
        let д = (j["door"] as? [String: Any]) ?? [:]
        let уПодъезда = СделкиAPI.да(д["out"])
        var дверь: [String: Any] = [:]
        if уПодъезда {
            дверь["out"] = true
        } else {
            for ключ in ["flat", "porch", "floor", "code"] {
                let значение = СделкиAPI.строка(д[ключ]).trimmingCharacters(in: .whitespaces)
                if !значение.isEmpty { дверь[ключ] = значение }
            }
        }
        let точка = ТочкаСделки(СделкиAPI.координата(j["lat"]), СделкиAPI.координата(j["lon"]))
        применить(Адрес(текст: текст, точка: точка, дверь: дверь, уПодъезда: уПодъезда))
    }

    /// Адрес из окна карты.
    func выбран(_ а: АдресИзКарты) {
        let точка = а.точка.flatMap { ТочкаСделки($0.latitude, $0.longitude) }
        применить(Адрес(текст: а.адрес, точка: точка, дверь: а.дверь, уПодъезда: а.уПодъезда))
    }

    /**
     Адрес без точки (recv_default без lat/lon — «проспект Абая, 30, Астана» у владельца): как _mkEcoGeo сайта — строку
     ≥ 8 знаков ищем геокодером, и только найденный дом даёт точку и расчёт; иначе «уточните дом на карте» с кнопкой карты.
     */
    private func применить(_ а: Адрес) {
        адрес = а
        if а.точка != nil {
            посчитать()
            return
        }
        номерРасчёта += 1
        let мой = номерРасчёта
        let текст = а.текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard текст.count >= 8 else {
            расчёт = .нужнаТочка
            return
        }
        расчёт = .считаем
        Task { @MainActor [weak self] in
            let найдено = await ДоставкаНовойСделки.точкаДома(текст)
            guard let self, мой == self.номерРасчёта, var текущий = self.адрес else { return }
            guard let найдено else {
                self.расчёт = .нужнаТочка
                return
            }
            текущий.точка = найдено
            self.адрес = текущий
            self.посчитать()
        }
    }

    /// Точка дома по строке адреса: геокодер телефона, только Казахстан и только с номером дома (house у сайта).
    private static func точкаДома(_ текст: String) async -> ТочкаСделки? {
        let метки = try? await CLGeocoder().geocodeAddressString(текст, in: nil,
                                                                 preferredLocale: Locale(identifier: "ru_KZ"))
        guard let метка = метки?.first, let место = метка.location else { return nil }
        if let страна = метка.isoCountryCode, !страна.isEmpty, страна != "KZ" { return nil }
        guard let дом = метка.subThoroughfare, !дом.isEmpty else { return nil }
        return ТочкаСделки(место.coordinate.latitude, место.coordinate.longitude)
    }

    /// Какой перевозчик ожидается, пока идёт расчёт (значок в полосе прогресса).
    func ожидать(_ вид: ВидПеревозчикаРасчёта) {
        видРасчёта = вид
    }

    /// Выбор строки: nil — «Заберу сам» (mkEcoShipPick).
    func выбрать(_ вариант: ВариантДоставкиСделки?) {
        guard let вариант else {
            самЗаберу = true
            return
        }
        самЗаберу = false
        тариф = вариант.id
        if вариант.доПВЗ {
            /* Как у сайта: выбранный раньше пункт, если он есть в списке, иначе первый. */
            let список = списокПунктов(вариант)
            let текущий = пункты[вариант.перевозчик] ?? ""
            if !список.contains(where: { $0.id == текущий }), let первый = список.first {
                пункты[вариант.перевозчик] = первый.id
            }
        }
    }

    func выбратьПункт(_ код: String, для вариант: ВариантДоставкиСделки) {
        пункты[вариант.перевозчик] = код
    }

    func списокПунктов(_ вариант: ВариантДоставкиСделки) -> [ПунктВыдачиСделки] {
        if case .перевозчики(_, let все) = расчёт { return все[вариант.перевозчик] ?? [] }
        return []
    }

    /// Выбранная доставка (k сайта): есть цена и не «Заберу сам».
    var выбранная: ВариантДоставкиСделки? {
        guard включена, !скрыт, !самЗаберу else { return nil }
        switch расчёт {
        case .курьер(let список), .перевозчики(let список, _):
            return список.first(where: { $0.id == тариф }) ?? список.first
        default:
            return nil
        }
    }

    var цена: Int { выбранная?.цена ?? 0 }

    /// «Заберу сам» отмечено: выбрано человеком или курьер сюда не возит (a = !_mkEcoSelf && i сайта).
    var самОтмечено: Bool {
        if самЗаберу { return true }
        if case .нельзя = расчёт { return true }
        return false
    }

    /// Подпись строки итогов: «Доставка курьером» / «Доставка СДЭК».
    var подписьЦены: String {
        guard let в = выбранная, в.транспортнаяКомпания else { return т("co_ship_row") }
        return т("co_ship_row_car").replacingOccurrences(of: "{name}", with: в.имя)
    }

    /// Повторить расчёт (сбой сети, «нажмите ещё раз»).
    func повторить() {
        if адрес?.точка != nil { посчитать() }
    }

    // MARK: Расчёт (mkEcoShipQuote)

    private func посчитать() {
        guard let а = адрес, let точка = а.точка, !товар.isEmpty else { return }
        номерРасчёта += 1
        let мой = номерРасчёта
        расчёт = .считаем
        /* Как mkEcoShipQuote сайта: _MKB + "api/ship_quote.php" — от корня (_ULX_BASE = ""), не /kz/<язык>/. */
        var хвост = "/api/ship_quote.php?item=" + Self.вАдрес(товар)
        хвост += "&lat=" + String(точка.широта) + "&lon=" + String(точка.долгота)
        if а.уПодъезда { хвост += "&dd=out" }
        let кратко = String(а.текст.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if !кратко.isEmpty { хвост += "&a=" + Self.вАдрес(кратко) }
        let запрос = хвост
        Task { @MainActor [weak self] in
            let ответ = try? await СделкиAPI.получить(запрос, отКорня: true)
            guard let self, мой == self.номерРасчёта else { return }
            guard let j = ответ else {
                self.расчёт = .сбой
                return
            }
            self.разобрать(j)
        }
    }

    private func разобрать(_ j: [String: Any]) {
        typealias A = СделкиAPI
        let причина = A.строка(j["reason"])
        if причина == "off" {
            скрыт = true
            расчёт = .нетАдреса
            return
        }
        if A.да(j["ok"]), A.строка(j["mode"]) == "carriers", j["offers"] is [String: Any] || j["offers"] is [Any] {
            скрыт = false
            видРасчёта = .сдэк
            /* offers — объект по ключам (у сайта) или, бывает, массив: разбираем оба, чтобы СДЭК не терялся. */
            var сырые: [(String, [String: Any])] = []
            if let словарь = j["offers"] as? [String: Any] {
                for ключ in словарь.keys.sorted() {
                    if let п = словарь[ключ] as? [String: Any] { сырые.append((ключ, п)) }
                }
            } else if let массив = j["offers"] as? [Any] {
                for (номер, значение) in массив.enumerated() {
                    guard let п = значение as? [String: Any] else { continue }
                    let свой = A.строка(п["key"])
                    сырые.append((свой.isEmpty ? "o" + String(номер) : свой, п))
                }
            }
            var список: [ВариантДоставкиСделки] = []
            /* Бесплатная доставка продавца (патч 46 сервера): price 0 и free — «Бесплатно», платит продавец. */
            let всеБесплатно = A.да(j["free"])
            for (ключ, п) in сырые {
                let q = A.строка(п["q"])
                let бесплатноТут = всеБесплатно || A.да(п["free"])
                let цена = бесплатноТут ? 0 : A.целое(п["price"])
                guard !q.isEmpty, цена > 0 || бесплатноТут else { continue }
                let перевозчик = A.строка(п["carrier"])
                let имя = A.строка(п["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
                /* Правило владельца: в другой город — только СДЭК, других компаний не показываем. */
                guard ПравилоДоставкиСДЭК.этоСДЭК(код: перевозчик, имя: имя) else { continue }
                список.append(ВариантДоставкиСделки(id: ключ, цена: цена, минут: 0, q: q, бесплатно: бесплатноТут,
                                                    перевозчик: перевозчик, имя: имя.isEmpty ? "СДЭК" : имя,
                                                    доПВЗ: A.строка(п["kind"]) == "pvz",
                                                    днейОт: A.целое(п["days_min"]), днейДо: A.целое(п["days_max"])))
            }
            /* У сайта порядок — порядок ключей ответа; JSONSerialization его не хранит — дешёвые выше, при равной — быстрее. */
            список.sort { ($0.цена, $0.днейДо) < ($1.цена, $1.днейДо) }
            guard !список.isEmpty else {
                расчёт = .межгородНельзя
                return
            }
            расчёт = .перевозчики(список, Self.разобратьПункты(j["points"]))
            самЗаберу = false
            let ключ = список.contains(where: { $0.id == тариф }) ? тариф : список[0].id
            if let вариант = список.first(where: { $0.id == ключ }) { выбрать(вариант) }
            return
        }
        if причина == "intercity" {
            скрыт = false
            расчёт = .межгородНельзя
            return
        }
        if причина == "region" {
            скрыт = false
            расчёт = .регион
            return
        }
        if A.да(j["ok"]), A.да(j["free"]) {
            /* Бесплатная доставка продавца: бесплатный курьер Яндекса — строкой «Бесплатно»; без курьера — точная
               причина (why: no_from — продавец не отметил точку забора, free_costly — доставка дороже его выплаты). */
            скрыт = false
            if A.да(j["courier"]), !A.строка(j["q"]).isEmpty {
                видРасчёта = .яндекс
                let в = ВариантДоставкиСделки(id: "courier", цена: 0, минут: A.целое(j["eta"]), q: A.строка(j["q"]),
                                             бесплатно: true, перевозчик: "", имя: "", доПВЗ: false, днейОт: 0, днейДо: 0)
                расчёт = .курьер([в])
                тариф = в.id
            } else {
                let почему = A.строка(j["why"])
                let код = почему.isEmpty ? "free_self" : (почему.hasPrefix("free_") ? почему : "free_" + почему)
                расчёт = .нельзя(код, "")
            }
            return
        }
        скрыт = false
        if A.да(j["ok"]), !A.да(j["free"]), !A.строка(j["q"]).isEmpty, A.целое(j["price"]) > 0 {
            видРасчёта = .яндекс
            let основнойТариф = A.строка(j["tariff"]).isEmpty ? "express" : A.строка(j["tariff"])
            var список = [ВариантДоставкиСделки(id: основнойТариф, цена: A.целое(j["price"]), минут: A.целое(j["eta"]),
                                                q: A.строка(j["q"]), бесплатно: false, перевозчик: "", имя: "",
                                                доПВЗ: false, днейОт: 0, днейДо: 0)]
            if let alt = j["alt"] as? [String: Any], !A.строка(alt["q"]).isEmpty, A.целое(alt["price"]) > 0,
               !A.строка(alt["tariff"]).isEmpty, A.строка(alt["tariff"]) != основнойТариф {
                список.append(ВариантДоставкиСделки(id: A.строка(alt["tariff"]), цена: A.целое(alt["price"]),
                                                    минут: A.целое(alt["eta"]), q: A.строка(alt["q"]), бесплатно: false,
                                                    перевозчик: "", имя: "", доПВЗ: false, днейОт: 0, днейДо: 0))
            }
            /* ["courier","express"] сайта: пеший первым. */
            список.sort { ($0.id == "courier" ? 0 : 1) < ($1.id == "courier" ? 0 : 1) }
            if !список.contains(where: { $0.id == тариф }) { тариф = основнойТариф }
            расчёт = .курьер(список)
            return
        }
        let код = причина.isEmpty ? "no" : причина
        if ["slow_down", "net", "unavailable"].contains(код) {
            расчёт = .сбой
        } else if код == "need_pt" {
            расчёт = .нужнаТочка
        } else {
            расчёт = .нельзя(код, Self.пояснение(j))
        }
    }

    /**
     Что именно ответил сервер: текст message / msg / error, если он для человека, иначе сам код причины. Сайт на любой
     незнакомый код пишет только «сюда курьер не возит» — натив добавляет строку с ответом, чтобы было видно почему.
     */
    private static func пояснение(_ j: [String: Any]) -> String {
        typealias A = СделкиAPI
        for ключ in ["message", "msg", "error_text", "text", "error"] {
            let текст = A.строка(j[ключ]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !текст.isEmpty, !КабинетСайта.машинныйКод(текст) { return String(текст.prefix(200)) }
        }
        let причина = A.строка(j["reason"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !причина.isEmpty { return String(причина.prefix(200)) }
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(ошибка.prefix(60))
    }

    /// encodeURIComponent сайта: всё, кроме A-Z a-z 0-9 - _ . ! ~ * ' ( ), — в %XX (кириллица тоже).
    private static let символыАдреса = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    private static func вАдрес(_ значение: String) -> String {
        значение.addingPercentEncoding(withAllowedCharacters: символыАдреса) ?? ""
    }

    private static func разобратьПункты(_ сырое: Any?) -> [String: [ПунктВыдачиСделки]] {
        guard let все = сырое as? [String: Any] else { return [:] }
        var итог: [String: [ПунктВыдачиСделки]] = [:]
        for (перевозчик, значение) in все {
            let строки = (значение as? [Any]) ?? []
            var список: [ПунктВыдачиСделки] = []
            for з in строки {
                guard let п = з as? [String: Any] else { continue }
                let код = СделкиAPI.строка(п["code"])
                guard !код.isEmpty else { continue }
                let км: Double? = п["km"] == nil || п["km"] is NSNull ? nil : СделкиAPI.число(п["km"])
                список.append(ПунктВыдачиСделки(id: код, адрес: СделкиAPI.строка(п["addr"]), км: км))
            }
            итог[перевозчик] = список
        }
        return итог
    }

    // MARK: Оформление (mkEcoPay)

    /// Проверка перед create: nil — можно оформлять.
    func ошибкаПередОформлением() -> String? {
        guard включена else { return nil }
        if case .межгородНельзя = расчёт { return т("co_ship_intercity") }
        guard !скрыт, !самЗаберу else { return nil }
        switch расчёт {
        case .считаем:
            return т("co_ship_wait")
        case .нетАдреса, .нужнаТочка, .сбой:
            return т("co_ship_need")
        case .перевозчики:
            if let в = выбранная, в.доПВЗ, (пункты[в.перевозчик] ?? "").isEmpty { return т("co_car_pvz_need") }
            return nil
        default:
            return nil
        }
    }

    /// Поля create: адрес, точка, доставка, дверь.
    func дополнить(_ тело: inout [String: Any]) {
        guard включена, let а = адрес else { return }
        тело["to_addr"] = String(а.текст.prefix(300))
        if let точка = а.точка {
            тело["to_lat"] = точка.широта
            тело["to_lon"] = точка.долгота
        }
        if let в = выбранная {
            тело["ship"] = в.транспортнаяКомпания ? "carrier" : "yandex"
            тело["ship_q"] = в.q
            if в.доПВЗ, let код = пункты[в.перевозчик], !код.isEmpty { тело["car_pvz"] = код }
        }
        if !самЗаберу && !а.дверь.isEmpty { тело["to_door"] = а.дверь }
    }

    /// Ответ create "ship_quote": цена устарела (или пункт не подходит) — текст и новый расчёт.
    func ценаУстарела(причина: String) -> String {
        let пункт = причина == "pvz"
        if пункт, let в = выбранная, в.транспортнаяКомпания { пункты[в.перевозчик] = nil }
        посчитать()
        return т(пункт ? "co_car_pvz_bad" : "co_ship_changed")
    }
}

// MARK: - Блок «Как получить» и «Куда привезти»

struct БлокДоставкиНовойСделки: View {
    @ObservedObject var доставка: ДоставкаНовойСделки
    let изменитьАдрес: () -> Void
    /// Окно объявления («Доставка в другой город»): без строки «Заберу сам» — там только расчёт.
    let безСамовывоза: Bool

    init(доставка: ДоставкаНовойСделки, изменитьАдрес: @escaping () -> Void, безСамовывоза: Bool = false) {
        self.доставка = доставка
        self.изменитьАдрес = изменитьАдрес
        self.безСамовывоза = безСамовывоза
    }

    private func т(_ ключ: String) -> String { ДоставкаСделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if доставка.бесплатная {
                ЗаметкаСделки(Text(т("co_ship_free")), вид: .хорошо, символ: "gift")
            }
            if !доставка.скрыт {
                Text(т("co_ship_pick").uppercased())
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.зелёный)
                    .accessibilityAddTraits(.isHeader)
                варианты
            }
            адрес
        }
        .animation(ДвижениеСайта.смена, value: доставка.расчёт)
    }

    // MARK: Варианты

    @ViewBuilder
    private var варианты: some View {
        switch доставка.расчёт {
        case .нетАдреса:
            подсказка(т("co_ship_addr_first"))
            строкаСам
        case .считаем:
            /* Адрес определён — полоса «Оцениваем стоимость доставки…», потом плавно результат. */
            ПрогрессРасчётаДоставки(вид: доставка.видРасчёта, заголовок: т("ship_estimating"))
        case .нужнаТочка:
            /* need_pt: адрес без дома — просим точку на карте; после неё расчёт идёт сам (выбран → посчитать). */
            ЗаметкаСделки(Text(т("co_ship_house_why")), вид: .инфо, символ: "mappin.and.ellipse")
            Button(action: изменитьАдрес) {
                Label(т("co_ship_house_btn"), systemImage: "map")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            строкаСам
        case .сбой:
            Button { доставка.повторить() } label: {
                Label(т("co_ship_retry2"), systemImage: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            строкаСам
        case .нельзя(let причина, let пояснение):
            if let текст = Self.текстБесплатной(причина) {
                /* Бесплатная доставка продавца без курьера — точная причина, а не «не возит». */
                ЗаметкаСделки(Text(т(текст)), вид: .инфо, символ: "gift")
            } else if ["no_from", "no_item", "bad_args"].contains(причина) {
                подсказка(т("co_ship_none"))
            } else {
                строкаЯндексаБезЦены(т(причина == "no_courier" ? "co_ship_bulky" : "co_ship_na"))
            }
            if !пояснение.isEmpty {
                подсказка(т("co_ship_why").replacingOccurrences(of: "{r}", with: пояснение))
            }
            строкаСам
            ПодписьСделки(т("co_ship_same"))
        case .межгородНельзя:
            ЗаметкаСделки(Text(т("co_ship_intercity")), вид: .предупреждение, символ: "shippingbox")
        case .регион:
            ЗаметкаСделки(Text(т("co_ship_region")), вид: .инфо, символ: "map")
        case .курьер(let список):
            ForEach(список) { в in
                строка(в)
            }
            строкаСам
        case .перевозчики(let список, _):
            ForEach(список) { в in
                VStack(alignment: .leading, spacing: 8) {
                    строка(в)
                    if в.доПВЗ && выбран(в) { выборПункта(в) }
                }
            }
            ПодписьСделки(т("co_car_track"))
        }
    }

    private func выбран(_ в: ВариантДоставкиСделки) -> Bool {
        доставка.выбранная?.id == в.id
    }

    /// Ключ текста причины бесплатной доставки без курьера (free_no_from, free_costly, free_self); nil — не она.
    static func текстБесплатной(_ причина: String) -> String? {
        switch причина {
        case "free_no_from": return "co_ship_free_no_from"
        case "free_costly": return "co_ship_free_costly"
        case "free_self": return "co_ship_free_self"
        default: return причина.hasPrefix("free_") ? "co_ship_free_self" : nil
        }
    }

    private func подсказка(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func строка(_ в: ВариантДоставкиСделки) -> some View {
        let заголовок: String
        let подпись: String
        if в.транспортнаяКомпания {
            заголовок = в.имя + " — " + т(в.доПВЗ ? "co_car_pvz" : "co_car_door")
            let срок = дни(в)
            /* Бесплатная доставка продавца: «2–4 дн. · оплачивает продавец». */
            подпись = в.бесплатно ? (срок.isEmpty ? т("co_ship_free_s") : срок + " · " + т("co_ship_free_s")) : срок
        } else if в.бесплатно {
            заголовок = т("co_ship_ya")
            подпись = т("co_ship_free_s")
        } else if в.id == "courier" || в.id == "express" {
            let двойной: Bool
            if case .курьер(let список) = доставка.расчёт { двойной = список.count > 1 } else { двойной = false }
            if двойной {
                заголовок = ДеньгиСделкиText.т(в.id == "courier" ? "co_ship_walk" : "co_ship_exp")
                подпись = т(в.id == "courier" ? "co_ship_walk_s" : "co_ship_exp_s")
            } else {
                заголовок = т("co_ship_ya")
                подпись = в.минут > 0 ? т("ship_eta").replacingOccurrences(of: "{n}", with: String(в.минут))
                                      : т("co_ship_ya_s")
            }
        } else {
            заголовок = т("co_ship_ya")
            подпись = т("co_ship_ya_s")
        }
        let цена = в.бесплатно ? т("co_ship_free_b") : СделкиФормат.тенге(в.цена)
        return СтрокаВыбораДоставки(заголовок: заголовок, подпись: подпись, цена: цена, выбрана: выбран(в),
                                    пунктир: false, доступна: true) {
            доставка.выбрать(в)
        }
    }

    /// Курьер не возит (no_courier, прочее): строка «Курьер Яндекса» без цены, неактивна.
    private func строкаЯндексаБезЦены(_ причина: String) -> some View {
        СтрокаВыбораДоставки(заголовок: т("co_ship_ya"), подпись: т("co_ship_ya_s"), цена: причина, выбрана: false,
                             пунктир: false, доступна: false) {}
    }

    @ViewBuilder
    private var строкаСам: some View {
        if !безСамовывоза {
            строкаСамСама
        }
    }

    private var строкаСамСама: some View {
        let выбрана = доставка.самОтмечено
        return СтрокаВыбораДоставки(заголовок: т("co_ship_self2"), подпись: т("co_ship_self2_s"),
                                    цена: СделкиФормат.тенге(0), выбрана: выбрана, пунктир: true, доступна: true) {
            доставка.выбрать(nil)
        }
    }

    private func дни(_ в: ВариантДоставкиСделки) -> String {
        let от = в.днейОт
        let до = в.днейДо
        if от == 0 && до == 0 { return "" }
        if от > 0 && до > 0 && от != до {
            return т("co_car_days").replacingOccurrences(of: "{a}", with: String(от))
                .replacingOccurrences(of: "{b}", with: String(до))
        }
        return т("co_car_days1").replacingOccurrences(of: "{n}", with: String(до > 0 ? до : от))
    }

    /// «Пункт выдачи»: выпадающий список адресов (addr · N км).
    private func выборПункта(_ в: ВариантДоставкиСделки) -> some View {
        let список = доставка.списокПунктов(в)
        let код = доставка.пункты[в.перевозчик] ?? ""
        let текущий = список.first(where: { $0.id == код })
        return VStack(alignment: .leading, spacing: 6) {
            Text(т("co_car_pt"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            if список.isEmpty {
                подсказка(т("co_car_pvz_need"))
            } else {
                Menu {
                    ForEach(список) { п in
                        Button(подписьПункта(п)) { доставка.выбратьПункт(п.id, для: в) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.акцент)
                            .accessibilityHidden(true)
                        Text(текущий.map { подписьПункта($0) } ?? т("co_car_pvz_need"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текст)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                }
            }
        }
        .padding(.leading, 30)
    }

    private func подписьПункта(_ п: ПунктВыдачиСделки) -> String {
        guard let км = п.км else { return п.адрес }
        let число = String(format: "%.1f", км).replacingOccurrences(of: ".", with: ",")
        return п.адрес + " · " + число + " км"
    }

    // MARK: Адрес

    private var адрес: some View {
        let текст = доставка.адрес?.текст ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            Text(т("co_to"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(текст.isEmpty ? Theme.текстВторой : Theme.зелёный)
                    .accessibilityHidden(true)
                Text(текст.isEmpty ? т("co_addr_none") : текст)
                    .font(.system(size: 14, weight: текст.isEmpty ? .regular : .semibold))
                    .foregroundStyle(текст.isEmpty ? Theme.текстВторой : Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(action: изменитьАдрес) {
                    Text(т(текст.isEmpty ? "co_addr_set" : "co_addr_edit"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
        }
    }
}

/// Строка выбора (.mk-eco-shipopt): точка-радио, название и подпись, цена справа; «Заберу сам» — пунктиром.
struct СтрокаВыбораДоставки: View {
    let заголовок: String
    let подпись: String
    let цена: String
    let выбрана: Bool
    let пунктир: Bool
    let доступна: Bool
    let нажать: () -> Void

    init(заголовок: String, подпись: String, цена: String, выбрана: Bool, пунктир: Bool, доступна: Bool,
         нажать: @escaping () -> Void) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.цена = цена
        self.выбрана = выбрана
        self.пунктир = пунктир
        self.доступна = доступна
        self.нажать = нажать
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button(action: нажать) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(выбрана ? Theme.зелёный : Theme.линия, lineWidth: выбрана ? 5 : 1.5)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: выбрана || !пунктир ? .bold : .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    if !подпись.isEmpty {
                        Text(подпись)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                Text(цена)
                    .font(.system(size: доступна ? 14 : 12, weight: доступна ? .heavy : .regular))
                    .foregroundStyle(доступна ? Theme.текст : Theme.текстВторой)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, пунктир ? 8 : 10)
            .frame(minHeight: 44)
            .background(выбрана ? КраскаСделокКабинета.хорошоФон : Color.clear, in: форма)
            .overlay {
                форма.strokeBorder(выбрана ? Theme.зелёный : Theme.линия,
                                   style: StrokeStyle(lineWidth: 1.5, dash: пунктир && !выбрана ? [5, 4] : []))
            }
            .contentShape(форма)
            .opacity(доступна ? 1 : 0.55)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!доступна)
        .accessibilityAddTraits(выбрана ? [.isSelected] : [])
    }
}

// MARK: - Метки гаранта (три равные плашки)

/// «Деньги под защитой · Возврат при споре · Оплата после получения» — три равные плашки в ряд: значок сверху,
/// подпись до двух строк по центру, одинаковая ширина и высота.
struct МеткиГарантииСделки: View {
    let подписи: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(подписи.enumerated()), id: \.offset) { пара in
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(пара.element)
                        .font(.system(size: 11, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                .padding(.horizontal, 6)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(КраскаСделокКабинета.хорошоФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(КраскаСделокКабинета.хорошоКромка, lineWidth: 1)
                }
                .accessibilityElement(children: .combine)
            }
        }
        /* Высота ряда — по самой высокой плашке, остальные тянутся до неё. */
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - «Оцениваем стоимость доставки…» — полоса прогресса расчёта

/**
 Пока ship_quote считает цену (адрес уже определён): значок перевозчика (Яндекс — красный круг «Я», СДЭК — зелёный
 квадрат «С», неизвестно — коробка), заголовок, подпись и полоса с бегущим зелёным бликом. «Уменьшение движения» —
 полоса стоит. Цвета — темы (светлая и тёмная).
 */
struct ПрогрессРасчётаДоставки: View {
    let вид: ВидПеревозчикаРасчёта
    let заголовок: String

    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(вид: ВидПеревозчикаРасчёта, заголовок: String) {
        self.вид = вид
        self.заголовок = заголовок
    }

    private var подпись: String {
        switch вид {
        case .яндекс: return ДоставкаСделкиText.т("ship_est_ya")
        case .сдэк: return ДоставкаСделкиText.т("ship_est_cdek")
        case .любой: return ДоставкаСделкиText.т("ship_est_any")
        }
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return HStack(alignment: .center, spacing: 12) {
            ЗначокПеревозчикаРасчёта(вид: вид, дышит: !безДвижения)
            VStack(alignment: .leading, spacing: 6) {
                Text(заголовок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ПолосаРасчётаДоставки(стоит: безДвижения)
                    .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// Значок перевозчика 36 pt; «дышит» (лёгкое увеличение) — только без «Уменьшения движения».
private struct ЗначокПеревозчикаРасчёта: View {
    let вид: ВидПеревозчикаРасчёта
    let дышит: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !дышит)) { шкала in
            let t = шкала.date.timeIntervalSinceReferenceDate
            let масштаб: CGFloat = дышит ? 1 + 0.05 * CGFloat(sin(t * 2 * Double.pi / 1.6)) : 1
            значок
                .scaleEffect(масштаб)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var значок: some View {
        switch вид {
        case .яндекс:
            Text("Я")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(red: 0.988, green: 0.247, blue: 0.114), in: Circle())
        case .сдэк:
            Text("С")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color(red: 0.0, green: 0.667, blue: 0.294),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .любой:
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// Полоса 6 pt: дорожка цвета линии и бегущий зелёный отрезок с бликом; стоит — отрезок на 60 % без движения.
private struct ПолосаРасчётаДоставки: View {
    let стоит: Bool

    var body: some View {
        GeometryReader { рамка in
            let ширина = рамка.size.width
            TimelineView(.animation(minimumInterval: nil, paused: стоит)) { шкала in
                let t = шкала.date.timeIntervalSinceReferenceDate
                let фаза = CGFloat(t.truncatingRemainder(dividingBy: 1.3) / 1.3)
                let длина = ширина * 0.42
                let сдвиг = стоит ? 0 : (ширина + длина) * фаза - длина
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.линия)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.зелёный2.opacity(0.25), Theme.зелёныйЯркий,
                                                      Theme.зелёный2.opacity(0.25)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: стоит ? ширина * 0.6 : длина)
                        .offset(x: сдвиг)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
