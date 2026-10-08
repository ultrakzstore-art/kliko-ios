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
    /// Живой поиск («Навести камеру», PhotoSearchLive.swift): выход кадров видео и кому их отдавать — только на очереди
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

    /// «Навести камеру»: кадры видео идут приёмнику на его очереди, сессия — 1280×720 (меньше работы и батареи);
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

/// Тёмный экран камеры: ✕ и фонарик сверху, рамка с уголками и подсказка, снизу галерея и затвор.
/// Над затвором — режим: «Навести камеру» (живой поиск, PhotoSearchLive.swift) или «Выбрать фото» (снимок и галерея,
/// как раньше); последний выбор запоминается на телефоне.
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
    /// Последний выбранный режим: true — «Навести камеру».
    @AppStorage("kliko.photosearch.live") private var живойРежим = false

    init(модель: ПоискПоФотоСайта, камера: КамераПоиска, живой: ЖивойПоискКамеры) {
        self.модель = модель
        self.камера = камера
        self.живой = живой
    }

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    /// Сейчас живой поиск: режим выбран и камера есть.
    private var живаяСъёмка: Bool { живойРежим && живая }

    /// Живой поиск уснул — минуту не было движения.
    private var спит: Bool { живаяСъёмка && живой.спит }

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
                    низЖивого
                }
                низ
            }
        }
        .onAppear {
            виден = true
            /* Сначала режим, потом запуск: обе просьбы идут на одну очередь камеры, и сессия сразу собирается 1280×720. */
            if живаяСъёмка { живой.включить(камера: камера, поиск: модель) }
            камера.запустить()
            ПоследнееФотоГалереи.загрузить { кадр in миниатюра = кадр }
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
                if живаяСъёмка { живой.включить(камера: камера, поиск: модель) }
                камера.запустить()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    /// Над затвором: в живом режиме — полоса похожих (пока не спит), в режиме снимка — подсказка; ниже — переключатель.
    private var низЖивого: some View {
        VStack(spacing: 0) {
            if живойРежим {
                if !живой.спит {
                    ПолосаЖивогоПоиска(живой: живой)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                }
            } else {
                подсказка
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
            }
            ПереключательРежимаКамеры(живой: $живойРежим)
                .padding(.horizontal, 16)
        }
    }

    /// Рамка наведения: в живом режиме уходит, когда внизу уже похожие (не спорит с полосой) или камера спит.
    private var рамкаНужна: Bool {
        !(живаяСъёмка && (живой.спит || !живой.товары.isEmpty))
    }

    @ViewBuilder
    private var фон: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ПревьюКамерыПоиска(камера: камера)
                .ignoresSafeArea()
                .opacity(камера.готова ? 1 : 0)
                .animation(ДвижениеСайта.появление, value: камера.готова)
                .accessibilityHidden(true)
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

    /// «Наведите на вещь — найдём похожие на Kliko» на тёмной капсуле.
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

    private var низ: some View {
        HStack(alignment: .center, spacing: 0) {
            кнопкаГалереи
            Spacer(minLength: 16)
            затвор
            Spacer(minLength: 16)
            Color.clear
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.6)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// Галерея: миниатюра последнего фото (галереи или этой камеры), иначе значок.
    private var кнопкаГалереи: some View {
        Button { модель.открытьГалерею() } label: {
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
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(т("ps_gallery"))
    }

    /// Большой затвор: белое кольцо и круг; во время снимка круг зеленеет.
    private var затвор: some View {
        Button { снять() } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 5)
                    .frame(width: 80, height: 80)
                Circle()
                    .fill(камера.снимаем ? Theme.зелёныйЯркий : Color.white)
                    .frame(width: 64, height: 64)
            }
            .contentShape(Circle())
            .opacity(камера.готова ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!камера.готова || камера.снимаем)
        .accessibilityLabel(живаяСъёмка ? т("shoot") : т("ps_shutter"))
        .accessibilityHint(т("ps_cam_hint"))
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
        /* В живом режиме затвор — «Снять»: тот же полный поиск по фото этим снимком; полоса живого — с чистого листа,
           когда сюда вернутся («Снять ещё»). */
        let живойСнимок = живаяСъёмка
        камера.снять { снимок in
            if живойСнимок { живой.забыть() }
            модель.снято(снимок)
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
struct РамкаПоискаФото: View {
    let тихо: Bool
    @State private var дышит = false
    @State private var бег = false

    var body: some View {
        GeometryReader { место in
            let сторона = min(место.size.width * 0.72, место.size.height * 0.5, 320)
            ZStack {
                if !тихо {
                    LinearGradient(colors: [Theme.зелёныйЯркий.opacity(0), Theme.зелёныйЯркий.opacity(0.9),
                                            Theme.зелёныйЯркий.opacity(0)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 2)
                        .shadow(color: Theme.зелёныйЯркий.opacity(0.8), radius: 6)
                        .padding(.horizontal, 18)
                        .offset(y: бег ? сторона / 2 - 18 : -сторона / 2 + 18)
                        .opacity(0.85)
                }
                УголкиПоискаФото(длина: 36, цвет: Theme.зелёныйЯркий, толщина: 4)
            }
            .frame(width: сторона, height: сторона)
            .scaleEffect(дышит ? 1.035 : 1)
            .position(x: место.size.width / 2, y: место.size.height / 2 - 30)
        }
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { дышит = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { бег = true }
        }
        .accessibilityHidden(true)
    }
}
