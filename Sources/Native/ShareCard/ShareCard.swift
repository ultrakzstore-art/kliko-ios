import SwiftUI
import UIKit

/**
 «ПОДЕЛИТЬСЯ» КАРТИНКОЙ — ЭТАП 19 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «следующие этапы»).

 Кнопка «Поделиться» в карточке объявления отдаёт не только ссылку, но и картинку: фото, цена, название, город и знак
 Kliko (КарточкаДляОтправки), нарисованную ImageRenderer в масштабе экрана. В мессенджере получатель видит объявление
 сразу, даже если ссылку не раскроет.

 🔴 ССЫЛКА — ПЕРВОЙ. Лист отправки (UIActivityViewController) получает [адрес, картинка]: адрес первым, и мессенджеры,
 которые умеют, по-прежнему разворачивают его в превью страницы; картинка идёт рядом. ShareLink двух разных предметов
 разом не отдаёт (items — одного типа), а Transferable с двумя представлениями отдаёт получателю одно из них на выбор —
 картинку или ссылку, а не обе. Поэтому здесь системный лист напрямую, как у мостов фото и контактов (верхний экран).

 🔴 СЕТЬ НЕ ЖДЁМ. Фото берём только из общего кэша запросов (URLCache.shared: его наполняет AsyncImage галереи) — какое
 открыто в галерее, иначе обложку. Нет в кэше — вместо фото подложка со значком: кнопка срабатывает сразу. Картинка не
 нарисовалась — отдаём одну ссылку, ровно как раньше (ShareLink(item:)).
 */
enum ОтправкаКартинкой {
    /// Картинка объявления для отправки или nil — не нарисовалась. `фото` — какое открыто в галерее.
    @MainActor
    static func картинка(_ товар: Listing, фото: URL?, масштаб: CGFloat) -> UIImage? {
        let снимок = изКэша(фото) ?? изКэша(товар.обложка)
        let рисовальщик = ImageRenderer(content: КарточкаДляОтправки(товар: товар, фото: снимок))
        рисовальщик.scale = max(1, масштаб)
        return рисовальщик.uiImage
    }

    /// Фото, уже скачанное раньше, — из кэша, без запроса. Нет — nil.
    static func изКэша(_ адрес: URL?) -> UIImage? {
        guard let адрес, let ответ = URLCache.shared.cachedResponse(for: URLRequest(url: адрес)) else { return nil }
        return UIImage(data: ответ.data)
    }

    /// Системный лист отправки: ссылка первой, картинка — если есть. false — показать не над чем (окна нет).
    @MainActor
    @discardableResult
    static func поделиться(адрес: URL, картинка: UIImage?) -> Bool {
        guard let верх = верхнийЭкран() else { return false }
        var предметы: [Any] = [адрес]
        if let картинка { предметы.append(картинка) }
        let лист = UIActivityViewController(activityItems: предметы, applicationActivities: nil)
        /* На iPad лист — всплывающий, и без точки привязки UIKit роняет приложение. Кнопка «Поделиться» — справа в
           шапке, туда и указываем. */
        if let всплывающее = лист.popoverPresentationController {
            let вид: UIView = верх.view
            всплывающее.sourceView = вид
            всплывающее.sourceRect = CGRect(x: вид.bounds.maxX - 44, y: вид.safeAreaInsets.top, width: 1, height: 1)
            всплывающее.permittedArrowDirections = [.up]
        }
        верх.present(лист, animated: true)
        return true
    }

    /// Самый верхний показанный экран ключевого окна — над ним и лист.
    @MainActor
    private static func верхнийЭкран() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var верх = (окна.first { $0.isKeyWindow } ?? окна.first)?.rootViewController
        while let дальше = верх?.presentedViewController { верх = дальше }
        return верх
    }
}

/**
 Картинка для отправки: фото 4:3, цена, название, город и знак Kliko. Всегда светлая и одного размера (360 pt в ширину,
 в пикселях — масштаб экрана): её увидят в чужом мессенджере, где наша тёмная тема и крупный текст ни при чём.
 */
struct КарточкаДляОтправки: View {
    let товар: Listing
    /// Фото из кэша; nil — подложка со значком.
    let фото: UIImage?

    static let ширина: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            обложка
                .frame(width: Self.ширина, height: Self.ширина * 3 / 4)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !товар.title.isEmpty {
                    Text(товар.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !товар.city.isEmpty {
                    Label(товар.city, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                HStack(alignment: .center) {
                    знак
                    Spacer(minLength: 8)
                    Text(ShareCardText.т("site"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.green2)
                }
                .padding(.top, 10)
            }
            .padding(16)
            .frame(width: Self.ширина, alignment: .leading)
        }
        .frame(width: Self.ширина, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private var обложка: some View {
        if let фото {
            Image(uiImage: фото)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Theme.mint
                Image(systemName: "photo")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.green2.opacity(0.5))
            }
        }
    }

    /// Знак Kliko — те же картинки, что у KlikoWordmark (296 × 74), но без мигающего маяка: на снимке анимации нет.
    private var знак: some View {
        let высота: CGFloat = 20
        let ширина = 296 * высота / 74
        return ZStack(alignment: .topLeading) {
            Image("WmKliko").resizable().renderingMode(.template).foregroundStyle(Theme.ink)
                .frame(width: ширина, height: высота)
            Image("WmKz").resizable().renderingMode(.original)
                .frame(width: ширина, height: высота)
        }
        .frame(width: ширина, height: высота)
        .accessibilityHidden(true)
    }
}
