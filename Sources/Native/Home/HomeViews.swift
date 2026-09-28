import SwiftUI

/**
 VIP, «КАК БЫЛО» И «ПОКАЗАТЬ ВСЕ» — ЭТАП 34 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Образец — mkHomeRender и css/marketplace-home.min.css главной kliko.kz на телефоне:
   .mh-vip — золотой квадрат 40×40 со звездой (linear-gradient(135deg, #d9b24c, #b88a1e), скругление --r-ms), рядом
     «VIP-объявления» заголовком .mh-h2 (21px, 800) и «Размещены в ТОП» мелко и приглушённо; ниже — сетка в две колонки
     (на широком экране — больше), каждая карточка в золотой рамке, как ТОП (.mh-vipg .mh-c);
   .mh-stale — строка «Показано, как было в последний раз» с белой пилюлей «Повторить»;
   .mh-all — зелёная кнопка во всю ширину, высота 48, скругление --r-md: «Показать все объявления», total на светлой
     плашке и стрелка.
 */
struct БлокВИП<Карточка: View>: View {
    let товары: [Listing]
    /// Колонки — те же, что у сетки ленты (ListingCard.сетка): при крупном тексте одна.
    let колонки: [GridItem]
    let карточка: (Listing) -> Карточка

    init(товары: [Listing], колонки: [GridItem], @ViewBuilder карточка: @escaping (Listing) -> Карточка) {
        self.товары = товары
        self.колонки = колонки
        self.карточка = карточка
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            заголовок
            /* Между строками — тот же зазор, что между колонками (.mh-vipg: gap var(--vx-gap)). */
            LazyVGrid(columns: колонки, spacing: колонки.first?.spacing ?? 12) {
                ForEach(товары) { товар in
                    карточка(товар)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var заголовок: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 20, weight: .bold))         // .mh-vipic svg 20 px
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                /* Тень — заливкой подложки (ShapeStyle.shadow), как у метки «★ ТОП» (сборка 33, «лента подвисает»). */
                .background(LinearGradient(colors: [Theme.топНачало, Theme.топКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .shadow(.drop(color: Color(red: 176 / 255, green: 132 / 255, blue: 24 / 255).opacity(0.5),
                                              radius: 6, x: 0, y: 5)),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeText.т("vip_h"))
                    .font(.system(size: 21, weight: .heavy))    // .mh-h2: --fs-h1 21 px/800, −0,015 em
                    .tracking(-0.315)
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(HomeText.т("vip_s"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// «Показано, как было в последний раз» с «Повторить» (.mh-stale): на экране копия главной с диска или прежнего места,
/// а свежая не пришла. Не помещается в строку — надпись над кнопкой, как flex-wrap сайта.
struct СтрокаУстаревшейГлавной: View {
    let повторить: () -> Void

    init(повторить: @escaping () -> Void) {
        self.повторить = повторить
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                надпись
                кнопка
            }
            VStack(spacing: 8) {
                надпись
                кнопка
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private var надпись: some View {
        Label(HomeText.т("stale"), systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(Theme.текстВторой)
            .multilineTextAlignment(.center)
    }

    private var кнопка: some View {
        Button(action: повторить) {
            Text(DesignText.т("retry"))
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.поверхность, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.линия, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

/// «Показать все объявления» с total (.mh-all): уводит с главной на всю ленту (mkHomeAll сайта; этап 49 — и у приложения:
/// FeedModel.показатьВсе).
struct КнопкаВсехОбъявлений: View {
    /// total ответа home=1; nil или 0 — без плашки, как .mh-all b:empty.
    let всего: Int?
    let действие: () -> Void

    init(всего: Int?, действие: @escaping () -> Void) {
        self.всего = всего
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 10) {
                Text(HomeText.т("show_all"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let всего, всего > 0 {
                    Text(DesignText.число(всего))
                        .font(.system(.footnote, weight: .heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                }
                Image(systemName: "arrow.forward")
                    .font(.system(size: 16, weight: .bold))
            }
            .font(.system(.subheadline, weight: .heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Theme.зелёный
                            .shadow(.drop(color: Color(red: 15 / 255, green: 81 / 255, blue: 50 / 255).opacity(0.45),
                                          radius: 10, x: 0, y: 8)),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеСайта())
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .accessibilityAddTraits(.isButton)
    }

    private var голос: String {
        guard let всего, всего > 0 else { return HomeText.т("show_all") }
        return HomeText.т("show_all") + ", " + DesignText.предложений(всего)
    }
}
