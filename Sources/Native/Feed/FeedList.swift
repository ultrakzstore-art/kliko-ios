import SwiftUI
import UIKit

/**
 ЛЕНТА СИСТЕМНЫМ СПИСКОМ (владелец 17.10.2026: «витрина всё равно подвисает, будто какое-то тяжёлое приложение»; на
 варианты ускорения — «Да, думаю перенести на сетку iOS»).

 Прежняя лента — ScrollView с LazyVGrid: ленивая сетка SwiftUI создаёт карточки по мере листания, но не отдаёт их
 обратно — чем дальше листают бесконечную ленту, тем больше живых карточек и тем тяжелее каждое обновление. Здесь та же
 лента — List (внутри iOS это UICollectionView): на экране живут только видимые строки, ячейки переиспользуются. Карточки,
 дизайн, переходы (и зум из карточки, ListingZoom.swift), меню долгого нажатия и «потяни — обновится» — прежние: всё
 остаётся в одном дереве SwiftUI. Ряд сетки — строка списка из 2 (на iPad — больше) карточек одной высоты.

 Чего у List нет, даёт НаблюдательСпискаЛенты: смещение прокрутки для нижней панели (ПанельПоПрокрутке), «у верха
 ленты» для полосы «Вы смотрели» и начало жеста для замера подвисаний (ЗамерЛистания). Невидимый якорь в первой строке
 находит над собой прокрутку списка и подключает её; подключение живёт, пока жива сама прокрутка, — строка с якорем может
 уйти за край и переиспользоваться.

 Рубильник feed_list (api/app_config.php): в сборке включён, сервер может выключить — тогда прежняя сетка, как в 85.
 */
extension Config {
    static let лентаСпискомВСборке = true
    static var лентаСписком: Bool { НастройкиСервера.вклВыкл("feed_list", сборка: лентаСпискомВСборке) }

    /// Сборка 87: верх главной (плитки, ряды разделов, VIP, «Для вас», заголовок ленты) — отдельными строками списка, а
    /// не одной (NativeFeedView.верхСпискаСтроками). Замер в CI 17.10.2026 (FeedScrollBench.swift): верх одной строкой
    /// собирался заново целиком при каждом возврате к нему — со всеми рядами и их карточками разом; даже с простыми
    /// ячейками ленты листание теряло больше половины кадров. Рубильник home_rows: в сборке включён, сервер может
    /// выключить — верх снова одной строкой.
    static let верхГлавнойСтрокамиВСборке = true
    static var верхГлавнойСтроками: Bool { НастройкиСервера.вклВыкл("home_rows", сборка: верхГлавнойСтрокамиВСборке) }
}

/// Ряд сетки в списке: карточки одной строки, ключ — по первой ячейке (смена числа колонок даёт новые ключи).
struct РядСпискаЛенты: Identifiable {
    let id: String
    let ячейки: [ЯчейкаЛенты]

    /// Разбить ячейки на ряды по `колонок`.
    static func ряды(_ ячейки: [ЯчейкаЛенты], колонок: Int) -> [РядСпискаЛенты] {
        let n = max(1, колонок)
        var итог: [РядСпискаЛенты] = []
        итог.reserveCapacity(ячейки.count / n + 1)
        var начало = 0
        while начало < ячейки.count {
            let конец = min(начало + n, ячейки.count)
            let кусок = Array(ячейки[начало..<конец])
            итог.append(РядСпискаЛенты(id: "р|" + кусок[0].id, ячейки: кусок))
            начало = конец
        }
        return итог
    }

    /// Сколько колонок помещается: как GridItem(.adaptive(minimum:)) — по наименьшей ширине карточки и зазору.
    static func колонок(ширина: CGFloat, поле: CGFloat, зазор: CGFloat, наименьшая: CGFloat) -> Int {
        let доступно: CGFloat = max(0, ширина - 2 * поле)
        let n = Int(((доступно + зазор) / (наименьшая + зазор)).rounded(.down))
        return max(1, n)
    }

    /// Ширина карточки при `колонок` колонках.
    static func ширинаКарточки(ширина: CGFloat, поле: CGFloat, зазор: CGFloat, колонок: Int) -> CGFloat {
        let n = CGFloat(max(1, колонок))
        let доступно: CGFloat = max(0, ширина - 2 * поле)
        return max(0, (доступно - (n - 1) * зазор) / n)
    }
}

/// Ширина карточки ряда списка ленты: по ней карточка просит фото своего размера (ListingCard.пунктовФото). 0 — ширину
/// не сказали (прежняя сетка, полки, избранное) — прежние 260 точек.
private struct КлючШириныКарточкиЛенты: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var ширинаКарточкиЛенты: CGFloat {
        get { self[КлючШириныКарточкиЛенты.self] }
        set { self[КлючШириныКарточкиЛенты.self] = newValue }
    }
}

extension View {
    /// Строка списка ленты: без полей, разделителей и подложки List — вид как у прежней прокрутки.
    func строкаСпискаЛенты() -> some View {
        self
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/**
 Смещение прокрутки списка ленты — тем, кому оно нужно. Одна прокрутка за раз (лента одна); новая заменяет прежнюю.
 KVO на contentOffset приходит на главной нити, и работы в нём — пара сравнений: панель решает по порогам, «у верха»
 публикуется только при смене.
 */
@MainActor
final class НаблюдательСпискаЛенты: NSObject, ObservableObject {
    static let shared = НаблюдательСпискаЛенты()

    /// Ближе этого к верху — «у верха ленты» (как прежнее «> −40» у ВерхЛентыКлюч).
    static let порогВерха: CGFloat = 40

    @Published private(set) var уВерха = true

    private weak var прокрутка: UIScrollView?
    private var слежка: NSKeyValueObservation?
    private var где = ""

    private override init() {
        super.init()
    }

    /// Якорь первой строки нашёл прокрутку списка. Та же — только «где»; другая — переподключиться.
    func подключить(_ новая: UIScrollView, где: String) {
        self.где = где
        if прокрутка === новая { return }
        отключить()
        прокрутка = новая
        новая.panGestureRecognizer.addTarget(self, action: #selector(листают(_:)))
        слежка = новая.observe(\.contentOffset, options: [.new]) { [weak self] вид, _ in
            MainActor.assumeIsolated {
                self?.сдвинулось(вид)
            }
        }
        #if DEBUG
        БенчЛистания.shared.может(новая, где: где)      // замер листания в CI (-klikoScrollBench, FeedScrollBench.swift)
        #endif
    }

    private func отключить() {
        слежка?.invalidate()
        слежка = nil
        прокрутка?.panGestureRecognizer.removeTarget(self, action: #selector(листают(_:)))
        прокрутка = nil
    }

    private func сдвинулось(_ вид: UIScrollView) {
        let сдвиг: CGFloat = вид.contentOffset.y + вид.adjustedContentInset.top
        ПанельПоПрокрутке.shared.прокручено(сдвиг)
        let верх: Bool = сдвиг < Self.порогВерха
        if верх != уВерха { уВерха = верх }
    }

    @objc(klikoFeedListPan:)
    private func листают(_ жест: UIPanGestureRecognizer) {
        guard жест.state == .began, let прокрутка else { return }
        ЗамерЛистания.shared.начать(прокрутка, где: где)
    }
}

/// Невидимый якорь в первой строке списка ленты: подключает её прокрутку к НаблюдательСпискаЛенты.
struct ЯкорьСпискаЛенты: UIViewRepresentable {
    let где: String

    func makeUIView(context: Context) -> ВидЯкоряСпискаЛенты {
        let вид = ВидЯкоряСпискаЛенты()
        вид.isUserInteractionEnabled = false
        вид.backgroundColor = .clear
        вид.где = где
        return вид
    }

    func updateUIView(_ uiView: ВидЯкоряСпискаЛенты, context: Context) {
        guard uiView.где != где else { return }
        uiView.где = где
        uiView.подключить()
    }
}

/// Вид якоря: попав в окно, ищет над собой прокрутку списка. Уходя из окна, ничего не отключает — прокрутка жива.
final class ВидЯкоряСпискаЛенты: UIView {
    var где = ""

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        подключить()
    }

    func подключить() {
        guard window != nil else { return }
        var узел = superview
        while let вид = узел {
            if let найдена = вид as? UIScrollView {
                НаблюдательСпискаЛенты.shared.подключить(найдена, где: где)
                return
            }
            узел = вид.superview
        }
    }
}
