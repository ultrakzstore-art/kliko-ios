import SwiftUI

/**
 СМАХНУТЬ СТРАНИЦУ ОБЪЯВЛЕНИЯ ВНИЗ — ЗАКРЫТЬ (владелец 26.09.2026, TestFlight: у страницы «×» сверху, как у листа, и её
 хочется смахнуть вниз, как лист iOS).

 Страница лежит в стеке (push), поэтому системного смахивания листа у неё нет — жест свой. Он начинается, только когда
 страница прокручена до самого верха и палец идёт в основном вниз, — в том числе с фото наверху: листание фото вбок
 и прокрутка текста остаются прежними, а у фото на весь экран своё смахивание (ФотоНаВесьЭкран). Страница едет за
 пальцем вместе с нижней панелью, скругляется и чуть уменьшается; отпустили дальше порога или бросили — закрывается
 (свою дорогу вниз она уже проехала, поэтому стек уходит без второй анимации), иначе возвращается на место.

 Где верх, говорит сама страница: ВерхСтраницыОбъявления — положение фото в прокрутке (0 — у самого верха, меньше —
 прокручено, больше — прокрутку тянут за край). Корень правой колонки iPad (не в стеке) жест не получает.
 */
struct ВерхСтраницыОбъявления: PreferenceKey {
    static let defaultValue: CGFloat = -1_000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Имя прокрутки страницы — в ней страница меряет своё фото.
enum ПрокруткаСтраницыОбъявления {
    static let имя = "страницаОбъявления"
}

struct ЗакрытьСмахиваниемВниз: ViewModifier {
    @Environment(\.dismiss) private var закрыть
    @Environment(\.isPresented) private var вСтеке
    /// Положение фото в прокрутке (ВерхСтраницыОбъявления).
    @State private var верх: CGFloat = -1_000
    /// Насколько палец ушёл вниз с начала смахивания.
    @State private var ход: CGFloat = 0
    /// nil — жест ещё не решён; true — смахиваем; false — это прокрутка или листание, не мешаем.
    @State private var смахивание: Bool?
    /// Высота строки состояния: фото уходит под неё, и скругление должно начинаться с него, а не ниже часов.
    @State private var подЧасами: CGFloat = 0

    /// Сдвиг страницы: палец минус то, что уже дала сама прокрутка, потянутая за край, — фото идёт ровно за пальцем.
    private var сдвиг: CGFloat { max(0, ход - max(0, верх)) }
    private var доля: CGFloat { min(сдвиг / 400, 1) }

    func body(content: Content) -> some View {
        content
            .clipShape(КрайСтраницы(радиус: сдвиг > 1 ? 28 : 0, сверху: подЧасами))
            .scaleEffect(1 - доля * 0.08, anchor: .top)
            .offset(y: сдвиг)
            .background {
                Color.black
                    .opacity(сдвиг > 0 ? 0.45 * (1 - доля) : 0)
                    .ignoresSafeArea()
            }
            .background {
                GeometryReader { г in
                    Color.clear
                        .onAppear { подЧасами = г.safeAreaInsets.top }
                        .onChange(of: г.safeAreaInsets.top) { _, стало in подЧасами = стало }
                }
            }
            .onPreferenceChange(ВерхСтраницыОбъявления.self) { значение in верх = значение }
            .simultaneousGesture(смахнуть, including: вСтеке ? .all : .subviews)
    }

    private var смахнуть: some Gesture {
        /* Глобальные координаты: страница сама едет за пальцем, в своих координатах ход бы плыл. */
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .onChanged { касание in
                let вниз = касание.translation.height
                if смахивание == nil {
                    let вбок = abs(касание.translation.width)
                    смахивание = верх >= -2 && верх > -1_000 && вниз > 0 && вниз > вбок * 1.4
                }
                if смахивание == true {
                    ход = max(0, вниз)
                }
            }
            .onEnded { касание in
                defer { смахивание = nil }
                guard смахивание == true else { return }
                let бросок = касание.predictedEndTranslation.height - касание.translation.height
                if сдвиг > 130 || (сдвиг > 20 && бросок > 280) {
                    withAnimation(.easeIn(duration: 0.2)) { ход += 1_200 }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 190_000_000)
                        var без = Transaction()
                        без.disablesAnimations = true
                        withTransaction(без) { закрыть() }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { ход = 0 }
                }
            }
    }
}

/// Прямоугольник страницы, продлённый вверх под часы, со скруглёнными углами, пока её тянут. Без скругления — с большим
/// запасом со всех сторон, чтобы ничего не резать (фото под часами, тени, панель).
private struct КрайСтраницы: Shape {
    var радиус: CGFloat
    let сверху: CGFloat

    var animatableData: CGFloat {
        get { радиус }
        set { радиус = newValue }
    }

    func path(in rect: CGRect) -> Path {
        if радиус < 0.5 {
            return Path(rect.insetBy(dx: -2_000, dy: -2_000))
        }
        let рамка = CGRect(x: rect.minX, y: rect.minY - сверху, width: rect.width, height: rect.height + сверху + 200)
        return Path(roundedRect: рамка, cornerRadius: радиус, style: .continuous)
    }
}
