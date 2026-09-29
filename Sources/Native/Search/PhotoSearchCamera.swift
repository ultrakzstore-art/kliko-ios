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

    let сессия = AVCaptureSession()
    private let очередь = DispatchQueue(label: "kz.kliko.photosearch.camera")
    private let выход = AVCapturePhotoOutput()
    private var устройство: AVCaptureDevice? = nil
    private var настроена = false
    /// Поворот кадра — как у интерфейса (на iPhone всегда портрет, 90°).
    private var уголПоворота: CGFloat = 90
    private var готово: (@MainActor (UIImage) -> Void)? = nil

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
            self.наГлавной {
                self.доступ = .есть
                self.готова = true
                self.фонарикЕсть = фонарь
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
        сессия.commitConfiguration()
        устройство = камера
        настроена = true
        return true
    }

    /// Ушли с экрана камеры: фонарик гаснет, сессия останавливается.
    func остановить() {
        очередь.async { [weak self] in
            guard let self else { return }
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
        очередь.async { [weak self] in self?.уголПоворота = угол }
    }

    /// Затвор: снимок придёт в `готово` на главной нити.
    func снять(_ готово: @escaping @MainActor (UIImage) -> Void) {
        guard готова, !снимаем else { return }
        снимаем = true
        self.готово = готово
        очередь.async { [weak self] in
            guard let self else { return }
            guard self.сессия.isRunning else {
                self.наГлавной { self.снимаем = false }
                return
            }
            if let связь = self.выход.connection(with: .video),
               связь.isVideoRotationAngleSupported(self.уголПоворота) {
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
struct ЭкранКамерыПоиска: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    @ObservedObject var камера: КамераПоиска
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var миниатюра: UIImage? = nil
    @State private var вспышка = false
    /// Камеры нет — галерея открывается сама, но один раз.
    @State private var галереяОткрыта = false

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            фон
            Color.white
                .opacity(вспышка ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                верх
                Spacer(minLength: 12)
                if живая {
                    подсказка
                        .padding(.horizontal, 24)
                        .padding(.bottom, 18)
                }
                низ
            }
        }
        .onAppear {
            камера.запустить()
            ПоследнееФотоГалереи.загрузить { кадр in миниатюра = кадр }
        }
        .onDisappear { камера.остановить() }
        .onChange(of: камера.доступ) { _, доступ in
            guard доступ == .нетКамеры, !галереяОткрыта else { return }
            галереяОткрыта = true
            модель.открытьГалерею()
        }
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
            РамкаПоискаФото(тихо: тихо)
                .allowsHitTesting(false)
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
            if камера.фонарикЕсть && живая {
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
        .accessibilityLabel(т("ps_shutter"))
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
        камера.снять { снимок in
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
