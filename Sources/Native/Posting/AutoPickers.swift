import SwiftUI
import UIKit

/**
 ЭКРАН «ОБ АВТОМОБИЛЕ» МАСТЕРА АВТО — ВЫБОР ВМЕСТО НАБОРА (владелец 14.10.2026, скрины TestFlight шагов «Поколение» и
 «Год выпуска, пробег»: «объём сайт знает — можно выбрать или вписать; пробег сделай как регулятор стильно, а не
 цифрами набирать вручную; так же и год выбрать… такие мелочи нужно упрощать для юзеров»).

 Год — чипами лет поколения или лентой с прилипанием к центру; пробег — регулятор с неровной шкалой и точным вводом по
 нажатию на число; объём — чипы gens[].eng (без них — ходовые объёмы) и «Другой — вписать»; коробка и топливо — сначала
 варианты поколения, остальные слова — за «Другой…». Плитка поколения — годы крупно и шкала времени модели. Всё лёгкое:
 один замер на ленту и регулятор, а не на каждую строку, анимации короткие — летает и на iPhone XR. Тексты —
 ПараметрыАвтоText (AutoPickersText.swift), сам экран собирает МастерАвтоВид (PostingMasters.swift).
 */

// MARK: - Блок экрана

/// Блок экрана «Об автомобиле» (.ecard кабинета): значок в мятном квадрате, подпись («*» — обязательно, «· необязательно»),
/// справа — выбранное значение; под ними — сам выбор. Появляется мягко, по очереди (номер).
struct БлокПараметраАвто<Содержимое: View>: View {
    let заголовок: String
    let значок: String
    let значение: String
    let обязательно: Bool
    let необязательно: Bool
    let номер: Int
    let содержимое: Содержимое

    init(_ заголовок: String, значок: String, значение: String = "", обязательно: Bool = false,
         необязательно: Bool = false, номер: Int = 0, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.значок = значок
        self.значение = значение
        self.обязательно = обязательно
        self.необязательно = необязательно
        self.номер = номер
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            шапка
            содержимое
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
        .shadow(color: КраскаПодачи.тень, radius: 6, y: 2)
        .появлениеАвто(номер)
    }

    private var шапка: some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 30, height: 30)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(заголовок)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if обязательно {
                    Text("*")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(КраскаПодачи.плохоТекст)
                }
                if необязательно {
                    Text("· " + ПараметрыАвтоText.т("form_optional"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            if !значение.isEmpty {
                Text(значение)
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.выбор, value: значение)
    }
}

/// Мягкое появление блока, как был каскад прежнего экрана «Быстро / Подробно»: снизу и из прозрачности, пружиной, по
/// очереди — номер × 0,05 с (не дольше 0,4 с). «Уменьшение движения» или лёгкий режим — сразу на месте.
@MainActor
struct ПоявлениеБлокаАвто: ViewModifier {
    let номер: Int
    @State private var видно: Bool
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(номер: Int) {
        self.номер = номер
        _видно = State(initialValue: ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий)
    }

    func body(content: Content) -> some View {
        content
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 14)
            .onAppear {
                guard !видно else { return }
                guard !безДвижения else {
                    видно = true
                    return
                }
                let пружина = Animation.spring(response: 0.42, dampingFraction: 0.86)
                    .delay(Double(min(max(номер, 0), 8)) * 0.05)
                withAnimation(ДвижениеСайта.мягко(пружина)) {
                    видно = true
                }
            }
    }
}

extension View {
    /// Блок и плитка мастера авто появляются мягко, по очереди (ПоявлениеБлокаАвто).
    @MainActor
    func появлениеАвто(_ номер: Int) -> some View {
        modifier(ПоявлениеБлокаАвто(номер: номер))
    }
}

// MARK: - Год: чипы лет поколения

/// Годы поколения сеткой по четыре (новые первыми): выбранный — зелёной заливкой, нажал выбранный — остаётся.
struct ЧипыЛетАвто: View {
    let годы: [Int]
    let выбран: String
    let выбрать: (Int) -> Void

    private let колонки = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(годы: [Int], выбран: String, выбрать: @escaping (Int) -> Void) {
        self.годы = годы
        self.выбран = выбран
        self.выбрать = выбрать
    }

    var body: some View {
        LazyVGrid(columns: колонки, spacing: 8) {
            ForEach(годы, id: \.self) { г in
                let вкл = выбран == String(г)
                let вес = вкл ? Font.Weight.heavy : Font.Weight.semibold
                Button {
                    выбрать(г)
                } label: {
                    Text(String(г))
                        .font(Font.system(size: 15, weight: вес).monospacedDigit())
                        .foregroundStyle(вкл ? Color.white : КраскаПодачи.текст)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(вкл ? Theme.зелёный : КраскаПодачи.поле,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(вкл ? Theme.зелёный : КраскаПодачи.линия, lineWidth: 1)
                        }
                        .scaleEffect(вкл ? 1.04 : 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
                .accessibilityAddTraits(вкл ? .isSelected : [])
            }
        }
        .animation(ДвижениеСайта.выбор, value: выбран)
    }
}

// MARK: - Год: лента с прилипанием к центру

/// Левый край ряда лет в координатах ленты — по нему видно, какой год в окошке.
struct СдвигЛентыГодовКлюч: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/**
 Лента годов (года поколения нет: текущий … 1960): листается пальцем и прилипает так, что один год стоит в окошке по
 центру — он и выбран, крупнее и зелёный, со щелчком отклика на каждой смене. Пока года нет, лента стоит на прикидке и
 окошко серое: выбор — первым движением или нажатием на год. Записывается, когда лента остановилась (0,16 с без смены),
 — чтобы на быстром пролёте экран не пересчитывался на каждый год. Всегда слева направо: числа и в арабском по порядку.
 */
struct ЛентаГодовАвто: View {
    @Binding var год: String
    /// Годы ленты — новые первыми.
    let годы: [Int]
    /// Где встать, пока год не выбран.
    let прикидка: Int

    /// Год в окошке (пока листают — ещё не записан).
    @State private var центр: Int? = nil
    /// Лента встала на место — дальше сдвиг только от пальца.
    @State private var готова = false
    /// Листаем сами (нажали на год, год поменяли снаружи) — без отклика и записи по пути.
    @State private var сами = false
    /// Человек уже листал или нажимал — год в окошке зелёный ещё до записи.
    @State private var тронута = false
    @State private var запись: Task<Void, Never>? = nil

    private static let ячейка: CGFloat = 64
    private static let высота: CGFloat = 56
    private static let имяПрокрутки = "лента-годов-авто"

    init(год: Binding<String>, годы: [Int], прикидка: Int) {
        self._год = год
        self.годы = годы
        self.прикидка = прикидка
    }

    private func т(_ ключ: String) -> String { ПараметрыАвтоText.т(ключ) }

    var body: some View {
        GeometryReader { гео in
            let поле = max(0, (гео.size.width - Self.ячейка) / 2)
            ScrollViewReader { прокрутка in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(годы, id: \.self) { г in
                            ячейка(г) { нажат(г, прокрутка) }
                                .id(г)
                        }
                    }
                    .scrollTargetLayout()
                    .background {
                        GeometryReader { ряд in
                            Color.clear.preference(key: СдвигЛентыГодовКлюч.self,
                                                   value: ряд.frame(in: NamedCoordinateSpace.named(Self.имяПрокрутки)).minX)
                        }
                    }
                }
                .contentMargins(.horizontal, поле, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .coordinateSpace(NamedCoordinateSpace.named(Self.имяПрокрутки))
                .onPreferenceChange(СдвигЛентыГодовКлюч.self) { x in
                    /* Замер приходит на главной нити; замыкание — Sendable, поэтому явно. */
                    MainActor.assumeIsolated { сдвинута(x, поле: поле) }
                }
                .onAppear { встать(прокрутка) }
                .onChange(of: год) { _, новое in
                    guard let г = Int(новое), г != центр, годы.contains(г) else { return }
                    листатьСами(к: г, прокрутка)
                }
            }
        }
        .frame(height: Self.высота)
        .background { окошко }
        .mask { края }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("aw_year"))
        .accessibilityValue(год.isEmpty ? "—" : год)
        .accessibilityAdjustableAction { куда in
            let сейчас = Int(год).flatMap { годы.firstIndex(of: $0) } ?? годы.firstIndex(of: центр ?? прикидка) ?? 0
            /* Годы — новые первыми: «больше» — к началу ленты. */
            let номер: Int
            switch куда {
            case .increment: номер = сейчас - 1
            case .decrement: номер = сейчас + 1
            @unknown default: return
            }
            guard номер >= 0 && номер < годы.count else { return }
            тронута = true
            год = String(годы[номер])
        }
    }

    private func ячейка(_ г: Int, нажать: @escaping () -> Void) -> some View {
        let вОкошке = центр == г
        let отмечен = вОкошке && (тронута || год == String(г))
        let вес = вОкошке ? Font.Weight.heavy : Font.Weight.semibold
        return Button(action: нажать) {
            Text(String(г))
                .font(Font.system(size: 17, weight: вес).monospacedDigit())
                .foregroundStyle(отмечен ? КраскаПодачи.хорошоТекст : (вОкошке ? КраскаПодачи.текст : Theme.текстВторой))
                .scaleEffect(вОкошке ? 1.22 : 1)
                .frame(width: Self.ячейка, height: Self.высота)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(ДвижениеСайта.выбор, value: вОкошке)
    }

    /// Окошко по центру: выбран — мятное с зелёной кромкой, нет — серое.
    private var окошко: some View {
        let есть = тронута || !год.isEmpty
        return RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
            .fill(есть ? КраскаПодачи.хорошоФон : КраскаПодачи.поле)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(есть ? КраскаПодачи.акцентТекст.opacity(0.45) : КраскаПодачи.линия, lineWidth: 1.5)
            }
            .frame(width: Self.ячейка - 2, height: Self.высота - 6)
            .animation(ДвижениеСайта.смена, value: есть)
    }

    /// Края ленты гаснут — видно, что дальше ещё годы.
    private var края: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                               .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Ход ленты

    private func сдвинута(_ x: CGFloat, поле: CGFloat) {
        guard !годы.isEmpty, x.isFinite else { return }
        let номер = min(годы.count - 1, max(0, Int(((поле - x) / Self.ячейка).rounded())))
        let г = годы[номер]
        guard г != центр else { return }
        центр = г
        guard готова && !сами else { return }
        тронута = true
        ОткликСайта.выбор()
        записатьПозже(г)
    }

    /// Запись года, когда лента остановилась: новая смена в окошке отменяет прежнюю.
    private func записатьПозже(_ г: Int) {
        запись?.cancel()
        запись = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            if год != String(г) { год = String(г) }
        }
    }

    /// Первое появление: на выбранный год, нет его — на прикидку; без полёта и без отклика.
    private func встать(_ прокрутка: ScrollViewProxy) {
        guard !годы.isEmpty else { return }
        let выбран = Int(год).flatMap { годы.contains($0) ? $0 : nil }
        let цель = выбран ?? (годы.contains(прикидка) ? прикидка : годы[годы.count / 2])
        сами = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000)
            прокрутка.scrollTo(цель, anchor: .center)
            try? await Task.sleep(nanoseconds: 350_000_000)
            сами = false
            готова = true
        }
    }

    private func нажат(_ г: Int, _ прокрутка: ScrollViewProxy) {
        тронута = true
        запись?.cancel()
        if год != String(г) {
            год = String(г)
            ОткликСайта.выбор()
        }
        листатьСами(к: г, прокрутка)
    }

    private func листатьСами(к г: Int, _ прокрутка: ScrollViewProxy) {
        сами = true
        withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(г, anchor: .center) }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            сами = false
        }
    }
}

// MARK: - Пробег: регулятор

/**
 Пробег «регулятором» (владелец: «пробег сделай как регулятор стильно, а не цифрами набирать вручную»): крупное число,
 под ним толстая дорожка во всю ширину с круглой ручкой, ручка под пальцем крупнее. Шкала неровная — внизу частая,
 вверху редкая: 0–100 тыс. шагом 1 000 на первые 40 % дорожки, 100–300 тыс. шагом 5 000 на следующие 35 %, 300 тыс.–
 1 млн шагом 10 000 на остаток. Щелчок отклика — на каждые 10 000 км, не на каждый шаг. Пока не трогали — значения
 нет: ручка бледная на прикидке по возрасту машины, вместо числа «Сдвиньте регулятор»; значение ставят нажатие на
 дорожку или ход пальца вбок, а палец вверх-вниз — это прокрутка экрана, пробег он не трогает.
 Нажатие на число — точный ввод цифрами (до 7 знаков). В форму уходят только цифры (ПодачаМодель.цифры).
 */
struct РегуляторПробега: View {
    @Binding var пробег: String
    /// Где стоит бледная ручка, пока значения нет (≈17 000 км на год возраста).
    let прикидка: Int

    @State private var тянут = false
    @State private var вводом = false
    @FocusState private var фокус: Bool

    /// Конец дорожки — 1 млн км; точным вводом можно и больше.
    static let предел = 1_000_000
    /// Отметки и подписи под дорожкой.
    private static let метки = [0, 50_000, 100_000, 200_000, 300_000, 1_000_000]
    /// Радиус ручки: дорожка начинается и кончается на её середине.
    private static let радиус: CGFloat = 15

    init(пробег: Binding<String>, прикидка: Int) {
        self._пробег = пробег
        self.прикидка = прикидка
    }

    private func т(_ ключ: String) -> String { ПараметрыАвтоText.т(ключ) }

    private var значение: Int? { пробег.isEmpty ? nil : Int(пробег) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if вводом {
                полеВвода
            } else {
                число
            }
            дорожка
                .frame(height: 40)
            шкала
                .frame(height: 14)
        }
        .animation(ДвижениеСайта.смена, value: вводом)
        .onChange(of: фокус) { _, стало in
            if !стало && вводом { вводом = false }
        }
    }

    // MARK: Шкала: доля дорожки ⇄ километры

    /// Доля дорожки → километры по шагу своего участка.
    static func километры(доля: Double) -> Int {
        let д = min(max(доля.isFinite ? доля : 0, 0), 1)
        if д <= 0.40 { return Int((д / 0.40 * 100).rounded()) * 1_000 }
        if д <= 0.75 { return 100_000 + Int(((д - 0.40) / 0.35 * 40).rounded()) * 5_000 }
        return 300_000 + Int(((д - 0.75) / 0.25 * 70).rounded()) * 10_000
    }

    /// Километры → доля дорожки (обратное к километры(доля:)); больше 1 млн — конец дорожки.
    static func доля(_ км: Int) -> Double {
        let v = Double(min(max(км, 0), предел))
        if v <= 100_000 { return v / 100_000 * 0.40 }
        if v <= 300_000 { return 0.40 + (v - 100_000) / 200_000 * 0.35 }
        return 0.75 + (v - 300_000) / 700_000 * 0.25
    }

    // MARK: Число и точный ввод

    private var число: some View {
        Button {
            открытьВвод()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let км = значение {
                        Text(ПодачаМодель.деньги(км))
                            .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(КраскаПодачи.текст)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        Text(т("aw_km"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Theme.текстВторой)
                    } else {
                        Text(т("ap_mileage_drag"))
                            .font(.system(size: 21, weight: .heavy))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(т("ap_mileage_exact"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(КраскаПодачи.хорошоФон, in: Capsule())
            }
            .frame(minHeight: 46)
            .animation(ДвижениеСайта.мягко(.snappy(duration: 0.18)), value: пробег)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(т("ap_exact_hint"))
    }

    private var полеВвода: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(т("ap_mileage_ph"), text: точно)
                    .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(КраскаПодачи.текст)
                    .keyboardType(.numberPad)
                    .focused($фокус)
                Text(т("aw_km"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.акцентТекст, lineWidth: 1.5)
            }
            Button {
                фокус = false
                вводом = false
            } label: {
                Text(т("m_done"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }

    /// Только цифры, не длиннее 7 знаков (до 9 999 999 км).
    private var точно: Binding<String> {
        let связь = $пробег
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.цифры(новое, предел: 7)
        })
    }

    private func открытьВвод() {
        вводом = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            фокус = true
        }
    }

    // MARK: Дорожка и ручка

    /// Дорожка всегда слева направо: километры и в арабском растут вправо.
    private var дорожка: some View {
        GeometryReader { гео in
            let р = Self.радиус
            let ширина = max(1, гео.size.width - р * 2)
            let км = значение ?? прикидка
            let доля = CGFloat(Self.доля(км))
            let есть = значение != nil
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(КраскаПодачи.поле)
                    .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                    .frame(height: 12)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: р + ширина * доля, height: 12)
                    .opacity(есть ? 1 : 0.22)
                ForEach(Self.метки, id: \.self) { м in
                    let своя = CGFloat(Self.доля(м))
                    Circle()
                        .fill(есть && своя <= доля ? Color.white.opacity(0.75) : Theme.текстВторой.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .offset(x: р + ширина * своя - 2)
                }
                ручка(есть: есть)
                    .offset(x: ширина * доля)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            /* Нажатие — значение под пальцем; тянут — только вбок: касание, с которого листают экран, пробег не ставит. */
            .onTapGesture { точка in
                поставить(Self.километры(доля: Double((точка.x - р) / ширина)))
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { жест in
                        if !тянут {
                            guard abs(жест.translation.width) > abs(жест.translation.height) else { return }
                            тянут = true
                        }
                        поставить(Self.километры(доля: Double((жест.location.x - р) / ширина)))
                    }
                    .onEnded { _ in
                        тянут = false
                    }
            )
            .animation(тянут ? nil : ДвижениеСайта.смена, value: км)
            .animation(ДвижениеСайта.мягко(.spring(response: 0.28, dampingFraction: 0.7)), value: тянут)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(т("aw_mileage"))
        .accessibilityValue(значение.map { ПодачаМодель.деньги($0) + " " + т("aw_km") } ?? т("ap_mileage_drag"))
        .accessibilityAdjustableAction { куда in
            let сейчас = значение ?? прикидка
            switch куда {
            case .increment: поставить(min(Self.предел, сейчас + Self.шагДоступности(сейчас)))
            case .decrement: поставить(max(0, сейчас - Self.шагДоступности(max(0, сейчас - 1))))
            @unknown default: break
            }
        }
    }

    private func ручка(есть: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: Self.радиус * 2, height: Self.радиус * 2)
            .overlay { Circle().strokeBorder(Theme.зелёный2, lineWidth: 3) }
            .overlay { Circle().fill(Theme.зелёный2).frame(width: 8, height: 8) }
            .shadow(color: Color.black.opacity(тянут ? 0.28 : 0.18), radius: тянут ? 7 : 3, y: тянут ? 3 : 1)
            .scaleEffect(тянут ? 1.25 : 1)
            .opacity(есть ? 1 : 0.55)
    }

    /// Новое значение с дорожки: щелчок — когда перешли через 10 000 км (и при первом касании).
    private func поставить(_ км: Int) {
        let было = значение
        guard км != было else { return }
        if было == nil || (было ?? 0) / 10_000 != км / 10_000 { ОткликСайта.выбор() }
        пробег = String(км)
    }

    /// VoiceOver: шаг пальцем вверх-вниз — крупнее, чем на дорожке.
    private static func шагДоступности(_ км: Int) -> Int {
        км < 100_000 ? 5_000 : (км < 300_000 ? 10_000 : 50_000)
    }

    // MARK: Подписи шкалы

    private var шкала: some View {
        GeometryReader { гео in
            let р = Self.радиус
            let ширина = max(1, гео.size.width - р * 2)
            ZStack(alignment: .topLeading) {
                ForEach(Self.метки, id: \.self) { м in
                    Text(подпись(м))
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: р + ширина * CGFloat(Self.доля(м)), y: 7)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// «0», «50 тыс», «1 млн».
    private func подпись(_ км: Int) -> String {
        if км == 0 { return "0" }
        if км >= 1_000_000 { return String(format: т("ap_m"), String(км / 1_000_000)) }
        return String(format: т("ap_k"), String(км / 1_000))
    }
}

// MARK: - Объём двигателя

/**
 Объём чипами: объёмы поколения (gens[].eng) с переносом строк, без них — ходовые объёмы лентой в ряд; «Другой —
 вписать» (у чипов — последним, в ленте — первым, иначе он за краем экрана) → поле с дробной клавиатурой. Значение —
 «1.6» с точкой на любом языке (поле storage сайта).
 */
struct ВыборОбъёмаАвто: View {
    @Binding var объём: String
    /// «1.4», «1.6» — объёмы поколения или ходовые.
    let варианты: [String]
    /// Ходовые объёмы — лентой в ряд (их много), объёмы поколения — чипами с переносом.
    let лентой: Bool

    @State private var своё = false
    @FocusState private var фокус: Bool

    init(объём: Binding<String>, варианты: [String], лентой: Bool) {
        self._объём = объём
        self.варианты = варианты
        self.лентой = лентой
    }

    private func т(_ ключ: String) -> String { ПараметрыАвтоText.т(ключ) }

    /// 1.6 → «1.6», 2.0 → «2.0», 1.25 → «1.25», 0.66 → «0.66»: до двух знаков после точки, но не меньше одного;
    /// точка на любом языке.
    static func литры(_ л: Double) -> String {
        var с = String(format: "%.2f", л)
        if с.hasSuffix("0") { с.removeLast() }
        return с
    }

    /// «1,6», «1.60» → «1.6» — так значение сверяется с чипами; не число — как есть.
    static func ровно(_ текст: String) -> String {
        let сТочкой = текст.replacingOccurrences(of: ",", with: ".")
        guard let л = Double(сТочкой), л > 0 else { return сТочкой }
        return литры(л)
    }

    private var выбранный: String { Self.ровно(объём) }
    /// Вписан свой объём, которого нет среди чипов.
    private var вписан: Bool { !объём.isEmpty && !варианты.contains(выбранный) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if лентой {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        чипы
                    }
                    .padding(.vertical, 1)
                }
            } else {
                ПотокЧипов(зазор: 8) {
                    чипы
                }
            }
            if своё || вписан {
                поле
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.смена, value: своё)
    }

    @ViewBuilder
    private var чипы: some View {
        if лентой { чипДругой }
        ForEach(варианты, id: \.self) { в in
            ЧипПодачи(в + " " + т("aw_l"), выбран: выбранный == в) {
                выбрать(в)
            }
        }
        if !лентой { чипДругой }
    }

    /// «Другой — вписать»: отмечен, пока поле пустое или в нём объём не из чипов (вписали «1.6» — горит чип «1.6»).
    private var чипДругой: some View {
        ЧипПодачи(т("ap_engine_other"), выбран: вписан || (своё && !варианты.contains(выбранный))) {
            другой()
        }
    }

    private func выбрать(_ в: String) {
        своё = false
        фокус = false
        объём = выбранный == в ? "" : в
        ОткликСайта.выбор()
    }

    /// «Другой — вписать»: открыть поле (выбранный чип снимается) или закрыть его вместе со своим значением.
    private func другой() {
        ОткликСайта.выбор()
        if своё || вписан {
            фокус = false
            своё = false
            if вписан { объём = "" }
            return
        }
        своё = true
        if !объём.isEmpty { объём = "" }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            фокус = true
        }
    }

    private var поле: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField(т("ap_engine_ph"), text: дробное)
                    .font(.system(size: 16))
                    .foregroundStyle(КраскаПодачи.текст)
                    .keyboardType(.decimalPad)
                    .focused($фокус)
                Text(т("aw_l"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            Button {
                фокус = false
                if объём.isEmpty { своё = false }
            } label: {
                Text(т("m_done"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 46)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// «1.6» или «1,6», не длиннее 4 знаков (ПодачаМодель.дробное).
    private var дробное: Binding<String> {
        let связь = $объём
        return Binding(get: { связь.wrappedValue }, set: { новое in
            связь.wrappedValue = ПодачаМодель.дробное(новое, предел: 4)
        })
    }
}

// MARK: - Коробка и топливо

/**
 Слова фильтра витрины чипами: сначала варианты поколения (gens[].gear, gens[].fuel), за ними «Другой…» — он раскрывает
 остальные слова. Данных у поколения нет — все слова сразу. Выбранное снаружи поколения (например, «Газ») — раскрыто.
 Повторное нажатие снимает выбор.
 */
struct ВыборСловаАвто: View {
    let значение: String
    let все: [String]
    let свои: [String]
    let выбрать: (String) -> Void

    @State private var раскрыто = false

    init(значение: String, все: [String], свои: [String], выбрать: @escaping (String) -> Void) {
        self.значение = значение
        self.все = все
        self.свои = свои
        self.выбрать = выбрать
    }

    private var первые: [String] { свои.isEmpty ? все : свои }
    private var остальные: [String] { все.filter { !свои.contains($0) } }
    private var открыто: Bool { свои.isEmpty || раскрыто || (!значение.isEmpty && остальные.contains(значение)) }
    /// Значение из формы, которого нет среди слов (старое объявление), — первым, чтобы было видно и можно снять.
    private var лишнее: Bool { !значение.isEmpty && !все.contains(значение) && !свои.contains(значение) }

    var body: some View {
        ПотокЧипов(зазор: 8) {
            if лишнее { чип(значение) }
            ForEach(первые, id: \.self) { с in
                чип(с)
            }
            if !свои.isEmpty && !остальные.isEmpty {
                if открыто {
                    ForEach(остальные, id: \.self) { с in
                        чип(с)
                    }
                } else {
                    ЧипПодачи(ПараметрыАвтоText.т("ap_more"), выбран: false) {
                        withAnimation(ДвижениеСайта.смена) { раскрыто = true }
                    }
                }
            }
        }
    }

    private func чип(_ с: String) -> some View {
        ЧипПодачи(с, выбран: значение == с) {
            выбрать(значение == с ? "" : с)
            ОткликСайта.выбор()
        }
    }
}

// MARK: - Плитка поколения

/// Отрезок шкалы времени: от доли «с» до доли «по» ширины (не уже высоты — короткое поколение видно точкой).
struct ОтрезокШкалыПоколения: Shape {
    let с: CGFloat
    let по: CGFloat

    func path(in rect: CGRect) -> Path {
        let начало = rect.minX + rect.width * min(max(с, 0), 1)
        let конец = rect.minX + rect.width * min(max(по, 0), 1)
        let ширина = min(rect.width, max(rect.height, конец - начало))
        let x = max(rect.minX, min(начало, rect.maxX - ширина))
        return Path(roundedRect: CGRect(x: x, y: rect.minY, width: ширина, height: rect.height),
                    cornerRadius: rect.height / 2)
    }
}

/**
 Плитка поколения: крупно годы «2002–2007», под ними код поколения, внизу — тонкая шкала времени: где годы поколения
 лежат на отрезке всех лет модели (правее — новее), сразу видно, какое новее. Выбранная — мятная с зелёной кромкой.
 */
struct ПлиткаПоколенияАвто: View {
    let годы: String
    let код: String
    /// Доли начала и конца поколения на шкале модели, 0…1.
    let с: CGFloat
    let по: CGFloat
    let выбрана: Bool
    let действие: () -> Void

    init(годы: String, код: String, с: CGFloat, по: CGFloat, выбрана: Bool, действие: @escaping () -> Void) {
        self.годы = годы
        self.код = код
        self.с = с
        self.по = по
        self.выбрана = выбрана
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button(action: действие) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(годы)
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(КраскаПодачи.текст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if выбрана {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.зелёный2)
                            .transition(.scale.combined(with: .opacity))
                            .accessibilityHidden(true)
                    }
                }
                if !код.isEmpty {
                    Text(код)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
                ZStack {
                    Capsule()
                        .fill(КраскаПодачи.линия)
                    ОтрезокШкалыПоколения(с: с, по: по)
                        .fill(выбрана ? Theme.зелёный2 : КраскаПодачи.акцентТекст.opacity(0.7))
                }
                .frame(height: 5)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(выбрана ? КраскаПодачи.хорошоФон : КраскаПодачи.карточка, in: форма)
            .overlay {
                форма.strokeBorder(выбрана ? КраскаПодачи.акцентТекст : КраскаПодачи.линия, lineWidth: выбрана ? 1.5 : 1)
            }
            .contentShape(форма)
            .animation(ДвижениеСайта.выбор, value: выбрана)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}
