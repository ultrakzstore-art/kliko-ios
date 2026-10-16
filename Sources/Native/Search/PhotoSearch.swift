import SwiftUI
import PhotosUI
import UIKit
import ImageIO

/**
 ПОИСК ПО ФОТО — СВОЙ ЭКРАН КАМЕРЫ (владелец 29.09.2026: «И поиск по фото тоже дизайн камеры»).

 Запрос к сайту прежний — тот же, что mkPhotoSearch сайта (js/marketplace.min.js), см. ПоискПоФотоAPI ниже:
 • снимок — как _mkPhotoPicked: большая сторона не больше 1024, JPEG 0,82, dataURL;
 • POST /api/photo_search.php, multipart, поле imgb64 (и csrf страницы), с куками веб-сессии (SiteSession); с правки
   сайта 14.10.2026 — и city, свой город так, как он уходит в ленту;
 • ответ ok + query (+ category) — что распознано; с 14.10.2026 ещё title, keywords, confidence, qa и первые карточки
   items (+ items_total, items_cat, items_city) — РаспознаноПоФото, PhotoSearchItems.swift; need/error «auth» — нужен
   вход; отказ по частоте (error или code «rate_limit», HTTP 429, или limit и window в ответе; сайт пускает 40 поисков
   в час на человека, было 20) — «Не больше N поисков в час» с числом из limit, без него — «Много поисков подряд».
   Области снимка API не принимает, поэтому снимок затвора режет сам телефон — по рамке на экране с запасом
   (ОбрезкаСнимкаПоиска, PhotoSearchCamera.swift); галерея — целиком.

 Что видит человек (PhotoSearchCamera.swift, PhotoSearchResults.swift):
 • гость (сеанс сайта «не вошёл») — до камеры нативный лист «Войдите, чтобы искать по фото»: «Войти» (ВходПоверх),
   «Регистрация через eGov», «Позже»; вошёл — сразу камера;
 • тёмный экран живой камеры (AVFoundation): ✕, фонарик, большой затвор, галерея с миниатюрой последнего фото,
   подсказка «Поместите вещь в рамку…», рамка с уголками (без движения при «Уменьшении движения»); камеры нет или доступ
   запрещён — заглушка с «Выбрать из галереи» (и «Открыть Настройки»), без камеры галерея открывается сама;
 • снимок — «Ищем похожие…» (Kliko AI) поверх фото; затем сетка карточек ленты (ListingCard) «Похожие на ваше фото»:
   сайт прислал items — они, со следующими страницами по написаниям («Показать ещё», ЛистаниеПохожихФото); нет —
   по распознанному запросу и разделу — каскадом от точного к широкому (КаскадПохожихФото, PhotoSearchMatch.swift:
   своё место → вся страна → без раздела → запрос короче → только раздел), под шапкой — чем выдача отличается от
   точной; капсула «Kliko AI видит: … ✎» — исправить запрос и искать заново; «Снять ещё» и «Все в ленте» (запрос и
   раздел, что дали выдачу, встают в ленту, плашка «Ищем: …»; только если выдача найдена в своём месте — лента ищет
   в выбранном городе);
 • лимит сайта (rate_limit) — «Не больше N поисков в час» (без limit — «Много поисков подряд»): «Снять ещё» и галерея,
   без «Повторить»;
 • сайт не распознал фото — Vision на телефоне угадывает раздел (РазделСнимкаНаТелефоне): угадал — похожие из
   раздела с подписью «Kliko AI не узнал вещь точно», нет — ошибка;
 • ошибка распознавания или сети — «Повторить», «Снять ещё», «Выбрать из галереи»; сайт просит вход — лист входа;
 • внизу камеры — «Галерея», затвор «Найти» и «Авто» (запоминается): «Авто» — живой поиск, стабильный кадр сам
   уходит в этот же запрос, похожие — полосой снизу (PhotoSearchLive.swift).
 */
enum ПоискПоФотоAPI {
    enum Итог: Equatable {
        /// Распознано: query и category, с правки сайта 14.10.2026 — и title, написания, первые карточки.
        case найдено(РаспознаноПоФото)
        case нуженВход
        case отказ(String)
        /// «Свой ИИ»: own_ai:"<код>", готовый текст в error — окно с «Настройки своего ИИ».
        case свойИИ(ОтказСвоегоИИ)
        /// Отказ по частоте: 40 поисков по фото в час на человека (было 20; снимки и живой поиск вместе, число меняется
        /// в админке сайта) — подождать, а не переснимать. Число — limit ответа; nil — не пришёл (старый сервер).
        case часто(Int?)
        case сеть
    }

    /// city для photo_search — свой город так, как он уходит в api/listings.php (ГдеИскать.параметры: city=<название>).
    /// Вся страна или регион без города — пусто, поле не шлём.
    static func городПоиска() -> String {
        ГдеИскать.сохранённое().параметры.first(where: { $0.name == "city" })?.value ?? ""
    }

    /// Как _mkPhotoPicked сайта: большая сторона не больше 1024, JPEG с качеством 0,82 → «data:image/jpeg;base64,…».
    /// Поворот снимка камеры рисование учитывает само. Пустой или битый — nil (у сайта — dataURL короче 120 знаков).
    static func сжать(_ снимок: UIImage) -> String? {
        let w = снимок.size.width * снимок.scale
        let h = снимок.size.height * снимок.scale
        guard w > 0, h > 0 else { return nil }
        let k = min(1, 1024 / max(w, h))
        let размер = CGSize(width: max(1, (w * k).rounded()), height: max(1, (h * k).rounded()))
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let рисовальщик = UIGraphicsImageRenderer(size: размер, format: формат)
        let готовый = рисовальщик.image { _ in
            снимок.draw(in: CGRect(origin: .zero, size: размер))
        }
        guard let данные = готовый.jpegData(compressionQuality: 0.82) else { return nil }
        let адрес = "data:image/jpeg;base64," + данные.base64EncodedString()
        return адрес.count > 120 ? адрес : nil
    }

    /// Фото из галереи — уменьшенным уже при чтении (ImageIO): длинная сторона не больше `сторона` px, поворот по EXIF
    /// применён, раскодировано заранее. Формат, который ImageIO не прочёл, — UIImage(data:), как раньше. Вне главной
    /// нити.
    static func открыть(_ данные: Data, сторона: Int) -> UIImage? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        if let источник = CGImageSourceCreateWithData(данные as CFData, чтение) {
            let параметры: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: сторона
            ]
            if let кадр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры as CFDictionary) {
                return UIImage(cgImage: кадр)
            }
        }
        return UIImage(data: данные)
    }

    /// _mkPhotoSend: POST /api/photo_search.php (FormData с imgb64 и city), куки и токен веб-сессии.
    static func отправить(_ адресФото: String) async -> Итог {
        guard let адрес = Config.url("/api/photo_search.php") else { return .сеть }
        let город = городПоиска()
        let граница = "----KlikoPhotoSearch" + UUID().uuidString
        var тело = Data()
        func поле(_ имя: String, _ значение: String) {
            var часть = "--" + граница + "\r\n"
            часть += "Content-Disposition: form-data; name=\"" + имя + "\"\r\n\r\n"
            часть += значение + "\r\n"
            тело.append(Data(часть.utf8))
        }
        поле("imgb64", адресФото)
        /* city (правка сайта 14.10.2026, необязательное): карточки сайт ищет сначала в нём. Старый сервер поле не читает. */
        if !город.isEmpty { поле("city", город) }
        if let csrf = await SiteSession.csrf() { поле("csrf", csrf) }
        тело.append(Data(("--" + граница + "--\r\n").utf8))

        var запрос = URLRequest(url: адрес)
        запрос.httpMethod = "POST"
        запрос.timeoutInterval = 60
        запрос.httpShouldHandleCookies = false
        запрос.setValue("multipart/form-data; boundary=" + граница, forHTTPHeaderField: "Content-Type")
        запрос.setValue("application/json", forHTTPHeaderField: "Accept")
        /* Origin не подставляем (владелец: без поддельных Origin/Referer): photo_search.php источник не проверяет —
           ему нужны вошедшая сессия (куки) и токен страницы в теле. */
        let куки = await SiteSession.куки()
        for (имя, значение) in куки { запрос.setValue(значение, forHTTPHeaderField: имя) }
        запрос.httpBody = тело

        let данные: Data
        let ответ: URLResponse
        do {
            (данные, ответ) = try await URLSession.shared.data(for: запрос)
        } catch {
            return .сеть
        }
        let код = (ответ as? HTTPURLResponse)?.statusCode ?? 200
        /* Не JSON — «Не удалось распознать фото» (t._bad у сайта); 401/403 без тела — вход. */
        guard let поля = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            if код == 429 { return .часто(nil) }
            return (код == 401 || код == 403) ? .нуженВход : .отказ(ПоискСайтаText.т("ps_fail"))
        }
        let запросФото = строка(поля["query"])
        if да(поля["ok"]) && !запросФото.isEmpty {
            return .найдено(распознано(поля, данные, запрос: запросФото, город: город))
        }
        if строка(поля["need"]) == "auth" || строка(поля["error"]) == "auth" { return .нуженВход }
        if let отказ = ОтказСвоегоИИ.из(поля) { return .свойИИ(отказ) }
        let ошибка = строка(поля["error"])
        /* Правка сайта 14.10.2026: отказ по частоте — прежний текст в error плюс limit (поисков в час) и window (секунд).
           Квота (need=<причина>) — не частота, её не трогаем. */
        let предел = целое(поля["limit"])
        let частоПоПолям = строка(поля["need"]).isEmpty && предел != nil && поля["window"] != nil
        if ошибка == "rate_limit" || строка(поля["code"]) == "rate_limit" || код == 429 || частоПоПолям {
            return .часто(предел.flatMap { $0 > 0 ? $0 : nil })
        }
        /* Прочий машинный код — не человеку: как ulxErr сайта, показываем общий текст. */
        if ошибка.isEmpty || ошибка.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil {
            return .отказ(ПоискСайтаText.т("ps_fail"))
        }
        return .отказ(ошибка)
    }

    /// Успех: query и category, как раньше, и поля правки сайта 14.10.2026. items — тем же разбором, что страница ленты
    /// (ListingsAPI.разобрать: корень с items, карточка не разобралась — пропущена), повторы id убраны. Старый сервер —
    /// новые поля пустые.
    private static func распознано(_ поля: [String: Any], _ данные: Data, запрос: String,
                                   город: String) -> РаспознаноПоФото {
        var товары: [Listing] = []
        if let список = поля["items"] as? [Any], !список.isEmpty, let страница = try? ListingsAPI.разобрать(данные) {
            var были = Set<String>()
            товары = страница.items.filter { были.insert($0.id).inserted }
        }
        let написания = ((поля["keywords"] as? [Any]) ?? []).map { строка($0) }.filter { !$0.isEmpty }
        let qa: String
        if let части = поля["qa"] as? [Any] {
            qa = части.map { строка($0) }.filter { !$0.isEmpty }.joined(separator: "|")
        } else {
            qa = строка(поля["qa"])
        }
        return РаспознаноПоФото(запрос: запрос, раздел: строка(поля["category"]),
                                описание: String(строка(поля["title"]).prefix(90)),
                                написания: Array(написания.prefix(8)), уверенность: доля(поля["confidence"]),
                                qa: qa, товары: товары, всего: целое(поля["items_total"]).map { max($0, товары.count) },
                                разделКарточек: строка(поля["items_cat"]), городКарточек: строка(поля["items_city"]),
                                присланныйГород: город, своимИИ: ОтветСвоегоИИ.своим(поля))
    }

    private static func строка(_ значение: Any?) -> String {
        if let s = значение as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = значение as? NSNumber { return n.stringValue }
        return ""
    }

    /// Целое из числа или строки (PHP шлёт и так и так); иначе nil.
    private static func целое(_ значение: Any?) -> Int? {
        if let n = значение as? NSNumber {
            let d = n.doubleValue
            return d.isFinite && abs(d) < 1e12 ? Int(d) : nil
        }
        if let s = значение as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    /// confidence: число 0…1 (или строкой); иначе nil.
    private static func доля(_ значение: Any?) -> Double? {
        var пришло: Double? = nil
        if let n = значение as? NSNumber {
            пришло = n.doubleValue
        } else if let s = значение as? String {
            пришло = Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let число = пришло, число.isFinite else { return nil }
        return min(1, max(0, число))
    }

    private static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s == "true" }
        return false
    }
}

/// Итог распознавания для ленты: запрос в поле и раздел (пусто — без раздела).
struct ИтогПоискаПоФото: Equatable {
    let id = UUID()
    let запрос: String
    let раздел: String
    /// qa photo_search — выдача по написаниям (сайт прислал items): лента ищет «ИЛИ» по ним, как экран похожих; пусто —
    /// выдача каскадом, лента ищет по запросу, как раньше.
    var qa = ""
}

@MainActor
final class ПоискПоФотоСайта: ObservableObject {
    static let shared = ПоискПоФотоСайта()

    enum Шаг: Equatable {
        case камера
        case идёт
        case результаты
        case ошибка(String)
    }

    /// Гостю — лист «Войдите, чтобы искать по фото» до камеры.
    @Published var ворота = false
    /// Экран поиска по фото поверх всего: камера, «Ищем похожие…», похожие, ошибка.
    @Published var окно = false
    /// Системная галерея (PhotosPicker) — из экрана камеры.
    @Published var галерея = false
    @Published var элемент: PhotosPickerItem? = nil
    @Published private(set) var шаг: Шаг = .камера
    @Published private(set) var превью: UIImage? = nil
    /// Последний снимок этой камеры — миниатюра у кнопки галереи, если доступа к фото нет.
    @Published private(set) var последний: UIImage? = nil
    /// Что распознал Kliko AI (или что человек написал в «Исправить запрос») и раздел от ИИ — с них начинается каскад.
    @Published private(set) var запрос = ""
    @Published private(set) var раздел = ""
    @Published private(set) var товары: [Listing] = []
    @Published private(set) var всего: Int? = nil
    /// Чем выдача на экране отличается от точной (КаскадПохожихФото): запрос, раздел и место, что её дали, и уровень.
    @Published private(set) var выдача: ИтогПохожихФото? = nil
    /// Сайт фото не распознал, раздел угадал Vision на телефоне — подпись «Kliko AI не узнал вещь точно».
    @Published private(set) var догадка = false
    /// «Все в ленте» — лента подставляет запрос и раздел.
    @Published private(set) var итог: ИтогПоискаПоФото? = nil
    /// Плашка «Ищем: …» (toast сайта).
    @Published private(set) var плашка: String? = nil
    /// title от Kliko AI («Apple iPhone 13 Pro, синий») — капсула «Kliko AI видит: …»; пусто — в капсуле запрос.
    @Published private(set) var описание = ""
    /// own_ai_run в ответе photo_search: распознал свой ИИ человека — капсула «… · через ваш ИИ» вместо «Kliko AI видит».
    @Published private(set) var своимИИ = false
    /// Выдача по написаниям (сайт прислал items) и её следующие страницы; nil — выдача каскадом, она не листается.
    @Published private(set) var листание: ЛистаниеПохожихФото? = nil
    /// Следующая страница выдачи по написаниям идёт; не вышло — «Показать ещё» с «Не загрузилось».
    @Published private(set) var грузимЕщё = false
    @Published private(set) var ошибкаЕщё = false
    /// Текст отказа по частоте на экране ошибки — без «Повторить» и совета про ракурс (ЭкранОшибкиПоискаФото).
    @Published private(set) var текстЧасто = ""

    private var адресФото: String? = nil
    private var задача: Task<Void, Never>? = nil
    private var задачаЕщё: Task<Void, Never>? = nil
    private var поколение = 0

    private init() {}

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    /// Камера в поле поиска: гость — лист входа, иначе сразу камера.
    func начать() {
        Task { @MainActor in
            let состояние = await SiteSession.состояние()
            if состояние.вошёл == false {
                ворота = true
            } else {
                открытьКамеру()
            }
        }
    }

    func открытьКамеру() {
        сбросить()
        шаг = .камера
        окно = true
    }

    /// «Снять ещё» — обратно к камере в том же окне.
    func снятьЕщё() {
        сбросить()
        шаг = .камера
    }

    /// «Выбрать из галереи» с экрана ошибки или заглушки.
    func открытьГалерею() {
        галерея = true
    }

    private func сбросить() {
        поколение += 1
        задача?.cancel()
        задача = nil
        превью = nil
        адресФото = nil
        запрос = ""
        раздел = ""
        описание = ""
        своимИИ = false
        товары = []
        всего = nil
        выдача = nil
        догадка = false
        забытьЛистание()
    }

    /// Выдача по написаниям больше не на экране: её следующая страница не нужна.
    private func забытьЛистание() {
        задачаЕщё?.cancel()
        задачаЕщё = nil
        листание = nil
        грузимЕщё = false
        ошибкаЕщё = false
    }

    /// Снимок с камеры.
    func снято(_ снимок: UIImage) {
        последний = снимок
        обработать(снимок)
    }

    /// Выбрали в галерее.
    func принять(_ выбранный: PhotosPickerItem?) {
        guard let выбранный else { return }
        элемент = nil
        поколение += 1
        let номер = поколение
        Task { @MainActor in
            let данные = try? await выбранный.loadTransferable(type: Data.self)
            guard номер == поколение else { return }
            /* Скорость: снимок галереи (бывает 48 Мп) — сразу уменьшенным до 2048 px и раскодированным, вне главной нити;
               сайт всё равно получает не больше 1024 (ПоискПоФотоAPI.сжать). */
            var снимок: UIImage? = nil
            if let данные {
                снимок = await Task.detached(priority: .userInitiated) { ПоискПоФотоAPI.открыть(данные, сторона: 2048) }
                    .value
            }
            guard номер == поколение else { return }
            guard let снимок else {
                шаг = .ошибка(т("ps_bad_img"))
                return
            }
            обработать(снимок)
        }
    }

    private func обработать(_ снимок: UIImage) {
        сбросить()
        превью = снимок
        шаг = .идёт
        let номер = поколение
        /* Скорость (владелец 16.10.2026): сжатие в JPEG и base64 — не на главной нити: «Ищем похожие…» встаёт сразу,
           а не после замирания экрана. Пока жали, начали заново («Снять ещё», другое фото) — этот снимок не нужен. */
        Task { @MainActor in
            let адрес = await Task.detached(priority: .userInitiated) { ПоискПоФотоAPI.сжать(снимок) }.value
            guard номер == поколение else { return }
            guard let адрес else {
                шаг = .ошибка(т("ps_fail"))
                return
            }
            адресФото = адрес
            распознать(адрес)
        }
    }

    /// Фото — на сайт (тот же запрос, что mkPhotoSearch), распознанное — в выдачу похожих.
    private func распознать(_ адрес: String) {
        let номер = поколение
        шаг = .идёт
        задача?.cancel()
        задача = Task { @MainActor in
            let ответ = await ПоискПоФотоAPI.отправить(адрес)
            guard номер == поколение, !Task.isCancelled else { return }
            switch ответ {
            case .найдено(let распознано):
                запрос = распознано.запрос
                раздел = распознано.раздел
                описание = распознано.описание
                своимИИ = распознано.своимИИ
                догадка = false
                /* Сайт сам нашёл карточки (items, правка 14.10.2026) — первая страница они, без каскада; items нет
                   (старый сервер или пусто) — прежний каскад по запросу. */
                if let готовое = ЛистаниеПохожихФото.первая(распознано, своё: ГдеИскать.сохранённое()) {
                    листание = готовое.листание
                    показать(готовое.итог)
                } else {
                    await найтиПохожие(номер)
                }
            case .нуженВход:
                закрыть()
                try? await Task.sleep(nanoseconds: 450_000_000)
                ворота = true
            case .отказ(let текст):
                await догадатьсяПоСнимку(текст, номер)
            case .свойИИ(let отказ):
                шаг = .ошибка(отказ.текст)
                ОкноСвоегоИИ.показатьОтказ(отказ)
            case .часто(let предел):
                /* Лимит сайта — переснимать бесполезно, и запас на телефоне тут не к месту: человеку — подождать. Число
                   из limit — «Не больше N поисков в час»; нет его — прежнее «Много поисков подряд». */
                текстЧасто = ПохожиеПоФотоText.часто(предел)
                шаг = .ошибка(текстЧасто)
            case .сеть:
                шаг = .ошибка(т("err_no_conn"))
            }
        }
    }

    /// Сайт не распознал: Vision на телефоне по тому же снимку угадывает раздел (как подсказка живого поиска) — угадал,
    /// похожие из раздела с подписью «Kliko AI не узнал вещь точно»; нет или раздел пуст — прежняя ошибка сайта.
    private func догадатьсяПоСнимку(_ текстОшибки: String, _ номер: Int) async {
        guard let снимок = превью else {
            шаг = .ошибка(текстОшибки)
            return
        }
        let ключ = await РазделСнимкаНаТелефоне.найти(снимок)
        guard номер == поколение, !Task.isCancelled else { return }
        guard let ключ else {
            шаг = .ошибка(текстОшибки)
            return
        }
        запрос = ""
        раздел = ключ
        своимИИ = false
        догадка = true
        await найтиПохожие(номер, еслиПусто: текстОшибки)
    }

    /// Объявления по распознанному запросу — как лента (api/listings.php), каскадом от точного к широкому
    /// (КаскадПохожихФото: своё место, вся страна, без раздела, запрос короче, только раздел). `еслиПусто` — догадка
    /// Vision ничего не дала: вместо пустой выдачи прежняя ошибка сайта.
    private func найтиПохожие(_ номер: Int, еслиПусто: String? = nil) async {
        do {
            /* 24 на страницу — как лента по умолчанию (ListingsAPI.Запрос.per), как и прежде. */
            let найденное = try await КаскадПохожихФото.найти(запрос: запрос, раздел: раздел, лёгкий: false, на: 24)
            guard номер == поколение, !Task.isCancelled else { return }
            if найденное.товары.isEmpty, let еслиПусто {
                шаг = .ошибка(еслиПусто)
                return
            }
            показать(найденное)
        } catch {
            guard номер == поколение, !Task.isCancelled else { return }
            шаг = .ошибка(т("err_no_conn"))
        }
    }

    /// Выдача на экран и весть VoiceOver: сколько нашлось и чем выдача отличается от точной.
    private func показать(_ найденное: ИтогПохожихФото) {
        выдача = найденное
        товары = найденное.товары
        всего = найденное.всего
        шаг = .результаты
        var объявление = товары.isEmpty ? т("ps_empty") : String(format: т("ps_count"), всего ?? товары.count)
        if let подпись = подписьУровня { объявление += ". " + подпись }
        UIAccessibility.post(notification: .announcement, argument: объявление)
    }

    /// Есть следующая страница похожих (выдача по написаниям) — подгрузка и «Показать ещё».
    var естьЕщё: Bool {
        guard шаг == .результаты, let листание else { return false }
        return !листание.конец
    }

    /// Следующая страница выдачи по написаниям: GET api/listings.php?qa=…&cat=…&city=…&page=N&per=24
    /// (ЛистаниеПохожихФото.следующая). `сама` — долистали до конца сетки: после неудачи сама не повторяет, повтор —
    /// «Показать ещё».
    func дальше(сама: Bool = false) {
        guard естьЕщё, !грузимЕщё, let листание else { return }
        if сама && ошибкаЕщё { return }
        let номер = поколение
        let запросСтраницы = листание.следующая
        грузимЕщё = true
        ошибкаЕщё = false
        задачаЕщё = Task { @MainActor in
            var пришло: (страница: ListingsPage, сырое: Data)? = nil
            var написания: [String]? = nil
            if let ответ = try? await ListingsAPI.загрузить(запросСтраницы) {
                пришло = ответ
                написания = await ЛистаниеПохожихФото.написанияВФоне(ответ.сырое)
            }
            guard номер == поколение, !Task.isCancelled, var текущее = self.листание else { return }
            грузимЕщё = false
            guard let страница = пришло?.страница else {
                ошибкаЕщё = true
                return
            }
            /* Нет поля qa — сервер ленты старый: искал не по написаниям, а без q это просто лента раздела. Такую
               страницу не показываем и дальше не листаем. */
            guard let принятые = написания, !принятые.isEmpty else {
                текущее.закончить()
                self.листание = текущее
                return
            }
            var были = Set(товары.map(\.id))
            let новые = страница.items.filter { были.insert($0.id).inserted }
            текущее.пришла(было: страница.items.count, новых: новые.count, естьЕщё: страница.hasMore,
                           всего: страница.total, наЭкране: товары.count + новые.count)
            self.листание = текущее
            if !новые.isEmpty { товары += новые }
        }
    }

    /// Листание объявлений (ListingFlip) у последнего: следующая страница и весь список заново; не прибавилось — nil.
    func дальшеИДождаться() async -> [Listing]? {
        let было = товары.count
        if !грузимЕщё { дальше() }
        if let идёт = задачаЕщё { await идёт.value }
        return товары.count > было ? товары : nil
    }

    /// Подпись под шапкой похожих: чем выдача отличается от точной; точная или пустая — nil.
    var подписьУровня: String? {
        guard let выдача, !выдача.товары.isEmpty else { return nil }
        if let листание { return подписьКарточек(листание) }
        if догадка {
            if let имя = СловарьЖивогоПоиска.имя(выдача.раздел) { return String(format: т("ps_lvl_guess"), имя) }
            return т("ps_lvl_guess_any")
        }
        switch выдача.уровень {
        case .точно, .пусто:
            return nil
        case .поСтране, .безРаздела:
            /* Без раздела, но в своём месте «вся страна» — для человека та же выдача: подписи нет. */
            return выдача.шире ? т("ps_lvl_country") : nil
        case .короче:
            return String(format: т("ps_lvl_short"), выдача.запрос)
        case .раздел:
            if let имя = СловарьЖивогоПоиска.имя(выдача.раздел) { return String(format: т("ps_lvl_cat"), имя) }
            return т("ps_lvl_cat_any")
        }
    }

    /// Выдача по написаниям: своё место не «вся страна», а items_city пуст — «Рядом не нашли — по всему Казахстану»;
    /// items_cat пуст при разделе от ИИ — «без раздела»; оба — одной строкой.
    private func подписьКарточек(_ листание: ЛистаниеПохожихФото) -> String? {
        let безРаздела = !раздел.isEmpty && листание.раздел.isEmpty
        switch (листание.шире, безРаздела) {
        case (false, false):
            return nil
        case (true, false):
            return т("ps_lvl_country")
        case (true, true):
            return ПохожиеПоФотоText.т("psi_lvl_wide")
        case (false, true):
            if let имя = СловарьЖивогоПоиска.имя(раздел) {
                return String(format: ПохожиеПоФотоText.т("psi_lvl_nocat"), имя)
            }
            return ПохожиеПоФотоText.т("psi_lvl_nocat_any")
        }
    }

    /// «Исправить запрос» на экране похожих: свой текст — новый поиск каскадом; раздел от ИИ остаётся (каскад сам
    /// расширит). Пустой текст — ничего.
    func искатьЗаново(_ текст: String) {
        let чистый = текст.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return }
        поколение += 1
        let номер = поколение
        задача?.cancel()
        забытьЛистание()
        запрос = String(чистый.prefix(120))
        /* Свой текст — в капсуле он, а не описание от ИИ; ищем им каскадом, как раньше. */
        описание = ""
        своимИИ = false
        догадка = false
        выдача = nil
        товары = []
        всего = nil
        шаг = .идёт
        задача = Task { @MainActor in await найтиПохожие(номер) }
    }

    /// «Повторить»: распознано — снова выдача, нет — снова то же фото на сайт; фото нет — к камере.
    func повторить() {
        if !запрос.isEmpty {
            поколение += 1
            let номер = поколение
            шаг = .идёт
            задача?.cancel()
            забытьЛистание()
            задача = Task { @MainActor in await найтиПохожие(номер) }
        } else if let адрес = адресФото {
            поколение += 1
            забытьЛистание()
            распознать(адрес)
        } else {
            снятьЕщё()
        }
    }

    /// Лента покажет то же, что экран похожих: выдача есть и найдена в своём месте. Лента всегда ищет в выбранном
    /// городе (FeedModel.обновить): выдача, найденная только по всей стране (шире), там сузилась бы до города, где
    /// каскад уже получил ноль, а пустая — тем более пуста. Тогда «Все в ленте» не показываем.
    var вЛентуМожно: Bool {
        guard let выдача, !выдача.товары.isEmpty, !выдача.шире else { return false }
        return !выдача.запрос.isEmpty || !выдача.раздел.isEmpty
    }

    /// «Все в ленте»: окно закрывается, в ленту встают запрос и раздел, которые дали выдачу на экране (сработал
    /// «только раздел» — пустой запрос и раздел), плашка «Ищем: …». Выдача по написаниям (items) — и её qa: лента ищет
    /// «ИЛИ» по написаниям, а не короткий запрос через q. Только когда вЛентуМожно.
    func вЛенту() {
        guard вЛентуМожно, let выдача else { return }
        let найдено = выдача.запрос
        let ключ = выдача.раздел
        let слова = найдено.isEmpty ? (СловарьЖивогоПоиска.имя(ключ) ?? "") : найдено
        закрыть()
        итог = ИтогПоискаПоФото(запрос: найдено, раздел: ключ, qa: найдено.isEmpty ? "" : (листание?.qa ?? ""))
        if !слова.isEmpty { показатьПлашку(String(format: т("ps_found"), слова)) }
    }

    /// «Войти» в листе гостя: свой экран входа поверх всего; вошли — камера.
    func войтиИзВорот() {
        ворота = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ВходПоверх.показать(готово: { [weak self] in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    self?.открытьКамеру()
                }
            })
        }
    }

    /// «Регистрация через eGov» в листе гостя.
    func eGovИзВорот(_ открыть: @escaping (URL) -> Void) {
        ворота = false
        guard let адрес = Config.страницаСайта("cabinet?egov=1") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            открыть(адрес)
        }
    }

    func закрыть() {
        поколение += 1
        задача?.cancel()
        задача = nil
        /* Следующая страница выдачи закрытому окну не нужна; само листание (как и выдача) живёт до нового снимка. */
        задачаЕщё?.cancel()
        задачаЕщё = nil
        грузимЕщё = false
        окно = false
    }

    /// Живой поиск камерой услышал от сайта «нужен вход» (сеанс истёк, пока окно открыто): как у снимка — окно
    /// закрывается, через миг лист входа.
    func входДляЖивого() {
        закрыть()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            ворота = true
        }
    }

    private func показатьПлашку(_ текст: String) {
        плашка = текст
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self.плашка == текст { self.плашка = nil }
        }
    }
}

// MARK: - Слой и окно

/// Лист гостя и окно поиска по фото — слой под лентой, чтобы его листы не спорили с листами ленты.
struct СлойПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .sheet(isPresented: $модель.ворота) {
                ЛистВходаПоискаФото(модель: модель, открыть: открыть)
            }
            .fullScreenCover(isPresented: $модель.окно) {
                ОкноПоискаПоФото(модель: модель, открыть: открыть)
            }
    }
}

/// Окно поверх всего: камера → «Ищем похожие…» → похожие (карточки открываются в том же стеке) или ошибка.
struct ОкноПоискаПоФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void
    /// Камера живёт, пока открыто окно: «Снять ещё» не собирает её заново.
    @StateObject private var камера = КамераПоиска()
    /// Живой поиск («Авто») — тоже на всё окно: вернулись от объявления — полоса похожих на месте.
    @StateObject private var живой = ЖивойПоискКамеры()
    /// Стек окна: объявление открыто (из сетки похожих или из полосы живого поиска) — оно в оформлении телефона,
    /// а не в тёмном камеры.
    @State private var путь = NavigationPath()
    /// Тема окна приложения (выбор кабинета или iPhone) — её получают похожие и объявление.
    @Environment(\.colorScheme) private var схемаОкна

    /// Камера, «Ищем похожие…» и ошибка — тёмные; похожие и открытое объявление — в теме приложения.
    private var тёмный: Bool { модель.шаг != .результаты && путь.isEmpty }

    var body: some View {
        NavigationStack(path: $путь) {
            содержимое
                .navigationDestination(for: Listing.self) { товар in
                    ListingDetailView(товар: товар, открыть: { адрес in
                        модель.закрыть()
                        открыть(адрес)
                    }, листание: источникЛистания(товар))
                }
        }
        .tint(Theme.зелёный2)
        /* Тёмная камера — только этому окну. .preferredColorScheme(.dark) красил ВСЁ окно приложения, а возвращая nil,
           снимал с окна тему, выбранную в кабинете (overrideUserInterfaceStyle, SceneDelegate): после камеры приложение
           оставалось в теме iPhone — тёмным у кого iPhone тёмный. Строка состояния на тёмных шагах спрятана, как у
           камеры подачи (PostingGuidedCamera): тёмные часы на чёрном не видны. */
        .environment(\.colorScheme, тёмный ? .dark : схемаОкна)
        .statusBarHidden(тёмный)
        .photosPicker(isPresented: $модель.галерея, selection: $модель.элемент, matching: .images)
        .onChange(of: модель.элемент) { _, новый in
            модель.принять(новый)
        }
        .onDisappear {
            живой.приостановить()
            камера.остановить()
        }
    }

    /// Листание (ListingFlip.swift): открыто из выдачи похожих — по ней (выдача по написаниям — у последнего её
    /// следующая страница), из полосы живого поиска — по полосе; поверх карточки (её похожие) — нет.
    private func источникЛистания(_ товар: Listing) -> ИсточникЛистанияОбъявлений? {
        guard путь.count <= 1 else { return nil }
        let м = модель
        var ещё: (@MainActor (Listing) async -> [Listing]?)? = nil
        if м.естьЕщё { ещё = { _ in await м.дальшеИДождаться() } }
        return ИсточникЛистанияОбъявлений.поСписку(м.товары, открыто: товар, ещё: ещё)
            ?? ИсточникЛистанияОбъявлений.поСписку(живой.товары, открыто: товар)
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.шаг {
        case .камера:
            ЭкранКамерыПоиска(модель: модель, камера: камера, живой: живой)
                .toolbar(.hidden, for: .navigationBar)
        case .идёт:
            ЭкранРаспознаванияФото(модель: модель)
                .toolbar(.hidden, for: .navigationBar)
        case .результаты:
            ЭкранПохожихПоФото(модель: модель)
        case .ошибка(let текст):
            ЭкранОшибкиПоискаФото(модель: модель, текст: текст)
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Лист гостя до камеры (mkRegGate сайта, нативно): зачем вход, «Войти», «Регистрация через eGov», «Позже».
private struct ЛистВходаПоискаФото: View {
    @ObservedObject var модель: ПоискПоФотоСайта
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { ПоискСайтаText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 72, height: 72)
                    .background(Theme.мята, in: Circle())
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
                Text(т("ps_gate_title"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                Text(т("ps_gate_text"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)
                ЗелёнаяКнопкаФото(заголовок: т("sign_in"), значок: "person.crop.circle") { модель.войтиИзВорот() }
                    .padding(.bottom, 10)
                ЗелёнаяКнопкаФото(заголовок: т("gate_go"), значок: "checkmark.shield", контурная: true) {
                    модель.eGovИзВорот(открыть)
                }
                .padding(.bottom, 6)
                Button { модель.ворота = false } label: {
                    Text(т("later"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Кнопка во всю ширину, как у экранов подачи: зелёная заливка или зелёный контур, скругление 14, Dynamic Type.
struct ЗелёнаяКнопкаФото: View {
    let заголовок: String
    let значок: String
    var контурная = false
    var наТёмном = false
    let действие: () -> Void

    init(заголовок: String, значок: String, контурная: Bool = false, наТёмном: Bool = false,
         действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.значок = значок
        self.контурная = контурная
        self.наТёмном = наТёмном
        self.действие = действие
    }

    private var цветТекста: Color {
        if !контурная { return Color.white }
        return наТёмном ? Color.white : Theme.зелёный2
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Image(systemName: значок)
                    .font(.body.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.body.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(цветТекста)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .fill(контурная ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.зелёный2))
            }
            .overlay {
                if контурная {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(наТёмном ? Color.white.opacity(0.55) : Theme.зелёный2, lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото())
    }
}

/// Лёгкое сжатие под пальцем (как .mh-c:active сайта) — остаётся и при «Уменьшении движения».
struct НажатиеКнопкиФото: ButtonStyle {
    var сжатие: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? сжатие : 1)
            .animation(ДвижениеСайта.нажатие, value: configuration.isPressed)
    }
}

/// Четыре уголка рамки распознавания (.mk-pc сайта): длина, цвет и толщина — для камеры и превью.
struct УголкиПоискаФото: View {
    var длина: CGFloat = 24
    var цвет: Color = Color.white.opacity(0.92)
    var толщина: CGFloat = 2.5

    var body: some View {
        Canvas { контекст, размер in
            let д = длина
            let р: CGFloat = min(10, длина / 3)
            let ш = размер.width
            let в = размер.height
            var путь = Path()
            /* левый верхний */
            путь.move(to: CGPoint(x: 0, y: д))
            путь.addLine(to: CGPoint(x: 0, y: р))
            путь.addQuadCurve(to: CGPoint(x: р, y: 0), control: CGPoint(x: 0, y: 0))
            путь.addLine(to: CGPoint(x: д, y: 0))
            /* правый верхний */
            путь.move(to: CGPoint(x: ш - д, y: 0))
            путь.addLine(to: CGPoint(x: ш - р, y: 0))
            путь.addQuadCurve(to: CGPoint(x: ш, y: р), control: CGPoint(x: ш, y: 0))
            путь.addLine(to: CGPoint(x: ш, y: д))
            /* левый нижний */
            путь.move(to: CGPoint(x: 0, y: в - д))
            путь.addLine(to: CGPoint(x: 0, y: в - р))
            путь.addQuadCurve(to: CGPoint(x: р, y: в), control: CGPoint(x: 0, y: в))
            путь.addLine(to: CGPoint(x: д, y: в))
            /* правый нижний */
            путь.move(to: CGPoint(x: ш - д, y: в))
            путь.addLine(to: CGPoint(x: ш - р, y: в))
            путь.addQuadCurve(to: CGPoint(x: ш, y: в - р), control: CGPoint(x: ш, y: в))
            путь.addLine(to: CGPoint(x: ш, y: в - д))
            контекст.stroke(путь, with: .color(цвет),
                            style: StrokeStyle(lineWidth: толщина, lineCap: .round, lineJoin: .round))
        }
        .shadow(color: Color.black.opacity(0.35), radius: 2)
        .accessibilityHidden(true)
    }
}
