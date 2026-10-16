import SwiftUI
import PhotosUI
import UIKit

/**
 ПРИМЕРОЧНАЯ — ШАГ 1 «ВАШЕ ФОТО»: живая камера с контуром человека (владелец 13.10.2026).

 Камера — та же, что у поиска по фото (КамераПоиска и ПревьюКамерыПоиска, PhotoSearchCamera.swift): своя очередь, доступ
 спрашивается при первом показе, фонарик и смена камеры. Поверх — контур человека в полный рост (пунктир со свечением,
 «дышит», сверху вниз бежит линия сканера) и три совета, которые выезжают по очереди: «В полный рост», «Светло»,
 «Однотонный фон». Внизу — «Галерея» (PhotosPicker), большой затвор и «Другая камера»; сверху — ✕ и таймер 3 с (чтобы
 снять себя на переднюю камеру с вытянутой руки или со штатива — крупный отсчёт 3-2-1). Нет доступа или камеры — заглушка
 с «Выбрать из галереи» (и «Открыть Настройки»). При «Уменьшении движения» всё неподвижно.

 Вид примерки (модель.вид, ВидИИПримерки) меняет контур, советы и заголовок: «На свою машину» — силуэт машины сбоку с
 колёсами («Машина боком», «Колёса целиком», «Светло»), «В моей комнате» — рамка комнаты с местом на полу («Угол или
 стена», «Светло», «Без людей»). У машины и комнаты — только задняя камера (с неё камера и начинает) и без таймера: себя
 там снимать не нужно.
 */
struct ШагСъёмкиПримерочной: View {
    @ObservedObject var модель: МодельПримерочной
    @ObservedObject var камера: КамераПоиска
    let закрыть: () -> Void
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.scenePhase) private var фаза
    @State private var выбор: PhotosPickerItem? = nil
    @State private var галерея = false
    @State private var вспышка = false
    @State private var таймер = false
    @State private var отсчёт: Int? = nil
    @State private var задачаОтсчёта: Task<Void, Never>? = nil
    @State private var виден = false
    @State private var вФоне = false

    private static let ширинаКнопки: CGFloat = 88

    init(модель: МодельПримерочной, камера: КамераПоиска, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.камера = камера
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    /// Без движения: «Уменьшение движения» или лёгкий режим (РежимУстройства) — камера и так нагружает телефон.
    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо || РежимУстройства.сейчас }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            фон
            Color.white
                .opacity(вспышка ? 0.8 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            if let отсчёт {
                Text(String(отсчёт))
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: Theme.зелёныйЯркий.opacity(0.9), radius: 24)
                    .id(отсчёт)
                    .transition(тихо ? AnyTransition.opacity
                                     : AnyTransition.scale(scale: 1.6).combined(with: AnyTransition.opacity))
                    .accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                верх
                if живая {
                    советы
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                }
                Spacer(minLength: 12)
                if живая {
                    подсказка
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                }
                низ
            }
            if модель.готовим {
                ZStack {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        SiteSpinner(размер: 34, толщина: 3.5, дорожка: Color.white.opacity(0.15),
                                    верх: Theme.зелёныйЯркий)
                        Text(т("to_preparing"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity)
            }
        }
        .photosPicker(isPresented: $галерея, selection: $выбор, matching: .images)
        .onChange(of: выбор) { _, новый in загрузить(новый) }
        .onAppear {
            виден = true
            камера.запустить()
        }
        .onDisappear {
            виден = false
            задачаОтсчёта?.cancel()
            задачаОтсчёта = nil
            отсчёт = nil
            камера.остановить()
        }
        .onChange(of: фаза) { _, новая in
            guard виден else { return }
            switch новая {
            case .background:
                вФоне = true
                задачаОтсчёта?.cancel()
                отсчёт = nil
                камера.остановить()
            case .active:
                guard вФоне else { return }
                вФоне = false
                камера.запустить()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }

    // MARK: Фон: превью и контур, или заглушка

    @ViewBuilder
    private var фон: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ПревьюКамерыПоиска(камера: камера)
                .ignoresSafeArea()
                .opacity(камера.готова ? 1 : 0)
                .animation(ДвижениеСайта.появление, value: камера.готова)
                .accessibilityHidden(true)
            КонтурПримерочной(тихо: тихо, вид: модель.вид)
                .padding(.top, 130)
                .padding(.bottom, 200)
                .padding(.horizontal, 24)
                .allowsHitTesting(false)
        case .запрещён:
            заглушка(заголовок: т("to_denied"), текст: т("to_denied_hint"), настройки: true)
        case .нетКамеры:
            заглушка(заголовок: т("to_no_cam"), текст: модель.вид.безКамеры, настройки: false)
        }
    }

    // MARK: Верх: ✕, заголовок, таймер

    private var верх: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("to_close"), действие: закрыть)
            Spacer(minLength: 0)
            Text(модель.вид.заголовок)
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(color: Color.black.opacity(0.5), radius: 3)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if живая && модель.вид == .человек {
                КруглаяКнопкаФото(значок: "timer", подпись: т("to_timer"), активна: таймер) {
                    ОткликСайта.выбор()
                    таймер.toggle()
                    UIAccessibility.post(notification: .announcement, argument: т(таймер ? "to_timer_on" : "to_timer_off"))
                }
                .accessibilityValue(т(таймер ? "to_timer_on" : "to_timer_off"))
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    /// Три совета — фишками, выезжают по очереди; не влезают в строку — столбиком.
    private var советы: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { фишки }
            VStack(spacing: 6) { фишки }
        }
    }

    /// Советы вида: у человека — «В полный рост», «Светло», «Однотонный фон»; у машины и комнаты — свои.
    private var фишки: some View {
        ForEach(Array(модель.вид.советы.enumerated()), id: \.offset) { пара in
            ФишкаСоветаПримерочной(значок: пара.element.значок, текст: пара.element.текст, номер: пара.offset,
                                   тихо: тихо)
        }
    }

    private var подсказка: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .accessibilityHidden(true)
            Text(модель.вид.подсказкаКамеры)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
    }

    // MARK: Низ: «Галерея», затвор, «Другая камера»

    private var низ: some View {
        HStack(alignment: .top, spacing: 0) {
            кнопкаНиза(значок: "photo.on.rectangle", подпись: т("to_gallery"), доступна: true) { галерея = true }
            Spacer(minLength: 8)
            затвор
            Spacer(minLength: 8)
            if живая && камера.естьПередняя && модель.вид == .человек {
                кнопкаНиза(значок: "arrow.triangle.2.circlepath.camera", подпись: т("to_flip"), доступна: камера.готова) {
                    ОткликСайта.выбор()
                    камера.переключитьКамеру()
                }
            } else {
                Color.clear
                    .frame(width: Self.ширинаКнопки, height: 1)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.65)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func подписьКнопки(_ текст: String) -> some View {
        Text(текст)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .shadow(color: Color.black.opacity(0.6), radius: 2)
    }

    private func кнопкаНиза(значок: String, подпись: String, доступна: Bool,
                            действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5) }
                    .frame(height: 80)
                подписьКнопки(подпись)
            }
            .frame(width: Self.ширинаКнопки)
            .contentShape(Rectangle())
            .opacity(доступна ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .disabled(!доступна)
        .accessibilityLabel(подпись)
    }

    /// Большой затвор: белое кольцо и круг; во время снимка и отсчёта круг зеленеет.
    private var затвор: some View {
        Button { нажатьЗатвор() } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(камера.снимаем || отсчёт != nil ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 64, height: 64)
                    if таймер {
                        Image(systemName: "timer")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }
                подписьКнопки(т("to_shoot"))
            }
            .frame(width: 96)
            .contentShape(Rectangle())
            .opacity(камера.готова ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!камера.готова || камера.снимаем || отсчёт != nil || модель.готовим)
        .accessibilityLabel(т("to_shoot_a11y"))
        .accessibilityValue(таймер ? т("to_timer_on") : "")
    }

    // MARK: Действия

    private func нажатьЗатвор() {
        guard камера.готова, !камера.снимаем, отсчёт == nil else { return }
        guard таймер else {
            снять()
            return
        }
        задачаОтсчёта?.cancel()
        задачаОтсчёта = Task { @MainActor in
            for число in [3, 2, 1] {
                withAnimation(тихо ? nil : .spring(response: 0.32, dampingFraction: 0.68)) { отсчёт = число }
                UISelectionFeedbackGenerator().selectionChanged()
                UIAccessibility.post(notification: .announcement, argument: String(число))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled {
                    отсчёт = nil
                    return
                }
            }
            withAnimation(тихо ? nil : .easeOut(duration: 0.15)) { отсчёт = nil }
            снять()
        }
    }

    private func снять() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !тихо {
            вспышка = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeOut(duration: 0.3)) { вспышка = false }
            }
        }
        камера.снять { снимок in
            модель.принять(снимок)
        }
    }

    private func загрузить(_ элемент: PhotosPickerItem?) {
        guard let элемент else { return }
        выбор = nil
        Task { @MainActor in
            guard let данные = try? await элемент.loadTransferable(type: Data.self) else {
                модель.показатьВесть(т("to_bad_image"))
                return
            }
            модель.принять(данные: данные)
        }
    }

    /// Нет доступа или камеры: значок, объяснение, «Выбрать из галереи» и (если запрещено) «Открыть Настройки».
    private func заглушка(заголовок: String, текст: String, настройки: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: модель.вид.значок)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .frame(width: 80, height: 80)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                ЗелёнаяКнопкаФото(заголовок: т("to_pick"), значок: "photo.on.rectangle") {
                    галерея = true
                }
                .padding(.bottom, 10)
                if настройки {
                    ЗелёнаяКнопкаФото(заголовок: т("to_settings"), значок: "gearshape", контурная: true,
                                      наТёмном: true) {
                        if let адрес = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(адрес)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 120)
            .padding(.bottom, 140)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Совет фишкой

/// Совет над камерой: значок и слово на тёмной капсуле; выезжает сверху с задержкой по номеру.
struct ФишкаСоветаПримерочной: View {
    let значок: String
    let текст: String
    let номер: Int
    let тихо: Bool
    @State private var видна = false

    init(значок: String, текст: String, номер: Int, тихо: Bool) {
        self.значок = значок
        self.текст = текст
        self.номер = номер
        self.тихо = тихо
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: значок)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .accessibilityHidden(true)
            Text(текст)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.5), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1) }
        .opacity(видна ? 1 : 0)
        .offset(y: видна ? 0 : -10)
        .onAppear {
            guard !видна else { return }
            if тихо {
                видна = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.25 + Double(номер) * 0.15)) {
                    видна = true
                }
            }
        }
    }
}

// MARK: - Контур

/// Контур поверх камеры: человек в полный рост, машина сбоку или рамка комнаты — мягкое зелёное свечение, белый
/// пунктир, тихое «дыхание» и линия сканера, бегущая сверху вниз только внутри фигуры. При «Уменьшении движения» —
/// неподвижен.
struct КонтурПримерочной: View {
    let тихо: Bool
    let вид: ВидИИПримерки
    @State private var дышит = false
    @State private var бег = false

    init(тихо: Bool, вид: ВидИИПримерки = .человек) {
        self.тихо = тихо
        self.вид = вид
    }

    private var фигура: AnyShape {
        switch вид {
        case .человек: return AnyShape(СилуэтПримерочной())
        case .машина: return AnyShape(СилуэтМашиныПримерочной())
        case .комната: return AnyShape(РамкаКомнатыПримерочной())
        }
    }

    /// Где бежит линия сканера: внутри человека или машины, у комнаты — во всей рамке.
    private var маска: AnyShape {
        вид == .комната ? AnyShape(Rectangle()) : фигура
    }

    private func местоФигуры(в место: CGSize) -> CGRect {
        switch вид {
        case .человек: return СилуэтПримерочной.рамка(в: место)
        case .машина: return СилуэтМашиныПримерочной.рамка(в: место)
        case .комната: return РамкаКомнатыПримерочной.рамка(в: место)
        }
    }

    var body: some View {
        GeometryReader { место in
            let рамка = местоФигуры(в: место.size)
            ZStack {
                if тихо {
                    /* Без движения — и ореол без размытия: blur над живой камерой пересчитывается на каждом её кадре. */
                    фигура
                        .stroke(Theme.зелёныйЯркий.opacity(0.3),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                } else {
                    фигура
                        .stroke(Theme.зелёныйЯркий.opacity(0.45),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .blur(radius: 7)
                }
                фигура
                    .stroke(Color.white.opacity(0.92),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [9, 7]))
                if !тихо {
                    LinearGradient(colors: [Theme.зелёныйЯркий.opacity(0), Theme.зелёныйЯркий.opacity(0.55),
                                            Color.white.opacity(0.9)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 34)
                        .offset(y: бег ? рамка.height / 2 : -рамка.height / 2)
                        .frame(width: рамка.width, height: рамка.height)
                        .mask { маска.fill(Color.white) }
                        .opacity(0.8)
                }
            }
            .frame(width: рамка.width, height: рамка.height)
            .scaleEffect(дышит ? 1.02 : 1)
            .position(x: рамка.midX, y: рамка.midY)
        }
        .onAppear {
            guard !тихо else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { дышит = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { бег = true }
        }
        .accessibilityHidden(true)
    }
}

/**
 Фигура человека в поле 100 × 240: голова — овал, шея, плечи, руки вдоль тела, туловище, ноги. Правая половина идёт от
 шеи вниз до шага, левая — зеркально обратно к шее (у обратной кривой контрольная точка та же, только отражена).
 */
struct СилуэтПримерочной: Shape {
    /// Ширина к высоте поля рисунка.
    static let пропорция: CGFloat = 100.0 / 240.0

    /// Место контура в поле `место`: вся высота (или вся ширина, если поле узкое), по центру.
    static func рамка(в место: CGSize) -> CGRect {
        let высота = max(0, min(место.height, место.width / пропорция))
        let ширина = высота * пропорция
        return CGRect(x: (место.width - ширина) / 2, y: (место.height - высота) / 2, width: ширина, height: высота)
    }

    func path(in rect: CGRect) -> Path {
        let мx = rect.width / 100
        let мy = rect.height / 240
        func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * мx, y: rect.minY + y * мy) }
        var путь = Path()
        путь.addEllipse(in: CGRect(x: rect.minX + 37 * мx, y: rect.minY + 6 * мy, width: 26 * мx, height: 32 * мy))
        /* правая половина: шея → плечо → рука → кисть → внутренняя сторона руки → бок → нога → стопа → шаг */
        путь.move(to: т(56, 38))
        путь.addLine(to: т(57, 45))
        путь.addQuadCurve(to: т(77, 52), control: т(64, 46))
        путь.addQuadCurve(to: т(85, 108), control: т(88, 60))
        путь.addLine(to: т(84, 130))
        путь.addQuadCurve(to: т(76, 130), control: т(80, 137))
        путь.addLine(to: т(76, 106))
        путь.addQuadCurve(to: т(71, 68), control: т(76, 80))
        путь.addLine(to: т(70, 128))
        путь.addQuadCurve(to: т(65, 226), control: т(73, 176))
        путь.addLine(to: т(67, 236))
        путь.addLine(to: т(53, 236))
        путь.addLine(to: т(54, 224))
        путь.addQuadCurve(to: т(50, 136), control: т(54, 170))
        /* левая половина — зеркально, от шага обратно к шее */
        путь.addQuadCurve(to: т(46, 224), control: т(46, 170))
        путь.addLine(to: т(47, 236))
        путь.addLine(to: т(33, 236))
        путь.addLine(to: т(35, 226))
        путь.addQuadCurve(to: т(30, 128), control: т(27, 176))
        путь.addLine(to: т(29, 68))
        путь.addQuadCurve(to: т(24, 106), control: т(24, 80))
        путь.addLine(to: т(24, 130))
        путь.addQuadCurve(to: т(16, 130), control: т(20, 137))
        путь.addLine(to: т(15, 108))
        путь.addQuadCurve(to: т(23, 52), control: т(12, 60))
        путь.addQuadCurve(to: т(43, 45), control: т(36, 46))
        путь.addLine(to: т(44, 38))
        return путь
    }
}

/**
 Машина сбоку в поле 240 × 104: кузов от заднего бампера по крыше к переднему, низ с двумя арками, окна и линия двери,
 два колеса со ступицами — колёса и есть то, что поменяет ИИ, поэтому они обведены целиком.
 */
struct СилуэтМашиныПримерочной: Shape {
    /// Ширина к высоте поля рисунка.
    static let пропорция: CGFloat = 240.0 / 104.0

    /// Место контура в поле `место`: вся ширина (или вся высота, если поле низкое), по центру.
    static func рамка(в место: CGSize) -> CGRect {
        let ширина = max(0, min(место.width, место.height * пропорция))
        let высота = ширина / пропорция
        return CGRect(x: (место.width - ширина) / 2, y: (место.height - высота) / 2, width: ширина, height: высота)
    }

    func path(in rect: CGRect) -> Path {
        let мx = rect.width / 240
        let мy = rect.height / 104
        func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * мx, y: rect.minY + y * мy) }
        func круг(_ x: CGFloat, _ y: CGFloat, _ р: CGFloat) -> CGRect {
            CGRect(x: rect.minX + (x - р) * мx, y: rect.minY + (y - р) * мy, width: 2 * р * мx, height: 2 * р * мy)
        }
        var путь = Path()
        /* кузов: задний бампер → багажник → заднее стекло → крыша → лобовое → капот → передний бампер → низ с арками */
        путь.move(to: т(6, 78))
        путь.addLine(to: т(4, 60))
        путь.addQuadCurve(to: т(16, 46), control: т(4, 48))
        путь.addLine(to: т(58, 42))
        путь.addQuadCurve(to: т(88, 18), control: т(70, 22))
        путь.addLine(to: т(150, 16))
        путь.addQuadCurve(to: т(180, 40), control: т(168, 18))
        путь.addLine(to: т(222, 48))
        путь.addQuadCurve(to: т(236, 62), control: т(234, 50))
        путь.addLine(to: т(236, 78))
        путь.addLine(to: т(214, 78))
        путь.addQuadCurve(to: т(166, 78), control: т(190, 44))
        путь.addLine(to: т(78, 78))
        путь.addQuadCurve(to: т(30, 78), control: т(54, 44))
        путь.closeSubpath()
        /* окна и дверь */
        путь.move(to: т(70, 40))
        путь.addQuadCurve(to: т(92, 22), control: т(78, 26))
        путь.addLine(to: т(146, 21))
        путь.addQuadCurve(to: т(170, 40), control: т(160, 24))
        путь.closeSubpath()
        путь.move(to: т(122, 22))
        путь.addLine(to: т(122, 74))
        /* колёса и ступицы */
        путь.addEllipse(in: круг(54, 82, 17))
        путь.addEllipse(in: круг(54, 82, 7))
        путь.addEllipse(in: круг(190, 82, 17))
        путь.addEllipse(in: круг(190, 82, 7))
        return путь
    }
}

/**
 Рамка комнаты в поле 100 × 120: дальняя стена прямоугольником, от её углов к углам кадра — линии пола, потолка и
 стен (как внутри коробки), на полу — овал, куда встанет вещь.
 */
struct РамкаКомнатыПримерочной: Shape {
    /// Ширина к высоте поля рисунка.
    static let пропорция: CGFloat = 100.0 / 120.0

    /// Место рамки в поле `место`: вся высота (или вся ширина, если поле узкое), по центру.
    static func рамка(в место: CGSize) -> CGRect {
        let высота = max(0, min(место.height, место.width / пропорция))
        let ширина = высота * пропорция
        return CGRect(x: (место.width - ширина) / 2, y: (место.height - высота) / 2, width: ширина, height: высота)
    }

    func path(in rect: CGRect) -> Path {
        let мx = rect.width / 100
        let мy = rect.height / 120
        func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * мx, y: rect.minY + y * мy) }
        var путь = Path()
        /* дальняя стена */
        путь.move(to: т(24, 16))
        путь.addLine(to: т(76, 16))
        путь.addLine(to: т(76, 76))
        путь.addLine(to: т(24, 76))
        путь.closeSubpath()
        /* рёбра комнаты к углам кадра */
        путь.move(to: т(24, 16))
        путь.addLine(to: т(2, 2))
        путь.move(to: т(76, 16))
        путь.addLine(to: т(98, 2))
        путь.move(to: т(24, 76))
        путь.addLine(to: т(2, 118))
        путь.move(to: т(76, 76))
        путь.addLine(to: т(98, 118))
        /* место вещи на полу */
        путь.addEllipse(in: CGRect(x: rect.minX + 28 * мx, y: rect.minY + 89 * мy, width: 44 * мx, height: 14 * мy))
        return путь
    }
}
