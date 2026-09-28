import SwiftUI
import UIKit
import Foundation

/**
 ОТСЛЕЖИВАНИЕ ДОСТАВКИ — МОДЕЛЬ (владелец: «статусы Яндекс Доставки, СДЭК, Казпочты и других — нативно внутри приложения,
 без перехода на сайт и сайты перевозчиков»).

 Одна нормализованная запись на сделку (ДанныеТрека): перевозчик, трек-номер, текущий статус, сроки, курьер, лента
 событий, время обновления. Откуда она берётся — СлужбаОтслеживания (TrackingService.swift): сервер kliko.kz
 (escrow.php?action=track, контракт — docs/SERVER_TRACKING.md), живые поля Яндекса в clocal.delivery сделки, публичный
 API Казпочты. Экраны — TrackingViews.swift.

 🔒 Ключи перевозчиков (OAuth СДЭК, токен Яндекс B2B) в приложении не живут никогда: такие перевозчики — только через
 сервер. С телефона напрямую — только перевозчики с открытым API без ключа (сейчас одна Казпочта).

 Коды статусов (rawValue) — те же строки, что в JSON сервера: created, accepted, in_transit, arrived_pickup,
 out_for_delivery, delivered, returned, problem, cancelled, unknown.
 */

// MARK: - Перевозчик

enum ПеревозчикТрека: String, Codable, CaseIterable, Sendable {
    case yandex
    case indrive
    case cdek
    case kazpost
    case dhl
    case exline
    case avis
    case ups
    case fedex
    case другой = "other"

    /// Код сервера (ship_carrier, carrier, track.carrier) — неизвестный становится «другой».
    init(код: String) {
        let к = код.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch к {
        case "yandex_go", "yandex_delivery", "yandex-delivery", "ya", "yandex.go":
            self = .yandex
        case "kazpost", "post.kz", "kazpochta", "kz_post", "kaz_post", "qazpost":
            self = .kazpost
        case "indriver", "in_drive":
            self = .indrive
        case "sdek", "сдэк":
            self = .cdek
        default:
            self = ПеревозчикТрека(rawValue: к) ?? .другой
        }
    }

    var название: String {
        switch self {
        case .yandex:  return ТрекText.т("c_yandex")
        case .indrive: return "inDrive"
        case .cdek:    return ТрекText.т("c_cdek")
        case .kazpost: return ТрекText.т("c_kazpost")
        case .dhl:     return "DHL"
        case .exline:  return "Exline"
        case .avis:    return "Avis"
        case .ups:     return "UPS"
        case .fedex:   return "FedEx"
        case .другой:  return ТрекText.т("c_other")
        }
    }

    /// Знак в кружке — SF Symbol (своих логотипов перевозчиков в приложении нет: товарные знаки не рисуем).
    var символ: String {
        switch self {
        case .yandex, .indrive: return "car.fill"
        case .cdek:             return "shippingbox.fill"
        case .kazpost:          return "envelope.fill"
        case .dhl, .fedex:      return "airplane"
        case .exline, .avis:    return "box.truck.fill"
        case .ups:              return "shippingbox.fill"
        case .другой:           return "shippingbox"
        }
    }

    /// Фирменный цвет кружка — одинаковый в обеих темах (кружок лежит сам по себе, знак на нём своего цвета).
    var цвет: Color {
        switch self {
        case .yandex:  return Color(uiColor: Theme.hex(0xFFCC00))
        case .indrive: return Color(uiColor: Theme.hex(0xC1F11D))
        case .cdek:    return Color(uiColor: Theme.hex(0x1AB248))
        case .kazpost: return Color(uiColor: Theme.hex(0x0A4DA2))
        case .dhl:     return Color(uiColor: Theme.hex(0xFFCC00))
        case .exline:  return Color(uiColor: Theme.hex(0xF26722))
        case .avis:    return Color(uiColor: Theme.hex(0xD4002A))
        case .ups:     return Color(uiColor: Theme.hex(0x351C15))
        case .fedex:   return Color(uiColor: Theme.hex(0x4D148C))
        case .другой:  return Theme.зелёный
        }
    }

    /// Цвет знака на кружке: на жёлтом и салатовом — тёмный, на остальных — белый.
    var цветЗнака: Color {
        switch self {
        case .yandex, .indrive: return Color(uiColor: Theme.hex(0x1A1A1A))
        case .dhl:              return Color(uiColor: Theme.hex(0xD40511))
        case .ups:              return Color(uiColor: Theme.hex(0xFFB500))
        default:                return Color.white
        }
    }

    /// Статусы без ключа можно спросить прямо с телефона — только Казпочта (КазпочтаТрека).
    var открытыйAPI: Bool { self == .kazpost }

    /**
     Публичная страница отслеживания перевозчика — последний выход (СостояниеТрека.нетДанных): открывается листом
     Safari ВНУТРИ приложения, не в браузере. Адреса — публичные страницы перевозчиков, проверить на устройстве.
     */
    func страница(номер: String) -> URL? {
        let н = номер.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        guard !н.isEmpty else { return nil }
        switch self {
        case .cdek:    return URL(string: "https://www.cdek.kz/ru/tracking?order_id=" + н)
        case .kazpost: return URL(string: "https://post.kz/mail/search/track/" + н + "/detail")
        case .dhl:     return URL(string: "https://www.dhl.com/kz-ru/home/tracking.html?tracking-id=" + н)
        case .ups:     return URL(string: "https://www.ups.com/track?tracknum=" + н)
        case .fedex:   return URL(string: "https://www.fedex.com/fedextrack/?trknbr=" + н)
        case .yandex, .indrive, .exline, .avis, .другой: return nil
        }
    }
}

// MARK: - Статус

/// Вид плашки статуса: зелёный — вручено, синий — едет, жёлтый — ждём, красный — беда, серый — неясно.
enum ВидСтатусаТрека: Sendable {
    case хорошо
    case путь
    case ждём
    case плохо
    case тихо

    /// Краски кабинета сделок (КраскаСделокКабинета, css_cabinet.css) — как плашки .dmn рядом.
    var цвет: Color {
        switch self {
        case .хорошо: return КраскаСделокКабинета.хорошоТекст
        case .путь:   return КраскаСделокКабинета.инфоТекст
        case .ждём:   return КраскаСделокКабинета.предупреждениеТекст
        case .плохо:  return КраскаСделокКабинета.плохоТекст
        case .тихо:   return Theme.текстВторой
        }
    }

    var фон: Color {
        switch self {
        case .хорошо: return КраскаСделокКабинета.хорошоФон
        case .путь:   return КраскаСделокКабинета.инфоФон
        case .ждём:   return КраскаСделокКабинета.предупреждениеФон
        case .плохо:  return КраскаСделокКабинета.плохоФон
        case .тихо:   return Theme.поверхность2
        }
    }
}

enum СтатусТрека: String, Codable, CaseIterable, Sendable {
    case создан = "created"
    case принят = "accepted"
    case вПути = "in_transit"
    case вПунктеВыдачи = "arrived_pickup"
    case курьерВезёт = "out_for_delivery"
    case доставлен = "delivered"
    case возврат = "returned"
    case проблема = "problem"
    case отменён = "cancelled"
    case неизвестно = "unknown"

    /// Код сервера; синонимы — на всякий случай (returning, arrived, exception…).
    init(код: String) {
        let к = код.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch к {
        case "new", "registered", "info_received", "pending": self = .создан
        case "picked_up", "pickup", "received": self = .принят
        case "transit", "intransit", "sorting", "departed": self = .вПути
        case "arrived", "ready", "ready_for_pickup", "available_for_pickup", "pvz": self = .вПунктеВыдачи
        case "courier", "out_for_delivery_courier", "delivering": self = .курьерВезёт
        case "handed", "done", "completed": self = .доставлен
        case "returning", "return", "returned_to_sender": self = .возврат
        case "exception", "failed", "delay", "delayed", "lost": self = .проблема
        case "canceled", "cancel": self = .отменён
        default: self = СтатусТрека(rawValue: к) ?? .неизвестно
        }
    }

    /// clocalYaLabel сайта → нормализованный статус. performer_found и дальше — курьер уже едет за товаром.
    static func изЯндекса(_ код: String) -> СтатусТрека {
        switch код.lowercased() {
        case "new", "estimating", "ready_for_approval", "accepted", "performer_lookup", "performer_draft":
            return .создан
        case "performer_found", "pickup_arrived", "ready_for_pickup_confirmation":
            return .принят
        case "pickuped":
            return .вПути
        case "delivery_arrived", "ready_for_delivery_confirmation":
            return .курьерВезёт
        case "pay_waiting", "delivered", "delivered_finish":
            return .доставлен
        case "returning", "return_arrived", "ready_for_return_confirmation", "returned", "returned_finish":
            return .возврат
        case "cancelled", "cancelled_by_taxi", "cancelled_with_payment", "cancelled_with_items_on_hands":
            return .отменён
        case "failed", "performer_not_found", "estimating_failed":
            return .проблема
        default:
            return .неизвестно
        }
    }

    /// dealCarStage сайта (ship_car_stage): created, accepted, in_transit, arrived, delivered, returning, returned,
    /// cancelled, problem. arrived «до двери» — курьер везёт.
    static func изЭтапа(_ этап: String, доДвери: Bool) -> СтатусТрека {
        switch этап.lowercased() {
        case "created":    return .создан
        case "accepted":   return .принят
        case "in_transit": return .вПути
        case "arrived":    return доДвери ? .курьерВезёт : .вПунктеВыдачи
        case "delivered":  return .доставлен
        case "returning", "returned": return .возврат
        case "cancelled":  return .отменён
        case "problem":    return .проблема
        default:           return .неизвестно
        }
    }

    /**
     Статус по словам события (Казпочта и другие отдают только текст). Порядок проверок важен: «возврат» раньше
     «вручено» (бывает «возврат вручен отправителю»), «вручено» раньше «прибыло».
     */
    static func поТексту(_ текст: String) -> СтатусТрека {
        let t = текст.lowercased()
        func есть(_ слова: [String]) -> Bool { слова.contains { t.contains($0) } }
        if есть(["возврат", "return", "қайтар"]) { return .возврат }
        if есть(["вручен", "выдан", "получено адресат", "delivered", "табыст", "тапсырыл"]) { return .доставлен }
        if есть(["не удал", "задерж", "утер", "поврежд", "problem", "fail", "exception", "delay", "кідір"]) {
            return .проблема
        }
        if есть(["отмен", "cancel"]) { return .отменён }
        if есть(["курьер", "доставк", "out for delivery", "with courier"]) { return .курьерВезёт }
        if есть(["прибыл", "поступил", "в отделени", "пункт выдач", "постамат", "ожидает", "arrived", "ready for pickup",
                 "келді", "бөлімше"]) {
            return .вПунктеВыдачи
        }
        if есть(["прием", "приём", "принят", "accepted", "posted", "қабылд"]) { return .принят }
        if есть(["отправ", "транзит", "сортир", "покинул", "в пути", "transit", "dispatch", "departed", "жөнелт", "жолда"]) {
            return .вПути
        }
        if есть(["оформл", "создан", "registered", "created", "тіркел"]) { return .создан }
        return .неизвестно
    }

    /// Полная подпись — крупно в карточке.
    var текст: String { ТрекText.т("st_" + rawValue) }
    /// Короткая подпись — на пилюле.
    var коротко: String { ТрекText.т("sh_" + rawValue) }

    var символ: String {
        switch self {
        case .создан:        return "doc.text"
        case .принят:        return "tray.and.arrow.down.fill"
        case .вПути:         return "box.truck.fill"
        case .вПунктеВыдачи: return "mappin.and.ellipse"
        case .курьерВезёт:   return "location.fill"
        case .доставлен:     return "checkmark.seal.fill"
        case .возврат:       return "arrow.uturn.backward"
        case .проблема:      return "exclamationmark.triangle.fill"
        case .отменён:       return "xmark.circle.fill"
        case .неизвестно:    return "questionmark.circle"
        }
    }

    var вид: ВидСтатусаТрека {
        switch self {
        case .доставлен, .вПунктеВыдачи: return .хорошо
        case .вПути, .курьерВезёт, .принят: return .путь
        case .создан: return .ждём
        case .возврат, .проблема, .отменён: return .плохо
        case .неизвестно: return .тихо
        }
    }

    /// Шаг полосы «Принято · В пути · Рядом · Вручено» (1…4); у возврата, отмены и неизвестного полосы нет.
    var шаг: Int? {
        switch self {
        case .создан: return 0
        case .принят: return 1
        case .вПути: return 2
        case .вПунктеВыдачи, .курьерВезёт: return 3
        case .доставлен: return 4
        case .возврат, .проблема, .отменён, .неизвестно: return nil
        }
    }

    /// Дальше статус не сменится — опрос реже.
    var конечный: Bool { self == .доставлен || self == .возврат || self == .отменён }
}

// MARK: - Событие, срок, курьер

/// Одна строка ленты «История доставки».
struct СобытиеТрека: Codable, Hashable, Sendable {
    var когда: Date?
    var статус: СтатусТрека
    var текст: String
    var место: String

    init(когда: Date?, статус: СтатусТрека, текст: String, место: String = "") {
        self.когда = когда
        self.статус = статус
        self.текст = текст
        self.место = место
    }
}

/// Куда относится срок: вся доставка (перевозчик) или точка маршрута курьера Яндекса (yandex_eta_a / b / r).
enum ЦельСрокаТрека: String, Codable, Sendable {
    case доставка = "delivery"
    case кПродавцу = "pickup"
    case кПокупателю = "dropoff"
    case обратно = "return"
}

struct СрокТрека: Codable, Hashable, Sendable {
    var цель: ЦельСрокаТрека
    var когда: Date
    /// Конец окна («12–14 окт.»); nil — точное время.
    var до: Date?
}

/// Курьер: имя, машина и цвет, звонок (подменный номер сервера), код для курьера, где он сейчас.
struct КурьерТрека: Codable, Hashable, Sendable {
    var имя: String = ""
    var машина: String = ""
    var цветМашины: String = ""
    var номерМашины: String = ""
    /// Готовый номер от сервера (tel:); пусто и звонок = true — номер спрашивается по нажатию (clocal_courier_phone).
    var телефон: String = ""
    var добавочный: String = ""
    var звонок: Bool = false
    var код: String = ""
    /// Для чего код: "return" — забрать обратно; иначе — по роли (отдаёте / получаете).
    var кодДля: String = ""
    var попыток: Int = 0
    /// Код придёт в SMS (yandex_code_sms).
    var кодВСМС: Bool = false
    var широта: Double? = nil
    var долгота: Double? = nil

    var пусто: Bool {
        имя.isEmpty && машина.isEmpty && телефон.isEmpty && !звонок && код.isEmpty && !кодВСМС
    }

    /// «Hyundai Solaris · белый · 123ABC02» — то, что видно на улице.
    var описаниеМашины: String {
        var части: [String] = []
        if !машина.isEmpty { части.append(машина) }
        if !цветМашины.isEmpty { части.append(цветМашины) }
        if !номерМашины.isEmpty { части.append(номерМашины.слеваНаправо) }
        return части.joined(separator: " · ")
    }
}

/// Откуда запись: сервер kliko.kz, сделка (clocal, ship_car_*), сам перевозчик (публичный API), кэш.
enum ИсточникТрека: String, Codable, Sendable {
    case сервер = "server"
    case сделка = "deal"
    case перевозчик = "carrier"
}

// MARK: - Запись отслеживания

struct ДанныеТрека: Codable, Hashable, Sendable {
    var перевозчик: ПеревозчикТрека
    /// Имя от сервера («СДЭК», «Exline»); пусто — название перевозчика.
    var имяПеревозчика: String = ""
    var номер: String = ""
    var статус: СтатусТрека = .неизвестно
    /// Подпись от сервера или Яндекса; пусто — СтатусТрека.текст.
    var текстСтатуса: String = ""
    /// Сырой код перевозчика (yandex_status, код СДЭК) — для Live Activity и отладки.
    var кодПеревозчика: String = ""
    var сроки: [СрокТрека] = []
    var курьер: КурьерТрека? = nil
    /// Новые сверху.
    var события: [СобытиеТрека] = []
    var обновлено: Date = Date()
    /// Публичная страница или ссылка службы (https, хост из белого списка) — последний выход, лист Safari.
    var ссылка: String = ""
    /// Курьер в пути прямо сейчас — опрос каждые 30 с.
    var живой: Bool = false
    var источник: ИсточникТрека = .сделка
    /// "seller" / "buyer" — от роли зависят подписи сроков и кода.
    var роль: String = ""
    /// Подсказка сервера, через сколько секунд спрашивать снова (next_poll).
    var следующийОпрос: Double? = nil

    init(перевозчик: ПеревозчикТрека) {
        self.перевозчик = перевозчик
    }

    var название: String { имяПеревозчика.isEmpty ? перевозчик.название : имяПеревозчика }
    var подпись: String { текстСтатуса.isEmpty ? статус.текст : текстСтатуса }
    var продавец: Bool { роль == "seller" }

    /// Есть что показать, кроме «статус уточняется».
    var содержательно: Bool {
        статус != .неизвестно || !события.isEmpty || !(курьер?.пусто ?? true)
    }

    var адресСсылки: URL? {
        guard ссылка.hasPrefix("https://"), let адрес = URL(string: ссылка) else { return nil }
        return адрес
    }

    /// Ссылка для листа Safari: своя ссылка сделки, иначе публичная страница перевозчика по номеру.
    var запаснаяСтраница: URL? {
        адресСсылки ?? перевозчик.страница(номер: номер)
    }

    // MARK: Для плашки на экране блокировки (DealActivityAttributes.ContentState)

    /**
     phase Live Activity: search · to_seller · at_seller · to_buyer · at_buyer · delivered · returning. Только для курьера
     Яндекса — у перевозчика фаз нет (nil).
     */
    var фазаКурьера: String? {
        guard перевозчик == .yandex, !кодПеревозчика.isEmpty else { return nil }
        switch кодПеревозчика {
        case "new", "estimating", "ready_for_approval", "accepted", "performer_lookup", "performer_draft":
            return "search"
        case "performer_found": return "to_seller"
        case "pickup_arrived", "ready_for_pickup_confirmation": return "at_seller"
        case "pickuped": return "to_buyer"
        case "delivery_arrived", "ready_for_delivery_confirmation": return "at_buyer"
        case "pay_waiting", "delivered", "delivered_finish": return "delivered"
        case "returning", "return_arrived", "ready_for_return_confirmation", "returned", "returned_finish":
            return "returning"
        default: return nil
        }
    }

    /// Ближайший срок как unix-время для плашки (etaAt); нет — nil.
    var срокДляПлашки: Double? {
        let будущие = сроки.filter { $0.когда.timeIntervalSinceNow > -60 }
        return будущие.min(by: { $0.когда < $1.когда })?.когда.timeIntervalSince1970
    }

    /// Машина курьера для плашки: «белый Hyundai Solaris».
    var машинаДляПлашки: String? {
        guard let к = курьер else { return nil }
        let t = [к.цветМашины, к.машина].filter { !$0.isEmpty }.joined(separator: " ")
        return t.isEmpty ? nil : t
    }
}

// MARK: - Состояние экрана

/// Что знает служба о доставке сделки.
enum СостояниеТрека: Equatable {
    /// Ещё ни разу не спросили и в кэше пусто.
    case загрузка
    case данные(ДанныеТрека)
    /// Статусов нет ни у сервера, ни у перевозчика. запись — то, что известно (перевозчик, номер, ссылка).
    case нетДанных(ДанныеТрека?)
    /// Спросить не удалось и показать нечего.
    case ошибка(String)

    var запись: ДанныеТрека? {
        switch self {
        case .данные(let д): return д
        case .нетДанных(let д): return д
        case .загрузка, .ошибка: return nil
        }
    }
}

// MARK: - Определение перевозчика по ссылке или номеру (trkLinkFind сайта + форматы номеров)

struct НайденныйТрек: Equatable, Sendable {
    var перевозчик: ПеревозчикТрека
    var номер: String
    var ссылка: String
}

enum ОпределениеПеревозчика {
    /**
     Хосты служб. Первые десять — _TRK_HOSTS сайта (Яндекс Go и inDrive), дальше — перевозчики. Совпадение — сам хост или
     его поддомен (a === r || a.endsWith("." + r)), как у trkLinkFind.
     */
    static let хосты: [(хост: String, перевозчик: ПеревозчикТрека)] = [
        ("yandex.ru", .yandex), ("yandex.kz", .yandex), ("yandex.com", .yandex), ("yandex.by", .yandex),
        ("yandex.uz", .yandex), ("go.yandex", .yandex), ("go.yandex.ru", .yandex),
        ("indrive.com", .indrive), ("indriver.com", .indrive), ("indrive.kz", .indrive),
        ("cdek.ru", .cdek), ("cdek.kz", .cdek), ("cdek.shopping", .cdek),
        ("post.kz", .kazpost), ("kazpost.kz", .kazpost),
        ("dhl.com", .dhl), ("dhl.kz", .dhl),
        ("exline.kz", .exline),
        ("ups.com", .ups),
        ("fedex.com", .fedex)
    ]

    /// Перевозчик по хосту ссылки; чужой хост — nil.
    static func поХосту(_ хост: String) -> ПеревозчикТрека? {
        let h = хост.lowercased()
        for пара in хосты where h == пара.хост || h.hasSuffix("." + пара.хост) {
            return пара.перевозчик
        }
        return nil
    }

    /// Номер без пробелов и дефисов, заглавными.
    static func чистый(_ номер: String) -> String {
        номер.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /**
     Перевозчик по формату номера:
       · S10 ВПС «RR123456789KZ», «CC…KZ», «LP…CN» — Казпочта (международные отправления в Казахстане везёт она);
       · 10 цифр — СДЭК (номер заказа);
       · «1Z» + 16 знаков — UPS; «JJD…», «JVGL…» — DHL.
     Прочее — nil (FedEx и DHL Express по одним цифрам не отличить от СДЭК — только по ссылке).
     */
    static func поНомеру(_ номер: String) -> ПеревозчикТрека? {
        let н = чистый(номер)
        guard н.count >= 8, н.count <= 30 else { return nil }
        if совпадает(н, "^[A-Z]{2}[0-9]{9}[A-Z]{2}$") { return .kazpost }
        if совпадает(н, "^[0-9]{10}$") { return .cdek }
        if совпадает(н, "^1Z[0-9A-Z]{16}$") { return .ups }
        if совпадает(н, "^(JJD|JVGL)[0-9A-Z]{6,}$") { return .dhl }
        return nil
    }

    private static func совпадает(_ s: String, _ шаблон: String) -> Bool {
        s.range(of: шаблон, options: .regularExpression) != nil
    }

    /// Все ссылки http(s) в тексте. Текст длиннее 2000 символов не разбирается (как у сайта).
    static func ссылки(_ текст: String) -> [String] {
        guard !текст.isEmpty, текст.count <= 2000,
              let выражение = try? NSRegularExpression(pattern: "https?://[^\\s\"'<>]+", options: [.caseInsensitive]) else {
            return []
        }
        let диапазон = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        return выражение.matches(in: текст, options: [], range: диапазон).compactMap { совпадение in
            Range(совпадение.range, in: текст).map { String(текст[$0]) }
        }
    }

    /// trkLinkFind: первая ссылка известной службы; нет — пусто.
    static func найтиСсылку(_ текст: String) -> String {
        for ссылка in ссылки(текст) {
            guard let хост = URL(string: ссылка)?.host else { continue }
            if поХосту(хост) != nil { return ссылка }
        }
        return ""
    }

    /// Номер из ссылки перевозчика: параметр запроса (order_id, tracking-id, trknbr…) или часть пути.
    static func номерИзСсылки(_ адрес: URL) -> String {
        let имена: Set<String> = ["order_id", "orderid", "track", "tracking", "trackingnumber", "tracking-id",
                                  "tracknum", "trknbr", "barcode", "number", "q", "id"]
        if let части = URLComponents(url: адрес, resolvingAgainstBaseURL: false)?.queryItems {
            for п in части where имена.contains(п.name.lowercased()) {
                let з = чистый(п.value ?? "")
                if поНомеру(з) != nil { return з }
            }
        }
        for кусок in адрес.pathComponents.reversed() {
            let з = чистый(кусок)
            if поНомеру(з) != nil { return з }
        }
        return ""
    }

    /**
     Разбор того, что человек вставил в поле «Трек-номер или ссылка»: сначала ссылка известной службы (с номером из
     неё, если он там есть), потом номер известного формата среди слов. Ничего — nil.
     */
    static func изТекста(_ текст: String) -> НайденныйТрек? {
        let t = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let ссылка = найтиСсылку(t)
        if !ссылка.isEmpty, let адрес = URL(string: ссылка), let хост = адрес.host, let п = поХосту(хост) {
            return НайденныйТрек(перевозчик: п, номер: номерИзСсылки(адрес), ссылка: ссылка)
        }
        let слова = t.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        for слово in слова {
            if let п = поНомеру(слово) { return НайденныйТрек(перевозчик: п, номер: чистый(слово), ссылка: "") }
        }
        /* Номер, набранный с пробелами: «RR 123 456 789 KZ». */
        if let п = поНомеру(t) { return НайденныйТрек(перевозчик: п, номер: чистый(t), ссылка: "") }
        return nil
    }
}
