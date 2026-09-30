import SwiftUI
import UIKit
import ImageIO

/**
 КАРТИНКИ ЛЕНТЫ — ИСПРАВЛЕНИЯ С ТЕЛЕФОНА (владелец 25.09.2026: «лента подвисает»; проверка на телефоне, сборка 33).

 До этого каждая картинка ленты была голым AsyncImage. У него нет кэша в памяти, а готовый снимок он отдаёт слою
 нераспакованным: WebP (_t.webp объявлений, cat-*.webp плиток) iOS распаковывает программно, и делала это главная
 очередь в том же кадре, где карточка въезжает на экран, — а на 120 Гц на кадр всего 8 мс. Без уменьшения до размера
 ячейки: если у объявления нет thumb, распаковывалось полное фото.

 Здесь картинка скачивается тем же URLSession.shared (URLCache.shared остаётся полным — из него берёт ShareCard),
 уменьшается до размера ячейки и распаковывается сразу, не на главной очереди (ImageIO, CGImageSourceCreateThumbnail),
 и кладётся в память (NSCache): карточка, созданная заново, показывает фото с первого кадра. Одна и та же картинка,
 нужная двум ячейкам сразу, скачивается один раз.
 */
@MainActor
final class КартинкиЛенты {
    static let shared = КартинкиЛенты()

    /// Распакованные картинки по адресу и размеру. Вес — байты растра; при нехватке памяти NSCache отдаёт их сам.
    private let память: NSCache<NSString, UIImage> = {
        let кэш = NSCache<NSString, UIImage>()
        кэш.totalCostLimit = 100 * 1024 * 1024
        return кэш
    }()
    /// Одна скачивающаяся картинка: общая задача и сколько ячеек её ещё ждёт (не отменённых).
    private struct Загрузка {
        let номер: Int
        let задача: Task<UIImage?, Never>
        var ждут: Int
    }
    /// Картинки, которые уже качаются: вторая ячейка ждёт ту же загрузку, а не начинает свою.
    private var вПути: [String: Загрузка] = [:]
    private var номерЗагрузки = 0

    private init() {}

    /// Ключ — адрес, размер и режим: для «заполнить» картинка уменьшается иначе (по короткой стороне).
    private static func ключ(_ адрес: URL, _ пикселей: Int, _ заполнить: Bool) -> String {
        адрес.absoluteString + "#" + String(пикселей) + (заполнить ? "f" : "")
    }

    /// Готовая картинка из памяти или nil — без сети, для первого кадра ячейки.
    func готовая(_ адрес: URL, пикселей: Int, заполнить: Bool) -> UIImage? {
        память.object(forKey: Self.ключ(адрес, пикселей, заполнить) as NSString)
    }

    /// Скачать, уменьшить до размера ячейки и распаковать не на главной очереди. Не вышло — nil.
    /// Ячейку убрали с экрана (её .task отменён) и загрузку больше никто не ждёт — запрос отменяется,
    /// как это делал AsyncImage: при быстрой прокрутке сеть не забита снимками пролетевших карточек.
    func загрузить(_ адрес: URL, пикселей: Int, заполнить: Bool) async -> UIImage? {
        let ключ = Self.ключ(адрес, пикселей, заполнить)
        if let есть = память.object(forKey: ключ as NSString) { return есть }
        if Task.isCancelled { return nil }
        let загрузка: Загрузка
        if var идёт = вПути[ключ] {
            идёт.ждут += 1
            вПути[ключ] = идёт
            загрузка = идёт
        } else {
            номерЗагрузки += 1
            let задача = Task<UIImage?, Never> {
                guard let данные = await КартинкиЛенты.скачать(адрес, пикселей: пикселей, заполнить: заполнить) else { return nil }
                if Task.isCancelled { return nil }
                guard let картинка = await КартинкиЛенты.уменьшить(данные, пикселей: пикселей, заполнить: заполнить)
                else { return nil }
                self.память.setObject(картинка, forKey: ключ as NSString, cost: КартинкиЛенты.вес(картинка))
                return картинка
            }
            загрузка = Загрузка(номер: номерЗагрузки, задача: задача, ждут: 1)
            вПути[ключ] = загрузка
        }
        let номер = загрузка.номер
        let картинка = await withTaskCancellationHandler {
            await загрузка.задача.value
        } onCancel: {
            Task { @MainActor in КартинкиЛенты.shared.отпустить(ключ, номер: номер) }
        }
        // Задача уже закончилась (готовое лежит в памяти) — запись больше не нужна. Номер: не тронуть новую загрузку.
        if вПути[ключ]?.номер == номер { вПути[ключ] = nil }
        return картинка
    }

    /// Скорость: картинки ячеек, до которых человек вот-вот долистает, — скачать, уменьшить и положить в память заранее,
    /// с тем же ключом, что у ячейки (адрес, пиксели, режим). Уже в памяти или в пути — пропускаем. Ячейка, пришедшая
    /// за такой картинкой, ждёт ту же загрузку; ушла с экрана последней из ждущих — загрузка отменяется, как обычно.
    func заранее(_ адреса: [URL], пунктов: CGFloat, масштаб: CGFloat, заполнить: Bool = true) {
        let пикселей = max(64, Int((пунктов * max(1, масштаб)).rounded(.up)))
        for адрес in адреса {
            let ключ = Self.ключ(адрес, пикселей, заполнить)
            guard память.object(forKey: ключ as NSString) == nil, вПути[ключ] == nil else { continue }
            номерЗагрузки += 1
            let номер = номерЗагрузки
            let задача = Task<UIImage?, Never>(priority: .utility) {
                let данные = await КартинкиЛенты.скачать(адрес, пикселей: пикселей, заполнить: заполнить)
                defer { if self.вПути[ключ]?.номер == номер { self.вПути[ключ] = nil } }
                guard let данные else { return nil }
                if Task.isCancelled { return nil }
                guard let картинка = await КартинкиЛенты.уменьшить(данные, пикселей: пикселей, заполнить: заполнить)
                else { return nil }
                self.память.setObject(картинка, forKey: ключ as NSString, cost: КартинкиЛенты.вес(картинка))
                return картинка
            }
            /* Ждущих ячеек пока нет (0): придёт ячейка — станет 1, уйдёт — 0, и загрузка отменится. */
            вПути[ключ] = Загрузка(номер: номер, задача: задача, ждут: 0)
        }
    }

    /// Одна из ждущих ячеек отменена. Не осталось ни одной — отменить загрузку (URLSession рвёт запрос).
    private func отпустить(_ ключ: String, номер: Int) {
        guard var идёт = вПути[ключ], идёт.номер == номер else { return }
        идёт.ждут -= 1
        if идёт.ждут > 0 {
            вПути[ключ] = идёт
        } else {
            идёт.задача.cancel()
            вПути[ключ] = nil
        }
    }

    // MARK: - Лёгкие фото (img.php, правка 102 сервера)

    /// Адрес уменьшенной копии на img.php или nil — качать исходный адрес: рубильник выключен, фото не из img/uploads
    /// сайта, нужно больше 1280 точек (полный экран — оригинал), превью _t и так не больше нужного.
    /// Ключ памяти остаётся по исходному адресу: ячейка и «заранее» делят одну загрузку, как раньше.
    nonisolated static func адресЛёгкого(_ адрес: URL, пикселей: Int, заполнить: Bool) -> URL? {
        guard Config.лёгкиеФото else { return nil }
        /* Ширины, которые делает img.php сайта (наибольшая сторона); другие сервер округляет вверх до этих же.
           Превью ленты (_t) — около 420 точек: его только уменьшаем, крупнее не просим — трафик не должен расти. */
        let ширины = [160, 320, 480, 640, 960, 1280]
        let ширинаПревью = 420
        let полный = адрес.absoluteURL
        guard let хост = полный.host?.lowercased(), let свой = Config.apiBase.host?.lowercased(),
              хост == свой || хост == "www." + свой,
              полный.query == nil else { return nil }
        let путь = полный.path
        guard путь.hasPrefix("/img/uploads/"), !путь.contains("..") else { return nil }
        let расширение = полный.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "webp"].contains(расширение) else { return nil }
        /* «Заполнить» обрезает снимок по ячейке: короткая сторона 4:3 должна покрыть её — длинная на треть больше. */
        let нужно = заполнить ? (пикселей * 4 + 2) / 3 : пикселей
        guard let ширина = ширины.first(where: { $0 >= нужно }) else { return nil }
        let имя = полный.deletingPathExtension().lastPathComponent
        if имя.hasSuffix("_t") && ширина >= ширинаПревью { return nil }
        var части = URLComponents()
        части.scheme = полный.scheme ?? "https"
        части.host = полный.host
        части.port = полный.port
        части.path = "/img.php"
        части.queryItems = [URLQueryItem(name: "src", value: String(путь.dropFirst())),
                            URLQueryItem(name: "w", value: String(ширина))]
        return части.url
    }

    /// Байты картинки: при включённых лёгких фото — с img.php (Accept с WebP/AVIF), не вышло (не 2xx, нет сети) —
    /// исходный адрес. nil — не скачалось вовсе.
    nonisolated private static func скачать(_ адрес: URL, пикселей: Int, заполнить: Bool) async -> Data? {
        if let лёгкий = адресЛёгкого(адрес, пикселей: пикселей, заполнить: заполнить) {
            var запрос = URLRequest(url: лёгкий)
            запрос.setValue("image/avif,image/webp,image/jpeg;q=0.8,image/png;q=0.8", forHTTPHeaderField: "Accept")
            if let ответ = try? await URLSession.shared.data(for: запрос),
               let http = ответ.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode), !ответ.0.isEmpty {
                return ответ.0
            }
            if Task.isCancelled { return nil }
        }
        guard let ответ = try? await URLSession.shared.data(from: адрес) else { return nil }
        if let http = ответ.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
        return ответ.0
    }

    /// Сколько байт занимает растр — цена для NSCache.
    private static func вес(_ картинка: UIImage) -> Int {
        guard let растр = картинка.cgImage else { return 1 }
        return max(1, растр.bytesPerRow * растр.height)
    }

    /// Уменьшение и распаковка (ShouldCacheImmediately) — вне главной очереди: nonisolated async уходит с MainActor.
    /// Больше исходника не растягивает: MaxPixelSize — только потолок, и он ограничивает ДЛИННУЮ сторону.
    /// Для «заполнить» (scaledToFill) короткая сторона тоже должна покрыть ячейку, иначе вертикальное фото в
    /// горизонтальной ячейке (или 16:9 в квадратной) растягивается и мылится — потолок поднимается во столько раз,
    /// во сколько длинная сторона снимка больше короткой (но не больше самого снимка и не больше 4× ячейки).
    nonisolated private static func уменьшить(_ данные: Data, пикселей: Int, заполнить: Bool) async -> UIImage? {
        let параметрыИсточника = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, параметрыИсточника) else { return nil }
        var потолок = пикселей
        if заполнить,
           let свойства = CGImageSourceCopyPropertiesAtIndex(источник, 0, nil) as? [String: Any],
           let ширина = (свойства[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
           let высота = (свойства[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue,
           ширина > 0, высота > 0 {
            let длинная = max(ширина, высота)
            let короткая = min(ширина, высота)
            let нужно = Int((Double(пикселей) * Double(длинная) / Double(короткая)).rounded(.up))
            потолок = max(пикселей, min(длинная, нужно, пикселей * 4))
        }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: потолок] as CFDictionary
        guard let растр = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры) else { return nil }
        return UIImage(cgImage: растр)
    }
}

/// Картинка ячейки ленты вместо AsyncImage: из памяти — сразу, иначе заглушка, пока КартинкиЛенты не принесёт
/// уменьшенную. `пунктов` — наибольшая сторона ячейки в точках; `заполнить` — scaledToFill (фото карточек), иначе
/// scaledToFit (картинки плиток разделов). Обрезает тот, кто ставит рамку, — как и у AsyncImage.
struct КартинкаЛенты<Заглушка: View>: View {
    let адрес: URL?
    let пунктов: CGFloat
    let заполнить: Bool
    let заглушка: Заглушка
    @Environment(\.displayScale) private var масштаб
    @State private var загруженная: UIImage? = nil
    @State private var загруженАдрес: URL? = nil

    init(_ адрес: URL?, пунктов: CGFloat, заполнить: Bool = true, @ViewBuilder заглушка: () -> Заглушка) {
        self.адрес = адрес
        self.пунктов = пунктов
        self.заполнить = заполнить
        self.заглушка = заглушка()
    }

    var body: some View {
        ZStack {
            if let картинка = показать {
                Image(uiImage: картинка)
                    .resizable()
                    .aspectRatio(contentMode: заполнить ? ContentMode.fill : ContentMode.fit)
            } else {
                заглушка
            }
        }
        .task(id: адрес) { await загрузить() }
    }

    /// Пикселей по длинной стороне: точки ячейки на плотность экрана, не меньше 64.
    private var пикселей: Int {
        max(64, Int((пунктов * max(1, масштаб)).rounded(.up)))
    }

    /// Что показать: своя загруженная для этого адреса или готовая из памяти (ячейку создали заново).
    @MainActor
    private var показать: UIImage? {
        guard let цель = адрес else { return nil }
        if загруженАдрес == цель, let своя = загруженная { return своя }
        return КартинкиЛенты.shared.готовая(цель, пикселей: пикселей, заполнить: заполнить)
    }

    @MainActor
    private func загрузить() async {
        guard let цель = адрес else { return }
        if загруженАдрес == цель && загруженная != nil { return }
        let размер = пикселей
        if let есть = КартинкиЛенты.shared.готовая(цель, пикселей: размер, заполнить: заполнить) {
            загруженная = есть
            загруженАдрес = цель
            return
        }
        let пришла = await КартинкиЛенты.shared.загрузить(цель, пикселей: размер, заполнить: заполнить)
        guard !Task.isCancelled, let новая = пришла else { return }
        загруженная = новая
        загруженАдрес = цель
    }
}
