import SwiftUI
import UIKit

/**
 «ПОМЕСТИТСЯ ЛИ?» — ЛИНЕЙКА: ЧАСТИ ЭКРАНА (владелец 14.10.2026: «добавь линейку для габаритных вещей»). Модель и сцена —
 ЛинейкаГабаритов (FitBoxRuler.swift); окно — ЭкранГабаритов (FitBoxScreen.swift), он и ставит эти части:
   · ПереключательРежимаГабаритов — «Коробка / Линейка» под заголовком;
   · ПрицелЛинейкиГабаритов — прицел ровно в центре экрана (оттуда ARKit бросает луч) и длина тянущегося отрезка;
   · ПодсказкаЛинейкиГабаритов — что делать сейчас («Медленно ведите телефоном», «Наведите на начало…»);
   · ПанельЛинейкиГабаритов — «Сравнить с вещью» (чипы и итог), «Очистить», «Отменить», «+», «Снимок» и точность;
   · ОзвучкаСценыЛинейкиГабаритов — подпись и значение сцены для VoiceOver в обоих режимах;
   · КнопкаГотовоЗамераЛинейки — «Готово» замера вещи из подачи (замеры — в поля «Габариты, см»).
 При крупном тексте (AX) панель держит «+» на экране: верх панели прокручивается, «+» не больше 96 pt, подсказка — до
 трёх строк. Окно всегда тёмное — цвета здесь под камеру; шрифты — по «Размеру текста»; при «Уменьшении движения» ничего не
 качается; справа налево ряды разворачиваются сами (HStack, ScrollView).
 */

// MARK: - Переключатель

struct ПереключательРежимаГабаритов: View {
    let режим: РежимГабаритов
    let сменить: (РежимГабаритов) -> Void

    private func т(_ ключ: String) -> String { ЛинейкаГабаритовText.т(ключ) }

    var body: some View {
        HStack(spacing: 4) {
            кнопка(.коробка, значок: "cube.transparent", подпись: т("fr_mode_box"))
            кнопка(.линейка, значок: "ruler", подпись: т("fr_mode_ruler"))
        }
        .padding(4)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .animation(ДвижениеСайта.выбор, value: режим)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(т("fr_mode_a11y"))
    }

    private func кнопка(_ свой: РежимГабаритов, значок: String, подпись: String) -> some View {
        let выбран = режим == свой
        return Button {
            guard !выбран else { return }
            сменить(свой)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(выбран ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(выбран ? AnyShapeStyle(Theme.шапкаМята) : AnyShapeStyle(Color.clear), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Прицел

/// Прицел в центре экрана: сплошной и с мятной точкой — под ним поверхность; пунктир — луч ни во что не упёрся. Под
/// прицелом — длина от начала до прицела. Касания проходят насквозь, для VoiceOver скрыт (сцену озвучивает модель).
struct ПрицелЛинейкиГабаритов: View {
    @ObservedObject var живое: ЖивоеЛинейкиГабаритов

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(живое.цель ? 0.95 : 0.55),
                              style: StrokeStyle(lineWidth: 2, dash: живое.цель ? [] : [4, 4]))
            Circle()
                .fill(живое.цель ? Theme.шапкаМята : Color.white.opacity(0.6))
                .frame(width: 7, height: 7)
        }
        .frame(width: 38, height: 38)
        .overlay(alignment: .top) {
            if let длина = живое.длина {
                Text(ЛинейкаГабаритовText.длина(длина))
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.шапкаМята, in: Capsule())
                    .fixedSize()
                    .offset(y: 48)
            }
        }
        .shadow(color: Color.black.opacity(0.45), radius: 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Подсказка

struct ПодсказкаЛинейкиГабаритов: View {
    @ObservedObject private var линейка: ЛинейкаГабаритов
    @ObservedObject private var живое: ЖивоеЛинейкиГабаритов
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(линейка: ЛинейкаГабаритов) {
        _линейка = ObservedObject(wrappedValue: линейка)
        _живое = ObservedObject(wrappedValue: линейка.живое)
    }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        let подсказка = линейка.подсказка(цель: живое.цель)
        VStack(spacing: 8) {
            пилюля(значок: подсказка.значок, текст: подсказка.текст)
                .id(подсказка.текст)
                .transition(.opacity)
            if let сообщение = линейка.сообщение {
                Text(сообщение)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.шапкаМята,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .animation(ДвижениеСайта.смена, value: подсказка.текст)
        .animation(ДвижениеСайта.смена, value: линейка.сообщение)
    }

    private func пилюля(значок: String, текст: String) -> some View {
        HStack(spacing: 10) {
            значокПодсказки(значок)
                .accessibilityHidden(true)
            /* Крупный текст: не больше трёх строк (с ужатием) — подсказка не выдавливает панель с «+» за экран;
               целиком её читает VoiceOver. */
            if размерТекста.isAccessibilitySize {
                Text(текст)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            } else {
                Text(текст)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// «Медленно ведите телефоном» — телефон покачивается (при «Уменьшении движения» — стоит).
    @ViewBuilder
    private func значокПодсказки(_ значок: String) -> some View {
        let картинка = Image(systemName: значок)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.шапкаМята)
        if значок == "iphone" && !тихо {
            картинка.phaseAnimator([false, true]) { вид, фаза in
                вид
                    .offset(x: фаза ? 5 : -5)
                    .rotationEffect(.degrees(фаза ? 8 : -8))
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        } else {
            картинка
        }
    }
}

// MARK: - Панель

struct ПанельЛинейкиГабаритов: View {
    @ObservedObject var линейка: ЛинейкаГабаритов
    /// Камера идёт: ставить точки можно.
    let можно: Bool
    let снять: () -> Void
    @ScaledMetric(relativeTo: .title) private var плюс: CGFloat = 70
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(линейка: ЛинейкаГабаритов, можно: Bool, снять: @escaping () -> Void) {
        self.линейка = линейка
        self.можно = можно
        self.снять = снять
    }

    private func т(_ ключ: String) -> String { ЛинейкаГабаритовText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var естьЧтоУбрать: Bool { линейка.начато || линейка.отрезков > 0 }

    /// Крупный текст (AX-размеры): карточка сравнения, «Сравнить / Очистить» и точность — в прокрутке ограниченной
    /// высоты, ряд с «+» закреплён под ней, «+» не больше 96 pt — на маленьком iPhone органы управления не уходят за
    /// экран.
    private var крупно: Bool { размерТекста.isAccessibilitySize }

    private var размерПлюса: CGFloat { min(плюс, 96) }

    var body: some View {
        VStack(spacing: 10) {
            if крупно {
                ScrollView {
                    верх
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: линейка.сравнивать && линейка.габариты != nil ? 170 : 110)
            } else {
                верх
            }
            HStack(alignment: .center, spacing: 8) {
                боковая(значок: "arrow.uturn.backward", подпись: т("fr_undo"), озвучка: т("fr_undo_a11y"),
                        можно: естьЧтоУбрать) {
                    линейка.отменить()
                }
                кнопкаПлюс
                кнопкаСнимка
            }
            if !крупно {
                точность
            }
        }
        .animation(ДвижениеСайта.смена, value: линейка.сравнивать)
    }

    /// Над рядом с «+»: сравнение с вещью, «Сравнить / Очистить»; при крупном тексте — и точность (в прокрутке).
    private var верх: some View {
        VStack(spacing: 10) {
            if линейка.сравнивать && линейка.габариты != nil {
                КарточкаСравненияЛинейки(линейка: линейка)
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                if линейка.габариты != nil {
                    кнопкаСравнения
                }
                кнопкаОчистки
            }
            if крупно {
                точность
            }
        }
    }

    private var точность: some View {
        Text(ЛинейкаГабаритов.точность)
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.75))
            .multilineTextAlignment(.center)
            .shadow(color: Color.black.opacity(0.6), radius: 3)
    }

    private var кнопкаПлюс: some View {
        Button {
            линейка.добавить()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 4)
                    .frame(width: размерПлюса, height: размерПлюса)
                Circle()
                    .fill(можно ? Theme.зелёныйЯркий : Color.white.opacity(0.3))
                    .frame(width: размерПлюса - 14, height: размерПлюса - 14)
                Image(systemName: "plus")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!можно)
        .accessibilityLabel(линейка.начато ? т("fr_add_end") : т("fr_add"))
    }

    private var кнопкаСнимка: some View {
        let доступно = линейка.отрезков > 0 && !линейка.снимаем
        return Button {
            ОткликСайта.выбор()
            снять()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if линейка.снимаем {
                        SiteSpinner(размер: 20, толщина: 2.5, дорожка: Color.white.opacity(0.25), верх: Color.white,
                                    стоит: тихо)
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                Text(ГабаритыText.т("fb_shot"))
                    .font(.caption.weight(.semibold))
                    .lineLimit(крупно ? 1 : 2)
                    .minimumScaleFactor(крупно ? 0.6 : 1)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black.opacity(0.6), radius: 3)
            }
            .foregroundStyle(Color.white)
            .opacity(доступно ? 1 : 0.4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!доступно)
        .accessibilityLabel(ГабаритыText.т("fb_shot"))
        .accessibilityHint(т("fr_shot_a11y"))
    }

    private func боковая(значок: String, подпись: String, озвучка: String, можно: Bool,
                         действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 4) {
                Image(systemName: значок)
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
                Text(подпись)
                    .font(.caption.weight(.semibold))
                    .lineLimit(крупно ? 1 : 2)
                    .minimumScaleFactor(крупно ? 0.6 : 1)
                    .multilineTextAlignment(.center)
                    .shadow(color: Color.black.opacity(0.6), radius: 3)
            }
            .foregroundStyle(Color.white)
            .opacity(можно ? 1 : 0.4)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!можно)
        .accessibilityLabel(озвучка)
    }

    private var кнопкаСравнения: some View {
        let включено = линейка.сравнивать
        return Button {
            ОткликСайта.выбор()
            линейка.сравнивать.toggle()
        } label: {
            капсула(значок: включено ? "checkmark.circle.fill" : "arrow.left.and.right.square", текст: т("fr_compare"),
                    включено: включено)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(т("fr_compare"))
        .accessibilityHint(т("fr_compare_hint"))
        .accessibilityAddTraits(включено ? .isSelected : [])
    }

    private var кнопкаОчистки: some View {
        Button {
            линейка.очистить()
        } label: {
            капсула(значок: "trash", текст: т("fr_clear"), включено: false)
                .opacity(естьЧтоУбрать ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .disabled(!естьЧтоУбрать)
        .accessibilityLabel(т("fr_clear_a11y"))
    }

    private func капсула(значок: String, текст: String, включено: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: значок)
                .font(.footnote.weight(.bold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(включено ? Color.black : Color.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(включено ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.5)),
                    in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.шапкаМята.opacity(включено ? 0 : 0.55), lineWidth: 1) }
        .contentShape(Capsule())
    }
}

// MARK: - Сравнение с вещью

/// Чипы «Авто · Ширина 60 · Высота 85 · Глубина 55 · Проём двери» и итог последнего отрезка.
struct КарточкаСравненияЛинейки: View {
    @ObservedObject var линейка: ЛинейкаГабаритов

    private func т(_ ключ: String) -> String { ЛинейкаГабаритовText.т(ключ) }

    var body: some View {
        let сравнение = линейка.сравнение
        VStack(alignment: .leading, spacing: 8) {
            чипы(сравнение)
            итог(сравнение)
            if let заметка = пояснение(сравнение) {
                Text(заметка)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(кайма(сравнение), lineWidth: 1)
        }
        .frame(maxWidth: 520)
    }

    private func чипы(_ сравнение: СравнениеЛинейки?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ГабаритСравненияЛинейки.allCases) { габарит in
                    чип(габарит, подсвечен: линейка.выбор == .авто && сравнение?.габарит == габарит)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func подписьЧипа(_ габарит: ГабаритСравненияЛинейки) -> String {
        let г = линейка.габариты
        switch габарит {
        case .авто:
            return т("fr_auto")
        case .ширина:
            return ГабаритыText.т("fb_w") + (г.map { " " + ГабаритыВещи.число($0.ширина) } ?? "")
        case .высота:
            return ГабаритыText.т("fb_h") + (г.map { " " + ГабаритыВещи.число($0.высота) } ?? "")
        case .глубина:
            return ГабаритыText.т("fb_d") + (г.map { " " + ГабаритыВещи.число($0.глубина) } ?? "")
        case .проём:
            return т("fr_door")
        }
    }

    /// Чип; подсвечен — его выбрал «Авто» (тонкая мятная кайма).
    private func чип(_ габарит: ГабаритСравненияЛинейки, подсвечен: Bool) -> some View {
        let выбран = линейка.выбор == габарит
        let подпись = подписьЧипа(габарит)
        return Button {
            guard !выбран else { return }
            ОткликСайта.выбор()
            линейка.выбор = габарит
        } label: {
            Text(подпись)
                .font(.footnote.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(выбран ? Color.black : Color.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(выбран ? AnyShapeStyle(Theme.шапкаМята) : AnyShapeStyle(Color.white.opacity(0.08)),
                            in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.шапкаМята.opacity(подсвечен ? 0.9 : (выбран ? 0 : 0.25)),
                                           lineWidth: подсвечен ? 1.5 : 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    @ViewBuilder
    private func итог(_ сравнение: СравнениеЛинейки?) -> some View {
        if let сравнение {
            Text(сравнение.строка)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(цвет(сравнение.итог))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(сравнение.озвучка)
            if сравнение.итог == .впритык {
                Text(т("fr_tight"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: ЛинейкаГабаритов.янтарь))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        } else {
            Text(т("fr_measure_first"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func пояснение(_ сравнение: СравнениеЛинейки?) -> String? {
        if линейка.выбор == .проём { return т("fr_door_note") }
        guard let сравнение, сравнение.авто else { return nil }
        let имя: String
        switch сравнение.габарит {
        case .высота: имя = т("fr_dim_h")
        case .глубина: имя = т("fr_dim_d")
        case .ширина, .авто, .проём: имя = т("fr_dim_w")
        }
        return ЛинейкаГабаритовText.т("fr_auto_note", имя)
    }

    private func цвет(_ итог: СравнениеЛинейки.Итог) -> Color {
        switch итог {
        case .хватает: return Color(uiColor: КоробкаГабаритов.зелёный)
        case .впритык: return Color(uiColor: ЛинейкаГабаритов.янтарь)
        case .неХватает: return Color(uiColor: ЛинейкаГабаритов.малиновый)
        }
    }

    private func кайма(_ сравнение: СравнениеЛинейки?) -> Color {
        guard let сравнение else { return Color.white.opacity(0.12) }
        return цвет(сравнение.итог).opacity(0.7)
    }
}

// MARK: - VoiceOver

/// Подпись и значение сцены: в линейке — «Камера с линейкой» и отрезки (ЛинейкаГабаритов.озвучка), в коробке — что
/// передал экран. Модификатор, а не ветвление: сцена (ARView) не пересоздаётся при смене режима.
struct ОзвучкаСценыЛинейкиГабаритов: ViewModifier {
    @ObservedObject var линейка: ЛинейкаГабаритов
    let включена: Bool
    let подписьКоробки: String
    let значениеКоробки: String

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(включена ? ЛинейкаГабаритовText.т("fr_scene_a11y") : подписьКоробки)
            .accessibilityValue(включена ? линейка.озвучка : значениеКоробки)
    }
}

// MARK: - Замер вещи для подачи

/// «Готово» в замере вещи («Измерить в AR» из подачи): есть хоть один отрезок — первые три уходят в поля Ш, В, Г.
struct КнопкаГотовоЗамераЛинейки: View {
    @ObservedObject var линейка: ЛинейкаГабаритов
    let готово: () -> Void

    var body: some View {
        let можно = линейка.отрезков > 0 && !линейка.снимаем
        Button {
            ОткликСайта.успех()
            готово()
        } label: {
            Text(ГабаритыText.т("fb_done"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(можно ? Color.black : Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(можно ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.45)),
                            in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.шапкаМята.opacity(можно ? 0 : 0.5), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .disabled(!можно)
        .accessibilityLabel(ГабаритыText.т("fb_done"))
        .accessibilityHint(ЛинейкаГабаритовText.т("fr_meas_done_a11y"))
    }
}
