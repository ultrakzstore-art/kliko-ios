import SwiftUI
import UIKit

/**
 НИЖНЯЯ ПАНЕЛЬ КАК НА САЙТЕ — ЭТАП 27 (владелец 25.09.2026: «приложение должно быть почти 100% похоже на сайт»).

 Образец — nav.ulx-bbar главной kliko.kz (<style id="ulx-bbar-css"> и html.mk-gtop .ulx-bbar): белая (в тёмной —
 #16161f) панель со скруглённым верхом 22 pt и зелёной кромкой, пункты «Категории · Избранное · [камера] · Чат ·
 Кабинет» — значок 23 pt и подпись 11 pt, серые (#5f6c63 / #90a499), выбранный — зелёный акцент; посередине —
 приподнятая на 20 pt зелёная круглая кнопка камеры 50 pt с кромкой цвета панели. Счётчик непрочитанных — красная
 «пилюля» #e0245e у значка «Чата», как .ulx-bb-badge.

 Первая кнопка — как у сайта: на главной «Категории», в разделе или поиске — «Главная» с домиком, и ведёт на главную.
 Камера — страница подачи (a.ulx-bb-add: /kz/<язык>/cabinet?go=add). Значки — ближайшие SF Symbols к SVG сайта.
 */
struct НижняяПанельСайта: View {
    enum Пункт: Hashable { case категории, избранное, чат, кабинет }

    /// Выбранный пункт; nil — ни один.
    let выбран: Пункт?
    /// Лента на главной: первая кнопка — «Категории», иначе «Главная».
    let главная: Bool
    let непрочитано: Int
    let показатьИзбранное: Bool
    let выбрать: (Пункт) -> Void
    /// Кнопка камеры; nil — адреса подачи нет, и кнопки нет.
    let камера: (() -> Void)?

    /// Явный init, как у ListingCard: панель создаёт другой файл (NativeTabsView), и поэлементный init не должен
    /// зависеть от того, появится ли здесь закрытое свойство.
    init(выбран: Пункт?, главная: Bool, непрочитано: Int, показатьИзбранное: Bool,
         выбрать: @escaping (Пункт) -> Void, камера: (() -> Void)?) {
        self.выбран = выбран
        self.главная = главная
        self.непрочитано = непрочитано
        self.показатьИзбранное = показатьИзбранное
        self.выбрать = выбрать
        self.камера = камера
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            пункт(.категории, значок: главная ? "square.grid.2x2" : "house",
                  подпись: DesignText.т(главная ? "categories" : "home"))
            if показатьИзбранное {
                пункт(.избранное, значок: "heart", подпись: DesignText.т("favorites"))
            }
            if let камера {
                кнопкаКамеры(камера)
            }
            пункт(.чат, значок: "message", подпись: DesignText.т("chat"), счёт: непрочитано)
            пункт(.кабинет, значок: "person", подпись: DesignText.т("cabinet"))
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 6)
        .padding(.top, 7)
        .frame(maxWidth: .infinity)
        .frame(height: 60, alignment: .top)
        .background(alignment: .top) {
            ФонПанелиСайта()
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DesignText.т("nav"))
    }

    private func пункт(_ п: Пункт, значок: String, подпись: String, счёт: Int = 0) -> some View {
        let активен = выбран == п
        return Button { выбрать(п) } label: {
            VStack(spacing: 4) {
                Image(systemName: значок)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 23)
                Text(подпись)
                    .font(.system(size: 11, weight: активен ? Font.Weight.bold : Font.Weight.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(активен ? Theme.акцент : Theme.панельПункт)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .overlay(alignment: .top) {
                if счёт > 0 {
                    Text(счёт > 99 ? "99+" : String(счёт))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Theme.сердце, in: Capsule())
                        .shadow(color: Theme.сердце.opacity(0.4), radius: 2, x: 0, y: 1)
                        .offset(x: 14, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта())
        .accessibilityLabel(подпись)
        .accessibilityValue(счёт > 0 ? String(format: DesignText.т("unread"), счёт) : "")
        .accessibilityAddTraits(активен ? .isSelected : [])
    }

    /// .ulx-bb-add: круг 50 pt на 20 pt выше панели, градиент зелёного, кромка 3 pt цвета панели, камера 26 pt.
    private func кнопкаКамеры(_ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: "camera")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 50, height: 50)
                .background(
                    LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay {
                    Circle().strokeBorder(Theme.панель, lineWidth: 3)
                }
                .shadow(color: Theme.кнопкаКамерыНачало.opacity(0.55), radius: 9, x: 0, y: 6)
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.9))
        .frame(width: 54)
        .offset(y: -20)
        .accessibilityLabel(DesignText.т("post"))
        .accessibilityHint(DesignText.т("on_site"))
    }
}

/// Фон панели: поверхность со скруглённым верхом 22 pt, зелёная кромка сверху (гаснет к краям), тень вверх.
struct ФонПанелиСайта: View {
    @Environment(\.colorScheme) private var схема

    init() {}

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.шапка, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: Theme.Радиус.шапка, style: .continuous)
    }

    var body: some View {
        форма
            .fill(Theme.панель)
            .overlay {
                форма
                    .stroke(LinearGradient(colors: [Theme.панельКромка.opacity(0.12), Theme.панельКромка,
                                                    Theme.панельКромка.opacity(0.12)],
                                           startPoint: .leading, endPoint: .trailing),
                            lineWidth: 2)
                    /* Только верхняя кромка, как border-top сайта: боковые и нижняя гаснут. */
                    .mask {
                        LinearGradient(colors: [Color.black, Color.clear], startPoint: .top,
                                       endPoint: UnitPoint(x: 0.5, y: 0.3))
                    }
            }
            .shadow(color: схема == .dark ? Color.black.opacity(0.55)
                                          : Color(red: 10 / 255, green: 45 / 255, blue: 28 / 255).opacity(0.18),
                    radius: 12, x: 0, y: -4)
            .accessibilityHidden(true)
    }
}

/// Нажатие пункта панели — .ulx-bb-item:active { transform: scale(.92) }.
struct НажатиеПанелиСайта: ButtonStyle {
    var сжатие: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? сжатие : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Клавиатура на экране: панель под ней не нужна — иначе safeAreaInset поднял бы её над клавиатурой, между полем
/// ввода и клавишами. Аппаратная клавиатура iPad присылает «показ» с полоской высотой в пару десятков точек — это
/// не клавиатура, панель остаётся.
enum КлавиатураНаЭкране {
    static func видна(_ уведомление: Notification) -> Bool {
        guard let рамка = уведомление.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return true }
        return рамка.height > 120
    }
}
