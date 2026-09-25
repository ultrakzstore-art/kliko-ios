import Combine
import CoreLocation
import Foundation
import MapKit

/**
 КАРТА ОБЪЯВЛЕНИЙ — СОСТОЯНИЕ (этап 39, владелец 25.09.2026: «почти 100% похоже на сайт, только нативное SwiftUI»).

 Как карта сайта (mkMapOpen и _mkMapOnMove, _mkMapRender, _mkMapListUpdate, mkCityZoom в js/marketplace.min.js):
   · издалека (зум не больше 12 — MK_APPROX_MAXZOOM) на карте — пузыри городов с числом объявлений, а в списке под
     картой — города в кадре по убыванию числа, не больше 200; вверху — сколько всего («1 234 предложения»);
   · ближе — ценники объявлений в видимой области, а в списке — они же: три ТОПа первыми, дальше по расстоянию от
     центра карты, не больше 120, вверху — «N в этой области»;
   · пузырь города приближает карту к нему на два шага за порог (MK_APPROX_MAXZOOM + 2) и показывает в списке объявления
     этого города (per=60) — «N · Город», пока карту снова не отдалят.
 Ценники близко друг к другу собираются в кружок с числом — как L.markerClusterGroup сайта (maxClusterRadius: 48);
 нажатие на кружок приближает карту.

 🔴 ЗАПРОСЫ — НЕ ЧАЩЕ, ЧЕМ НАДО. Ценники просим только когда карта остановилась (onMapCameraChange .onEnd) и простояла
 0,4 с (у сайта 250 мс после moveend — владелец просил не меньше 400): пока человек водит пальцем, запросов нет. Новый
 запрос отменяет прежний (Task.cancel обрывает URLSession), а ответ, пришедший после более нового запроса, выбрасывается
 по номеру. Повторов сами не делаем — только кнопка «Повторить».

 Ничего не хранится: всё в памяти экрана, как у сайта (_mkSrvCities, _mkSrvPins, _mkCityList — переменные страницы).
 Поэтому и при выходе стирать нечего.
 */

// MARK: - Геометрия

/**
 Зум сайта и область MapKit. У Leaflet сайта — зум (setView(…, 5), MK_APPROX_MAXZOOM = 12, maxZoom 14 у fitBounds), у
 MapKit зума нет, есть видимая область. Переводим тем же счётом, что тайлы OpenStreetMap сайта: на зуме z вся долгота
 мира — 256·2^z точек, значит зум = log2(360 · ширина / (256 · охват долготы)). На холсте телефона (~350 pt) порог 12 —
 это ~0,12° по долготе: ближе — ценники, дальше — пузыри.
 */
enum ГеометрияКарты {
    /// MK_APPROX_MAXZOOM сайта: дальше этого — пузыри городов, ближе — ценники.
    static let порогЗума: Double = 12
    /// Глубже этого нажатие на кружок ценников не приближает — тайлы сайта кончаются на 19.
    static let наибольшийЗум: Double = 18
    /// Холст ещё не измерен — считаем по холсту телефона.
    static let обычныйРазмер = CGSize(width: 350, height: 350)
    /// Кружок собирает ценники в этом радиусе, pt — maxClusterRadius: 48 сайта.
    static let радиусКружка: CGFloat = 48
    /// Стартовый вид сайта — setView([48.02, 66.92], 5): Казахстан.
    static let всяСтрана = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.02, longitude: 66.92),
                                               span: MKCoordinateSpan(latitudeDelta: 13, longitudeDelta: 16))

    /// Зум сайта для этой области на холсте такой ширины.
    static func зум(_ видимая: MKCoordinateRegion, ширина: CGFloat) -> Double {
        let охват = видимая.span.longitudeDelta
        guard охват > 0, охват.isFinite else { return 0 }
        let точек = Double(ширина > 0 ? ширина : обычныйРазмер.width)
        return log2(360 * точек / (256 * охват))
    }

    /// Область вокруг точки на таком зуме — setView сайта. Метров на точку на зуме z: 156 543 · cos(широты) / 2^z.
    static func область(центр: CLLocationCoordinate2D, зум: Double, размер: CGSize) -> MKCoordinateRegion {
        let ширина = Double(размер.width > 0 ? размер.width : обычныйРазмер.width)
        let высота = Double(размер.height > 0 ? размер.height : обычныйРазмер.height)
        let косинус = max(0.01, cos(центр.latitude * Double.pi / 180))
        let метровНаТочку = 156_543.03392 * косинус / pow(2, зум)
        return MKCoordinateRegion(center: центр, latitudinalMeters: метровНаТочку * высота,
                                  longitudinalMeters: метровНаТочку * ширина)
    }

    /// Точка в области (n.contains у Leaflet). Через 180-й меридиан Казахстан не переходит — простого сравнения хватает.
    static func внутри(_ широта: Double, _ долгота: Double, _ о: MKCoordinateRegion) -> Bool {
        abs(широта - о.center.latitude) <= о.span.latitudeDelta / 2
            && abs(долгота - о.center.longitude) <= о.span.longitudeDelta / 2
    }

    /// Края области — getNorth/getSouth/getEast/getWest сайта.
    static func края(_ о: MKCoordinateRegion) -> (север: Double, юг: Double, восток: Double, запад: Double) {
        let север = min(90, о.center.latitude + о.span.latitudeDelta / 2)
        let юг = max(-90, о.center.latitude - о.span.latitudeDelta / 2)
        let восток = min(180, о.center.longitude + о.span.longitudeDelta / 2)
        let запад = max(-180, о.center.longitude - о.span.longitudeDelta / 2)
        return (север: север, юг: юг, восток: восток, запад: запад)
    }

    /// Расстояние по большому кругу, км — mkGeoDistKm сайта.
    static func км(_ широта1: Double, _ долгота1: Double, _ широта2: Double, _ долгота2: Double) -> Double {
        let радиан = Double.pi / 180
        let пш = sin((широта2 - широта1) * радиан / 2)
        let пд = sin((долгота2 - долгота1) * радиан / 2)
        let произведение = cos(широта1 * радиан) * cos(широта2 * радиан)
        let а = min(1, max(0, пш * пш + произведение * пд * пд))
        return 6371 * 2 * atan2(sqrt(а), sqrt(1 - а))
    }

    private struct Ячейка: Hashable {
        let x: Int
        let y: Int
    }

    /**
     Ценники — в кружки: сетка ячеек по радиусу кружка в точках холста, всё, что попало в одну ячейку, — один кружок в
     средней точке; один ценник — сам ценник. Сетка привязана к нулевому меридиану, а не к краю экрана: сдвинули карту —
     кружки не перескакивают. Берём с запасом в полэкрана по краям: ценники у края видны, пока едут новые.
     */
    static func собрать(_ пины: [КартаAPI.Пин], область о: MKCoordinateRegion, размер: CGSize) -> [ЗнакКарты] {
        let ширина = Double(размер.width > 0 ? размер.width : обычныйРазмер.width)
        let высота = Double(размер.height > 0 ? размер.height : обычныйРазмер.height)
        let шагДолготы = о.span.longitudeDelta * Double(радиусКружка) / ширина
        let шагШироты = о.span.latitudeDelta * Double(радиусКружка) / высота
        let запас = MKCoordinateRegion(center: о.center,
                                       span: MKCoordinateSpan(latitudeDelta: о.span.latitudeDelta * 2,
                                                              longitudeDelta: о.span.longitudeDelta * 2))
        let видные = пины.filter { внутри($0.широта, $0.долгота, запас) }
        guard шагДолготы.isFinite, шагШироты.isFinite, шагДолготы > 0.000_000_1, шагШироты > 0.000_000_1 else {
            return видные.map { ЗнакКарты(один: $0) }
        }
        var порядок: [Ячейка] = []
        var группы: [Ячейка: [КартаAPI.Пин]] = [:]
        for пин in видные {
            let ячейка = Ячейка(x: Int((пин.долгота / шагДолготы).rounded(.down)),
                                y: Int((пин.широта / шагШироты).rounded(.down)))
            if группы[ячейка] == nil {
                порядок.append(ячейка)
                группы[ячейка] = [пин]
            } else {
                группы[ячейка]?.append(пин)
            }
        }
        var итог: [ЗнакКарты] = []
        for ячейка in порядок {
            guard let вместе = группы[ячейка], let первый = вместе.first else { continue }
            if вместе.count == 1 {
                итог.append(ЗнакКарты(один: первый))
            } else {
                итог.append(ЗнакКарты(ключ: "c\(ячейка.x)_\(ячейка.y)", вместе: вместе))
            }
        }
        return итог
    }
}

/// Знак на карте ближе порога: ценник одного объявления или кружок с числом.
struct ЗнакКарты: Identifiable, Equatable {
    let id: String
    let широта: Double
    let долгота: Double
    /// Одно — ценник, больше — кружок.
    let пины: [КартаAPI.Пин]

    var координата: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: широта, longitude: долгота) }

    init(один пин: КартаAPI.Пин) {
        id = "p" + пин.id
        широта = пин.широта
        долгота = пин.долгота
        пины = [пин]
    }

    /// Кружок — в средней точке своих ценников.
    init(ключ: String, вместе: [КартаAPI.Пин]) {
        id = ключ
        let n = Double(max(1, вместе.count))
        широта = вместе.reduce(0.0) { $0 + $1.широта } / n
        долгота = вместе.reduce(0.0) { $0 + $1.долгота } / n
        пины = вместе
    }
}

/// Строка списка под картой — .mk-mcard сайта: объявление, расстояние от центра карты и метка «ТОП» у трёх первых.
struct СтрокаКарты: Identifiable, Equatable {
    let товар: Listing
    /// _dist сайта, км; у списка города его нет.
    let км: Double?
    /// _mtop: первые три ТОПа — с золотистой подложкой и меткой.
    let топ: Bool

    var id: String { товар.id }
}

/// Точка «Вы здесь» — _mkMeMk сайта (кнопка «Рядом»).
struct МоёМестоНаКарте: Identifiable, Equatable {
    let широта: Double
    let долгота: Double

    var id: String { "я" }
    var координата: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: широта, longitude: долгота) }
}

// MARK: - Модель

@MainActor
final class МодельКарты: ObservableObject {
    /// Что на холсте: пузыри городов или ценники.
    enum Режим: Equatable {
        case города
        case пины
    }

    /// Что в списке под картой — ветки _mkMapListUpdate сайта.
    enum ВидСписка: Equatable {
        case города
        case город(String)
        case пины
    }

    @Published private(set) var города: [КартаAPI.Город] = []
    /// total ответа map=1 — сколько всего объявлений по фильтрам.
    @Published private(set) var всего: Int?
    /// Ответ map=1 уже пришёл (удачный) — до него «Загружаем карту…», а не «Приблизьте карту».
    @Published private(set) var городаПришли = false
    @Published private(set) var грузимГорода = false
    @Published private(set) var пины: [КартаAPI.Пин] = []
    @Published private(set) var грузимПины = false
    /// Ценники и кружки для холста — пересобираются, когда карта остановилась и когда пришли ценники.
    @Published private(set) var знаки: [ЗнакКарты] = []
    /// Последний запрос карты не удался — _mkSrvFail сайта: плашка «Карта недоступна» с «Повторить».
    @Published private(set) var неудача = false
    /// Видимая область холста — после каждой остановки карты.
    @Published private(set) var область: MKCoordinateRegion = ГеометрияКарты.всяСтрана
    /// _mkFocusCity сайта: город, чьи объявления в списке.
    @Published private(set) var фокус: String?
    @Published private(set) var списокГорода: [Listing] = []
    @Published private(set) var всегоВГороде: Int?
    @Published private(set) var грузимСписок = false

    /// Размер холста в точках — ставит экран; по нему зум и радиус кружков.
    var размер: CGSize = .zero

    private var условия = УсловияКарты()
    private var начато = false
    private var задачаГородов: Task<Void, Never>?
    private var задачаПинов: Task<Void, Never>?
    private var задачаСписка: Task<Void, Never>?
    /// Номера запросов: ответ на прежний, пришедший после нового, выбрасывается.
    private var номерГородов = 0
    private var номерПинов = 0
    private var номерСписка = 0
    private let геопозиция = ГеопозицияКарты()

    /// Пауза после остановки карты перед запросом ценников, нс.
    private static let пауза: UInt64 = 400_000_000

    init() {}

    // MARK: - Что показывать

    var режим: Режим {
        ГеометрияКарты.зум(область, ширина: размер.width) > ГеометрияКарты.порогЗума ? .пины : .города
    }

    var видСписка: ВидСписка {
        if режим == .города { return .города }
        if let город = фокус { return .город(город) }
        return .пины
    }

    /// Пузыри на холсте — только издалека.
    var пузыри: [КартаAPI.Город] { режим == .города ? города : [] }

    /// Ценники и кружки на холсте — только ближе порога.
    var знакиНаХолсте: [ЗнакКарты] { режим == .пины ? знаки : [] }

    /// Идёт какой-нибудь запрос — крутилка в зелёной полосе.
    var занята: Bool { грузимГорода || грузимПины || грузимСписок }

    /// Города в кадре по убыванию числа объявлений (срез до 200 — у экрана).
    var городаВКадре: [КартаAPI.Город] {
        let о = область
        let видны = города.filter { ГеометрияКарты.внутри($0.широта, $0.долгота, о) }
        return видны.sorted { $0.число > $1.число }
    }

    /**
     Ценники в кадре — как список сайта в режиме пинов: три ТОПа первыми (у сайта их порядок ещё и меняется по дням —
     mkShuffle по DAY_SEED; у нас — как пришли), остальные ТОПы и прочие — по расстоянию от центра карты. Срез до 120 —
     у экрана.
     */
    var строкиПинов: [СтрокаКарты] {
        let о = область
        var топы: [СтрокаКарты] = []
        var прочие: [СтрокаКарты] = []
        for пин in пины where ГеометрияКарты.внутри(пин.широта, пин.долгота, о) {
            let расстояние = ГеометрияКарты.км(о.center.latitude, о.center.longitude, пин.широта, пин.долгота)
            if пин.товар.isTop {
                топы.append(СтрокаКарты(товар: пин.товар, км: расстояние, топ: true))
            } else {
                прочие.append(СтрокаКарты(товар: пин.товар, км: расстояние, топ: false))
            }
        }
        let первые = Array(топы.prefix(3))
        var дальше = прочие
        for строка in топы.dropFirst(3) {
            дальше.append(СтрокаКарты(товар: строка.товар, км: строка.км, топ: false))
        }
        дальше.sort { ($0.км ?? 0) < ($1.км ?? 0) }
        return первые + дальше
    }

    /// Объявления города: три ТОПа первыми, потом прочие, потом остальные ТОПы — как у сайта. Срез до 120 — у экрана.
    var строкиГорода: [СтрокаКарты] {
        let топы = списокГорода.filter { $0.isTop }
        let прочие = списокГорода.filter { !$0.isTop }
        let первые: [СтрокаКарты] = топы.prefix(3).map { СтрокаКарты(товар: $0, км: nil, топ: true) }
        let остальныеТопы: [Listing] = Array(топы.dropFirst(3))
        let дальше: [СтрокаКарты] = (прочие + остальныеТопы).map { СтрокаКарты(товар: $0, км: nil, топ: false) }
        return первые + дальше
    }

    /// Подпись в зелёной полосе — #mk-map-cnt сайта: «1 234 предложения», «56 · Алматы», «12 в этой области».
    var подписьСчёта: String? {
        switch видСписка {
        case .города:
            guard городаПришли else { return nil }
            let n: Int
            if let пришло = всего {
                n = пришло
            } else {
                n = городаВКадре.reduce(0) { $0 + $1.число }
            }
            return DesignText.предложений(n)
        case .город(let имя):
            if грузимСписок { return MapText.т("loading") }
            let n: Int
            if let пришло = всегоВГороде, пришло > 0 {
                n = пришло
            } else {
                n = строкиГорода.count
            }
            return DesignText.число(n) + " · " + имя
        case .пины:
            return String(строкиПинов.count) + " " + MapText.т("found")
        }
    }

    // MARK: - Действия

    /// Экран открылся: города по фильтрам ленты. Второй раз (вернулись с объявления) — только если фильтры сменились.
    func начать(_ новые: УсловияКарты) {
        guard начато else {
            начато = true
            условия = новые
            загрузитьГорода()
            return
        }
        сменитьУсловия(новые)
    }

    /// Сменились раздел или фильтры ленты (полоса разделов карты — как mkMapCat сайта): всё заново.
    func сменитьУсловия(_ новые: УсловияКарты) {
        guard новые != условия else { return }
        условия = новые
        города = []
        всего = nil
        городаПришли = false
        пины = []
        знаки = []
        загрузитьГорода()
        if режим == .пины { запроситьПины(сразу: true) }
        if let город = фокус { загрузитьСписок(город) }
    }

    /// «Повторить» на плашке неудачи.
    func повторить() {
        неудача = false
        загрузитьГорода()
        if режим == .пины { запроситьПины(сразу: true) }
    }

    /// Карта остановилась (onMapCameraChange .onEnd) — _mkMapOnMove сайта.
    func камераСменилась(_ новая: MKCoordinateRegion) {
        область = новая
        if режим == .пины {
            знаки = ГеометрияКарты.собрать(пины, область: новая, размер: размер)
            запроситьПины(сразу: false)
        } else {
            задачаПинов?.cancel()
            грузимПины = false
            /* Отдалили карту — список снова города, фокус города снят (_mkFocusCity = null). */
            if фокус != nil { снятьФокус() }
        }
    }

    /// Пузырь или карточка города — mkCityZoom: фокус на городе и его объявления в список. Карту к нему ведёт экран;
    /// `цель` — куда: пока карта летит, режим уже тот, что будет, и список сразу про город.
    func выбратьГород(_ город: String, цель: MKCoordinateRegion) {
        фокус = город
        область = цель
        if режим == .пины { знаки = ГеометрияКарты.собрать(пины, область: цель, размер: размер) }
        загрузитьСписок(город)
    }

    /// «Рядом»: одна точка от CoreLocation (разрешение «при использовании» — то же, что у страниц сайта в приложении,
    /// GeoBridge). nil — нет разрешения или точки.
    func найтиМеня(_ готово: @escaping @MainActor (CLLocationCoordinate2D?) -> Void) {
        геопозиция.узнать { координата in
            Task { @MainActor in готово(координата) }
        }
    }

    // MARK: - Запросы

    private func загрузитьГорода() {
        задачаГородов?.cancel()
        номерГородов += 1
        let номер = номерГородов
        let снимок = условия
        грузимГорода = true
        неудача = false
        задачаГородов = Task { [weak self] in
            let итог: КартаAPI.Города?
            do { итог = try await КартаAPI.города(снимок) } catch { итог = nil }
            guard let self, !Task.isCancelled, номер == self.номерГородов else { return }
            self.грузимГорода = false
            if let итог {
                self.города = итог.города
                self.всего = итог.всего
                self.городаПришли = true
            } else {
                self.неудача = true
            }
        }
    }

    /// Ценники видимой области. `сразу` — без паузы: сменились фильтры или «Повторить», карта не движется.
    private func запроситьПины(сразу: Bool) {
        задачаПинов?.cancel()
        номерПинов += 1
        let номер = номерПинов
        let снимок = условия
        let края = ГеометрияКарты.края(область)
        грузимПины = true
        задачаПинов = Task { [weak self] in
            if !сразу {
                try? await Task.sleep(nanoseconds: МодельКарты.пауза)
                if Task.isCancelled { return }
            }
            let пришли: [КартаAPI.Пин]?
            do {
                пришли = try await КартаAPI.пины(снимок, север: края.север, юг: края.юг, восток: края.восток,
                                                 запад: края.запад)
            } catch {
                пришли = nil
            }
            guard let self, !Task.isCancelled, номер == self.номерПинов else { return }
            self.грузимПины = false
            guard let пришли else {
                self.неудача = true
                return
            }
            self.пины = пришли
            self.знаки = ГеометрияКарты.собрать(пришли, область: self.область, размер: self.размер)
        }
    }

    private func загрузитьСписок(_ город: String) {
        задачаСписка?.cancel()
        номерСписка += 1
        let номер = номерСписка
        let снимок = условия
        списокГорода = []
        всегоВГороде = nil
        грузимСписок = true
        задачаСписка = Task { [weak self] in
            let итог: КартаAPI.СписокГорода?
            do { итог = try await КартаAPI.списокГорода(снимок, город: город) } catch { итог = nil }
            guard let self, !Task.isCancelled, номер == self.номерСписка else { return }
            self.грузимСписок = false
            /* Не пришло — как у сайта: пустой список с «Нет объявлений в этой области». */
            if let итог {
                self.списокГорода = итог.товары
                self.всегоВГороде = итог.всего
            }
        }
    }

    private func снятьФокус() {
        задачаСписка?.cancel()
        номерСписка += 1
        фокус = nil
        списокГорода = []
        всегоВГороде = nil
        грузимСписок = false
    }
}

// MARK: - Где я

/**
 Одна точка для «Рядом» (mkMapHere сайта). Разрешение — системное «при использовании», одно на всё приложение: его же
 спрашивает GeoBridge для страниц сайта (NSLocationWhenInUseUsageDescription уже в Info.plist). Не спрашивали — спросим
 по нажатию; запрещено или точки нет — nil, экран скажет «Не удалось определить местоположение». Следить не следим:
 одна requestLocation на нажатие.

 Обычный класс, как GeoBridge: CLLocationManager зовёт делегата на той нити, где создан, — модель создаёт его на главной.
 */
final class ГеопозицияКарты: NSObject, CLLocationManagerDelegate {
    private let менеджер = CLLocationManager()
    private var ждёт: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func узнать(_ готово: @escaping (CLLocationCoordinate2D?) -> Void) {
        ждёт = готово
        switch менеджер.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            менеджер.requestLocation()
        case .notDetermined:
            менеджер.requestWhenInUseAuthorization()
        default:
            отдать(nil)
        }
    }

    private func отдать(_ координата: CLLocationCoordinate2D?) {
        guard let готово = ждёт else { return }
        ждёт = nil
        готово(координата)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        /* Вызов приходит и сразу при создании менеджера — тогда никто не ждёт, и решать нечего. */
        guard ждёт != nil else { return }
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
