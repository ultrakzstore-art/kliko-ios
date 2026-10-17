import SwiftUI
import UIKit

/*
 ЧАСТИ СТРАНИЦЫ ОБЪЯВЛЕНИЯ КАК НА САЙТЕ (этап 28, владелец 25.09.2026: «почти 100% похоже на сайт, только нативное
 SwiftUI»). Каждая часть — свой вид: так тело страницы остаётся коротким, и компилятор не выбирает типы часами.
 Размеры и краски — из css/marketplace.min.css (.mk-mgal, .mk-gprog, .mk-gcond, .mk-mtitle, .mk-mprice, .mk-hours,
 .mk-trustbox, .mk-mcats, .mk-btips, .mk-msub, .mk-mspec, .mk-mdesc, .mk-mmeta, .mk-msc) в разметке телефона.
 */

// MARK: - Перенос строк (flex-wrap сайта)

/// Ряд, который переносится на следующую строку, когда не помещается, — как display:flex; flex-wrap:wrap у крошек и
/// характеристик сайта.
struct ПереносСтрок: Layout {
    var промежуток: CGFloat = 8
    var междуСтрок: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var строка: CGFloat = 0
        var самая: CGFloat = 0
        for вид in subviews {
            let р = вид.sizeThatFits(ProposedViewSize(width: ширина, height: nil))
            if x > 0 && x + р.width > ширина {
                y += строка + междуСтрок
                x = 0
                строка = 0
            }
            x += р.width + промежуток
            строка = max(строка, р.height)
            самая = max(самая, x - промежуток)
        }
        return CGSize(width: proposal.width ?? самая, height: y + строка)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var строка: CGFloat = 0
        for вид in subviews {
            let р = вид.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + р.width > bounds.maxX {
                y += строка + междуСтрок
                x = bounds.minX
                строка = 0
            }
            вид.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                      proposal: ProposedViewSize(width: min(р.width, bounds.width), height: р.height))
            x += р.width + промежуток
            строка = max(строка, р.height)
        }
    }
}

// MARK: - «Смахни — назад» без системной панели

/**
 Страница объявления прячет системную панель (кнопки — над фото, как у сайта), а UIKit вместе с панелью выключает жест
 «смахнуть от края — назад». Посредник на время показа страницы становится делегатом этого жеста у своего стека и
 разрешает его, когда есть куда возвращаться; уходя, возвращает прежнего делегата — остальные экраны живут как жили.
 Глобальной подмены UINavigationController нет: она задела бы чат, кабинет и iPad.

 Владелец 14.10.2026: «у некоторых привычка слайдом назад — тоже сделать как надо». Одного делегата мало: палец у края
 забирали галерея фото (страницы TabView — горизонтальная прокрутка) и одновременные жесты страницы (смахнуть вниз,
 подтянуть к следующему). Теперь край первый: всё внутри верхнего экрана стека ждёт, пока жест края откажется (палец
 не у края или идёт вверх-вниз — отказывается сразу), — как у системной панели. Чату, карте и листу разделов это тоже
 на пользу: у них тот же посредник.
 */
struct СмахнутьНазад: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Посредник { Посредник() }
    func updateUIViewController(_ uiViewController: Посредник, context: Context) {}

    final class Посредник: UIViewController, UIGestureRecognizerDelegate {
        private weak var стек: UINavigationController?
        private weak var прежний: UIGestureRecognizerDelegate?
        private var поставлен = false

        /* Каждое появление — заново делегат и isEnabled: пока страница была под окном или листом, жест мог уйти к
           другому делегату или выключиться. */
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let найден = navigationController, let жест = найден.interactivePopGestureRecognizer else {
                return
            }
            /* Листание на месте (ListingFlip.swift): новая страница встаёт, пока прежняя ещё на экране, и делегат
               жеста — посредник прежней. Он уйдёт вместе с ней, поэтому берём не его, а то, что запомнил он сам:
               иначе, вернувшись к списку, жест остался бы без делегата и на корне стека заморозил бы экран. Делегат
               уже мы — прежний уже запомнен: иначе запомнили бы самих себя. */
            if let другой = жест.delegate as? Посредник {
                if другой !== self { прежний = другой.прежний }
            } else {
                прежний = жест.delegate
            }
            стек = найден
            жест.delegate = self
            жест.isEnabled = true
            поставлен = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            вернуть()
        }

        private func вернуть() {
            guard поставлен else { return }
            поставлен = false
            if let жест = стек?.interactivePopGestureRecognizer, жест.delegate === self {
                жест.delegate = прежний
            }
        }

        /// Корень стека смахивать некуда: жест на нём у UIKit замораживает экран. Посреди перехода (стек ещё едет) — тоже
        /// нет. И только когда палец от края идёт вбок, а не вверх-вниз: вертикальное — прокрутке и «смахнуть вниз».
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let стек, стек.viewControllers.count > 1, стек.transitionCoordinator == nil else { return false }
            guard let тяга = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            var движение = тяга.velocity(in: тяга.view)
            if движение == .zero { движение = тяга.translation(in: тяга.view) }
            return abs(движение.x) > abs(движение.y)
        }

        /// Край первый: прокрутки (галерея фото, похожие, сама страница) и жесты SwiftUI верхнего экрана стека ждут, пока
        /// жест края откажется. Касания и долгие нажатия не ждут — у края им мешать нечему.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            жестКраяИЭкрана(gestureRecognizer, otherGestureRecognizer)
        }

        /// С жестами верхнего экрана — не вместе: край забрал палец — страница под ним не листается и не едет.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        /// Жест края своего стека и другой распознаватель внутри вида верхнего экрана стека. Возвращаться некуда (корень
        /// стека, правая колонка iPad) — никто край не ждёт.
        private func жестКраяИЭкрана(_ край: UIGestureRecognizer, _ другой: UIGestureRecognizer) -> Bool {
            guard let стек, стек.viewControllers.count > 1, край === стек.interactivePopGestureRecognizer,
                  другой !== край,
                  !(другой is UIScreenEdgePanGestureRecognizer),
                  !(другой is UITapGestureRecognizer),
                  !(другой is UILongPressGestureRecognizer),
                  let экран = стек.topViewController?.viewIfLoaded, let вид = другой.view else { return false }
            return вид.isDescendant(of: экран)
        }
    }
}

// MARK: - Кнопки над фото (.mk-mhead)

/**
 Мерки кнопок над фото — одни на сердце, «Поделиться», пару стрелок ˄ ˅ и «×» (владелец 13.10.2026: «модалке кнопки»,
 «схема должна быть ровной»). Видно квадрат 36 pt (.mk-mbtn сайта), а вокруг — невидимое поле 4 pt: палец попадает в
 44 pt, соседние кнопки стоят ровно через 8 pt, а от краёв фото — через 16 pt (12 pt ряда и поле), по одной линии с
 меткой «Б/У» под ними.
 */
enum МеркиКнопокНадФото {
    /// Видимая сторона кнопки.
    static let сторона: CGFloat = 36
    /// Невидимое поле вокруг кнопки — до 44 pt под палец.
    static let поле: CGFloat = 4
    /// Сегмент пары стрелок шире квадрата: с полем по внешнему краю — те же 44 pt под палец.
    static let сегмент: CGFloat = 40
    /// Значок — 16 pt полужирный, у всех кнопок ряда.
    static let значок: CGFloat = 16
    /// Ряд кнопок от краёв фото (видимый край — ещё на поле дальше: 16 pt).
    static let отступРяда: CGFloat = 12
    /// Ряд от верха фото: видимый верх в 20 pt — на 8 pt ниже полосок-историй и на 10 pt выше метки «Б/У» (66 pt).
    static let отступСверху: CGFloat = 16
}

extension View {
    /// .mk-mhead .mk-mbtn: квадрат 36 pt со скруглением 10, rgba(14,20,17,.45) и размытие под ним, значок белый;
    /// вокруг — поле до 44 pt под палец.
    func фонКнопкиНадФото() -> some View {
        self
            .frame(width: МеркиКнопокНадФото.сторона, height: МеркиКнопокНадФото.сторона)
            .стеклоНадФото()
            .padding(МеркиКнопокНадФото.поле)
            .contentShape(Rectangle())
    }

    /// Стекло кнопок над фото без размера — одно у квадратной кнопки и у пары стрелок: тёмный 45 % с размытием,
    /// скругление 10 и тонкий блик по верхней кромке, чтобы кнопка читалась и на тёмном снимке.
    func стеклоНадФото() -> some View {
        modifier(СтеклоНадФото())
    }
}

/// Стекло кнопок над фото. Лёгкий режим (РежимУстройства: слабое железо, энергосбережение, перегрев) — без размытия
/// .ultraThinMaterial: тёмная подложка и блик те же, а размытие под каждой кнопкой — лишняя работа на каждом кадре
/// листания фото. Размытие — слоем фона, само содержимое при смене режима не пересоздаётся.
private struct СтеклоНадФото: ViewModifier {
    @ObservedObject private var режим = РежимУстройства.shared

    func body(content: Content) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
        return content
            .background(Theme.кнопкаНадФото, in: форма)
            .background {
                if !режим.лёгкий {
                    форма.fill(.ultraThinMaterial)
                }
            }
            .overlay {
                форма
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.clear],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .environment(\.colorScheme, .dark)
    }
}

/**
 Нажатие кнопок страницы объявления (над фото и в панели связи): под пальцем — короткое сжатие, отпустили — пружинка
 обратно с лёгким перелётом. «Уменьшение движения» — без движения: кнопка лишь на миг бледнеет.
 */
struct НажатиеСПружинкой: ButtonStyle {
    var сжатие: CGFloat = ДвижениеСайта.сжатиеПанели

    func makeBody(configuration: Configuration) -> some View {
        let тихо = ДвижениеСайта.тихо
        let нажата = configuration.isPressed
        return configuration.label
            .scaleEffect(нажата && !тихо ? сжатие : 1)
            .opacity(нажата && тихо ? 0.7 : 1)
            .animation(нажата || тихо ? ДвижениеСайта.нажатие : Self.отпустили, value: нажата)
    }

    /// Возврат после нажатия — пружина с небольшим перелётом.
    private static let отпустили = Animation.spring(response: 0.32, dampingFraction: 0.55)
}

struct КнопкаНадФото: View {
    let значок: String
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: МеркиКнопокНадФото.значок, weight: .semibold))
                .foregroundStyle(Color.white)
                .фонКнопкиНадФото()
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.9))
        .accessibilityLabel(подпись)
    }
}

// MARK: - Галерея (.mk-mgal на телефоне)

/**
 Фото от края до края под строкой состояния. Рамка — одна у всех объявлений: 16:10 по ширине экрана, от снимков не
 зависит (владелец 14.10.2026: «все должны быть одного вида 16 на 9», РамкаГалереиОбъявления в GalleryFocus.swift).
 Снимок заполняет рамку целиком, без полос, а кадр сдвинут к главному предмету (ФокусСнимка); целиком, в своей
 пропорции, снимок видно только на весь экран. Сверху — затемнение (.mk-mgal::before: 104 pt, но не больше 38 %
 высоты фото), полоски-истории (.mk-gprog: сами листают каждые 3,6 с) и метка состояния (.mk-gbadges) в 66 pt от
 верха фото.
 Касание левой трети — назад, правой — вперёд, середины — фото на весь экран (mkInitCardSwipe).

 Сборка 84 (владелец 17.10.2026, на макет «Окно товара — упрощение» — «Собирай 84»; ListingWindowV2.swift). Рубильник
 gallery_43: рамка 4:3, а снимок другой пропорции (видно меньше 85 %) — целиком на своей размытой копии (СлайдФото).
 Рубильник modal_summary: фото само не листается — полоски только показывают, какое фото открыто (текущая белая,
 остальные на 40 %), касания по третям листают как раньше; метки «Б/У» / «Новое» / «С пробегом» / «Аренда» на фото нет —
 состояние словом стоит в первой строке карточки решения под ценой. Значения рубильников — один раз на открытое окно:
 вид пересоздаётся при каждом проходе страницы (прокрутка, листание), поэтому modal_summary приходит снимком страницы
 (окноРешения:, тот же, по которому страница ставит карточку решения), а gallery_43 галерея держит в @State с первого
 показа; не передали — берётся из Config (ответ настроек при открытом окне не перестраивает фото).
 */
struct ГалереяСайта: View {
    let адреса: [URL]
    @Binding var страница: Int
    /// Высота строки состояния: фото уходит под неё, а полоски и метка — ниже.
    let верх: CGFloat
    let ширина: CGFloat
    let метка: Listing.МеткаСостояния?
    let аренда: Bool
    /// Истории стоят: страницу прокрутили от фото (mkStoryVis сайта).
    let пауза: Bool
    let открыть: (Int) -> Void
    /// Двойное касание фото — в избранное (mkHeartBurst сайта); nil — избранное выключено.
    let вИзбранное: (@MainActor () -> Void)?
    /// Двойное касание: растёт — сердце вспыхивает ещё раз.
    @State private var вспышка = 0
    /// Палец на фото — истории ждут (mkStoryPause на touchstart/touchend).
    @GestureState private var тянут = false
    @Environment(\.layoutDirection) private var направление
    /// Обложка из ленты — заставкой первого слайда, пока качается полное фото; nil — без заставки.
    let обложка: URL?
    /// Сборка 84, modal_summary — снимок страницы (окноРешения: в init): фото само не листается, метки состояния на фото
    /// нет. Страница не передала — Config.окноРешения при создании вида.
    private let окноРешения: Bool
    /// Сборка 84, gallery_43: рамка 4:3, снимок другой пропорции — целиком на размытой копии. @State — значение с первого
    /// показа галереи: вид пересоздаётся при каждом проходе страницы, а рамка открытого окна от ответа настроек не прыгает
    /// между 16:10 и 4:3 (_целиком в init — начальное значение, а не запись, как _кадр у СлайдФото).
    @State private var целиком: Bool

    /// Явный init: страницу создаёт другой файл, и поэлементный init не должен зависеть от закрытых свойств.
    /// окноРешения и целиком — снимки рубильников у страницы (сборка 84); nil — из Config.
    init(адреса: [URL], страница: Binding<Int>, верх: CGFloat, ширина: CGFloat, метка: Listing.МеткаСостояния?,
         аренда: Bool, пауза: Bool = false, вИзбранное: (@MainActor () -> Void)? = nil, обложка: URL? = nil,
         окноРешения: Bool? = nil, целиком: Bool? = nil, открыть: @escaping (Int) -> Void) {
        self.обложка = обложка
        self.адреса = адреса
        _страница = страница
        self.верх = верх
        self.ширина = ширина
        self.метка = метка
        self.аренда = аренда
        self.пауза = пауза
        self.вИзбранное = вИзбранное
        self.открыть = открыть
        self.окноРешения = окноРешения ?? Config.окноРешения
        _целиком = State(initialValue: целиком ?? Config.фотоЦеликом)
    }

    /// Высота фото — одна у всех объявлений (16:10 по ширине, при gallery_43 — 4:3), строка состояния — сверх неё.
    private var высотаФото: CGFloat { РамкаГалереиОбъявления.высотаФото(ширина: ширина, целиком: целиком) }

    var body: some View {
        let высота = верх + высотаФото
        return ZStack(alignment: .topLeading) {
            слайды(высота: высота)
            /* 104 pt сайта — под рамку 4:5; у 16:10 это почти половина фото до самого фокуса. Теперь 38 % высоты фото
               (390 pt ширины — около 83 pt): под полосками и рядом кнопок, у метки «Б/У» уже сходит на нет — у неё
               свой фон. */
            затемнение
                .frame(width: ширина, height: верх + min(104, высотаФото * 0.38))
                .allowsHitTesting(false)
            if адреса.count > 1 {
                ПолоскиИсторииСайта(всего: адреса.count, страница: $страница, пауза: пауза || тянут, ширина: ширина,
                                    самиЛистают: !окноРешения)
                    .padding(.top, верх + 10)
                    .allowsHitTesting(false)
            }
            /* modal_summary: метки на самом товаре нет — состояние словом в карточке решения под ценой. */
            if !окноРешения {
                метки
                    .padding(.top, верх + 66)
                    .padding(.leading, 16)
                    .allowsHitTesting(false)
            }
            if вИзбранное != nil {
                сердце
                    .frame(width: ширина, height: высота)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: ширина, height: высота, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func слайды(высота: CGFloat) -> some View {
        if адреса.isEmpty {
            /* .mk-gempty: коробка #b3c2ba на поверхности 2 галереи. */
            Theme.цвет(0xF4F8F6, 0x14141C)
                .overlay {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Color(uiColor: Theme.hex(0xB3C2BA)))
                        .padding(.top, верх)
                }
                .frame(width: ширина, height: высота)
                .accessibilityHidden(true)
        } else {
            TabView(selection: $страница) {
                ForEach(Array(адреса.enumerated()), id: \.offset) { номер, адрес in
                    СлайдФото(адрес: адрес, верх: верх, ширина: ширина, высотаФото: высотаФото,
                              превью: номер == 0 ? обложка : nil, целиком: целиком)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture(count: 2).onEnded { _ in дважды() }
                                .exclusively(before: SpatialTapGesture().onEnded { касание in
                                    коснулись(касание.location.x, номер: номер)
                                })
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(format: ListingPageText.т("photo"), номер + 1, адреса.count))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { открыть(номер) }
                        .tag(номер)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: ширина, height: высота)
            .simultaneousGesture(DragGesture(minimumDistance: 10).updating($тянут) { _, тянется, _ in тянется = true })
        }
    }

    /// Левая треть (0,28) — назад, правая — вперёд, середина — на весь экран; в RTL края меняются местами.
    private func коснулись(_ x: CGFloat, номер: Int) {
        guard адреса.count > 1, ширина > 0 else { return открыть(номер) }
        var доля = x / ширина
        if направление == .rightToLeft { доля = 1 - доля }
        if доля < 0.28 {
            withAnimation(ДвижениеСайта.слайд) { страница = max(0, страница - 1) }
        } else if доля > 0.72 {
            withAnimation(ДвижениеСайта.слайд) { страница = min(адреса.count - 1, страница + 1) }
        } else {
            открыть(номер)
        }
    }

    /// Двойное касание: в избранное (если ещё нет — решает вызывающий) и вспышка сердца.
    @MainActor private func дважды() {
        guard let добавить = вИзбранное else { return }
        добавить()
        ОткликСайта.выбор()
        if !ДвижениеСайта.тихо { вспышка += 1 }
    }

    /// .mk-heartburst: сердце 90 pt #e0245e с розовой тенью по центру фото, 0,7 с: 0,3 → 1,15 → 0,95 → 1,05 → 1,
    /// затем гаснет, вырастая до 1,1 и поднимаясь на 10 pt (mkHeart).
    private var сердце: some View {
        let краска = Color(uiColor: Theme.hex(0xE0245E))
        return Image(systemName: "heart.fill")
            .font(.system(size: 80))
            .foregroundStyle(краска)
            .shadow(color: краска.opacity(0.5), radius: 6, x: 0, y: 4)
            .frame(width: 90, height: 90)
            .keyframeAnimator(initialValue: КадрСердцаГалереи(), trigger: вспышка) { вид, кадр in
                вид
                    .scaleEffect(кадр.масштаб)
                    .offset(y: кадр.сдвиг)
                    .opacity(кадр.видно)
            } keyframes: { _ in
                KeyframeTrack(\.масштаб) {
                    LinearKeyframe(0.3, duration: 0)
                    CubicKeyframe(1.15, duration: 0.105)
                    CubicKeyframe(0.95, duration: 0.105)
                    CubicKeyframe(1.05, duration: 0.105)
                    CubicKeyframe(1, duration: 0.175)
                    LinearKeyframe(1.1, duration: 0.21)
                }
                KeyframeTrack(\.видно) {
                    LinearKeyframe(0, duration: 0)
                    LinearKeyframe(1, duration: 0.105)
                    LinearKeyframe(1, duration: 0.385)
                    LinearKeyframe(0, duration: 0.21)
                }
                KeyframeTrack(\.сдвиг) {
                    LinearKeyframe(0, duration: 0.49)
                    LinearKeyframe(-10, duration: 0.21)
                }
            }
            .accessibilityHidden(true)
    }

    private var затемнение: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 6 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.46), location: 0),
            .init(color: Color(red: 6 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.14), location: 0.58),
            .init(color: Color.clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }


    /// .mk-gcond: «Б/У» оранжевым (#b8620c), «Новое» — зелёным; «Аренда» — синим градиентом.
    private var метки: some View {
        HStack(spacing: 6) {
            if let состояние = метка {
                Text(состояние.текст)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(состояние.новое ? Theme.меткаНовое : Theme.меткаБУ,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            if аренда {
                Text(ListingPageText.т("rent"))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x2563EB)), Color(uiColor: Theme.hex(0x1D4ED8))],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        }
    }
}

/// Кадр вспышки сердца: в покое невидимо.
private struct КадрСердцаГалереи {
    var масштаб: CGFloat = 0.3
    var видно: Double = 0
    var сдвиг: CGFloat = 0
}

/// .mk-gprog.run: полоски 2,5 pt через 4 pt, белые 40 %; пройденные белые, текущая заливается за 3,6 с и листает
/// дальше по кругу (mkStoryFill). Меньше движения — листания нет, текущая сразу белая.
/// Сборка 84, modal_summary (владелец 17.10.2026: «фокус сбивается» — фото само листалось над названием и ценой): сами не
/// листают, полоски — только указатель: текущая белая, остальные на 40 %; листают касания по третям и палец.
private struct ПолоскиИсторииСайта: View {
    let всего: Int
    @Binding var страница: Int
    let пауза: Bool
    let ширина: CGFloat
    /// false — окно v2 (modal_summary): без автолистания и заливки, полоски только показывают открытое фото.
    var самиЛистают = true
    @State private var ход: CGFloat = 0
    /// Чья полоска сейчас в ходе: смена страницы показывает новую пустой с первого кадра, а не заполненной на миг.
    @State private var страницаХода = -1
    /// Сколько секунд текущей полоски прошло до последней паузы.
    @State private var прошло: Double = 0
    /// Когда пошёл текущий отрезок заливки; nil — стоит.
    @State private var пошёл: Date?

    private static let длительность: Double = 3.6

    /// Скорость (владелец 16.10.2026): заливка — одной анимацией на остаток, а не 36 перерисовками по 0,1 с; в лёгком
    /// режиме (РежимУстройства) истории не листают сами — текущая сразу белая, как при «Уменьшении движения».
    private var авто: Bool { самиЛистают && !ДвижениеСайта.тихо && !РежимУстройства.сейчас && всего > 1 }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<всего, id: \.self) { номер in
                GeometryReader { г in
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(Color.white)
                            .frame(width: г.size.width * заполнение(номер))
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 2.5)
                .background(Capsule().fill(Color.white.opacity(0.4)))
                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: ширина)
        /* Смена страницы или паузы — новый отрезок: пауза замораживает заливку там, где она есть, снятие — доливает
           остаток. Без опроса раз в 0,1 с. */
        .task(id: страница * 2 + (пауза ? 1 : 0)) { await идти() }
    }

    private func заполнение(_ номер: Int) -> CGFloat {
        /* Окно v2: указатель, а не история — белая только открытая. */
        if !самиЛистают { return номер == страница ? 1 : 0 }
        if номер < страница { return 1 }
        if номер > страница { return 0 }
        guard авто else { return 1 }
        return страницаХода == страница ? ход : 0
    }

    /// Заливка без анимации — сразу на место (новая страница с нуля, пауза — где стоит).
    private func поставить(_ доля: CGFloat) {
        var без = Transaction()
        без.disablesAnimations = true
        withTransaction(без) { ход = доля }
    }

    private func идти() async {
        if страницаХода != страница {
            страницаХода = страница
            прошло = 0
            пошёл = nil
            поставить(0)
        }
        guard авто else { return }
        if пауза {
            if let с = пошёл {
                прошло += Date().timeIntervalSince(с)
                пошёл = nil
            }
            поставить(CGFloat(min(1, прошло / Self.длительность)))
            return
        }
        let остаток = max(0, Self.длительность - прошло)
        пошёл = Date()
        withAnimation(.linear(duration: остаток)) { ход = 1 }
        try? await Task.sleep(nanoseconds: UInt64(остаток * 1_000_000_000))
        guard !Task.isCancelled else { return }
        пошёл = nil
        withAnimation(ДвижениеСайта.слайд) { страница = (страница + 1) % всего }
    }
}

/// Скорость (владелец 16.10.2026: «моментально открывал всё»): готовые к показу снимки галереи — в памяти за время
/// работы приложения. Повторное открытие, листание назад и заготовка следующего (ListingFlip.swift) рисуют кадр в
/// первом же проходе, без спиннера и без раскодирования. NSCache сам потокобезопасен и сам чистится при нехватке
/// памяти; вес — байты растра, на слабом железе предел вдвое меньше.
enum ГотовыеСнимкиГалереи {
    private static let кэш: NSCache<NSURL, UIImage> = {
        let к = NSCache<NSURL, UIImage>()
        к.totalCostLimit = (ЖелезоУстройства.слабое ? 24 : 48) * 1024 * 1024
        return к
    }()

    static func снимок(_ адрес: URL) -> UIImage? {
        кэш.object(forKey: адрес as NSURL)
    }

    static func положить(_ снимок: UIImage, _ адрес: URL) {
        let вес = снимок.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        кэш.setObject(снимок, forKey: адрес as NSURL, cost: max(1, вес))
        /* Сборка 84 (gallery_43): снимок встанет в рамку 4:3 целиком — размытую копию заранее, на своей очереди: у
           заготовки следующего объявления (ListingFlip.swift) первый кадр слайда встанет уже на ней. */
        if Config.фотоЦеликом,
           !РамкаГалереиОбъявления.заполняет(снимок: снимок.size, рамка: РамкаГалереиОбъявления.пропорция43) {
            РазмытаяКопияСнимка.заготовить(снимок, адрес: адрес)
        }
    }
}

/// Один снимок: заполняет рамку ширина × высотаФото под строкой состояния (16:10, РамкаГалереиОбъявления), без полос и
/// размытой подложки, кадр сдвинут к главному предмету (ФокусСнимка, GalleryFocus.swift). Пока снимок или фокус не
/// готовы — подложка со спиннером: кадр появляется сразу на своём месте, без прыжка из центра. Картинка своя, а не
/// AsyncImage: нужен её размер (сдвиг кадра), а URLSession.shared кладёт её в общий кэш — оттуда её берёт «Поделиться»
/// (этап 19).
/// Сборка 84, gallery_43 (владелец 17.10.2026: «фото внутри модалки — как сделать, чтобы не резал»): рамка 4:3; снимок,
/// у которого при заполнении видно меньше 85 %, стоит целиком (scaledToFit, по центру) поверх своей размытой копии
/// (РазмытаяКопияСнимка) с затемнением 10 % — белый снимок не сливается с фоном; пока копии нет — на поверхности 2.
/// Решение — по размеру уже раскодированного снимка, без GeometryReader; такому снимку Vision не зовём. Обложка ленты
/// (превью) решает по своему размеру так же. Рубильник выключен — всё как раньше.
private struct СлайдФото: View {
    let адрес: URL
    let верх: CGFloat
    let ширина: CGFloat
    let высотаФото: CGFloat
    /// Обложка из ленты (малый снимок, лента его уже качала) — заставкой, пока в пути полный; nil — без неё.
    let превью: URL?
    /// Сборка 84, gallery_43 — снимок рубильника от галереи: снимок другой пропорции — целиком на размытой копии.
    let целиком: Bool
    @State private var кадр: ГотовыйКадр?
    @State private var неудача = false
    /// Обложка ленты на месте кадра, пока полный снимок не готов: вместо спиннера — то же фото, что было в ленте.
    @State private var заставка: ГотовыйКадр?
    /// Размытая копия под снимком «целиком» (gallery_43) и чья она: кадр другого адреса её не берёт.
    @State private var размытая: РазмытыйФон?

    /// Снимок и его фокус приходят вместе: показываем только оба сразу. Адрес — чей это кадр: строка ленты без фото
    /// показывает обложку, а с полной карточкой на том же слайде встаёт другой адрес — кадр меняется, а не застревает.
    private struct ГотовыйКадр {
        let адрес: URL
        let картинка: UIImage
        let фокус: CGPoint
    }

    /// Размытая копия снимка «целиком» и адрес её снимка.
    private struct РазмытыйФон {
        let адрес: URL
        let картинка: UIImage
    }

    init(адрес: URL, верх: CGFloat, ширина: CGFloat, высотаФото: CGFloat, превью: URL? = nil, целиком: Bool = false) {
        self.адрес = адрес
        self.верх = верх
        self.ширина = ширина
        self.высотаФото = высотаФото
        self.превью = превью
        self.целиком = целиком
        /* Снимок уже раскодирован за этот запуск и точка известна — кадр в первом же проходе, без спиннера. */
        let рамка = Self.доля(CGSize(width: ширина, height: высотаФото))
        _кадр = State(initialValue: Self.готовый(адрес, целиком: целиком, рамка: рамка))
    }

    /// Кадр из памяти (ГотовыеСнимкиГалереи и точка ФокусСнимка) — только когда есть оба; иначе nil. Снимок «целиком»
    /// (gallery_43) точки не ждёт: резать нечего.
    private static func готовый(_ адрес: URL, целиком: Bool, рамка: CGFloat) -> ГотовыйКадр? {
        guard let снимок = ГотовыеСнимкиГалереи.снимок(адрес) else { return nil }
        if решитьЦеликом(снимок.size, целиком: целиком, рамка: рамка) {
            return ГотовыйКадр(адрес: адрес, картинка: снимок, фокус: ФокусСнимка.центр)
        }
        guard let фокус = ФокусСнимка.изПамяти(снимок, адрес: адрес) else { return nil }
        return ГотовыйКадр(адрес: адрес, картинка: снимок, фокус: фокус)
    }

    /// Сборка 84 (gallery_43): снимок этого размера — целиком на размытой копии (при заполнении видно меньше 85 %).
    /// Рубильник выключен — всегда false: снимок заполняет рамку, как раньше.
    private static func решитьЦеликом(_ размер: CGSize, целиком: Bool, рамка: CGFloat) -> Bool {
        целиком && !РамкаГалереиОбъявления.заполняет(снимок: размер, рамка: рамка)
    }

    /// То же для этого слайда: рамка — ширина × высотаФото.
    private func показатьЦеликом(_ размер: CGSize) -> Bool {
        let рамка = Self.доля(CGSize(width: ширина, height: высотаФото))
        return Self.решитьЦеликом(размер, целиком: целиком, рамка: рамка)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.подложкаФото
            if let готово = кадр {
                /* Рамка одна у всех снимков: вертикальный и горизонтальный выглядят одинаково, целиком — на весь экран. */
                видКадра(готово)
                    .padding(.top, верх)
                    .transition(.opacity)
            } else if неудача {
                /* .mk-imgretry: «Повторить» зелёным на поверхности 2. */
                Theme.поверхность2
                Button {
                    неудача = false
                    Task { await загрузить() }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .semibold))
                        Text(FeedText.т("retry"))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Theme.зелёный2)
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: ширина, height: высотаФото)
                .padding(.top, верх)
            } else if let заставка {
                /* Обложка ленты, пока полный снимок в пути: то же фото, что человек только что видел в ленте. */
                видКадра(заставка)
                    .padding(.top, верх)
            } else {
                SiteSpinner.белый
                    .frame(width: ширина, height: высотаФото)
                    .padding(.top, верх)
            }
        }
        .frame(width: ширина, height: верх + высотаФото, alignment: .top)
        .clipped()
        .task(id: адрес) {
            await загрузить()
            /* Сборка 84: кадр «целиком» встал из памяти — размытая копия под него (рубильник выключен — сразу выход). */
            await подложитьРазмытую()
        }
    }

    /// Снимок заполняет рамку (видСнимка) или — при gallery_43 и другой пропорции — стоит в ней целиком (видЦеликом).
    @ViewBuilder
    private func видКадра(_ готово: ГотовыйКадр) -> some View {
        if показатьЦеликом(готово.картинка.size) {
            видЦеликом(готово)
        } else {
            видСнимка(готово)
        }
    }

    /**
     Снимок заполняет рамку (как scaledToFill), а сдвинут так, чтобы фокус встал в центр, но край снимка внутрь рамки не
     зашёл (ФокусСнимка.кадр). Все размеры известны заранее — без GeometryReader. Сдвиг — слева направо и в RTL: это
     снимок, а не текст, зеркалить его нельзя.
     */
    private func видСнимка(_ готово: ГотовыйКадр) -> some View {
        let место = ФокусСнимка.кадр(снимок: готово.картинка.size, рамка: CGSize(width: ширина, height: высотаФото),
                                     фокус: готово.фокус)
        return Image(uiImage: готово.картинка)
            .resizable()
            .frame(width: место.width, height: место.height)
            .offset(x: место.minX, y: место.minY)
            .frame(width: ширина, height: высотаФото, alignment: .topLeading)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
    }

    /**
     Сборка 84 (gallery_43): снимок целиком, по центру рамки, поверх своей размытой копии. Размеры известны заранее —
     без GeometryReader; не зеркалится в RTL — это снимок, а не текст.
     */
    private func видЦеликом(_ готово: ГотовыйКадр) -> some View {
        ZStack {
            фонЦеликом(готово.адрес)
            Image(uiImage: готово.картинка)
                .resizable()
                .scaledToFit()
                .frame(width: ширина, height: высотаФото)
        }
        .frame(width: ширина, height: высотаФото)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Подложка снимка «целиком»: размытая копия на всю рамку и затемнение 10 % (белый снимок отделяется от фона); копии
    /// ещё нет — поверхность 2. Живого .blur нет: копия уже размыта и крошечная.
    @ViewBuilder
    private func фонЦеликом(_ адресКадра: URL) -> some View {
        if let копия = размытаяКопия(адресКадра) {
            Image(uiImage: копия)
                .resizable()
                .scaledToFill()
                .frame(width: ширина, height: высотаФото)
                .clipped()
                .overlay {
                    Color.black.opacity(0.1)
                }
                .transition(.opacity)
                .accessibilityHidden(true)
        } else {
            Theme.поверхность2
                .frame(width: ширина, height: высотаФото)
                .accessibilityHidden(true)
        }
    }

    /// Размытая копия для кадра этого адреса: своя (@State) или из памяти (РазмытаяКопияСнимка) — без ожидания.
    private func размытаяКопия(_ адресКадра: URL) -> UIImage? {
        if let своя = размытая, своя.адрес == адресКадра { return своя.картинка }
        return РазмытаяКопияСнимка.готовая(адресКадра)
    }

    private func загрузить() async {
        /* Прежний кадр (другого адреса) стоит, пока не готов новый: без вспышки спиннера. */
        guard кадр?.адрес != адрес else { return }
        /* Скорость: снимок уже раскодирован за этот запуск (листание назад, заготовка следующего) — сразу, без сети. */
        let рамка = Self.доля(CGSize(width: ширина, height: высотаФото))
        if let г = Self.готовый(адрес, целиком: целиком, рамка: рамка) {
            кадр = г
            неудача = false
            return
        }
        let начало = ContinuousClock.now
        let запрос = URLRequest(url: адрес, cachePolicy: .returnCacheDataElseLoad)
        /* Полный снимок качается сразу, а пока он в пути — заставка из обложки ленты. */
        async let ответ = URLSession.shared.data(for: запрос)
        if заставка == nil, кадр == nil, let превью, превью != адрес {
            await показатьЗаставку(превью)
        }
        do {
            let (данные, _) = try await ответ
            guard let снимок = UIImage(data: данные) else {
                неудача = true
                return
            }
            /* Раскодирование и фокус — разом. Фокус — до показа (обычно десятки миллисекунд, повторно — из памяти): кадр
               сразу на своём месте. Не дольше 0,3 с — первый разбор после запуска грузит модель Vision; не успел —
               центр, кадр потом не прыгает. Обложка той же пропорции уже разобрана — её точка, без Vision. Сборка 84
               (gallery_43): снимок встанет целиком — резать нечего, Vision не зовём. */
            let наРазмытом = показатьЦеликом(снимок.size)
            async let распакованный = снимок.byPreparingForDisplay()
            let фокус: CGPoint
            if наРазмытом {
                фокус = ФокусСнимка.центр
            } else if let заставка, let превью, abs(Self.доля(заставка.картинка.size) - Self.доля(снимок.size)) < 0.02,
                      let точка = ФокусСнимка.изПамяти(заставка.картинка, адрес: превью) {
                фокус = точка
                ФокусСнимка.запомнить(точка, адрес: адрес)
            } else {
                фокус = await ФокусСнимка.фокус(для: снимок, адрес: адрес, неДольше: 0.3)
            }
            let готовый = await распакованный ?? снимок
            ГотовыеСнимкиГалереи.положить(готовый, адрес)
            /* Сборка 84: размытая копия — до показа (на крошечной копии это миллисекунды): снимок и фон встают вместе. */
            let копия: UIImage?
            if наРазмытом {
                копия = await РазмытаяКопияСнимка.копия(для: готовый, адрес: адрес)
            } else {
                копия = nil
            }
            guard !Task.isCancelled else { return }
            /* Короткое проявление, без движения кадра, — только если ждали (сеть, Vision); из кэша — сразу. «Уменьшение
               движения» — тоже сразу. */
            let ждали = ContinuousClock.now - начало > .milliseconds(60)
            withAnimation(ждали ? ДвижениеСайта.мягко(.easeOut(duration: 0.18)) : nil) {
                кадр = ГотовыйКадр(адрес: адрес, картинка: готовый, фокус: фокус)
                if let копия {
                    размытая = РазмытыйФон(адрес: адрес, картинка: копия)
                }
                заставка = nil
                неудача = false
            }
        } catch {
            if !Task.isCancelled { неудача = true }
        }
    }

    /// Обложка ленты — только из кэша URLSession (.returnCacheDataDontLoad: без сети, лента её уже качала). Не вышло —
    /// молча, остаётся спиннер. Обложка, которая встанет целиком (gallery_43), — без Vision.
    private func показатьЗаставку(_ превью: URL) async {
        let запрос = URLRequest(url: превью, cachePolicy: .returnCacheDataDontLoad)
        guard let ответ = try? await URLSession.shared.data(for: запрос),
              let снимок = UIImage(data: ответ.0) else { return }
        let малая = await снимок.byPreparingForDisplay() ?? снимок
        let фокус: CGPoint
        if показатьЦеликом(малая.size) {
            фокус = ФокусСнимка.центр
        } else {
            фокус = await ФокусСнимка.фокус(для: малая, адрес: превью, неДольше: 0.15)
        }
        guard !Task.isCancelled, кадр == nil else { return }
        заставка = ГотовыйКадр(адрес: адрес, картинка: малая, фокус: фокус)
    }

    /// Сборка 84 (gallery_43): кадр «целиком» встал из памяти (листание назад, заготовка следующего), а размытой копии у
    /// слайда ещё нет — взять её из памяти или сделать вне главной нити и проявить под снимком. Рубильник выключен или
    /// снимок заполняет рамку — ничего.
    private func подложитьРазмытую() async {
        guard целиком, let готово = кадр, готово.адрес == адрес, показатьЦеликом(готово.картинка.size) else { return }
        if let своя = размытая, своя.адрес == адрес { return }
        if let изПамяти = РазмытаяКопияСнимка.готовая(адрес) {
            /* Ту же картинку тело уже берёт из памяти; держим её у себя — память может её выкинуть. */
            размытая = РазмытыйФон(адрес: адрес, картинка: изПамяти)
            return
        }
        guard let копия = await РазмытаяКопияСнимка.копия(для: готово.картинка, адрес: адрес),
              !Task.isCancelled else { return }
        withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.18))) {
            размытая = РазмытыйФон(адрес: адрес, картинка: копия)
        }
    }

    /// Ширина к высоте; пустой — 0.
    private static func доля(_ размер: CGSize) -> CGFloat {
        размер.height > 0 ? размер.width / размер.height : 0
    }
}

// MARK: - Заголовок и цена (.mk-mtitle, .mk-mprice)

/// Название 21 pt (--fs-h1, строка 1,25) и под ним тонкая черта: зелёный 45 % → 16 % → цвет линии (.mk-mtitle::after).
struct ЗаголовокСайта: View {
    let текст: String
    /// Поколение модели (gen), если его нет в названии, — серая метка .mk-gentag после названия.
    var метка: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let метка {
                ПереносСтрок(промежуток: 8, междуСтрок: 6) {
                    название
                    Text(метка)
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.22)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .padding(.top, 5)
                }
            } else {
                название
            }
            LinearGradient(stops: [
                .init(color: Theme.зелёный2.opacity(0.45), location: 0),
                .init(color: Theme.зелёный2.opacity(0.16), location: 0.26),
                .init(color: Theme.линия, location: 0.52),
                .init(color: Theme.линия.opacity(0.35), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(height: 2)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
    }

    private var название: some View {
        Text(текст)
            .font(.system(size: 21, weight: .heavy))
            .tracking(-0.21)
            .lineSpacing(1.2)
            .foregroundStyle(Theme.текст)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Цена clamp(22px, 7vw, 30px): «от» у услуг, «/сут» у аренды, красная со скидкой и зачёркнутой старой, «ТОРГ» при
/// торге. Как flex-wrap .mk-mprice: не влезло в строку — старая цена, скидка и «ТОРГ» уходят ниже, а не ужимают цену.
struct ЦенаСайта: View {
    let товар: Listing
    /// Ширина экрана — от неё размер цены (7vw сайта).
    var ширина: CGFloat = 390

    private var р: CGFloat { min(30, max(22, ширина * 0.07)) }
    private var естьДополнения: Bool {
        guard товар.ценаАренды == nil, !(товар.negotiable && (товар.price ?? 0) <= 0) else { return false }
        return (товар.скидкаПроцентов != nil && товар.oldPrice != nil) || (товар.negotiable && (товар.price ?? 0) > 0)
    }

    var body: some View {
        Group {
            if естьДополнения {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        главная
                        дополнения
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { главная }
                        HStack(alignment: .firstTextBaseline, spacing: 8) { дополнения }
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) { главная }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var главная: some View {
        if товар.ценаОт {
            Text(ListingPageText.т("price_from"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
        }
        if let день = товар.ценаАренды {
            Text(ListingCard.тенге(день))
                .font(.system(size: р, weight: .heavy))
                .tracking(-0.025 * р)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            Text(товар.единицаАренды)
                .font(.system(size: (0.62 * р).rounded(), weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
        } else if товар.negotiable && (товар.price ?? 0) <= 0 {
            /* Владелец: «Договорная» огромная — меньше числовой цены (20–22 pt), прямым шрифтом, цветом текста. */
            Text(ListingPageText.т("negotiable"))
                .font(.system(size: max(20, min(22, 0.75 * р)), weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(ListingCard.цена(товар))
                .font(.system(size: р, weight: .heavy))
                .tracking(-0.025 * р)
                .foregroundStyle(товар.скидкаПроцентов == nil ? Theme.текст : Theme.ценаСкидка)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var дополнения: some View {
        if let скидка = товар.скидкаПроцентов, let старая = товар.oldPrice {
            Text(ListingCard.тенге(старая))
                .font(.system(size: (0.62 * р).rounded(), weight: .bold))
                .strikethrough(true, color: Theme.ценаСкидка)
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
            Text(verbatim: "↓ \(скидка)%")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.скидкаТекст)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.скидкаФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
        }
        if товар.negotiable && (товар.price ?? 0) > 0 {
            Text(ListingPageText.т("torg").uppercased())
                .font(.system(size: 0.6 * р, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Theme.зелёный2)
                .lineLimit(1)
        }
    }
}

// MARK: - Режим работы (.mk-hours)

struct БлокЧасов: View {
    enum Состояние { case открыто, нетНаМесте, закрыто }

    let часы: String
    /// «РЕЖИМ РАБОТЫ» — у услуг; у товаров сайт пишет одно время.
    let подпись: String?
    let состояние: Состояние
    @Environment(\.colorScheme) private var схема

    private var краска: Color {
        switch состояние {
        case .открыто: return Theme.зелёный
        case .нетНаМесте: return Theme.оранжевый
        case .закрыто: return Theme.малиновый
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(состояние == .закрыто ? Theme.текстВторой : краска,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .shadow(color: состояние == .закрыто ? Color.clear : краска.opacity(0.45), radius: 6, x: 0, y: 4)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let надпись = подпись {
                    Text(надпись.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.текстВторой)
                }
                Text(часы)
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(краска.opacity(состояние == .закрыто ? 0.09 : 0.10),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            /* .mk-mwrap .mk-hours: рамка — линия на 70 %; в тёмной её рисует теньКарточкиСайта. */
            if схема != .dark {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия.opacity(0.7), lineWidth: 1)
            }
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Наличие (.mk-stock)

/// «В НАЛИЧИИ 12 шт»: склад в зелёном квадрате 30 pt на зелёном 10 %; три и меньше — оранжевым и «осталось мало».
struct БлокНаличияСайта: View {
    let штук: Int
    @Environment(\.colorScheme) private var схема

    private static let мало = Color(uiColor: Theme.hex(0xD97706))

    var body: some View {
        let малоОсталось = штук <= 3
        let краска = малоОсталось ? Self.мало : Theme.зелёный
        HStack(spacing: 10) {
            Image(systemName: "house")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(краска, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(ListingPageText.т("stock_in_avail").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.2)
                    .foregroundStyle(Theme.текстВторой)
                Text(String(format: ListingPageText.т("stock_pcs"), штук))
                    .font(.system(size: 14, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if малоОсталось {
                HStack(spacing: 6) {
                    Circle()
                        .fill(краска)
                        .frame(width: 7, height: 7)
                        .background(Circle().fill(краска.opacity(0.2)).frame(width: 13, height: 13))
                    Text(ListingPageText.т("stock_low"))
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(краска)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(краска.opacity(малоОсталось ? 0.11 : 0.10),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            if схема != .dark {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия.opacity(0.7), lineWidth: 1)
            }
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Подзаголовок (.mk-msub)

/// «ОПИСАНИЕ», «ПРОДАВЕЦ УТВЕРЖДАЕТ»: значок в мятном квадрате 24 pt и прописные 11 pt.
struct ПодзаголовокСайта: View {
    let значок: String
    let текст: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 24, height: 24)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .accessibilityHidden(true)
            Text(текст.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - «Продавец утверждает» (.mk-trustbox)

/// Сборка 84, modal_summary (владелец 17.10.2026: «фокус сбивается» — обрезанный крайний чип и прокрутка вбок посреди
/// вертикальной страницы тянули взгляд): пункты переносятся на следующую строку (ПереносСтрок), горизонтальной прокрутки
/// нет; шапка по-прежнему открывает лист «Безопасная покупка» (ЛистДоверия).
struct БлокДоверия: View {
    let пункты: [Listing.ПунктДоверия]
    let подробнее: () -> Void
    /// Сборка 84, modal_summary — снимок страницы (окноРешения: в init; блок пересоздаётся при каждом её проходе, и
    /// вид должен совпадать с её раскладкой): пункты с переносом строк. Не передали — Config.окноРешения.
    private let окноРешения: Bool

    /// Явный init: закрытое свойство спрятало бы поэлементный, а блок создаёт страница (SiteListing.swift).
    init(пункты: [Listing.ПунктДоверия], окноРешения: Bool? = nil, подробнее: @escaping () -> Void) {
        self.пункты = пункты
        self.подробнее = подробнее
        self.окноРешения = окноРешения ?? Config.окноРешения
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ПодзаголовокСайта(значок: "checkmark.shield", текст: ListingPageText.т("claims"))
                Spacer(minLength: 8)
                Button(action: подробнее) {
                    HStack(spacing: 2) {
                        Text(ListingPageText.т("what_gives"))
                            .font(.system(size: 11, weight: .bold))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(Theme.зелёный2)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if окноРешения {
                ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                    ForEach(пункты, id: \.self) { пункт in
                        ПунктДоверияСайта(пункт: пункт)
                    }
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
                .onTapGesture(perform: подробнее)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(пункты, id: \.self) { пункт in
                            ПунктДоверияСайта(пункт: пункт)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: подробнее)
            }
        }
    }
}

/// .mk-trustbox-i: галочка и подпись; ключевой (гарантия, доставка) — зелёный на зелёной подложке.
struct ПунктДоверияСайта: View {
    let пункт: Listing.ПунктДоверия

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: пункт.значок)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.акцент)
                .opacity(пункт.ключевой ? 1 : 0.75)
                .accessibilityHidden(true)
            Text(пункт.текст)
                .font(.system(size: 12, weight: пункт.ключевой ? Font.Weight.bold : Font.Weight.semibold))
                .tracking(0.06)
                .foregroundStyle(пункт.ключевой ? Theme.акцент : Theme.текстПункта)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(пункт.ключевой ? Theme.оттенокАкцента : Theme.фонПункта,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous)
                .strokeBorder(пункт.ключевой ? Theme.оттенокАкцента : Theme.рамкаПункта, lineWidth: 1)
        }
    }
}

/// Строка листа «Безопасная покупка» (.mk-trust-row): значок, подпись, пометка «заявлено» и пояснение.
private struct СтрокаЛистаДоверия: Hashable {
    let значок: String
    let текст: String
    var описание: String = ""
    /// .on — зелёная строка.
    var вкл = false
    /// «✓ ЗАЯВЛЕНО» — знак, который продавец заявил сам.
    var заявлено = false
}

/// Раздел листа (.mk-trust-sec и его строки).
private struct РазделЛистаДоверия: Hashable {
    let заголовок: String
    let строки: [СтрокаЛистаДоверия]
}

/**
 «Что это даёт» — openInfo сайта (.mk-trust-card): шапка со щитом «Безопасная покупка», разделы «Знаки доверия»
 (_trustBlock: заявленное продавцом с пояснениями TRUST_INFO), «Гарантия продавца — N» или «Продаётся как есть»
 (_coverageBlock) и «Доставка» (_deliveryBlock), внизу — «Понятно».
 */
struct ЛистДоверия: View {
    let товар: Listing
    @Environment(\.dismiss) private var закрыть

    /// #16a34a — зелёный строк и значков карточки сайта, одинаковый в обеих темах.
    private static let зелёный = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)

    init(товар: Listing) {
        self.товар = товар
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(разделы.enumerated()), id: \.offset) { номер, раздел in
                        заголовокРаздела(раздел.заголовок, первый: номер == 0)
                        ForEach(раздел.строки, id: \.self) { строка in
                            строкаЛиста(строка)
                        }
                    }
                }
                .padding(10)
            }
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        /* Этап 31: лист целиком на поверхности сайта — иначе в тёмной теме по краям видна системная подложка.
           TestFlight 1.10 («срезается снизу кнопка»): «Понятно» — не последней строкой прокрутки, а закреплена внизу
           над полоской «домой» (SheetPinned.swift); высота листа — текст + кнопка. */
        .листСКнопкойВнизу {
            Button { закрыть() } label: {
                Text(ListingPageText.т("ok"))
                    .font(.system(size: 16, weight: .heavy))
                    .tracking(0.16)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .shadow(color: Self.зелёный.opacity(0.45), radius: 12, x: 0, y: 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        }
    }

    // MARK: Шапка (.mk-trust-head)

    private var шапка: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 46, height: 46)
                .background(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .shadow(color: Self.зелёный.opacity(0.5), radius: 10, x: 0, y: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ListingPageText.т("info_title"))
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.285)
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(ListingPageText.т("info_sub"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ListingPageText.т("close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(LinearGradient(colors: [Self.зелёный.opacity(0.06), Color.clear], startPoint: .top, endPoint: .bottom))
        /* ::before — зелёная полоса 3 pt по верху карточки. */
        .overlay(alignment: .top) {
            LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2, Theme.зелёныйЯркий],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .accessibilityHidden(true)
        }
    }

    // MARK: Раздел и строка (.mk-trust-sec, .mk-trust-row)

    private func заголовокРаздела(_ текст: String, первый: Bool) -> some View {
        HStack(spacing: 10) {
            Text(текст.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.66)
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Theme.линия
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .padding(.top, первый ? 4 : 12)
        .padding(.bottom, 4)
    }

    private func строкаЛиста(_ строка: СтрокаЛистаДоверия) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: строка.значок)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(строка.вкл ? Self.зелёный : Theme.текстВторой)
                .frame(width: 40, height: 40)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .fill(строка.вкл
                              ? AnyShapeStyle(LinearGradient(colors: [Self.зелёный.opacity(0.18), Self.зелёный.opacity(0.3)],
                                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Theme.поверхность2))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(строка.вкл ? Self.зелёный.opacity(0.35) : Theme.линия, lineWidth: 1)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                ПереносСтрок(промежуток: 8, междуСтрок: 4) {
                    Text(строка.текст)
                        .font(.system(size: 14, weight: .bold))
                        .tracking(-0.07)
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    if строка.заявлено {
                        пометкаЗаявлено
                    }
                }
                if !строка.описание.isEmpty {
                    Text(строка.описание)
                        .font(.system(size: 13))
                        .lineSpacing(3.5)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(строка.вкл ? Self.зелёный.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(строка.вкл ? Self.зелёный.opacity(0.22) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// .mk-trust-claim: «✓ ЗАЯВЛЕНО» 10 pt белым на зелёном градиенте.
    private var пометкаЗаявлено: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .black))
                .accessibilityHidden(true)
            Text(ListingPageText.т("claimed").uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.2)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(LinearGradient(colors: [Theme.зелёныйЯркий, Theme.зелёный2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Capsule())
        .shadow(color: Self.зелёный.opacity(0.45), radius: 4, x: 0, y: 3)
        .padding(.top, 1)
    }

    // MARK: Содержимое (openInfo)

    private var разделы: [РазделЛистаДоверия] {
        var итог: [РазделЛистаДоверия] = []
        /* «Безопасная сделка» (guarantor) продавца — только пока гарант не на паузе. */
        let пауза = ПаузаГаранта.наПаузеСейчас
        let заявления = товар.заявления.filter { ключ in !(пауза && ключ == "guarantor") }
        if !заявления.isEmpty {
            let строки = заявления.map { ключ in
                СтрокаЛистаДоверия(значок: Self.значок(ключ), текст: ListingPageText.т("t_" + ключ),
                                   описание: ListingPageText.т("t_" + ключ + "_d"), вкл: true, заявлено: true)
            }
            итог.append(РазделЛистаДоверия(заголовок: ListingPageText.т("trust_title"), строки: строки))
        }
        if let гарантия = разделГарантии { итог.append(гарантия) }
        if let доставка = разделДоставки { итог.append(доставка) }
        if итог.isEmpty {
            итог.append(РазделЛистаДоверия(заголовок: ListingPageText.т("trust_title"),
                                           строки: [СтрокаЛистаДоверия(значок: "shield", текст: ListingPageText.т("trust_look"))]))
        }
        return итог
    }

    /// _coverageBlock: у товаров (не услуг, работы и жилья), если продавец не выключил гарантию.
    private var разделГарантии: РазделЛистаДоверия? {
        let к = товар.корень
        guard !товар.услуга, !["services", "jobs", "realty"].contains(к), !товар.гарантияВыключена else { return nil }
        let дни = товар.гарантияДней ?? 0
        /* Гарант на паузе — без обещаний «Безопасной сделки» (строки cov_w2, cov_a2, талон в сделке). */
        let пауза = ПаузаГаранта.наПаузеСейчас
        if дни > 0 {
            let срок = Listing.срокГарантии(дни)
            let талон = !пауза && !товар.поляВида.безГаранта && к != "transport" && !(товар.forRent && (товар.price ?? 0) <= 0)
            return РазделЛистаДоверия(
                заголовок: String(format: ListingPageText.т("cov_warr_title"), срок),
                строки: [
                    СтрокаЛистаДоверия(значок: "shield", текст: String(format: ListingPageText.т("cov_w1_l"), срок),
                                       описание: ListingPageText.т("cov_w1_d"), вкл: true),
                    СтрокаЛистаДоверия(значок: "checkmark", текст: ListingPageText.т(пауза ? "cov_w2_l_np" : "cov_w2_l"),
                                       описание: ListingPageText.т(пауза ? "cov_w2_d_np" : "cov_w2_d")),
                    СтрокаЛистаДоверия(значок: "doc.text", текст: ListingPageText.т(талон ? "cov_w3_l2" : "cov_w3_l"),
                                       описание: ListingPageText.т(талон ? "cov_w3_d2" : "cov_w3_d"))
                ])
        }
        return РазделЛистаДоверия(
            заголовок: ListingPageText.т("cov_asis_title"),
            строки: [
                СтрокаЛистаДоверия(значок: "lock.open", текст: ListingPageText.т("cov_a1_l"),
                                   описание: ListingPageText.т("cov_a1_d")),
                СтрокаЛистаДоверия(значок: "checkmark", текст: ListingPageText.т("cov_a2_l"),
                                   описание: ListingPageText.т(пауза ? "cov_a2_d_np" : "cov_a2_d"), вкл: true),
                СтрокаЛистаДоверия(значок: "shield", текст: ListingPageText.т("cov_a3_l"),
                                   описание: ListingPageText.т("cov_a3_d"))
            ])
    }

    /// _deliveryBlock: у всего, кроме жилья, транспорта, услуг и вакансий.
    private var разделДоставки: РазделЛистаДоверия? {
        guard !["realty", "transport", "services", "jobs"].contains(товар.корень) else { return nil }
        var строки: [СтрокаЛистаДоверия] = []
        if товар.доставкаБесплатно {
            строки.append(СтрокаЛистаДоверия(значок: "truck.box", текст: ListingPageText.т("ship_free"),
                                             описание: ListingPageText.т("dlv_free_d"), вкл: true))
        }
        if let дни = товар.доставкаДней {
            строки.append(СтрокаЛистаДоверия(значок: "clock", текст: String(format: ListingPageText.т("ship_days"), дни),
                                             описание: ListingPageText.т("dlv_days_d")))
        }
        if let перевозчик = товар.поляВида.перевозчик {
            строки.append(СтрокаЛистаДоверия(значок: "shippingbox", текст: ListingPageText.т("dlv_carrier_l"),
                                             описание: перевозчик))
        }
        /* Гарант на паузе — строки «Курьер и безопасная сделка» нет. */
        if !ПаузаГаранта.наПаузеСейчас {
            строки.append(СтрокаЛистаДоверия(значок: "shield", текст: ListingPageText.т("dlv_safe_l"),
                                             описание: ListingPageText.т("dlv_safe_d")))
        }
        guard !строки.isEmpty else { return nil }
        return РазделЛистаДоверия(заголовок: ListingPageText.т("dlv_title"), строки: строки)
    }

    /// Значки TRUST_INFO сайта (.i) символами SF.
    private static func значок(_ ключ: String) -> String {
        switch ключ {
        case "receipt", "tags": return "doc.plaintext"
        case "working", "vet_checked": return "checkmark"
        case "complete": return "shippingbox"
        case "vin_clean": return "car"
        case "service_book": return "book"
        case "one_owner": return "person"
        case "docs_ok", "contract", "condition_act": return "doc.text"
        case "no_liens": return "lock.open"
        case "lawyer_checked": return "scalemass"
        case "mortgage_ok": return "building.columns"
        case "vet_passport", "sterilized": return "cross.case"
        case "pedigree": return "memorychip"
        case "trained": return "pawprint"
        case "original": return "tag"
        case "measured": return "ruler"
        case "no_defects", "clean", "cleaned": return "sparkles"
        case "safety_cert": return "rosette"
        case "guarantor": return "person.2"
        case "licensed": return "briefcase"
        case "portfolio": return "star"
        case "deposit": return "wallet.pass"
        case "insured": return "umbrella"
        default: return "shield"
        }
    }
}

// MARK: - Хлебные крошки (.mk-mcats)

/// Значок корня, родитель зелёным, «›», сам раздел чёрным; под ними — линия. Нажатие — лента этого раздела.
/// Сборка 84, исправление при любом рубильнике (владелец 17.10.2026, скриншот link20: одинокий значок-сетка без слов и
/// линия под «Разбором»): не пришло ни одного названия (раздел «other» — его нет ни в дереве, ни в названиях сайта) —
/// крошек нет совсем: ни значка-плитки, ни линии.
/// Сборка 84, modal_summary: текстовая строка 22 pt «Раздел › Подраздел ›» под описанием — без значка-плитки, без своей
/// линии и без зелёного; корень, совпавший с родителем, второй раз не пишется.
struct КрошкиСайта: View {
    let раздел: String
    let названия: [String: String]
    let выбрать: (String) -> Void
    /// Сборка 84, modal_summary — снимок страницы (окноРешения: в init; крошки пересоздаются при каждом её проходе):
    /// текстовая строка вместо значка, крошек и линии. Не передали — Config.окноРешения.
    private let окноРешения: Bool

    /// Явный init: закрытое свойство спрятало бы поэлементный, а крошки создаёт страница (SiteListing.swift).
    init(раздел: String, названия: [String: String], окноРешения: Bool? = nil, выбрать: @escaping (String) -> Void) {
        self.раздел = раздел
        self.названия = названия
        self.выбрать = выбрать
        self.окноРешения = окноРешения ?? Config.окноРешения
    }

    /// Крошкам есть что показать — пришло хоть одно название (иначе вид пустой: ни значка, ни линии). Для страницы:
    /// решить, ставить ли вокруг крошек отступ или свою линию, не рисуя их.
    static func естьНазвание(раздел: String, названия: [String: String]) -> Bool {
        КрошкиСайта(раздел: раздел, названия: названия, выбрать: { _ in }).названиеЕсть
    }

    /// Пришло хоть одно название: родителя, самого раздела или его корня.
    private var названиеЕсть: Bool { родительСИменем != nil || листСИменем != nil }

    @ViewBuilder
    var body: some View {
        let родитель = родительСИменем
        let своё = листСИменем
        if родитель != nil || своё != nil {
            if окноРешения {
                строкаОкнаРешения(родитель, своё)
            } else {
                прежние(родитель, своё)
            }
        }
    }

    /// Родитель раздела и его название; названия нет — nil (крошки родителя нет).
    private var родительСИменем: (ключ: String, имя: String)? {
        guard let родитель = РазделыСайта.родитель(раздел), let имя = названия[родитель] else { return nil }
        return (родитель, имя)
    }

    /// Сам раздел и его название; страница сайта его не назвала — хотя бы корень, словами приложения; нет и его — nil.
    private var листСИменем: (ключ: String, имя: String)? {
        if let имя = названия[раздел] { return (раздел, имя) }
        return имяКорня
    }

    /// Как до сборки 84: значок корня, крошки через ПереносСтрок и линия под ними.
    private func прежние(_ родитель: (ключ: String, имя: String)?, _ своё: (ключ: String, имя: String)?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ПереносСтрок(промежуток: 8, междуСтрок: 6) {
                Image(systemName: РазделыСайта.значок(раздел))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(height: 22)
                    .accessibilityHidden(true)
                if let родитель {
                    крошка(родитель.имя, куда: родитель.ключ, лист: false)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.текстВторой.opacity(0.55))
                        .frame(height: 22)
                        .accessibilityHidden(true)
                }
                if let своё {
                    /* Страница сайта не назвала раздел — хотя бы корень, словами приложения (листСИменем). */
                    крошка(своё.имя, куда: своё.ключ, лист: true)
                }
            }
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// Окно v2: «Раздел › Подраздел ›» одной текстовой строкой 22 pt (длинные названия переносятся), без значка и линии.
    private func строкаОкнаРешения(_ родитель: (ключ: String, имя: String)?,
                                   _ своё: (ключ: String, имя: String)?) -> some View {
        ПереносСтрок(промежуток: 6, междуСтрок: 2) {
            if let родитель {
                крошкаОкнаРешения(родитель.имя, куда: родитель.ключ, лист: false)
                стрелкаОкнаРешения
            }
            if let своё, своё.ключ != родитель?.ключ {
                крошкаОкнаРешения(своё.имя, куда: своё.ключ, лист: true)
                стрелкаОкнаРешения
            }
        }
    }

    /// Корень раздела названием из текстов приложения; неизвестный корень — nil, крошки нет.
    private var имяКорня: (ключ: String, имя: String)? {
        let корень = РазделыСайта.корень(раздел)
        if let своё = ЗагрузкаКаталогаПоиска.имя(корень) { return (корень, своё) }
        let имя = ListingPageText.т("root_" + корень)
        return имя.hasPrefix("root_") ? nil : (корень, имя)
    }

    private func крошка(_ текст: String, куда: String, лист: Bool) -> some View {
        Button { выбрать(куда) } label: {
            Text(текст)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(лист ? Theme.текст : Theme.акцент)
                .lineLimit(1)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Крошка окна v2: родитель — вторым цветом, сам раздел — цветом текста; без зелёного.
    private func крошкаОкнаРешения(_ текст: String, куда: String, лист: Bool) -> some View {
        let вес: Font.Weight = лист ? Font.Weight.semibold : Font.Weight.medium
        let краска: Color = лист ? Theme.текст : Theme.текстВторой
        return Button { выбрать(куда) } label: {
            Text(текст)
                .font(.system(size: 13, weight: вес))
                .foregroundStyle(краска)
                .lineLimit(1)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var стрелкаОкнаРешения: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.текстВторой.opacity(0.55))
            .frame(height: 22)
            .accessibilityHidden(true)
    }
}

// MARK: - Совет «… — на что смотреть» (.mk-btips)

struct СписокСовета: View {
    let ключ: String

    /// Советы, которые обещают «Безопасную сделку»: на паузе гаранта их нет.
    private static let проСделку: Set<String> = ["auto_4", "tech_4", "realty_4", "rent_4", "service_3"]

    private var номера: [Int] {
        let пауза = ПаузаГаранта.наПаузеСейчас
        let поСделке = (1...4).filter { номер in !(пауза && Self.проСделку.contains("\(ключ)_\(номер)")) }
        /* Сборка 84, исправление при любом рубильнике (разбор окна 17.10.2026, «Найденные ошибки» плана): без пунктов,
           что зовут к кнопкам «Проверить авто» и «Проверка устройства», пока самих проверок по базам РК на странице нет
           (ПунктыСоветаОбъявления, SiteListingKinds.swift) — текст обещал кнопку, которой нет ни в одном окне. Так же и
           в «Разборе» (ListingBriefSheet). Вернутся сами, когда проверки включат (проверкиРКВключены). */
        return ПунктыСоветаОбъявления.номера(ключ, из: поСделке)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(номера, id: \.self) { номер in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    Text(ListingPageText.т("tip_\(ключ)_\(номер)"))
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Плашка совета: зелёная черта слева, лампочка, «×» и «Понятно» — оба прячут совет этого вида насовсем (как
/// localStorage ulx_btips_<вид> у сайта).
/// Сборка 84, modal_summary (владелец 17.10.2026: «фокус сбивается» — совет на 230–290 pt выталкивал описание за сгиб):
/// одна строка 44 pt в виде карточки (поверхность 2, рамка-линия): лампочка, «… — на что смотреть» и шеврон. Касание
/// раскрывает пункты на месте, под ними — «Скрыть» (то же замыкание: совет этого вида прячется насовсем). «Понятно» нет.
struct БлокСовета: View {
    let ключ: String
    let скрыть: () -> Void
    /// Сборка 84, modal_summary — снимок страницы (окноРешения: в init; совет пересоздаётся при каждом её проходе):
    /// свёрнутый вид. Не передали — Config.окноРешения.
    private let окноРешения: Bool
    /// Окно v2: пункты совета раскрыты (касание по строке).
    @State private var раскрыт = false

    /// Явный init: закрытые свойства спрятали бы поэлементный, а совет создаёт страница (SiteListing.swift).
    init(ключ: String, окноРешения: Bool? = nil, скрыть: @escaping () -> Void) {
        self.ключ = ключ
        self.скрыть = скрыть
        self.окноРешения = окноРешения ?? Config.окноРешения
    }

    @ViewBuilder
    var body: some View {
        if окноРешения {
            свёрнутый
        } else {
            прежний
        }
    }

    /// Окно v2: строка 44 pt, по касанию — пункты и «Скрыть» на месте.
    private var свёрнутый: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(ДвижениеСайта.смена) { раскрыт.toggle() }
            } label: {
                строкаСвёрнутого
            }
            .buttonStyle(.plain)
            .accessibilityHint(ЧастиСтраницыText.т(раскрыт ? "slp_tips_close" : "slp_tips_open"))
            if раскрыт {
                VStack(alignment: .leading, spacing: 2) {
                    СписокСовета(ключ: ключ)
                        .padding(.top, 2)
                    Button(action: скрыть) {
                        Text(ЧастиСтраницыText.т("slp_hide"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }
        }
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// Лампочка, «… — на что смотреть» и шеврон вниз (раскрыт — вверх); вся строка — под палец, не ниже 44 pt.
    private var строкаСвёрнутого: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(ListingPageText.т("tip_" + ключ))
                .font(.system(size: 14, weight: .heavy))
                .tracking(-0.14)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .rotationEffect(.degrees(раскрыт ? 180 : 0))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    /// Как до сборки 84: плашка с чертой слева, «×» и «Понятно».
    private var прежний: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(ListingPageText.т("tip_" + ключ))
                    .font(.system(size: 14, weight: .heavy))
                    .tracking(-0.14)
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: скрыть) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ListingPageText.т("close"))
            }
            СписокСовета(ключ: ключ)
            Button(action: скрыть) {
                Text(ListingPageText.т("ok"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.leading, 19)
        .padding(.trailing, 16)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        /* border-left 3px: полоса, обрезанная скруглением плашки, — идёт по дуге углов, а не торчит. */
        .overlay(alignment: .leading) {
            Theme.зелёный2
                .frame(width: 3)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

// MARK: - Описание и характеристики (.mk-about-h, .mk-mspec, .mk-mdesc, .mk-mmeta)

struct БлокОписанияСайта: View {
    let характеристики: [Listing.Характеристика]
    let описание: String?
    let добавлено: String?
    let просмотры: Int?

    /// Промежутки сайта: подзаголовок → 8 → характеристики → 14 → текст (margin-bottom 20 + gap 14) → «Добавлено».
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ПодзаголовокСайта(значок: "info.circle", текст: ListingPageText.т("desc"))
            if !характеристики.isEmpty {
                ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                    ForEach(характеристики, id: \.self) { х in
                        Text(х.ключ + ": " + х.значение)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(minHeight: 32)
                            .background(Theme.поверхность2, in: Capsule())
                    }
                }
                .padding(.top, 8)
            }
            if let текст = описание {
                ТекстОписанияСайта(текст: текст)
                    .padding(.top, характеристики.isEmpty ? 8 : 14)
            }
            if добавлено != nil || (просмотры ?? 0) > 0 {
                СтрокаДобавленоСайта(добавлено: добавлено, просмотры: просмотры)
                    .padding(.top, описание != nil ? 34 : 14)
            }
        }
    }
}

/// .mk-mwrap .mk-mdesc: 14 pt, строка 1,6 (22,4 pt).
struct ТекстОписанияСайта: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14))
            .lineSpacing(5.7)
            .foregroundStyle(Theme.текст)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// .mk-mmeta: «Добавлено …» и просмотры, 12 pt бледным, через 16 pt.
struct СтрокаДобавленоСайта: View {
    let добавлено: String?
    let просмотры: Int?

    var body: some View {
        HStack(spacing: 16) {
            if let когда = добавлено {
                Label(String(format: ListingPageText.т("added"), когда), systemImage: "clock")
            }
            if let п = просмотры, п > 0 {
                Label(String(п), systemImage: "eye")
                    .accessibilityLabel(String(format: ListingPageText.т("views"), п))
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.текстВторой)
        .labelStyle(МеткаСайта())
    }
}

/// Значок и текст через 6 pt, значок чуть бледнее — как span svg в .mk-mmeta.
struct МеткаСайта: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .opacity(0.85)
            configuration.title
        }
    }
}

// MARK: - Продавец (.mk-msc)

struct КарточкаПродавцаСайта: View {
    let товар: Listing
    /// Этап 36: число подписчиков для строки «сделки · подписчики · с какого года» (mkSellerFolHtml сайта) — свежее из
    /// subs.php или seller_followers объявления. nil — строки о подписчиках нет, как до этапа 36.
    var подписчики: Int? = nil
    /// Этап 37: карточка нажимается (отзывы о продавце) — справа стрелка, как .mk-msc-prof сайта.
    var стрелка: Bool = false
    /// Продавец — магазин (MK_SHOPS): в строке статистики плашка «Магазин», как .mk-mshopbadge.
    var магазин: Bool = false
    /// Сборка 84, modal_summary (владелец 17.10.2026, макет «Окно товара — упрощение»: «Карточка плоская: поверхность2 и
    /// рамка вместо тени»): карточка без тени, на поверхности 2. false — как до сборки 84. Окно v2 ставит своим снимком
    /// рубильника — этим параметром или окружением карточкаПродавцаПлоская (оно доходит и через БлокПродавца и
    /// ПродавецСПодпиской).
    var плоская: Bool = false

    private var буква: String {
        String((товар.продавец ?? "?").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            аватар
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(товар.продавец ?? FeedText.т("seller"))
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(-0.14)
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if товар.продавецПроверен {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.проверен)
                            Text(ListingPageText.т("verified"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.текст)
                                .lineLimit(1)
                        }
                        .layoutPriority(-1)
                    }
                }
                рейтинг
                if магазин || статистика != nil {
                    HStack(spacing: 8) {
                        if магазин {
                            плашкаМагазина
                        }
                        if let строка = статистика {
                            Text(строка)
                                .font(.system(size: 12))
                                .lineSpacing(3.7)
                                .foregroundStyle(Theme.текстВторой)
                                .lineLimit(2)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if стрелка {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .padding(14)
        .modifier(ФонКарточкиПродавца(плоская: плоская))
        .accessibilityElement(children: .combine)
    }

    /// .mk-msc-av: квадрат 52 pt со скруглением 14, зелёный градиент и первая буква имени; есть фото — фото.
    private var аватар: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
            .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .overlay {
                Text(буква)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
            .overlay {
                if let адрес = товар.аватарПродавца.flatMap({ Config.url($0) }) {
                    /* КартинкаЛенты, а не AsyncImage: из памяти — в первом кадре, уменьшенной и раскодированной вне
                       главной нити. */
                    КартинкаЛенты(адрес, пунктов: 52) {
                        Color.clear
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }

    /// .mk-mshopbadge: витрина 13 pt и «Магазин» 11 pt на мятном, скругление 10.
    private var плашкаМагазина: some View {
        HStack(spacing: 4) {
            Image(systemName: "storefront")
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(ListingPageText.т("shop"))
                .font(.system(size: 11, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.зелёный)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .fixedSize()
    }

    /// Пять звёзд ★ 14 pt (.mk-stars5), «5.0» и «· 5 отзывов»; оценки нет — «Новый продавец».
    @ViewBuilder
    private var рейтинг: some View {
        if let оценка = товар.рейтингПродавца {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { номер in
                        ЗвездаПродавцаСайта(заливка: Self.заливкаЗвезды(номер, оценка))
                    }
                }
                .accessibilityHidden(true)
                Text(String(format: "%.1f", оценка))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if let отзывы = товар.отзывыПродавца {
                    Text("· " + ListingPageText.число(отзывы, "reviews"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
        } else {
            Text(ListingPageText.т("new_seller"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// Правило .mk-stars5: до целой части — полные; следующая — полная от ,75, половина от ,25.
    private static func заливкаЗвезды(_ номер: Int, _ оценка: Double) -> ЗвездаПродавцаСайта.Заливка {
        let целых = Int(оценка.rounded(.down))
        let доля = оценка - Double(целых)
        if номер <= целых { return .полная }
        if номер == целых + 1 {
            if доля >= 0.75 { return .полная }
            if доля >= 0.25 { return .половина }
        }
        return .пустая
    }

    /// «7 сделок · 12 подписчиков · с 2026 г.» — порядок сайта, числа жирным тёмным (<b> в .mk-msc-st); подписчиков
    /// ноль — не пишем, как сайт.
    private var статистика: AttributedString? {
        var части: [AttributedString] = []
        if let с = товар.сделкиПродавца { части.append(Self.сЧислом(ListingPageText.число(с, "deals"), с)) }
        if let число = подписчики, число > 0 { части.append(Self.сЧислом(SubsText.подписчики(число), число)) }
        if let год = товар.продавецС { части.append(AttributedString(String(format: ListingPageText.т("since"), год))) }
        guard var итог = части.first else { return nil }
        for часть in части.dropFirst() {
            итог.append(AttributedString(" · "))
            итог.append(часть)
        }
        return итог
    }

    private static func сЧислом(_ строка: String, _ число: Int) -> AttributedString {
        var текст = AttributedString(строка)
        if let где = текст.range(of: String(число)) {
            текст[где].font = Font.system(size: 12, weight: .bold)
            текст[где].foregroundColor = Theme.текст
        }
        return текст
    }
}

/// Звезда ★ 14 pt: полная — золото темы, пустая — линия, половина — левая половина #e0a013 (.mk-st.half).
private struct ЗвездаПродавцаСайта: View {
    enum Заливка { case полная, половина, пустая }
    let заливка: Заливка

    var body: some View {
        Text(verbatim: "★")
            .font(.system(size: 14))
            .foregroundStyle(заливка == .полная ? Theme.звезда : Theme.линия)
            .overlay {
                if заливка == .половина {
                    GeometryReader { г in
                        Text(verbatim: "★")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(uiColor: Theme.hex(0xE0A013)))
                            .frame(width: г.size.width, height: г.size.height)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: г.size.width / 2)
                            }
                    }
                }
            }
    }
}

/// Фон карточки продавца. Как до сборки 84 — поверхность, рамка-линия и тень карточки сайта; окно v2 (modal_summary,
/// владелец 17.10.2026: «Карточка плоская: поверхность2 и рамка вместо тени») — поверхность 2 и та же рамка, без тени.
/// Плоская — по параметру карточки или по окружению карточкаПродавцаПлоская.
private struct ФонКарточкиПродавца: ViewModifier {
    let плоская: Bool
    @Environment(\.карточкаПродавцаПлоская) private var плоскаяОкружением

    /// Явный init: закрытое свойство окружения спрятало бы поэлементный.
    init(плоская: Bool) {
        self.плоская = плоская
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        if плоская || плоскаяОкружением {
            content
                .background(Theme.поверхность2, in: форма)
                .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        } else {
            content
                .background(Theme.поверхность, in: форма)
                .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
                .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        }
    }
}

private struct КлючКарточкаПродавцаПлоская: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    /// Сборка 84, modal_summary: карточки продавца внутри — плоские (поверхность 2 и рамка, без тени). Ставит окно v2
    /// своим снимком рубильника на весь блок продавца — так доходит до карточки и через БлокПродавца (SellerViews.swift),
    /// и через ПродавецСПодпиской (SubsViews.swift). По умолчанию false — карточка как до сборки 84.
    var карточкаПродавцаПлоская: Bool {
        get { self[КлючКарточкаПродавцаПлоская.self] }
        set { self[КлючКарточкаПродавцаПлоская.self] = newValue }
    }
}
