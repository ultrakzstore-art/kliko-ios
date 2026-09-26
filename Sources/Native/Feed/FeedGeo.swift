import Foundation
import CoreLocation
import SwiftUI
import UIKit

/**
 ГЕОПОЗИЦИЯ ВИТРИНЫ: РАССТОЯНИЕ НА КАРТОЧКАХ, «РЯДОМ С ВАМИ» И ВРЕМЯ В ПУТИ — как у сайта (js/geo.min.js и
 js/marketplace.min.js, 26.09.2026).

 Когда сайт знает, где человек:
   · при загрузке ленты — mkGeoFetch → ulxGeo без просьбы: точка из памяти не старше 30 минут, иначе замер, но только
     если разрешение уже дано (permissions.query == "granted"); не дано — не спрашивает вовсе («нет-жеста»);
   · по нажатию «Рядом с вами» (mkVitNear → mkNearToggle) — ulxGetPosition с «поЖеланию»: тут спрашивает систему; запрещено
     — окно ulxPermHint «Доступ к геопозиции запрещён» с «Открыть настройки» и «Понятно».
 Приложение делает то же: тихо() при показе ленты, попросить() — по нажатию. Системное окно «при использовании» у
 приложения одно на всё (его же спрашивает GeoBridge для страниц сайта), NSLocationWhenInUseUsageDescription уже есть.

 Что сайт показывает с точкой:
   · карточка витрины (mkVitCardHTML): до 5 км — вместо города булавка и расстояние яркой зеленью, жирно (.mk-vc-geo.near),
     дальше — город, как без точки; подпись mkDistLabel: меньше километра — «N м», до 10 км — «2.3 км», дальше — «12 км»;
   · время в пути (mkEtaFill): api/eta.php?ids=<до 12 номеров>&lat=&lon= для карточек на экране, пауза 300 мс; ответ
     {ok, e:{id:{t,k,c}}, more:[…]} — «· 12 мин» зеленью у места карточки (k:"far" — серым), more — спросить ещё раз;
     reason:"off" — сервер это выключил, больше не спрашиваем;
   · «Рядом с вами» (карусель над лентой): «N в радиусе 2 км» среди загруженных; нажатие — лента по расстоянию
     (mkSt.near: ТОП и прочие по расстоянию, золотым ритмом; в услугах — без золота), второе нажатие — обратно.
 */
struct ТочкаЛенты: Equatable, Codable, Sendable {
    let широта: Double
    let долгота: Double
    /// Когда замерена (unix, секунды) — ts у ulx_user_geo сайта.
    let когда: Double
}

@MainActor
final class ГеоЛенты: ObservableObject {
    static let shared = ГеоЛенты()

    /// Точка человека (mkSt.userLat/userLon сайта); nil — не знаем. «Рядом со мной» включает лента (FeedModel.рядом).
    @Published private(set) var точка: ТочкаЛенты?
    /// Идёт замер по нажатию — кружок «Рядом с вами» ждёт.
    @Published private(set) var ищем = false

    /// Почему точки нет после просьбы.
    enum Отказ: Equatable {
        /// Kliko запрещено — окно с «Открыть настройки».
        case запрещено
        /// Службы геолокации выключены на всём устройстве — окно с путём в Настройках.
        case выключено
        /// Разрешено, но замер не удался — «Не удалось определить местоположение».
        case ошибка
    }

    private let замер = ЗамерГеоЛенты()
    /// Тихий замер уже был за этот запуск — _mkGeoFetched сайта.
    private var тихийБыл = false

    private static let ключ = "kliko.feed.userGeo"

    private init() {
        точка = замер.разрешено ? Self.изПамяти(возраст: 1800) : nil
    }

    /// mkGeoFetch при загрузке ленты: память не старше 30 минут, иначе замер. Владелец: расстояние — только с
    /// разрешением на геопозицию; разрешение забрали в Настройках — точки нет, и память не показываем.
    func тихо() {
        guard замер.разрешено else {
            if точка != nil { точка = nil }
            return
        }
        guard !тихийБыл else { return }
        тихийБыл = true
        if let память = Self.изПамяти(возраст: 1800) {
            точка = память
            return
        }
        замер.узнать { [weak self] координата in
            Task { @MainActor in
                guard let self, let координата else { return }
                self.принять(координата)
            }
        }
    }

    /**
     mkNearToggle, включение: спросить точку (с системным окном, если не спрашивали) — ulxGetPosition с «поЖеланию».
     `готово` — nil, если точка есть, иначе причина: её покажет окно ulxPermHint или строка «Не удалось определить
     местоположение».
     */
    func найтиТочку(_ готово: @escaping @MainActor (Отказ?) -> Void) {
        guard !ищем else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            готово(.выключено)
            return
        }
        ищем = true
        замер.узнать(просить: true) { [weak self] координата in
            Task { @MainActor in
                guard let self else { return }
                self.ищем = false
                if let координата {
                    self.принять(координата)
                    готово(nil)
                } else {
                    готово(self.замер.запрещено ? .запрещено : .ошибка)
                }
            }
        }
    }

    private func принять(_ к: CLLocationCoordinate2D) {
        let новая = ТочкаЛенты(широта: к.latitude, долгота: к.longitude, когда: Date().timeIntervalSince1970)
        точка = новая
        if let данные = try? JSONEncoder().encode(новая) { UserDefaults.standard.set(данные, forKey: Self.ключ) }
    }

    /// ulxGeoCached: точка из памяти не старше `возраст` секунд.
    private static func изПамяти(возраст: Double) -> ТочкаЛенты? {
        guard let данные = UserDefaults.standard.data(forKey: ключ),
              let т = try? JSONDecoder().decode(ТочкаЛенты.self, from: данные) else { return nil }
        let сейчас = Date().timeIntervalSince1970
        guard т.когда > 0, сейчас - т.когда < возраст, т.широта != 0, т.долгота != 0 else { return nil }
        return т
    }

    // MARK: - Расстояние (mkGeoDistKm, mkDistLabel)

    /// mkGeoDistKm сайта: гаверсинус, 12742 — диаметр Земли в километрах.
    nonisolated static func км(_ ш1: Double, _ д1: Double, _ ш2: Double, _ д2: Double) -> Double {
        let r = (ш2 - ш1) * Double.pi / 180
        let i = (д2 - д1) * Double.pi / 180
        let a = sin(r / 2) * sin(r / 2) + cos(ш1 * Double.pi / 180) * cos(ш2 * Double.pi / 180) * sin(i / 2) * sin(i / 2)
        return 12742 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// mkDistLabel сайта: меньше километра — «350 м», до 10 км — одна цифра после точки («2.3 км»), дальше — целые.
    nonisolated static func подпись(км: Double) -> String {
        if км < 1 {
            return String(Int((км * 1000).rounded())) + " " + ВитринаТекст.т("unit_m")
        }
        let число = км < 10 ? String(format: "%.1f", км) : String(format: "%.0f", км)
        return число + " " + ВитринаТекст.т("unit_km")
    }

    /// Расстояние до объявления в километрах; nil — точки человека или объявления нет.
    func км(до товар: Listing) -> Double? {
        guard let т = точка, let ш = товар.поляВида.широта, let д = товар.поляВида.долгота else { return nil }
        return Self.км(т.широта, т.долгота, ш, д)
    }

    /// «Рядом с вами»: сколько загруженных в радиусе 2 км (mkVitPicks); nil — точки нет.
    func вРадиусеДвух(_ товары: [Listing]) -> Int? {
        guard точка != nil else { return nil }
        var видели = Set<String>()
        var n = 0
        for товар in товары where !видели.contains(товар.id) {
            видели.insert(товар.id)
            if let км = км(до: товар), км <= 2 { n += 1 }
        }
        return n
    }
}

/**
 Один замер CoreLocation. Обычный класс, как ГеопозицияКарты и GeoBridge: CLLocationManager зовёт делегата на той нити,
 где создан, — ГеоЛенты создаёт его на главной.
 */
final class ЗамерГеоЛенты: NSObject, CLLocationManagerDelegate {
    private let менеджер = CLLocationManager()
    private var ждут: [(CLLocationCoordinate2D?) -> Void] = []
    private var просили = false

    override init() {
        super.init()
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Разрешение уже дано — тихий замер можно.
    var разрешено: Bool {
        switch менеджер.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    /// Запрещено Kliko (или ограничено) — окно «Открыть настройки».
    var запрещено: Bool {
        switch менеджер.authorizationStatus {
        case .denied, .restricted: return true
        default: return false
        }
    }

    /// Одна точка. `просить` — спросить систему, если ещё не спрашивали (только по нажатию человека).
    func узнать(просить: Bool = false, _ готово: @escaping (CLLocationCoordinate2D?) -> Void) {
        switch менеджер.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            ждут.append(готово)
            менеджер.requestLocation()
        case .notDetermined:
            guard просить else {
                готово(nil)
                return
            }
            ждут.append(готово)
            просили = true
            менеджер.requestWhenInUseAuthorization()
        default:
            готово(nil)
        }
    }

    private func отдать(_ координата: CLLocationCoordinate2D?) {
        let все = ждут
        ждут = []
        for готово in все { готово(координата) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        /* Вызов приходит и сразу при создании менеджера — тогда никто не ждёт. */
        guard !ждут.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            отдать(nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        отдать(locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        отдать(nil)
    }
}

// MARK: - Время в пути (mkEtaFill, api/eta.php)

/// «· 12 мин» у места карточки — ответ api/eta.php: t — текст, k — "far" (серым), c — пояснение.
struct ОценкаПути: Equatable, Sendable {
    let текст: String
    let далеко: Bool
}

@MainActor
final class ОценкиПути: ObservableObject {
    static let shared = ОценкиПути()

    /// Ответ по номеру; значение nil — спрашивали, оценки нет (как _mkEta[e] = null у сайта).
    @Published private(set) var оценки: [String: ОценкаПути?] = [:]

    private var спрошены = Set<String>()
    private var ждут: [String] = []
    private var ждутМножество = Set<String>()
    private var пауза: Task<Void, Never>?
    /// reason:"off" — сервер выключил оценки, до следующего запуска не спрашиваем (_mkEtaOff).
    private var выключено = false

    private init() {}

    /// Карточка на экране — её номер в очередь; через 300 мс уходят до двенадцати ещё не спрошенных (mkEtaFill).
    func нужна(_ id: String) {
        guard !выключено, !id.isEmpty, оценки[id] == nil, !спрошены.contains(id), !ждутМножество.contains(id),
              ГеоЛенты.shared.точка != nil else { return }
        ждут.append(id)
        ждутМножество.insert(id)
        запланировать()
    }

    private func запланировать() {
        пауза?.cancel()
        пауза = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.спросить()
        }
    }

    private func спросить() async {
        guard !выключено, let т = ГеоЛенты.shared.точка else { return }
        let номера = Array(ждут.prefix(12))
        ждут.removeFirst(номера.count)
        for н in номера { ждутМножество.remove(н) }
        guard !номера.isEmpty else { return }
        for н in номера { спрошены.insert(н) }
        var ч = URLComponents(url: Config.apiBase.appendingPathComponent("api/eta.php"), resolvingAgainstBaseURL: false)
        ч?.queryItems = [URLQueryItem(name: "ids", value: номера.joined(separator: ",")),
                         URLQueryItem(name: "lat", value: String(format: "%.5f", т.широта)),
                         URLQueryItem(name: "lon", value: String(format: "%.5f", т.долгота))]
        guard let адрес = ч?.url else { return }
        var запрос = URLRequest(url: адрес)
        запрос.httpShouldHandleCookies = false
        запрос.timeoutInterval = 20
        for (имя, значение) in await SiteSession.куки() { запрос.setValue(значение, forHTTPHeaderField: имя) }
        let ответ = try? await URLSession.shared.data(for: запрос)
        guard let данные = ответ?.0,
              let поля = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            /* Сеть подвела — как .catch сайта: номера остаются «спрошенными» до следующего запуска. */
            if !ждут.isEmpty { запланировать() }
            return
        }
        guard (поля["ok"] as? Bool) == true || (поля["ok"] as? NSNumber)?.intValue == 1 else {
            if (поля["reason"] as? String) == "off" { выключено = true }
            return
        }
        let ещё = Set((поля["more"] as? [Any] ?? []).map { "\($0)" })
        let ответы = поля["e"] as? [String: Any] ?? [:]
        var новые = оценки
        for н in номера {
            if ещё.contains(н) {
                спрошены.remove(н)
                if !ждутМножество.contains(н) {
                    ждут.append(н)
                    ждутМножество.insert(н)
                }
                continue
            }
            if let о = ответы[н] as? [String: Any], let текст = о["t"] as? String, !текст.isEmpty {
                новые[н] = .some(ОценкаПути(текст: текст, далеко: (о["k"] as? String) == "far"))
            } else {
                новые[н] = .some(nil)
            }
        }
        оценки = новые
        if !ждут.isEmpty { запланировать() }
    }

    /// Оценка для карточки; nil — нет.
    func оценка(_ id: String) -> ОценкаПути? {
        guard let есть = оценки[id] else { return nil }
        return есть
    }
}

// MARK: - Карточка: место с расстоянием

extension Listing {
    /// Место карточки витрины (mkVitCardHTML): до 5 км от человека — расстояние («350 м», «2.3 км») и признак «рядом»;
    /// дальше или без точки — город, без города — дата. `км` — расстояние, если известно.
    func местоСРасстоянием(км: Double?) -> (текст: String, рядом: Bool) {
        if let км, км >= 0, км <= 5 {
            return (ГеоЛенты.подпись(км: км), true)
        }
        return (местоЛенты, false)
    }
}
