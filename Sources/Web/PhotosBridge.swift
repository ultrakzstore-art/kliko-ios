import UIKit
import WebKit
import PhotosUI

/// Выбор снимков ТОЛЬКО из медиатеки телефона (мост klikoPhotos).
///
/// Владелец 22.09.2026: «камера и так открыта — без возможности выбора с файлов и с других мест»;
/// 23.09.2026: «собери приложение, чтобы на камере просил только фото с галереи».
///
/// ПОЧЕМУ НУЖЕН НАТИВ. В WKWebView обычный `<input type="file" accept="image/*">` открывает системный
/// лист с тремя дорогами: «Фото», «Снять фото» и «Выбрать файл». Убрать из него лишнее со стороны
/// страницы нельзя — атрибута «только медиатека» в вебе не существует (`capture` умеет ровно обратное,
/// заставить камеру). А лист этот в нашем случае бессмысленный: человек уже стоит в открытой камере и
/// нажал «Галерея» — ему нужна только плёнка, и «Файлы» с iCloud Drive рядом сбивают.
///
/// PHPickerViewController показывается системой в ОТДЕЛЬНОМ процессе и не требует разрешения на доступ
/// к фото: приложение получает только те снимки, которые человек выбрал сам. Поэтому ни окна «Разрешить
/// доступ к Фото», ни ключа NSPhotoLibraryUsageDescription не нужно — и App Review нечего спрашивать.
///
/// Страница зовёт `window.KlikoPhotos.pick(сколько)` и получает обещание `{ok, files}`, где files —
/// обычные File, как из `<input type="file">`; дальше их принимает тот же код подачи (см. WebContainer.liveBridgeJS).
final class PhotosBridge: NSObject, PHPickerViewControllerDelegate {
    weak var webView: WKWebView?
    private var ждёт: Int = 0

    /// Сторона длинной грани и качество JPEG. Снимок с телефона — это 12 мегапикселей и 4-8 МБ HEIC;
    /// объявлению столько не нужно (витрина всё равно ужимает), а через мост такой кадр поедет секундами
    /// и займёт память и там, и в странице. 1600 точек хватает и для карточки, и для разбора ИИ.
    private let сторона: CGFloat = 1600
    private let качество: CGFloat = 0.82

    func pick(id: Int, limit: Int) {
        ждёт = id
        DispatchQueue.main.async {
            var настройки = PHPickerConfiguration(photoLibrary: .shared())
            настройки.filter = .images                      // только снимки: видео объявлению не нужно
            настройки.selectionLimit = max(1, min(limit, 10))
            настройки.selection = .ordered                  // порядок выбора = порядок кадров
            let пикер = PHPickerViewController(configuration: настройки)
            пикер.delegate = self
            guard let верх = PhotosBridge.верхнийЭкран() else {
                self.готово(0, code: "no_view")
                return
            }
            верх.present(пикер, animated: true)
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let id = ждёт
        guard !results.isEmpty else { готово(0, code: "cancel"); return }

        /* Кадры уходят в страницу ПО ОДНОМУ, а не одним куском: восемь снимков одной строкой — это
           несколько мегабайт в одном вызове JavaScript, и на слабом телефоне это заметная пауза.
           Порядок сохраняем: грузим параллельно, но раскладываем по местам и отдаём по очереди. */
        /* Кадры готовятся параллельно, а складываются под замком: писать в один массив из нескольких
           потоков нельзя даже по разным местам — это не просто «редкая ошибка», а порча памяти. */
        var готовые = [Int: Data]()
        let замок = DispatchQueue(label: "kz.kliko.photos.collect")
        let группа = DispatchGroup()
        for (i, r) in results.enumerated() {
            группа.enter()
            r.itemProvider.loadObject(ofClass: UIImage.self) { объект, _ in
                defer { группа.leave() }
                guard let кадр = объект as? UIImage, let d = self.вjpeg(кадр) else { return }
                замок.sync { готовые[i] = d }
            }
        }
        группа.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            var ушло = 0
            for i in 0..<results.count {
                guard let d = замок.sync(execute: { готовые[i] }) else { continue }
                ушло += 1
                self.часть(id, имя: "photo\(i + 1).jpg", данные: d)
            }
            self.готово(ушло, code: ушло > 0 ? "" : "decode")
        }
    }

    /// МИНИАТЮРА ПОСЛЕДНЕГО СНИМКА ПЛЁНКИ — для плитки «Галерея» в камере.
    ///
    /// Владелец 23.09.2026: «в камере с левой стороны, где выбор с галереи, должно показывать последнее фото с
    /// галереи». В родной камере телефона эта плитка показывает именно последний кадр плёнки, и без неё кнопка
    /// читается как пустой квадрат.
    ///
    /// Здесь, в отличие от выбора снимков, нужен НАСТОЯЩИЙ доступ к медиатеке: прочитать чужой (не выбранный
    /// человеком) кадр иначе нельзя. Поэтому спрашиваем разрешение — и молча отступаем, если его не дали:
    /// страница оставит свой значок, кнопка продолжит работать. Сами по кругу не переспрашиваем — это делает
    /// система. При «ограниченном доступе» плёнка видна не вся: тогда покажем последний из разрешённых, а если
    /// разрешённых нет — ответим пустым, и это не ошибка.
    func latest(id: Int) {
        let статус = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch статус {
        case .authorized, .limited:
            взятьПоследний(id)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] новый in
                guard let self = self else { return }
                if новый == .authorized || новый == .limited { self.взятьПоследний(id) }
                else { self.миниатюра(id, b64: "") }
            }
        default:
            миниатюра(id, b64: "")
        }
    }

    private func взятьПоследний(_ id: Int) {
        let отбор = PHFetchOptions()
        отбор.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        отбор.fetchLimit = 1
        guard let снимок = PHAsset.fetchAssets(with: .image, options: отбор).firstObject else {
            миниатюра(id, b64: "")   // плёнка пуста или показывать нечего
            return
        }
        let настройки = PHImageRequestOptions()
        настройки.deliveryMode = .highQualityFormat   // один ответ, а не «сначала мыло, потом резкое»
        настройки.resizeMode = .exact
        настройки.isNetworkAccessAllowed = true       // кадр может лежать только в iCloud
        настройки.isSynchronous = false
        var ответил = false
        PHImageManager.default().requestImage(for: снимок,
                                              targetSize: CGSize(width: 240, height: 240),
                                              contentMode: .aspectFill,
                                              options: настройки) { [weak self] кадр, _ in
            guard let self = self, !ответил else { return }
            ответил = true
            let данные = кадр?.jpegData(compressionQuality: 0.7)
            self.миниатюра(id, b64: данные?.base64EncodedString() ?? "")
        }
    }

    private func миниатюра(_ id: Int, b64: String) {
        let js = "window.__klikoPhotoLatest && window.__klikoPhotoLatest(\(id), '\(b64)')"
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(js) }
    }

    /// Ужать до разумной стороны и перекодировать в JPEG. HEIC с телефона веб-страница читает не везде,
    /// а JPEG понимают все — и сервер, и разбор по фото.
    private func вjpeg(_ кадр: UIImage) -> Data? {
        let б = max(кадр.size.width, кадр.size.height)
        guard б > 0 else { return nil }
        let k = min(1, сторона / б)
        if k >= 1 { return кадр.jpegData(compressionQuality: качество) }
        let размер = CGSize(width: кадр.size.width * k, height: кадр.size.height * k)
        let рисовальщик = UIGraphicsImageRenderer(size: размер)
        let меньше = рисовальщик.image { _ in кадр.draw(in: CGRect(origin: .zero, size: размер)) }
        return меньше.jpegData(compressionQuality: качество)
    }

    private func часть(_ id: Int, имя: String, данные: Data) {
        let b64 = данные.base64EncodedString()
        let js = "window.__klikoPhotoPart && window.__klikoPhotoPart(\(id), '\(имя)', '\(b64)')"
        webView?.evaluateJavaScript(js)
    }

    private func готово(_ сколько: Int, code: String) {
        let id = ждёт
        let js = "window.__klikoPhotoDone && window.__klikoPhotoDone(\(id), \(сколько), '\(code)')"
        DispatchQueue.main.async { [weak self] in self?.webView?.evaluateJavaScript(js) }
    }

    private static func верхнийЭкран() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var экран = окна.first(where: { $0.isKeyWindow })?.rootViewController ?? окна.first?.rootViewController
        while let сверху = экран?.presentedViewController { экран = сверху }
        return экран
    }
}
