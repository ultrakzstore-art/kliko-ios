import SwiftUI
import UIKit
import RealityKit
import ARKit
import QuickLook
import Combine
import simd

/**
 3D-ОБЗОР — ЭКРАН «3D» (владелец 14.10.2026: «5 разных фото, и ИИ сам собрал 3D любой вещи или авто»).

 Модель (USDZ из model3d, Listing3DModel.swift) качается в кэш на диске (КэшОбъёма) с долей на полосе; под ней — постер
 модели, если сервер его дал. Готово — RealityKit ARView без камеры (.nonAR): модель на круглом «подиуме», мягкий свет
 (основной сверху-спереди с тенью и слабый заполняющий сбоку), тень на подиуме. Палец по горизонтали — поворот модели,
 по вертикали — наклон взгляда; отпустили — поворот ещё немного катится и гаснет (инерция; при «Уменьшении движения» —
 нет). Щипок — ближе/дальше, двойное касание — вид как в начале (плавно; при «Уменьшении движения» — сразу).

 Модель любого размера вписывается в кадр: самая длинная сторона — 1 м сцены, низ — на подиуме. Реальный размер
 нужен только «В комнате»: AR Quick Look (QLPreviewController + ARQuickLookPreviewItem) ставит файл как есть; если
 сервер прислал все три размера — модель в USDZ в настоящих метрах, и масштабировать её щипком нельзя
 (allowsContentScaling = false); размеров нет — щипком можно. Кнопка «В комнате» — только где есть ARKit с поиском
 плоскостей (в симуляторе её нет, и код AR Quick Look туда не собирается).

 Лёгкий режим (РежимУстройства.лёгкий): без теней и HDR, один источник света. VoiceOver: сцена — один элемент
 «3D-модель вещи» со значением поворота; смахивание вверх/вниз — повернуть на 45°, действия «Сбросить вид»,
 «Приблизить», «Отдалить». Тёмная тема — фон сцены и подиум темнеют вместе с экраном.

 ARView живёт, пока открыто окно: его держит ДвижокОбъёма3D (@StateObject экрана ЭкранОбъёмаОбъявления), поэтому
 «3D» → «360°» → «3D» не грузит модель заново. Ушли из «3D» — загрузка отменяется (задача .task), ожидание RealityKit
 отпускается, инерция стоит; закрыли окно (✕) — вид разбирается сразу (жесты, якорь, подписка кадров).
 */
@MainActor
final class ДвижокОбъёма3D: NSObject, ObservableObject {
    enum Состояние: Equatable {
        case загрузка
        case готово
        case ошибка
    }

    let модель: МодельОбъёмаОбъявления
    @Published private(set) var состояние: Состояние = .загрузка
    /// Доля скачанного USDZ, 0…1; nil — сервер не сказал длину или файл уже на диске.
    @Published private(set) var доля: Double? = nil
    /// Локальный USDZ — для «В комнате».
    @Published private(set) var файл: URL? = nil
    /// Человек уже трогал модель — подсказку жестов можно убрать.
    @Published private(set) var трогали = false
    /// Поворот модели, целые градусы 0…359 — значение для VoiceOver.
    @Published private(set) var поворотГрадусов = 0

    private(set) var вид: ARView?
    private var якорь: AnchorEntity?
    private var поворот: Entity?
    private var камера: PerspectiveCamera?
    private var подиум: ModelEntity?
    private var подписка: (any Cancellable)?
    private var запросЗагрузки: (any Cancellable)?
    private var ожиданиеЗагрузки: CheckedContinuation<Entity, Error>?

    /* Вид сейчас и куда он плавно идёт (сброс, VoiceOver); палец меняет оба сразу. */
    private var рыскание: Float = 0
    private var рысканиеЦель: Float = 0
    private var наклон: Float = ДвижокОбъёма3D.наклонНачала
    private var наклонЦель: Float = ДвижокОбъёма3D.наклонНачала
    private var даль: Float = 3
    private var дальЦель: Float = 3
    private var дальОснова: Float = 3
    private var дальНачалаЩипка: Float = 3
    private var центр = SIMD3<Float>(0, 0.5, 0)
    /// Скорость поворота после броска пальцем, рад/с.
    private var скорость: Float = 0

    private let лёгкий: Bool
    private var тёмная: Bool

    private static let наклонНачала: Float = 0.28
    private static let наклонМин: Float = -0.05
    private static let наклонМакс: Float = 1.25
    /// Поле зрения камеры, градусы.
    private static let полеЗрения: Float = 38
    /// Радиан поворота на точку пути пальца.
    private static let чувствительность: Float = 0.011

    init(модель: МодельОбъёмаОбъявления, лёгкий: Bool, тёмная: Bool) {
        self.модель = модель
        self.лёгкий = лёгкий
        self.тёмная = тёмная
        super.init()
    }

    private var тихо: Bool { UIAccessibility.isReduceMotionEnabled || ДвижениеСайта.тихо }

    // MARK: Загрузка

    /// Скачать (или взять с диска) USDZ, открыть RealityKit'ом и поставить на подиум. Отмена задачи — тихо выйти.
    func загрузить() async {
        /* Экран снова на виду (вернулись из «В комнате») — модель уже стоит, второй раз не грузим. */
        guard состояние != .готово else { return }
        guard let адрес = модель.usdz else {
            состояние = .ошибка
            return
        }
        if состояние != .загрузка { состояние = .загрузка }
        доля = nil
        let локальный: URL
        do {
            локальный = try await КэшОбъёма.shared.файл(адрес, прогресс: { [weak self] д in
                Task { @MainActor [weak self] in
                    guard let self, self.состояние == .загрузка else { return }
                    self.доля = д
                }
            }, расширение: "usdz")
        } catch {
            if !Task.isCancelled && !(error is CancellationError) { состояние = .ошибка }
            return
        }
        guard !Task.isCancelled else { return }
        доля = nil
        do {
            let сущность = try await открыть(локальный)
            guard !Task.isCancelled else { return }
            поставить(сущность)
            файл = локальный
            состояние = .готово
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            /* RealityKit файл не открыл — он негодный: убрать с диска, чтобы «Повторить» скачал заново. */
            await КэшОбъёма.shared.забыть(адрес, расширение: "usdz")
            состояние = .ошибка
        }
    }

    /// «Повторить» после ошибки.
    func заново() {
        состояние = .загрузка
        доля = nil
    }

    /// Entity.loadAsync (iOS 13+) — не на главной нити; ответ приходит на главную. Отмена задачи отпускает ожидание сразу.
    private func открыть(_ файл: URL) async throws -> Entity {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (продолжить: CheckedContinuation<Entity, Error>) in
                ожиданиеЗагрузки = продолжить
                /* Ответ — на главную очередь явно: дальше он трогает сцену. */
                запросЗагрузки = Entity.loadAsync(contentsOf: файл)
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { [weak self] итог in
                        guard case .failure(let ошибка) = итог else { return }
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.отдатьЗагрузку(.failure(ошибка))
                        }
                    }, receiveValue: { [weak self] сущность in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.отдатьЗагрузку(.success(сущность))
                        }
                    })
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in self?.отдатьЗагрузку(.failure(CancellationError())) }
        }
    }

    private func отдатьЗагрузку(_ итог: Result<Entity, Error>) {
        guard let продолжить = ожиданиеЗагрузки else { return }
        ожиданиеЗагрузки = nil
        запросЗагрузки = nil
        продолжить.resume(with: итог)
    }

    // MARK: Сцена

    /// ARView без камеры: создаётся один раз, при первой готовой модели (до неё сцена не рисуется вовсе).
    func создатьВид() -> ARView {
        if let вид { return вид }
        #if targetEnvironment(simulator)
        let новый = ARView(frame: .zero)
        #else
        let новый = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        var параметры: ARView.RenderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain]
        if лёгкий { параметры.formUnion([.disableHDR, .disableGroundingShadows]) }
        новый.renderOptions.formUnion(параметры)
        новый.environment.background = .color(цветФона)
        #endif
        новый.isAccessibilityElement = false
        новый.backgroundColor = цветФона

        let якорь = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        новый.scene.addAnchor(якорь)
        let поворот = Entity()
        якорь.addChild(поворот)

        let подиум = ModelEntity(mesh: .generatePlane(width: 1, depth: 1, cornerRadius: 0.5),
                                 materials: [материалПодиума])
        подиум.position = SIMD3<Float>(0, -0.002, 0)
        якорь.addChild(подиум)

        /* Основной свет сверху-спереди-справа — с тенью на подиум; заполняющий слева-сзади — без тени, чтобы теневая
           сторона не проваливалась в черноту. В лёгком режиме — только основной, без тени. */
        let основной = DirectionalLight()
        основной.light.color = .white
        основной.light.intensity = лёгкий ? 2600 : 2200
        if !лёгкий {
            основной.shadow = DirectionalLightComponent.Shadow(maximumDistance: 6, depthBias: 1.5)
        }
        Self.навести(основной, из: SIMD3<Float>(0.9, 2.6, 1.7), на: SIMD3<Float>(0, 0, 0))
        якорь.addChild(основной)
        if !лёгкий {
            let заполняющий = DirectionalLight()
            заполняющий.light.color = .white
            заполняющий.light.intensity = 700
            Self.навести(заполняющий, из: SIMD3<Float>(-2.2, 1.4, -1.2), на: SIMD3<Float>(0, 0.3, 0))
            якорь.addChild(заполняющий)
        }

        let камера = PerspectiveCamera()
        камера.camera.fieldOfViewInDegrees = Self.полеЗрения
        якорь.addChild(камера)

        self.якорь = якорь
        self.поворот = поворот
        self.подиум = подиум
        self.камера = камера
        добавитьЖесты(новый)
        /* Кадр сцены приходит на главной нити: инерция и плавный сброс. */
        подписка = новый.scene.subscribe(to: SceneEvents.Update.self) { [weak self] событие in
            MainActor.assumeIsolated {
                self?.кадр(Float(событие.deltaTime))
            }
        }
        вид = новый
        применить()
        return новый
    }

    /// Модель — в держатель: самая длинная сторона 1 м, низ по центру — в начале координат (на подиуме).
    private func поставить(_ сущность: Entity) {
        _ = создатьВид()
        guard let поворот, let подиум else { return }
        for старый in Array(поворот.children) { старый.removeFromParent() }
        let держатель = Entity()
        держатель.addChild(сущность)
        let рамка = держатель.visualBounds(relativeTo: держатель)
        let размеры = рамка.extents
        let наибольший = max(размеры.x, max(размеры.y, размеры.z))
        let масштаб: Float = (наибольший.isFinite && наибольший > 0.000_1) ? 1 / наибольший : 1
        let низ = SIMD3<Float>(рамка.center.x, рамка.min.y, рамка.center.z)
        держатель.scale = SIMD3<Float>(repeating: масштаб)
        держатель.position = Self.конечно(низ) ? -низ * масштаб : SIMD3<Float>(0, 0, 0)
        поворот.addChild(держатель)

        let в = размеры * масштаб
        let высота = в.y.isFinite ? в.y : 1
        центр = SIMD3<Float>(0, высота / 2, 0)
        let радиус = max(0.3, 0.5 * simd_length(Self.конечно(в) ? в : SIMD3<Float>(1, 1, 1)))
        let половинаПоля = Self.полеЗрения * .pi / 360
        дальОснова = радиус / sin(половинаПоля) * 1.12
        let след = max(в.x.isFinite ? в.x : 1, в.z.isFinite ? в.z : 1)
        let поперёк = след * 1.5 + 0.25
        подиум.scale = SIMD3<Float>(поперёк, 1, поперёк)

        рыскание = 0
        рысканиеЦель = 0
        наклон = Self.наклонНачала
        наклонЦель = Self.наклонНачала
        даль = дальОснова
        дальЦель = дальОснова
        скорость = 0
        применить()
    }

    /// Поставить сущность в точку и повернуть «лицом» (−Z, как смотрят камера и свет) к цели; верх — ось Y мира. Своя
    /// математика вместо look(at:from:relativeTo:): у той в новых SDK есть перегрузка iOS 18 с тем же началом.
    private static func навести(_ сущность: Entity, из точка: SIMD3<Float>, на цель: SIMD3<Float>) {
        let отЦели = точка - цель
        let длина = simd_length(отЦели)
        сущность.position = точка
        guard длина > 0.000_1 else { return }
        let назад = отЦели / длина
        var вправо = simd_cross(SIMD3<Float>(0, 1, 0), назад)
        вправо = simd_length(вправо) < 0.000_1 ? SIMD3<Float>(1, 0, 0) : simd_normalize(вправо)
        let вверх = simd_cross(назад, вправо)
        сущность.orientation = simd_quatf(simd_float3x3(columns: (вправо, вверх, назад)))
    }

    private static func конечно(_ т: SIMD3<Float>) -> Bool {
        т.x.isFinite && т.y.isFinite && т.z.isFinite
    }

    /// Поворот модели и место камеры — по текущим значениям.
    private func применить() {
        поворот?.orientation = simd_quatf(angle: рыскание, axis: SIMD3<Float>(0, 1, 0))
        guard let камера else { return }
        let откуда = центр + SIMD3<Float>(0, sin(наклон) * даль, cos(наклон) * даль)
        Self.навести(камера, из: откуда, на: центр)
    }

    /// Значение поворота для VoiceOver — когда модель остановилась (не на каждом кадре броска: экран не перерисовывается
    /// с частотой сцены).
    private func отметитьПоворот() {
        let градусы = Int((рысканиеЦель * 180 / .pi).rounded())
        let норм = ((градусы % 360) + 360) % 360
        if норм != поворотГрадусов { поворотГрадусов = норм }
    }

    /// Кадр сцены: инерция поворота и плавный подход к цели. Ничего не менялось — сцену не трогаем.
    private func кадр(_ шаг: Float) {
        let время = min(max(шаг, 0), 0.05)
        guard время > 0 else { return }
        var менялось = false
        if скорость != 0 {
            рысканиеЦель += скорость * время
            рыскание = рысканиеЦель
            /* За секунду остаётся 4 % скорости. */
            скорость *= pow(0.04, время)
            if abs(скорость) < 0.05 {
                скорость = 0
                отметитьПоворот()
            }
            менялось = true
        }
        let подход = min(1, время * 9)
        if Self.подойти(&рыскание, рысканиеЦель, подход) { менялось = true }
        if Self.подойти(&наклон, наклонЦель, подход) { менялось = true }
        if Self.подойти(&даль, дальЦель, подход) { менялось = true }
        if менялось { применить() }
    }

    /// Шаг к цели; true — значение изменилось.
    private static func подойти(_ значение: inout Float, _ цель: Float, _ доля: Float) -> Bool {
        let разница = цель - значение
        if abs(разница) < 0.000_5 {
            guard значение != цель else { return false }
            значение = цель
            return true
        }
        значение += разница * доля
        return true
    }

    // MARK: Тема

    private var цветФона: UIColor { тёмная ? Theme.hex(0x1C1C26) : Theme.hex(0xF4F8F6) }

    private var материалПодиума: SimpleMaterial {
        SimpleMaterial(color: тёмная ? Theme.hex(0x2A2A36) : Theme.hex(0xE3ECE7), roughness: 0.95, isMetallic: false)
    }

    /// Тёмная тема включилась или выключилась, пока экран открыт.
    func сменитьТему(тёмная новая: Bool) {
        guard новая != тёмная else { return }
        тёмная = новая
        guard let вид else { return }
        вид.backgroundColor = цветФона
        #if !targetEnvironment(simulator)
        вид.environment.background = .color(цветФона)
        #endif
        подиум?.model?.materials = [материалПодиума]
    }

    // MARK: Жесты

    private func добавитьЖесты(_ вид: ARView) {
        let тяга = UIPanGestureRecognizer(target: self, action: #selector(жестТяги(_:)))
        тяга.maximumNumberOfTouches = 1
        тяга.delegate = self
        let щипок = UIPinchGestureRecognizer(target: self, action: #selector(жестЩипка(_:)))
        щипок.delegate = self
        let двойное = UITapGestureRecognizer(target: self, action: #selector(жестДвойного(_:)))
        двойное.numberOfTapsRequired = 2
        вид.addGestureRecognizer(тяга)
        вид.addGestureRecognizer(щипок)
        вид.addGestureRecognizer(двойное)
    }

    @objc(klikoObjem3DPan:)
    private func жестТяги(_ жест: UIPanGestureRecognizer) {
        guard let вид, состояние == .готово else { return }
        switch жест.state {
        case .began:
            скорость = 0
            отметитьКасание()
        case .changed:
            let сдвиг = жест.translation(in: вид)
            жест.setTranslation(.zero, in: вид)
            /* Палец вправо — передняя сторона уходит вправо (как вертушка под пальцем); вниз — смотрим сверху. Поворот
               физический, в RTL не зеркалится. */
            рысканиеЦель += Float(сдвиг.x) * Self.чувствительность
            рыскание = рысканиеЦель
            наклонЦель = min(Self.наклонМакс, max(Self.наклонМин, наклонЦель + Float(сдвиг.y) * 0.006))
            наклон = наклонЦель
            применить()
        case .ended:
            let бросок = Float(жест.velocity(in: вид).x) * Self.чувствительность
            скорость = тихо ? 0 : min(12, max(-12, бросок))
            if скорость == 0 { отметитьПоворот() }
        default:
            break
        }
    }

    @objc(klikoObjem3DPinch:)
    private func жестЩипка(_ жест: UIPinchGestureRecognizer) {
        guard состояние == .готово else { return }
        switch жест.state {
        case .began:
            скорость = 0
            дальНачалаЩипка = дальЦель
            отметитьКасание()
        case .changed:
            let масштаб = max(0.2, Float(жест.scale))
            дальЦель = ограничитьДаль(дальНачалаЩипка / масштаб)
            даль = дальЦель
            применить()
        default:
            break
        }
    }

    @objc(klikoObjem3DDoubleTap:)
    private func жестДвойного(_ жест: UITapGestureRecognizer) {
        guard состояние == .готово, жест.state == .ended else { return }
        отметитьКасание()
        сбросить()
    }

    private func ограничитьДаль(_ д: Float) -> Float {
        min(дальОснова * 2.2, max(дальОснова * 0.45, д))
    }

    private func отметитьКасание() {
        if !трогали { трогали = true }
    }

    // MARK: Действия (VoiceOver и кнопки)

    /// Вид как в начале: плавно, при «Уменьшении движения» — сразу. Поворот — к ближайшему целому обороту.
    func сбросить() {
        скорость = 0
        let обороты = (рысканиеЦель / (2 * .pi)).rounded()
        рысканиеЦель = обороты * 2 * .pi
        наклонЦель = Self.наклонНачала
        дальЦель = дальОснова
        if тихо {
            рыскание = рысканиеЦель
            наклон = наклонЦель
            даль = дальЦель
        }
        применить()
        отметитьПоворот()
    }

    /// Повернуть на 45° (VoiceOver): вперёд — как палец вправо.
    func повернуть(вперёд: Bool) {
        скорость = 0
        рысканиеЦель += (вперёд ? 1 : -1) * .pi / 4
        if тихо { рыскание = рысканиеЦель }
        отметитьКасание()
        применить()
        отметитьПоворот()
    }

    func приблизить(_ ближе: Bool) {
        скорость = 0
        дальЦель = ограничитьДаль(дальЦель * (ближе ? 0.8 : 1.25))
        if тихо { даль = дальЦель }
        применить()
    }

    // MARK: Разбор

    /// Экран ушёл из виду (закрыли, сменили на «360°», сверху встал AR Quick Look): инерция стоит. Сам вид и сцену
    /// отпускает освобождение движка вместе с экраном; вернулись — всё на месте.
    func остановить() {
        скорость = 0
    }

    /// Ушли с экрана насовсем: подписка кадров, жесты, якорь — отпустить сразу, ожидание RealityKit — отпустить.
    func разобрать() {
        подписка?.cancel()
        подписка = nil
        запросЗагрузки?.cancel()
        отдатьЗагрузку(.failure(CancellationError()))
        скорость = 0
        guard let вид else { return }
        for жест in вид.gestureRecognizers ?? [] { вид.removeGestureRecognizer(жест) }
        if let якорь { вид.scene.removeAnchor(якорь) }
        якорь = nil
        поворот = nil
        камера = nil
        подиум = nil
    }
}

extension ДвижокОбъёма3D: UIGestureRecognizerDelegate {
    /// Поворот одним пальцем и щипок — не мешают друг другу: начали крутить, второй палец сразу приближает.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// ARView движка в SwiftUI.
struct СценаОбъёма3D: UIViewRepresentable {
    let движок: ДвижокОбъёма3D

    func makeUIView(context: Context) -> ARView {
        движок.создатьВид()
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

// MARK: - Вид «3D»

/// Сцена, загрузка с долей, ошибка с «Повторить», подсказка жестов и «В комнате».
struct ПросмотрМодели3D: View {
    let модель: МодельОбъёмаОбъявления
    /// Страница объявления — «Поделиться» внутри AR Quick Look.
    let страница: URL?
    /// Движок держит экран (ЭкранОбъёмаОбъявления): переключились на «360°» и обратно — модель уже стоит.
    @ObservedObject var движок: ДвижокОбъёма3D
    @State private var попытка = 0
    @Environment(\.colorScheme) private var схема

    init(модель: МодельОбъёмаОбъявления, страница: URL?, движок: ДвижокОбъёма3D) {
        self.модель = модель
        self.страница = страница
        self.движок = движок
    }

    private func т(_ ключ: String) -> String { ОбъёмText.т(ключ) }

    var body: some View {
        ZStack {
            switch движок.состояние {
            case .загрузка:
                ЗагрузкаОбъёма(постер: модель.постер, доля: движок.доля, текст: т("o3_loading"))
            case .ошибка:
                ОшибкаОбъёма(заголовок: т("o3_error")) {
                    движок.заново()
                    попытка += 1
                }
            case .готово:
                сцена
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
        .animation(ДвижениеСайта.смена, value: движок.состояние)
        .task(id: попытка) { await движок.загрузить() }
        .onAppear { движок.сменитьТему(тёмная: схема == .dark) }
        .onChange(of: схема) { _, новая in движок.сменитьТему(тёмная: новая == .dark) }
        .onDisappear { движок.остановить() }
    }

    private var сцена: some View {
        СценаОбъёма3D(движок: движок)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(т("o3_scene_a11y"))
            .accessibilityValue(String(format: т("o3_turn_value"), String(движок.поворотГрадусов)))
            .accessibilityHint(т("o3_scene_hint"))
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAdjustableAction { направление in
                switch направление {
                case .increment: движок.повернуть(вперёд: true)
                case .decrement: движок.повернуть(вперёд: false)
                @unknown default: break
                }
            }
            .accessibilityActions {
                Button(т("o3_reset")) { движок.сбросить() }
                Button(т("o3_zoom_in")) { движок.приблизить(true) }
                Button(т("o3_zoom_out")) { движок.приблизить(false) }
            }
            .transition(.opacity)
    }

    /// Подсказка жестов (до первого касания) и «В комнате» (когда файл на месте и есть AR).
    private var низ: some View {
        VStack(spacing: 10) {
            if движок.состояние == .готово && !движок.трогали {
                ПодсказкаОбъёма(значок: "hand.draw", текст: т("o3_hint_3d"))
                    .transition(.opacity)
            }
            if let файл = движок.файл, движок.состояние == .готово, ОкноОбъёма.комнатаДоступна {
                КнопкаКомнатыОбъёма(размерыИзвестны: модель.размерыИзвестны) {
                    ОткликСайта.выбор()
                    ОкноОбъёма.вКомнате(файл: файл, модель: модель, страница: страница)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(ДвижениеСайта.появление, value: движок.трогали)
    }
}

/// «В комнате»: большая зелёная кнопка во всю ширину.
private struct КнопкаКомнатыОбъёма: View {
    let размерыИзвестны: Bool
    let действие: () -> Void
    @ScaledMetric(relativeTo: .body) private var значок: CGFloat = 20

    /// Явный init: поэлементный был бы закрытым из-за закрытого значка.
    init(размерыИзвестны: Bool, действие: @escaping () -> Void) {
        self.размерыИзвестны = размерыИзвестны
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: "arkit")
                    .font(.system(size: значок, weight: .semibold))
                    .accessibilityHidden(true)
                Text(ОбъёмText.т("o3_room"))
                    .font(.headline.weight(.heavy))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Theme.панельСвязиКонец.opacity(0.28), radius: 10, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityHint(ОбъёмText.т(размерыИзвестны ? "o3_room_hint" : "o3_room_hint_scaled"))
    }
}

// MARK: - «В комнате» — AR Quick Look

#if !targetEnvironment(simulator)
/**
 Источник AR Quick Look: один файл USDZ. QLPreviewController держит источник слабо — держим сами, пока окно не
 закроют (previewControllerDidDismiss).
 */
final class КомнатаОбъёма: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    @MainActor private static var текущая: КомнатаОбъёма?
    private let элемент: ARQuickLookPreviewItem

    private init(элемент: ARQuickLookPreviewItem) {
        self.элемент = элемент
        super.init()
    }

    /// Показать модель через камеру. Размеры известны — модель в USDZ в настоящих метрах, щипком её не растянуть.
    @MainActor
    static func показать(файл: URL, размерыИзвестны: Bool, страница: URL?, поверх: UIViewController) {
        let элемент = ARQuickLookPreviewItem(fileAt: файл)
        элемент.allowsContentScaling = !размерыИзвестны
        if let страница { элемент.canonicalWebPageURL = страница }
        let источник = КомнатаОбъёма(элемент: элемент)
        текущая = источник
        let окно = QLPreviewController()
        окно.dataSource = источник
        окно.delegate = источник
        поверх.present(окно, animated: true)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        элемент
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        Task { @MainActor in КомнатаОбъёма.текущая = nil }
    }
}
#endif
