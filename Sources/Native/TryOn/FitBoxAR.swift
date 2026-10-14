import SwiftUI
import UIKit
import RealityKit
import ARKit
import AVFoundation
import Combine
import simd

/**
 «ПОМЕСТИТСЯ ЛИ?» — СЦЕНА AR С КОРОБКОЙ НАСТОЯЩИХ РАЗМЕРОВ (владелец 13.10.2026: «нужнее охват всего»).

 Без 3D-модели и без сервера: RealityKit ARView с ARWorldTrackingConfiguration ищет пол (и стены — для «Прижать к
 стене», Config.габаритыСтена). Касание пола ставит коробку размеров из объявления (ГабаритыВещи, FitBoxSize.swift):
 полупрозрачная зелёная, с яркими рёбрами и тенью-следом на полу, лицом к человеку. Появляется «вырастанием» снизу
 вверх (при «Уменьшении движения» — сразу). Два пальца — поворот вокруг вертикали, один палец — сдвиг по полу, касание
 пола в стороне — переставить туда. Подписи размеров («Ш 60 см», «В 85 см», «Г 55 см») — у трёх рёбер ближнего к
 камере угла: точки рёбер каждый кадр переводятся на экран (ARView.project), подписи — обычные UIView поверх сцены
 (крупный шрифт — по «Размеру текста»).

 «Прижать к стене»: коробка разворачивается задней стороной к ближайшей найденной стене и встаёт вплотную; сдвиг тогда
 идёт вдоль стены, поворот пальцами — отпускает. «Снимок» — ARView.snapshot, поверх него рисуются подписи и строка
 «Kliko.kz · размеры».

 Сессия идёт, только пока экран на виду и приложение не в фоне (ЭкранГабаритов зовёт появился/ушёл/вФон/изФона).
 Делегат сессии приходит на главную очередь; из него наружу — только значения (ПлоскостьГабаритов), самих ARFrame не
 держим и не копируем. В симуляторе ARKit не работает, а часть API ARView в нём не собирается — эти места под
 #if !targetEnvironment(simulator); кнопки там и нет (ОкноГабаритов.доступно).

 Линейка (владелец 14.10.2026, FitBoxRuler.swift): режим «Линейка» живёт в той же сессии и том же ARView — модель
 только прячет коробку и её подписи (жесты коробки в линейке молчат: точки ставит «+»), пересылает линейке слежение,
 размеры и сброс сцены. На устройствах с лидаром смена режима перенастраивает сессию (линейке — глубина и сетка сцены).
 */

/// Плоскость ARKit значениями — из делегата сессии на главную нить.
struct ПлоскостьГабаритов: Sendable {
    let ид: UUID
    let стена: Bool
    /// Центр плоскости в мире.
    let точка: SIMD3<Float>
    /// Нормаль (ось y якоря плоскости).
    let нормаль: SIMD3<Float>
    /// Ширина найденного куска, м.
    let ширина: Float
}

/// Как ARKit видит мир.
enum СлежениеГабаритов: Equatable, Sendable {
    case запуск
    case норма
    case быстро
    case мало
    case возврат
    case нет
}

/// Готовый снимок с коробкой или с отрезками линейки.
struct СнимокГабаритов: Identifiable {
    let id = UUID()
    let картинка: UIImage
    /// Подпись картинки для VoiceOver; nil — по размерам коробки (ЛистСнимкаГабаритов).
    var озвучка: String? = nil
}

@MainActor
final class МодельГабаритов: NSObject, ObservableObject {
    enum Этап: Equatable {
        case ищемПол
        case можноСтавить
        case стоит
    }

    enum Камера: Equatable {
        case ждём
        case идёт
        case пауза
        case запрещена
        case сбой
    }

    let товар: Listing
    let найдено: НайденныеГабариты
    /// «Измерить в AR» из подачи (ОкноГабаритов.открытьЗамер): только линейка, без коробки и сравнения; «Готово» отдаёт
    /// первые три отрезка как ширину, высоту и глубину вещи.
    let замерВещи: Bool

    /// Размеры коробки; nil — ещё не указали (открыт лист размеров).
    @Published private(set) var габариты: ГабаритыВещи? = nil
    @Published var листРазмеров = false
    /// Лист снимка: пока он открыт, сессия на паузе (неподвижная картинка, а камера и поиск плоскостей тратили бы
    /// батарею); закрыли — снова идёт, без сброса (коробка на месте).
    @Published var снимок: СнимокГабаритов? = nil {
        didSet {
            guard (снимок == nil) != (oldValue == nil) else { return }
            if снимок == nil { запустить() } else { остановить() }
        }
    }
    @Published private(set) var этап: Этап = .ищемПол
    @Published private(set) var слежение: СлежениеГабаритов = .запуск
    @Published private(set) var камера: Камера = .ждём
    @Published private(set) var естьСтена = false
    @Published private(set) var прижато = false
    @Published private(set) var снимаем = false
    /// Короткое сообщение поверх камеры (сама гаснет).
    @Published private(set) var сообщение: String? = nil
    /// Коробка или линейка (переключатель сверху).
    @Published private(set) var режим: РежимГабаритов = .коробка
    /// Линейка AR — в той же сессии (FitBoxRuler.swift).
    let линейка: ЛинейкаГабаритов

    private(set) var вид: ARView?
    private var корень: AnchorEntity?
    /// Положение и поворот коробки (дитя корня в начале мира).
    private var корпус: Entity?
    /// Сама коробка: её масштаб по высоте — «вырастание».
    private var рост: Entity?
    private var подписи: [ПодписьРебраГабаритов] = []
    private var подписиВидны = false
    private var подписка: (any Cancellable)?
    private var стены: [UUID: ПлоскостьГабаритов] = [:]
    private var полы: Set<UUID> = []
    private var стенаПрижатия: UUID? = nil
    private var виден = false
    /// Окно закрывают насовсем (✕): при уходе с экрана — разобрать ARView, а не только поставить паузу.
    private var закрывается = false
    private var вФоне = false
    private var идёт = false
    private var первыйЗапуск = true
    private var угол: Float = 0
    private var уголНачала: Float = 0
    private var сдвиг = SIMD3<Float>(0, 0, 0)
    private var тянем = false
    private var задачаСообщения: Task<Void, Never>? = nil
    private var задачаПодписей: Task<Void, Never>? = nil

    init(товар: Listing, найдено: НайденныеГабариты, замерВещи: Bool = false) {
        self.товар = товар
        self.найдено = найдено
        self.замерВещи = замерВещи
        линейка = ЛинейкаГабаритов(замерВещи: замерВещи)
        super.init()
        if замерВещи {
            режим = .линейка
        } else {
            габариты = найдено.надёжно ? найдено.полные : nil
            линейка.задатьГабариты(габариты)
        }
    }

    private func т(_ ключ: String) -> String { ГабаритыText.т(ключ) }

    private var тихо: Bool { UIAccessibility.isReduceMotionEnabled || ДвижениеСайта.тихо }

    // MARK: Жизнь экрана

    func появился() {
        виден = true
        /* Линейке размеры вещи не нужны (замер для подачи, ниша без размеров) — камера сразу. */
        guard габариты == nil && режим == .коробка else {
            запустить()
            return
        }
        /* Размеров нет или они сомнительны — сначала лист (когда окно доедет: лист поверх едущего окна не встаёт). */
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, self.виден, self.габариты == nil, self.режим == .коробка, !self.листРазмеров else { return }
            self.листРазмеров = true
        }
    }

    func ушёл() {
        виден = false
        остановить()
        задачаСообщения?.cancel()
        задачаПодписей?.cancel()
        if закрывается { разобрать() }
    }

    /// Окно закрывают (✕ или лист размеров закрыт без размеров) — после ухода с экрана всё разобрать.
    func закрываем() {
        закрывается = true
    }

    /**
     ARView, подписка на кадры сцены, делегат сессии, жесты и подписи — отпустить сразу, не дожидаясь деинициализатора
     модели: у ARView бывает, что он держит Metal и сессию дольше нужного, а каждое открытие окна создаёт новый.
     */
    private func разобрать() {
        подписка?.cancel()
        подписка = nil
        линейка.отключить()
        guard let вид else { return }
        #if !targetEnvironment(simulator)
        вид.session.delegate = nil
        #endif
        for жест in вид.gestureRecognizers ?? [] { вид.removeGestureRecognizer(жест) }
        if let корень { вид.scene.removeAnchor(корень) }
        for подпись in подписи { подпись.removeFromSuperview() }
        подписи = []
        подписиВидны = false
        корпус = nil
        рост = nil
        корень = nil
        self.вид = nil
    }

    func вФон() {
        guard виден else { return }
        вФоне = true
        остановить()
    }

    func изФона() {
        guard виден, вФоне else { return }
        вФоне = false
        /* Вернулись из Настроек — камеру могли разрешить: пробуем заново (запрещена по-прежнему — снова заглушка). */
        if камера == .запрещена {
            камера = .ждём
            первыйЗапуск = true
        }
        запустить()
    }

    /// Новые размеры из листа: коробка, если стоит, перестраивается; сессия — запускается.
    func задать(_ новые: ГабаритыВещи) {
        let прежние = габариты
        габариты = новые
        линейка.задатьГабариты(новые)
        if корпус != nil && прежние != новые { перестроить() }
        запустить()
    }

    func повторить() {
        камера = .ждём
        первыйЗапуск = true
        идёт = false
        запустить()
    }

    /**
     Перед запуском с .resetTracking (после сбоя сессии, после разрешения камеры): начало мира переедет к телефону —
     старая коробка с подписями повисла бы в случайном месте, а найденные пол и стены уже не те. Всё — с начала.
     */
    private func сброситьСцену() {
        задачаПодписей?.cancel()
        корпус?.removeFromParent()
        корпус = nil
        рост = nil
        показатьПодписи(false)
        полы.removeAll()
        стены.removeAll()
        линейка.сброситьСцену()
        прижато = false
        стенаПрижатия = nil
        if естьСтена { естьСтена = false }
        if этап != .ищемПол { этап = .ищемПол }
    }

    // MARK: Сессия

    /// AR-вид для сцены (СценаГабаритовAR): создаётся один раз.
    func создатьВид() -> ARView {
        if let вид { return вид }
        #if targetEnvironment(simulator)
        let новый = ARView(frame: .zero)
        #else
        let новый = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        /* В сцене только UnlitMaterial и свой след на полу: свет окружения, HDR, тени и зерно камеры — лишняя работа
           GPU за долгий сеанс «померить шкаф». */
        новый.renderOptions.formUnion([.disableMotionBlur, .disableDepthOfField, .disableAREnvironmentLighting,
                                       .disableHDR, .disableGroundingShadows, .disableCameraGrain])
        новый.session.delegate = self
        #endif
        новый.isAccessibilityElement = false
        let корень = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        новый.scene.addAnchor(корень)
        self.корень = корень
        добавитьЖесты(новый)
        подписи = (0..<3).map { _ in
            let подпись = ПодписьРебраГабаритов(frame: .zero)
            новый.addSubview(подпись)
            return подпись
        }
        обновитьТекстыПодписей()
        линейка.подключить(к: новый)
        линейка.включить(режим == .линейка)
        линейка.слежениеПришло(слежение)
        /* Обновление сцены RealityKit приходит на главной нити. */
        подписка = новый.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.кадр()
            }
        }
        вид = новый
        /* Вид мог появиться позже onAppear — запуск тогда отсюда. */
        Task { @MainActor [weak self] in
            self?.запустить()
        }
        return новый
    }

    /// Коробке нужны размеры вещи, линейке — нет: в линейке камера идёт и без них (померить нишу у старого объявления).
    private func запустить() {
        guard ОкноГабаритов.доступно, виден, !вФоне, !идёт, снимок == nil, габариты != nil || режим == .линейка,
              вид != nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            камера = .запрещена
            return
        default:
            break
        }
        #if !targetEnvironment(simulator)
        let настройка = настройкаСессии()
        if первыйЗапуск { сброситьСцену() }
        let параметры: ARSession.RunOptions = первыйЗапуск ? [.resetTracking, .removeExistingAnchors] : []
        вид?.session.run(настройка, options: параметры)
        #endif
        первыйЗапуск = false
        идёт = true
        if камера != .идёт { камера = .идёт }
    }

    #if !targetEnvironment(simulator)
    private func настройкаСессии() -> ARWorldTrackingConfiguration {
        let настройка = ARWorldTrackingConfiguration()
        настройка.planeDetection = Config.габаритыСтена ? [.horizontal, .vertical] : [.horizontal]
        настройка.environmentTexturing = .none
        /* Коробка стоит неподвижно — хватит 30 кадров в секунду (обычный формат — 60): тот же размер кадра или меньше,
           не 4K. Такого формата нет — остаётся обычный. С лидаром — всегда обычный: линейка перенастраивает сессию
           (сетка сцены), и смена режима не должна менять формат видео на ходу. */
        let обычный = настройка.videoFormat.imageResolution
        func площадь(_ формат: ARConfiguration.VideoFormat) -> CGFloat {
            формат.imageResolution.width * формат.imageResolution.height
        }
        let тише = ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { формат in
                формат.framesPerSecond == 30 && формат.imageResolution.width <= обычный.width
                    && формат.imageResolution.height <= обычный.height
            }
            .max { площадь($0) < площадь($1) }
        if let тише, !ЛинейкаГабаритов.лидар { настройка.videoFormat = тише }
        if режим == .линейка { ЛинейкаГабаритов.точнее(настройка) }
        return настройка
    }
    #endif

    /// Режим сменился на идущей сессии: с лидаром — та же сессия с новой настройкой (без сброса, якоря на месте).
    private func перенастроить() {
        guard идёт, ЛинейкаГабаритов.лидар else { return }
        #if !targetEnvironment(simulator)
        вид?.session.run(настройкаСессии(), options: [])
        #endif
    }

    // MARK: Режим

    /**
     «Коробка / Линейка»: одна сессия на оба режима. Коробка в линейке прячется (место и поворот помнит), подписи её
     гаснут; отрезки линейки в коробке — тоже. Касания по сцене в линейке коробку не двигают.
     */
    func сменитьРежим(_ новый: РежимГабаритов) {
        guard новый != режим, !замерВещи, Config.габаритыЛинейка || новый == .коробка else { return }
        режим = новый
        let коробка = новый == .коробка
        корпус?.isEnabled = коробка
        показатьПодписи(коробка && этап == .стоит)
        линейка.включить(!коробка)
        перенастроить()
        /* Линейка без размеров вещи: камера могла ещё не идти (лист размеров закрыли пустым). */
        запустить()
        ОткликСайта.выбор()
        UIAccessibility.post(notification: .announcement,
                             argument: ЛинейкаГабаритовText.т(коробка ? "fr_mode_box_on" : "fr_mode_ruler_on"))
        /* В коробку без размеров — сначала лист размеров (закроют пустым — обратно в линейку, безРазмеров()). */
        if коробка && габариты == nil { листРазмеров = true }
    }

    /**
     Лист размеров закрыли, а размеров нет: коробку ставить не с чего, но линейке они не нужны — окно остаётся в режиме
     линейки (померить нишу или проём). false — линейки нет (рубильник, нет AR): окно закрывают.
     */
    func безРазмеров() -> Bool {
        guard Config.габаритыЛинейка, ОкноГабаритов.доступно, габариты == nil else { return false }
        if режим == .линейка {
            запустить()
        } else {
            сменитьРежим(.линейка)
            показать(ЛинейкаГабаритовText.т("fr_no_dims"))
        }
        return true
    }

    /// «Снимок» в линейке: кадр с отрезками — в тот же лист снимка (сессия на паузе, пока он открыт).
    func снятьЛинейку() {
        guard режим == .линейка else { return }
        линейка.снять { [weak self] готовый in
            guard let self else { return }
            guard let готовый else {
                self.показать(self.т("fb_shot_fail"))
                return
            }
            guard self.виден else { return }
            ОткликСайта.успех()
            self.снимок = готовый
        }
    }

    private func остановить() {
        guard идёт else { return }
        идёт = false
        #if !targetEnvironment(simulator)
        вид?.session.pause()
        #endif
    }

    fileprivate func плоскостиПришли(_ новые: [ПлоскостьГабаритов], убрать: [UUID]) {
        for плоскость in новые {
            if плоскость.стена {
                стены[плоскость.ид] = плоскость
            } else {
                полы.insert(плоскость.ид)
            }
        }
        for ид in убрать {
            стены[ид] = nil
            полы.remove(ид)
        }
        if этап == .ищемПол && !полы.isEmpty {
            этап = .можноСтавить
            if режим == .коробка { UIAccessibility.post(notification: .announcement, argument: т("fb_tap")) }
        }
        let стена = Config.габаритыСтена && !стены.isEmpty
        if стена != естьСтена { естьСтена = стена }
    }

    fileprivate func слежениеПришло(_ новое: СлежениеГабаритов) {
        if слежение != новое { слежение = новое }
        линейка.слежениеПришло(новое)
    }

    fileprivate func сессияПрервана(_ прервана: Bool) {
        guard камера == .идёт || камера == .пауза else { return }
        камера = прервана ? .пауза : .идёт
    }

    fileprivate func сбойСессии(запрет: Bool) {
        идёт = false
        камера = запрет ? .запрещена : .сбой
    }

    // MARK: Что показать

    /// Подсказка над камерой: значок и текст; nil — не нужна.
    var подсказка: (значок: String, текст: String)? {
        switch камера {
        case .запрещена, .сбой:
            return nil
        case .пауза:
            return ("pause.circle", т("fb_paused"))
        case .ждём:
            if габариты == nil { return nil }
            return ("camera", т("fb_start"))
        case .идёт:
            break
        }
        switch слежение {
        case .быстро:
            return ("tortoise", т("fb_fast"))
        case .мало:
            return ("lightbulb", т("fb_dark"))
        case .возврат:
            if этап == .стоит { return ("arrow.uturn.backward", т("fb_relocal")) }
        case .запуск, .нет, .норма:
            break
        }
        switch этап {
        case .ищемПол: return ("iphone", т("fb_scan"))
        case .можноСтавить: return ("hand.tap", т("fb_tap"))
        case .стоит: return ("rotate.3d", т("fb_placed"))
        }
    }

    /// Показывать ли «Прижать к стене».
    var стенаДоступна: Bool { Config.габаритыСтена && этап == .стоит && (естьСтена || прижато) }

    /// Для VoiceOver: что сейчас в кадре.
    var описаниеСостояния: String {
        if этап == .стоит, let габариты {
            return ГабаритыText.т("fb_state_box", габариты.озвучка)
        }
        return подсказка?.текст ?? ""
    }

    private func показать(_ текст: String) {
        сообщение = текст
        UIAccessibility.post(notification: .announcement, argument: текст)
        задачаСообщения?.cancel()
        задачаСообщения = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.сообщение = nil
        }
    }

    // MARK: Коробка

    /// Поставить коробку (или переставить) туда, куда смотрит точка экрана.
    private func поставить(в точка: CGPoint) {
        guard габариты != nil else { return }
        if let корпус {
            guard let место = точкаНаПолу(точка) ?? точкаНаПлоскости(точка, высота: корпус.position.y) else {
                показать(т("fb_no_floor"))
                return
            }
            /* Касание по самой коробке — не перестановка. */
            let местная = корпус.convert(position: место, from: nil)
            if let р = габариты?.метры, abs(местная.x) < р.x / 2, abs(местная.z) < р.z / 2 { return }
            if прижато {
                прижато = false
                стенаПрижатия = nil
            }
            передвинуть(в: место)
            return
        }
        guard let место = точкаНаПолу(точка) else {
            показать(т("fb_no_floor"))
            return
        }
        построить(на: место)
    }

    func поставитьВЦентр() {
        guard let вид else { return }
        поставить(в: CGPoint(x: вид.bounds.midX, y: вид.bounds.midY))
    }

    /// Повернуть на 15° (VoiceOver).
    func повернуть(влево: Bool) {
        guard let корпус else { return }
        отпуститьСтену()
        угол += (влево ? 1 : -1) * Float.pi / 12
        корпус.orientation = simd_quatf(angle: угол, axis: SIMD3<Float>(0, 1, 0))
    }

    func убрать() {
        guard let корпус else { return }
        корпус.removeFromParent()
        self.корпус = nil
        рост = nil
        прижато = false
        стенаПрижатия = nil
        показатьПодписи(false)
        этап = полы.isEmpty ? .ищемПол : .можноСтавить
        ОткликСайта.выбор()
        UIAccessibility.post(notification: .announcement, argument: т("fb_removed"))
    }

    private func построить(на место: SIMD3<Float>) {
        guard let корень, let габариты else { return }
        let корпус = Entity()
        корпус.position = место
        угол = уголКамере(место)
        корпус.orientation = simd_quatf(angle: угол, axis: SIMD3<Float>(0, 1, 0))
        let рост = КоробкаГабаритов.собрать(габариты.метры)
        корпус.addChild(рост)
        корень.addChild(корпус)
        self.корпус = корпус
        self.рост = рост
        этап = .стоит
        вырастить(рост)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIAccessibility.post(notification: .announcement, argument: т("fb_placed_done"))
    }

    /// Размеры сменились — коробка новая, на том же месте и с тем же поворотом.
    private func перестроить() {
        guard let корпус, let габариты else { return }
        рост?.removeFromParent()
        let новый = КоробкаГабаритов.собрать(габариты.метры)
        корпус.addChild(новый)
        рост = новый
        обновитьТекстыПодписей()
        if прижато, let ид = стенаПрижатия, let стена = стены[ид] {
            прижать(к: стена, плавно: false)
        }
        вырастить(новый)
    }

    private func передвинуть(в место: SIMD3<Float>) {
        guard let корпус else { return }
        var цель = корпус.transform
        цель.translation = место
        if тихо {
            корпус.transform = цель
        } else {
            _ = корпус.move(to: цель, relativeTo: корпус.parent, duration: 0.25, timingFunction: .easeInOut)
        }
    }

    /// «Вырастание» снизу вверх: масштаб по высоте от 2 % до 100 %; подписи — когда выросла.
    private func вырастить(_ рост: Entity) {
        показатьПодписи(false)
        задачаПодписей?.cancel()
        if тихо {
            рост.scale = SIMD3<Float>(1, 1, 1)
            показатьПодписи(true)
            return
        }
        рост.scale = SIMD3<Float>(1, 0.02, 1)
        var цель = рост.transform
        цель.scale = SIMD3<Float>(1, 1, 1)
        _ = рост.move(to: цель, relativeTo: рост.parent, duration: 0.55, timingFunction: .easeOut)
        задачаПодписей = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 520_000_000)
            guard !Task.isCancelled else { return }
            self?.показатьПодписи(true)
        }
    }

    /// Угол поворота вокруг вертикали, при котором лицо коробки (+z) смотрит на камеру.
    private func уголКамере(_ место: SIMD3<Float>) -> Float {
        guard let вид else { return 0 }
        let камера = вид.cameraTransform.translation
        let dx = камера.x - место.x
        let dz = камера.z - место.z
        guard abs(dx) + abs(dz) > 0.0001 else { return 0 }
        return atan2(dx, dz)
    }

    // MARK: Пол и луч

    /// Точка на горизонтальной плоскости ARKit (пол, стол) под точкой экрана.
    private func точкаНаПолу(_ точка: CGPoint) -> SIMD3<Float>? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard let вид else { return nil }
        let попадание = вид.raycast(from: точка, allowing: .existingPlaneGeometry, alignment: .horizontal).first
            ?? вид.raycast(from: точка, allowing: .estimatedPlane, alignment: .horizontal).first
        guard let попадание else { return nil }
        let столбец = попадание.worldTransform.columns.3
        return SIMD3<Float>(столбец.x, столбец.y, столбец.z)
        #endif
    }

    /// Луч из точки экрана до горизонтали на высоте `высота` — сдвиг пальцем по тому же полу, без запросов ARKit.
    private func точкаНаПлоскости(_ точка: CGPoint, высота: Float) -> SIMD3<Float>? {
        guard let вид, let луч = вид.ray(through: точка) else { return nil }
        let н = луч.direction
        guard н.y < -0.0001 else { return nil }
        let путь = (высота - луч.origin.y) / н.y
        guard путь > 0, путь < 20 else { return nil }
        return луч.origin + н * путь
    }

    // MARK: Стена

    func переключитьСтену() {
        guard let корпус else { return }
        if прижато {
            отпуститьСтену()
            ОткликСайта.выбор()
            return
        }
        guard let найдена = ближайшаяСтена(к: корпус.position) else {
            показать(т("fb_wall_far"))
            return
        }
        стенаПрижатия = найдена.ид
        прижато = true
        прижать(к: найдена.стена, плавно: true)
        ОткликСайта.выбор()
        UIAccessibility.post(notification: .announcement, argument: т("fb_wall_on"))
    }

    private func отпуститьСтену() {
        guard прижато else { return }
        прижато = false
        стенаПрижатия = nil
    }

    /// Горизонтальная нормаль стены в сторону точки `к` (в комнату); стена почти горизонтальна — nil.
    private func нормаль(_ стена: ПлоскостьГабаритов, к точка: SIMD3<Float>) -> SIMD3<Float>? {
        var н = SIMD3<Float>(стена.нормаль.x, 0, стена.нормаль.z)
        let длина = simd_length(н)
        guard длина > 0.3 else { return nil }
        н /= длина
        var сторона = точка - стена.точка
        if abs(simd_dot(сторона, н)) < 0.02, let вид {
            сторона = вид.cameraTransform.translation - стена.точка
        }
        if simd_dot(сторона, н) < 0 { н = -н }
        return н
    }

    /// Ближайшая стена не дальше 3 м от коробки и не в стороне от найденного куска больше чем на метр.
    private func ближайшаяСтена(к точка: SIMD3<Float>) -> (ид: UUID, стена: ПлоскостьГабаритов)? {
        var лучшая: (ид: UUID, стена: ПлоскостьГабаритов)? = nil
        var наименьшее: Float = 3
        for (ид, стена) in стены {
            guard let н = нормаль(стена, к: точка) else { continue }
            let от = точка - стена.точка
            let до = abs(simd_dot(от, н))
            let вдоль = от - н * simd_dot(от, н)
            let вбок = simd_length(SIMD3<Float>(вдоль.x, 0, вдоль.z))
            guard вбок < стена.ширина / 2 + 1, до < наименьшее else { continue }
            наименьшее = до
            лучшая = (ид: ид, стена: стена)
        }
        return лучшая
    }

    /// Развернуть коробку спиной к стене и поставить вплотную (полсантиметра зазора).
    private func прижать(к стена: ПлоскостьГабаритов, плавно: Bool) {
        guard let корпус, let габариты, let н = нормаль(стена, к: корпус.position) else { return }
        угол = atan2(н.x, н.z)
        let место = кСтене(корпус.position, стена: стена, нормаль: н, глубина: габариты.метры.z)
        let цель = Transform(scale: корпус.scale, rotation: simd_quatf(angle: угол, axis: SIMD3<Float>(0, 1, 0)),
                             translation: место)
        if плавно && !тихо {
            _ = корпус.move(to: цель, relativeTo: корпус.parent, duration: 0.3, timingFunction: .easeInOut)
        } else {
            корпус.transform = цель
        }
    }

    private func кСтене(_ место: SIMD3<Float>, стена: ПлоскостьГабаритов, нормаль н: SIMD3<Float>,
                        глубина: Float) -> SIMD3<Float> {
        let до = simd_dot(место - стена.точка, н)
        var итог = место - н * (до - глубина / 2 - 0.005)
        итог.y = место.y
        return итог
    }

    // MARK: Жесты

    private func добавитьЖесты(_ вид: ARView) {
        let касание = UITapGestureRecognizer(target: self, action: #selector(жестКасания(_:)))
        let тяга = UIPanGestureRecognizer(target: self, action: #selector(жестТяги(_:)))
        тяга.maximumNumberOfTouches = 1
        тяга.delegate = self
        let вращение = UIRotationGestureRecognizer(target: self, action: #selector(жестВращения(_:)))
        вращение.delegate = self
        вид.addGestureRecognizer(касание)
        вид.addGestureRecognizer(тяга)
        вид.addGestureRecognizer(вращение)
    }

    @objc(klikoFitBoxTap:)
    private func жестКасания(_ жест: UITapGestureRecognizer) {
        guard режим == .коробка, let вид, жест.state == .ended else { return }
        поставить(в: жест.location(in: вид))
    }

    @objc(klikoFitBoxPan:)
    private func жестТяги(_ жест: UIPanGestureRecognizer) {
        guard режим == .коробка, let вид, let корпус else { return }
        let пол = корпус.position.y
        let точка = жест.location(in: вид)
        switch жест.state {
        case .began:
            guard let место = точкаНаПлоскости(точка, высота: пол) else {
                тянем = false
                return
            }
            сдвиг = корпус.position - место
            сдвиг.y = 0
            тянем = true
        case .changed:
            guard тянем, let место = точкаНаПлоскости(точка, высота: пол) else { return }
            var новое = место + сдвиг
            новое.y = пол
            if прижато, let ид = стенаПрижатия, let стена = стены[ид], let габариты,
               let н = нормаль(стена, к: корпус.position) {
                новое = кСтене(новое, стена: стена, нормаль: н, глубина: габариты.метры.z)
            }
            корпус.position = новое
        default:
            тянем = false
        }
    }

    @objc(klikoFitBoxRotate:)
    private func жестВращения(_ жест: UIRotationGestureRecognizer) {
        guard режим == .коробка, let корпус else { return }
        switch жест.state {
        case .began:
            отпуститьСтену()
            уголНачала = угол
        case .changed:
            угол = уголНачала - Float(жест.rotation)
            корпус.orientation = simd_quatf(angle: угол, axis: SIMD3<Float>(0, 1, 0))
        default:
            break
        }
    }

    // MARK: Подписи у рёбер

    private func обновитьТекстыПодписей() {
        guard let г = габариты, подписи.count == 3 else { return }
        let см = т("fb_cm")
        подписи[0].текст = т("fb_w_short") + " " + ГабаритыВещи.число(г.ширина) + " " + см
        подписи[1].текст = т("fb_h_short") + " " + ГабаритыВещи.число(г.высота) + " " + см
        подписи[2].текст = т("fb_d_short") + " " + ГабаритыВещи.число(г.глубина) + " " + см
    }

    private func показатьПодписи(_ показ: Bool) {
        /* В линейке подписи коробки не видны, даже если «вырастание» досчиталось уже после смены режима. */
        let да = показ && режим == .коробка
        подписиВидны = да
        let подписи = self.подписи
        if да && !тихо {
            UIView.animate(withDuration: 0.25) {
                for подпись in подписи { подпись.alpha = 1 }
            }
        } else {
            for подпись in подписи { подпись.alpha = да ? 1 : 0 }
        }
    }

    /// Каждый кадр сцены: три точки у рёбер ближнего к камере угла — на экран.
    private func кадр() {
        guard подписиВидны, let вид, let корпус, let габариты, подписи.count == 3 else { return }
        let р = габариты.метры
        let камера = вид.cameraTransform.translation
        let центр = корпус.position
        let поворот = корпус.orientation
        var ближний = (x: Float(1), z: Float(1))
        var наименьшее = Float.greatestFiniteMagnitude
        for x in [Float(-1), 1] {
            for z in [Float(-1), 1] {
                let точка = центр + поворот.act(SIMD3<Float>(x * р.x / 2, 0, z * р.z / 2))
                let до = simd_distance(точка, камера)
                if до < наименьшее {
                    наименьшее = до
                    ближний = (x: x, z: z)
                }
            }
        }
        let отступ: Float = 0.05
        let местные = [
            SIMD3<Float>(0, 0.02, ближний.z * (р.z / 2 + отступ)),
            SIMD3<Float>(ближний.x * (р.x / 2 + отступ), р.y / 2, ближний.z * (р.z / 2 + отступ)),
            SIMD3<Float>(ближний.x * (р.x / 2 + отступ), 0.02, 0)
        ]
        let поле = вид.bounds.insetBy(dx: -30, dy: -30)
        for (номер, местная) in местные.enumerated() {
            let подпись = подписи[номер]
            подпись.следить()
            if let наЭкране = вид.project(центр + поворот.act(местная)), поле.contains(наЭкране) {
                подпись.center = наЭкране
                if подпись.isHidden { подпись.isHidden = false }
            } else if !подпись.isHidden {
                подпись.isHidden = true
            }
        }
    }

    // MARK: Снимок

    func снять() {
        guard let вид, !снимаем, корпус != nil else { return }
        снимаем = true
        вид.snapshot(saveToHDR: false) { [weak self] картинка in
            guard let self else { return }
            Task { @MainActor in
                self.снимокПришёл(картинка)
            }
        }
    }

    /**
     На главной нити — только лёгкое: подписи у рёбер маленькими картинками и их места (слой UIView рисуется только
     здесь). Склейка во весь экран в пикселях и плашка с текстом — в фоне (UIGraphicsImageRenderer потокобезопасен).
     */
    private func снимокПришёл(_ картинка: UIImage?) {
        guard let картинка, let вид, картинка.size.width > 0, вид.bounds.width > 0 else {
            снимаем = false
            показать(т("fb_shot_fail"))
            return
        }
        let к = картинка.size.width / вид.bounds.width
        let видимые = подписи.filter { !$0.isHidden && $0.alpha > 0.01 }
        let метки: [(картинка: UIImage, место: CGRect)] = видимые.map { подпись in
            let формат = UIGraphicsImageRendererFormat()
            формат.scale = картинка.scale * к
            формат.opaque = false
            let малая = UIGraphicsImageRenderer(size: подпись.bounds.size, format: формат).image { холст in
                подпись.layer.render(in: холст.cgContext)
            }
            let м = подпись.frame
            return (малая, CGRect(x: м.minX * к, y: м.minY * к, width: м.width * к, height: м.height * к))
        }
        let строка = габариты.map { "Kliko.kz · " + $0.строка + " " + т("fb_cm") } ?? "Kliko.kz"
        Task { @MainActor [weak self] in
            let готовая = await Task.detached(priority: .userInitiated) { () -> UIImage in
                МодельГабаритов.собрать(картинка, метки: метки, строка: строка, к: к)
            }.value
            guard let self else { return }
            self.снимаем = false
            guard self.виден else { return }
            ОткликСайта.успех()
            self.снимок = СнимокГабаритов(картинка: готовая)
        }
    }

    /// Кадр + подписи у рёбер (или у отрезков линейки) + плашка «Kliko.kz · …» внизу. Не на главной нити.
    nonisolated static func собрать(_ кадр: UIImage, метки: [(картинка: UIImage, место: CGRect)],
                                    строка: String, к: CGFloat) -> UIImage {
        let размер = кадр.size
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = кадр.scale
        формат.opaque = true
        return UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
            кадр.draw(in: CGRect(origin: .zero, size: размер))
            for метка in метки {
                метка.картинка.draw(in: метка.место)
            }
            let шрифт = UIFont.systemFont(ofSize: 15 * к, weight: .bold)
            let текст = NSAttributedString(string: строка, attributes: [
                .font: шрифт,
                .foregroundColor: UIColor.white
            ])
            /* Строка линейки со сравнением («Kliko.kz · Ниша 1 м 25 см · вещь (ширина) 1 м 30 см · не хватает 5 см ✗»)
               шире кадра телефона: плашка не шире кадра, текст переносится — итог справа не уходит за край. */
            let отступ = 16 * к
            let предел = max(отступ, размер.width - отступ * 2 - отступ * 1.2)
            let варианты: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
            let поле = текст.boundingRect(with: CGSize(width: предел, height: .greatestFiniteMagnitude),
                                          options: варианты, context: nil).integral
            let плашка = CGRect(x: отступ, y: размер.height - поле.height - отступ * 2.4,
                                width: поле.width + отступ * 1.2, height: поле.height + отступ * 0.8)
            UIColor(white: 0, alpha: 0.55).setFill()
            UIBezierPath(roundedRect: плашка, cornerRadius: min(плашка.height / 2, отступ * 1.2)).fill()
            текст.draw(with: CGRect(x: плашка.minX + отступ * 0.6, y: плашка.minY + отступ * 0.4, width: поле.width,
                                    height: поле.height),
                       options: варианты, context: nil)
        }
    }
}

// MARK: - Делегат сессии

extension МодельГабаритов: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let плоскости = Self.плоскости(anchors)
        guard !плоскости.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.плоскостиПришли(плоскости, убрать: [])
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let плоскости = Self.плоскости(anchors)
        guard !плоскости.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.плоскостиПришли(плоскости, убрать: [])
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let ид = anchors.compactMap { ($0 as? ARPlaneAnchor)?.identifier }
        guard !ид.isEmpty else { return }
        Task { @MainActor [weak self] in
            self?.плоскостиПришли([], убрать: ид)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let слежение = Self.слежение(camera.trackingState)
        Task { @MainActor [weak self] in
            self?.слежениеПришло(слежение)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let запрет = (error as? ARError)?.code == .cameraUnauthorized
        Task { @MainActor [weak self] in
            self?.сбойСессии(запрет: запрет)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.сессияПрервана(true)
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in
            self?.сессияПрервана(false)
        }
    }

    /// Плоскости из якорей — значениями (сами якоря наружу не уходят).
    nonisolated private static func плоскости(_ якоря: [ARAnchor]) -> [ПлоскостьГабаритов] {
        якоря.compactMap { якорь -> ПлоскостьГабаритов? in
            guard let плоскость = якорь as? ARPlaneAnchor else { return nil }
            let м = плоскость.transform
            let ц = м * SIMD4<Float>(плоскость.center.x, плоскость.center.y, плоскость.center.z, 1)
            return ПлоскостьГабаритов(ид: плоскость.identifier,
                                      стена: плоскость.alignment == .vertical,
                                      точка: SIMD3<Float>(ц.x, ц.y, ц.z),
                                      нормаль: SIMD3<Float>(м.columns.1.x, м.columns.1.y, м.columns.1.z),
                                      ширина: плоскость.planeExtent.width)
        }
    }

    nonisolated private static func слежение(_ состояние: ARCamera.TrackingState) -> СлежениеГабаритов {
        switch состояние {
        case .normal:
            return .норма
        case .notAvailable:
            return .нет
        case .limited(let причина):
            switch причина {
            case .initializing: return .запуск
            case .excessiveMotion: return .быстро
            case .insufficientFeatures: return .мало
            case .relocalizing: return .возврат
            @unknown default: return .мало
            }
        @unknown default:
            return .нет
        }
    }
}

// MARK: - Жесты вместе

extension МодельГабаритов: UIGestureRecognizerDelegate {
    /// Поворот двумя пальцами и сдвиг одним — не мешают друг другу.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Коробка

/**
 Коробка для сцены: полупрозрачное зелёное тело, двенадцать ярких рёбер и тёмный след на полу чуть шире коробки.
 Начало — в центре дна: масштаб по высоте растит коробку от пола вверх.
 */
@MainActor
enum КоробкаГабаритов {
    static let зелёный = UIColor(red: 0.30, green: 0.86, blue: 0.56, alpha: 1)

    static func собрать(_ размер: SIMD3<Float>) -> Entity {
        let рост = Entity()
        let ш = max(размер.x, 0.005)
        let в = max(размер.y, 0.005)
        let г = max(размер.z, 0.005)

        var грань = UnlitMaterial(color: зелёный)
        грань.blending = .transparent(opacity: .init(floatLiteral: 0.24))
        let тело = ModelEntity(mesh: .generateBox(width: ш, height: в, depth: г), materials: [грань])
        тело.position = SIMD3<Float>(0, в / 2, 0)
        рост.addChild(тело)

        var тень = UnlitMaterial(color: .black)
        тень.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        let след = ModelEntity(mesh: .generatePlane(width: ш + 0.04, depth: г + 0.04), materials: [тень])
        след.position = SIMD3<Float>(0, 0.002, 0)
        рост.addChild(след)

        let ребро = UnlitMaterial(color: зелёный)
        let толщина = min(Float(0.012), max(Float(0.004), min(ш, min(в, г)) * 0.08))
        let стойка = MeshResource.generateBox(width: толщина, height: в, depth: толщина)
        let поперёк = MeshResource.generateBox(width: ш + толщина, height: толщина, depth: толщина)
        let вглубь = MeshResource.generateBox(width: толщина, height: толщина, depth: г + толщина)
        var рёбра: [(сетка: MeshResource, место: SIMD3<Float>)] = []
        for x in [-ш / 2, ш / 2] {
            for z in [-г / 2, г / 2] {
                рёбра.append((стойка, SIMD3<Float>(x, в / 2, z)))
            }
        }
        for y in [толщина / 2, в] {
            for z in [-г / 2, г / 2] {
                рёбра.append((поперёк, SIMD3<Float>(0, y, z)))
            }
            for x in [-ш / 2, ш / 2] {
                рёбра.append((вглубь, SIMD3<Float>(x, y, 0)))
            }
        }
        for реброКоробки in рёбра {
            let кусок = ModelEntity(mesh: реброКоробки.сетка, materials: [ребро])
            кусок.position = реброКоробки.место
            рост.addChild(кусок)
        }
        return рост
    }
}

// MARK: - Подпись у ребра

/// Пилюля «Ш 60 см» поверх сцены: тёмная, с зелёной каймой, шрифт — по «Размеру текста». Для VoiceOver скрыта —
/// размеры читает сама сцена (описаниеСостояния).
final class ПодписьРебраГабаритов: UIView {
    private let надпись = UILabel()
    private var размерШрифта: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        alpha = 0
        backgroundColor = UIColor(white: 0.04, alpha: 0.74)
        layer.borderWidth = 1
        layer.borderColor = КоробкаГабаритов.зелёный.withAlphaComponent(0.9).cgColor
        надпись.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.systemFont(ofSize: 13, weight: .bold), maximumPointSize: 28)
        надпись.adjustsFontForContentSizeCategory = true
        надпись.textColor = .white
        надпись.textAlignment = .center
        addSubview(надпись)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    var текст: String = "" {
        didSet {
            guard текст != oldValue else { return }
            надпись.text = текст
            подогнать()
        }
    }

    /// Размер по тексту; центр остаётся на месте.
    private func подогнать() {
        размерШрифта = надпись.font.pointSize
        let нужно = надпись.sizeThatFits(CGSize(width: 600, height: 200))
        bounds = CGRect(x: 0, y: 0, width: ceil(нужно.width) + 18, height: ceil(нужно.height) + 8)
        layer.cornerRadius = bounds.height / 2
        надпись.frame = bounds.insetBy(dx: 9, dy: 4)
    }

    /// Шрифт сменился («Размер текста» поменяли на ходу) — подогнать заново.
    func следить() {
        if надпись.font.pointSize != размерШрифта { подогнать() }
    }
}

// MARK: - Вид для SwiftUI

/// ARView модели в SwiftUI. Вид живёт в модели — пересоздание представления не заводит вторую сессию.
struct СценаГабаритовAR: UIViewRepresentable {
    let модель: МодельГабаритов

    func makeUIView(context: Context) -> ARView {
        модель.создатьВид()
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
