import SwiftUI
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

/// Фото студии: адрес, уменьшенная картинка для карточки, размытый фон (R сайта) и «в ролике ли».
struct ФотоРолика: Identifiable, Equatable {
    let id: String
    let адрес: URL
    var картинка: UIImage? = nil
    var фон: UIImage? = nil
    var включено: Bool
    var загружено = false
}

/// Готовка фото вне главной нити: уменьшить для карточки и размыть для фона.
enum ПодготовкаФотоРолика {
    /// Картинка карточки: сторона не больше 1400 (в кадре она не больше 960 × 1060), фон — 216 × 384 с размытием.
    static func подготовить(_ адрес: URL) async -> (UIImage?, UIImage?) {
        guard let исходная = await ПоделитьсяСайта.загрузить(адрес) else { return (nil, nil) }
        let карточка = уменьшить(исходная, сторона: 1400)
        return (карточка, размыть(карточка))
    }

    static func уменьшить(_ картинка: UIImage, сторона: CGFloat) -> UIImage {
        let размер = картинка.size
        guard размер.width > 0, размер.height > 0 else { return картинка }
        let k = min(1, сторона / max(размер.width, размер.height))
        let новый = CGSize(width: (размер.width * k).rounded(), height: (размер.height * k).rounded())
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        return UIGraphicsImageRenderer(size: новый, format: формат).image { _ in
            картинка.draw(in: CGRect(origin: .zero, size: новый))
        }
    }

    /// R сайта: фото «обложкой» в 216 × 384 и сильно размыто — фон кадра.
    static func размыть(_ картинка: UIImage) -> UIImage? {
        let холст = CGSize(width: 216, height: 384)
        let размер = картинка.size
        guard размер.width > 0, размер.height > 0 else { return nil }
        let k = max(холст.width / размер.width, холст.height / размер.height)
        let w = размер.width * k
        let h = размер.height * k
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let малое = UIGraphicsImageRenderer(size: холст, format: формат).image { _ in
            картинка.draw(in: CGRect(x: (холст.width - w) / 2, y: (холст.height - h) / 2, width: w, height: h))
        }
        guard let вход = CIImage(image: малое) else { return малое }
        let фильтр = CIFilter.gaussianBlur()
        фильтр.inputImage = вход.clampedToExtent()
        фильтр.radius = 7
        guard let выход = фильтр.outputImage?.cropped(to: вход.extent),
              let готово = CIContext().createCGImage(выход, from: вход.extent) else { return малое }
        return UIImage(cgImage: готово)
    }
}

/// Одна соцсеть social_status для автопостинга из студии.
struct СоцсетьРолика: Equatable {
    var включено = false
    var подключено = false
    var имя = ""
}

/// Ящик для идентификатора ролика в Фото: блок performChanges его заполняет.
private final class ЯщикИдРолика: @unchecked Sendable {
    var ид: String? = nil
}

/**
 Состояние студии роликов: объявление и его фото (my_items сайта, как openReelForListing), стиль, тексты, звук, превью
 и запись. Любая правка после готового ролика возвращает к превью — как reelReroll сайта сбрасывает готовое видео.
 */
@MainActor
final class МодельСтудииРоликов: ObservableObject {
    enum Этап: Equatable {
        case превью
        case запись(Double, ЭтапЗаписиРолика)
        case готово(ГотовыйРолик)
        case сбой
    }

    static let ссылкаAppStore = "https://apps.apple.com/kz/app/kliko-kz/id6805824484"
    static let наибольшеФото = 5

    let данные: ДанныеОтправкиСайта
    var закрыть: (() -> Void)? = nil

    @Published private(set) var загружается = true
    @Published var фото: [ФотоРолика] = [] { didSet { if фото != oldValue { изменено() } } }
    @Published var номерСтиля: Int { didSet { if номерСтиля != oldValue { изменено() } } }
    @Published var название: String { didSet { if название != oldValue { изменено() } } }
    @Published var цена: String { didSet { if цена != oldValue { изменено() } } }
    @Published var призыв: String { didSet { if призыв != oldValue { изменено() } } }
    @Published var звук = true { didSet { if звук != oldValue { сброситьГотовое() } } }
    @Published var громкость: Double = 1 { didSet { if готовый != nil && громкость != oldValue { сброситьГотовое() } } }
    @Published private(set) var рисовальщик: РисовальщикРолика? = nil
    @Published private(set) var этап: Этап = .превью
    @Published private(set) var тост: String? = nil
    @Published private(set) var картинкаГотовится = false
    @Published private(set) var соцсети: [String: СоцсетьРолика]? = nil
    @Published private(set) var публикуется: String? = nil
    @Published private(set) var опубликованоВ: Set<String> = []

    private var пары: [ПараРолика] = []
    private var город = ""
    private var qr: UIImage? = nil
    private var задача: Task<Void, Never>? = nil
    private var задачаТоста: Task<Void, Never>? = nil
    private var начато = false

    init(данные: ДанныеОтправкиСайта) {
        self.данные = данные
        номерСтиля = СтильРолика.случайный(кроме: -1)
        название = данные.название
        цена = данные.цена > 0 ? "\(DesignText.число(Int(данные.цена.rounded()))) ₸" : ReelStudioText.т("negotiable")
        призыв = ReelStudioText.т("v_cta")
    }

    private func т(_ ключ: String) -> String { ReelStudioText.т(ключ) }

    var стиль: СтильРолика {
        СтильРолика.все.indices.contains(номерСтиля) ? СтильРолика.все[номерСтиля] : СтильРолика.все[0]
    }

    var включено: Int { фото.filter { $0.включено }.count }

    var идётЗапись: Bool {
        if case .запись = этап { return true }
        return false
    }

    var готовый: ГотовыйРолик? {
        if case .готово(let ролик) = этап { return ролик }
        return nil
    }

    // MARK: Загрузка

    /// openReelForListing сайта: my_items → фото, город и характеристики объявления; нет записи — одно фото из данных.
    func начать() async {
        guard !начато else { return }
        начато = true
        typealias A = МоиОбъявленияAPI
        qr = ПоделитьсяСайта.qr(данные.адрес.absoluteString, модуль: 8)
        var адреса: [URL] = []
        if let j = try? await A.получить("cabinet.php?action=my_items"),
           let записи = j["items"] as? [[String: Any]],
           let запись = записи.first(where: { A.строка($0["id"]) == данные.id }) {
            адреса = МодельСтудииРоликов.адресаФото(запись)
            город = A.строка(запись["city"]).trimmingCharacters(in: .whitespacesAndNewlines)
            пары = МодельСтудииРоликов.характеристики(запись)
        }
        if адреса.isEmpty, let одно = данные.фото { адреса = [одно] }
        var были = Set<String>()
        var список: [ФотоРолика] = []
        for адрес in адреса where !были.contains(адрес.absoluteString) {
            были.insert(адрес.absoluteString)
            список.append(ФотоРолика(id: адрес.absoluteString, адрес: адрес, включено: список.count < МодельСтудииРоликов.наибольшеФото))
        }
        фото = список
        загружается = false
        пересобрать()
        await withTaskGroup(of: Void.self) { группа in
            for элемент in список {
                let адрес = элемент.адрес
                let номер = элемент.id
                группа.addTask { [weak self] in
                    let (карточка, фон) = await ПодготовкаФотоРолика.подготовить(адрес)
                    await self?.принять(номер, карточка, фон)
                }
            }
        }
        if !фото.isEmpty && фото.allSatisfy({ $0.картинка == nil }) {
            показатьТост(т("photos_none"), секунд: 4)
        }
    }

    private func принять(_ номер: String, _ карточка: UIImage?, _ фон: UIImage?) {
        guard let i = фото.firstIndex(where: { $0.id == номер }) else { return }
        var обновлённое = фото[i]
        обновлённое.картинка = карточка
        обновлённое.фон = фон
        обновлённое.загружено = true
        фото[i] = обновлённое
    }

    /// images[] записи (строки или {url}) и img; относительные — от корня сайта, как у сайта.
    private static func адресаФото(_ запись: [String: Any]) -> [URL] {
        typealias A = МоиОбъявленияAPI
        var строки: [String] = []
        if let список = запись["images"] as? [Any] {
            for элемент in список {
                if let s = элемент as? String {
                    строки.append(s)
                } else if let d = элемент as? [String: Any] {
                    строки.append(A.строка(d["url"] ?? d["src"]))
                }
            }
        }
        if строки.isEmpty { строки.append(A.строка(запись["img"])) }
        return строки.compactMap { сырой in
            let s = сырой.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return nil }
            if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
            var путь = Substring(s)
            while путь.hasPrefix("/") { путь = путь.dropFirst() }
            return Config.url("/\(путь)")
        }
    }

    /// reelSpecPairs сайта (без полей недвижимости REALTY_FIELDS): specs массивом, объектом или строкой, и состояние.
    private static func характеристики(_ запись: [String: Any]) -> [ПараРолика] {
        typealias A = МоиОбъявленияAPI
        var итог: [ПараРолика] = []
        var были = Set<String>()
        func пусто(_ v: String) -> Bool {
            v.isEmpty || v == "0" || v == "—" || v == "-" || v == "false" || v.lowercased().hasPrefix("не указ")
        }
        func добавить(_ подпись: String, _ значение: String) {
            let l = подпись.trimmingCharacters(in: .whitespacesAndNewlines)
            let v = значение.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !пусто(v) else { return }
            let ключ = (l.isEmpty ? v : l).lowercased()
            guard !были.contains(ключ) else { return }
            были.insert(ключ)
            итог.append(ПараРолика(подпись: l, значение: v))
        }
        let specs = запись["specs"]
        if let список = specs as? [Any] {
            for элемент in список {
                if let d = элемент as? [String: Any] {
                    добавить(A.строка(d["label"]), A.строка(d["value"]))
                } else if let s = элемент as? String {
                    добавить("", s)
                }
            }
        } else if let словарь = specs as? [String: Any] {
            for ключ in словарь.keys.sorted() { добавить(ключ, A.строка(словарь[ключ])) }
        } else if let строка = specs as? String {
            for часть in строка.components(separatedBy: CharacterSet(charactersIn: "·•|")) { добавить("", часть) }
        }
        switch A.строка(запись["condition"]) {
        case "new": добавить("", ReelStudioText.т("cond_new"))
        case "used": добавить("", ReelStudioText.т("cond_used"))
        default: break
        }
        return Array(итог.prefix(6))
    }

    // MARK: Правки

    private func изменено() {
        сброситьГотовое()
        пересобрать()
    }

    /// reelReroll сайта: готовое видео больше не соответствует настройкам.
    private func сброситьГотовое() {
        if let ролик = готовый {
            try? FileManager.default.removeItem(at: ролик.файл)
        }
        if case .запись = этап { return }
        этап = .превью
    }

    private func содержимое() -> СодержимоеРолика {
        let выбранные = фото.filter { $0.включено && $0.картинка != nil }.prefix(МодельСтудииРоликов.наибольшеФото)
        var все: [ПараРолика] = []
        if !город.isEmpty { все.append(ПараРолика(подпись: "", значение: город, булавка: true)) }
        все.append(contentsOf: пары)
        let имя = название.trimmingCharacters(in: .whitespacesAndNewlines)
        return СодержимоеРолика(
            стиль: стиль,
            название: имя.isEmpty ? т("default_title") : имя,
            цена: цена.trimmingCharacters(in: .whitespacesAndNewlines),
            призыв: призыв.trimmingCharacters(in: .whitespacesAndNewlines),
            пары: все,
            фото: выбранные.compactMap { $0.картинка },
            фоны: выбранные.map { $0.фон },
            qr: qr,
            подзаголовок: т("v_tagline"),
            доверие: т("v_trust"),
            магазинМелко: т("v_store"),
            подсказкаQR: т("v_qr"),
            подсказкаПостера: т("v_poster_qr"))
    }

    private func пересобрать() {
        рисовальщик = РисовальщикРолика(содержимое())
    }

    /// «Стиль»: другой случайный.
    func другойСтиль() {
        guard !идётЗапись else { return }
        номерСтиля = СтильРолика.случайный(кроме: номерСтиля)
        ОткликСайта.выбор()
    }

    func выбратьСтиль(_ номер: Int) {
        guard !идётЗапись, СтильРолика.все.indices.contains(номер) else { return }
        номерСтиля = номер
        ОткликСайта.выбор()
    }

    /// Фото в ролик и из ролика: не больше 5 и не меньше одного.
    func переключить(_ id: String) {
        guard !идётЗапись, let i = фото.firstIndex(where: { $0.id == id }) else { return }
        if фото[i].включено {
            guard включено > 1 else {
                показатьТост(т("photos_min"))
                return
            }
        } else if включено >= МодельСтудииРоликов.наибольшеФото {
            ОткликСайта.предупреждение()
            показатьТост(т("photos_max"))
            return
        }
        фото[i].включено.toggle()
        ОткликСайта.выбор()
    }

    func сдвинуть(_ id: String, на шаг: Int) {
        guard !идётЗапись, let i = фото.firstIndex(where: { $0.id == id }) else { return }
        let j = i + шаг
        guard фото.indices.contains(j) else { return }
        withAnimation(ДвижениеСайта.смена) { фото.swapAt(i, j) }
        ОткликСайта.выбор()
    }

    // MARK: Запись

    /// reelMake сайта.
    func сделатьВидео() {
        guard !идётЗапись, let рисовальщик else { return }
        сброситьГотовое()
        этап = .запись(0, .кадры)
        let соЗвуком = звук
        let громкостьЗвука = громкость
        задача = Task { [weak self] in
            do {
                let ролик = try await ЭкспортРолика.сделать(рисовальщик, звук: соЗвуком, громкость: громкостьЗвука,
                                                            ход: { [weak self] доля, шаг in
                                                                self?.ход(доля, шаг)
                                                            })
                guard let self else {
                    try? FileManager.default.removeItem(at: ролик.файл)
                    return
                }
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: ролик.файл)
                    return
                }
                self.этап = .готово(ролик)
                ОткликСайта.успех()
                let звукСлова = соЗвуком ? (ролик.соЗвуком ? self.т("ready_snd") : self.т("ready_nosnd")) : ""
                UIAccessibility.post(notification: .announcement, argument: "\(self.т("ready")) \(звукСлова)")
            } catch is CancellationError {
                self?.этап = .превью
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.этап = .сбой
                ОткликСайта.предупреждение()
            }
        }
    }

    private func ход(_ доля: Double, _ шаг: ЭтапЗаписиРолика) {
        guard идётЗапись else { return }
        этап = .запись(доля, шаг)
    }

    func отменить() {
        guard идётЗапись else { return }
        задача?.cancel()
        задача = nil
        этап = .превью
        показатьТост(т("cancelled"))
    }

    /// Закрытие студии: запись останавливается, файл готового ролика удаляется.
    func закрыто() {
        задача?.cancel()
        задача = nil
        задачаТоста?.cancel()
    }

    // MARK: После записи

    /// Подпись reelShare сайта: название — цена, гарант, ссылка, App Store, теги.
    var подпись: String {
        let имя = название.trimmingCharacters(in: .whitespacesAndNewlines)
        let частьЦены = данные.цена > 0 ? " — \(DesignText.число(Int(данные.цена.rounded()))) ₸" : ""
        var теги = "#Kliko #KlikoKZ"
        let городТегом = город.components(separatedBy: .whitespaces).joined()
        if !городТегом.isEmpty { теги = "\(теги) #\(городТегом)" }
        let строки: [String] = [
            "\(имя.isEmpty ? данные.название : имя)\(частьЦены)",
            "",
            т("c_safe"),
            "👉 \(данные.адрес.absoluteString)",
            "\(т("c_app")) \(МодельСтудииРоликов.ссылкаAppStore)",
            теги
        ]
        return строки.joined(separator: "\n")
    }

    private func скопироватьПодпись() {
        UIPasteboard.general.string = подпись
    }

    /// «Поделиться»: системный лист с файлом и подписью; подпись ещё и в буфер (Reels и TikTok текст не берут).
    func поделиться() {
        guard let ролик = готовый else { return }
        скопироватьПодпись()
        показатьТост(т("caption_copied"), секунд: 3)
        ПоделитьсяСайта.системныйЛист([ролик.файл, подпись])
    }

    /// TikTok: публичной схемы для видео нет — системный лист (TikTok в нём есть), подпись в буфере.
    func tikTok() {
        guard let ролик = готовый else { return }
        скопироватьПодпись()
        показатьТост(т("caption_copied"), секунд: 3)
        ПоделитьсяСайта.системныйЛист([ролик.файл])
    }

    /// «В галерею»: только добавление (NSPhotoLibraryAddUsageDescription).
    func вГалерею() {
        guard let ролик = готовый else { return }
        Task { [weak self] in
            let ид = await МодельСтудииРоликов.сохранитьВФото(ролик.файл)
            guard let self else { return }
            if ид != nil {
                ОткликСайта.успех()
                self.показатьТост(self.т("saved"))
            } else {
                ОткликСайта.предупреждение()
                self.показатьТост(self.т("save_fail"), секунд: 3)
            }
        }
    }

    /// Instagram Reels: ролик в Фото и instagram://library?LocalIdentifier= — Instagram открывает его в редакторе;
    /// нет Instagram или доступа к Фото — системный лист.
    func instagramReels() {
        guard let ролик = готовый else { return }
        скопироватьПодпись()
        Task { [weak self] in
            let ид = await МодельСтудииРоликов.сохранитьВФото(ролик.файл)
            guard let self else { return }
            if let ид, !ид.isEmpty,
               let адрес = URL(string: "instagram://library?LocalIdentifier=\(ПоделитьсяСайта.код(ид))"),
               UIApplication.shared.canOpenURL(адрес) {
                self.показатьТост(self.т("caption_copied"), секунд: 3)
                UIApplication.shared.open(адрес, options: [:], completionHandler: nil)
            } else {
                self.показатьТост(self.т("caption_copied"), секунд: 3)
                ПоделитьсяСайта.системныйЛист([ролик.файл])
            }
        }
    }

    /// Instagram Stories: видео фоном через буфер (instagram-stories://share, нужен FacebookAppID); иначе системный лист.
    func instagramStories() {
        guard let ролик = готовый else { return }
        скопироватьПодпись()
        if let приложение = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String, !приложение.isEmpty,
           let схема = URL(string: "instagram-stories://share?source_application=\(ПоделитьсяСайта.код(приложение))"),
           UIApplication.shared.canOpenURL(схема),
           let данныеВидео = try? Data(contentsOf: ролик.файл) {
            let предмет: [String: Any] = [
                "com.instagram.sharedSticker.backgroundVideo": данныеВидео,
                "com.instagram.sharedSticker.contentURL": данные.адрес.absoluteString
            ]
            UIPasteboard.general.setItems([предмет], options: [.expirationDate: Date().addingTimeInterval(300)])
            UIApplication.shared.open(схема, options: [:], completionHandler: nil)
            return
        }
        показатьТост(т("caption_copied"), секунд: 3)
        ПоделитьсяСайта.системныйЛист([ролик.файл])
    }

    /// Ролик в Фото; идентификатор новой записи или nil.
    nonisolated private static func сохранитьВФото(_ файл: URL) async -> String? {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return nil }
        let ящик = ЯщикИдРолика()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let запрос = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: файл)
                ящик.ид = запрос?.placeholderForCreatedAsset?.localIdentifier
            }
            return ящик.ид ?? ""
        } catch {
            return nil
        }
    }

    /// reelShareImage сайта: «Картинка» — кадр с QR, сразу в системный лист с подписью.
    func картинка() {
        guard !картинкаГотовится else { return }
        картинкаГотовится = true
        показатьТост(т("image_making"), секунд: 1.2)
        let постер = РисовальщикРолика(содержимое(), постер: true)
        let текст = подпись
        Task { [weak self] in
            let готово = await Task.detached(priority: .userInitiated) { () -> Data? in
                постер.кадр(постер.времяПостера, масштаб: 1)?.jpegData(compressionQuality: 0.92)
            }.value
            guard let self else { return }
            self.картинкаГотовится = false
            guard let готово, let картинка = UIImage(data: готово) else {
                ОткликСайта.предупреждение()
                self.показатьТост(self.т("image_fail"))
                return
            }
            UIPasteboard.general.string = текст
            ПоделитьсяСайта.системныйЛист([картинка, текст])
        }
    }

    // MARK: Автопостинг (socialPost сайта)

    /// cabinet.php?action=social_status → {instagram: {enabled, connected, username}, tiktok: {…}}.
    func загрузитьСоцсети() async {
        guard соцсети == nil else { return }
        typealias A = МоиОбъявленияAPI
        var итог: [String: СоцсетьРолика] = [:]
        if let j = try? await A.получить("cabinet.php?action=social_status"), A.да(j["ok"]) {
            for ключ in ["instagram", "tiktok"] {
                guard let запись = j[ключ] as? [String: Any] else { continue }
                итог[ключ] = СоцсетьРолика(включено: A.да(запись["enabled"]), подключено: A.да(запись["connected"]),
                                           имя: A.строка(запись["username"]))
            }
        }
        withAnimation(ДвижениеСайта.смена) { соцсети = итог }
    }

    func нажатаСоцсеть(_ ключ: String, _ имя: String) {
        guard let с = соцсети?[ключ], с.включено, публикуется == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            guard await self.естьАвтопостинг() else {
                self.нуженПРО()
                return
            }
            if с.подключено {
                await self.опубликовать(ключ, имя)
            } else {
                self.подключить(ключ, имя)
            }
        }
    }

    /// proGate("autopost"): уровень PRO со страницы кабинета; не прочиталась — решит сервер.
    private func естьАвтопостинг() async -> Bool {
        let модель = БизнесМодель.shared
        if модель.страница == nil { await модель.загрузитьСтраницу() }
        guard let страница = модель.страница else { return true }
        return страница.естьФункция("autopost")
    }

    /// showProOffer: подсказка; при Config.цифровыеПокупки и загруженном товаре PRO (ДоступПокупкиApple) — затем окно
    /// покупки PRO через App Store. Иначе — только подсказка, без перехода на оплату и без пустого окна.
    private func нуженПРО() {
        показатьТост(т("pro_need"), секунд: 2)
        guard ПокупкиApple.shared.можноКупить(.про) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.закрыть?()
            ЛистУслугиApple.показать(.про)
        }
    }

    /// Нативно: одноразовая ссылка сервера и лист входа соцсети (ПодключениеСоцсети); по возврату — social_status
    /// заново. Сервер ещё не умеет — прежняя страница сайта.
    private func подключить(_ ключ: String, _ имя: String) {
        показатьТост(String(format: т("connecting"), имя), секунд: 2)
        Task { [weak self] in
            let итог = await ПодключениеСоцсети.подключить(ключ, имя: имя)
            guard let self else { return }
            switch итог {
            case .наСайт:
                self.подключитьНаСайте(ключ)
                return
            case .подключено:
                ОткликСайта.успех()
                self.показатьТост(ПодключениеСоцсети.текстУспеха(имя), секунд: 2.5)
            case .ошибка(let слова):
                ОткликСайта.предупреждение()
                self.показатьТост(слова, секунд: 4)
            case .отменено:
                break
            }
            await self.перечитатьСоцсети()
        }
    }

    /// social_status заново (загрузитьСоцсети читает только первый раз).
    private func перечитатьСоцсети() async {
        соцсети = nil
        await загрузитьСоцсети()
    }

    /// Прежний путь: страница сайта поверх (сессия kliko_cab живёт только в WKWebsiteDataStore.default(), у листа
    /// входа — куки Safari).
    private func подключитьНаСайте(_ ключ: String) {
        guard let адрес = Config.страницаСайта("social_connect.php?platform=\(ключ)&do=start") else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            self?.закрыть?()
            ПоверхВсего.открытьАдрес(адрес)
        }
    }

    /// POST social_post {id, platform}: сервер сам публикует объявление в подключённый аккаунт.
    private func опубликовать(_ ключ: String, _ имя: String) async {
        typealias A = МоиОбъявленияAPI
        публикуется = ключ
        do {
            let j = try await A.отправить("cabinet.php?action=social_post", тело: ["id": данные.id, "platform": ключ])
            публикуется = nil
            if A.да(j["ok"]) {
                опубликованоВ.insert(ключ)
                ОткликСайта.успех()
                показатьТост(String(format: т("posted_to"), имя), секунд: 3.5)
            } else if A.да(j["need_connect"]) {
                подключить(ключ, имя)
            } else {
                let слова = A.строка(j["msg"])
                ОткликСайта.предупреждение()
                показатьТост(слова.isEmpty ? т("post_fail") : слова, секунд: 4)
            }
        } catch {
            публикуется = nil
            показатьТост(т("no_conn"))
        }
    }

    // MARK: Тост

    func показатьТост(_ текст: String, секунд: Double = 1.8) {
        задачаТоста?.cancel()
        withAnimation(ДвижениеСайта.появление) { тост = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        задачаТоста = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(секунд * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(ДвижениеСайта.уход) { self?.тост = nil }
        }
    }
}
