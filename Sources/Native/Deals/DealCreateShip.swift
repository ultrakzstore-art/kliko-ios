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
       доставляем только СДЭК…»; бесплатная доставка продавца — только free + courier; иначе курьер Яндекса: tariff
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
        "co_ship_same": "Транспортные компании (СДЭК…) — только в другой город, дальше 30 км. В своём городе — курьер Яндекса или «Заберу сам».",
        "co_ship_intercity": "Дальше 30 км доставляем только СДЭК, а для этого товара и адреса он сейчас недоступен — оформить с доставкой не получится. Напишите продавцу.",
        "co_ship_region": "Продавец не отправляет в ваш регион — можно договориться о встрече или забрать самому.",
        "co_ship_free": "Доставка за счёт продавца",
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
        "co_car_track": "Трек-номер выдаст транспортная компания, когда продавец сдаст посылку, — он появится в сделке."
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
        "co_ship_same": "Көлік компаниялары (СДЭК…) — тек басқа қалаға, 30 км-ден алыс. Өз қалаңызда — Яндекс курьері немесе «Өзім аламын».",
        "co_ship_intercity": "30 км-ден алыс тек СДЭК жеткізеді, ал бұл тауар мен мекенжай үшін ол қазір қолжетімсіз — жеткізумен рәсімдеу мүмкін емес. Сатушыға жазыңыз.",
        "co_ship_region": "Сатушы сіздің өңіріңізге жібермейді — кездесуге келісуге немесе өзіңіз алып кетуге болады.",
        "co_ship_free": "Жеткізу сатушының есебінен",
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
        "co_car_track": "Трек-нөмірді сатушы сәлемдемені тапсырғанда көлік компаниясы береді — ол мәміледе шығады."
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
        "co_ship_same": "Shipping companies (CDEK…) are only for another city, farther than 30 km. Within your city — Yandex courier or pickup.",
        "co_ship_intercity": "Beyond 30 km only CDEK delivers, and it isn't available for this item and address right now — delivery can't be arranged. Message the seller.",
        "co_ship_region": "The seller doesn't ship to your region — you can arrange a meeting or pick it up yourself.",
        "co_ship_free": "Delivery paid by the seller",
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
        "co_car_track": "The shipping company issues the tracking number when the seller drops off the parcel — it will appear in the deal."
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
        "co_ship_same": "شركات الشحن (CDEK…) للمدن الأخرى فقط، أبعد من 30 كم. داخل مدينتك — مندوب Yandex أو الاستلام بنفسك.",
        "co_ship_intercity": "لأبعد من 30 كم يوصل CDEK فقط، وهو غير متاح الآن لهذه السلعة وهذا العنوان — لا يمكن الطلب مع التوصيل. راسل البائع.",
        "co_ship_region": "البائع لا يشحن إلى منطقتك — يمكنكما الاتفاق على لقاء أو الاستلام بنفسك.",
        "co_ship_free": "التوصيل على حساب البائع",
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
        "co_car_track": "رقم التتبع تصدره شركة النقل عندما يسلّم البائع الطرد — وسيظهر في الصفقة."
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
    }

    private static var запись: Запись? = nil

    static func положить(товар: String, текст: String, широта: Double?, долгота: Double?) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else {
            запись = nil
            return
        }
        запись = Запись(товар: товар, текст: чистый, точка: ТочкаСделки(широта, долгота), когда: Date())
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
            применить(Адрес(текст: изЛиста.текст, точка: изЛиста.точка, дверь: [:], уПодъезда: false))
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

    private func применить(_ а: Адрес) {
        адрес = а
        if а.точка != nil {
            посчитать()
        } else {
            номерРасчёта += 1
            расчёт = .нужнаТочка
        }
    }

    /// Выбор строки: nil — «Заберу сам» (mkEcoShipPick).
    func выбрать(_ вариант: ВариантДоставкиСделки?) {
        guard let вариант else {
            самЗаберу = true
            return
        }
        самЗаберу = false
        тариф = вариант.id
        if вариант.доПВЗ, (пункты[вариант.перевозчик] ?? "").isEmpty, let первый = списокПунктов(вариант).first {
            пункты[вариант.перевозчик] = первый.id
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
        if A.да(j["ok"]), A.строка(j["mode"]) == "carriers", let предложения = j["offers"] as? [String: Any] {
            скрыт = false
            var список: [ВариантДоставкиСделки] = []
            for ключ in предложения.keys.sorted() {
                guard let п = предложения[ключ] as? [String: Any] else { continue }
                let q = A.строка(п["q"])
                let цена = A.целое(п["price"])
                guard !q.isEmpty, цена > 0 else { continue }
                список.append(ВариантДоставкиСделки(id: ключ, цена: цена, минут: 0, q: q, бесплатно: false,
                                                    перевозчик: A.строка(п["carrier"]), имя: A.строка(п["name"]),
                                                    доПВЗ: A.строка(п["kind"]) == "pvz",
                                                    днейОт: A.целое(п["days_min"]), днейДо: A.целое(п["days_max"])))
            }
            /* У сайта порядок — порядок ключей ответа; JSONSerialization его не хранит — дешёвые выше. */
            список.sort { $0.цена < $1.цена }
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
        if бесплатная {
            /* Бесплатная доставка продавца: только бесплатный курьер, иначе блока нет. */
            if A.да(j["ok"]), A.да(j["free"]), A.да(j["courier"]), !A.строка(j["q"]).isEmpty {
                скрыт = false
                let в = ВариантДоставкиСделки(id: "courier", цена: 0, минут: A.целое(j["eta"]), q: A.строка(j["q"]),
                                             бесплатно: true, перевозчик: "", имя: "", доПВЗ: false, днейОт: 0, днейДо: 0)
                расчёт = .курьер([в])
                тариф = в.id
            } else {
                скрыт = true
            }
            return
        }
        скрыт = false
        if A.да(j["ok"]), !A.да(j["free"]), !A.строка(j["q"]).isEmpty, A.целое(j["price"]) > 0 {
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

    init(доставка: ДоставкаНовойСделки, изменитьАдрес: @escaping () -> Void) {
        self.доставка = доставка
        self.изменитьАдрес = изменитьАдрес
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
            HStack(spacing: 8) {
                SiteSpinner.мелкий
                Text(т("co_ship_calc2"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            строкаСам
        case .нужнаТочка:
            подсказка(т("co_ship_house"))
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
            if ["no_from", "no_item", "bad_args"].contains(причина) {
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
            подпись = дни(в)
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

    private var строкаСам: some View {
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
