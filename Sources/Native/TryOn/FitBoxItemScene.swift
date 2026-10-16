import Combine
import UIKit
import RealityKit
import simd

/**
 «ПОМЕСТИТСЯ ЛИ?» — РЕЖИМ «ВЕЩЬ»: СЦЕНА (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ — 5 разных фото, и ИИ сам
 собрал 3D любой вещи или авто»; раньше: «чтобы по-настоящему по камере показывал объект в примерке»).

 Как КоробкаГабаритов (FitBoxAR.swift): готовая сущность с началом в центре дна, лицом (+z) — к человеку; её кладёт в
 корпус МодельГабаритов, а двигают, крутят, прижимают к стене и снимают — те же жесты и тот же корпус, что у коробки.
 Масштаб по высоте — «вырастание» снизу вверх (его делает МодельГабаритов).

 3D-модель ИИ (USDZ из model3d): в модели свои размеры (w_cm, h_cm, d_cm пришли — сервер собрал её в настоящем размере) —
 подгоняем одним масштабом по ширине, пропорции модели не трогаем; своих размеров нет — по каждой оси к ширине, высоте и
 глубине объявления, но не дальше ±25–33 % от масштаба по ширине (сильнее — это уже не вещь, а растянутая картинка).
 Тень — мягкое тёмное пятно на полу (тени RealityKit «от земли» на iOS 17 в AR-сцене выключены ради батареи); свет —
 свет окружения AR (карта окружения ARKit, кроме лёгкого режима) и свои направленные источники: основной сверху-спереди
 и заполняющий сзади-слева, в лёгком режиме — только основной, ярче.

 Настольная вещь и телевизор без 3D-модели — уже не «стойка», а 3D-форма по размерам (СборкаФормыГабаритов,
 FitBoxItemShape.swift); «стойка» осталась мебели и прочему крупному.

 «Стойка» (3D-модели нет или не загрузилась): вырезанное фото на вертикальной плоскости настоящих ширины и высоты у
 лицевой стороны вещи, сзади — оно же зеркально и темнее; по бокам — тонкие боковины глубины вещи в её средний цвет;
 на полу — та же мягкая тень. Пропорции фото и размеров близки (до трети разницы) — фото растягивается ровно в Ш×В:
 силуэт вещи и есть её габарит; дальше — вписывается в Ш×В без искажения, стоя на полу по центру.
 */
@MainActor
enum СборкаВещиГабаритов {
    /// 3D-модель в настоящем размере. своиРазмеры — в модели настоящий размер (подгонка одним масштабом по ширине).
    static func модель(_ шаблон: Entity, габариты г: ГабаритыВещи, своиРазмеры: Bool, тень: TextureResource?,
                       лёгкий: Bool) -> Entity {
        let рост = Entity()
        let р = г.метры
        let обёртка = Entity()
        обёртка.addChild(шаблон.clone(recursive: true))
        let рамка = обёртка.visualBounds(relativeTo: обёртка)
        let e = рамка.extents
        var масштаб = SIMD3<Float>(1, 1, 1)
        if конечно(e), e.x > 0.000_1, e.y > 0.000_1, e.z > 0.000_1 {
            let поШирине = р.x / e.x
            if своиРазмеры {
                масштаб = SIMD3<Float>(repeating: поШирине)
            } else {
                func вПределах(_ k: Float) -> Float { min(поШирине * 1.33, max(поШирине * 0.75, k)) }
                масштаб = SIMD3<Float>(поШирине, вПределах(р.y / e.y), вПределах(р.z / e.z))
            }
        } else if конечно(e), e.y > 0.000_1 {
            масштаб = SIMD3<Float>(repeating: р.y / e.y)
        }
        let низ = SIMD3<Float>(рамка.center.x, рамка.min.y, рамка.center.z)
        обёртка.scale = масштаб
        обёртка.position = конечно(низ) ? -низ * масштаб : SIMD3<Float>(0, 0, 0)
        рост.addChild(обёртка)

        let ширина = конечно(e) ? max(0.05, e.x * масштаб.x) : р.x
        let глубина = конечно(e) ? max(0.05, e.z * масштаб.z) : р.z
        рост.addChild(пятно(ширина: ширина, глубина: глубина, тень: тень))
        осветить(рост, высота: max(0.3, р.y), лёгкий: лёгкий)
        return рост
    }

    /// «Стойка»: фото вещи на плоскости настоящих ширины и высоты, боковины глубины в цвет вещи, тень на полу.
    /// пропорция — ширина фото к высоте.
    static func стойка(лицо: TextureResource, спина: TextureResource?, пропорция: CGFloat, цвет: UIColor,
                       габариты: ГабаритыВещи, тень: TextureResource?) -> Entity {
        let рост = Entity()
        let р = габариты.метры
        let ш = max(р.x, 0.01)
        let в = max(р.y, 0.01)
        let г = max(р.z, 0.01)
        let плоскость = размерФото(пропорция: Float(max(0.01, пропорция)), ширина: ш, высота: в)

        var перед = UnlitMaterial()
        перед.color = .init(tint: .white, texture: .init(лицо))
        перед.blending = .transparent(opacity: .init(floatLiteral: 1))
        let лицевая = ModelEntity(mesh: .generatePlane(width: плоскость.x, height: плоскость.y), materials: [перед])
        лицевая.position = SIMD3<Float>(0, плоскость.y / 2, г / 2)
        рост.addChild(лицевая)

        /* Сзади — силуэт отражён (зеркальная картинка) и темнее: видно, что это спина, а не второе лицо. Плоскость
           повёрнута на 180° — её лицо смотрит назад (с обратной стороны плоскость не рисуется). */
        if let спина {
            var зад = UnlitMaterial()
            зад.color = .init(tint: UIColor(white: 0.62, alpha: 1), texture: .init(спина))
            зад.blending = .transparent(opacity: .init(floatLiteral: 1))
            let задняя = ModelEntity(mesh: .generatePlane(width: плоскость.x, height: плоскость.y), materials: [зад])
            задняя.position = SIMD3<Float>(0, плоскость.y / 2, -г / 2)
            задняя.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
            рост.addChild(задняя)
        }

        /* Боковины: тонкие, на всю высоту и глубину, по краям настоящей ширины; чуть темнее среднего цвета вещи. */
        var бок = UnlitMaterial(color: цвет)
        бок.blending = .transparent(opacity: .init(floatLiteral: 0.88))
        let толщина = min(Float(0.012), max(Float(0.004), ш * 0.02))
        let сетка = MeshResource.generateBox(width: толщина, height: в, depth: max(0.002, г - 0.004))
        for x in [-(ш - толщина) / 2, (ш - толщина) / 2] {
            let боковина = ModelEntity(mesh: сетка, materials: [бок])
            боковина.position = SIMD3<Float>(x, в / 2, 0)
            рост.addChild(боковина)
        }

        рост.addChild(пятно(ширина: ш, глубина: г, тень: тень))
        return рост
    }

    /// Плоскость фото: пропорции близки к Ш:В — ровно Ш×В (растянуть); иначе — вписать в Ш×В без искажения.
    private static func размерФото(пропорция: Float, ширина: Float, высота: Float) -> SIMD2<Float> {
        let нужная = ширина / высота
        let разница = пропорция / нужная
        if разница >= 0.75 && разница <= 1.33 { return SIMD2<Float>(ширина, высота) }
        if пропорция > нужная { return SIMD2<Float>(ширина, ширина / пропорция) }
        return SIMD2<Float>(высота * пропорция, высота)
    }

    // MARK: Тень и свет

    /// Мягкое пятно тени на полу чуть шире вещи; текстуры нет — ровный полупрозрачный прямоугольник.
    private static func пятно(ширина: Float, глубина: Float, тень: TextureResource?) -> Entity {
        var материал: UnlitMaterial
        if let тень {
            материал = UnlitMaterial()
            материал.color = .init(tint: .white, texture: .init(тень))
            материал.blending = .transparent(opacity: .init(floatLiteral: 1))
        } else {
            материал = UnlitMaterial(color: .black)
            материал.blending = .transparent(opacity: .init(floatLiteral: 0.22))
        }
        let запас: Float = тень == nil ? 0.04 : 0.16
        let след = ModelEntity(mesh: .generatePlane(width: ширина + запас, depth: глубина + запас), materials: [материал])
        след.position = SIMD3<Float>(0, 0.002, 0)
        return след
    }

    /// Свет для модели и 3D-формы (у их материалов — физический свет): основной сверху-спереди-справа, заполняющий
    /// сзади-слева. Не в лёгком режиме в сцене есть и свет окружения AR (карта окружения ARKit, FitBoxAR.swift) — лампы
    /// тогда слабее, только объём подчеркнуть; в лёгком окружения нет — одна яркая лампа.
    static func осветить(_ рост: Entity, высота: Float, лёгкий: Bool) {
        let основной = DirectionalLight()
        основной.light.color = .white
        основной.light.intensity = лёгкий ? 2400 : 1000
        навести(основной, из: SIMD3<Float>(0.8, высота + 1.6, 1.6), на: SIMD3<Float>(0, высота * 0.4, 0))
        рост.addChild(основной)
        guard !лёгкий else { return }
        let заполняющий = DirectionalLight()
        заполняющий.light.color = .white
        заполняющий.light.intensity = 350
        навести(заполняющий, из: SIMD3<Float>(-1.6, высота + 0.8, -1.2), на: SIMD3<Float>(0, высота * 0.4, 0))
        рост.addChild(заполняющий)
    }

    /// Направленный свет светит вдоль своей −z: повернуть −z от точки к цели.
    private static func навести(_ сущность: Entity, из точка: SIMD3<Float>, на цель: SIMD3<Float>) {
        сущность.position = точка
        let путь = цель - точка
        let длина = simd_length(путь)
        guard длина > 0.000_1 else { return }
        сущность.orientation = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: путь / длина)
    }

    // MARK: Текстуры

    /// Текстура цвета из картинки (с прозрачностью). Не вышло — nil.
    static func текстура(_ картинка: CGImage) -> TextureResource? {
        try? TextureResource.generate(from: картинка, options: .init(semantic: .color))
    }

    /**
     Та же текстура, но не останавливая кадр камеры: RealityKit готовит её не на главной нити (generateAsync, iOS 15+;
     на SDK 18+ — только предупреждение об устаревании), ответ — на главной. Стойка ждёт лицо и спину по очереди, а не
     две синхронные загрузки 1024 px подряд посреди идущей сессии AR. Отмена задачи подготовку не обрывает (она
     короткая) — итог просто не возьмут. Не вышло — nil.
     */
    static func текстураВФоне(_ картинка: CGImage) async -> TextureResource? {
        let запрос = ЗапросТекстурыВещиГабаритов()
        let итог = await withCheckedContinuation { (продолжить: CheckedContinuation<TextureResource?, Never>) in
            запрос.отдать = { продолжить.resume(returning: $0) }
            запрос.подписка = TextureResource.generateAsync(from: картинка, options: .init(semantic: .color))
                .receive(on: DispatchQueue.main)
                .sink(receiveCompletion: { конец in
                    if case .failure = конец { запрос.закончить(nil) }
                }, receiveValue: { текстура in
                    запрос.закончить(текстура)
                })
        }
        запрос.подписка = nil
        return итог
    }

    /// Мягкая круглая тень: чёрный, к краям прозрачный (64×64, рисуется один раз на окно).
    static func текстураТени() -> TextureResource? {
        let сторона = 64
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let к = CGContext(data: nil, width: сторона, height: сторона, bitsPerComponent: 8, bytesPerRow: 0,
                                space: пространство,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let цвета = [UIColor(white: 0, alpha: 0.42).cgColor, UIColor(white: 0, alpha: 0.30).cgColor,
                     UIColor(white: 0, alpha: 0).cgColor] as CFArray
        let места: [CGFloat] = [0, 0.55, 1]
        guard let градиент = CGGradient(colorsSpace: пространство, colors: цвета, locations: места) else { return nil }
        let центр = CGPoint(x: CGFloat(сторона) / 2, y: CGFloat(сторона) / 2)
        к.drawRadialGradient(градиент, startCenter: центр, startRadius: 0, endCenter: центр,
                             endRadius: CGFloat(сторона) / 2, options: [])
        guard let картинка = к.makeImage() else { return nil }
        return текстура(картинка)
    }

    private static func конечно(_ т: SIMD3<Float>) -> Bool {
        т.x.isFinite && т.y.isFinite && т.z.isFinite
    }
}

/// Ожидание одной текстуры generateAsync: подписка живёт до ответа, ответ отдаётся ровно один раз (значение или сбой).
final class ЗапросТекстурыВещиГабаритов {
    var подписка: AnyCancellable? = nil
    var отдать: ((TextureResource?) -> Void)? = nil

    init() {}

    func закончить(_ текстура: TextureResource?) {
        let ответ = отдать
        отдать = nil
        ответ?(текстура)
    }
}
