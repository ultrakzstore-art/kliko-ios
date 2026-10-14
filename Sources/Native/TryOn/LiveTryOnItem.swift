import SwiftUI
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА — ШАГ «ВЕЩЬ» (владелец 14.10.2026: «через студию для примерочной должен обрезаться»).

 Перед камерой — короткий шаг: вещь с фото объявления, вырезанная тем же движком, что ИИ-студия подачи (ВырезкаПредмета,
 PhotoStudioEngine.swift), на шахматке — видно, где прозрачно, то есть что именно ляжет на лицо или руку. Пока режется —
 фото под вуалью и бегущая зелёная линия, как в студии (РазвёрткаСтудииФото); при «Уменьшении движения» — колесо на
 месте, без линии. Ниже — строка состояния, миниатюры фото объявления (если их больше одного), «Обрезать вручную» —
 рамка с уголками по фото (РамкаОбрезкиЖивойПримерки; вырезка — внутри неё), «Автоматически» — если вырезано по рамке, и
 «Примерить» — дальше камера, как было. Вырезка не вышла — честная строка и те же выходы: другое фото или рамка.

 Камера на этом шаге не работает: МодельЖивойПримерки запускает её только на этапе примерки. Тёмный всегда, как вся
 живая примерка; тексты растут с «Размером текста»; фото и рамка не зеркалятся в RTL, кнопки — зеркалятся.
 */
struct ШагВещиЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    let тихо: Bool
    let закрыть: () -> Void
    /// Открыта рамка «Обрезать вручную».
    @State private var правка = false
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(модель: МодельЖивойПримерки, тихо: Bool, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.тихо = тихо
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ВещьЖивойПримеркиText.т(ключ) }

    private func тж(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    private var готово: Bool { модель.вещь == .готово && !модель.вырезки.isEmpty }

    /// Фото не загрузилось по сети — вместо «Примерить» стоит «Повторить».
    private var повторНужен: Bool {
        if case .неВышло(_, повторить: true) = модель.вещь { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 0) {
                шапка
                if размерТекста.isAccessibilitySize {
                    /* Крупный текст: строка, миниатюры и кнопки выше экрана маленького iPhone — всё прокручивается,
                       карточке — постоянная высота, «Примерить» всегда достижима. */
                    ScrollView {
                        VStack(spacing: 0) {
                            карточка
                                .frame(height: 280)
                            низШага
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                } else {
                    карточка
                        .frame(minHeight: 140, maxHeight: .infinity)
                    низШага
                }
            }
            .frame(maxWidth: 560)
            .accessibilityHidden(правка)
            if правка, let исходник = модель.исходник {
                РамкаОбрезкиЖивойПримерки(картинка: исходник, начальная: начальнаяРамка, отмена: {
                    withAnimation(ДвижениеСайта.уход) { правка = false }
                    UIAccessibility.post(notification: .screenChanged, argument: nil)
                }, готово: { рамка in
                    withAnimation(ДвижениеСайта.уход) { правка = false }
                    модель.обрезатьВручную(рамка)
                })
                .transition(.opacity)
            }
        }
    }

    private var карточка: some View {
        КарточкаВещиЖивойПримерки(модель: модель, тихо: тихо)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }

    /// Под карточкой: строка состояния, миниатюры фото объявления и кнопки.
    private var низШага: some View {
        VStack(spacing: 0) {
            строкаСостояния
                .padding(.horizontal, 20)
                .padding(.top, 12)
            if модель.товар.фотоАдреса.count > 1 {
                ПолосаФотоЖивойПримерки(модель: модель)
                    .padding(.top, 10)
            }
            кнопки
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: тж("lt_close"), действие: закрыть)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(т("lw_title"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text(модель.вид.название)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // MARK: Состояние

    @ViewBuilder
    private var строкаСостояния: some View {
        switch модель.вещь {
        case .грузим:
            строка(значок: nil, текст: тж("lt_preparing"), цвет: Color.white)
        case .готово:
            строка(значок: "checkmark.circle.fill", текст: т(модель.ручная ? "lw_ready_manual" : "lw_ready"),
                   цвет: Theme.зелёныйЯркий)
        case .неВышло(let текст, let повторить):
            VStack(spacing: 6) {
                строка(значок: "exclamationmark.triangle.fill", текст: текст, цвет: Theme.оранжевый)
                if !повторить && модель.исходник != nil {
                    Text(т(модель.товар.фотоАдреса.count > 1 ? "lw_fail_hint" : "lw_fail_hint_one"))
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func строка(значок: String?, текст: String, цвет: Color) -> some View {
        HStack(spacing: 8) {
            if let значок {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(цвет)
                    .accessibilityHidden(true)
            } else {
                SiteSpinner(размер: 15, толщина: 2, дорожка: Color.white.opacity(0.2), верх: Theme.зелёныйЯркий,
                            стоит: тихо)
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .id(текст)
        .transition(.opacity)
    }

    // MARK: Кнопки

    private var кнопки: some View {
        VStack(spacing: 10) {
            if повторНужен {
                ЗелёнаяКнопкаФото(заголовок: тж("lt_retry"), значок: "arrow.clockwise") {
                    модель.повторить()
                }
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("lw_try"), значок: модель.вид.значок) {
                    модель.кПримерке()
                }
                .disabled(!готово)
                .opacity(готово ? 1 : 0.45)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { вторые }
                VStack(spacing: 10) { вторые }
            }
        }
    }

    @ViewBuilder
    private var вторые: some View {
        малаяКнопка(т("lw_crop"), значок: "crop", доступна: модель.исходник != nil) {
            ОткликСайта.выбор()
            withAnimation(ДвижениеСайта.появление) { правка = true }
        }
        if модель.ручная {
            малаяКнопка(т("lw_auto"), значок: "wand.and.stars", доступна: модель.вещь != .грузим) {
                модель.автоВырезка()
            }
        }
    }

    private func малаяКнопка(_ заголовок: String, значок: String, доступна: Bool,
                             действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .opacity(доступна ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото())
        .disabled(!доступна)
        .accessibilityLabel(заголовок)
    }

    /// Ручная рамка начинается там, где вещь нашлась (с запасом 4 %), прежняя ручная — как была; иначе — 80 % фото по
    /// центру.
    private var начальнаяРамка: CGRect {
        let поЦентру = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        guard let р = модель.рамкаВещи else { return поЦентру }
        if модель.ручная { return р }
        let с = р.insetBy(dx: -0.04, dy: -0.04).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return с.isNull || с.width < 0.08 || с.height < 0.08 ? поЦентру : с
    }
}

// MARK: - Карточка вещи

/// Шахматка (прозрачное), поверх — вырезанная вещь (у серёг — обе); пока режется — фото под вуалью и бегущая линия.
struct КарточкаВещиЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    let тихо: Bool

    init(модель: МодельЖивойПримерки, тихо: Bool) {
        self.модель = модель
        self.тихо = тихо
    }

    private var режем: Bool { модель.вещь == .грузим }
    private var готово: Bool { модель.вещь == .готово && !модель.вырезки.isEmpty }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        ZStack {
            ШахматкаЖивойПримерки()
            if !готово, let исходник = модель.исходник {
                фото(исходник)
                    .transition(.opacity)
            }
            if готово {
                вырезанное
                    .padding(24)
                    .transition(тихо ? AnyTransition.opacity : AnyTransition.scale(scale: 0.88).combined(with: .opacity))
            }
            if режем && (тихо || модель.исходник == nil) {
                SiteSpinner(размер: 30, толщина: 3, дорожка: Color.white.opacity(0.2), верх: Theme.зелёныйЯркий,
                            стоит: тихо)
            }
            if !готово && !режем {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(форма)
        .overlay { форма.strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(.isImage)
    }

    /// Исходное фото под вуалью; пока режется — с бегущей линией (как в студии), без неё при «Уменьшении движения».
    private func фото(_ исходник: UIImage) -> some View {
        Image(uiImage: исходник)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .opacity(режем ? 0.5 : 0.28)
            .overlay {
                if режем && !тихо {
                    РазвёрткаСтудииФото(цвет: Theme.зелёныйЯркий)
                }
            }
            .clipped()
            .padding(12)
    }

    @ViewBuilder
    private var вырезанное: some View {
        if модель.вырезки.count >= 2 {
            HStack(spacing: 20) {
                ForEach(Array(модель.вырезки.prefix(2).enumerated()), id: \.offset) { _, кусок in
                    Image(uiImage: кусок)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
            .shadow(color: Theme.зелёныйЯркий.opacity(0.3), radius: 12)
        } else if let одна = модель.вырезки.first {
            Image(uiImage: одна)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: Theme.зелёныйЯркий.opacity(0.3), radius: 12)
        }
    }

    private var подпись: String {
        switch модель.вещь {
        case .грузим:
            return ЖиваяПримеркаText.т("lt_preparing")
        case .готово:
            return String(format: ВещьЖивойПримеркиText.т("lw_card_a11y"), модель.вид.название)
        case .неВышло(let текст, _):
            return текст
        }
    }
}

/// Шахматка под вырезкой: видно, где прозрачно. Тёмные клетки — экран всегда тёмный.
struct ШахматкаЖивойПримерки: View {
    var клетка: CGFloat = 14

    var body: some View {
        Canvas { холст, размер in
            холст.fill(Path(CGRect(origin: .zero, size: размер)), with: .color(Color(white: 0.15)))
            guard клетка > 1, размер.width > 0, размер.height > 0 else { return }
            let столбцы = Int((размер.width / клетка).rounded(.up))
            let строки = Int((размер.height / клетка).rounded(.up))
            var путь = Path()
            for строка in 0..<строки {
                for столбец in 0..<столбцы where (строка + столбец) % 2 == 0 {
                    путь.addRect(CGRect(x: CGFloat(столбец) * клетка, y: CGFloat(строка) * клетка, width: клетка,
                                        height: клетка))
                }
            }
            холст.fill(путь, with: .color(Color(white: 0.22)))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Рамка «Обрезать вручную»

/**
 «Обрезать вручную»: фото вещи целиком и рамка поверх — четыре уголка тянутся пальцем, рамка двигается за середину, вне
 рамки — затемнение. «Обрезать» отдаёт рамку в долях фото (начало сверху слева); внутри неё МодельЖивойПримерки пробует
 вырезку студии, иначе берёт рамку как есть. VoiceOver: рамка — регулируемый элемент (смахнуть вверх или вниз — больше
 или меньше) и действия «Сдвинуть влево, вправо, вверх, вниз»; «Отмена» — и жестом выхода. Фото и рамка не зеркалятся в
 RTL.
 */
struct РамкаОбрезкиЖивойПримерки: View {
    let картинка: UIImage
    let отмена: () -> Void
    let готово: (CGRect) -> Void
    /// Рамка в долях фото, начало сверху слева.
    @State private var рамка: CGRect
    /// Рамка в начале жеста: тянем от неё, а не копим ошибку по шагам.
    @State private var начало: CGRect? = nil

    /// Наименьшая сторона рамки — доля фото.
    private static let наименьшая: CGFloat = 0.08

    private enum Угол: CaseIterable {
        case левыйВерх, правыйВерх, левыйНиз, правыйНиз
    }

    init(картинка: UIImage, начальная: CGRect, отмена: @escaping () -> Void, готово: @escaping (CGRect) -> Void) {
        self.картинка = картинка
        self.отмена = отмена
        self.готово = готово
        _рамка = State(initialValue: Self.поправить(начальная))
    }

    private func т(_ ключ: String) -> String { ВещьЖивойПримеркиText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.97)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                /* Крупный текст не съедает холст: подсказка растёт до AX2, фото с рамкой — не меньше 200 pt. */
                заголовок
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                холст
                    .padding(20)
                    .frame(minHeight: 200, maxHeight: .infinity)
                кнопки
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 560)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { отмена() }
    }

    private var заголовок: some View {
        VStack(spacing: 6) {
            Text(т("lw_crop"))
                .font(.headline)
                .foregroundStyle(Color.white)
                .accessibilityAddTraits(.isHeader)
            Text(т("lw_crop_hint"))
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var кнопки: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { парыКнопок }
            VStack(spacing: 10) { парыКнопок }
        }
    }

    @ViewBuilder
    private var парыКнопок: some View {
        ЗелёнаяКнопкаФото(заголовок: т("lw_cancel"), значок: "xmark", контурная: true, наТёмном: true, действие: отмена)
        ЗелёнаяКнопкаФото(заголовок: т("lw_crop_apply"), значок: "crop") {
            ОткликСайта.выбор()
            готово(рамка)
        }
    }

    // MARK: Фото и рамка

    private var холст: some View {
        GeometryReader { г in
            let место = Self.вписать(картинка.size, в: г.size)
            let э = CGRect(x: место.minX + рамка.minX * место.width, y: место.minY + рамка.minY * место.height,
                           width: рамка.width * место.width, height: рамка.height * место.height)
            ZStack(alignment: .topLeading) {
                Image(uiImage: картинка)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: max(1, место.width), height: max(1, место.height))
                    .position(x: место.midX, y: место.midY)
                    .accessibilityHidden(true)
                Path { путь in
                    путь.addRect(место)
                    путь.addRect(э)
                }
                .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                видРамки(э, место: место)
                ForEach(Угол.allCases, id: \.self) { угол in
                    уголок(угол, э: э, место: место)
                }
            }
            .frame(width: г.size.width, height: г.size.height)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Рамка: белая кромка, сетка третей, зелёные уголки; середину тянут — рамка едет. Для VoiceOver — один элемент.
    private func видРамки(_ э: CGRect, место: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
            СеткаОбрезкиЖивойПримерки()
            УголкиПоискаФото(длина: max(8, min(26, min(э.width, э.height) / 3)), цвет: Theme.зелёныйЯркий, толщина: 4)
        }
        .frame(width: max(1, э.width), height: max(1, э.height))
        .contentShape(Rectangle())
        .gesture(сдвиг(место))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("lw_frame"))
        .accessibilityValue(String(format: т("lw_frame_value"), Int((рамка.width * 100).rounded()),
                                   Int((рамка.height * 100).rounded())))
        .accessibilityHint(т("lw_frame_hint"))
        .accessibilityAdjustableAction { куда in
            switch куда {
            case .increment:
                изменить(на: 0.1)
            case .decrement:
                изменить(на: -0.1)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text(т("lw_move_left"))) { подвинуть(-0.05, 0) }
        .accessibilityAction(named: Text(т("lw_move_right"))) { подвинуть(0.05, 0) }
        .accessibilityAction(named: Text(т("lw_move_up"))) { подвинуть(0, -0.05) }
        .accessibilityAction(named: Text(т("lw_move_down"))) { подвинуть(0, 0.05) }
        .position(x: э.midX, y: э.midY)
    }

    /// Уголок: зелёный кружок 20 pt, место для пальца — 44 pt.
    private func уголок(_ угол: Угол, э: CGRect, место: CGRect) -> some View {
        let точка: CGPoint
        switch угол {
        case .левыйВерх: точка = CGPoint(x: э.minX, y: э.minY)
        case .правыйВерх: точка = CGPoint(x: э.maxX, y: э.minY)
        case .левыйНиз: точка = CGPoint(x: э.minX, y: э.maxY)
        case .правыйНиз: точка = CGPoint(x: э.maxX, y: э.maxY)
        }
        return Circle()
            .fill(Theme.зелёныйЯркий)
            .frame(width: 20, height: 20)
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
            .shadow(color: Color.black.opacity(0.4), radius: 3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .gesture(тянуть(угол, место: место))
            .accessibilityHidden(true)
            .position(точка)
    }

    // MARK: Жесты

    private func тянуть(_ угол: Угол, место: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { ход in
                let исходная = начало ?? рамка
                if начало == nil { начало = рамка }
                let dx = ход.translation.width / max(1, место.width)
                let dy = ход.translation.height / max(1, место.height)
                рамка = Self.сУглом(угол, исходная, dx, dy)
            }
            .onEnded { _ in начало = nil }
    }

    private func сдвиг(_ место: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { ход in
                let исходная = начало ?? рамка
                if начало == nil { начало = рамка }
                var р = исходная
                р.origin.x = исходная.minX + ход.translation.width / max(1, место.width)
                р.origin.y = исходная.minY + ход.translation.height / max(1, место.height)
                рамка = Self.поправить(р)
            }
            .onEnded { _ in начало = nil }
    }

    /// VoiceOver: больше или меньше на долю вокруг середины.
    private func изменить(на доля: CGFloat) {
        let ш = рамка.width * (1 + доля)
        let в = рамка.height * (1 + доля)
        рамка = Self.поправить(CGRect(x: рамка.midX - ш / 2, y: рамка.midY - в / 2, width: ш, height: в))
    }

    private func подвинуть(_ dx: CGFloat, _ dy: CGFloat) {
        рамка = Self.поправить(рамка.offsetBy(dx: dx, dy: dy))
    }

    // MARK: Расчёт

    /// Где фото размера `размер` стоит в месте `место` целиком (по центру, без обрезки).
    private static func вписать(_ размер: CGSize, в место: CGSize) -> CGRect {
        guard размер.width > 0, размер.height > 0, место.width > 0, место.height > 0 else {
            return CGRect(origin: .zero, size: место)
        }
        let к = min(место.width / размер.width, место.height / размер.height)
        let ш = размер.width * к
        let в = размер.height * к
        return CGRect(x: (место.width - ш) / 2, y: (место.height - в) / 2, width: ш, height: в)
    }

    /// Уголок ушёл на dx, dy (доли фото): противоположный стоит, рамка не меньше наименьшей и не за краем фото.
    private static func сУглом(_ угол: Угол, _ и: CGRect, _ dx: CGFloat, _ dy: CGFloat) -> CGRect {
        let м = наименьшая
        var лево = и.minX
        var верх = и.minY
        var право = и.maxX
        var низ = и.maxY
        switch угол {
        case .левыйВерх:
            лево = min(max(0, лево + dx), право - м)
            верх = min(max(0, верх + dy), низ - м)
        case .правыйВерх:
            право = max(min(1, право + dx), лево + м)
            верх = min(max(0, верх + dy), низ - м)
        case .левыйНиз:
            лево = min(max(0, лево + dx), право - м)
            низ = max(min(1, низ + dy), верх + м)
        case .правыйНиз:
            право = max(min(1, право + dx), лево + м)
            низ = max(min(1, низ + dy), верх + м)
        }
        return CGRect(x: лево, y: верх, width: право - лево, height: низ - верх)
    }

    /// В пределах фото и не меньше наименьшей: сначала размер, потом сдвиг внутрь.
    private static func поправить(_ р: CGRect) -> CGRect {
        let ш = min(1, max(наименьшая, р.width.isFinite ? р.width : 0.8))
        let в = min(1, max(наименьшая, р.height.isFinite ? р.height : 0.8))
        let x = min(max(0, р.minX.isFinite ? р.minX : 0.1), 1 - ш)
        let y = min(max(0, р.minY.isFinite ? р.minY : 0.1), 1 - в)
        return CGRect(x: x, y: y, width: ш, height: в)
    }
}

/// Сетка третей внутри рамки обрезки — тонкие белые линии.
struct СеткаОбрезкиЖивойПримерки: View {
    var body: some View {
        Canvas { холст, размер in
            var путь = Path()
            for доля in [CGFloat(1) / 3, CGFloat(2) / 3] {
                путь.move(to: CGPoint(x: размер.width * доля, y: 0))
                путь.addLine(to: CGPoint(x: размер.width * доля, y: размер.height))
                путь.move(to: CGPoint(x: 0, y: размер.height * доля))
                путь.addLine(to: CGPoint(x: размер.width, y: размер.height * доля))
            }
            холст.stroke(путь, with: .color(Color.white.opacity(0.35)), lineWidth: 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
