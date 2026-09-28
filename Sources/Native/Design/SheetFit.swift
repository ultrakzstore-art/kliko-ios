import SwiftUI
import UIKit

/**
 ЛИСТ ПО ВЫСОТЕ СОДЕРЖИМОГО — как нижний лист сайта (.mk-offer-sheet, .hp-ov): высота по тому, что внутри, а не на весь
 экран с пустотой снизу (владелец, TestFlight 1.10: «навверху вместо ровного отображения»).

 Содержимое внутри ScrollView помечается .мерилоЛиста() — фон с GeometryReader отдаёт свою высоту через
 ВысотаЛистаКлюч (PreferenceKey — onGeometryChange есть только с iOS 18). Корень листа получает .листПоВысоте():
 он ловит высоту, прибавляет нижний отступ безопасной зоны (полоску «домой» лист оставляет за собой) и ставит
 .presentationDetents([.height(h)]). Пока высоты нет — .large, чтобы первый кадр не был крошечным. Не влезает на экран —
 система сама ограничит высоту, а ScrollView даст долистать. Полоска сверху и скругление листа остаются.
 */
struct ВысотаЛистаКлюч: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Сумма высот закреплённых частей листа вне прокрутки (шапка сверху, панель снизу) — .частьЛистаВнеПрокрутки().
struct ВысотаЧастейЛистаКлюч: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

extension View {
    /// Шапка или нижняя панель листа вне ScrollView: её высота прибавляется к высоте содержимого.
    func частьЛистаВнеПрокрутки() -> some View {
        background(
            GeometryReader { гео in
                Color.clear.preference(key: ВысотаЧастейЛистаКлюч.self, value: гео.size.height)
            }
        )
    }

    /// Метка содержимого листа: его высота уходит в ВысотаЛистаКлюч.
    func мерилоЛиста() -> some View {
        background(
            GeometryReader { гео in
                Color.clear.preference(key: ВысотаЛистаКлюч.self, value: гео.size.height)
            }
        )
    }

    /// Лист высотой по содержимому, помеченному .мерилоЛиста(); с полоской сверху.
    func листПоВысоте() -> some View {
        modifier(ЛистПоВысоте())
    }

    /// То же; полоска: false — для окна, которое смахнуть нельзя (interactiveDismissDisabled).
    func листПоВысоте(полоска: Bool) -> some View {
        modifier(ЛистПоВысоте(полоска: полоска))
    }
}

struct ЛистПоВысоте: ViewModifier {
    /// Полоска-хваталка сверху листа.
    let полоска: Bool
    @State private var высота: CGFloat = 0
    @State private var низ: CGFloat = 0
    /// Высота от .мерилоФормы(): содержимое прокрутки UIKit вместе с панелью навигации.
    @State private var высотаФормы: CGFloat = 0
    /// Шапка и нижняя панель вне прокрутки (.частьЛистаВнеПрокрутки()).
    @State private var части: CGFloat = 0

    init(полоска: Bool = true) {
        self.полоска = полоска
    }

    func body(content: Content) -> some View {
        content
            .environment(\.отдатьВысотуЛиста, { (новое: CGFloat) in
                if abs(новое - высотаФормы) > 0.5 { высотаФормы = новое }
            })
            .background(
                GeometryReader { гео in
                    Color.clear
                        .onAppear { низ = Self.отступ(гео.safeAreaInsets.bottom) }
                        .onChange(of: гео.safeAreaInsets.bottom) { _, новое in низ = Self.отступ(новое) }
                }
                .ignoresSafeArea(.keyboard)
            )
            .onPreferenceChange(ВысотаЛистаКлюч.self) { новое in
                /* Полпункта дрожания не двигает лист — иначе вечная перекладка на дробных размерах. */
                if abs(новое - высота) > 0.5 { высота = новое }
            }
            .onPreferenceChange(ВысотаЧастейЛистаКлюч.self) { новое in
                if abs(новое - части) > 0.5 { части = новое }
            }
            .presentationDetents(набор)
            .presentationDragIndicator(полоска ? .visible : .hidden)
    }

    /// Только полоска «домой» (34 пт), не клавиатура: иначе лист рос бы на её высоту и прыгал.
    private static func отступ(_ значение: CGFloat) -> CGFloat {
        /* iOS 26: лист парит над полоской «домой» со своим отступом — прибавлять её ещё раз значит оставить под
           кнопкой пустую полосу (владелец: «всё равно внизу дыра»). */
        if #available(iOS 26.0, *) { return 0 }
        return min(max(значение, 0), 44)
    }

    private var набор: Set<PresentationDetent> {
        let основа: CGFloat = высотаФормы > 1 ? высотаФормы : высота
        guard основа > 1 else { return [.large] }
        let итог: CGFloat = (основа + части + низ).rounded(.up)
        return [.height(итог)]
    }
}

/*
 ФОРМА И СПИСОК В ЛИСТЕ. Form и List жадные: занимают всю высоту, и мерило в фоне (GeometryReader) отдаёт высоту листа,
 а не содержимого; из строк списка PreferenceKey наружу доходит не всегда. Поэтому строка формы (любая, обычно кнопка
 внизу) помечается .мерилоФормы(): невидимый UIView находит ближайшую UIScrollView (у Form и List это UICollectionView,
 у ScrollView тоже UIScrollView) и следит за contentSize. Высота = содержимое + верхняя вставка (панель навигации);
 клавиатура — нижняя вставка, её не берём, чтобы лист не прыгал. Длинная форма: помеченная строка внизу ещё не
 построена, высоты нет — лист остаётся большим и прокручивается. Замер уходит в .листПоВысоте() через окружение;
 вне такого листа (мастер «Начало работы») пометка ничего не делает.
 */
private struct ОтдатьВысотуЛистаКлюч: EnvironmentKey {
    static let defaultValue: ((CGFloat) -> Void)? = nil
}

extension EnvironmentValues {
    /// Куда .мерилоФормы() отдаёт высоту содержимого прокрутки; ставит .листПоВысоте().
    var отдатьВысотуЛиста: ((CGFloat) -> Void)? {
        get { self[ОтдатьВысотуЛистаКлюч.self] }
        set { self[ОтдатьВысотуЛистаКлюч.self] = newValue }
    }
}

extension View {
    /// Метка строки Form/List (или содержимого ScrollView): высота всей прокрутки уходит в .листПоВысоте().
    func мерилоФормы() -> some View {
        modifier(МерилоФормыЛиста())
    }
}

struct МерилоФормыЛиста: ViewModifier {
    @Environment(\.отдатьВысотуЛиста) private var отдать

    @ViewBuilder
    func body(content: Content) -> some View {
        if let отдать {
            content.background {
                МерилоПрокруткиЛиста(отдать: отдать)
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

/// Невидимый UIView внутри прокрутки: отдаёт contentSize.height + верхнюю вставку ближайшей UIScrollView.
struct МерилоПрокруткиЛиста: UIViewRepresentable {
    let отдать: (CGFloat) -> Void

    func makeUIView(context: Context) -> ВидМерилаПрокруткиЛиста {
        let вид = ВидМерилаПрокруткиЛиста()
        вид.isUserInteractionEnabled = false
        вид.backgroundColor = .clear
        вид.отдать = отдать
        return вид
    }

    func updateUIView(_ uiView: ВидМерилаПрокруткиЛиста, context: Context) {
        uiView.отдать = отдать
    }
}

final class ВидМерилаПрокруткиЛиста: UIView {
    var отдать: ((CGFloat) -> Void)?
    private weak var прокрутка: UIScrollView?
    private var наблюдения: [NSKeyValueObservation] = []
    private var последнее: CGFloat = -1

    override func didMoveToWindow() {
        super.didMoveToWindow()
        наблюдения = []
        прокрутка = nil
        guard window != nil else { return }
        var узел: UIView? = superview
        while let текущий = узел, !(текущий is UIScrollView) {
            узел = текущий.superview
        }
        guard let найдена = узел as? UIScrollView else { return }
        прокрутка = найдена
        /* contentOffset — ловит и смену верхней вставки: панель навигации встаёт позже первого замера. */
        let размер = найдена.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
            guard let вид = self else { return }
            Task { @MainActor in вид.пересчитать() }
        }
        let сдвиг = найдена.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            guard let вид = self else { return }
            Task { @MainActor in вид.пересчитать() }
        }
        наблюдения = [размер, сдвиг]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        пересчитать()
    }

    private func пересчитать() {
        guard let прокрутка else { return }
        let итог: CGFloat = прокрутка.contentSize.height + max(прокрутка.adjustedContentInset.top, 0)
        guard прокрутка.contentSize.height > 1, abs(итог - последнее) > 0.5 else { return }
        последнее = итог
        let отдать = self.отдать
        /* Не посреди раскладки UIKit: состояние SwiftUI меняем следующим тактом. */
        DispatchQueue.main.async { отдать?(итог) }
    }
}
