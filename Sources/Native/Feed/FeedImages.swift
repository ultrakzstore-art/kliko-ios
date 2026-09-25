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
    /// Картинки, которые уже качаются: вторая ячейка ждёт ту же загрузку, а не начинает свою.
    private var вПути: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    private static func ключ(_ адрес: URL, _ пикселей: Int) -> String {
        адрес.absoluteString + "#" + String(пикселей)
    }

    /// Готовая картинка из памяти или nil — без сети, для первого кадра ячейки.
    func готовая(_ адрес: URL, пикселей: Int) -> UIImage? {
        память.object(forKey: Self.ключ(адрес, пикселей) as NSString)
    }

    /// Скачать, уменьшить до `пикселей` по длинной стороне и распаковать не на главной очереди. Не вышло — nil.
    func загрузить(_ адрес: URL, пикселей: Int) async -> UIImage? {
        let ключ = Self.ключ(адрес, пикселей)
        if let есть = память.object(forKey: ключ as NSString) { return есть }
        if let идёт = вПути[ключ] { return await идёт.value }
        let задача = Task<UIImage?, Never> {
            guard let ответ = try? await URLSession.shared.data(from: адрес) else { return nil }
            if let http = ответ.1 as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard let картинка = await КартинкиЛенты.уменьшить(ответ.0, пикселей: пикселей) else { return nil }
            self.память.setObject(картинка, forKey: ключ as NSString, cost: КартинкиЛенты.вес(картинка))
            return картинка
        }
        вПути[ключ] = задача
        let картинка = await задача.value
        вПути[ключ] = nil
        return картинка
    }

    /// Сколько байт занимает растр — цена для NSCache.
    private static func вес(_ картинка: UIImage) -> Int {
        guard let растр = картинка.cgImage else { return 1 }
        return max(1, растр.bytesPerRow * растр.height)
    }

    /// Уменьшение и распаковка (ShouldCacheImmediately) — вне главной очереди: nonisolated async уходит с MainActor.
    /// Больше исходника не растягивает: MaxPixelSize — только потолок.
    nonisolated private static func уменьшить(_ данные: Data, пикселей: Int) async -> UIImage? {
        let параметрыИсточника = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithData(данные as CFData, параметрыИсточника) else { return nil }
        let параметры = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                         kCGImageSourceShouldCacheImmediately: true,
                         kCGImageSourceCreateThumbnailWithTransform: true,
                         kCGImageSourceThumbnailMaxPixelSize: пикселей] as CFDictionary
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
        return КартинкиЛенты.shared.готовая(цель, пикселей: пикселей)
    }

    @MainActor
    private func загрузить() async {
        guard let цель = адрес else { return }
        if загруженАдрес == цель && загруженная != nil { return }
        let размер = пикселей
        if let есть = КартинкиЛенты.shared.готовая(цель, пикселей: размер) {
            загруженная = есть
            загруженАдрес = цель
            return
        }
        let пришла = await КартинкиЛенты.shared.загрузить(цель, пикселей: размер)
        guard !Task.isCancelled, let новая = пришла else { return }
        загруженная = новая
        загруженАдрес = цель
    }
}
