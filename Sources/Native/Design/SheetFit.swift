import SwiftUI

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

extension View {
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
}

struct ЛистПоВысоте: ViewModifier {
    @State private var высота: CGFloat = 0
    @State private var низ: CGFloat = 0

    func body(content: Content) -> some View {
        content
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
            .presentationDetents(набор)
            .presentationDragIndicator(.visible)
    }

    /// Только полоска «домой» (34 пт), не клавиатура: иначе лист рос бы на её высоту и прыгал.
    private static func отступ(_ значение: CGFloat) -> CGFloat {
        min(max(значение, 0), 44)
    }

    private var набор: Set<PresentationDetent> {
        guard высота > 1 else { return [.large] }
        let итог: CGFloat = (высота + низ).rounded(.up)
        return [.height(итог)]
    }
}
