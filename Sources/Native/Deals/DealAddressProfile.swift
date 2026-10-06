import Foundation
import CoreLocation

/**
 АДРЕС ПОЛУЧЕНИЯ ИЗ ПРОФИЛЯ ДЛЯ ЛИСТА «КУДА ДОСТАВИТЬ» (владелец, 06.10.2026: «нижние поля должны заполняться
 автоматически заранее — из адреса в основных настройках профиля»).

 Адрес и точка — из настроек «Регион и адрес» (CAB_PREF_GEO: city, address, lat, lon). Квартиру, подъезд, этаж и
 домофон сайт в CAB_PREF_GEO не отдаёт: они уходят серверу полем door в save_pref_geo (если сервер его примет —
 придут обратно в CAB_PREF_GEO.door) и всегда хранятся на телефоне (ДверьПрофиляТелефона), стираются при выходе.
 */
extension ДверьСделки {
    /// Есть хоть что-то для курьера, кроме комментария: «у подъезда» или квартира / подъезд / этаж / домофон.
    var естьДетали: Bool {
        уПодъезда || !квартира.isEmpty || !подъезд.isEmpty || !этаж.isEmpty || !домофон.isEmpty
    }

    /// «кв. 12 · подъезд 3 · этаж 5 · домофон 12К».
    var сводка: String {
        let т = ТочкаText.т
        var части: [String] = []
        if !квартира.isEmpty { части.append(т("s_flat") + " " + квартира) }
        if !подъезд.isEmpty { части.append(т("s_porch") + " " + подъезд) }
        if !этаж.isEmpty { части.append(т("s_floor") + " " + этаж) }
        if !домофон.isEmpty { части.append(т("s_code") + " " + домофон) }
        return части.joined(separator: " · ")
    }

    /// Для профиля и телефона: все поля строками, out — да/нет.
    var значениеПрофиля: [String: Any] {
        ["out": уПодъезда, "flat": квартира, "porch": подъезд, "floor": этаж, "code": домофон, "note": комментарий]
    }

    /// CAB_PREF_GEO.door, если сервер его хранит.
    static func изПрофиля(_ j: ДанныеJSON?) -> ДверьСделки? {
        guard let j, !j.пары.isEmpty else { return nil }
        var д = ДверьСделки()
        д.уПодъезда = j["out"]?.да ?? false
        д.квартира = (j["flat"]?.текст ?? "").trimmingCharacters(in: .whitespaces)
        д.подъезд = (j["porch"]?.текст ?? "").trimmingCharacters(in: .whitespaces)
        д.этаж = (j["floor"]?.текст ?? "").trimmingCharacters(in: .whitespaces)
        д.домофон = (j["code"]?.текст ?? "").trimmingCharacters(in: .whitespaces)
        д.комментарий = (j["note"]?.текст ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return д.естьДетали || !д.комментарий.isEmpty ? д : nil
    }
}

/// Детали двери адреса получения на телефоне.
enum ДверьПрофиляТелефона {
    private static let ключ = "kliko.recvDoor.v1"

    static func загрузить() -> ДверьСделки? {
        guard let д = UserDefaults.standard.dictionary(forKey: ключ), let дверь = ДверьСделки(д) else { return nil }
        return дверь.естьДетали || !дверь.комментарий.isEmpty ? дверь : nil
    }

    static func запомнить(_ д: ДверьСделки) {
        if д.естьДетали || !д.комментарий.isEmpty {
            UserDefaults.standard.set(д.значениеПрофиля, forKey: ключ)
        } else {
            UserDefaults.standard.removeObject(forKey: ключ)
        }
    }

    static func стереть() {
        UserDefaults.standard.removeObject(forKey: ключ)
    }
}

@MainActor
enum АдресПолученияПрофиля {
    /// Детали двери: из профиля с сервера, иначе с телефона.
    static func дверь(_ п: ПрофильКабинета?) -> ДверьСделки? {
        if let д = п?.дверьАдреса { return д }
        return ДверьПрофиляТелефона.загрузить()
    }

    /// «Астана, проспект Абая, 30» — город профиля и улица; улицы нет — nil.
    static func текст(_ п: ПрофильКабинета?) -> String? {
        guard let п else { return nil }
        let улица = п.адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !улица.isEmpty else { return nil }
        let город = ГеоДанные.городБезАдминистрации(п.город)
        if город.isEmpty || улица.lowercased().contains(город.lowercased()) { return улица }
        return город + ", " + улица
    }

    static func точка(_ п: ПрофильКабинета?) -> CLLocationCoordinate2D? {
        guard let ш = п?.широта, let д = п?.долгота, ш.isFinite, д.isFinite, ш != 0 || д != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: ш, longitude: д)
    }

    /**
     «Сохранить в профиле»: дверь — на телефон сразу; адрес, точка и дверь — серверу тем же save_pref_geo, что форма
     «Регион и адрес» (регион, район, город и «адрес получения» — из профиля). Город в начале строки отрезается: в
     профиле он своим полем. Профиля ещё нет (кабинет не загружен) — только телефон.
     */
    static func сохранить(адрес: String, точка: CLLocationCoordinate2D?, дверь: ДверьСделки) {
        ДверьПрофиляТелефона.запомнить(дверь)
        guard let п = НастройкиМодель.shared.профиль else { return }
        let город = п.город.trimmingCharacters(in: .whitespacesAndNewlines)
        var улица = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        let чистыйГород = ГеоДанные.городБезАдминистрации(город)
        for имя in [город, чистыйГород] where !имя.isEmpty {
            let приставка = имя.lowercased() + ","
            if улица.lowercased().hasPrefix(приставка) {
                улица = String(улица.dropFirst(приставка.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        улица = String(улица.prefix(300))
        var гео: [String: Any] = ["region": п.регион, "district": п.район, "city": город, "address": улица,
                                  "recv": true, "door": дверь.значениеПрофиля]
        if let т = точка {
            гео["lat"] = NSNumber(value: т.latitude)
            гео["lon"] = NSNumber(value: т.longitude)
        } else {
            гео["lat"] = NSNull()
            гео["lon"] = NSNull()
        }
        let тело = гео
        let итогУлица = улица
        Task { @MainActor in
            guard let j = try? await НастройкиAPI.отправить("cabinet.php?action=save_pref_geo", тело),
                  МоиОбъявленияAPI.да(j["ok"]) else { return }
            НастройкиМодель.shared.изменить { п in
                п.адрес = итогУлица
                п.адресПолучения = true
                п.широта = точка?.latitude
                п.долгота = точка?.longitude
                п.дверьАдреса = дверь.естьДетали || !дверь.комментарий.isEmpty ? дверь : nil
            }
        }
    }
}
