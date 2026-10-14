import SwiftUI

/**
 ЛИСТ ВЫСОТОЙ ПО СОДЕРЖИМОМУ (владелец 14.10.2026, TestFlight 74: «снизу пустота» у листов «Связаться с продавцом» и
 «Разбор объявления»). Тот же приём, что у окна жалобы (Seller/ReportSheet.swift): содержимое прокрутки меряет свою
 высоту (мерятьВысотуЛиста — на VStack внутри ScrollView, после полей), лист встаёт на .height(высота + запас); потянуть
 вверх — на весь экран, там и остаётся. Пока мерки нет — .medium. Содержимое выросло (догрузился «Разбор») — лист растёт.
 */
struct ВысотаСодержимогоЛиста: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Мерка высоты содержимого листа: вешать на VStack внутри ScrollView листа, после его полей.
    func мерятьВысотуЛиста() -> some View {
        background {
            GeometryReader { рамка in
                Color.clear.preference(key: ВысотаСодержимогоЛиста.self, value: рамка.size.height)
            }
        }
    }

    /// Деталь листа по высоте содержимого (вместо presentationDetents); запас — под полоску «домой».
    func листПоСодержимому(запас: CGFloat = 24) -> some View {
        modifier(ЛистПоСодержимому(запас: запас))
    }
}

struct ЛистПоСодержимому: ViewModifier {
    let запас: CGFloat
    @State private var высота: CGFloat = 0
    @State private var ступень: PresentationDetent = .medium

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(ВысотаСодержимогоЛиста.self) { новая in мерить(новая) }
            .presentationDetents(детали, selection: $ступень)
    }

    private var детали: Set<PresentationDetent> {
        высота > 0 ? [.height(высота + запас), .large] : [.medium, .large]
    }

    /// Новая высота содержимого; лист раскрыт на весь экран — там и остаётся.
    private func мерить(_ новая: CGFloat) {
        guard новая > 0, abs(новая - высота) > 0.5 else { return }
        let поВысоте = ступень != .large
        высота = новая
        if поВысоте { ступень = .height(новая + запас) }
    }
}
