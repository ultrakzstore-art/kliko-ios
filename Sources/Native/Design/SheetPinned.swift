import SwiftUI

/**
 ЛИСТ С ЗАКРЕПЛЁННОЙ КНОПКОЙ ВНИЗУ (владелец, TestFlight 1.10: «знаки доверия — понятно, срезается снизу кнопка»).

 У листа по высоте содержимого (SheetFit.swift, .листПоВысоте) кнопка «Понятно» жила внутри прокрутки последней строкой:
 стоило высоте листа выйти на пару пунктов меньше содержимого (крупный шрифт, перенос строки после замера, полоска
 «домой»), и низ кнопки уходил под край. Теперь прокручивается только содержимое, а кнопка стоит вставкой снизу
 (.safeAreaInset(edge: .bottom)) — над полоской «домой» и всегда целиком. Высота листа — содержимое + кнопка + нижний
 отступ безопасной зоны и небольшой запас; не влезает на экран — система ограничит лист, а текст над кнопкой долистается.

 Содержимое внутри ScrollView метится тем же .мерилоЛиста(); корень — .листСКнопкойВнизу { кнопка }.
 */
struct ВысотаНизаЛистаКлюч: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Лист высотой по содержимому (помеченному .мерилоЛиста()) с кнопкой, закреплённой внизу над полоской «домой».
    func листСКнопкойВнизу<Низ: View>(фон: Color = Theme.поверхность,
                                     @ViewBuilder низ: () -> Низ) -> some View {
        modifier(ЛистСКнопкойВнизу(фон: фон, низ: низ()))
    }
}

struct ЛистСКнопкойВнизу<Низ: View>: ViewModifier {
    let фон: Color
    let низ: Низ

    @State private var высотаСодержимого: CGFloat = 0
    @State private var высотаНиза: CGFloat = 0
    @State private var отступСнизу: CGFloat = 0

    /// Запас на полоску-хваталку сверху и дробные пункты: без него последняя строка текста могла уйти под кнопку.
    private static let запас: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                низ
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .background(фон)
                    .background(
                        GeometryReader { гео in
                            Color.clear.preference(key: ВысотаНизаЛистаКлюч.self, value: гео.size.height)
                        }
                    )
            }
            .background(
                GeometryReader { гео in
                    Color.clear
                        .onAppear { отступСнизу = Self.отступ(гео.safeAreaInsets.bottom) }
                        .onChange(of: гео.safeAreaInsets.bottom) { _, новое in отступСнизу = Self.отступ(новое) }
                }
                .ignoresSafeArea(.keyboard)
            )
            .onPreferenceChange(ВысотаЛистаКлюч.self) { новое in
                if abs(новое - высотаСодержимого) > 0.5 { высотаСодержимого = новое }
            }
            .onPreferenceChange(ВысотаНизаЛистаКлюч.self) { новое in
                if abs(новое - высотаНиза) > 0.5 { высотаНиза = новое }
            }
            .presentationDetents(набор)
            .presentationDragIndicator(.visible)
            .presentationBackground(фон)
    }

    /// Только полоска «домой» (34 пт), не клавиатура: иначе лист рос бы на её высоту и прыгал.
    private static func отступ(_ значение: CGFloat) -> CGFloat {
        min(max(значение, 0), 44)
    }

    private var набор: Set<PresentationDetent> {
        guard высотаСодержимого > 1 else { return [.large] }
        let итог: CGFloat = (высотаСодержимого + высотаНиза + отступСнизу + Self.запас).rounded(.up)
        return [.height(итог)]
    }
}
