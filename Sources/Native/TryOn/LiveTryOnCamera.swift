import SwiftUI
import AVFoundation
import Vision
import CoreImage
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА — КАМЕРА И АНАЛИЗ КАДРОВ (владелец 13.10.2026: «нужнее охват всего»).

 Камера — своя сессия AVFoundation на своей очереди (как КамераПоиска, PhotoSearchCamera.swift), только без снимков:
 превью (AVCaptureVideoPreviewLayer) и выход кадров видео. Кадры выхода повёрнуты так же, как превью, а у передней
 камеры ещё и отражены — ровно как человек видит себя на экране. Поэтому точки Vision ложатся на экран простой формулой
 «заполнить» (ПосадкаЖивойПримерки.наЭкран), а снимок с вещью совпадает с тем, что было на экране.

 Анализ — на своей очереди, не чаще 15 кадров в секунду: лицо (VNDetectFaceLandmarksRequest — зрачки, глаза, контур,
 нос, брови) или рука (VNDetectHumanHandPoseRequest — запястье, пястные суставы, безымянный палец). Кадр в Vision идёт
 как есть, без копии; копия (CGImage) делается только для снимка — один кадр по запросу. Наружу — доли кадра с началом
 слева сверху, на главную нить.

 Сессия стоит, когда экран ушёл или приложение в фоне (ЭкранЖивойПримерки). Доступ спрашивается при первом показе;
 запрещён или камеры нет — заглушка.
 */
final class КамераЖивойПримерки: NSObject, ObservableObject {
    enum Доступ: Equatable {
        case неизвестно
        case есть
        case запрещён
        case нетКамеры
    }

    @Published private(set) var доступ: Доступ = .неизвестно
    /// Сессия идёт — кадры приходят.
    @Published private(set) var готова = false
    /// Снимает передняя камера.
    @Published private(set) var передняя = true
    /// Есть и вторая камера — «Другая камера».
    @Published private(set) var естьДругая = false
    /// Растёт при смене камеры: превью заново ставит поворот своей связи.
    @Published private(set) var смена = 0
    /// Сессию прервали (звонок, камеру взяло другое приложение, Split View или Slide Over на iPad): кадры не идут.
    @Published private(set) var прервана = false
    /// Прерывание началось или кончилось — на главной нити: модель сбрасывает слежение и показывает подсказку.
    var приПрерывании: (@MainActor (Bool) -> Void)? = nil

    let сессия = AVCaptureSession()
    private let очередь = DispatchQueue(label: "kz.kliko.livetryon.camera")
    private let выход = AVCaptureVideoDataOutput()
    private var наблюдения: [NSKeyValueObservation] = []

    /* Дальше — только на очереди камеры. */
    private var настроена = false
    /// Экран хочет камеру: запуск после ответа о доступе не включит её, если экран уже ушёл.
    private var нужна = false
    private var сторона: AVCaptureDevice.Position = .front
    /// Поворот кадров — как у превью (на iPhone в портрете 90°).
    private var угол: CGFloat = 90
    private var приёмник: АнализЖивойПримерки? = nil
    /// Сколько раз сессию, вставшую саму (сбой, сброс медиаслужб), запускали заново с последнего запустить().
    private var перезапусков = 0

    override init() {
        super.init()
        /* Прерывания и сбои сессии — через KVO её свойств isInterrupted и isRunning (оба наблюдаемы): звонок, Split
           View на iPad, камера у другого приложения, сброс медиаслужб. Разбор — на очереди камеры. */
        наблюдения = [
            сессия.observe(\.isInterrupted, options: [.new]) { [weak self] _, _ in self?.ходСменился() },
            сессия.observe(\.isRunning, options: [.new]) { [weak self] _, _ in self?.ходСменился() }
        ]
    }

    private func ходСменился() {
        очередь.async { [weak self] in self?.сверитьХод() }
    }

    /// На очереди камеры: сессия встала сама, а экран её ждёт, — запустить снова (не больше двух раз, без петли на
    /// постоянном сбое). На главную — идёт ли и прервана ли.
    private func сверитьХод() {
        if нужна && настроена && !сессия.isRunning && !сессия.isInterrupted && перезапусков < 2 {
            перезапусков += 1
            сессия.startRunning()
        }
        let прервана = нужна && сессия.isInterrupted
        let идёт = нужна && сессия.isRunning && !прервана
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.готова != идёт { self.готова = идёт }
            guard self.прервана != прервана else { return }
            self.прервана = прервана
            self.приПрерывании?(прервана)
        }
    }

    private func наГлавной(_ блок: @escaping () -> Void) {
        DispatchQueue.main.async(execute: блок)
    }

    /// Кому отдавать кадры. Зовётся один раз, до запуска.
    func подключить(_ анализ: АнализЖивойПримерки) {
        очередь.async { [weak self] in
            guard let self else { return }
            self.приёмник = анализ
            if self.настроена { self.выход.setSampleBufferDelegate(анализ, queue: анализ.очередь) }
        }
    }

    /// Экран на виду: спросить доступ (если ещё не спрашивали) и запустить. передней — с какой камеры начать (только
    /// в первый раз; потом — та, что была).
    func запустить(передней: Bool) {
        очередь.async {
            self.нужна = true
            self.перезапусков = 0
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            настроитьИЗапустить(передней)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] разрешили in
                guard let self else { return }
                if разрешили {
                    self.настроитьИЗапустить(передней)
                } else {
                    self.наГлавной { self.доступ = .запрещён }
                }
            }
        case .denied, .restricted:
            наГлавной { self.доступ = .запрещён }
        @unknown default:
            наГлавной { self.доступ = .запрещён }
        }
    }

    private func настроитьИЗапустить(_ передней: Bool) {
        очередь.async { [weak self] in
            guard let self, self.нужна else { return }
            if !self.настроена && !self.настроить(передней) && !self.настроить(!передней) {
                self.наГлавной {
                    self.доступ = .нетКамеры
                    self.готова = false
                }
                return
            }
            if !self.сессия.isRunning { self.сессия.startRunning() }
            let сторона = self.сторона
            let другая: AVCaptureDevice.Position = сторона == .front ? .back : .front
            let естьДругая = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: другая) != nil
            let идёт = self.сессия.isRunning && !self.сессия.isInterrupted
            self.наГлавной {
                self.доступ = .есть
                self.готова = идёт
                self.передняя = сторона == .front
                self.естьДругая = естьДругая
            }
        }
    }

    /// На очереди камеры: широкая камера нужной стороны, 1280×720 и выход кадров.
    private func настроить(_ передней: Bool) -> Bool {
        let нужная: AVCaptureDevice.Position = передней ? .front : .back
        guard let камера = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: нужная),
              let вход = try? AVCaptureDeviceInput(device: камера) else { return false }
        сессия.beginConfiguration()
        if сессия.canSetSessionPreset(.hd1280x720) {
            сессия.sessionPreset = .hd1280x720
        }
        guard сессия.canAddInput(вход) else {
            сессия.commitConfiguration()
            return false
        }
        сессия.addInput(вход)
        if !сессия.outputs.contains(выход) {
            guard сессия.canAddOutput(выход) else {
                сессия.removeInput(вход)
                сессия.commitConfiguration()
                return false
            }
            выход.alwaysDiscardsLateVideoFrames = true
            let формат = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            if выход.availableVideoPixelFormatTypes.contains(формат) {
                выход.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: формат]
            }
            сессия.addOutput(выход)
        }
        if let приёмник { выход.setSampleBufferDelegate(приёмник, queue: приёмник.очередь) }
        сторона = нужная
        настроитьСвязь()
        сессия.commitConfiguration()
        настроена = true
        return true
    }

    /// На очереди камеры: кадры выхода — повёрнуты как превью, у передней камеры — отражены, как в зеркале.
    private func настроитьСвязь() {
        guard let связь = выход.connection(with: .video) else { return }
        if связь.isVideoRotationAngleSupported(угол) && связь.videoRotationAngle != угол {
            связь.videoRotationAngle = угол
        }
        if связь.isVideoMirroringSupported {
            связь.automaticallyAdjustsVideoMirroring = false
            связь.isVideoMirrored = сторона == .front
        }
    }

    /// Ушли с экрана или в фон: сессия стоит.
    func остановить() {
        /* Сильная ссылка: экран уже закрыт — сессия всё равно гаснет, а не ждёт освобождения. */
        очередь.async {
            self.нужна = false
            if self.сессия.isRunning { self.сессия.stopRunning() }
            self.наГлавной { self.готова = false }
        }
    }

    /// «Другая камера»: передняя ↔ задняя; вход сменить не вышло — остаётся прежняя.
    func переключить() {
        очередь.async { [weak self] in
            guard let self, self.настроена else { return }
            let нужная: AVCaptureDevice.Position = self.сторона == .back ? .front : .back
            guard let новая = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: нужная),
                  let вход = try? AVCaptureDeviceInput(device: новая) else { return }
            let прежние = self.сессия.inputs
            self.сессия.beginConfiguration()
            for старый in прежние { self.сессия.removeInput(старый) }
            if self.сессия.canAddInput(вход) {
                self.сессия.addInput(вход)
                self.сторона = нужная
            } else {
                for старый in прежние where self.сессия.canAddInput(старый) { self.сессия.addInput(старый) }
            }
            self.настроитьСвязь()
            self.сессия.commitConfiguration()
            let сторона = self.сторона
            self.наГлавной {
                self.передняя = сторона == .front
                self.смена += 1
            }
        }
    }

    /// Поворот превью (его сообщает вид превью) — тот же кадрам выхода.
    func запомнитьПоворот(_ новый: CGFloat) {
        очередь.async { [weak self] in
            guard let self, self.угол != новый else { return }
            self.угол = новый
            if self.настроена { self.настроитьСвязь() }
        }
    }
}

// MARK: - Превью

/// Превью во весь экран: AVCaptureVideoPreviewLayer с заполнением, поворот — по интерфейсу (как ПревьюКамерыПоиска).
/// Передняя камера отражается самим слоем — как и кадры выхода.
struct ПревьюЖивойПримерки: UIViewRepresentable {
    let камера: КамераЖивойПримерки
    /// Номер смены камеры: изменился — слой заново ставит поворот новой связи.
    let смена: Int

    final class Вид: UIView {
        weak var камера: КамераЖивойПримерки?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var слой: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            let угол: CGFloat
            switch window?.windowScene?.interfaceOrientation ?? .portrait {
            case .portraitUpsideDown: угол = 270
            case .landscapeLeft: угол = 180
            case .landscapeRight: угол = 0
            default: угол = 90
            }
            if let связь = слой?.connection, связь.isVideoRotationAngleSupported(угол), связь.videoRotationAngle != угол {
                связь.videoRotationAngle = угол
            }
            камера?.запомнитьПоворот(угол)
        }
    }

    func makeUIView(context: Context) -> Вид {
        let вид = Вид()
        вид.backgroundColor = .black
        вид.камера = камера
        вид.слой?.session = камера.сессия
        вид.слой?.videoGravity = .resizeAspectFill
        return вид
    }

    func updateUIView(_ uiView: Вид, context: Context) {
        uiView.setNeedsLayout()
    }
}

// MARK: - Что увидел Vision

/// Один разобранный кадр: его размер в пикселях (уже повёрнутого как экран) и найденное лицо или рука.
struct НаблюдениеЖивойПримерки: Sendable {
    let размер: CGSize
    let лицо: ЛицоЖивойПримерки?
    let рука: РукаЖивойПримерки?
}

/// Точки лица — доли кадра, начало слева сверху (как на экране). Глаза — центры зрачков в порядке слева направо.
struct ЛицоЖивойПримерки: Sendable {
    let глазСлева: CGPoint
    let глазСправа: CGPoint
    /// Контур лица (от виска через подбородок к другому виску).
    let контур: [CGPoint]
    /// Нос и его спинка.
    let нос: [CGPoint]
    /// Обе брови.
    let брови: [CGPoint]
    let рамка: CGRect
    /// Поворот головы влево-вправо, радианы; nil — Vision не сказал.
    let поворот: Double?
}

/// Точки руки — доли кадра, начало слева сверху.
struct РукаЖивойПримерки: Sendable {
    let запястье: CGPoint
    let указательный: CGPoint
    let средний: CGPoint
    let мизинец: CGPoint
    /// Безымянный палец: пястный сустав и следующий — для кольца; nil — не уверены.
    let безымянный: CGPoint?
    let безымянныйСустав: CGPoint?
}

// MARK: - Анализ кадров

/**
 Приёмник кадров выхода. Всё внутри — на своей очереди; наружу — НаблюдениеЖивойПримерки на главную нить (кадр без
 лица или руки — тоже, с пустыми полями: так экран узнаёт, что вещь потерялась).
 */
final class АнализЖивойПримерки: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let очередь = DispatchQueue(label: "kz.kliko.livetryon.vision", qos: .userInitiated)

    /// Не чаще 15 кадров в секунду.
    static let шаг: CFTimeInterval = 1.0 / 15.0

    private let наГлавную: @MainActor (НаблюдениеЖивойПримерки) -> Void

    /* Дальше — только на очереди анализа. */
    private var включён = false
    private var рука = false
    private var последний: CFTimeInterval = 0
    private var ждутКадр: (@MainActor (CGImage?) -> Void)? = nil
    private var контекст: CIContext? = nil
    private lazy var запросЛица: VNDetectFaceLandmarksRequest = VNDetectFaceLandmarksRequest()
    private lazy var запросРуки: VNDetectHumanHandPoseRequest = {
        let запрос = VNDetectHumanHandPoseRequest()
        запрос.maximumHandCount = 1
        return запрос
    }()

    init(наГлавную: @escaping @MainActor (НаблюдениеЖивойПримерки) -> Void) {
        self.наГлавную = наГлавную
        super.init()
    }

    /// Смотреть кадры: лицо или руку.
    func включить(рука: Bool) {
        очередь.async {
            self.включён = true
            self.рука = рука
            self.последний = 0
        }
    }

    func выключить() {
        очередь.async { self.включён = false }
    }

    /// Следующий кадр картинкой — для снимка. Ответ — на главной нити; кадров нет — ответа нет (ждущий ставит срок).
    func кадр(_ готово: @escaping @MainActor (CGImage?) -> Void) {
        очередь.async { self.ждутКадр = готово }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let буфер = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let ждут = ждутКадр {
            ждутКадр = nil
            let картинка = снимок(буфер)
            Task { @MainActor in ждут(картинка) }
        }
        guard включён else { return }
        let сейчас = CACurrentMediaTime()
        guard сейчас - последний >= Self.шаг else { return }
        последний = сейчас
        let размер = CGSize(width: CVPixelBufferGetWidth(буфер), height: CVPixelBufferGetHeight(буфер))
        let обработчик = VNImageRequestHandler(cvPixelBuffer: буфер, orientation: .up, options: [:])
        let наблюдение: НаблюдениеЖивойПримерки
        if рука {
            наблюдение = НаблюдениеЖивойПримерки(размер: размер, лицо: nil, рука: разобратьРуку(обработчик))
        } else {
            наблюдение = НаблюдениеЖивойПримерки(размер: размер, лицо: разобратьЛицо(обработчик), рука: nil)
        }
        let получатель = наГлавную
        Task { @MainActor in получатель(наблюдение) }
    }

    /// Кадр → CGImage (одна копия — только для снимка).
    private func снимок(_ буфер: CVPixelBuffer) -> CGImage? {
        let своё = контекст ?? CIContext(options: [.cacheIntermediates: false])
        контекст = своё
        let изображение = CIImage(cvPixelBuffer: буфер)
        return своё.createCGImage(изображение, from: изображение.extent)
    }

    /// Самое крупное лицо кадра. Точки Vision — доли рамки лица с началом снизу; переводим в доли кадра сверху.
    private func разобратьЛицо(_ обработчик: VNImageRequestHandler) -> ЛицоЖивойПримерки? {
        do {
            try обработчик.perform([запросЛица])
        } catch {
            return nil
        }
        guard let лицо = (запросЛица.results ?? []).max(by: { $0.boundingBox.width < $1.boundingBox.width }),
              let метки = лицо.landmarks else { return nil }
        let рамка = лицо.boundingBox
        func точки(_ область: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let область else { return [] }
            return область.normalizedPoints.map { т in
                CGPoint(x: рамка.minX + т.x * рамка.width, y: 1 - (рамка.minY + т.y * рамка.height))
            }
        }
        func центр(_ набор: [CGPoint]) -> CGPoint? {
            guard !набор.isEmpty else { return nil }
            let сумма = набор.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
            return CGPoint(x: сумма.x / CGFloat(набор.count), y: сумма.y / CGFloat(набор.count))
        }
        guard let первый = точки(метки.leftPupil).first ?? центр(точки(метки.leftEye)),
              let второй = точки(метки.rightPupil).first ?? центр(точки(метки.rightEye)) else { return nil }
        /* Кадр передней камеры отражён — «левый» Vision может оказаться справа; порядок берём по экрану. */
        let слева = первый.x <= второй.x ? первый : второй
        let справа = первый.x <= второй.x ? второй : первый
        return ЛицоЖивойПримерки(
            глазСлева: слева,
            глазСправа: справа,
            контур: точки(метки.faceContour),
            нос: точки(метки.nose) + точки(метки.noseCrest),
            брови: точки(метки.leftEyebrow) + точки(метки.rightEyebrow),
            рамка: CGRect(x: рамка.minX, y: 1 - рамка.maxY, width: рамка.width, height: рамка.height),
            поворот: лицо.yaw?.doubleValue)
    }

    /// Одна рука: запястье и пястные суставы обязательны (уверенность выше 0,3), безымянный — если виден.
    private func разобратьРуку(_ обработчик: VNImageRequestHandler) -> РукаЖивойПримерки? {
        do {
            try обработчик.perform([запросРуки])
        } catch {
            return nil
        }
        guard let рука = запросРуки.results?.first else { return nil }
        func точка(_ имя: VNHumanHandPoseObservation.JointName) -> CGPoint? {
            guard let т = try? рука.recognizedPoint(имя), т.confidence > 0.3 else { return nil }
            return CGPoint(x: т.location.x, y: 1 - т.location.y)
        }
        guard let запястье = точка(.wrist), let указательный = точка(.indexMCP), let средний = точка(.middleMCP),
              let мизинец = точка(.littleMCP) else { return nil }
        return РукаЖивойПримерки(запястье: запястье, указательный: указательный, средний: средний, мизинец: мизинец,
                                 безымянный: точка(.ringMCP), безымянныйСустав: точка(.ringPIP))
    }
}
