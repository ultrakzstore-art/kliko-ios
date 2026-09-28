import Foundation
import SwiftUI

/**
 ЗАГОТОВКИ ЛЕНТЫ — ЭТАП 11 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «5–7 этапов наперёд»).

 Пока пустая лента грузится (первый запуск без ленты на диске, смена раздела, поиск), вместо колеса — заготовки той же
 сетки: видно, где появятся объявления, и экран не прыгает, когда они придут. Вид — .mk-card.mk-skel сайта (mkRender:
 восемь штук): рамка 1 pt без тени, скругление 18, фото 4:3 и под ним три полосы .mk-skel-l по 11 pt (70, 40 и 55 %
 ширины, скругление 6, зазор 8, поля 10 12 14). Фото и полосы — блеск mk-shim: градиент --mk-line / --mk-surf /
 --mk-line (25, 37, 63 %) вчетверо шире полосы проезжает её за 1,4 с.

 Блеск — по часам (TimelineView), а не повторяющейся анимацией: repeatForever, запущенная в onAppear внутри
 NavigationStack, подхватывает и сдвиг самой сетки, когда встаёт поле поиска, и карточки начинают «плавать».
 При «Уменьшении движения» блеска нет — ровная заливка линией, как у сайта (prefers-reduced-motion). VoiceOver читает
 заготовки одной фразой «Загружаем объявления». Рубильник — Config.скелетЛенты.
 */
struct СкелетЛенты: View {
    let колонки: [GridItem]
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(колонки: [GridItem]) {
        self.колонки = колонки
    }

    var body: some View {
        Group {
            if безДвижения {
                сетка(nil)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { контекст in
                    сетка(Self.сдвиг(контекст.date))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessText.т("loading"))
    }

    private func сетка(_ сдвиг: CGFloat?) -> some View {
        /* Зазор и поля — те же, что у сетки ленты (этап 49: у вида сайта 14 и 16), иначе карточки прыгнут при ответе. */
        LazyVGrid(columns: колонки, spacing: ListingCard.зазор) {
            ForEach(0..<8, id: \.self) { _ in
                ЯчейкаСкелетаЛенты(сдвиг: сдвиг)
            }
        }
        .padding(.horizontal, ListingCard.поле)
    }

    /// mk-shim: background-position от 100 % до −100 % при ширине фона 400 % — начало градиента едет от −3 до +3
    /// ширин полосы за 1,4 с, с плавным ease.
    private static func сдвиг(_ сейчас: Date) -> CGFloat {
        let t = сейчас.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
        let плавно = t * t * (3 - 2 * t)
        return CGFloat(-3 + 6 * плавно)
    }
}

/// Одна заготовка .mk-card.mk-skel: фото 4:3 и три полосы, рамка без тени.
private struct ЯчейкаСкелетаЛенты: View {
    /// Где начало градиента, в ширинах фигуры; nil — без блеска.
    let сдвиг: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(заливка)
                .aspectRatio(4 / 3, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8) {
                полоса(0.70)
                полоса(0.40)
                полоса(0.55)
            }
            .padding(.top, 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg - 1, style: .continuous))
        .padding(1)                         // рамка 1 px у сайта — снаружи содержимого
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// .mk-skel-l: 11 pt, скругление 6, ширина — доля строки.
    private func полоса(_ доля: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 11, maxHeight: 11)
            .overlay(alignment: .leading) {
                GeometryReader { г in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(заливка)
                        .frame(width: г.size.width * доля, height: 11)
                }
            }
    }

    /// Градиент блеска относительно самой фигуры (как background у каждой полосы сайта) или ровная линия.
    private var заливка: AnyShapeStyle {
        guard let сдвиг else { return AnyShapeStyle(Theme.линия) }
        let блеск = Gradient(stops: [
            .init(color: Theme.линия, location: 0.25),
            .init(color: Theme.поверхность, location: 0.37),
            .init(color: Theme.линия, location: 0.63)
        ])
        return AnyShapeStyle(LinearGradient(gradient: блеск,
                                            startPoint: UnitPoint(x: сдвиг, y: 0.5),
                                            endPoint: UnitPoint(x: сдвиг + 4, y: 0.5)))
    }
}
