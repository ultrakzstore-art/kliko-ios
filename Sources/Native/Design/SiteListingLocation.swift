import SwiftUI
import MapKit
import CoreLocation
import UIKit

/**
 «РАСПОЛОЖЕНИЕ» НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ — ЦЕЛИКОМ, КАК У САЙТА (владелец 26.09.2026: «расположение и карты и вызов
 маршрут туда обратно тоже недонастроен в модалке»).

 Образец — mkLocationBlock, mkRouteOpen / mkRouteDir / mkRouteApps, mkCourier / mkCourierLaunch / mkCourierOrder в
 js/marketplace.min.js. Сайт кладёт блок в колонку .mk-mcol-e КАЖДОЙ страницы объявления (rt = mkLocationBlock(r)),
 поэтому и здесь он у всех разделов, а не только у авто и жилья. Условия — как у сайта:
   · нет ни города с районом, ни точки (lat/lon) — блока нет;
   · шапка: «Город, район» и «Открыть в 2ГИС →» (с точкой — geo/<lon>,<lat>, без — поиск по месту), под ней address;
   · карта — только с точкой. Сайт ставит точную метку (Leaflet, масштаб 14), приблизительной области с радиусом у
     него нет — и здесь метка точная. Нажатие — карта на весь экран: «Моё местоположение» по нажатию (разрешение
     спрашивается только тогда), расстояние «≈ N км» и пунктир от вас до места;
   · большая кнопка .mk-loc-go — только с точкой и если выбранный город человека (mkWhereAmI — ГдеИскать.сохранённое)
     не другой: у товаров, которые можно довезти (mkIsDeliverable: не realty, transport, services, jobs) и не крупных
     (mkIsBulky), — «Доехать или доставить», у прочих — «Построить маршрут»;
   · без точки, в своём городе, у довозимого некрупного — чип «Курьер по городу».
 Лист маршрута (mkRouteOpen): «Маршрут и доставка», переключатель «Я еду туда» / «Еду оттуда» (туда и обратно: точка
 объявления — конец или начало маршрута), Яндекс Go, inDrive, 2ГИС — как у сайта; ниже — навигаторы телефона: Apple
 Карты, Яндекс Карты, Google Maps. У довозимого некрупного — «или не ехать вовсе» и «Курьер по городу».
 Приложения открываются своими схемами (yandextaxi, dgis, yandexmaps, comgooglemaps — LSApplicationQueriesSchemes
 в project.yml); не установлено — те же адреса в браузере, что у сайта.
 Лист курьера (mkCourier): откуда — продавец, куда — ваш адрес (поле и «Определить автоматически»), «Вызвать курьера
 Яндекс Go» (tariffClass=courier, дальше 30 км — предупреждение, как mkCourierIntercityWarn), «Согласовать с
 продавцом» — чат объявления. 🔴 «Купить безопасно с доставкой» ведёт в сделку с деньгами — только при
 Config.деньгиСделок.
 «Газель / Грузоперевозки» и «Межгород из …» у крупного (mkBroadcast — запрос исполнителям), «Доставка из …» с
 транспортными компаниями (mkIntercityToggle), строка регионов отправки (mkShipRegionsLine) и расчёт доставки в листе
 курьера (mkShipQuote, только сведения) — SiteListingDelivery.swift.
 «Скопировать адрес» — своё, у сайта его нет: город, район и улица одной строкой.
 */

// MARK: - Тексты

/// Тексты блока «Расположение» на языке телефона (kk/ru/en/ar), как ListingKindsText. Русские — словарь
/// js/i18n-marketplace-ru.js (route_*, courier_*, from_seller, to_you, …) и строки прямо в коде сайта.
enum ListingLocationText {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "route_go_t": "Построить маршрут", "route_go_s": "Яндекс, inDrive или 2ГИС",
            "route_both_t": "Доехать или доставить", "route_both_s": "Такси, 2ГИС или курьер по городу",
            "route_h": "Маршрут и доставка", "route_to": "Я еду туда", "route_from": "Еду оттуда",
            "route_note_to": "Маршрут к товару", "route_note_from": "Маршрут от товара",
            "route_note_deal": "Договорная цена поездки", "route_or": "или не ехать вовсе",
            "nav_apps": "Навигаторы", "apple_maps": "Apple Карты", "yandex_maps": "Яндекс Карты",
            "google_maps": "Google Maps", "yandex_go": "Яндекс Go",
            "courier_city": "Курьер по городу", "route_cour_s": "Заберёт у продавца и привезёт вам",
            "from_seller": "Откуда · продавец", "to_you": "Куда · ваш адрес",
            "addr_unknown": "Адрес уточняется у продавца", "ph_courier_addr": "Ваш адрес доставки",
            "detect_auto": "Определить автоматически", "addr_detecting": "Определяем ваш адрес…",
            "addr_detected_call": "Адрес определён — можно вызывать",
            "geo_fail": "Не удалось получить геолокацию (разрешите доступ)",
            "courier_safe_t": "Купить безопасно с доставкой",
            "courier_safe_s": "Деньги у Kliko, пока вы не получите товар; адрес уходит в сделку",
            "call_courier_yandex": "Вызвать курьера Яндекс Go",
            "courier_ya_warn": "Вне защиты сделки: заказ и оплата — на стороне Яндекса, мы его не отслеживаем",
            "agree_with_seller": "Согласовать с продавцом",
            "route_note": "Приложение откроется с маршрутом А→Б. Если адрес не введён — укажете в самом приложении.",
            "courier_addr_in_app": "Точный адрес укажете в приложении", "opening_yandex": "Открываем Яндекс Go…",
            "courier_far": "Дальше 30 км — Яндекс Go возит только поблизости. Оформите доставку транспортной компанией в блоке «Доставка в другой город».",
            "geo_denied": "Доступ отклонён — впишите адрес вручную", "addr_fail_manual": "Не удалось определить — впишите вручную",
            "bids_sending": "Отправляем…", "bids_sent": "Заявка отправлена компаниям! Ставки — в кабинете → «Мои доставки»",
            "bids_auth": "Войдите, чтобы заказать доставку", "bids_fail": "Не удалось отправить",
            "copy_addr": "Скопировать адрес", "copied": "Скопировано",
            "open_map": "Открыть карту", "close": "Закрыть",
            "geo_ask_mine": "Моё местоположение", "geo_locating": "Определяю местоположение…",
            "dist_km": "≈ %@ км от вас", "dist_m": "≈ %@ м от вас",
            "gazelle_freight": "Газель / Грузоперевозки", "intercity_from": "Межгород из %@",
            "delivery_route": "Доставка %1$@ → %2$@", "delivery_from": "Доставка из %@",
            "delivery_other": "Доставка в другой город", "ship_only_city": "Доставка только по городу %@",
            "ship_only_regions": "Доставка только: %@", "ship_not_yours": "В ваш регион продавец не отправляет — встреча или самовывоз",
            "seller_choice": "выбор продавца", "delivered_by_tk": "Довезёт транспортная компания:",
            "logi_car_note": "цена и срок — при оформлении, по вашему адресу", "logi_intercity_h": "Межгород-доставка",
            "logi_other_h": "Доставка в другой город", "logi_free": "Бесплатная доставка — продавец организует и оплачивает сам",
            "logi_none": "Транспортные компании недоступны.", "logi_loading": "Загружаем транспортные компании…",
            "logi_price_from": "от %@ ₸", "logi_per_kg": "+%@ ₸/кг",
            "logi_car_cta": "Оформить с доставкой", "collect_bids": "Собрать ставки от компаний",
            "collect_bids_note": "Компании предложат свою цену — выберешь лучшую в «Мои доставки»", "bc_head": "Запрос специалистам рядом",
            "bc_sub": "Ваш запрос получат продавцы и специалисты в радиусе 2 км (или в вашем городе)", "ph_broadcast": "Опишите, что вам нужно…",
            "city_fail": "Не удалось определить город", "my_address": "Мой адрес",
            "send_request": "Отправить запрос", "request_sent": "Отправлено",
            "request_sent_n": "Отправлено (%@)", "write_need": "Напишите, что вам нужно", "empty_post": "Ищу это — спросить продавцов", "empty_ask_text": "Ищу: %@",
            "empty_ask_need": "Напишите, что ищете — тогда спросим продавцов",
            "report_sending": "Отправляю…", "error_short": "Ошибка",
            "net_error": "Ошибка сети", "detecting_addr": "Определяем адрес…",
            "addr_detected": "Адрес определён", "no_geo_access": "Нет доступа к геолокации",
            "bc_confirm_t": "Отправить запрос?", "bc_confirm_s": "Его увидят исполнители рядом и ответят вам в чате.",
            "cancel": "Отмена", "need_session": "Не удалось отправить, попробуйте ещё раз",
            "ship_quote": "Доставка ~ %@", "ship_quote_who": "платит покупатель, сверх суммы сделки",
            "ship_eta": "~%@ мин в пути", "eta_days": "%1$@–%2$@ дн.",
            "eta_days_one": "%@ дн.", "co_ship_free": "Доставка за счёт продавца"
        ],
        "kk": [
            "route_go_t": "Бағдар құру", "route_go_s": "Яндекс, inDrive немесе 2ГИС",
            "route_both_t": "Жету немесе жеткізу", "route_both_s": "Такси, 2ГИС немесе қала ішіндегі курьер",
            "route_h": "Бағдар және жеткізу", "route_to": "Мен сонда барамын", "route_from": "Сол жерден шығамын",
            "route_note_to": "Тауарға дейінгі бағдар", "route_note_from": "Тауардан шығатын бағдар",
            "route_note_deal": "Сапар бағасы келісім бойынша", "route_or": "немесе мүлде бармау",
            "nav_apps": "Навигаторлар", "apple_maps": "Apple Карталар", "yandex_maps": "Яндекс Карталар",
            "google_maps": "Google Maps", "yandex_go": "Яндекс Go",
            "courier_city": "Қала ішіндегі курьер", "route_cour_s": "Сатушыдан алып, сізге жеткізеді",
            "from_seller": "Қайдан · сатушы", "to_you": "Қайда · сіздің мекенжайыңыз",
            "addr_unknown": "Мекенжайды сатушыдан нақтылаңыз", "ph_courier_addr": "Жеткізу мекенжайыңыз",
            "detect_auto": "Автоматты анықтау", "addr_detecting": "Мекенжайыңызды анықтап жатырмыз…",
            "addr_detected_call": "Мекенжай анықталды — шақыруға болады",
            "geo_fail": "Геолокация алынбады (рұқсат беріңіз)",
            "courier_safe_t": "Жеткізумен қауіпсіз сатып алу",
            "courier_safe_s": "Тауарды алғанша ақша Kliko-да; мекенжай мәмілеге кетеді",
            "call_courier_yandex": "Яндекс Go курьерін шақыру",
            "courier_ya_warn": "Мәміле қорғауынан тыс: тапсырыс пен төлем — Яндекс жағында, біз оны бақыламаймыз",
            "agree_with_seller": "Сатушымен келісу",
            "route_note": "Қосымша А→Б бағдарымен ашылады. Мекенжай енгізілмесе — қосымшаның өзінде көрсетесіз.",
            "courier_addr_in_app": "Нақты мекенжайды қосымшада көрсетесіз", "opening_yandex": "Яндекс Go ашылуда…",
            "courier_far": "30 км-ден алыс — Яндекс Go тек жақын жерге апарады. Жеткізуді «Басқа қалаға жеткізу» блогында көлік компаниясы арқылы рәсімдеңіз.",
            "geo_denied": "Рұқсат берілмеді — мекенжайды қолмен жазыңыз", "addr_fail_manual": "Анықтау мүмкін болмады — қолмен жазыңыз",
            "bids_sending": "Жіберіп жатырмыз…", "bids_sent": "Өтінім компанияларға жіберілді! Ұсыныстар — кабинетте → «Менің жеткізулерім»",
            "bids_auth": "Жеткізуге тапсырыс беру үшін кіріңіз", "bids_fail": "Жіберу мүмкін болмады",
            "copy_addr": "Мекенжайды көшіру", "copied": "Көшірілді",
            "open_map": "Картаны ашу", "close": "Жабу",
            "geo_ask_mine": "Менің орным", "geo_locating": "Орналасқан жерді анықтап жатырмын…",
            "dist_km": "≈ сізден %@ км", "dist_m": "≈ сізден %@ м",
            "gazelle_freight": "Газель / Жүк тасымалы", "intercity_from": "%@ қаласынан қалааралық",
            "delivery_route": "Жеткізу %1$@ → %2$@", "delivery_from": "%@ қаласынан жеткізу",
            "delivery_other": "Басқа қалаға жеткізу", "ship_only_city": "Жеткізу тек %@ қаласы бойынша",
            "ship_only_regions": "Жеткізу тек: %@", "ship_not_yours": "Сатушы сіздің өңірге жібермейді — кездесу немесе өзі алып кету",
            "seller_choice": "сатушы таңдауы", "delivered_by_tk": "Көлік компаниясы жеткізеді:",
            "logi_car_note": "бағасы мен мерзімі — рәсімдегенде, мекенжайыңыз бойынша", "logi_intercity_h": "Қалааралық жеткізу",
            "logi_other_h": "Басқа қалаға жеткізу", "logi_free": "Тегін жеткізу — сатушы өзі ұйымдастырып, өзі төлейді",
            "logi_none": "Көлік компаниялары қолжетімсіз.", "logi_loading": "Көлік компанияларын жүктеп жатырмыз…",
            "logi_price_from": "%@ ₸-ден", "logi_per_kg": "+%@ ₸/кг",
            "logi_car_cta": "Жеткізумен рәсімдеу", "collect_bids": "Компаниялардан ұсыныс жинау",
            "collect_bids_note": "Компаниялар өз бағасын ұсынады — ең жақсысын «Менің жеткізулерім» бөлімінде таңдайсыз", "bc_head": "Жақын маңдағы мамандарға сұрау",
            "bc_sub": "Сұрауыңызды 2 км радиустағы (немесе қалаңыздағы) сатушылар мен мамандар алады", "ph_broadcast": "Не қажет екенін сипаттаңыз…",
            "city_fail": "Қаланы анықтау мүмкін болмады", "my_address": "Менің мекенжайым",
            "send_request": "Сұрау жіберу", "request_sent": "Жіберілді",
            "request_sent_n": "Жіберілді (%@)", "write_need": "Не қажет екенін жазыңыз", "empty_post": "Осыны іздеймін — сатушылардан сұрау", "empty_ask_text": "Іздеймін: %@",
            "empty_ask_need": "Не іздейтініңізді жазыңыз — сонда сатушылардан сұраймыз",
            "report_sending": "Жіберіп жатырмын…", "error_short": "Қате",
            "net_error": "Желі қатесі", "detecting_addr": "Мекенжайды анықтап жатырмыз…",
            "addr_detected": "Мекенжай анықталды", "no_geo_access": "Геолокацияға рұқсат жоқ",
            "bc_confirm_t": "Сұрау жіберілсін бе?", "bc_confirm_s": "Оны жақын маңдағы орындаушылар көріп, сізге чатта жауап береді.",
            "cancel": "Бас тарту", "need_session": "Жіберу мүмкін болмады, қайта көріңіз",
            "ship_quote": "Жеткізу ~ %@", "ship_quote_who": "сатып алушы төлейді, мәміле сомасынан бөлек",
            "ship_eta": "жолда ~%@ мин", "eta_days": "%1$@–%2$@ күн",
            "eta_days_one": "%@ күн", "co_ship_free": "Жеткізуді сатушы төлейді"
        ],
        "en": [
            "route_go_t": "Get directions", "route_go_s": "Yandex, inDrive or 2GIS",
            "route_both_t": "Go there or get it delivered", "route_both_s": "Taxi, 2GIS or a city courier",
            "route_h": "Directions and delivery", "route_to": "I'm going there", "route_from": "I'm leaving from there",
            "route_note_to": "Route to the item", "route_note_from": "Route from the item",
            "route_note_deal": "Negotiable ride price", "route_or": "or don't go at all",
            "nav_apps": "Navigation apps", "apple_maps": "Apple Maps", "yandex_maps": "Yandex Maps",
            "google_maps": "Google Maps", "yandex_go": "Yandex Go",
            "courier_city": "City courier", "route_cour_s": "Picks it up from the seller and brings it to you",
            "from_seller": "From · seller", "to_you": "To · your address",
            "addr_unknown": "Ask the seller for the address", "ph_courier_addr": "Your delivery address",
            "detect_auto": "Detect automatically", "addr_detecting": "Detecting your address…",
            "addr_detected_call": "Address found — you can call a courier",
            "geo_fail": "Couldn't get your location (allow access)",
            "courier_safe_t": "Buy safely with delivery",
            "courier_safe_s": "Kliko holds the money until you receive the item; the address goes into the deal",
            "call_courier_yandex": "Call a Yandex Go courier",
            "courier_ya_warn": "Not covered by deal protection: the order and payment are handled by Yandex, we don't track it",
            "agree_with_seller": "Arrange with the seller",
            "route_note": "The app opens with an A→B route. If you haven't entered an address, set it in the app.",
            "courier_addr_in_app": "You'll set the exact address in the app", "opening_yandex": "Opening Yandex Go…",
            "courier_far": "Over 30 km — Yandex Go only delivers nearby. Arrange shipping with a delivery company in the «Delivery to another city» block.",
            "geo_denied": "Access denied — type the address manually", "addr_fail_manual": "Couldn't detect — type it manually",
            "bids_sending": "Sending…", "bids_sent": "Request sent to companies! Bids are in your account → «My deliveries»",
            "bids_auth": "Sign in to order delivery", "bids_fail": "Couldn't send",
            "copy_addr": "Copy address", "copied": "Copied",
            "open_map": "Open map", "close": "Close",
            "geo_ask_mine": "My location", "geo_locating": "Finding your location…",
            "dist_km": "≈ %@ km from you", "dist_m": "≈ %@ m from you",
            "gazelle_freight": "Van / Freight", "intercity_from": "Intercity from %@",
            "delivery_route": "Delivery %1$@ → %2$@", "delivery_from": "Delivery from %@",
            "delivery_other": "Delivery to another city", "ship_only_city": "Delivery only within %@",
            "ship_only_regions": "Delivery only: %@", "ship_not_yours": "The seller doesn't ship to your region — meet up or pick it up",
            "seller_choice": "seller's choice", "delivered_by_tk": "Delivered by a shipping company:",
            "logi_car_note": "price and time at checkout, for your address", "logi_intercity_h": "Intercity delivery",
            "logi_other_h": "Delivery to another city", "logi_free": "Free delivery — the seller arranges and pays for it",
            "logi_none": "No shipping companies available.", "logi_loading": "Loading shipping companies…",
            "logi_price_from": "from %@ ₸", "logi_per_kg": "+%@ ₸/kg",
            "logi_car_cta": "Order with delivery", "collect_bids": "Collect bids from companies",
            "collect_bids_note": "Companies will offer their prices — pick the best one in “My deliveries”", "bc_head": "Request to specialists nearby",
            "bc_sub": "Sellers and specialists within 2 km (or in your city) will get your request", "ph_broadcast": "Describe what you need…",
            "city_fail": "Couldn't detect the city", "my_address": "My address",
            "send_request": "Send request", "request_sent": "Sent",
            "request_sent_n": "Sent (%@)", "write_need": "Write what you need", "empty_post": "Looking for this — ask sellers", "empty_ask_text": "Looking for: %@",
            "empty_ask_need": "Type what you are looking for — then we will ask sellers",
            "report_sending": "Sending…", "error_short": "Error",
            "net_error": "Network error", "detecting_addr": "Detecting your address…",
            "addr_detected": "Address found", "no_geo_access": "No access to location",
            "bc_confirm_t": "Send the request?", "bc_confirm_s": "Providers nearby will see it and reply to you in chat.",
            "cancel": "Cancel", "need_session": "Couldn't send, please try again",
            "ship_quote": "Delivery ~ %@", "ship_quote_who": "paid by the buyer, on top of the deal amount",
            "ship_eta": "~%@ min on the way", "eta_days": "%1$@–%2$@ days",
            "eta_days_one": "%@ days", "co_ship_free": "Delivery paid by the seller"
        ],
        "ar": [
            "route_go_t": "إنشاء مسار", "route_go_s": "Yandex أو inDrive أو 2GIS",
            "route_both_t": "الذهاب أو التوصيل", "route_both_s": "تاكسي أو 2GIS أو مندوب داخل المدينة",
            "route_h": "المسار والتوصيل", "route_to": "أنا ذاهب إلى هناك", "route_from": "أنطلق من هناك",
            "route_note_to": "مسار إلى المنتج", "route_note_from": "مسار من المنتج",
            "route_note_deal": "سعر الرحلة قابل للتفاوض", "route_or": "أو لا تذهب أبدًا",
            "nav_apps": "تطبيقات الملاحة", "apple_maps": "خرائط Apple", "yandex_maps": "خرائط Yandex",
            "google_maps": "خرائط Google", "yandex_go": "Yandex Go",
            "courier_city": "مندوب داخل المدينة", "route_cour_s": "يستلمه من البائع ويوصله إليك",
            "from_seller": "من · البائع", "to_you": "إلى · عنوانك",
            "addr_unknown": "اسأل البائع عن العنوان", "ph_courier_addr": "عنوان التوصيل الخاص بك",
            "detect_auto": "تحديد تلقائي", "addr_detecting": "جارٍ تحديد عنوانك…",
            "addr_detected_call": "تم تحديد العنوان — يمكنك الطلب",
            "geo_fail": "تعذّر الحصول على الموقع (اسمح بالوصول)",
            "courier_safe_t": "شراء آمن مع التوصيل",
            "courier_safe_s": "يحتفظ Kliko بالمال حتى تستلم السلعة، ويُضاف العنوان إلى الصفقة",
            "call_courier_yandex": "اطلب مندوب Yandex Go",
            "courier_ya_warn": "خارج حماية الصفقة: الطلب والدفع لدى Yandex، ونحن لا نتابعه",
            "agree_with_seller": "الاتفاق مع البائع",
            "route_note": "سيُفتح التطبيق بمسار من أ إلى ب. إن لم تُدخل العنوان فحدده في التطبيق نفسه.",
            "courier_addr_in_app": "ستحدد العنوان الدقيق في التطبيق", "opening_yandex": "جارٍ فتح Yandex Go…",
            "courier_far": "أبعد من 30 كم — Yandex Go يوصل إلى الأماكن القريبة فقط. اطلب التوصيل عبر شركة شحن في قسم «التوصيل إلى مدينة أخرى».",
            "geo_denied": "تم رفض الوصول — اكتب العنوان يدويًا", "addr_fail_manual": "تعذّر التحديد — اكتبه يدويًا",
            "bids_sending": "جارٍ الإرسال…", "bids_sent": "تم إرسال الطلب إلى الشركات! العروض في حسابك ← «توصيلاتي»",
            "bids_auth": "سجّل الدخول لطلب التوصيل", "bids_fail": "تعذّر الإرسال",
            "copy_addr": "نسخ العنوان", "copied": "تم النسخ",
            "open_map": "فتح الخريطة", "close": "إغلاق",
            "geo_ask_mine": "موقعي", "geo_locating": "جارٍ تحديد الموقع…",
            "dist_km": "≈ %@ كم منك", "dist_m": "≈ %@ م منك",
            "gazelle_freight": "شاحنة صغيرة / نقل بضائع", "intercity_from": "نقل بين المدن من %@",
            "delivery_route": "التوصيل من %1$@ إلى %2$@", "delivery_from": "التوصيل من %@",
            "delivery_other": "التوصيل إلى مدينة أخرى", "ship_only_city": "التوصيل داخل مدينة %@ فقط",
            "ship_only_regions": "التوصيل فقط: %@", "ship_not_yours": "البائع لا يرسل إلى منطقتك — لقاء أو استلام بنفسك",
            "seller_choice": "اختيار البائع", "delivered_by_tk": "ستوصله شركة نقل:",
            "logi_car_note": "السعر والمدة عند الطلب، حسب عنوانك", "logi_intercity_h": "توصيل بين المدن",
            "logi_other_h": "التوصيل إلى مدينة أخرى", "logi_free": "توصيل مجاني — البائع ينظمه ويدفع ثمنه",
            "logi_none": "شركات النقل غير متاحة.", "logi_loading": "جارٍ تحميل شركات النقل…",
            "logi_price_from": "من %@ ₸", "logi_per_kg": "+%@ ₸/كغ",
            "logi_car_cta": "اطلب مع التوصيل", "collect_bids": "اجمع العروض من الشركات",
            "collect_bids_note": "ستقدم الشركات أسعارها — اختر الأفضل في «توصيلاتي»", "bc_head": "طلب إلى المختصين القريبين",
            "bc_sub": "سيصل طلبك إلى البائعين والمختصين في نطاق 2 كم (أو في مدينتك)", "ph_broadcast": "صف ما تحتاجه…",
            "city_fail": "تعذّر تحديد المدينة", "my_address": "عنواني",
            "send_request": "إرسال الطلب", "request_sent": "تم الإرسال",
            "request_sent_n": "تم الإرسال (%@)", "write_need": "اكتب ما تحتاجه", "empty_post": "أبحث عن هذا — اسأل البائعين", "empty_ask_text": "أبحث عن: %@",
            "empty_ask_need": "اكتب ما تبحث عنه — ثم سنسأل البائعين",
            "report_sending": "جارٍ الإرسال…", "error_short": "خطأ",
            "net_error": "خطأ في الشبكة", "detecting_addr": "جارٍ تحديد العنوان…",
            "addr_detected": "تم تحديد العنوان", "no_geo_access": "لا يوجد وصول إلى الموقع",
            "bc_confirm_t": "إرسال الطلب؟", "bc_confirm_s": "سيراه مقدمو الخدمة القريبون ويردون عليك في الدردشة.",
            "cancel": "إلغاء", "need_session": "تعذّر الإرسال، حاول مرة أخرى",
            "ship_quote": "التوصيل ~ %@", "ship_quote_who": "يدفعه المشتري، إضافة إلى مبلغ الصفقة",
            "ship_eta": "~%@ دقيقة في الطريق", "eta_days": "%1$@–%2$@ أيام",
            "eta_days_one": "%@ أيام", "co_ship_free": "التوصيل على نفقة البائع"
        ]
    ]
}

private func тМеста(_ ключ: String) -> String { ListingLocationText.т(ключ) }

// MARK: - Правила сайта

/// mkIsDeliverable / mkIsBulky / mkWhereAmI и адреса приложений маршрута — mkRouteApps, mkCourierLaunch.
enum МаршрутОбъявления {
    /// Дальше этого курьер Яндекс Go не возит — MK_CITY_KM сайта.
    static let пределКурьераКм: Double = 30

    /// mkIsDeliverable: всё, кроме жилья, транспорта, услуг и работы.
    static func довозимое(_ товар: Listing) -> Bool {
        !["realty", "transport", "services", "jobs"].contains(товар.корень)
    }

    /// mkIsBulky: крупное — диваны, холодильники, стройматериалы… (по разделу category).
    static func крупное(_ товар: Listing) -> Bool {
        guard let раздел = товар.категория else { return false }
        return крупныеРазделы.contains(раздел)
    }

    private static let крупныеРазделы: Set<String> = [
        "sofas", "beds", "wardrobes", "tables", "furniture", "kitchen-furniture", "hall-furniture", "office-furniture",
        "outdoor-furniture", "fridges", "washing-machines", "dishwashers", "air-conditioners", "stoves", "water-heaters",
        "tv", "monitors", "desktops", "all-in-one", "windows-doors", "building-materials", "strollers",
        "strollers-carseats", "kids-furniture", "kids-beds", "cribs", "treadmills", "exercise-bikes", "weights-barbells",
        "home-theater", "projectors", "lawn-mowers"
    ]

    /// mkWhereAmI: город, выбранный в шапке ленты; не выбран — пусто.
    static var мойГород: String { ГдеИскать.сохранённое().город }

    /// Человек смотрит из другого города (s && t.city && s !== t.city у сайта).
    static func изДругогоГорода(_ товар: Listing) -> Bool {
        let мой = мойГород
        return !мой.isEmpty && !товар.city.isEmpty && мой != товар.city
    }

    /// Координата строкой без локали: «43.238949».
    static func число(_ x: Double) -> String { String(format: "%.6f", x) }

    private static let меткаЯндекса = "appmetrica_tracking_id=25395763362139037&lang=ru&ref=klikokz"

    /// Яндекс Go: к товару — end-lat/end-lon, от товара — start-lat/start-lon (mkRouteApps).
    static func яндексGo(_ т: CLLocationCoordinate2D, туда: Bool) -> (приложение: URL?, запасной: URL?) {
        let точка = туда
            ? "end-lat=" + число(т.latitude) + "&end-lon=" + число(т.longitude)
            : "start-lat=" + число(т.latitude) + "&start-lon=" + число(т.longitude)
        let хвост = "route?" + точка + "&" + меткаЯндекса
        return (URL(string: "yandextaxi://" + хвост), URL(string: "https://3.redirect.appmetrica.yandex.com/" + хвост))
    }

    /// Курьер Яндекс Go (mkCourierLaunch): откуда — товар, куда — вы, если точка известна.
    static func курьерЯндекса(от: CLLocationCoordinate2D?, до: CLLocationCoordinate2D?) -> (приложение: URL?, запасной: URL?) {
        var запрос = "route?tariffClass=courier&ref=klikokz&lang=ru&appmetrica_tracking_id=25395763362139037"
        if let а = от {
            запрос += "&start-lat=" + число(а.latitude)
            запрос += "&start-lon=" + число(а.longitude)
        }
        if let б = до {
            запрос += "&end-lat=" + число(б.latitude)
            запрос += "&end-lon=" + число(б.longitude)
        }
        return (URL(string: "yandextaxi://" + запрос), URL(string: "https://3.redirect.appmetrica.yandex.com/" + запрос))
    }

    /// 2ГИС: в приложении — routeSearch, в браузере — directions/points, как у сайта.
    static func дваГис(_ т: CLLocationCoordinate2D, туда: Bool) -> (приложение: URL?, запасной: URL?) {
        let lonLat = число(т.longitude) + "," + число(т.latitude)
        let вебТочка = число(т.longitude) + "%2C" + число(т.latitude)
        let приложение = "dgis://2gis.ru/routeSearch/rsType/car/" + (туда ? "to/" : "from/") + lonLat
        let веб = "https://2gis.kz/directions/points/" + (туда ? "%7C" + вебТочка : вебТочка + "%7C")
        return (URL(string: приложение), URL(string: веб))
    }

    static let inDrive = URL(string: "https://indrive.com")

    /// Apple Карты открываются всегда — своей схемы и проверки не нужно.
    static func appleКарты(_ т: CLLocationCoordinate2D, туда: Bool) -> URL? {
        let точка = число(т.latitude) + "," + число(т.longitude)
        return URL(string: "https://maps.apple.com/?" + (туда ? "daddr=" : "saddr=") + точка + "&dirflg=d")
    }

    static func яндексКарты(_ т: CLLocationCoordinate2D, туда: Bool) -> (приложение: URL?, запасной: URL?) {
        let точка = число(т.latitude) + "," + число(т.longitude)
        let маршрут = туда ? "~" + точка : точка + "~"
        return (URL(string: "yandexmaps://maps.yandex.ru/?rtext=" + маршрут + "&rtt=auto"),
                URL(string: "https://yandex.kz/maps/?rtext=" + маршрут + "&rtt=auto"))
    }

    static func googleMaps(_ т: CLLocationCoordinate2D, туда: Bool) -> (приложение: URL?, запасной: URL?) {
        let точка = число(т.latitude) + "," + число(т.longitude)
        let приложение = "comgooglemaps://?" + (туда ? "daddr=" : "saddr=") + точка + "&directionsmode=driving"
        let веб = "https://www.google.com/maps/dir/?api=1&" + (туда ? "destination=" : "origin=") + точка
        return (URL(string: приложение), URL(string: веб))
    }

    /// Установлено приложение — его схемой, нет — адресом в браузере.
    @MainActor
    static func открыть(_ пара: (приложение: URL?, запасной: URL?)) {
        if let приложение = пара.приложение, UIApplication.shared.canOpenURL(приложение) {
            UIApplication.shared.open(приложение)
        } else if let запасной = пара.запасной {
            UIApplication.shared.open(запасной)
        }
    }

    /// «≈ 3,4 км от вас» / «≈ 650 м от вас».
    static func расстояние(_ км: Double) -> String {
        if км < 1 {
            let метры = max(10, Int((км * 1000 / 10).rounded()) * 10)
            return String(format: тМеста("dist_m"), String(метры))
        }
        let ф = NumberFormatter()
        ф.locale = Locale(identifier: ListingPageText.язык)
        ф.maximumFractionDigits = км < 10 ? 1 : 0
        ф.minimumFractionDigits = 0
        let число = ф.string(from: NSNumber(value: км)) ?? String(Int(км.rounded()))
        return String(format: тМеста("dist_km"), число)
    }
}

// MARK: - Блок (mkLocationBlock)

struct РасположениеСайта: View {
    let товар: Listing
    /// Открыть страницу сайта — запасной путь «Согласовать с продавцом», если нативного чата нет.
    let открыть: ((URL) -> Void)?

    @State private var лист: ЛистРасположения?
    @State private var картаНаВесьЭкран = false
    @State private var чатСПродавцом = false
    @State private var скопировано = false
    /// Объявление вошедшего — блоков покупателя нет.
    @State private var своё = false
    /// «Как работает Безопасная сделка» (mkEscrowInfo) — гостю и непроверенному после «Купить безопасно с доставкой».
    @State private var пояснениеГаранта: ЛистГарантаОбъявления?
    @State private var послеПояснения: URL?

    init(товар: Listing, открыть: ((URL) -> Void)? = nil) {
        self.товар = товар
        self.открыть = открыть
    }

    private var поля: ПоляСтраницыВида { товар.поляВида }

    /// «Астана, Есильский район».
    private var место: String {
        var части: [String] = []
        if !товар.city.isEmpty { части.append(товар.city) }
        if let район = товар.районНазвание ?? поля.район { части.append(район) }
        return части.joined(separator: ", ")
    }

    private var точка: CLLocationCoordinate2D? { Self.точкаОбъявления(товар) }

    static func точкаОбъявления(_ товар: Listing) -> CLLocationCoordinate2D? {
        guard let ш = товар.поляВида.широта, let д = товар.поляВида.долгота, abs(ш) <= 90, abs(д) <= 180 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: ш, longitude: д)
    }

    /// Показывать ли блок: как у сайта — нет ни места, ни точки — нет и блока.
    static func есть(_ товар: Listing) -> Bool {
        !товар.city.isEmpty || товар.районНазвание != nil || товар.поляВида.район != nil || точкаОбъявления(товар) != nil
    }

    /// Город, район и улица одной строкой — для «Скопировать адрес».
    private var полныйАдрес: String {
        [место, поля.адрес ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// 2ГИС: с точкой — geo/<lon>,<lat>, без — поиск по месту.
    private var адрес2ГИС: URL? {
        if let т = точка {
            return URL(string: "https://2gis.kz/geo/" + МаршрутОбъявления.число(т.longitude) + "%2C"
                       + МаршрутОбъявления.число(т.latitude))
        }
        let допустимые = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~")
        guard !место.isEmpty, let запрос = место.addingPercentEncoding(withAllowedCharacters: допустимые) else {
            return nil
        }
        return URL(string: "https://2gis.kz/search/" + запрос)
    }

    private var довозимоеНекрупное: Bool {
        МаршрутОбъявления.довозимое(товар) && !МаршрутОбъявления.крупное(товар)
    }

    var body: some View {
        let другойГород = МаршрутОбъявления.изДругогоГорода(товар)
        /* Своё объявление: «в ваш регион не отправляют» не про продавца — его город не сверяем. */
        let регионы = ДоставкаОбъявления.строкаРегионов(товар, мойГород: своё ? "" : МаршрутОбъявления.мойГород)
        VStack(alignment: .leading, spacing: 10) {
            ПодзаголовокСайта(значок: "mappin.and.ellipse", текст: ListingKindsText.т("sec_location"))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(место.isEmpty ? ListingKindsText.т("sec_location") : место)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let адрес = адрес2ГИС {
                    Link(destination: адрес) {
                        Text(ListingKindsText.т("open_2gis"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.зелёный2)
                            .lineLimit(1)
                    }
                }
            }
            if let улица = поля.адрес {
                Text(улица)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !полныйАдрес.isEmpty {
                кнопкаСкопировать
            }
            if let регионы {
                СтрокаРегионовОтправки(строка: регионы)
            }
            if let т = точка {
                КартаМестаСайта(точка: т, название: товар.title) { картаНаВесьЭкран = true }
            }
            /* Владелец: на своём объявлении блоки покупателя («Доехать или доставить», курьер, грузоперевозки,
               «Доставка в другой город» и покупка) не имеют смысла — их нет; карта и адрес остаются. */
            if !своё {
                if точка != nil && !другойГород {
                    Button { лист = .маршрут } label: {
                        КнопкаМаршрутаСайта(доставить: довозимоеНекрупное)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                }
                if довозимоеНекрупное && точка == nil && !другойГород {
                    Button { лист = .курьер } label: {
                        ЧипМестаСайта(значок: "shippingbox", текст: тМеста("courier_city"))
                    }
                    .buttonStyle(.plain)
                }
                if МаршрутОбъявления.довозимое(товар) && МаршрутОбъявления.крупное(товар) {
                    ЧипыГрузоперевозокСайта(товар: товар, другойГород: другойГород)
                }
                if ДоставкаОбъявления.естьДоставкаИзГорода(товар, закрыто: регионы?.закрыто ?? false) {
                    ДоставкаИзГородаСайта(товар: товар, оформить: купитьБезопасно)
                }
            }
        }
        /* Вошедший — продавец этого объявления (P = w && w === r.seller_id, как у панели связи). */
        .task(id: товар.id) {
            let я = await SiteSession.состояние().пользователь
            своё = я != nil && я == товар.продавецID
        }
        /* .mk-mcol-e: линия сверху и 10 pt до «Расположения». */
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .sheet(item: $лист) { какой in
            switch какой {
            case .маршрут:
                if let т = точка {
                    ЛистМаршрутаСайта(товар: товар, точка: т, курьер: кКурьеру)
                }
            case .курьер:
                ЛистКурьераСайта(товар: товар, точка: точка,
                                 согласовать: кСогласованию,
                                 купитьБезопасно: купитьБезопасно)
            }
        }
        .fullScreenCover(isPresented: $картаНаВесьЭкран) {
            if let т = точка {
                КартаОбъявленияНаВесьЭкран(товар: товар, точка: т, маршрут: !другойГород)
            }
        }
        .sheet(item: $пояснениеГаранта, onDismiss: { открытьПослеПояснения() }) { какой in
            if case .пояснение(let кнопка) = какой {
                ЛистГарантСделки(кнопка: кнопка, открыть: { адрес in послеПояснения = адрес })
            }
        }
        .navigationDestination(isPresented: $чатСПродавцом) {
            экранЧата
        }
    }

    private var кнопкаСкопировать: some View {
        Button {
            UIPasteboard.general.string = полныйАдрес
            withAnimation(ДвижениеСайта.выбор) { скопировано = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation(ДвижениеСайта.выбор) { скопировано = false }
            }
        } label: {
            Label(тМеста(скопировано ? "copied" : "copy_addr"),
                  systemImage: скопировано ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(скопировано ? Theme.зелёный2 : Theme.текстВторой)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(тМеста("copy_addr"))
    }

    // MARK: Чат «Согласовать с продавцом» (mkCourierOrder → mkChatOpen)

    private var нативныйЧат: Bool {
        Config.нативныйЧат && (Config.чатОбъявления || (Config.нативныйЧатОтправка && товар.продавецID != nil))
    }

    /// «Курьер по городу» из листа маршрута — только у довозимого некрупного (как i у mkRouteOpen).
    private var кКурьеру: (() -> Void)? {
        guard довозимоеНекрупное else { return nil }
        return { лист = .курьер }
    }

    private var кСогласованию: (() -> Void)? {
        guard можноСогласовать else { return nil }
        return { согласовать() }
    }

    /// У сайта кнопка есть всегда; страница сайта нужна только запасному пути без нативного чата.
    private var можноСогласовать: Bool {
        нативныйЧат || (открыть != nil && товар.адрес != nil)
    }

    private func согласовать() {
        лист = nil
        if нативныйЧат {
            /* Лист сначала уезжает, потом страница кладёт чат в стек — иначе переход теряется. */
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                чатСПродавцом = true
            }
        } else if let адрес = товар.адрес, let открыть {
            открыть(адрес)
        }
    }

    @ViewBuilder
    private var экранЧата: some View {
        let откуда: (URL) -> Void = открыть ?? { _ in }
        if Config.чатОбъявления {
            ЭкранЧатаОбъявления(товар: товар, предложить: false, открыть: откуда)
        } else if let продавец = товар.продавецID {
            ChatThreadView(модель: ChatThreadModel(собеседник: продавец, объявление: товар.id),
                           заголовок: товар.продавец ?? "", открыть: откуда)
        }
    }

    /**
     🔴 «Купить безопасно с доставкой» / «Оформить с доставкой» — mkCourierClose() + mkEscrowCheckout(id) сайта: окно
     «Безопасная сделка» с курьером, выбранным сразу (DealCreateShip ставит тариф "courier"). Путь — как у «Купить
     безопасно» нижней панели (ПанельСвязиСайта.нажатьГарант): гость и непроверенный — пояснение, проверенный — своё
     создание сделки. Только при Config.деньгиСделок и если у объявления есть кнопка гаранта (ГарантОбъявления.кнопка:
     не ниже 20 000 ₸, не no_escrow, продавец проверен, не eds, гарант не на паузе).
     */
    private var купитьБезопасно: (() -> Void)? {
        guard Config.деньгиСделок, !товар.услуга, ГарантОбъявления.кнопка(товар) == .купить else { return nil }
        return { начатьСделкуСДоставкой() }
    }

    private func начатьСделкуСДоставкой() {
        let былЛист = лист != nil
        лист = nil
        Task { @MainActor in
            /* Лист сначала уезжает, потом переход (как у «Согласовать») — иначе он теряется. */
            if былЛист { try? await Task.sleep(nanoseconds: 450_000_000) }
            let доступ = await ЛистГарантСделки.кнопкаСейчас()
            guard доступ == .понятно else {
                пояснениеГаранта = .пояснение(доступ)
                return
            }
            if NativeRouter.доступна(.сделки) {
                ЗаданияДенегСделок.shared.положить(.сделка(товар: товар.id, оплата: "", срок: 0))
                NativeRouter.shared.цель = .сделки
            } else if let адрес = ГарантОбъявления.страница("cabinet.php?start_deal=", товар.id), let открыть {
                открыть(адрес)
            }
        }
    }

    /// Пояснение закрылось — страница, которую оно попросило открыть (регистрация, верификация).
    private func открытьПослеПояснения() {
        guard let адрес = послеПояснения else { return }
        послеПояснения = nil
        открыть?(адрес)
    }
}

enum ЛистРасположения: String, Identifiable {
    case маршрут, курьер
    var id: String { rawValue }
}

/// .mk-loc-go: значок такси в мятном квадрате, заголовок, подпись и шеврон.
private struct КнопкаМаршрутаСайта: View {
    let доставить: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "car.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 34, height: 34)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(тМеста(доставить ? "route_both_t" : "route_go_t"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(тМеста(доставить ? "route_both_s" : "route_go_s"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.forward")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 4)
        .contentShape(Rectangle())
    }
}

/// .mk-loc-chip: пилюля с значком.
struct ЧипМестаСайта: View {
    let значок: String
    let текст: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.текст)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(Theme.поверхность2, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.линия, lineWidth: 1.5) }
        .contentShape(Capsule())
    }
}

/// .mk-map: карта с меткой, масштаб 14 у сайта. На странице не листается (страницу смахивают вниз) — нажатие
/// открывает её на весь экран.
private struct КартаМестаСайта: View {
    let точка: CLLocationCoordinate2D
    let название: String
    let открыть: () -> Void

    var body: some View {
        let место = MKCoordinateRegion(center: точка, latitudinalMeters: 1600, longitudinalMeters: 1600)
        Map(initialPosition: MapCameraPosition.region(место), interactionModes: []) {
            Marker(название, coordinate: точка)
                .tint(Theme.зелёный2)
        }
        .frame(height: 200)
        .allowsHitTesting(false)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.текст)
                .frame(width: 30, height: 30)
                .background(Theme.поверхность, in: Circle())
                .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                .padding(10)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
        .overlay {
            /* Сама карта нажатий не принимает (allowsHitTesting) — нажатие ловит прозрачный слой поверх. */
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { открыть() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(тМеста("open_map"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { открыть() }
    }
}

// MARK: - Лист маршрута (mkRouteOpen)

struct ЛистМаршрутаСайта: View {
    let товар: Listing
    let точка: CLLocationCoordinate2D
    /// «Курьер по городу» под «или не ехать вовсе»; nil — не показывать.
    let курьер: (() -> Void)?

    @Environment(\.dismiss) private var закрыть
    /// «Я еду туда» (точка — конец маршрута) или «Еду оттуда» (начало), как _mkRouteDir.
    @State private var туда = true

    init(товар: Listing, точка: CLLocationCoordinate2D, курьер: (() -> Void)?) {
        self.товар = товар
        self.точка = точка
        self.курьер = курьер
    }

    private var подпись: String {
        var части: [String] = []
        if !товар.city.isEmpty { части.append(товар.city) }
        if let район = товар.районНазвание { части.append(район) }
        return части.joined(separator: ", ")
    }

    private var заметка: String { тМеста(туда ? "route_note_to" : "route_note_from") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(тМеста("route_h"))
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                        if !подпись.isEmpty {
                            Text(подпись)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЗакрытьМеста { закрыть() }
                }
                ПереключательНаправления(туда: $туда)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                СтрокаПриложенияМаршрута(значок: "car.fill", название: тМеста("yandex_go"), подпись: заметка,
                                         фон: Color(red: 1, green: 0.859, blue: 0.302),
                                         цвет: Color(red: 0.102, green: 0.102, blue: 0.102)) {
                    открыть(МаршрутОбъявления.яндексGo(точка, туда: туда))
                }
                СтрокаПриложенияМаршрута(значок: "car.2.fill", название: "inDrive", подпись: тМеста("route_note_deal"),
                                         фон: Color(red: 0.757, green: 0.945, blue: 0.114),
                                         цвет: Color(red: 0.086, green: 0.145, blue: 0.039)) {
                    открыть((приложение: nil, запасной: МаршрутОбъявления.inDrive))
                }
                СтрокаПриложенияМаршрута(значок: "location.north.circle.fill", название: "2ГИС", подпись: заметка,
                                         фон: Color(red: 0.149, green: 0.502, blue: 0.208), цвет: .white,
                                         подложкаЗначка: 0.2) {
                    открыть(МаршрутОбъявления.дваГис(точка, туда: туда))
                }
                РазделительМаршрута(текст: тМеста("nav_apps"))
                СтрокаПриложенияМаршрута(значок: "map.fill", название: тМеста("apple_maps"), подпись: заметка,
                                         фон: Theme.поверхность2, цвет: Theme.текст) {
                    открыть((приложение: nil, запасной: МаршрутОбъявления.appleКарты(точка, туда: туда)))
                }
                СтрокаПриложенияМаршрута(значок: "map", название: тМеста("yandex_maps"), подпись: заметка,
                                         фон: Theme.поверхность2, цвет: Theme.текст) {
                    открыть(МаршрутОбъявления.яндексКарты(точка, туда: туда))
                }
                СтрокаПриложенияМаршрута(значок: "globe", название: тМеста("google_maps"), подпись: заметка,
                                         фон: Theme.поверхность2, цвет: Theme.текст) {
                    открыть(МаршрутОбъявления.googleMaps(точка, туда: туда))
                }
                if let курьер {
                    РазделительМаршрута(текст: тМеста("route_or"))
                    Button { курьер() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.зелёный2)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(тМеста("courier_city"))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.текст)
                                Text(тМеста("route_cour_s"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 60)
                        .background(Theme.поверхность,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        /* По высоте списка приложений — целиком, без пустоты снизу. */
        .листПоВысоте()
    }

    /// Как onclick="mkRouteClose()" у ссылок сайта: приложение открылось — лист закрыт.
    private func открыть(_ пара: (приложение: URL?, запасной: URL?)) {
        МаршрутОбъявления.открыть(пара)
        закрыть()
    }
}

/// .mk-route-seg: «Я еду туда» / «Еду оттуда».
private struct ПереключательНаправления: View {
    @Binding var туда: Bool

    var body: some View {
        HStack(spacing: 4) {
            кнопка(тМеста("route_to"), выбрана: туда) { туда = true }
            кнопка(тМеста("route_from"), выбрана: !туда) { туда = false }
        }
        .padding(4)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func кнопка(_ текст: String, выбрана: Bool, _ действие: @escaping () -> Void) -> some View {
        Button {
            withAnimation(ДвижениеСайта.выбор) { действие() }
        } label: {
            Text(текст)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(выбрана ? Theme.текст : Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if выбрана {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .fill(Theme.поверхность)
                            .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}

/// .mk-route-app: цветная строка приложения со стрелкой «наружу».
private struct СтрокаПриложенияМаршрута: View {
    let значок: String
    let название: String
    let подпись: String
    let фон: Color
    let цвет: Color
    /// .ra-ic: белая подложка 35 %, у 2ГИС — 20 %.
    var подложкаЗначка: Double = 0.35
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(подложкаЗначка),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(название)
                        .font(.system(size: 14, weight: .heavy))
                    Text(подпись)
                        .font(.system(size: 11, weight: .medium))
                        .opacity(0.75)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(цвет)
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
    }
}

/// .mk-route-or: подпись между двумя линиями.
private struct РазделительМаршрута: View {
    let текст: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.линия).frame(height: 1)
            Text(текст.lowercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .layoutPriority(1)
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

/// .mk-route-x: круглый «×».
struct КнопкаЗакрытьМеста: View {
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 34, height: 34)
                .background(Theme.поверхность2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(тМеста("close"))
    }
}

// MARK: - Лист курьера (mkCourier)

struct ЛистКурьераСайта: View {
    let товар: Listing
    let точка: CLLocationCoordinate2D?
    /// «Согласовать с продавцом»; nil — некуда вести.
    let согласовать: (() -> Void)?
    /// 🔴 «Купить безопасно с доставкой» — nil, пока Config.деньгиСделок выключен.
    let купитьБезопасно: (() -> Void)?

    @Environment(\.dismiss) private var закрыть
    @State private var куда: String = UserDefaults.standard.string(forKey: ЛистКурьераСайта.ключАдреса) ?? ""
    @State private var моя: CLLocationCoordinate2D?
    @State private var состояние: Состояние = .нет
    @State private var гео = ГеопозицияКарты()

    /// Адрес покупателя — ulx_buyer_loc сайта: подставляется в следующий раз.
    static let ключАдреса = "kliko.buyer_loc"

    init(товар: Listing, точка: CLLocationCoordinate2D?, согласовать: (() -> Void)?, купитьБезопасно: (() -> Void)?) {
        self.товар = товар
        self.точка = точка
        self.согласовать = согласовать
        self.купитьБезопасно = купитьБезопасно
    }

    /// Поле адреса: правка руками сбрасывает найденную точку (oninput="_mkToCoords=null" у сайта); запись из
    /// «Определить автоматически» идёт мимо этой привязки и точку не трогает.
    private var полеКуда: Binding<String> {
        Binding(get: { куда }, set: { новое in
            куда = новое
            моя = nil
            if состояние == .найден || состояние == .безАдреса { состояние = .нет }
        })
    }

    enum Состояние: Equatable {
        /// отказ — доступ к геопозиции запрещён (geo_denied); безАдреса — точка есть, адрес по ней не нашёлся
        /// (addr_fail_manual).
        case нет, ищем, найден, ошибка, отказ, безАдреса, далеко, вПриложении, открываем
    }

    private var откуда: String {
        var части: [String] = []
        if !товар.city.isEmpty { части.append(товар.city) }
        if let район = товар.районНазвание ?? товар.поляВида.район { части.append(район) }
        if let улица = товар.поляВида.адрес { части.append(улица) }
        return части.isEmpty ? тМеста("addr_unknown") : части.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(тМеста("courier_city"), systemImage: "shippingbox.fill")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    КнопкаЗакрытьМеста { закрыть() }
                }
                маршрутАБ
                if let строка = строкаСостояния {
                    строка
                }
                if let моя {
                    КотировкаДоставкиСайта(товар: товар, точка: моя)
                }
                /* Гарант на паузе — без «Купить безопасно с доставкой» и его обещания. */
                if let купитьБезопасно, !ПаузаГаранта.наПаузеСейчас {
                    Button {
                        запомнитьАдрес()
                        АдресИзЛистаКурьера.положить(товар: товар.id, текст: куда,
                                                    широта: моя?.latitude, долгота: моя?.longitude)
                        купитьБезопасно()
                    } label: {
                        Label(тМеста("courier_safe_t"), systemImage: "checkmark.shield.fill")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                    Text(тМеста("courier_safe_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                Button { вызватьЯндекс() } label: {
                    HStack(spacing: 10) {
                        Text("Я")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color(red: 0.988, green: 0.247, blue: 0.114))
                            .frame(width: 22, height: 22)
                            .background(Color.white, in: Circle())
                            .accessibilityHidden(true)
                        Text(тМеста("call_courier_yandex"))
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(red: 0.988, green: 0.247, blue: 0.114),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                .padding(.top, 4)
                /* .mk-courier-warn: цвет предупреждения, по центру. */
                Text(тМеста("courier_ya_warn"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.звезда)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                if let согласовать {
                    Button {
                        запомнитьАдрес()
                        согласовать()
                    } label: {
                        Label(тМеста("agree_with_seller"), systemImage: "bubble.left.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.поверхность2,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                    .strokeBorder(Theme.линия, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.99))
                }
                /* .mk-courier-note: последней, как у сайта, по центру. */
                Text(тМеста("route_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        /* По высоте содержимого; не влезает — до полного с прокруткой. */
        .листПоВысоте()
    }

    /// Две точки с линией между ними — .mk-courier-row / .mk-courier-line.
    private var маршрутАБ: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Theme.зелёный2).frame(width: 12, height: 12).padding(.top, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(тМеста("from_seller"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    Text(откуда)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle()
                .fill(Theme.линия)
                .frame(width: 2, height: 18)
                .padding(.leading, 5)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(Theme.оранжевый).frame(width: 12, height: 12).padding(.top, 4)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(тМеста("to_you"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    TextField(тМеста("ph_courier_addr"), text: полеКуда)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текст)
                        .textContentType(.fullStreetAddress)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                    Button { определить() } label: {
                        Label(тМеста("detect_auto"), systemImage: "location.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.зелёный2)
                    }
                    .buttonStyle(.plain)
                    .disabled(состояние == .ищем)
                }
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var строкаСостояния: AnyView? {
        let текст: String
        let значок: String
        let цвет: Color
        switch состояние {
        case .нет:
            return nil
        case .ищем:
            текст = тМеста("addr_detecting"); значок = "location"; цвет = Theme.текстВторой
        case .найден:
            текст = тМеста("addr_detected_call"); значок = "checkmark.circle.fill"; цвет = Theme.зелёный2
        case .ошибка:
            текст = тМеста("geo_fail"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .отказ:
            текст = тМеста("geo_denied"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .безАдреса:
            текст = тМеста("addr_fail_manual"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .далеко:
            текст = тМеста("courier_far"); значок = "exclamationmark.triangle.fill"; цвет = Theme.оранжевый
        case .вПриложении:
            текст = тМеста("courier_addr_in_app"); значок = "location"; цвет = Theme.текстВторой
        case .открываем:
            текст = тМеста("opening_yandex"); значок = "checkmark.circle.fill"; цвет = Theme.зелёный2
        }
        return AnyView(
            Label(текст, systemImage: значок)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(цвет)
                .fixedSize(horizontal: false, vertical: true)
        )
    }

    private func запомнитьАдрес() {
        let адрес = куда.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !адрес.isEmpty else { return }
        UserDefaults.standard.set(адрес, forKey: Self.ключАдреса)
    }

    /// mkCourierGeo / mkGeoAddr: точка телефона и адрес по ней — «город, район, улица дом». Разрешение спрашивается
    /// здесь — по нажатию. Доступ запрещён — geo_denied; адрес не нашёлся — addr_fail_manual, но точка остаётся для
    /// маршрута и расчёта (у сайта её нет — своё, мягче).
    private func определить() {
        состояние = .ищем
        гео.узнать { координата in
            Task { @MainActor in
                guard let координата else {
                    let статус = CLLocationManager().authorizationStatus
                    состояние = (статус == .denied || статус == .restricted) ? .отказ : .ошибка
                    return
                }
                моя = координата
                let место = CLLocation(latitude: координата.latitude, longitude: координата.longitude)
                let найдено = try? await CLGeocoder().reverseGeocodeLocation(место)
                var строка = ""
                if let метка = найдено?.first {
                    let улица = [метка.thoroughfare, метка.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                    var части: [String] = []
                    if let город = метка.locality { части.append(город) }
                    if let район = метка.subLocality, район != метка.locality { части.append(район) }
                    if !улица.isEmpty { части.append(улица) }
                    строка = части.joined(separator: ", ")
                }
                guard !строка.isEmpty else {
                    состояние = .безАдреса
                    return
                }
                куда = строка
                состояние = .найден
                запомнитьАдрес()
            }
        }
    }

    /// mkCourierLaunch: откуда — точка объявления, куда — ваша точка; дальше 30 км — предупреждение.
    private func вызватьЯндекс() {
        запомнитьАдрес()
        if let б = моя {
            if далеко(б) {
                состояние = .далеко
                return
            }
            состояние = .открываем
            МаршрутОбъявления.открыть(МаршрутОбъявления.курьерЯндекса(от: точка, до: б))
            return
        }
        let введено = куда.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !введено.isEmpty else {
            МаршрутОбъявления.открыть(МаршрутОбъявления.курьерЯндекса(от: точка, до: nil))
            return
        }
        /* Адрес вписан руками: у сайта точка Б — центр города (_mkCityCoord по введённому, выбранному в ленте или
           городу объявления); здесь — геокодер телефона: введённое (с городом объявления, если его нет в строке), потом
           выбранный город и город объявления — первое найденное. */
        let город = товар.city.isEmpty ? МаршрутОбъявления.мойГород : товар.city
        var запросы: [String] = []
        if !город.isEmpty && !введено.lowercased().contains(город.lowercased()) {
            запросы.append(введено + ", " + город)
        } else {
            запросы.append(введено)
        }
        for запасной in [МаршрутОбъявления.мойГород, товар.city] where !запасной.isEmpty && !запросы.contains(запасной) {
            запросы.append(запасной)
        }
        Task { @MainActor in
            var найдено: CLLocationCoordinate2D? = nil
            for запрос in запросы {
                if let метка = try? await CLGeocoder().geocodeAddressString(запрос).first,
                   let место = метка.location {
                    найдено = место.coordinate
                    break
                }
            }
            guard let б = найдено else {
                состояние = .вПриложении
                МаршрутОбъявления.открыть(МаршрутОбъявления.курьерЯндекса(от: точка, до: nil))
                return
            }
            if далеко(б) {
                состояние = .далеко
                return
            }
            состояние = .открываем
            МаршрутОбъявления.открыть(МаршрутОбъявления.курьерЯндекса(от: точка, до: б))
        }
    }

    /// Дальше MK_CITY_KM от точки объявления (без точки объявления проверять не с чем).
    private func далеко(_ б: CLLocationCoordinate2D) -> Bool {
        guard let а = точка else { return false }
        return ГеометрияКарты.км(а.latitude, а.longitude, б.latitude, б.longitude) > МаршрутОбъявления.пределКурьераКм
    }
}

// MARK: - Карта на весь экран

struct КартаОбъявленияНаВесьЭкран: View {
    let товар: Listing
    let точка: CLLocationCoordinate2D
    /// Кнопка «Построить маршрут» — по тем же правилам, что на странице (не из другого города).
    let маршрут: Bool

    @Environment(\.dismiss) private var закрыть
    @State private var камера: MapCameraPosition
    @State private var моя: CLLocationCoordinate2D?
    @State private var ищем = false
    @State private var ошибка = false
    @State private var листМаршрута = false
    @State private var гео = ГеопозицияКарты()

    init(товар: Listing, точка: CLLocationCoordinate2D, маршрут: Bool) {
        self.товар = товар
        self.точка = точка
        self.маршрут = маршрут
        _камера = State(initialValue: MapCameraPosition.region(
            MKCoordinateRegion(center: точка, latitudinalMeters: 1600, longitudinalMeters: 1600)))
    }

    private var км: Double? {
        guard let я = моя else { return nil }
        return ГеометрияКарты.км(я.latitude, я.longitude, точка.latitude, точка.longitude)
    }

    var body: some View {
        Map(position: $камера) {
            Marker(товар.title, coordinate: точка)
                .tint(Theme.зелёный2)
            if let я = моя {
                Annotation(тМеста("geo_ask_mine"), coordinate: я) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                        .overlay { Circle().strokeBorder(Color.white, lineWidth: 3) }
                        .shadow(color: Color.black.opacity(0.25), radius: 3)
                }
                MapPolyline(coordinates: [я, точка])
                    .stroke(Theme.зелёный2, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topLeading) {
            КнопкаЗакрытьМеста { закрыть() }
                .padding(.leading, 16)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
        .background(Theme.поверхность.ignoresSafeArea())
        .sheet(isPresented: $листМаршрута) {
            ЛистМаршрутаСайта(товар: товар, точка: точка, курьер: nil)
        }
    }

    private var низ: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(товар.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
            if let км {
                Label(МаршрутОбъявления.расстояние(км), systemImage: "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
            } else if ошибка {
                Label(тМеста("geo_fail"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button { найтиМеня() } label: {
                    Label(тМеста(ищем ? "geo_locating" : "geo_ask_mine"), systemImage: "location")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                .disabled(ищем)
                if маршрут {
                    Button { листМаршрута = true } label: {
                        Label(тМеста("route_go_t"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.зелёный2,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1).accessibilityHidden(true)
        }
    }

    /// Разрешение спрашивается только здесь, по нажатию; точка — одна, следить не следим.
    private func найтиМеня() {
        ищем = true
        ошибка = false
        гео.узнать { координата in
            Task { @MainActor in
                ищем = false
                guard let координата else {
                    ошибка = true
                    return
                }
                моя = координата
                withAnimation(ДвижениеСайта.камера) { камера = .automatic }
            }
        }
    }
}
