import Foundation
import CoreLocation
import WebKit

/// Геопозиция для страницы — через CoreLocation, а не через окно WebKit.
///
/// ЗАЧЕМ. WKWebView спрашивает «kliko.kz хочет использовать вашу геопозицию» на каждом новом
/// документе и решения между страницами не помнит. Витрина, кабинет, карта, доставка — это разные
/// документы, и человек, однажды разрешивший гео, получал тот же вопрос снова в другом месте.
/// Здесь координаты отдаёт CoreLocation: система спрашивает ОДИН раз («При использовании
/// приложения») и помнит решение для всего приложения навсегда. Окно WebKit не появляется вовсе:
/// navigator.geolocation внутри приложения подменён мостом (WebContainer.Coordinator.liveBridgeJS).
///
/// Протокол. Страница шлёт {op:'get', id, high, maxAge, timeout} | {op:'watch', id, high} |
/// {op:'clear', id}. Ответ — вызов window.__klikoGeo(id, {ok:true, lat, lon, acc, ts, …}) или
/// {ok:false, code, message}; коды как у PositionError: 1 — запрещено, 2 — недоступно,
/// 3 — время вышло.
final class GeoBridge: NSObject, CLLocationManagerDelegate {
    weak var webView: WKWebView?
    private let менеджер = CLLocationManager()
    /// Разовые запросы (getCurrentPosition), которые ждут замера.
    private var разовые = Set<Int>()
    /// Таймеры «время вышло» разовых запросов.
    private var таймеры: [Int: DispatchWorkItem] = [:]
    /// Слежки (watchPosition).
    private var слежки = Set<Int>()
    /// Что сделать, когда человек ответит на системное окно разрешения.
    private var послеРазрешения: [(Bool) -> Void] = []

    override init() {
        super.init()
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func handle(_ body: [String: Any]) {
        let op = body["op"] as? String ?? ""
        let id = (body["id"] as? NSNumber)?.intValue ?? 0
        guard id > 0 else { return }
        if (body["high"] as? Bool) == true { менеджер.desiredAccuracy = kCLLocationAccuracyBest }
        switch op {
        case "get":
            let maxAge = (body["maxAge"] as? NSNumber)?.doubleValue ?? 0
            let timeout = (body["timeout"] as? NSNumber)?.doubleValue ?? 0
            сРазрешением(id) { [weak self] in self?.разовый(id, maxAge: maxAge, timeout: timeout) }
        case "watch":
            сРазрешением(id) { [weak self] in
                guard let self = self else { return }
                self.слежки.insert(id)
                self.менеджер.startUpdatingLocation()
            }
        case "clear":
            слежки.remove(id)
            if слежки.isEmpty { менеджер.stopUpdatingLocation() }
        default:
            break
        }
    }

    /// Выполнить действие, когда разрешение есть; спросить систему, если ещё не спрашивали.
    /// Спрашивает система — один раз на всё приложение, дальше она помнит ответ сама.
    private func сРазрешением(_ id: Int, _ действие: @escaping () -> Void) {
        switch менеджер.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            действие()
        case .notDetermined:
            послеРазрешения.append { [weak self] разрешено in
                if разрешено { действие() } else { self?.ответить(id, ошибка: 1, "denied") }
            }
            менеджер.requestWhenInUseAuthorization()
        default:
            // .denied и .restricted — сюда же попадает геолокация, выключенная на всём устройстве.
            // Какой из случаев, страница узнаёт у KlikoPerms и объясняет человеку.
            ответить(id, ошибка: 1, "denied")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let статус = manager.authorizationStatus
        // Вызов приходит и сразу при создании менеджера — ждущих тогда нет, и решать нечего.
        guard статус != .notDetermined, !послеРазрешения.isEmpty else { return }
        let разрешено = (статус == .authorizedWhenInUse || статус == .authorizedAlways)
        let ждут = послеРазрешения
        послеРазрешения = []
        ждут.forEach { $0(разрешено) }
    }

    private func разовый(_ id: Int, maxAge: Double, timeout: Double) {
        // Свежий последний замер отдаём сразу — то же разрешает maximumAge у браузера.
        if maxAge > 0, let последний = менеджер.location,
           -последний.timestamp.timeIntervalSinceNow * 1000 <= maxAge {
            ответить(id, место: последний)
            return
        }
        разовые.insert(id)
        if timeout > 0 {
            // Время считаем от начала замера, а не от вопроса о разрешении: пока человек читает
            // системное окно, таймер не идёт — иначе первый же запрос кончался бы «время вышло».
            let таймер = DispatchWorkItem { [weak self] in
                guard let self = self, self.разовые.contains(id) else { return }
                self.разовые.remove(id)
                self.таймеры[id] = nil
                self.ответить(id, ошибка: 3, "timeout")
            }
            таймеры[id] = таймер
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout / 1000, execute: таймер)
        }
        // Пока идёт слежка, замеры и так приходят — разовый получит ближайший.
        if слежки.isEmpty { менеджер.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let место = locations.last else { return }
        let ждут = разовые
        разовые = []
        for id in ждут {
            таймеры.removeValue(forKey: id)?.cancel()
            ответить(id, место: место)
        }
        for id in слежки { ответить(id, место: место) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let запрещено = (error as? CLError)?.code == .denied
        // Разовый запрос система завершает этой ошибкой — ответить обязаны, иначе он повиснет.
        let ждут = разовые
        разовые = []
        for id in ждут {
            таймеры.removeValue(forKey: id)?.cancel()
            ответить(id, ошибка: запрещено ? 1 : 2, запрещено ? "denied" : "unavailable")
        }
        // Слежку «пока не знаю, где вы» не обрываем: следующий замер придёт сам.
        if запрещено {
            for id in слежки { ответить(id, ошибка: 1, "denied") }
            слежки.removeAll()
            менеджер.stopUpdatingLocation()
        }
    }

    private func ответить(_ id: Int, место: CLLocation) {
        var данные: [String: Any] = [
            "ok": true,
            "lat": место.coordinate.latitude,
            "lon": место.coordinate.longitude,
            "acc": max(0, место.horizontalAccuracy),
            "ts": место.timestamp.timeIntervalSince1970 * 1000
        ]
        if место.verticalAccuracy >= 0 { данные["alt"] = место.altitude; данные["altAcc"] = место.verticalAccuracy }
        if место.course >= 0 { данные["heading"] = место.course }
        if место.speed >= 0 { данные["speed"] = место.speed }
        послать(id, данные)
    }

    private func ответить(_ id: Int, ошибка код: Int, _ текст: String) {
        послать(id, ["ok": false, "code": код, "message": текст])
    }

    private func послать(_ id: Int, _ данные: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(данные),
              let json = try? JSONSerialization.data(withJSONObject: данные),
              let строка = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.__klikoGeo && window.__klikoGeo(\(id), \(строка))")
        }
    }
}
