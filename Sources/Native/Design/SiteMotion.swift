import SwiftUI
import UIKit

/**
 ДВИЖЕНИЕ, ОТКЛИК И ЗАГРУЗКА — ОДНИ НА ВСЁ ПРИЛОЖЕНИЕ (владелец 26.09.2026: «все моменты, в том числе мелочи, в SwiftUI»).

 До этого у каждого экрана были свои числа: плашка появлялась за 0,2 с на одном экране и за 0,22 на соседнем, лист шага
 то пружиной, то плавно, отклик под пальцем — то UIKit, то sensoryFeedback. Теперь всё, что двигается, берёт постоянную
 отсюда (ДвижениеСайта), всё, что вздрагивает, — ОткликСайта, крутится — SiteSpinner, мерцает — МерцаниеСайта
 (оба ниже, в этом файле).

 «Уменьшение движения»: постоянные ДвижениеСайта — Animation? и при включённой настройке отдают nil: состояние меняется
 сразу, без полёта. Настройку кладёт в ДвижениеСайта.тихо корень нативного слоя (оформлениеСайта) из среды SwiftUI —
 постоянные читаются и из моделей, где среды нет.
 */
enum ДвижениеСайта {
    /// «Уменьшение движения» включено. Пишет только корень (ОформлениеСайта), читают постоянные ниже.
    static var тихо = false

    /// Своя анимация, которой нет среди постоянных ниже (бегущая полоса, мигание точек), — тоже гаснет при «Уменьшении
    /// движения».
    static func мягко(_ анимация: Animation) -> Animation? { тихо ? nil : анимация }

    // MARK: Нажатие

    /// Сжатие карточки и плитки под пальцем (.mh-tile:active, .mh-c:active) — 98 %.
    static let сжатие: CGFloat = 0.98
    /// Сжатие пункта нижней панели (.ulx-bb-item:active) — 92 %.
    static let сжатиеПанели: CGFloat = 0.92
    /// Нажатие — transition .12s ease-out сайта. Лёгкое сжатие не «полёт», его оставляем и при «Уменьшении движения».
    static let нажатие = Animation.easeOut(duration: 0.12)

    // MARK: Появление и уход

    /// Лист, карточка, плашка появляются: .2s ease-out.
    static var появление: Animation? { мягко(.easeOut(duration: 0.2)) }
    /// Плашка и карточка уходят: .2s ease-in.
    static var уход: Animation? { мягко(.easeIn(duration: 0.2)) }
    /// Смена содержимого на месте (сообщение, раскрытие, переключатель): .22s ease-in-out.
    static var смена: Animation? { мягко(.easeInOut(duration: 0.22)) }
    /// Выбор варианта, чипа, строки ошибки под полем: .15s ease-out.
    static var выбор: Animation? { мягко(.easeOut(duration: 0.15)) }

    // MARK: Списки, шаги, вкладки

    /// Строка списка вставлена или убрана (избранное, найденные при переносе, плитки фото).
    static var вставкаСписка: Animation? { мягко(.easeInOut(duration: 0.2)) }
    /// Шаг мастера (подача, резюме, перенос) вперёд и назад.
    static var шаг: Animation? { мягко(.easeInOut(duration: 0.25)) }
    /// Пилюля выбранной вкладки переезжает между пунктами нижней панели.
    static var вкладка: Animation? { мягко(.spring(response: 0.36, dampingFraction: 0.82)) }
    /// Прокрутка к месту (к началу ленты, к низу переписки, к полю с ошибкой).
    static var прокрутка: Animation? { мягко(.easeInOut(duration: 0.25)) }
    /// Смена слайда баннера и фото.
    static var слайд: Animation? { мягко(.easeInOut(duration: 0.45)) }
    /// Возврат на место после смахивания, которое не дотянули.
    static var возврат: Animation? { мягко(.spring(response: 0.32, dampingFraction: 0.84)) }
    /// Полоса прогресса дорастает до новой доли.
    static var прогресс: Animation? { мягко(.easeOut(duration: 0.4)) }
    /// Камера карты переезжает к точке.
    static var камера: Animation? { мягко(.easeInOut(duration: 0.45)) }

    // MARK: Нижняя панель (13-bottombar.min.js и .ulx-bbar сайта)

    /// .ulx-bbar { transition: transform .25s ease } — ease это cubic-bezier(.25, .1, .25, 1).
    static let панель = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.25)
    /// При «Уменьшении движения» панель не уезжает, а гаснет.
    static let затухание = Animation.easeInOut(duration: 0.2)
}

// MARK: - Отклик под пальцем

/**
 Один отклик на всё приложение: выбор (вкладка, чип, вариант) — лёгкий щелчок, отправка и публикация — «успех», ошибка
 проверки или отказ сервера — «предупреждение». В представлениях — модификаторы откликВыбора/откликУспеха/
 откликПредупреждения (sensoryFeedback iOS 17), в моделях и действиях — функции ниже.
 */
@MainActor
enum ОткликСайта {
    static func выбор() { UISelectionFeedbackGenerator().selectionChanged() }
    static func успех() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func предупреждение() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

extension View {
    /// Выбор вкладки, чипа, варианта — щелчок, когда меняется `повод`.
    func откликВыбора<T: Equatable>(_ повод: T) -> some View {
        sensoryFeedback(.selection, trigger: повод)
    }

    /// Отправлено, опубликовано, сохранено — «успех», когда меняется `повод`.
    func откликУспеха<T: Equatable>(_ повод: T) -> some View {
        sensoryFeedback(.success, trigger: повод)
    }

    /// Ошибка — «предупреждение», когда меняется `повод`.
    func откликПредупреждения<T: Equatable>(_ повод: T) -> some View {
        sensoryFeedback(.warning, trigger: повод)
    }
}

// MARK: - Спиннер .mk-spin сайта

/**
 Колесо сайта: круг с обводкой и цветным верхом (border + border-top-color), крутится равномерно. По умолчанию — .mk-spin
 из marketplace.min.css (.mk-loading): 20×20, обводка 2,5 — --mk-line (#e3ece7 / белый 10 %), верх --mk-green
 (#0f5132 / #22a05b), оборот 0,7 с. У сайта для него нет правила reduced-motion — крутится всегда.
 */
struct SiteSpinner: View {
    var размер: CGFloat = 20
    var толщина: CGFloat = 2.5
    var дорожка: Color = Theme.линия
    var верх: Color = Theme.зелёный
    var период: Double = 0.7
    /// Стоит на месте (прелоадер при «Уменьшении движения»).
    var стоит: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: стоит)) { шкала in
            let t = шкала.date.timeIntervalSinceReferenceDate
            let угол = стоит ? 0 : t.truncatingRemainder(dividingBy: период) / период * 360
            ZStack {
                Circle()
                    .strokeBorder(дорожка, lineWidth: толщина)
                /* border-top у круга — четверть от 225° до 315° (от левой верхней диагонали до правой). У Circle путь
                   начинается справа и идёт по часовой: это доли 0,625…0,875. */
                Circle()
                    .inset(by: толщина / 2)
                    .trim(from: 0.625, to: 0.875)
                    .stroke(верх, lineWidth: толщина)
            }
            .rotationEffect(.degrees(угол))
        }
        .frame(width: размер, height: размер)
        /* Как ProgressView: VoiceOver называет его «Загрузка…»; своя подпись снаружи (.accessibilityLabel) её заменяет. */
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ПодсказкиПрелоадера.загрузка)
    }
}

// MARK: - Мерцание заготовки

/// Мерцающая заготовка — .mh-sk, .mh-skc, .mh-tile-n:empty: заливка линией, прозрачность от 0,6 до 1 по часам.
struct МерцаниеСайта: View {
    let радиус: CGFloat
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    /// Лёгкий режим (DeviceMode.swift): ровная заливка, как при «Уменьшении движения».
    @ObservedObject private var режим = РежимУстройства.shared

    init(радиус: CGFloat) {
        self.радиус = радиус
    }

    var body: some View {
        Group {
            if безДвижения || режим.лёгкий {
                фигура(0.8)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20, paused: false)) { контекст in
                    фигура(0.8 + 0.2 * cos(контекст.date.timeIntervalSinceReferenceDate * 2 * Double.pi / 1.4))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func фигура(_ прозрачность: Double) -> some View {
        RoundedRectangle(cornerRadius: радиус, style: .continuous)
            .fill(Theme.линия)
            .opacity(прозрачность)
    }
}

// MARK: - Спиннер: готовые виды

extension SiteSpinner {
    /// На зелёной кнопке: белый верх на белой 35 % дорожке (вместо ProgressView().tint(.white)).
    static var белый: SiteSpinner {
        SiteSpinner(дорожка: Color.white.opacity(0.35), верх: Color.white)
    }

    /// Мелкий, в строку текста (вместо .controlSize(.small)): 16 pt.
    static var мелкий: SiteSpinner {
        SiteSpinner(размер: 16, толщина: 2)
    }

    /// Крошечный, в подпись кнопки (вместо .controlSize(.mini)): 12 pt.
    static var крошечный: SiteSpinner {
        SiteSpinner(размер: 12, толщина: 1.5)
    }

    /// Крупный, посреди пустого экрана (вместо .controlSize(.large)) — как колесо .prg прелоадера: 34 pt.
    static var крупный: SiteSpinner {
        SiteSpinner(размер: 34, толщина: 3)
    }

    /// Мелкий белый — на зелёной кнопке в строку.
    static var мелкийБелый: SiteSpinner {
        SiteSpinner(размер: 16, толщина: 2, дорожка: Color.white.opacity(0.35), верх: Color.white)
    }

    /// Своего цвета: верх — краска, дорожка — она же на 30 %.
    static func цвета(_ краска: Color) -> SiteSpinner {
        SiteSpinner(дорожка: краска.opacity(0.3), верх: краска)
    }
}

// MARK: - Корень нативного слоя: направление письма и «Уменьшение движения»

extension View {
    /**
     Корень нативного слоя (RootWebView) и окна, поднятые из UIKit: арабский — справа налево, остальные — слева направо,
     и «Уменьшение движения» в ДвижениеСайта.тихо. Код — ЯзыкПриложения.код.
     */
    func оформлениеСайта(языка код: String) -> some View {
        modifier(ОформлениеСайта(код: код))
    }
}

private struct ОформлениеСайта: ViewModifier {
    let код: String
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, ЯзыкПриложения.справаНалево(код) ? .rightToLeft : .leftToRight)
            .onAppear { ДвижениеСайта.тихо = безДвижения }
            .onChange(of: безДвижения) { _, новое in ДвижениеСайта.тихо = новое }
    }
}

extension String {
    /**
     Цена, телефон, номер — всегда слева направо и одним куском, как на сайте (unicode-bidi: isolate). В арабском тексте
     «+7 700 123 45 67» иначе стал бы «7 700 123 45 67+», а «12 500 ₸» — «₸ 12 500». Изоляция (U+2066 … U+2069) на
     экране не видна и места не занимает.
     */
    var слеваНаправо: String {
        "\u{2066}" + self + "\u{2069}"
    }
}

// MARK: - Нижняя панель прячется при прокрутке вниз (13-bottombar.min.js)

/**
 Как у сайта: у самого верха (меньше 80 pt) панель всегда видна; ниже — прокрутили вниз больше чем на 8 pt от последней
 точки решения — панель уезжает (translateY(100% + 4px)), вверх больше чем на 8 pt — возвращается. Короткая страница до
 80 pt не прокручивается — панель на ней не прячется никогда.

 Сдвиг сообщает корень вкладки модификатором панельСайтаПоПрокрутке() на содержимом своей прокрутки; панель
 (НижняяПанельСайта) смотрит на `скрыта` и сама возвращается при смене вкладки и при каждом появлении (ушла клавиатура,
 закрыли экран поверх корня). Место под панелью у корня (оставитьМестоПодПанелью) не меняется: как у сайта, уехавшая
 панель открывает низ содержимого, а прокрутка не прыгает.
 */
@MainActor
final class ПанельПоПрокрутке: ObservableObject {
    static let shared = ПанельПоПрокрутке()

    /// Ближе к верху — панель видна всегда (a < 80 у сайта).
    static let верх: CGFloat = 80
    /// Порог разворота: больше 8 pt в одну сторону от последней точки решения.
    static let порог: CGFloat = 8

    @Published private(set) var скрыта = false
    /// Точка последнего решения (e у сайта). nil — после сброса: первый же сдвиг становится опорой, ничего не решая
    /// (вернулись на вкладку, прокрученную до середины, — панель не должна уехать от первого касания).
    private var опора: CGFloat? = nil

    private init() {}

    /// Сдвиг прокрутки от верха корня вкладки: 0 — у верха, больше — прокручено вниз.
    func прокручено(_ сдвиг: CGFloat) {
        if сдвиг < Self.верх {
            опора = сдвиг
            показать()
            return
        }
        guard let прежняя = опора else {
            опора = сдвиг
            return
        }
        let разница = сдвиг - прежняя
        if разница > Self.порог {
            опора = сдвиг
            if !скрыта { скрыта = true }
        } else if разница < -Self.порог {
            опора = сдвиг
            показать()
        }
    }

    /// Вернуть панель: смена вкладки, панель снова на экране.
    func сбросить() {
        опора = nil
        показать()
    }

    private func показать() {
        if скрыта { скрыта = false }
    }
}

extension View {
    /**
     Содержимое прокрутки корня вкладки сообщает, насколько его прокрутили (ПанельПоПрокрутке). Ставится на то, что
     лежит внутри ScrollView: положение считается в пространстве ближайшей прокрутки (.scrollView, iOS 17), поэтому
     работает одинаково на iOS 17 и новее.
     */
    func панельСайтаПоПрокрутке() -> some View {
        modifier(СледПрокруткиПанели())
    }
}

private struct СледПрокруткиПанели: ViewModifier {
    /// Верх содержимого в покое — от него и считаем сдвиг (вставки сверху у каждой прокрутки свои).
    @State private var опора: CGFloat? = nil

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            GeometryReader { место in
                let верх = место.frame(in: .scrollView).minY
                Color.clear
                    .onAppear {
                        if опора == nil { опора = верх }
                    }
                    .onChange(of: верх) { _, новый in
                        let начало = опора ?? новый
                        if опора == nil { опора = новый }
                        ПанельПоПрокрутке.shared.прокручено(начало - новый)
                    }
            }
            .frame(height: 0)
            .accessibilityHidden(true)
        }
    }
}
