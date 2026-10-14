import SwiftUI
import UIKit

/**
 СМАХНУТЬ ОТ КРАЯ — НАЗАД (владелец 14.10.2026: «слайдом назад не работает» — в подаче объявления).

 Подача и её окна открыты поверх вкладок: системного стека с его «смахни от края — назад» у них нет. Этот модификатор
 даёт тот же жест: палец от левого края (в арабском — от правого) ведёт назад, как «‹ Назад» внизу экрана.
   · содержимое мягко идёт за пальцем — треть пути, у 44 pt упирается резиной: видно, что жест пойман, но экран
     не уезжает;
   · у края выезжает круглая стрелка 44 pt; ход перевалил порог 90 pt — она заливается зелёным «Далее →» подачи и
     один раз щёлкает;
   · отпустили за порогом или бросили (быстрее 700 pt/с в сторону «назад») — пружиной на место и назад(); не дотянули
     или за порогом резко вернули палец к краю — просто на место. После отпускания сдвиг всегда возвращается к нулю.

 Жест — UIKit, а не DragGesture: только UIScreenEdgePanGestureRecognizer у края получает приоритет над прокрутками и
 жестами SwiftUI экрана (они ждут, пока край откажется), иначе палец первой забирает прокрутка. Распознаватель вешает
 на корневой вид своего хостинга невидимый якорь, когда экран появился, и снимает, когда экран уходит: полноэкранное
 окно поверх (мастер авто) закрывает нижний — его жест под ним жить не должен. Выключен (включено == false) —
 распознаватель выключен целиком, и жесты экрана у края его не ждут.

 Кнопки «Назад» остаются: жест — дополнение, VoiceOver его не видит. «Уменьшение движения» — содержимое стоит на месте,
 появляется только кружок. Каждый кадр — только offset, прозрачность и масштаб: без GeometryReader и перерисовки экрана.
 */
extension View {
    /// Смахнуть от края экрана (слева; при арабском — справа) — назад. включено == false — жест не действует.
    func смахиваниеНазад(включено: Bool = true, назад: @escaping () -> Void) -> some View {
        modifier(СмахиваниеОтКрая(включено: включено, назад: назад))
    }
}

/// Мерки жеста и кружка.
private enum МеркиСмахиванияОтКрая {
    /// Ход пальца, за которым отпускание ведёт назад.
    static let порог: CGFloat = 90
    /// Бросок быстрее этого (pt/с, в сторону «назад») ведёт назад и до порога.
    static let бросок: CGFloat = 700
    /// Содержимое идёт за пальцем на эту долю хода…
    static let доляСдвига: CGFloat = 0.35
    /// …и не дальше этого.
    static let сдвиг: CGFloat = 44
    /// Сторона кружка со стрелкой — под палец, как у кнопок.
    static let кружок: CGFloat = 44
    /// Кружок от края, когда выехал целиком.
    static let отступКружка: CGFloat = 12
}

// MARK: - Вид: сдвиг и кружок

private struct СмахиваниеОтКрая: ViewModifier {
    let включено: Bool
    let назад: () -> Void
    @Environment(\.layoutDirection) private var направление
    /// Путь пальца от края в сторону «назад», pt; 0 — не тянут.
    @State private var ход: CGFloat = 0
    /// Ход за порогом: отпустят — назад. Стал true — один щелчок.
    @State private var взведено = false

    /// Явный init: закрытое состояние жеста не должно попадать в поэлементный.
    init(включено: Bool, назад: @escaping () -> Void) {
        self.включено = включено
        self.назад = назад
    }

    func body(content: Content) -> some View {
        let справа = направление == .rightToLeft
        /* offset сам в RTL не зеркалится: «назад» в арабском — влево, знак меняем руками. */
        let знак: CGFloat = справа ? -1 : 1
        let доля = min(ход / МеркиСмахиванияОтКрая.порог, 1)
        return content
            .offset(x: ДвижениеСайта.тихо ? 0 : Self.сдвиг(ход) * знак)
            .overlay(alignment: .leading) {
                КружокСмахиванияНазад(взведено: взведено)
                    .scaleEffect(взведено ? 1 : 0.7 + 0.3 * доля)
                    .offset(x: Self.выезд(доля) * знак)
                    .opacity(Double(min(1, доля * 2)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background(
                ЯкорьСмахиванияОтКрая(включено: включено, справа: справа,
                                      изменилось: { новый in тянут(новый) },
                                      закончилось: { последний, скорость in отпустили(последний, скорость) },
                                      отменилось: { вернуть() })
                    .frame(width: 0, height: 0)
            )
            .sensoryFeedback(.impact(weight: .light), trigger: взведено) { было, стало in !было && стало }
    }

    /// Палец идёт: новый ход и порог.
    private func тянут(_ новый: CGFloat) {
        let путь = max(0, новый)
        ход = путь
        let порог = МеркиСмахиванияОтКрая.порог
        /* Чуть ниже порога — ещё взведено: на границе кружок и щелчок не дрожат. */
        let теперь = взведено ? путь >= порог - 8 : путь >= порог
        guard теперь != взведено else { return }
        withAnimation(ДвижениеСайта.выбор) { взведено = теперь }
    }

    /// Отпустили: за порогом (и не бросили обратно к краю) или бросок к «назад» — назад; сдвиг — к нулю всегда.
    private func отпустили(_ последний: CGFloat, _ скорость: CGFloat) {
        let бросок = МеркиСмахиванияОтКрая.бросок
        let идтиНазад = скорость > бросок || (последний >= МеркиСмахиванияОтКрая.порог && скорость > -бросок / 2)
        вернуть()
        if идтиНазад { назад() }
    }

    /// Пружиной на место: и после отпускания, и когда жест забрала система.
    private func вернуть() {
        withAnimation(ДвижениеСайта.возврат) {
            ход = 0
            взведено = false
        }
    }

    /// Сдвиг содержимого: доля хода, у предела — резиной (плавно упирается в 44 pt, а не обрывается на нём).
    private static func сдвиг(_ ход: CGFloat) -> CGFloat {
        guard ход > 0 else { return 0 }
        let предел = Double(МеркиСмахиванияОтКрая.сдвиг)
        let прямо = Double(ход * МеркиСмахиванияОтКрая.доляСдвига)
        return CGFloat(предел * (1 - exp(-прямо / предел)))
    }

    /// Кружок выезжает из-за края: при 0 он целиком за краем, на пороге — на отступе от края. «Уменьшение движения» —
    /// сразу на месте, только проявляется.
    private static func выезд(_ доля: CGFloat) -> CGFloat {
        let отступ = МеркиСмахиванияОтКрая.отступКружка
        if ДвижениеСайта.тихо { return отступ }
        let кружок = МеркиСмахиванияОтКрая.кружок
        return -кружок + (кружок + отступ) * доля
    }
}

/// Кружок у края: стрелка назад на поверхности с тенью; за порогом заливается зелёным «Далее →» подачи (--acc-on).
/// chevron.backward сам смотрит «назад» по направлению письма: в арабском — вправо, к своему краю.
private struct КружокСмахиванияНазад: View {
    let взведено: Bool

    var body: some View {
        let форма = Circle()
        return Image(systemName: "chevron.backward")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(взведено ? Color.white : Theme.текст)
            .frame(width: МеркиСмахиванияОтКрая.кружок, height: МеркиСмахиванияОтКрая.кружок)
            .background(взведено ? КраскаПодачи.акцентТекст : Theme.поверхность, in: форма)
            .overlay { форма.strokeBorder(взведено ? Color.clear : Theme.линия, lineWidth: 1) }
            .shadow(color: Color(uiColor: Theme.hex(0x0D1B14, 0.18)), radius: 8, y: 3)
    }
}

// MARK: - Якорь: распознаватель края на хостинге

/**
 Невидимый якорь жеста — UIKit-контроллер нулевого размера. SwiftUI кладёт его ребёнком ближайшего UIHostingController:
 на корневой вид этого хостинга якорь и вешает распознаватель края — так он ловит палец над всем экраном, а не над
 своей пустой точкой. Свежие замыкания и флаг приходят при каждой перерисовке: жест не зовёт назад() ушедшего вида.
 */
private struct ЯкорьСмахиванияОтКрая: UIViewControllerRepresentable {
    let включено: Bool
    let справа: Bool
    /// Ход пальца в сторону «назад», pt.
    let изменилось: (CGFloat) -> Void
    /// Отпустили: последний ход и скорость в сторону «назад», pt/с.
    let закончилось: (CGFloat, CGFloat) -> Void
    /// Жест забрала система или распознаватель сняли посреди хода.
    let отменилось: () -> Void

    func makeUIViewController(context: Context) -> Якорь {
        let якорь = Якорь()
        передать(в: якорь)
        return якорь
    }

    func updateUIViewController(_ uiViewController: Якорь, context: Context) {
        передать(в: uiViewController)
    }

    /// Вид убрали — распознаватель с хостинга тоже прочь, не дожидаясь viewWillDisappear.
    static func dismantleUIViewController(_ uiViewController: Якорь, coordinator: ()) {
        uiViewController.снять()
    }

    private func передать(в якорь: Якорь) {
        якорь.изменилось = изменилось
        якорь.закончилось = закончилось
        якорь.отменилось = отменилось
        якорь.справа = справа
        якорь.включено = включено
        /* На виду, а распознавателя нет (в viewDidAppear хостинг не нашёлся) — ещё попытка; висит — ничего. */
        якорь.повесить()
    }

    final class Якорь: UIViewController, UIGestureRecognizerDelegate {
        var изменилось: (CGFloat) -> Void = { _ in }
        var закончилось: (CGFloat, CGFloat) -> Void = { _, _ in }
        var отменилось: () -> Void = {}
        /// Арабский: край — правый, «назад» — влево.
        var справа = false {
            didSet {
                if справа != oldValue { жест?.edges = справа ? .right : .left }
            }
        }
        /// Выключен — распознаватель выключен целиком: жесты экрана у края его не ждут, начатый ход отменяется.
        var включено = true {
            didSet {
                guard включено != oldValue else { return }
                if !включено { прервать() }
                жест?.isEnabled = включено
            }
        }
        private var жест: UIScreenEdgePanGestureRecognizer?
        /// Корневой вид хостинга, на котором висит распознаватель.
        private weak var хост: UIView?
        /// Между viewDidAppear и viewWillDisappear.
        private var наВиду = false
        /// Ход начался и не закончился: снимая распознаватель посреди хода, вернуть сдвиг.
        private var идёт = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            наВиду = true
            повесить()
        }

        /// Окно поверх (мастер на весь экран) или уход экрана: жест снят, вернётся с новым появлением.
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            наВиду = false
            снять()
        }

        /// Повесить распознаватель на корневой вид хостинга — один раз: уже висит там же — ничего.
        func повесить() {
            guard наВиду, let корень = корневойВид() else { return }
            if let жест, жест.view === корень { return }
            снять()
            let новый = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(сдвинули(_:)))
            новый.edges = справа ? .right : .left
            новый.delegate = self
            новый.isEnabled = включено
            корень.addGestureRecognizer(новый)
            жест = новый
            хост = корень
        }

        func снять() {
            прервать()
            if let жест {
                жест.view?.removeGestureRecognizer(жест)
            }
            жест = nil
            хост = nil
        }

        /// Ход шёл, а жест снимают или выключают — сдвиг к нулю. Не посреди обновления SwiftUI: сюда приходят и из
        /// updateUIViewController, и из dismantle.
        private func прервать() {
            guard идёт else { return }
            идёт = false
            let отмена = отменилось
            DispatchQueue.main.async { отмена() }
        }

        /// Корневой вид своего хостинга: родитель — ближайший UIHostingController; родителя нет — вверх по видам до
        /// первого, чей next — контроллер (не сам якорь).
        private func корневойВид() -> UIView? {
            if let родитель = parent {
                return родитель.viewIfLoaded
            }
            var узел = viewIfLoaded?.superview
            while let вид = узел {
                if let контроллер = вид.next as? UIViewController, контроллер !== self {
                    return вид
                }
                узел = вид.superview
            }
            return nil
        }

        @objc(klikoEdgeSwipeBack:)
        private func сдвинули(_ жест: UIScreenEdgePanGestureRecognizer) {
            let знак: CGFloat = справа ? -1 : 1
            let ход = жест.translation(in: жест.view).x * знак
            switch жест.state {
            case .began, .changed:
                идёт = true
                изменилось(max(0, ход))
            case .ended:
                guard идёт else { return }
                идёт = false
                закончилось(max(0, ход), жест.velocity(in: жест.view).x * знак)
            case .cancelled, .failed:
                guard идёт else { return }
                идёт = false
                отменилось()
            default:
                break
            }
        }

        // MARK: Делегат распознавателя

        /// Только когда включено и палец пошёл от края в сторону «назад» — больше вбок, чем вверх-вниз.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard включено, let тяга = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            var движение = тяга.velocity(in: тяга.view)
            if движение == .zero { движение = тяга.translation(in: тяга.view) }
            let вбок = движение.x * (справа ? -1 : 1)
            return вбок > 0 && вбок > abs(движение.y)
        }

        /// Край первый: прокрутки и жесты SwiftUI внутри этого хостинга ждут, пока он откажется (палец не у края — он
        /// отказывается сразу). Касания и долгие нажатия не ждут — у края им мешать нечему; другие жесты края — тоже:
        /// два края друг друга не ждут.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === жест, let хост, let вид = otherGestureRecognizer.view,
                  !(otherGestureRecognizer is UIScreenEdgePanGestureRecognizer),
                  !(otherGestureRecognizer is UITapGestureRecognizer),
                  !(otherGestureRecognizer is UILongPressGestureRecognizer) else { return false }
            return вид.isDescendant(of: хост)
        }
    }
}
