import SwiftUI
import UIKit

/**
 ИИ-СТУДИЯ ФОТО ПОДАЧИ — ЭКРАН (владелец 13.10.2026: «свой редактор фото для техники через ИИ»; «мощная анимированная
 подача», «удобно для глаз»).

 Полноэкранный и тёмный, как камеры приложения. Сверху — «✕» и «Студия». Посередине — большое фото: пока Vision ищет
 предмет, по нему бежит зелёная линия (как в поиске по фото); потом фон гаснет, предмет приподнимается и встаёт по
 центру студийного фона. Готово — шторка «До / После»: тянешь пальцем, и видно, где было и где стало. Снизу — фоны
 кружками («Свой», «Белый», «Светлый», «Градиент», «Тёплый», «Тёмный»), «Тень», «Свет и цвет», «Готово» (и «Вернуть как
 было», если фото уже из студии). Низ занимает место с самого начала — фото не прыгает, когда панель появляется.
 */
struct ЭкранСтудииФото: View {
    let подача: ПодачаМодель
    let плитка: UUID
    let закрыть: () -> Void
    @StateObject private var студия: МодельСтудииФото
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(подача: ПодачаМодель, плитка: UUID, закрыть: @escaping () -> Void) {
        self.подача = подача
        self.плитка = плитка
        self.закрыть = закрыть
        _студия = StateObject(wrappedValue: МодельСтудииФото(плитка: плитка))
    }

    private func т(_ ключ: String) -> String { СтудияФотоText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// Яркий зелёный тёмной темы (#5CD39A) — линия сканирования, выбранный кружок, «Готово».
    private static let зелёный = Color(uiColor: Theme.hex(0x5CD39A))

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 0) {
                шапка
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                область
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                низ
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .overlay(alignment: .top) { плашка }
        /* Тёмная — только эта студия (не .preferredColorScheme: он красит всё окно). Строка состояния спрятана, как
           у камер приложения: тёмные часы на чёрном не видны. */
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .task { await студия.запустить(подача: подача) }
        .onDisappear { студия.остановить() }
    }

    // MARK: - Шапка

    private var шапка: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Self.зелёный)
                Text(т("st_title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            HStack {
                КнопкаСтудииФото(значок: "xmark", подпись: т("st_close")) { закрыть() }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Фото

    @ViewBuilder
    private var область: some View {
        if let кадр = студия.исходник {
            холст(кадр)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                if студия.этап == .ошибка {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.7))
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Color.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }

    /**
     Слои снизу вверх: исходник («До»), затемнение на время отрыва, студийный фон полёта, летящий предмет, «После» под
     шторкой и бегущая линия. Все картинки одного размера — слои совпадают пиксель в пиксель.
     */
    private func холст(_ кадр: CGImage) -> some View {
        let соотношение = CGFloat(кадр.width) / CGFloat(max(1, кадр.height))
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        let этап = студия.этап
        return ZStack {
            Image(decorative: кадр, scale: 1)
                .resizable()
                .interpolation(.high)
            Color.black
                .opacity(этап == .отрыв || этап == .перенос ? 0.55 : 0)
            фонПолёта
            летящийПредмет
            послеПодШторкой
            if этап == .скан && !тихо {
                РазвёрткаСтудииФото(цвет: Self.зелёный)
            }
        }
        .aspectRatio(соотношение, contentMode: .fit)
        .overlay { шторка }
        .clipShape(форма)
        .overlay {
            форма
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private var фонПолёта: some View {
        if let фон = студия.фонПолёта {
            Image(decorative: фон, scale: 1)
                .resizable()
                .interpolation(.high)
                .opacity(студия.этап == .перенос ? 1 : 0)
                .accessibilityHidden(true)
        }
    }

    /**
     Вырезанный предмет на исходном месте: на «отрыве» чуть увеличивается и светится зелёным, на «переносе» пружиной
     уезжает и меняет размер так, что встаёт ровно туда же, где он на готовом «После» (центр рамки → центр места).
     */
    @ViewBuilder
    private var летящийПредмет: some View {
        if let а = студия.анализ, а.естьПредмет, let предмет = студия.предметДляПолёта {
            let этап = студия.этап
            let встал = этап == .перенос || этап == .готово
            let исх = а.рамкаСверху
            let цель = а.местоСверху
            let якорь = UnitPoint(x: исх.midX / max(1, а.ширина), y: исх.midY / max(1, а.высота))
            GeometryReader { г in
                let к = г.size.width / max(1, а.ширина)
                Image(decorative: предмет, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: г.size.width, height: г.size.height)
                    .shadow(color: Self.зелёный.opacity(этап == .отрыв ? 0.9 : 0), radius: 16)
                    .shadow(color: Color.black.opacity(этап == .отрыв ? 0.45 : 0), radius: 10, y: 8)
                    .scaleEffect(встал ? а.масштаб : (этап == .отрыв ? 1.04 : 1), anchor: якорь)
                    .offset(x: встал ? (цель.midX - исх.midX) * к : 0,
                            y: встал ? (цель.midY - исх.midY) * к : (этап == .отрыв ? -6 : 0))
            }
            .opacity(этап == .отрыв || этап == .перенос ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// «После»: прежняя картинка снизу, новая проявляется поверх — смена фона без вспышки «До». Справа от шторки.
    private var послеПодШторкой: some View {
        ZStack {
            if let прежнее = студия.прежнееПосле {
                Image(decorative: прежнее, scale: 1)
                    .resizable()
                    .interpolation(.high)
            }
            if let картинка = студия.после {
                Image(decorative: картинка, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .id(студия.версия)
                    .transition(.opacity)
            }
        }
        .mask {
            GeometryReader { г in
                Rectangle()
                    .frame(width: max(0, г.size.width * (1 - студия.доля)), height: г.size.height)
                    .offset(x: г.size.width * студия.доля)
            }
        }
        .opacity(студия.этап == .готово ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: - Шторка «До / После»

    private var шторка: some View {
        GeometryReader { г in
            let ширина = г.size.width
            let доля = студия.доля
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(тянуть(ширина))
                if доля > 0.005 && доля < 0.995 {
                    ручка(высота: г.size.height)
                        .position(x: ширина * доля, y: г.size.height / 2)
                }
                HStack(spacing: 0) {
                    if доля > 0.12 { метка(т("st_before"), акцент: false) }
                    Spacer(minLength: 0)
                    if доля < 0.88 { метка(т("st_after"), акцент: true) }
                }
                .padding(10)
                .allowsHitTesting(false)
            }
        }
        .opacity(студия.этап == .готово ? 1 : 0)
        .allowsHitTesting(студия.этап == .готово)
        .accessibilityElement()
        .accessibilityLabel(т("st_compare"))
        .accessibilityValue(String(format: т("st_compare_value"), Int(((1 - студия.доля) * 100).rounded())))
        .accessibilityHint(т("st_hint"))
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: студия.доля = max(0, студия.доля - 0.25)
            case .decrement: студия.доля = min(1, студия.доля + 0.25)
            @unknown default: break
            }
        }
        .accessibilityHidden(студия.этап != .готово)
    }

    /// Палец ведёт шторку (и нажатие ставит её туда же).
    private func тянуть(_ ширина: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { ход in
                guard ширина > 0 else { return }
                студия.доля = min(1, max(0, ход.location.x / ширина))
            }
    }

    private func ручка(высота: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 2.5, height: высота)
                .shadow(color: Color.black.opacity(0.35), radius: 3)
            Circle()
                .fill(Color.white)
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.3), radius: 6, y: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .allowsHitTesting(false)
    }

    private func метка(_ текст: String, акцент: Bool) -> some View {
        Text(текст.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(акцент ? Color.black : Color.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(акцент ? AnyShapeStyle(Self.зелёный) : AnyShapeStyle(Color.black.opacity(0.55)), in: Capsule())
    }

    // MARK: - Низ

    /// Панель занимает место всегда (невидимая, пока идёт разбор), поверх неё — ход или «не нашли».
    private var низ: some View {
        let готов = студия.этап == .готово
        return ZStack {
            панель
                .opacity(готов ? 1 : 0)
                .allowsHitTesting(готов)
                .accessibilityHidden(!готов)
            if !готов {
                состояние
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.смена, value: готов)
    }

    @ViewBuilder
    private var состояние: some View {
        switch студия.этап {
        case .нетПредмета:
            карточка(значок: "viewfinder", текст: т("st_not_found")) {
                ШирокаяКнопкаСтудииФото(подпись: т("st_light_only"), значок: "wand.and.stars", главная: true) {
                    студия.толькоСветИЦвет()
                }
                ШирокаяКнопкаСтудииФото(подпись: т("st_close"), значок: nil, главная: false) { закрыть() }
            }
        case .ошибка:
            карточка(значок: "wifi.exclamationmark", текст: т("st_error")) {
                ШирокаяКнопкаСтудииФото(подпись: т("st_close"), значок: nil, главная: false) { закрыть() }
            }
        default:
            HStack(spacing: 12) {
                ProgressView()
                    .tint(Self.зелёный)
                Text(строкаХода)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
    }

    private var строкаХода: String {
        switch студия.этап {
        case .загрузка: return т("st_loading")
        case .скан: return т("st_scanning")
        default: return т("st_lifting")
        }
    }

    private func карточка<Кнопки: View>(значок: String, текст: String,
                                         @ViewBuilder кнопки: () -> Кнопки) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Self.зелёный)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            кнопки()
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var панель: some View {
        VStack(spacing: 14) {
            сравнение
            фоны
            переключатели
            кнопки
        }
    }

    /// «До | После»: «До» — шторка вправо до конца, «После» — влево; между ними — сравнение.
    private var сравнение: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                сегмент(т("st_before"), активен: студия.доля >= 0.995) { поставитьШторку(1) }
                сегмент(т("st_after"), активен: студия.доля <= 0.005) { поставитьШторку(0) }
            }
            .padding(3)
            .background(Color.white.opacity(0.1), in: Capsule())
            Text(т("st_hint"))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
        }
    }

    private func поставитьШторку(_ доля: CGFloat) {
        ОткликСайта.выбор()
        withAnimation(тихо ? nil : Animation.easeInOut(duration: 0.45)) { студия.доля = доля }
    }

    private func сегмент(_ подпись: String, активен: Bool, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(активен ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 20)
                .frame(height: 30)
                .background(активен ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(ДвижениеСайта.выбор, value: активен)
        .accessibilityAddTraits(активен ? .isSelected : [])
    }

    /// Фоны кружками; предмета нет — доступен только «Свой» (остальные приглушены, место не прыгает).
    private var фоны: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ФонСтудииФото.allCases) { вид in
                    КругФонаСтудииФото(вид: вид, подпись: т(вид.ключ), выбран: студия.настройки.фон == вид,
                                       образец: студия.исходник, доступен: !студия.толькоСвет || вид == .свой,
                                       цвет: Self.зелёный) {
                        студия.выбратьФон(вид)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var переключатели: some View {
        HStack(spacing: 10) {
            ПереключательСтудииФото(значок: "square.fill.on.square.fill", подпись: т("st_shadow"),
                                    вкл: студия.настройки.тень, доступен: студия.вырез, цвет: Self.зелёный) {
                студия.переключитьТень()
            }
            ПереключательСтудииФото(значок: "wand.and.stars", подпись: т("st_light"), вкл: студия.настройки.свет,
                                    доступен: true, цвет: Self.зелёный) {
                студия.переключитьСвет()
            }
        }
    }

    private var кнопки: some View {
        HStack(spacing: 10) {
            if студия.естьОригинал {
                ШирокаяКнопкаСтудииФото(подпись: т("st_revert"), значок: "arrow.uturn.left", главная: false) {
                    вернуть()
                }
            }
            ШирокаяКнопкаСтудииФото(подпись: студия.сохраняем ? т("st_saving") : т("st_done"),
                                    значок: студия.сохраняем ? nil : "checkmark", главная: true,
                                    занято: студия.сохраняем) {
                готово()
            }
            .disabled(!студия.изменено || студия.сохраняем)
            .opacity(студия.изменено ? 1 : 0.45)
        }
    }

    @ViewBuilder
    private var плашка: some View {
        if let текст = студия.плашка {
            Text(текст)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: Theme.hex(0x2A2F33)), in: Capsule())
                .padding(.top, 60)
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Действия

    /// «Готово»: итог — в плитку вместо прежнего фото, студия закрывается.
    private func готово() {
        Task { @MainActor in
            guard let готовое = await студия.сохранить() else { return }
            подача.заменитьФотоСтудией(плитка, готовое)
            закрыть()
        }
    }

    private func вернуть() {
        подача.вернутьФотоДоСтудии(плитка)
        закрыть()
    }
}

// MARK: - Части экрана

/// Бегущая сверху вниз зелёная полоса со светящейся кромкой; повторяется, пока идёт поиск предмета.
struct РазвёрткаСтудииФото: View {
    let цвет: Color
    @State private var бег = false

    var body: some View {
        GeometryReader { г in
            VStack(spacing: 0) {
                LinearGradient(colors: [цвет.opacity(0), цвет.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                Rectangle()
                    .fill(цвет)
                    .frame(height: 2.5)
                    .shadow(color: цвет, radius: 8)
            }
            .frame(width: г.size.width)
            .offset(y: бег ? г.size.height : -93)
            .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: бег)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { бег = true }
    }
}

/// Круглая кнопка шапки (как у камер приложения).
struct КнопкаСтудииФото: View {
    let значок: String
    let подпись: String
    let действие: () -> Void

    init(значок: String, подпись: String, действие: @escaping () -> Void) {
        self.значок = значок
        self.подпись = подпись
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12), in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
    }
}

/// Кружок фона: образец цвета (у «Своего» — само фото), подпись; выбранный — в зелёном кольце и чуть крупнее.
struct КругФонаСтудииФото: View {
    let вид: ФонСтудииФото
    let подпись: String
    let выбран: Bool
    let образец: CGImage?
    let доступен: Bool
    let цвет: Color
    let действие: () -> Void

    init(вид: ФонСтудииФото, подпись: String, выбран: Bool, образец: CGImage?, доступен: Bool, цвет: Color,
         действие: @escaping () -> Void) {
        self.вид = вид
        self.подпись = подпись
        self.выбран = выбран
        self.образец = образец
        self.доступен = доступен
        self.цвет = цвет
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                круг
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1) }
                    .padding(3)
                    .overlay { Circle().strokeBorder(выбран ? цвет : Color.clear, lineWidth: 2.5) }
                    .scaleEffect(выбран ? 1.06 : 1)
                Text(подпись)
                    .font(.system(size: 11, weight: выбран ? .bold : .medium))
                    .foregroundStyle(выбран ? Color.white : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!доступен)
        .opacity(доступен ? 1 : 0.35)
        .animation(ДвижениеСайта.выбор, value: выбран)
        .accessibilityLabel(подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    @ViewBuilder
    private var круг: some View {
        let цвета = вид.цвета
        let верх = Color(uiColor: Theme.hex(цвета.0))
        let низ = Color(uiColor: Theme.hex(цвета.1))
        if вид == .свой {
            if let образец {
                Image(decorative: образец, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray
            }
        } else if вид.круглый {
            RadialGradient(colors: [верх, низ], center: UnitPoint(x: 0.5, y: 0.42), startRadius: 1, endRadius: 30)
        } else {
            LinearGradient(colors: [верх, низ], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// «Тень», «Свет и цвет»: капсула со значком и точкой-индикатором; включено — зелёная кромка.
struct ПереключательСтудииФото: View {
    let значок: String
    let подпись: String
    let вкл: Bool
    let доступен: Bool
    let цвет: Color
    let действие: () -> Void

    init(значок: String, подпись: String, вкл: Bool, доступен: Bool, цвет: Color, действие: @escaping () -> Void) {
        self.значок = значок
        self.подпись = подпись
        self.вкл = вкл
        self.доступен = доступен
        self.цвет = цвет
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: значок)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Capsule()
                    .fill(вкл && доступен ? цвет : Color.white.opacity(0.22))
                    .frame(width: 26, height: 16)
                    .overlay(alignment: вкл && доступен ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .padding(2)
                    }
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(вкл && доступен ? цвет.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!доступен)
        .opacity(доступен ? 1 : 0.4)
        .animation(ДвижениеСайта.выбор, value: вкл)
        .accessibilityLabel(подпись)
        .accessibilityValue(СтудияФотоText.т(вкл ? "st_on" : "st_off"))
    }
}

/// Широкая кнопка низа: главная — зелёная («Готово», «Только свет и цвет»), вторая — светлая на тёмном.
struct ШирокаяКнопкаСтудииФото: View {
    let подпись: String
    let значок: String?
    let главная: Bool
    let занято: Bool
    let действие: () -> Void

    init(подпись: String, значок: String?, главная: Bool, занято: Bool = false, действие: @escaping () -> Void) {
        self.подпись = подпись
        self.значок = значок
        self.главная = главная
        self.занято = занято
        self.действие = действие
    }

    private static let зелёный = Color(uiColor: Theme.hex(0x5CD39A))

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занято {
                    ProgressView()
                        .tint(Color.black)
                } else if let значок {
                    Image(systemName: значок)
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(главная ? Color.black : Color.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(главная ? AnyShapeStyle(Self.зелёный) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
            .overlay { Capsule().strokeBorder(Color.white.opacity(главная ? 0 : 0.14), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
