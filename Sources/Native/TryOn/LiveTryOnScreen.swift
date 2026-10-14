import SwiftUI
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА — ЭКРАН (владелец 13.10.2026: «нужнее охват всего»; 14.10.2026: «через студию для примерочной должен
 обрезаться»).

 Во весь экран и всегда тёмный, как камера примерочной. Сначала — шаг «Вещь» (LiveTryOnItem.swift): вещь, вырезанная
 движком ИИ-студии, на шахматке, миниатюры фото объявления, «Обрезать вручную» и «Примерить»; камера на нём не работает.
 Дальше — живая камера (передняя для лица, задняя для руки), поверх — вещь, которая едет за лицом или рукой. Сверху — ✕,
 «Живая примерка · Очки» и «Сбросить подгонку» (если вещь подгоняли); под ними — подсказка («Смотрите прямо в камеру»,
 «Поднесите руку ближе», один раз — как подгонять жестами). Снизу — «Фото вещи» (обратно к шагу «Вещь»), затвор
 «Снимок» и «Другая камера». Подгонка — щипок (размер), два пальца (поворот), палец (сдвиг); VoiceOver — регулируемый
 элемент (смахнуть вверх/вниз — размер) и действия «Повернуть», «Сбросить подгонку». Снимок — поверх: «Сохранить в
 Фото», «Поделиться», «Ещё снимок».

 Камера стоит, когда экран закрыт и когда приложение в фоне. Слой камеры и вещи не зеркалится в RTL (его координаты —
 координаты кадра), кнопки — зеркалятся. «Уменьшение движения» — вещь переставляется без доводки между кадрами, без
 полётов подсказок; тексты растут с «Размером текста».
 */
struct ЭкранЖивойПримерки: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельЖивойПримерки

    init(товар: Listing, вид: ВидЖивойПримерки, фото: Int, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельЖивойПримерки(товар: товар, вид: вид, фото: фото))
    }

    var body: some View {
        СтудияЖивойПримерки(модель: модель, камера: модель.камера, закрыть: закрыть)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Студия

struct СтудияЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    @ObservedObject var камера: КамераЖивойПримерки
    let закрыть: () -> Void
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.scenePhase) private var фаза
    @State private var виден = false

    private static let ширинаКнопки: CGFloat = 88

    init(модель: МодельЖивойПримерки, камера: КамераЖивойПримерки, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.камера = камера
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if модель.этап == .вещь {
                ШагВещиЖивойПримерки(модель: модель, тихо: тихо, закрыть: закрыть)
                    .transition(.opacity)
            } else {
                фон
                управление
            }
            if let снимок = модель.снимок {
                ЛистСнимкаЖивойПримерки(модель: модель, снимок: снимок)
                    .transition(.opacity)
            }
            if let весть = модель.весть {
                ВестьЖивойПримерки(текст: весть)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 150)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear {
            виден = true
            модель.открыт()
        }
        .onDisappear {
            виден = false
            модель.закрыть()
        }
        .onChange(of: фаза) { _, новая in
            guard виден else { return }
            switch новая {
            case .background:
                модель.вФон()
            case .active:
                модель.изФона()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if виден { модель.вФон() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if виден { модель.изФона() }
        }
    }

    // MARK: Фон: камера с вещью или заглушка

    @ViewBuilder
    private var фон: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ZStack {
                ПревьюЖивойПримерки(камера: камера, смена: камера.смена)
                    .opacity(камера.готова ? 1 : 0)
                    .animation(ДвижениеСайта.появление, value: камера.готова)
                    .accessibilityHidden(true)
                СлойВещиЖивойПримерки(модель: модель, слежение: модель.слежение, тихо: тихо)
            }
            .ignoresSafeArea()
            .environment(\.layoutDirection, .leftToRight)
        case .запрещён:
            заглушка(значок: "camera.fill", заголовок: т("lt_denied"), текст: т("lt_denied_hint"), настройки: true)
        case .нетКамеры:
            заглушка(значок: "video.slash", заголовок: т("lt_no_cam"), текст: т("lt_no_cam_hint"), настройки: false)
        }
    }

    // MARK: Управление: верх, подсказка, низ

    private var управление: some View {
        VStack(spacing: 0) {
            верх
            if живая {
                подсказка
                    .padding(.top, 10)
                    .padding(.horizontal, 16)
                Spacer(minLength: 12)
                низ
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private var верх: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("lt_close"), действие: закрыть)
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(т("lt_title"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text(модель.вид.название)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .shadow(color: Color.black.opacity(0.5), radius: 3)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if живая && !модель.подгонка.исходная {
                КруглаяКнопкаФото(значок: "arrow.counterclockwise", подпись: т("lt_reset")) {
                    модель.сброситьПодгонку()
                }
                .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .animation(ДвижениеСайта.появление, value: модель.подгонка.исходная)
    }

    /// Подсказка над камерой — капсулой; при подготовке вещи — с колесом.
    @ViewBuilder
    private var подсказка: some View {
        if let текст = модель.подсказка {
            HStack(spacing: 8) {
                if модель.вещь == .грузим {
                    SiteSpinner(размер: 16, толщина: 2, дорожка: Color.white.opacity(0.2), верх: Theme.зелёныйЯркий,
                                стоит: тихо)
                } else {
                    Image(systemName: значокПодсказки)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.зелёныйЯркий)
                        .accessibilityHidden(true)
                }
                Text(текст)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
            .accessibilityElement(children: .combine)
            .id(текст)
            .transition(.opacity)
        }
    }

    private var значокПодсказки: String {
        switch модель.состояние {
        case .нетЛица, .лицоДалеко: return "face.smiling"
        case .нетРуки: return "hand.raised"
        case .есть, .ищем: return "hand.draw"
        }
    }

    // MARK: Низ: «Фото вещи», затвор, «Другая камера»

    private var низ: some View {
        HStack(alignment: .top, spacing: 0) {
            /* Обратно к шагу «Вещь»: другое фото, ручная рамка. Есть всегда — рамка нужна и при одном фото. */
            кнопкаНиза(значок: "photo.on.rectangle.angled", подпись: ВещьЖивойПримеркиText.т("lw_item_btn"),
                       активна: false, доступна: !модель.снимаем) {
                модель.кВещи()
            }
            Spacer(minLength: 8)
            затвор
            Spacer(minLength: 8)
            if камера.естьДругая {
                кнопкаНиза(значок: "arrow.triangle.2.circlepath.camera", подпись: т("lt_flip"), активна: false,
                           доступна: камера.готова) {
                    модель.переключитьКамеру()
                }
            } else {
                пустоеМесто
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

    private var пустоеМесто: some View {
        Color.clear
            .frame(width: Self.ширинаКнопки, height: 1)
            .accessibilityHidden(true)
    }

    private func подписьКнопки(_ текст: String) -> some View {
        Text(текст)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .shadow(color: Color.black.opacity(0.6), radius: 2)
    }

    private func кнопкаНиза(значок: String, подпись: String, активна: Bool, доступна: Bool,
                            действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(активна ? Color.black : Color.white)
                    .frame(width: 56, height: 56)
                    .background(активна ? AnyShapeStyle(Theme.зелёныйЯркий) : AnyShapeStyle(Color.black.opacity(0.45)),
                                in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(активна ? 0 : 0.5), lineWidth: 1.5) }
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
        .accessibilityAddTraits(активна ? .isSelected : [])
    }

    private var можноСнять: Bool {
        камера.готова && модель.вещь == .готово && !модель.снимаем && модель.снимок == nil
    }

    /// Большой затвор: белое кольцо и круг; во время снимка круг зеленеет.
    private var затвор: some View {
        Button { модель.снять() } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 5)
                        .frame(width: 80, height: 80)
                    Circle()
                        .fill(модель.снимаем ? Theme.зелёныйЯркий : Color.white)
                        .frame(width: 64, height: 64)
                    Image(systemName: модель.вид.значок)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .accessibilityHidden(true)
                }
                подписьКнопки(т("lt_shot"))
            }
            .frame(width: 96)
            .contentShape(Rectangle())
            .opacity(можноСнять ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!можноСнять)
        .accessibilityLabel(т("lt_shot_a11y"))
    }

    // MARK: Нет доступа или камеры

    private func заглушка(значок: String, заголовок: String, текст: String, настройки: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: значок)
                    .font(.system(size: 30, weight: .semibold))
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
                    .accessibilityAddTraits(.isHeader)
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                if настройки {
                    ЗелёнаяКнопкаФото(заголовок: т("lt_settings"), значок: "gearshape") {
                        if let адрес = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(адрес)
                        }
                    }
                    .padding(.bottom, 10)
                }
                /* Камеры нет или её запретили — к шагу «Вещь» (другое фото, ручная рамка) не через ✕ и новое открытие. */
                ЗелёнаяКнопкаФото(заголовок: ВещьЖивойПримеркиText.т("lw_item_btn"), значок: "photo.on.rectangle.angled",
                                  контурная: true, наТёмном: true) {
                    модель.кВещи()
                }
                .padding(.bottom, 10)
                ЗелёнаяКнопкаФото(заголовок: т("lt_close"), значок: "xmark", контурная: true, наТёмном: true,
                                  действие: закрыть)
            }
            .padding(.horizontal, 32)
            .padding(.top, 120)
            .padding(.bottom, 60)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Слой вещи и жесты

/**
 Слой во весь экран поверх превью: вещи на своих местах и жесты подгонки. Наблюдает слежение (15 раз в секунду) —
 перерисовывается только он. Между кадрами анализа вещь плавно доезжает (линейно за один шаг анализа), при «Уменьшении
 движения» — переставляется сразу. Для VoiceOver слой — один регулируемый элемент.
 */
struct СлойВещиЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    @ObservedObject var слежение: СлежениеЖивойПримерки
    let тихо: Bool
    @GestureState private var масштабЖеста: CGFloat = 1
    @GestureState private var поворотЖеста: Double = 0
    @GestureState private var сдвигЖеста: CGSize = .zero

    init(модель: МодельЖивойПримерки, слежение: СлежениеЖивойПримерки, тихо: Bool) {
        self.модель = модель
        self.слежение = слежение
        self.тихо = тихо
    }

    private func т(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    /// Принятая подгонка и живой щипок с поворотом.
    private var живаяПодгонка: ПодгонкаЖивойПримерки {
        var п = модель.подгонка
        п.масштаб = min(3, max(0.3, п.масштаб * масштабЖеста))
        п.поворот += поворотЖеста
        return п
    }

    private var подписьДоступности: String {
        if модель.вещь == .готово && слежение.видно {
            return String(format: т("lt_item_a11y"), модель.вид.название)
        }
        return модель.подсказка ?? модель.вид.название
    }

    var body: some View {
        GeometryReader { место in
            ZStack(alignment: .topLeading) {
                Color.clear
                if модель.вещь == .готово && !модель.вырезки.isEmpty {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(слежение.положения.enumerated()), id: \.offset) { номер, базовое in
                            вещь(номер: номер, базовое: базовое)
                        }
                    }
                    .frame(width: место.size.width, height: место.size.height)
                    .opacity(слежение.видно ? 1 : 0)
                    .animation(тихо ? nil : .linear(duration: АнализЖивойПримерки.шаг), value: слежение.номер)
                    .animation(ДвижениеСайта.появление, value: слежение.видно)
                }
            }
            .frame(width: место.size.width, height: место.size.height)
            .contentShape(Rectangle())
            .gesture(сдвиг)
            .simultaneousGesture(щипок)
            .simultaneousGesture(поворот)
            .onAppear { слежение.размерЭкрана = место.size }
            .onChange(of: место.size) { _, новый in слежение.размерЭкрана = новый }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписьДоступности)
        .accessibilityValue(модель.вещь == .готово
                            ? String(format: т("lt_size_value"), Int((модель.подгонка.масштаб * 100).rounded())) : "")
        .accessibilityHint(модель.вещь == .готово ? т("lt_adjust_hint") : "")
        .accessibilityAdjustableAction { куда in
            switch куда {
            case .increment:
                модель.крупнее(true)
            case .decrement:
                модель.крупнее(false)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: Text(т("lt_rot_left"))) { модель.повернуть(вправо: false) }
        .accessibilityAction(named: Text(т("lt_rot_right"))) { модель.повернуть(вправо: true) }
        .accessibilityAction(named: Text(т("lt_reset"))) { модель.сброситьПодгонку() }
    }

    @ViewBuilder
    private func вещь(номер: Int, базовое: РасположениеВещиЖивой) -> some View {
        if let картинка = модель.вырезки.indices.contains(номер) ? Optional(модель.вырезки[номер]) : модель.вырезки.first {
            ВещьЖивойПримерки(картинка: картинка,
                              р: базовое.сПодгонкой(живаяПодгонка, зеркально: модель.вид.пара && номер == 1,
                                                     сдвигЭкрана: сдвигЖеста))
        }
    }

    private var сдвиг: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($сдвигЖеста) { значение, состояние, _ in
                состояние = значение.translation
            }
            .onEnded { значение in
                модель.принятьЖест(масштаб: 1, поворот: 0, сдвиг: значение.translation)
            }
    }

    private var щипок: some Gesture {
        MagnifyGesture()
            .updating($масштабЖеста) { значение, состояние, _ in
                состояние = значение.magnification
            }
            .onEnded { значение in
                модель.принятьЖест(масштаб: значение.magnification, поворот: 0, сдвиг: .zero)
            }
    }

    private var поворот: some Gesture {
        RotateGesture()
            .updating($поворотЖеста) { значение, состояние, _ in
                состояние = значение.rotation.radians
            }
            .onEnded { значение in
                модель.принятьЖест(масштаб: 1, поворот: значение.rotation.radians, сдвиг: .zero)
            }
    }
}

/// Одна вещь на экране: якорь картинки — в точке центра, поворот и сжатие вокруг него, ремешок дальше предела гаснет
/// (та же маска, что у снимка, — СнимокЖивойПримерки.стопы).
struct ВещьЖивойПримерки: View {
    let картинка: UIImage
    let р: РасположениеВещиЖивой

    var body: some View {
        let пропорция = картинка.size.width / max(1, картинка.size.height)
        let ш = max(1, р.ширина)
        let в = ш / max(0.05, пропорция)
        Image(uiImage: картинка)
            .resizable()
            .interpolation(.high)
            .frame(width: ш, height: в)
            .mask { маска(высота: в) }
            .scaleEffect(x: р.сжатие.width, y: р.сжатие.height, anchor: р.якорьЕдиницы)
            .rotationEffect(.radians(р.угол), anchor: р.якорьЕдиницы)
            .position(x: р.центр.x - (р.якорь.x - 0.5) * ш, y: р.центр.y - (р.якорь.y - 0.5) * в)
            .opacity(р.видимость)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func маска(высота в: CGFloat) -> some View {
        if let предел = р.предел, в > 0, предел < в {
            let места = СнимокЖивойПримерки.стопы(видно: предел / в)
            LinearGradient(stops: [
                Gradient.Stop(color: Color.white.opacity(0), location: места[0]),
                Gradient.Stop(color: Color.white.opacity(0), location: места[1]),
                Gradient.Stop(color: Color.white, location: места[2]),
                Gradient.Stop(color: Color.white, location: места[3]),
                Gradient.Stop(color: Color.white.opacity(0), location: места[4]),
                Gradient.Stop(color: Color.white.opacity(0), location: места[5])
            ], startPoint: .top, endPoint: .bottom)
        } else {
            Color.white
        }
    }
}

// MARK: - Полоса фото вещи

/// Миниатюры фото объявления на шаге «Вещь»: выбранное — в зелёной рамке, не подошедшие — с меткой.
struct ПолосаФотоЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    var отступ: CGFloat = 16

    init(модель: МодельЖивойПримерки, отступ: CGFloat = 16) {
        self.модель = модель
        self.отступ = отступ
    }

    private func т(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(модель.товар.фотоАдреса.enumerated()), id: \.offset) { номер, адрес in
                    миниатюра(номер: номер, адрес: адрес)
                }
            }
            .padding(.horizontal, отступ)
            .padding(.vertical, 4)
        }
    }

    private func миниатюра(номер: Int, адрес: URL) -> some View {
        let выбрана = номер == модель.номерФото
        let неПодошло = модель.неПодошли.contains(номер)
        return Button { модель.выбратьФото(номер) } label: {
            КартинкаЛенты(адрес, пунктов: 60) {
                Color.white.opacity(0.08)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбрана ? Theme.зелёныйЯркий : Color.white.opacity(0.22), lineWidth: выбрана ? 3 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if неПодошло {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white, Theme.оранжевый)
                        .padding(3)
                        .accessibilityHidden(true)
                }
            }
            .opacity(неПодошло && !выбрана ? 0.55 : 1)
            .scaleEffect(выбрана ? 1 : 0.94)
            .animation(ДвижениеСайта.выбор, value: выбрана)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(String(format: т("lt_photo_n"), номер + 1))
        .accessibilityValue(неПодошло ? т("lt_photo_bad") : "")
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}

// MARK: - Снимок

/// Снимок с вещью поверх живой примерки: картинка, пометка «примерка приблизительная», «Сохранить в Фото»,
/// «Поделиться», «Ещё снимок».
struct ЛистСнимкаЖивойПримерки: View {
    @ObservedObject var модель: МодельЖивойПримерки
    let снимок: UIImage

    init(модель: МодельЖивойПримерки, снимок: UIImage) {
        self.модель = модель
        self.снимок = снимок
    }

    private func т(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                шапка
                Image(uiImage: снимок)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .shadow(color: Theme.зелёныйЯркий.opacity(0.18), radius: 24, x: 0, y: 8)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .frame(maxWidth: 520, maxHeight: .infinity)
                    .layoutPriority(1)
                    .accessibilityLabel(String(format: т("lt_item_a11y"), модель.вид.название))
                Text(т("lt_note"))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 10)
                действия
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var шапка: some View {
        HStack(spacing: 12) {
            КруглаяКнопкаФото(значок: "xmark", подпись: т("lt_close")) { модель.закрытьСнимок() }
            Spacer(minLength: 0)
            Text(т("lt_shot_title"))
                .font(.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var действия: some View {
        VStack(spacing: 10) {
            ЗелёнаяКнопкаФото(заголовок: т("lt_save"), значок: "square.and.arrow.down") {
                модель.сохранить()
            }
            .disabled(модель.сохраняем)
            .opacity(модель.сохраняем ? 0.6 : 1)
            HStack(spacing: 10) {
                малаяКнопка(т("lt_share"), значок: "square.and.arrow.up") { модель.поделиться() }
                малаяКнопка(т("lt_again"), значок: "camera") { модель.закрытьСнимок() }
            }
        }
    }

    private func малаяКнопка(_ заголовок: String, значок: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото())
        .accessibilityLabel(заголовок)
    }
}

// MARK: - Весть

/// Короткая весть внизу экрана: тёмное стекло, зелёная кромка. Читает её VoiceOver (объявление в модели).
struct ВестьЖивойПримерки: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.зелёныйЯркий.opacity(0.55), lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}
