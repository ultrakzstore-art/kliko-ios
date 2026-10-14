import SwiftUI
import UIKit
import RealityKit
import ARKit
import Combine
import simd

/**
 «ПОМЕСТИТСЯ ЛИ?» — ЛИНЕЙКА AR (владелец 14.10.2026: «добавь линейку для габаритных вещей и главное чтобы он работал»).

 Как «Рулетка» iPhone, только рядом с вещью: в том же окне «Поместится ли?» сверху переключатель «Коробка / Линейка»
 (РежимГабаритов, МодельГабаритов.сменитьРежим). Сессия ARKit и ARView — те же, что у коробки (второй сессии нет):
 в режиме линейки коробка спрятана (место и поворот помнит), в режиме коробки спрятаны отрезки.

 Прицел — в центре экрана. Каждый кадр из центра идёт луч ARKit (raycast, выравнивание любое — пол, стена, столешница,
 бок шкафа): по найденным плоскостям и по прикидке (.estimatedPlane); прикидка ближе плоскости больше чем на 5 см —
 берём её (на полу стоит тумба, а плоскость пола — за ней). «+» ставит начало, второе «+» — конец: отрезок с подписью
 длины (целые сантиметры, от метра — «1 м 25 см»). Отрезков может быть несколько (до двенадцати); «Отменить» убирает
 незаконченное начало или последний отрезок, «Очистить» — всё.

 Стабильность. Пока слежение ARKit не «норма» — ничего не ставим (подсказка «Медленно ведите телефоном»). Точки —
 якоря ARAnchor в сессии (AnchorEntity(anchor:)): ARKit уточняет карту мира — якоря едут вместе с ней, а не дрейфуют;
 линии каждый кадр заново протягиваются между якорями. Подписи — обычные UIView поверх сцены (ПодписьРебраГабаритов,
 как у коробки): всегда лицом к камере, шрифт — по «Размеру текста».

 Лидар (ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) или кадры .sceneDepth): в режиме линейки
 сессия включает sceneReconstruction — луч ложится на настоящую поверхность. Подпись точности честная: «Точность ±1 см
 (лидар)» или «Точность ±2–4 см — оставьте запас»; порог «впритык» — по верхней границе погрешности (2 и 4 см).

 «Сравнить с вещью»: последний отрезок — с размером вещи (авто — ближайший к замеру; чипами — ширина, высота, глубина;
 «Проём двери» — меньшее из ширины и глубины: вещь проносят боком). Итог — «Ниша 62 см · вещь 60 см · запас 2 см ✓»
 зелёным, «впритык» янтарным (запас меньше погрешности замера), «не хватает 3 см ✗» малиновым.

 Размеры вещи линейке не нужны: без них камера идёт, просто нет сравнения. Замер вещи для подачи (замерВещи,
 «Измерить в AR» в блоке «Габариты, см»): три отрезка — ширина, высота, глубина («Ш 60 см»…), свои подсказки, «Готово»
 отдаёт их в поля (ОкноГабаритов.открытьЗамер).

 «Снимок» — как у коробки: ARView.snapshot, поверх — подписи отрезков и плашка «Kliko.kz · …»
 (МодельГабаритов.собрать). Всё здесь — на главной нити; склейка снимка — в фоне. ARKit в симуляторе не работает: места
 с сессией и лучом — под #if !targetEnvironment(simulator) (окна с камерой там и нет, ОкноГабаритов.доступно).
 */
extension Config {
    /// Линейка в «Поместится ли?»: переключатель «Коробка / Линейка» под заголовком. false — только коробка.
    static let габаритыЛинейка = true
}

/// Что сейчас в окне «Поместится ли?»: вещь (фото или 3D-модель, FitBoxItem.swift), коробка вещи или линейка.
enum РежимГабаритов: Equatable, Sendable {
    case вещь
    case коробка
    case линейка
}

/// С каким размером вещи сравнить последний отрезок.
enum ГабаритСравненияЛинейки: String, CaseIterable, Identifiable, Sendable {
    /// Ближайший к замеру из ширины, высоты и глубины.
    case авто
    case ширина
    case высота
    case глубина
    /// Проём двери: меньшее из ширины и глубины — вещь проносят боком.
    case проём

    var id: String { rawValue }
}

/// Итог сравнения отрезка с вещью, сантиметры.
struct СравнениеЛинейки: Equatable, Sendable {
    enum Итог: Equatable, Sendable {
        case хватает
        case впритык
        case неХватает
    }

    let замер: Double
    let вещь: Double
    /// Чем сравнивали (авто здесь уже разрешён в ширину, высоту или глубину).
    let габарит: ГабаритСравненияЛинейки
    /// Размер выбран сам — ближайший к замеру.
    let авто: Bool
    /// Погрешность замера, см: запас меньше неё — «впритык».
    let погрешность: Double

    var запас: Double { замер - вещь }

    var итог: Итог {
        if запас < 0 { return .неХватает }
        return запас < погрешность ? .впритык : .хватает
    }

    static func сравнить(замер: Double, габариты г: ГабаритыВещи, выбор: ГабаритСравненияЛинейки,
                         погрешность: Double) -> СравнениеЛинейки {
        var габарит = выбор
        let вещь: Double
        switch выбор {
        case .ширина:
            вещь = г.ширина
        case .высота:
            вещь = г.высота
        case .глубина:
            вещь = г.глубина
        case .проём:
            вещь = min(г.ширина, г.глубина)
        case .авто:
            let варианты: [(габарит: ГабаритСравненияЛинейки, см: Double)] = [
                (.ширина, г.ширина), (.высота, г.высота), (.глубина, г.глубина)
            ]
            let ближний = варианты.min { abs($0.см - замер) < abs($1.см - замер) } ?? (.ширина, г.ширина)
            габарит = ближний.габарит
            вещь = ближний.см
        }
        return СравнениеЛинейки(замер: замер, вещь: вещь, габарит: габарит, авто: выбор == .авто,
                                погрешность: погрешность)
    }

    /// «Ниша 62 см · вещь (ширина) 60 см · запас 2 см ✓» (у проёма — «Проём 70 см · вещь 55 см · …»).
    var строка: String {
        let т = ЛинейкаГабаритовText.self
        let место = т.т(габарит == .проём ? "fr_opening" : "fr_niche", т.длина(замер))
        let хвост = итог == .неХватает
            ? т.т("fr_short", т.длина(-запас)) + " ✗"
            : т.т("fr_spare", т.длина(запас)) + " ✓"
        return место + " · " + размерВещи + " · " + хвост
    }

    /// «вещь (глубина) 55 см»: с каким размером сравнили — и на карточке, и на снимке, и в озвучке (авто мог выбрать
    /// не тот, что мерили). У проёма имя не нужно — он назван в начале строки.
    private var размерВещи: String {
        let т = ЛинейкаГабаритовText.self
        let имя: String
        switch габарит {
        case .ширина: имя = т.т("fr_dim_w")
        case .высота: имя = т.т("fr_dim_h")
        case .глубина: имя = т.т("fr_dim_d")
        case .проём, .авто: return т.т("fr_item", т.длина(вещь))
        }
        return т.т("fr_item_dim", имя, т.длина(вещь))
    }

    /// Для VoiceOver: то же без значков и с выводом «Поместится» / «Не поместится».
    var озвучка: String {
        let т = ЛинейкаГабаритовText.self
        let место = т.т(габарит == .проём ? "fr_opening" : "fr_niche", т.длина(замер))
        let размер = размерВещи
        switch итог {
        case .хватает:
            return место + ", " + размер + ", " + т.т("fr_spare", т.длина(запас)) + ". " + т.т("fr_fits")
        case .впритык:
            return место + ", " + размер + ", " + т.т("fr_spare", т.длина(запас)) + ". " + т.т("fr_tight")
        case .неХватает:
            return место + ", " + размер + ", " + т.т("fr_short", т.длина(-запас)) + ". " + т.т("fr_no_fit")
        }
    }
}

/// То, что меняется каждый кадр: есть ли поверхность под прицелом и длина тянущегося отрезка. Отдельно от
/// ЛинейкаГабаритов — чтобы кадр перерисовывал только прицел и подсказку, а не всю панель.
@MainActor
final class ЖивоеЛинейкиГабаритов: ObservableObject {
    @Published fileprivate(set) var цель = false
    /// Длина от поставленного начала до прицела, см; nil — начала нет или прицел ни на что не смотрит.
    @Published fileprivate(set) var длина: Int? = nil
}

@MainActor
final class ЛинейкаГабаритов: ObservableObject {
    /// Наибольшее число отрезков: каждый — два якоря ARKit, линия и подпись.
    static let предел = 12
    private static let имяЯкоря = "kliko.ruler"
    /// Янтарный («впритык») и малиновый («не хватает») для тёмной камеры: светлее Theme.малиновый — текст читается.
    static let янтарь = UIColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1)
    static let малиновый = UIColor(red: 0.98, green: 0.44, blue: 0.52, alpha: 1)

    /// Есть ли лидар: сетка сцены или кадры глубины.
    static let лидар: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #endif
    }()

    /// Порог «впритык», см: запас меньше него — янтарём. Верхняя граница погрешности, а не нижняя: без лидара — 4
    /// («±2–4 см»), с лидаром — 2 (по ±1 см на каждом конце). Ложное «влезет» для ниши хуже ложного «впритык».
    static var погрешность: Double { лидар ? 2 : 4 }

    /// «Точность ±1 см (лидар)» / «Точность ±2–4 см — оставьте запас».
    static var точность: String { ЛинейкаГабаритовText.т(лидар ? "fr_acc_lidar" : "fr_acc") }

    let живое: ЖивоеЛинейкиГабаритов

    @Published private(set) var включена = false
    @Published private(set) var слежение: СлежениеГабаритов = .запуск
    /// Начало отрезка поставлено, конца ещё нет.
    @Published private(set) var начато = false
    @Published private(set) var отрезков = 0
    /// Длина последнего отрезка, см.
    @Published private(set) var последний: Int? = nil
    @Published private(set) var габариты: ГабаритыВещи? = nil
    @Published private(set) var снимаем = false
    /// Короткое сообщение под подсказкой (само гаснет).
    @Published private(set) var сообщение: String? = nil
    @Published var сравнивать = true {
        didSet { if сравнивать != oldValue { раскрасить() } }
    }
    @Published var выбор: ГабаритСравненияЛинейки = .авто {
        didSet { if выбор != oldValue { раскрасить() } }
    }

    private struct Точка {
        /// Якорь сессии (в симуляторе — nil).
        let якорь: ARAnchor?
        let сущность: AnchorEntity
        /// Где поставили: пока RealityKit не привязал сущность к якорю, линия идёт отсюда.
        let место: SIMD3<Float>
    }

    private struct Отрезок {
        let начало: Точка
        let конец: Точка
        let линия: ModelEntity
        let подпись: ПодписьРебраГабаритов
        var см: Int
    }

    private weak var вид: ARView?
    /// Линии и точка прицела — дети неподвижного якоря в начале мира.
    private var корень: AnchorEntity?
    private var прицел: ModelEntity?
    private var тяга: ModelEntity?
    private var сеткаТочки: MeshResource?
    private var сеткаЛинии: MeshResource?
    private var начало: Точка? = nil
    private var отрезки: [Отрезок] = []
    private var попадание: SIMD3<Float>? = nil
    private var подписка: (any Cancellable)?
    private var задачаСообщения: Task<Void, Never>? = nil
    private var послеСнимка: ((СнимокГабаритов?) -> Void)? = nil
    /// Сколько обновлений сцены ждать до snapshot (прицел уже спрятан); 0 — не ждём.
    private var кадровДоСнимка = 0
    /// Снимок, если сцена не обновляется (сессия встала).
    private var запаснойСнимок: Task<Void, Never>? = nil

    /// Замер вещи для подачи (МодельГабаритов.замерВещи): три отрезка — ширина, высота, глубина; подписи с буквой
    /// размера, свои подсказки, без сравнения.
    let замерВещи: Bool

    init(замерВещи: Bool = false) {
        живое = ЖивоеЛинейкиГабаритов()
        self.замерВещи = замерВещи
    }

    /// Сколько отрезков можно: у замера вещи — три (Ш, В, Г).
    private var пределОтрезков: Int { замерВещи ? 3 : Self.предел }

    /// Замер вещи: первые три отрезка — ширина, высота, глубина, см (не мерили — nil).
    var замеры: (ширина: Double?, высота: Double?, глубина: Double?) {
        func см(_ номер: Int) -> Double? { отрезки.indices.contains(номер) ? Double(отрезки[номер].см) : nil }
        return (см(0), см(1), см(2))
    }

    /// Имя размера отрезка в замере вещи: «Ширина», «Высота», «Глубина».
    private func имяРоли(_ номер: Int) -> String {
        ГабаритыText.т(номер == 0 ? "fb_w" : (номер == 1 ? "fb_h" : "fb_d"))
    }

    private func т(_ ключ: String) -> String { ЛинейкаГабаритовText.т(ключ) }

    // MARK: Связь с моделью коробки

    /// ARView модели: свой якорь в начале мира, прицел, тянущаяся линия и подписка на кадры сцены.
    func подключить(к вид: ARView) {
        guard self.вид !== вид else { return }
        отключить()
        self.вид = вид
        let корень = AnchorEntity(world: SIMD3<Float>(0, 0, 0))
        let сеткаТочки = MeshResource.generateSphere(radius: 0.007)
        let сеткаЛинии = MeshResource.generateBox(width: 0.004, height: 0.004, depth: 1)
        let прицел = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.005),
                                 materials: [UnlitMaterial(color: .white)])
        прицел.isEnabled = false
        корень.addChild(прицел)
        var полупрозрачный = UnlitMaterial(color: .white)
        полупрозрачный.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        let тяга = ModelEntity(mesh: сеткаЛинии, materials: [полупрозрачный])
        тяга.isEnabled = false
        корень.addChild(тяга)
        корень.isEnabled = включена
        вид.scene.addAnchor(корень)
        self.корень = корень
        self.прицел = прицел
        self.тяга = тяга
        self.сеткаТочки = сеткаТочки
        self.сеткаЛинии = сеткаЛинии
        /* Обновление сцены RealityKit приходит на главной нити. */
        подписка = вид.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.кадр()
            }
        }
    }

    /// Окно закрывают — отпустить якоря, линии, подписи и подписку сразу.
    func отключить() {
        подписка?.cancel()
        подписка = nil
        /* Снимок ещё не сделан — окно закрывают, отдавать его некому. */
        запаснойСнимок?.cancel()
        запаснойСнимок = nil
        if кадровДоСнимка > 0 {
            кадровДоСнимка = 0
            послеСнимка = nil
            снимаем = false
        }
        убратьВсё()
        корень?.removeFromParent()
        корень = nil
        прицел = nil
        тяга = nil
        вид = nil
        задачаСообщения?.cancel()
    }

    /// Режим линейки включили или выключили: показать или спрятать всё своё.
    func включить(_ да: Bool) {
        if включена != да { включена = да }
        корень?.isEnabled = да
        if let начало { начало.сущность.isEnabled = да }
        for отрезок in отрезки {
            отрезок.начало.сущность.isEnabled = да
            отрезок.конец.сущность.isEnabled = да
            if !да { отрезок.подпись.isHidden = true }
        }
        if !да {
            прицел?.isEnabled = false
            тяга?.isEnabled = false
            попадание = nil
            if живое.цель { живое.цель = false }
            if живое.длина != nil { живое.длина = nil }
        }
    }

    func слежениеПришло(_ новое: СлежениеГабаритов) {
        if слежение != новое { слежение = новое }
    }

    func задатьГабариты(_ новые: ГабаритыВещи?) {
        guard габариты != новые else { return }
        габариты = новые
        раскрасить()
    }

    /// Сессию перезапустили с .removeExistingAnchors (начало мира переехало): старые отрезки висели бы где попало.
    func сброситьСцену() {
        убратьВсё()
    }

    // MARK: Точки и отрезки

    /// «+»: начало отрезка, а если оно уже есть — конец.
    func добавить() {
        guard включена, let вид else { return }
        guard слежение == .норма else {
            показать(т("fr_scan"))
            ОткликСайта.предупреждение()
            return
        }
        guard let точка = луч(вид) ?? попадание else {
            показать(т("fr_no_surface"))
            ОткликСайта.предупреждение()
            return
        }
        guard let начало else {
            guard отрезки.count < пределОтрезков else {
                показать(т(замерВещи ? "fr_meas_ready" : "fr_limit"))
                ОткликСайта.предупреждение()
                return
            }
            self.начало = новаяТочка(точка, вид: вид)
            начато = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIAccessibility.post(notification: .announcement, argument: т("fr_start_done"))
            return
        }
        let а = Self.место(начало)
        let см = Self.сантиметры(а, точка)
        guard см >= 1, let сеткаЛинии, let корень else {
            показать(т("fr_too_short"))
            return
        }
        let конец = новаяТочка(точка, вид: вид)
        let линия = ModelEntity(mesh: сеткаЛинии, materials: [UnlitMaterial(color: .white)])
        корень.addChild(линия)
        Self.протянуть(линия, от: а, до: точка)
        let подпись = ПодписьРебраГабаритов(frame: .zero)
        подпись.alpha = 1
        подпись.isHidden = true
        вид.addSubview(подпись)
        отрезки.append(Отрезок(начало: начало, конец: конец, линия: линия, подпись: подпись, см: см))
        self.начало = nil
        начато = false
        отрезков = отрезки.count
        последний = см
        тяга?.isEnabled = false
        if живое.длина != nil { живое.длина = nil }
        раскрасить()
        var озвучка = замерВещи
            ? имяРоли(отрезки.count - 1) + ": " + ЛинейкаГабаритовText.длина(см)
            : ЛинейкаГабаритовText.т("fr_seg_done", ЛинейкаГабаритовText.длина(см))
        if замерВещи && отрезки.count >= пределОтрезков { озвучка += ". " + т("fr_meas_ready") }
        if let сравнение {
            озвучка += ". " + сравнение.озвучка
            if сравнение.итог == .неХватает { ОткликСайта.предупреждение() } else { ОткликСайта.успех() }
        } else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        UIAccessibility.post(notification: .announcement, argument: озвучка)
    }

    /// «Отменить»: незаконченное начало («Начало отрезка убрано»), а нет его — последний отрезок целиком («Отрезок
    /// 62 см убран»): озвучка говорит, что именно ушло.
    func отменить() {
        let весть: String
        if let начало {
            убрать(начало)
            self.начало = nil
            начато = false
            тяга?.isEnabled = false
            if живое.длина != nil { живое.длина = nil }
            весть = т("fr_undone")
        } else if let отрезок = отрезки.popLast() {
            убрать(отрезок)
            отрезков = отрезки.count
            последний = отрезки.last?.см
            раскрасить()
            весть = ЛинейкаГабаритовText.т("fr_seg_undone", ЛинейкаГабаритовText.длина(отрезок.см))
        } else {
            return
        }
        ОткликСайта.выбор()
        UIAccessibility.post(notification: .announcement, argument: весть)
    }

    /// «Очистить»: все отрезки и незаконченное начало.
    func очистить() {
        guard начало != nil || !отрезки.isEmpty else { return }
        убратьВсё()
        ОткликСайта.выбор()
        UIAccessibility.post(notification: .announcement, argument: т("fr_cleared"))
    }

    private func убратьВсё() {
        if let начало { убрать(начало) }
        начало = nil
        for отрезок in отрезки { убрать(отрезок) }
        отрезки = []
        тяга?.isEnabled = false
        прицел?.isEnabled = false
        попадание = nil
        if начато { начато = false }
        if отрезков != 0 { отрезков = 0 }
        if последний != nil { последний = nil }
        if живое.длина != nil { живое.длина = nil }
    }

    private func новаяТочка(_ место: SIMD3<Float>, вид: ARView) -> Точка {
        #if targetEnvironment(simulator)
        let якорь: ARAnchor? = nil
        let сущность = AnchorEntity(world: место)
        #else
        var матрица = matrix_identity_float4x4
        матрица.columns.3 = SIMD4<Float>(место.x, место.y, место.z, 1)
        let новый = ARAnchor(name: Self.имяЯкоря, transform: матрица)
        вид.session.add(anchor: новый)
        let якорь: ARAnchor? = новый
        let сущность = AnchorEntity(anchor: новый)
        #endif
        if let сеткаТочки {
            let шарик = ModelEntity(mesh: сеткаТочки, materials: [UnlitMaterial(color: КоробкаГабаритов.зелёный)])
            сущность.addChild(шарик)
        }
        сущность.isEnabled = включена
        вид.scene.addAnchor(сущность)
        return Точка(якорь: якорь, сущность: сущность, место: место)
    }

    private func убрать(_ точка: Точка) {
        точка.сущность.removeFromParent()
        #if !targetEnvironment(simulator)
        if let якорь = точка.якорь { вид?.session.remove(anchor: якорь) }
        #endif
    }

    private func убрать(_ отрезок: Отрезок) {
        убрать(отрезок.начало)
        убрать(отрезок.конец)
        отрезок.линия.removeFromParent()
        отрезок.подпись.removeFromSuperview()
    }

    // MARK: Кадр

    /// Каждый кадр сцены: луч из центра, прицел на поверхности, тянущаяся линия, линии и подписи отрезков.
    private func кадр() {
        if кадровДоСнимка > 0 {
            кадровДоСнимка -= 1
            if кадровДоСнимка == 0 { сделатьСнимок() }
        }
        guard включена, let вид, вид.bounds.width > 0 else { return }
        let точка = слежение == .норма ? луч(вид) : nil
        попадание = точка
        if живое.цель != (точка != nil) { живое.цель = точка != nil }
        /* На время снимка прицел и тянущаяся линия спрятаны — в кадр попадают только отрезки. */
        let видно = !снимаем
        if let прицел {
            if let точка, видно {
                прицел.position = точка
                if !прицел.isEnabled { прицел.isEnabled = true }
            } else if прицел.isEnabled {
                прицел.isEnabled = false
            }
        }
        if let начало, let точка, let тяга, видно {
            let а = Self.место(начало)
            Self.протянуть(тяга, от: а, до: точка)
            let см = Self.сантиметры(а, точка)
            if живое.длина != см { живое.длина = см }
        } else {
            if тяга?.isEnabled == true { тяга?.isEnabled = false }
            if живое.длина != nil { живое.длина = nil }
        }
        обновитьОтрезки(вид)
    }

    private func обновитьОтрезки(_ вид: ARView) {
        guard !отрезки.isEmpty else { return }
        let камера = вид.cameraTransform.matrix
        let глаз = SIMD3<Float>(камера.columns.3.x, камера.columns.3.y, камера.columns.3.z)
        let вперёд = -SIMD3<Float>(камера.columns.2.x, камера.columns.2.y, камера.columns.2.z)
        let поле = вид.bounds.insetBy(dx: -20, dy: -20)
        var последнийСменился = false
        for номер in отрезки.indices {
            let а = Self.место(отрезки[номер].начало)
            let б = Self.место(отрезки[номер].конец)
            Self.протянуть(отрезки[номер].линия, от: а, до: б)
            /* ARKit уточнил карту мира — якоря сдвинулись, длина могла смениться на сантиметр. */
            let см = Self.сантиметры(а, б)
            if см != отрезки[номер].см {
                отрезки[номер].см = см
                if номер == отрезки.count - 1 {
                    последнийСменился = true
                } else {
                    подписать(номер, сравнение: nil)
                }
            }
            let подпись = отрезки[номер].подпись
            подпись.следить()
            let середина = (а + б) / 2
            if simd_dot(середина - глаз, вперёд) > 0.03, let наЭкране = вид.project(середина),
               поле.contains(наЭкране) {
                подпись.center = наЭкране
                if подпись.isHidden { подпись.isHidden = false }
            } else if !подпись.isHidden {
                подпись.isHidden = true
            }
        }
        if последнийСменился {
            последний = отрезки.last?.см
            раскрасить()
        }
    }

    /// Луч из центра экрана: найденные плоскости и прикидка ARKit, любое выравнивание. nil — поверхности не видно.
    private func луч(_ вид: ARView) -> SIMD3<Float>? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard вид.bounds.width > 0 else { return nil }
        let центр = CGPoint(x: вид.bounds.midX, y: вид.bounds.midY)
        func место(_ попадание: ARRaycastResult?) -> SIMD3<Float>? {
            guard let попадание else { return nil }
            let столбец = попадание.worldTransform.columns.3
            return SIMD3<Float>(столбец.x, столбец.y, столбец.z)
        }
        let точное = место(вид.raycast(from: центр, allowing: .existingPlaneGeometry, alignment: .any).first)
        let прикидка = место(вид.raycast(from: центр, allowing: .estimatedPlane, alignment: .any).first)
        guard let точное else { return прикидка }
        guard let прикидка else { return точное }
        /* Найденная плоскость точнее прикидки, но прикидка заметно ближе — между камерой и плоскостью что-то стоит. */
        let глаз = вид.cameraTransform.translation
        return simd_distance(прикидка, глаз) < simd_distance(точное, глаз) - 0.05 ? прикидка : точное
        #endif
    }

    private static func место(_ точка: Точка) -> SIMD3<Float> {
        точка.сущность.isAnchored ? точка.сущность.position(relativeTo: nil) : точка.место
    }

    private static func сантиметры(_ а: SIMD3<Float>, _ б: SIMD3<Float>) -> Int {
        Int((simd_distance(а, б) * 100).rounded())
    }

    /// Тонкий брусок единичной длины — от а до б: длина — масштабом по z, направление — поворотом z к отрезку.
    private static func протянуть(_ линия: Entity, от а: SIMD3<Float>, до б: SIMD3<Float>) {
        let вектор = б - а
        let длина = simd_length(вектор)
        guard длина > 0.001 else {
            if линия.isEnabled { линия.isEnabled = false }
            return
        }
        if !линия.isEnabled { линия.isEnabled = true }
        линия.transform = Transform(scale: SIMD3<Float>(1, 1, длина),
                                    rotation: simd_quatf(from: SIMD3<Float>(0, 0, 1), to: вектор / длина),
                                    translation: (а + б) / 2)
    }

    // MARK: Сравнение и подписи

    /// Последний отрезок против вещи; nil — сравнение выключено, нет размеров или отрезков.
    var сравнение: СравнениеЛинейки? {
        guard сравнивать, let габариты, let последний else { return nil }
        return .сравнить(замер: Double(последний), габариты: габариты, выбор: выбор, погрешность: Self.погрешность)
    }

    /// Тексты и кайма подписей: у последнего отрезка при сравнении — ✓ / ✗ и цвет итога.
    private func раскрасить() {
        let сравнение = self.сравнение
        for номер in отрезки.indices {
            подписать(номер, сравнение: номер == отрезки.count - 1 ? сравнение : nil)
        }
    }

    private func подписать(_ номер: Int, сравнение: СравнениеЛинейки?) {
        let отрезок = отрезки[номер]
        var текст = ЛинейкаГабаритовText.длина(отрезок.см)
        /* Замер вещи: «Ш 60 см», «В 85 см», «Г 55 см» — какой это размер. */
        if замерВещи {
            текст = ГабаритыText.т(номер == 0 ? "fb_w_short" : (номер == 1 ? "fb_h_short" : "fb_d_short")) + " " + текст
        }
        var кайма = КоробкаГабаритов.зелёный.withAlphaComponent(0.9)
        if let сравнение {
            switch сравнение.итог {
            case .хватает:
                текст += " ✓"
                кайма = КоробкаГабаритов.зелёный
            case .впритык:
                текст += " ✓"
                кайма = Self.янтарь
            case .неХватает:
                текст += " ✗"
                кайма = Self.малиновый
            }
        }
        отрезок.подпись.текст = текст
        отрезок.подпись.layer.borderColor = кайма.cgColor
        отрезок.подпись.layer.borderWidth = сравнение == nil ? 1 : 2
    }

    // MARK: Что показать

    /// Подсказка над камерой: что делать сейчас.
    func подсказка(цель: Bool) -> (значок: String, текст: String) {
        switch слежение {
        case .быстро:
            return ("tortoise", ГабаритыText.т("fb_fast"))
        case .мало:
            return ("lightbulb", ГабаритыText.т("fb_dark"))
        case .запуск, .нет, .возврат:
            return ("iphone", т("fr_scan"))
        case .норма:
            break
        }
        if замерВещи && отрезков >= пределОтрезков { return ("checkmark.circle", т("fr_meas_ready")) }
        if !цель { return ("scope", т("fr_no_surface")) }
        if начато { return ("smallcircle.filled.circle", т("fr_aim_end")) }
        if замерВещи {
            let ключи = ["fr_meas_w", "fr_meas_h", "fr_meas_d"]
            return ("plus.circle", т(ключи[min(отрезков, ключи.count - 1)]))
        }
        return ("plus.circle", отрезков == 0 ? т("fr_aim") : т("fr_aim_more"))
    }

    /// Для VoiceOver: сколько отрезков, последний, сравнение.
    var озвучка: String {
        var части: [String] = []
        if let последний {
            части.append(ЛинейкаГабаритовText.т("fr_state", String(отрезков), ЛинейкаГабаритовText.длина(последний)))
        } else {
            части.append(т("fr_state_none"))
        }
        if начато { части.append(т("fr_start_done")) }
        if let сравнение { части.append(сравнение.озвучка) }
        return части.joined(separator: ". ")
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

    // MARK: Снимок

    /**
     Кадр с отрезками и подписями; готово(nil) — не вышло. Прицел и тянущаяся линия прячутся, но RealityKit рисует это
     только в следующем кадре: snapshot сразу мог бы поймать белую точку прицела. Поэтому ждём два обновления сцены
     (кадр()) — первый уже нарисован без них; сцена встала (пауза) — через 0,2 с снимаем всё равно.
     */
    func снять(готово: @escaping (СнимокГабаритов?) -> Void) {
        guard вид != nil, !снимаем, !отрезки.isEmpty else { return }
        снимаем = true
        послеСнимка = готово
        прицел?.isEnabled = false
        тяга?.isEnabled = false
        кадровДоСнимка = 2
        запаснойСнимок?.cancel()
        запаснойСнимок = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self, self.кадровДоСнимка > 0 else { return }
            self.кадровДоСнимка = 0
            self.сделатьСнимок()
        }
    }

    /// Сам снимок ARView — когда прицел уже не на экране.
    private func сделатьСнимок() {
        запаснойСнимок?.cancel()
        запаснойСнимок = nil
        guard let вид else {
            снимокПришёл(nil)
            return
        }
        вид.snapshot(saveToHDR: false) { [weak self] картинка in
            guard let self else { return }
            Task { @MainActor in
                self.снимокПришёл(картинка)
            }
        }
    }

    /**
     На главной нити — только лёгкое: подписи отрезков маленькими картинками и их места. Склейка во весь экран и плашка
     с текстом — в фоне (МодельГабаритов.собрать, тот же рисунок, что у коробки).
     */
    private func снимокПришёл(_ картинка: UIImage?) {
        guard let картинка, let вид, картинка.size.width > 0, вид.bounds.width > 0 else {
            снимаем = false
            let готово = послеСнимка
            послеСнимка = nil
            готово?(nil)
            return
        }
        let к = картинка.size.width / вид.bounds.width
        let видимые = отрезки.map { $0.подпись }.filter { !$0.isHidden && $0.alpha > 0.01 }
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
        let строка = строкаСнимка
        let озвучка = ЛинейкаГабаритовText.т("fr_shot_img", длиныСтрокой(", "))
        Task { @MainActor [weak self] in
            let готовая = await Task.detached(priority: .userInitiated) { () -> UIImage in
                МодельГабаритов.собрать(картинка, метки: метки, строка: строка, к: к)
            }.value
            guard let self else { return }
            self.снимаем = false
            let готово = self.послеСнимка
            self.послеСнимка = nil
            готово?(СнимокГабаритов(картинка: готовая, озвучка: озвучка))
        }
    }

    /// Длины последних отрезков (до трёх, по порядку).
    private func длиныСтрокой(_ между: String) -> String {
        отрезки.suffix(3).map { ЛинейкаГабаритовText.длина($0.см) }.joined(separator: между)
    }

    /// Плашка снимка: «Kliko.kz · 62 см · 1 м 25 см» или «Kliko.kz · Ниша 62 см · вещь 60 см · запас 2 см ✓».
    private var строкаСнимка: String {
        if let сравнение { return "Kliko.kz · " + сравнение.строка }
        return "Kliko.kz · " + длиныСтрокой(" · ")
    }
}

#if !targetEnvironment(simulator)
extension ЛинейкаГабаритов {
    /// Настройка сессии для линейки: на устройствах с лидаром — сетка сцены (луч ложится на настоящую поверхность, а не
    /// на прикидку по точкам). Кадры глубины (.sceneDepth) не включаем: их никто не читает — луч ARKit берёт лидар и
    /// без них, а каждый кадр глубины — работа GPU и батарея за долгий замер. Без лидара — ничего не меняет.
    static func точнее(_ настройка: ARWorldTrackingConfiguration) {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            настройка.sceneReconstruction = .mesh
        }
    }
}
#endif
