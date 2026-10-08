import SwiftUI
import AVFoundation
import Photos
import UIKit

/**
 ЖИВАЯ КАМЕРА ПОИСКА ПО ФОТО (владелец 29.09.2026) — свой экран вместо системного листа камеры.

 Сессия AVFoundation живёт на своей очереди (запуск, фонарик, снимок); наружу — только опубликованные признаки на
 главной нити. Доступ: не спрашивали — спросим при первом показе; запрещён или камеры нет (симулятор, iPad без
 камеры) — заглушка с галереей. Язык оформления — как у камеры подачи объявления: тёмный фон, зелёный акцент,
 круглые кнопки на полупрозрачной подложке, тексты растут с «Размером текста», RTL — зеркально сам SwiftUI.
 */
final class КамераПоиска: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum Доступ: Equatable {
        case неизвестно
        case есть
        case запрещён
        case нетКамеры
    }

    @Published private(set) var доступ: Доступ = .неизвестно
    /// Сессия запущена — затвор можно нажимать.
    @Published private(set) var готова = false
    @Published private(set) var фонарикЕсть = false
    @Published private(set) var фонарик = false
    @Published private(set) var снимаем = false
    /// Есть и передняя камера — съёмка по плану подачи показывает «Другая камера».
    @Published private(set) var естьПередняя = false

    let сессия = AVCaptureSession()
    private let очередь = DispatchQueue(label: "kz.kliko.photosearch.camera")
    private let выход = AVCapturePhotoOutput()
    private var устройство: AVCaptureDevice? = nil
    private var настроена = false
    /// Какая камера снимает сейчас — только на очереди камеры.
    private var сторона: AVCaptureDevice.Position = .back
    /// Поворот кадра — как у интерфейса (на iPhone всегда портрет, 90°).
    private var уголПоворота: CGFloat = 90
    private var готово: (@MainActor (UIImage) -> Void)? = nil
    /// Живой поиск («Авто», PhotoSearchLive.swift): выход кадров видео и кому их отдавать — только на очереди
    /// камеры. Приёмника нет — выхода в сессии нет, и сессия снимает как раньше (.photo).
    private let видеоВыход = AVCaptureVideoDataOutput()
    private var видеоВСессии = false
    private weak var приёмникКадров: AVCaptureVideoDataOutputSampleBufferDelegate? = nil
    private var очередьКадров: DispatchQueue? = nil

    override init() {
        super.init()
    }

    private func наГлавной(_ блок: @escaping () -> Void) {
        DispatchQueue.main.async(execute: блок)
    }

    /// Показали экран: спросить доступ (если ещё не спрашивали) и запустить сессию.
    func запустить() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            настроитьИЗапустить()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] разрешили in
                guard let self else { return }
                if разрешили {
                    self.настроитьИЗапустить()
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

    private func настроитьИЗапустить() {
        очередь.async { [weak self] in
            guard let self else { return }
            if !self.настроена && !self.настроить() {
                self.наГлавной {
                    self.доступ = .нетКамеры
                    self.готова = false
                }
                return
            }
            if !self.сессия.isRunning { self.сессия.startRunning() }
            let фонарь = self.устройство?.hasTorch ?? false
            let передняя = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
            self.наГлавной {
                self.доступ = .есть
                self.готова = true
                self.фонарикЕсть = фонарь
                self.естьПередняя = передняя
            }
        }
    }

    /// На очереди камеры: задняя широкая камера и выход снимков.
    private func настроить() -> Bool {
        guard let камера = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let вход = try? AVCaptureDeviceInput(device: камера) else { return false }
        сессия.beginConfiguration()
        сессия.sessionPreset = .photo
        guard сессия.canAddInput(вход), сессия.canAddOutput(выход) else {
            сессия.commitConfiguration()
            return false
        }
        сессия.addInput(вход)
        сессия.addOutput(выход)
        применитьЖивыеКадры()
        сессия.commitConfiguration()
        устройство = камера
        настроена = true
        return true
    }

    /// «Авто» (живой поиск): кадры видео идут приёмнику на его очереди, сессия — 1280×720 (меньше работы и батареи);
    /// nil — выход кадров снимается, сессия снова .photo. Сессию не запускает и не останавливает.
    func живыеКадры(_ приёмник: AVCaptureVideoDataOutputSampleBufferDelegate?, очередь своя: DispatchQueue?) {
        очередь.async { [weak self] in
            guard let self else { return }
            self.приёмникКадров = приёмник
            self.очередьКадров = приёмник == nil ? nil : своя
            (приёмник as? АнализКадровПоиска)?.повернуть(self.уголПоворота)
            guard self.настроена else { return }
            self.сессия.beginConfiguration()
            self.применитьЖивыеКадры()
            self.сессия.commitConfiguration()
        }
    }

    /// На очереди камеры, между beginConfiguration и commitConfiguration: выход кадров и размер сессии — по приёмнику.
    private func применитьЖивыеКадры() {
        if let приёмник = приёмникКадров, let своя = очередьКадров {
            if сессия.sessionPreset != .hd1280x720 && сессия.canSetSessionPreset(.hd1280x720) {
                сессия.sessionPreset = .hd1280x720
            }
            if !видеоВСессии && сессия.canAddOutput(видеоВыход) {
                видеоВыход.alwaysDiscardsLateVideoFrames = true
                let формат = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                if видеоВыход.availableVideoPixelFormatTypes.contains(формат) {
                    видеоВыход.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: формат]
                }
                сессия.addOutput(видеоВыход)
                видеоВСессии = true
            }
            видеоВыход.setSampleBufferDelegate(приёмник, queue: своя)
        } else {
            видеоВыход.setSampleBufferDelegate(nil, queue: nil)
            if видеоВСессии {
                сессия.removeOutput(видеоВыход)
                видеоВСессии = false
            }
            if сессия.sessionPreset != .photo && сессия.canSetSessionPreset(.photo) {
                сессия.sessionPreset = .photo
            }
        }
    }

    /// Ушли с экрана камеры: фонарик гаснет, сессия останавливается.
    func остановить() {
        /* Сильная ссылка: экран с @StateObject уже закрыт — сессия и фонарик всё равно гаснут, а не ждут освобождения. */
        очередь.async {
            if let у = self.устройство, у.hasTorch, у.torchMode == .on, (try? у.lockForConfiguration()) != nil {
                у.torchMode = .off
                у.unlockForConfiguration()
            }
            if self.сессия.isRunning { self.сессия.stopRunning() }
            self.наГлавной {
                self.готова = false
                self.фонарик = false
                self.снимаем = false
            }
        }
    }

    /// «Другая камера» (съёмка по плану подачи): задняя ↔ передняя; вход сменить не вышло — остаётся прежняя.
    func переключитьКамеру() {
        очередь.async { [weak self] in
            guard let self, self.настроена else { return }
            let нужна: AVCaptureDevice.Position = self.сторона == .back ? .front : .back
            guard let новая = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: нужна),
                  let вход = try? AVCaptureDeviceInput(device: новая) else { return }
            if let у = self.устройство, у.hasTorch, у.torchMode == .on, (try? у.lockForConfiguration()) != nil {
                у.torchMode = .off
                у.unlockForConfiguration()
            }
            let прежние = self.сессия.inputs
            self.сессия.beginConfiguration()
            for старый in прежние { self.сессия.removeInput(старый) }
            if self.сессия.canAddInput(вход) {
                self.сессия.addInput(вход)
                self.устройство = новая
                self.сторона = нужна
            } else {
                for старый in прежние where self.сессия.canAddInput(старый) { self.сессия.addInput(старый) }
            }
            self.сессия.commitConfiguration()
            let фонарь = self.устройство?.hasTorch ?? false
            self.наГлавной {
                self.фонарикЕсть = фонарь
                self.фонарик = false
            }
        }
    }

    func переключитьФонарик() {
        очередь.async { [weak self] in
            guard let self, let у = self.устройство, у.hasTorch else { return }
            guard (try? у.lockForConfiguration()) != nil else { return }
            let включить = у.torchMode != .on
            у.torchMode = включить ? .on : .off
            у.unlockForConfiguration()
            self.наГлавной { self.фонарик = включить }
        }
    }

    /// Поворот превью (главная нить сообщает его и снимку).
    func запомнитьПоворот(_ угол: CGFloat) {
        очередь.async { [weak self] in
            guard let self, self.уголПоворота != угол else { return }
            self.уголПоворота = угол
            /* Живой поиск поворачивает кадры сам, по метке ориентации, — ему тоже. */
            (self.приёмникКадров as? АнализКадровПоиска)?.повернуть(угол)
        }
    }

    /// Затвор: снимок придёт в `готово` на главной нити.
    func снять(_ готово: @escaping @MainActor (UIImage) -> Void) {
        guard готова, !снимаем else { return }
        снимаем = true
        self.готово = готово
        очередь.async { [weak self] in
            guard let self else { return }
            /* Без живой видеосвязи (прерывание, неудачная смена камеры) capturePhoto бросает исключение — не снимаем. */
            guard self.сессия.isRunning, let связь = self.выход.connection(with: .video),
                  связь.isActive, связь.isEnabled else {
                self.наГлавной { self.снимаем = false }
                return
            }
            if связь.isVideoRotationAngleSupported(self.уголПоворота) {
                связь.videoRotationAngle = self.уголПоворота
            }
            self.выход.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let снимок = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        наГлавной {
            self.снимаем = false
            let действие = self.готово
            self.готово = nil
            guard let снимок, let действие else { return }
            Task { @MainActor in действие(снимок) }
        }
    }
}

/// Превью камеры во весь экран: AVCaptureVideoPreviewLayer с заполнением, поворот — по интерфейсу.
struct ПревьюКамерыПоиска: UIViewRepresentable {
    let камера: КамераПоиска

    final class Вид: UIView {
        weak var камера: КамераПоиска?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var слой: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            let угол: CGFloat
            switch window?.windowScene?.interfaceOrientation ?? .portrait {
            case .portraitUpsideDown: угол = 270
            case .landscapeLeft: угол = 180
            case .landscapeRight: угол = 0
            default: угол = 90
            }
            if let связь = слой.connection, связь.isVideoRotationAngleSupported(угол), связь.videoRotationAngle != угол {
                связь.videoRotationAngle = угол
            }
            камера?.запомнитьПоворот(угол)
        }
    }

    func makeUIView(context: Context) -> Вид {
        let вид = Вид()
        вид.backgroundColor = .black
        вид.камера = камера
        вид.слой.session = камера.сессия
        вид.слой.videoGravity = .resizeAspectFill
        return вид
    }

    func updateUIView(_ uiView: Вид, context: Context) {
        uiView.setNeedsLayout()
    }
}

/// Последнее фото галереи — только если доступ к фото уже дан (сами не спрашиваем: PhotosPicker его не требует).
enum ПоследнееФотоГалереи {
    static func загрузить(_ готово: @escaping (UIImage?) -> Void) {
        let статус = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard статус == .authorized || статус == .limited else {
            готово(nil)
            return
        }
        let отбор = PHFetchOptions()
        отбор.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        отбор.fetchLimit = 1
        guard let снимок = PHAsset.fetchAssets(with: .image, options: отбор).firstObject else {
            готово(nil)
            return
        }
        let настройки = PHImageRequestOptions()
        настройки.deliveryMode = .highQualityFormat
        настройки.resizeMode = .fast
        настройки.isNetworkAccessAllowed = false
        настройки.isSynchronous = false
        PHImageManager.default().requestImage(for: снимок, targetSize: CGSize(width: 160, height: 160),
                                              contentMode: .aspectFill, options: настройки) { кадр, _ in
            DispatchQueue.main.async { готово(кадр) }
        }
    }
}

// MARK: - Экран камеры

/// Тёмный экран камеры: ✕ и фонарик сверху, рамка с уголками; снизу три подписанные кнопки — «Галерея» (готовое фото),
/// большой затвор «Найти» (снимок того, что в рамке, — в поиск по фото) и «Авто» (автопоиск: похожие появляются сами,
/// пока наводят камеру, PhotoSearchLive.swift; включён или нет — запоминается на телефоне). Над рядом — подсказка,
/// а при «Авто» — полоса похожих. В первый раз на телефоне поверх камеры — карточка «Как искать по фото».
struct ЭкранКамерыПоиска: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    @ObservedObject var камера: КамераПоиска
    @ObservedObject var живой: ЖивойПоискКамеры
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.scenePhase) private var фаза
    @State private var миниатюра: UIImage? = nil
    @State private var вспышка = false
    /// Камеры нет — галерея открывается сама, но один раз.
    @State private var галереяОткрыта = false
    /// Экран на виду (не ушли к объявлению, к «Ищем похожие…», окно не закрыто) — фон и возврат из фона трогают камеру
    /// только тогда.
    @State private var виден = false
    /// Уходили в фон — по возвращении камеру запустить снова (простое «неактивно» её не трогает).
    @State private var вФоне = false
    /// Весть над рядом после нажатия «Авто»: true — включили, false — выключили, nil — не видна.
    @State private var автоВесть: Bool? = nil
    /// Номер вести: нажали «Авто» ещё раз — таймер прежней вести не гасит новую раньше срока.
    @State private var номерВести = 0
    /// Карточка «Как искать по фото» на экране.
    @State private var советВиден = false
    /// Превью (во весь экран, под краями) и место рамки (без краёв) в координатах окна; ноль — ещё не измерено.
    /// Из них — доля рамки на превью, по которой режется снимок затвора.
    @State private var местоПревью: CGRect = .zero
    @State private var местоРамки: CGRect = .zero
    /// «Авто» (живой поиск) включён. Ключ прежний, со времён переключателя «Навести камеру / Выбрать фото», — выбор
    /// людей сохраняется.
    @AppStorage("kliko.photosearch.live") private var живойРежим = false
    /// Карточку «Как искать по фото» уже закрыли «Понятно» — больше не показываем.
    @AppStorage("kliko.photosearch.tip1") private var советПрочитан = false

    /// Ширина колонок «Галерея» и «Авто» и колонки затвора: подписи под кнопками — на одной линии.
    private static let ширинаКнопки: CGFloat = 88
    private static let ширинаЗатвора: CGFloat = 96

    init(модель: ПоискПоФотоСайта, камера: КамераПоиска, живой: ЖивойПоискКамеры) {
        self.модель = модель
        self.камера = камера
        self.живой = живой
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    /// Сейчас живой поиск: «Авто» включён и камера есть.
    private var живаяСъёмка: Bool { живойРежим && живая }

    /// Живой поиск уснул — минуту не было движения.
    private var спит: Bool { живаяСъёмка && живой.спит }

    /// Весть и карточка появляются пружиной; при «Уменьшении движения» — только прозрачность, без полёта.
    private var анимацияПоявления: Animation {
        тихо ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.84)
    }

    private var переходВести: AnyTransition {
        тихо ? AnyTransition.opacity : AnyTransition.opacity.combined(with: AnyTransition.offset(y: 12))
    }

    private var переходСовета: AnyTransition {
        тихо ? AnyTransition.opacity : AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.94))
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            фон
            Color.white
                .opacity(вспышка ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if спит {
                ПаузаЖивогоПоиска { живой.проснуться() }
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                верх
                if живаяСъёмка, !живой.спит, let имя = живой.похоже {
                    ПодписьЖивогоПоиска(имя: имя)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                        .transition(.opacity)
                }
                Spacer(minLength: 12)
                if живая {
                    надРядом
                }
                низ
            }
            if советВиден && камера.доступ == .есть {
                /* Затемнение ловит касания: сначала «Понятно», потом камера. Доступ ещё не дан — карточка ждёт, не
                   споря с системным вопросом о камере. */
                Color.black
                    .opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .accessibilityHidden(true)
                СоветКамерыПоиска { закрытьСовет() }
                    .transition(переходСовета)
            }
        }
        .onAppear {
            виден = true
            /* Сначала режим, потом запуск: обе просьбы идут на одну очередь камеры, и сессия сразу собирается 1280×720. */
            if живаяСъёмка { живой.включить(камера: камера, поиск: модель) }
            камера.запустить()
            ПоследнееФотоГалереи.загрузить { кадр in миниатюра = кадр }
            показатьСоветПозже()
        }
        .onDisappear {
            виден = false
            живой.приостановить()
            камера.остановить()
        }
        .onChange(of: камера.доступ) { _, доступ in
            guard доступ == .нетКамеры, !галереяОткрыта else { return }
            галереяОткрыта = true
            модель.открытьГалерею()
        }
        .onChange(of: модель.галерея) { _, открыта in
            /* Пока выбирают фото в галерее, живой поиск не шлёт кадры из-под неё. */
            guard живаяСъёмка, виден, !живой.спит else { return }
            if открыта {
                живой.приостановить()
            } else {
                живой.включить(камера: камера, поиск: модель)
            }
        }
        .onChange(of: живойРежим) { _, включили in
            if включили {
                живой.включить(камера: камера, поиск: модель)
            } else {
                let спал = живой.спит
                живой.выключить()
                if спал && виден { камера.запустить() }
            }
        }
        .onChange(of: фаза) { _, новая in
            guard виден else { return }
            switch новая {
            case .background:
                вФоне = true
                живой.приостановить()
                камера.остановить()
            case .active:
                guard вФоне else { return }
                вФоне = false
                guard !спит else { return }
                /* Карточка «Как искать по фото» на экране — живой поиск ждёт «Понятно» (закрытьСовет). */
                if живаяСъёмка && !советВиден { живой.включить(камера: камера, поиск: модель) }
                камера.запустить()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Над рядом кнопок: весть после «Авто»; при «Авто» — полоса похожих (пока не спит), без него — подсказка.
    private var надРядом: some View {
        VStack(spacing: 0) {
            if let включён = автоВесть {
                плашкаАвто(включён)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .transition(переходВести)
            }
            if живойРежим {
                if !живой.спит {
                    ПолосаЖивогоПоиска(живой: живой)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
            } else {
                подсказка
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .transition(.opacity)
            }
        }
    }

    /// Рамка наведения: при «Авто» уходит, когда внизу уже похожие (не спорит с полосой) или камера спит.
    private var рамкаНужна: Bool {
        !(живаяСъёмка && (живой.спит || !живой.товары.isEmpty))
    }

    @ViewBuilder
    private var фон: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ПревьюКамерыПоиска(камера: камера)
                .background { замер { местоПревью = $0 } }
                .ignoresSafeArea()
                .opacity(камера.готова ? 1 : 0)
                .animation(ДвижениеСайта.появление, value: камера.готова)
                .accessibilityHidden(true)
            /* Место рамки — тот же слот, что у РамкаПоискаФото (без ignoresSafeArea), и тогда, когда рамка убрана. */
            замер { местоРамки = $0 }
            if рамкаНужна {
                РамкаПоискаФото(тихо: тихо)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        case .запрещён:
            заглушка(значок: "camera.fill", заголовок: т("ps_denied"), текст: т("ps_denied_hint"), настройки: true)
        case .нетКамеры:
            заглушка(значок: "camera.fill", заголовок: т("ps_no_cam"), текст: т("ps_no_cam_hint"), настройки: false)
        }
    }

    /// Невидимый замер места в координатах окна — при появлении и при каждой смене (onGeometryChange — только iOS 18).
    private func замер(_ запомнить: @escaping (CGRect) -> Void) -> some View {
        GeometryReader { г in
            Color.clear
                .onAppear { запомнить(г.frame(in: CoordinateSpace.global)) }
                .onChange(of: г.frame(in: CoordinateSpace.global)) { _, новое in запомнить(новое) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Рамка наведения в координатах окна — по той же формуле, что её рисует; место не измерено — nil.
    private var рамкаНаЭкране: CGRect? {
        guard местоРамки.width > 0, местоРамки.height > 0 else { return nil }
        return РамкаПоискаФото.прямоугольник(в: местоРамки.size).offsetBy(dx: местоРамки.minX, dy: местоРамки.minY)
    }

    private var верх: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("close")) { модель.закрыть() }
            Spacer(minLength: 0)
            Text(т("ps_title"))
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if камера.фонарикЕсть && живая && !спит {
                КруглаяКнопкаФото(значок: камера.фонарик ? "flashlight.on.fill" : "flashlight.off.fill",
                                  подпись: камера.фонарик ? т("ps_torch_off") : т("ps_torch_on"),
                                  активна: камера.фонарик) { камера.переключитьФонарик() }
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// «Поместите вещь в рамку и нажмите «Найти»…» на тёмной капсуле (без «Авто»): рамка решает, что уйдёт на сайт.
    private var подсказка: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .accessibilityHidden(true)
            Text(т("ps_cam_hint"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    /// Весть после «Авто» — капсула над рядом на 1,6 с: включён — наводите камеру, выключен — снимайте «Найти».
    private func плашкаАвто(_ включён: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: включён ? "sparkles" : "camera.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .accessibilityHidden(true)
            Text(т(включён ? "ps_cam_auto_toast_on" : "ps_cam_auto_toast_off"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.75), in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.зелёныйЯркий.opacity(0.6), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Нижний ряд: «Галерея», затвор «Найти», «Авто» — у каждой кнопки подпись снизу (без камеры «Авто» нет, место
    /// той же ширины остаётся пустым, затвор не съезжает).
    private var низ: some View {
        HStack(alignment: .top, spacing: 0) {
            кнопкаГалереи
            Spacer(minLength: 8)
            затвор
            Spacer(minLength: 8)
            if живая {
                кнопкаАвто
            } else {
                Color.clear
                    .frame(width: Self.ширинаКнопки, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// Подпись под кнопкой ряда: мелкий белый текст, растёт с «Размером текста» до предела — ряд не разъезжается.
    private func подписьКнопки(_ текст: String) -> some View {
        Text(текст)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .shadow(color: Color.black.opacity(0.6), radius: 2)
    }

    /// «Галерея»: миниатюра последнего фото (галереи или этой камеры), иначе значок; подпись под ней.
    private var кнопкаГалереи: some View {
        Button { модель.открытьГалерею() } label: {
            VStack(spacing: 6) {
                миниатюраГалереи
                    .frame(height: 80)
                подписьКнопки(т("ps_cam_gallery"))
            }
            .frame(width: Self.ширинаКнопки)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(т("ps_gallery"))
    }

    private var миниатюраГалереи: some View {
        ZStack {
            if let кадр = миниатюра ?? модель.последний {
                Image(uiImage: кадр)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.14)
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
        }
    }

    /// Большой затвор «Найти»: белое кольцо и круг (во время снимка круг зеленеет), подпись под ним.
    private var затвор: some View {
        Button { снять() } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(камера.снимаем ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 64, height: 64)
                }
                подписьКнопки(т("ps_cam_find"))
            }
            .frame(width: Self.ширинаЗатвора)
            .contentShape(Rectangle())
            .opacity(камера.готова ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!камера.готова || камера.снимаем)
        .accessibilityLabel(т("ps_cam_find_a11y"))
        .accessibilityHint(т("ps_cam_find_hint"))
    }

    /// «Авто» — автопоиск: выключен — белые искры на тёмном круге, включён — зелёный круг, как включённый фонарик.
    private var кнопкаАвто: some View {
        Button { переключитьАвто() } label: {
            VStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(живойРежим ? Color.black : Color.white)
                    .frame(width: 56, height: 56)
                    .background(живойРежим ? AnyShapeStyle(Theme.зелёныйЯркий)
                                           : AnyShapeStyle(Color.black.opacity(0.45)), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(живойРежим ? 0 : 0.5), lineWidth: 1.5) }
                    .frame(height: 80)
                подписьКнопки(живойРежим ? т("ps_cam_auto_on") : т("ps_cam_auto"))
            }
            .frame(width: Self.ширинаКнопки)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(т("ps_cam_auto_a11y"))
        .accessibilityValue(живойРежим ? т("ps_cam_auto_v_on") : т("ps_cam_auto_v_off"))
        .accessibilityHint(т("ps_cam_tip_auto"))
    }

    /// «Авто»: лёгкий щелчок, режим — в память телефона (живой поиск включает и выключает onChange(of: живойРежим)),
    /// над рядом — короткая весть, что теперь делать.
    private func переключитьАвто() {
        ОткликСайта.выбор()
        let включить = !живойРежим
        withAnimation(тихо ? nil : ДвижениеСайта.смена) { живойРежим = включить }
        показатьВестьАвто(включить)
    }

    private func показатьВестьАвто(_ включён: Bool) {
        номерВести += 1
        let номер = номерВести
        withAnimation(анимацияПоявления) { автоВесть = включён }
        UIAccessibility.post(notification: .announcement,
                             argument: т(включён ? "ps_cam_auto_toast_on" : "ps_cam_auto_toast_off"))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard номер == номерВести else { return }
            withAnimation(анимацияПоявления) { автоВесть = nil }
        }
    }

    /// Первый раз на телефоне — карточка «Как искать по фото», когда окно уже выехало. Пока она на экране, живой поиск
    /// стоит: кадры из-под затемнения не тратят часовой запас (БюджетЖивогоПоиска) и не меняют полосу.
    private func показатьСоветПозже() {
        guard !советПрочитан, !советВиден else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard виден, !советПрочитан else { return }
            withAnimation(анимацияПоявления) { советВиден = true }
            живой.приостановить()
        }
    }

    /// «Понятно»: карточка уходит, живой поиск (если «Авто» включён и экран на виду) — снова.
    private func закрытьСовет() {
        советПрочитан = true
        withAnimation(анимацияПоявления) { советВиден = false }
        if живаяСъёмка && виден && !живой.спит { живой.включить(камера: камера, поиск: модель) }
    }

    private func снять() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !тихо {
            вспышка = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeOut(duration: 0.3)) { вспышка = false }
            }
        }
        /* При «Авто» затвор — тот же полный поиск по фото этим снимком; полоса живого — с чистого листа, когда сюда
           вернутся («Снять ещё»). */
        let живойСнимок = живаяСъёмка
        /* Где рамка на превью — сейчас, пока экран тот же: снимок придёт позже. Режем только по рамке на экране: при
           «Авто» с похожими внизу (или во сне) её не видно — тогда, как и живой поиск, весь кадр. */
        let доля = рамкаНужна ? рамкаНаЭкране.flatMap { ОбрезкаСнимкаПоиска.доля(рамки: $0, превью: местоПревью) } : nil
        let превью = местоПревью.size
        камера.снять { снимок in
            if живойСнимок { живой.забыть() }
            /* В модель — часть в рамке: сайту меньше фона, и «Ищем похожие…» показывает то, что искали. */
            модель.снято(ОбрезкаСнимкаПоиска.обрезать(снимок, доля: доля, превью: превью))
        }
    }

    /// Нет доступа или камеры: значок, объяснение, «Выбрать из галереи» и (если запрещено) «Открыть Настройки».
    private func заглушка(значок: String, заголовок: String, текст: String, настройки: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: значок)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .frame(width: 76, height: 76)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                ЗелёнаяКнопкаФото(заголовок: т("ps_gallery"), значок: "photo.on.rectangle") {
                    модель.открытьГалерею()
                }
                .padding(.bottom, 10)
                if настройки {
                    ЗелёнаяКнопкаФото(заголовок: т("ps_settings"), значок: "gearshape", контурная: true,
                                      наТёмном: true) {
                        if let адрес = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(адрес)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 120)
            .padding(.bottom, 140)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Круглая кнопка 44 pt на тёмной полупрозрачной подложке; включённая (фонарик) — зелёная.
struct КруглаяКнопкаФото: View {
    let значок: String
    let подпись: String
    var активна = false
    let действие: () -> Void

    init(значок: String, подпись: String, активна: Bool = false, действие: @escaping () -> Void) {
        self.значок = значок
        self.подпись = подпись
        self.активна = активна
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(активна ? Color.black : Color.white)
                .frame(width: 44, height: 44)
                .background(активна ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.45)),
                            in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(активна ? 0 : 0.16), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }
}

/// Рамка наведения: зелёные уголки по центру, тихое «дыхание» и бегущая линия; при «Уменьшении движения» — неподвижна.
/// Где она стоит — прямоугольник(в:): по той же формуле снимок затвора режется (ОбрезкаСнимкаПоиска).
struct РамкаПоискаФото: View {
    let тихо: Bool
    @State private var дышит = false
    @State private var бег = false

    /// Квадрат рамки в месте размера `место`, в координатах этого места: сторона — меньшее из 72 % ширины, половины
    /// высоты и 320 pt; центр — середина ширины, по высоте на 30 pt выше середины. Одна формула — и для рисования,
    /// и для обрезки снимка.
    static func прямоугольник(в место: CGSize) -> CGRect {
        let сторона = max(0, min(место.width * 0.72, место.height * 0.5, 320))
        return CGRect(x: место.width / 2 - сторона / 2, y: место.height / 2 - 30 - сторона / 2,
                      width: сторона, height: сторона)
    }

    var body: some View {
        GeometryReader { место in
            let рамка = Self.прямоугольник(в: место.size)
            ZStack {
                if !тихо {
                    LinearGradient(colors: [Theme.зелёныйЯркий.opacity(0), Theme.зелёныйЯркий.opacity(0.9),
                                            Theme.зелёныйЯркий.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .shadow(color: Theme.зелёныйЯркий.opacity(0.8), radius: 6)
                        .padding(.horizontal, 18)
                        .offset(y: бег ? рамка.height / 2 - 18 : -рамка.height / 2 + 18)
                        .opacity(0.85)
                }
                УголкиПоискаФото(длина: 36, цвет: Theme.зелёныйЯркий, толщина: 4)
            }
            .frame(width: рамка.width, height: рамка.height)
            .scaleEffect(дышит ? 1.035 : 1)
            .position(x: рамка.midX, y: рамка.midY)
        }
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { дышит = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { бег = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Подсказка первого раза

/// «Как искать по фото» — один раз на телефоне поверх камеры: «Найти», «Галерея», «Авто» и «Понятно». Тёмное стекло
/// (окно камеры — в тёмной схеме), текст растёт с «Размером текста»; не влезает по высоте — листается.
struct СоветКамерыПоиска: View {
    let понятно: () -> Void

    init(понятно: @escaping () -> Void) {
        self.понятно = понятно
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            карточка
            ScrollView {
                карточка
                    .padding(.vertical, 16)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var карточка: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(т("ps_cam_tip_title"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            строка(значок: "camera.fill", слово: т("ps_cam_find"), пояснение: т("ps_cam_tip_find"))
            строка(значок: "photo.on.rectangle", слово: т("ps_cam_gallery"), пояснение: т("ps_cam_tip_gallery"))
            строка(значок: "sparkles", слово: т("ps_cam_auto"), пояснение: т("ps_cam_tip_auto"))
            ЗелёнаяКнопкаФото(заголовок: т("ps_cam_tip_ok"), значок: "checkmark", действие: понятно)
                .padding(.top, 4)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
    }

    /// Строка: значок в круге, жирное слово кнопки и что она делает.
    private func строка(значок: String, слово: String, пояснение: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: значок)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(слово)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(пояснение)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Обрезка снимка по рамке

/**
 Снимок затвора — серверу только то, что в рамке, с запасом: меньше фона — ИИ сайта лучше узнаёт вещь. Чистые функции
 без состояния, годятся для любой нити (экран зовёт обрезку на главной сразу после снимка: рисуется только часть до
 2048 px — не дольше прежнего сжатия целого кадра); галерея не режется.

 Координаты. Превью (ПревьюКамерыПоиска, AVCaptureVideoPreviewLayer с .resizeAspectFill) лежит во весь экран, под
 краями (ignoresSafeArea); рамка — в месте без краёв. Оба замерены в координатах окна (ЭкранКамерыПоиска), отсюда доля
 рамки на превью, 0…1. Снимок камеры повёрнут меткой ориентации (.right у портрета): UIImage.size — уже размер «как
 видно», а UIImage.draw рисует снимок повёрнутым. Поэтому пиксели части считаем в видимом снимке и рисуем её сразу
 ровно (.up, масштаб 1) — выпрямление и обрезка одним рисованием, без полноразмерной копии снимка.
 */
enum ОбрезкаСнимкаПоиска {
    /// Запас вокруг рамки — доля её стороны с каждой стороны.
    static let запас: CGFloat = 0.25
    /// Часть уже этой доли короткой стороны снимка — замер сбился, режем не то: снимок уходит целиком.
    static let меньшаяДоля: CGFloat = 0.3
    /// Большая сторона части — не больше: сайт всё равно получает до 1024 (ПоискПоФотоAPI.сжать).
    static let предел: CGFloat = 2048

    /// Рамка на превью долями его ширины и высоты (0…1); оба прямоугольника — в одних координатах. Нет замера — nil.
    static func доля(рамки рамка: CGRect, превью: CGRect) -> CGRect? {
        guard рамка.width > 0, рамка.height > 0, превью.width > 0, превью.height > 0 else { return nil }
        return CGRect(x: (рамка.minX - превью.minX) / превью.width, y: (рамка.minY - превью.minY) / превью.height,
                      width: рамка.width / превью.width, height: рамка.height / превью.height)
    }

    /// Доля рамки на превью → пиксели снимка. Превью заполняет вид (aspect-fill): масштаб = max(Wпревью / Wснимка,
    /// Hпревью / Hснимка), снимок по центру, лишнее ушло за края экрана. Потом запас 25 % с каждой стороны и края
    /// снимка. Нулевые размеры или часть меньше 30 % короткой стороны снимка — nil.
    static func область(доля: CGRect, превью: CGSize, снимок: CGSize) -> CGRect? {
        guard превью.width > 0, превью.height > 0, снимок.width > 0, снимок.height > 0,
              доля.width > 0, доля.height > 0 else { return nil }
        let масштаб = max(превью.width / снимок.width, превью.height / снимок.height)
        /* Где левый верхний угол снимка на превью: ≤ 0 — края снимка срезаны краями экрана. */
        let сдвигX = (превью.width - снимок.width * масштаб) / 2
        let сдвигY = (превью.height - снимок.height * масштаб) / 2
        let x = (доля.minX * превью.width - сдвигX) / масштаб
        let y = (доля.minY * превью.height - сдвигY) / масштаб
        let ш = доля.width * превью.width / масштаб
        let в = доля.height * превью.height / масштаб
        let сЗапасом = CGRect(x: x - ш * запас, y: y - в * запас,
                              width: ш * (1 + 2 * запас), height: в * (1 + 2 * запас))
        let часть = сЗапасом.integral.intersection(CGRect(origin: .zero, size: снимок))
        guard !часть.isNull, часть.width > 0, часть.height > 0 else { return nil }
        let наименьшая = min(снимок.width, снимок.height) * меньшаяДоля
        guard часть.width >= наименьшая, часть.height >= наименьшая else { return nil }
        return часть
    }

    /// Снимок затвора → часть в рамке, ровно (.up) и в масштабе 1. Нет доли или часть не вышла — снимок как есть.
    static func обрезать(_ снимок: UIImage, доля: CGRect?, превью: CGSize) -> UIImage {
        guard let доля else { return снимок }
        let пиксели = CGSize(width: снимок.size.width * снимок.scale, height: снимок.size.height * снимок.scale)
        guard let часть = область(доля: доля, превью: превью, снимок: пиксели) else { return снимок }
        let k = min(1, предел / max(часть.width, часть.height))
        let размер = CGSize(width: max(1, (часть.width * k).rounded()), height: max(1, (часть.height * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        return UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
            /* Весь снимок, сдвинутый так, что часть легла в начало холста; поворот по метке draw делает сам. */
            снимок.draw(in: CGRect(x: -часть.minX * k, y: -часть.minY * k,
                                   width: пиксели.width * k, height: пиксели.height * k))
        }
    }
}
