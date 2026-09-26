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

 TestFlight 1.10 (владелец: «снизу боттом бар более современный — как на iOS 26+»): панель — плавающая капсула с
 отступом от краёв над домашней полосой. iOS 26 — Liquid Glass (glassEffect), iOS 17–25 — .ultraThinMaterial с кромкой и
 тенью (СтеклоПанели). Выбранный пункт — пилюля, переезжающая между пунктами (matchedGeometryEffect), значок залитый;
 камера — круглая заметная кнопка внутри капсулы (КругКамеры), без прежнего подъёма на 20 pt. Пункты, подписи, счётчик,
 VoiceOver — прежние; отклик под пальцем — sensoryFeedback(.selection). Прятать панель над экранами поверх корня и место
 под ней у корней вкладок (оставитьМестоПодПанелью, высота 64) — как раньше. ФонПанелиСайта (прежняя сплошная панель)
 оставлен для совместимости.
 */
struct НижняяПанельСайта: View {
    enum Пункт: Hashable { case категории, избранное, чат, кабинет }

    /// Место под панелью у корней вкладок (оставитьМестоПодПанелью): капсула 58 pt и зазор 6 pt над домашней полосой.
    static let высота: CGFloat = 64
    /// Высота самой капсулы.
    static let высотаКапсулы: CGFloat = 58

    /// Выбранный пункт; nil — ни один.
    let выбран: Пункт?
    /// Лента на главной: первая кнопка — «Категории», иначе «Главная».
    let главная: Bool
    let непрочитано: Int
    let показатьИзбранное: Bool
    let выбрать: (Пункт) -> Void
    /// Кнопка камеры; nil — адреса подачи нет, и кнопки нет.
    let камера: (() -> Void)?

    /// Пилюля выбранного пункта переезжает между пунктами (matchedGeometryEffect).
    @Namespace private var пилюля
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    /// Отклик под пальцем — счётчик нажатий, а не выбранный пункт: повторное нажатие (к началу стека) тоже отзывается.
    @State private var нажатий = 0

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
        ряд
            .padding(.horizontal, 6)
            .frame(height: Self.высотаКапсулы)
            .modifier(СтеклоПанели())
            .frame(maxWidth: 520)
            .padding(.horizontal, 14)
            .padding(.bottom, Self.высота - Self.высотаКапсулы)
            .frame(maxWidth: .infinity)
            .frame(height: Self.высота, alignment: .bottom)
            .animation(безДвижения ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: выбран)
            .sensoryFeedback(.selection, trigger: нажатий)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(DesignText.т("nav"))
    }

    private var ряд: some View {
        HStack(alignment: .center, spacing: 2) {
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
    }

    private func пункт(_ п: Пункт, значок: String, подпись: String, счёт: Int = 0) -> some View {
        let активен = выбран == п
        return Button {
            нажатий += 1
            выбрать(п)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: активен ? значок + ".fill" : значок)
                    .font(.system(size: 19, weight: активен ? Font.Weight.semibold : Font.Weight.regular))
                    .frame(height: 22)
                Text(подпись)
                    .font(.system(size: 10.5, weight: активен ? Font.Weight.bold : Font.Weight.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(активен ? Theme.акцент : Theme.панельПункт)
            .frame(maxWidth: .infinity)
            .frame(height: Self.высотаКапсулы - 10)
            .background {
                if активен {
                    ПилюляВыбора()
                        .matchedGeometryEffect(id: "выбор", in: пилюля)
                }
            }
            .overlay(alignment: .top) {
                if счёт > 0 {
                    Text(счёт > 99 ? "99+" : String(счёт))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(Theme.сердце, in: Capsule())
                        .shadow(color: Theme.сердце.opacity(0.4), radius: 2, x: 0, y: 1)
                        .offset(x: 13, y: 2)
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

    /// Камера посередине — круглая заметная кнопка: зелёное стекло на iOS 26, зелёный градиент раньше.
    private func кнопкаКамеры(_ действие: @escaping () -> Void) -> some View {
        Button {
            нажатий += 1
            действие()
        } label: {
            КругКамеры()
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.9))
        .frame(width: 58)
        .accessibilityLabel(DesignText.т("post"))
        .accessibilityHint(DesignText.т("on_site"))
    }
}

/**
 Нижняя панель в духе iOS 26 (владелец, TestFlight 1.10: «снизу боттом бар более современный — как на iOS 26+»):
 плавающая капсула с отступом от краёв над домашней полосой. На iOS 26 — Liquid Glass (glassEffect(.regular, in:)),
 раньше — .ultraThinMaterial с тонкой кромкой и мягкой тенью. Пункты, камера, счётчик и подписи — прежние, сайта.
 */
private struct СтеклоПанели: ViewModifier {
    @Environment(\.colorScheme) private var схема

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule())
                .shadow(color: Color.black.opacity(схема == .dark ? 0.35 : 0.10), radius: 14, x: 0, y: 6)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .background(Theme.панель.opacity(схема == .dark ? 0.55 : 0.45), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(схема == .dark ? 0.16 : 0.7),
                                                              Theme.панельКромка.opacity(0.25)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: 0.8)
                        .accessibilityHidden(true)
                }
                .shadow(color: схема == .dark ? Color.black.opacity(0.5)
                                              : Color(red: 10 / 255, green: 45 / 255, blue: 28 / 255).opacity(0.16),
                        radius: 16, x: 0, y: 6)
        }
    }
}

/// Пилюля выбранного пункта: мягкий зелёный оттенок с бликом сверху — «стеклянная» подсветка на любой версии.
private struct ПилюляВыбора: View {
    @Environment(\.colorScheme) private var схема

    var body: some View {
        Capsule()
            .fill(Theme.оттенокАкцента)
            .overlay {
                Capsule()
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(схема == .dark ? 0.18 : 0.8),
                                                          Theme.акцент.opacity(0.18)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.8)
            }
            .padding(.horizontal, 2)
            .accessibilityHidden(true)
    }
}

/// Круг камеры 46 pt: на iOS 26 — зелёное «жидкое стекло» с откликом на касание, раньше — градиент с бликом и тенью.
private struct КругКамеры: View {
    var body: some View {
        let значок = Image(systemName: "camera.fill")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 46, height: 46)
        if #available(iOS 26.0, *) {
            значок
                .glassEffect(.regular.tint(Theme.кнопкаКамерыНачало).interactive(), in: Circle())
                .shadow(color: Theme.кнопкаКамерыНачало.opacity(0.35), radius: 8, x: 0, y: 4)
        } else {
            значок
                .background(
                    LinearGradient(colors: [Theme.кнопкаКамерыКонец, Theme.кнопкаКамерыНачало],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: Theme.кнопкаКамерыНачало.opacity(0.45), radius: 8, x: 0, y: 4)
        }
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

/**
 Место под нижней панелью сайта у корня вкладки (владелец 25.09.2026, проверка на телефоне, сборка 33).

 🔴 На телефоне в переписке не было поля ввода: панель висела поверх экрана чата и закрывала его низ. Этап 27 ставил
 панель вставкой снизу (safeAreaInset) на стопку вкладок и считал, что каждый экран в NavigationStack отступит от неё
 сам. Экран, положенный в стек поверх корня, живёт в своём UIHostingController внутри UINavigationController и эту
 вставку не получает — он отступал только от домашней полосы, и нижние 60 pt (поле ввода) оказывались под панелью.

 Теперь панель — слой поверх (overlay), безопасную зону никому не меняет, а место под неё оставляет сам корень вкладки
 этой вставкой — внутри своего стека, где вставки работают (так же держится шапка ленты и панель «Связаться»).
 Экраны поверх корня (переписка, объявление, сравнение) места не оставляют: панель над ними спрятана.
 */
private struct КлючМестаПодПанелью: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Сколько оставить внизу корня ленты под панелью сайта; 0 — панели нет (без нижних вкладок или клавиатура).
    /// Ставит NativeTabsView, читает только NativeFeedView — у неё стек внутри.
    var местоПодПанельюСайта: CGFloat {
        get { self[КлючМестаПодПанелью.self] }
        set { self[КлючМестаПодПанелью.self] = newValue }
    }
}

extension View {
    /// Прозрачная вставка снизу высотой панели: прокрутка корня вкладки доезжает до панели, а не уходит под неё.
    func оставитьМестоПодПанелью(_ высота: CGFloat) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if высота > 0 {
                Color.clear
                    .frame(height: высота)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Экран, открытый поверх стека без NavigationPath (navigationDestination(isPresented:)): путь стека его не видит,
    /// а панель над ним должна прятаться так же, как над остальными.
    func отметкаПоверхСайта() -> some View {
        modifier(ОтметкаПоверхСайта())
    }
}

/// Отметка «поверх корня» в ВидСайта.поверх — пока экран на экране.
struct ОтметкаПоверхСайта: ViewModifier {
    @Environment(\.стекСайта) private var стек
    @State private var метка = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { ВидСайта.shared.поверх[метка] = стек }
            .onDisappear { ВидСайта.shared.поверх[метка] = nil }
    }
}

/// Клавиатура на экране: панель под ней не нужна — иначе она встала бы над клавиатурой, между полем
/// ввода и клавишами. Аппаратная клавиатура iPad присылает «показ» с полоской высотой в пару десятков точек — это
/// не клавиатура, панель остаётся.
enum КлавиатураНаЭкране {
    static func видна(_ уведомление: Notification) -> Bool {
        guard let рамка = уведомление.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return true }
        return рамка.height > 120
    }
}
