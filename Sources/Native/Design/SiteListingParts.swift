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
 */
struct СмахнутьНазад: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Посредник { Посредник() }
    func updateUIViewController(_ uiViewController: Посредник, context: Context) {}

    final class Посредник: UIViewController, UIGestureRecognizerDelegate {
        private weak var стек: UINavigationController?
        private weak var прежний: UIGestureRecognizerDelegate?
        private var поставлен = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !поставлен, let найден = navigationController, let жест = найден.interactivePopGestureRecognizer else {
                return
            }
            стек = найден
            прежний = жест.delegate
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

        /// Корень стека смахивать некуда: жест на нём у UIKit замораживает экран.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (стек?.viewControllers.count ?? 0) > 1
        }
    }
}

// MARK: - Кнопки над фото (.mk-mhead)

extension View {
    /// .mk-mhead .mk-mbtn: квадрат 36 pt со скруглением 10, rgba(14,20,17,.45) и размытие под ним, значок белый.
    func фонКнопкиНадФото() -> some View {
        self
            .frame(width: 36, height: 36)
            .background(Theme.кнопкаНадФото, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(4)
            .contentShape(Rectangle())
    }
}

struct КнопкаНадФото: View {
    let значок: String
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .фонКнопкиНадФото()
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }
}

// MARK: - Галерея (.mk-mgal на телефоне)

/**
 Фото от края до края под строкой состояния. Сайт показывает снимок целиком (object-fit: contain, прижат к верху) на
 тёмной подложке #0d1512 (.mk-gslide) — здесь так же. Высота — по пропорции первого снимка, но не выше 4:5, как
 _mkGalFrame сайта; до загрузки — 4:5 (aspect-ratio .mk-mgal). Сверху — затемнение 104 pt (.mk-mgal::before),
 полоски-истории (.mk-gprog: сами листают каждые 3,6 с) и метка состояния (.mk-gbadges) в 66 pt от верха фото.
 Касание левой трети — назад, правой — вперёд, середины — фото на весь экран (mkInitCardSwipe).
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
    /// До загрузки первого снимка — 4:5, как aspect-ratio .mk-mgal сайта.
    @State private var пропорция: CGFloat = 0.8
    /// Палец на фото — истории ждут (mkStoryPause на touchstart/touchend).
    @GestureState private var тянут = false
    @Environment(\.layoutDirection) private var направление

    /// Явный init: страницу создаёт другой файл, и поэлементный init не должен зависеть от закрытых свойств.
    init(адреса: [URL], страница: Binding<Int>, верх: CGFloat, ширина: CGFloat, метка: Listing.МеткаСостояния?,
         аренда: Bool, пауза: Bool = false, вИзбранное: (@MainActor () -> Void)? = nil, открыть: @escaping (Int) -> Void) {
        self.адреса = адреса
        _страница = страница
        self.верх = верх
        self.ширина = ширина
        self.метка = метка
        self.аренда = аренда
        self.пауза = пауза
        self.вИзбранное = вИзбранное
        self.открыть = открыть
    }

    var body: some View {
        let высотаФото = ширина / max(0.8, пропорция)
        let высота = верх + высотаФото
        return ZStack(alignment: .topLeading) {
            слайды(высота: высота)
            затемнение
                .frame(width: ширина, height: верх + 104)
                .allowsHitTesting(false)
            if адреса.count > 1 {
                ПолоскиИсторииСайта(всего: адреса.count, страница: $страница, пауза: пауза || тянут, ширина: ширина)
                    .padding(.top, верх + 10)
                    .allowsHitTesting(false)
            }
            метки
                .padding(.top, верх + 66)
                .padding(.leading, 16)
                .allowsHitTesting(false)
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
                    СлайдФото(адрес: адрес, верх: верх, ширина: ширина, высота: высота) { размер in
                        guard номер == 0, размер.height > 0 else { return }
                        пропорция = размер.width / размер.height
                    }
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
private struct ПолоскиИсторииСайта: View {
    let всего: Int
    @Binding var страница: Int
    let пауза: Bool
    let ширина: CGFloat
    @State private var ход: CGFloat = 0
    /// Пауза в хранилище состояния: задача читает её живой, а не копию на момент запуска.
    @State private var стоп = false

    private static let длительность: Double = 3.6
    private static let шаг: Double = 0.1

    private var авто: Bool { !ДвижениеСайта.тихо && всего > 1 }

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
        .onChange(of: пауза, initial: true) { _, стало in стоп = стало }
        .task(id: страница) { await идти() }
    }

    private func заполнение(_ номер: Int) -> CGFloat {
        if номер < страница { return 1 }
        if номер > страница { return 0 }
        return авто ? ход : 1
    }

    private func идти() async {
        ход = 0
        guard авто else { return }
        var прошло: Double = 0
        while прошло < Self.длительность {
            try? await Task.sleep(nanoseconds: UInt64(Self.шаг * 1_000_000_000))
            if Task.isCancelled { return }
            if стоп { continue }
            прошло += Self.шаг
            withAnimation(.linear(duration: Self.шаг)) { ход = CGFloat(min(1, прошло / Self.длительность)) }
        }
        guard !Task.isCancelled else { return }
        withAnimation(ДвижениеСайта.слайд) { страница = (страница + 1) % всего }
    }
}

/// Один снимок: целиком по ширине, прижат к верху, на тёмной подложке .mk-gslide. Картинка своя, а не AsyncImage:
/// нужен её размер (пропорция галереи), а URLSession.shared кладёт её в общий кэш — оттуда её берёт «Поделиться» (этап 19).
private struct СлайдФото: View {
    let адрес: URL
    let верх: CGFloat
    let ширина: CGFloat
    let высота: CGFloat
    let размер: (CGSize) -> Void
    @State private var картинка: UIImage? = nil
    @State private var неудача = false

    init(адрес: URL, верх: CGFloat, ширина: CGFloat, высота: CGFloat, размер: @escaping (CGSize) -> Void) {
        self.адрес = адрес
        self.верх = верх
        self.ширина = ширина
        self.высота = высота
        self.размер = размер
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.подложкаФото
            if let снимок = картинка {
                Image(uiImage: снимок)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ширина, height: max(1, высота - верх), alignment: .top)
                    .padding(.top, верх)
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
                .frame(maxHeight: .infinity)
            } else {
                SiteSpinner.белый
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: ширина, height: высота)
        .clipped()
        .task(id: адрес) { await загрузить() }
    }

    private func загрузить() async {
        guard картинка == nil else { return }
        var запрос = URLRequest(url: адрес)
        запрос.cachePolicy = .returnCacheDataElseLoad
        do {
            let (данные, _) = try await URLSession.shared.data(for: запрос)
            guard let снимок = UIImage(data: данные) else {
                неудача = true
                return
            }
            let готовый = await снимок.byPreparingForDisplay() ?? снимок
            guard !Task.isCancelled else { return }
            картинка = готовый
            неудача = false
            размер(готовый.size)
        } catch {
            if !Task.isCancelled { неудача = true }
        }
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
            Text(ListingPageText.т("negotiable"))
                .font(.system(size: 0.9 * р, weight: .heavy))
                .italic()
                .foregroundStyle(Theme.зелёный2)
                .lineLimit(1)
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

struct БлокДоверия: View {
    let пункты: [Listing.ПунктДоверия]
    let подробнее: () -> Void

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
struct КрошкиСайта: View {
    let раздел: String
    let названия: [String: String]
    let выбрать: (String) -> Void

    var body: some View {
        let родитель = РазделыСайта.родитель(раздел)
        let имяРаздела = названия[раздел]
        return VStack(alignment: .leading, spacing: 12) {
            ПереносСтрок(промежуток: 8, междуСтрок: 6) {
                Image(systemName: РазделыСайта.значок(раздел))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(height: 22)
                    .accessibilityHidden(true)
                if let родитель, let имя = названия[родитель] {
                    крошка(имя, куда: родитель, лист: false)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.текстВторой.opacity(0.55))
                        .frame(height: 22)
                        .accessibilityHidden(true)
                }
                if let имяРаздела {
                    крошка(имяРаздела, куда: раздел, лист: true)
                } else if let корень = имяКорня {
                    /* Страница сайта не назвала раздел — хотя бы корень, словами приложения. */
                    крошка(корень.имя, куда: корень.ключ, лист: true)
                }
            }
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
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
}

// MARK: - Совет «… — на что смотреть» (.mk-btips)

struct СписокСовета: View {
    let ключ: String

    /// Советы, которые обещают «Безопасную сделку»: на паузе гаранта их нет.
    private static let проСделку: Set<String> = ["auto_4", "tech_4", "realty_4", "rent_4", "service_3"]

    private var номера: [Int] {
        let пауза = ПаузаГаранта.наПаузеСейчас
        return (1...4).filter { номер in !(пауза && Self.проСделку.contains("\(ключ)_\(номер)")) }
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
struct БлокСовета: View {
    let ключ: String
    let скрыть: () -> Void

    var body: some View {
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
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
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
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
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
