import SwiftUI

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР»: ЖИВАЯ СХЕМА (владелец 16.10.2026: «мощная анимированная подача»; образец подхода — живой
 диск колеса, TryOn/WheelDiskView.swift).

 Компьютер сбоку со снятой крышкой: корпус, материнская плата в масштабе своего форм-фактора (ATX 244×305 мм,
 Micro-ATX 244×244, Mini-ITX 170×170), сокет с подписью (AM4), слоты памяти — сколько их на плате — с планками и объёмом,
 слоты M.2 с SSD, видеокарта в масштабе своей длины и пунктир — предел длины карты в корпусе, блок питания с ваттами,
 отсеки 2.5″ с дисками. Ноутбук — снизу без крышки: батарея, вентиляторы и тепловые трубки, процессор (BGA),
 видеокарта или «встроенная», память — слоты SO-DIMM или распаянные чипы с замком, M.2 и отсек 2.5″.

 Части — кнопки (выбор — в панели под схемой, MyThingsPCParts.swift); выбранная обведена акцентом, заполненные по снимку
 экрана — вспыхивают. Смена значений — мягко: плата меняет размер, планки встают в слоты, карта вытягивается, пунктир
 предела переезжает. При первом показе части собираются каскадом, вентиляторы медленно крутятся. «Уменьшение
 движения» (ДвижениеСайта.тихо) — всё сразу и без вращения; лёгкий режим (РежимУстройства) — без свечения, каскада и
 вращения. Неизвестное рисуется обычным (ATX, 4 слота, карта 240 мм) и бледнее. Надписи — цифры и латиница, рисунок
 всегда слева направо.
 */

// MARK: - Краска

/// Цвета рисунка: плата зелёная, чипы и пазы тёмные в обеих темах, металл в тёмной — глуше.
enum КраскаКомпьютераМоего {
    static let корпус = Theme.цвет(0xEEF3F0, 0x20222B)
    static let кромка = Theme.цвет(0xB9C6BF, 0x3A3F4B)
    static let плата = Theme.цвет(0x2F6F52, 0x1D4A37)
    static let платаКромка = Theme.цвет(0x23573F, 0x2C6A4E)
    static let чип = Theme.цвет(0x2B302D, 0x0D100E)
    static let металл = Theme.цвет(0xC9D2CD, 0x6E7973)
    static let паз = Theme.цвет(0x1C2420, 0x0B0F0D)
    static let планка = Theme.цвет(0x1F7A55, 0x2E9E6E)
    static let контакты = Theme.цвет(0xC9A227, 0xB8923A)
    static let ssd = Theme.цвет(0x27313B, 0x0F151B)
    static let карта = Theme.цвет(0x3A413D, 0x2A302C)
    static let кожух = Theme.цвет(0x59635E, 0x48514C)
    static let бп = Theme.цвет(0x3A413D, 0x262D29)
    static let батарея = Theme.цвет(0xD9E2DC, 0x2A3330)
    static let трубка = Theme.цвет(0xB87333, 0x8A5A2B)
    static let вентилятор = Theme.цвет(0x9AA8A1, 0x5A6560)
    static let надпись = Color.white.opacity(0.92)
    static let надписьТёмная = Theme.цвет(0x3B4540, 0xB9C6BF)
}

// MARK: - Данные рисунка

/// Всё, что рисует схема, — одним значением: смена любого поля анимируется целиком.
struct ДанныеСхемыКомпьютераМоего: Equatable {
    struct Слот: Equatable {
        /// Длина M.2, мм (80 у 2280).
        var длина: CGFloat
        var занят: Bool
        var подпись: String?
    }

    var ноутбук: Bool
    var сокет: String?
    var платаШирина: CGFloat
    var платаВысота: CGFloat
    var платаИзвестна: Bool
    var слотов: Int
    var слотыИзвестны: Bool
    var планки: [Int]
    var всего: Int?
    var распаяно: Int?
    var всяРаспаяна: Bool
    var картаДлина: CGFloat?
    var картаЕсть: Bool
    var встроенная: Bool
    var картаПодпись: String?
    var пределКарты: CGFloat?
    var бпВатт: Int?
    var m2: [Слот]
    var отсеков: Int
    var диски: [String]

    init(_ к: КомпьютерМоего) {
        ноутбук = к.вид == .ноутбук
        сокет = к.сокетДляСверки
        if let код = к.корпус.плата, let ф = КаталогСтандартов.формыПлат.first(where: { $0.код == код }) {
            // Сбоку видно: по горизонтали — глубина платы (244), по вертикали — ширина (305).
            платаШирина = CGFloat(ф.глубина)
            платаВысота = CGFloat(ф.ширина)
            платаИзвестна = true
        } else {
            платаШирина = 244
            платаВысота = 305
            платаИзвестна = false
        }
        let м = к.память
        планки = м.планки
        всего = м.всего
        распаяно = м.распаяно
        всяРаспаяна = м.всяРаспаяна
        if let n = м.слотов {
            слотов = n
            слотыИзвестны = true
        } else {
            слотов = к.вид == .ноутбук ? 2 : 4
            слотыИзвестны = false
        }
        слотов = min(8, max(слотов, м.планки.count))
        let в = к.видеокарта
        встроенная = в.встроенная && в.чип == nil
        картаЕсть = в.чип != nil || в.длина != nil
        картаДлина = в.длина.map { CGFloat($0) }
        картаПодпись = в.чип
        пределКарты = к.корпус.длинаКарты.map { CGFloat($0) }
        бпВатт = к.бп.ватт
        // Слоты M.2 и диски в них по порядку; дисков M.2 без слотов — рисуем их занятыми слотами.
        let дискиM2 = к.накопители.filter { КаталогСтандартов.длинаM2($0.форма) != nil }
        var слоты: [Слот] = []
        var номерДиска = 0
        for слот in к.слотыM2 {
            var подпись: String? = nil
            if слот.занят, номерДиска < дискиM2.count {
                подпись = дискиM2[номерДиска].тб.map { ФорматКомпьютераМоего.объём($0) }
                номерДиска += 1
            }
            слоты.append(Слот(длина: CGFloat(КаталогСтандартов.длинаM2(слот.длина) ?? 80), занят: слот.занят,
                              подпись: подпись))
        }
        if слоты.isEmpty {
            for диск in дискиM2.prefix(3) {
                слоты.append(Слот(длина: CGFloat(КаталогСтандартов.длинаM2(диск.форма) ?? 80), занят: true,
                                  подпись: диск.тб.map { ФорматКомпьютераМоего.объём($0) }))
            }
        }
        m2 = слоты
        отсеков = к.отсеков25 ?? 0
        диски = к.накопители.filter { КаталогСтандартов.длинаM2($0.форма) == nil }.map { ФорматКомпьютераМоего.диск($0) }
    }
}

// MARK: - Разметка корпуса

/// Места частей настольного компьютера в точках холста 100 × 80 единиц (u — точек в единице).
private struct РазметкаКорпусаМоего {
    let корпус: CGRect
    let вентилятор: CGRect
    let плата: CGRect
    let процессор: CGRect
    let слоты: [CGRect]
    let память: CGRect
    let подписьПамяти: CGRect
    let m2: [CGRect]
    let накопителиПлаты: CGRect
    let карта: CGRect
    let пределX: CGFloat?
    let картаГруппа: CGRect
    let бп: CGRect
    let отсеки: [CGRect]
    let отсекиГруппа: CGRect

    /// Миллиметров в единице холста: плата ATX (305 мм) — 56 единиц.
    static let масштаб: CGFloat = 56.0 / 305.0

    init(_ д: ДанныеСхемыКомпьютераМоего, u: CGFloat) {
        func р(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * u, y: y * u, width: max(0, w) * u, height: max(0, h) * u)
        }
        let s = Self.масштаб
        let bw = д.платаШирина * s
        let bh = д.платаВысота * s
        let bx: CGFloat = 16
        let by: CGFloat = 4
        корпус = р(1, 1, 98, 78)
        вентилятор = р(3, 6.5, 11, 11)
        плата = р(bx, by, bw, bh)
        let сторона = 0.26 * bw
        процессор = р(bx + 0.14 * bw, by + 0.10 * bh, сторона, сторона)
        let n = max(1, д.слотов)
        let x0 = bx + 0.58 * bw
        let шаг = min(0.085 * bw, 0.36 * bw / CGFloat(n))
        let ширинаСлота = min(0.045 * bw, шаг * 0.62)
        let yСлота = by + 0.07 * bh
        let hСлота = 0.40 * bh
        слоты = (0..<n).map { i in р(x0 + CGFloat(i) * шаг, yСлота, ширинаСлота, hСлота) }
        память = р(x0 - 0.03 * bw, yСлота - 1.2, CGFloat(n) * шаг + 0.03 * bw, hСлота + 5.6)
        подписьПамяти = р(x0 - 0.03 * bw, yСлота + hСлота + 0.6, CGFloat(n) * шаг + 0.03 * bw, 3.4)
        let рядов = min(3, д.m2.count)
        m2 = (0..<рядов).map { i in
            р(bx + 0.08 * bw, by + 0.56 * bh + CGFloat(i) * 0.075 * bh, д.m2[i].длина / 80 * 0.40 * bw, 0.05 * bh)
        }
        накопителиПлаты = р(bx + 0.05 * bw, by + 0.53 * bh, 0.5 * bw,
                            max(CGFloat(max(1, рядов)) * 0.075 * bh, 0.09 * bh) + 0.02 * bh)
        let высотаКарты = max(4, 0.11 * bh)
        let yКарты = by + 0.80 * bh
        let длинаКарты = (д.картаДлина ?? 240) * s
        карта = р(bx - 1.5, yКарты, длинаКарты, высотаКарты)
        пределX = д.пределКарты.map { (bx + $0 * s) * u }
        let конецКарты = bx - 1.5 + длинаКарты
        let конецПредела = д.пределКарты.map { bx + $0 * s } ?? 0
        let правый = min(98, max(конецКарты, конецПредела) + 3)
        картаГруппа = р(bx - 3, yКарты - 4.5, правый - (bx - 3), высотаКарты + 8)
        бп = р(4, 64, 40, 13)
        let отсековВсего = min(4, max(д.отсеков, д.диски.count))
        отсеки = (0..<отсековВсего).map { i in р(60, 64.6 + CGFloat(i) * 3.2, 34, 2.5) }
        отсекиГруппа = р(57, 62.5, 40, 15)
    }

    /// Рамки подсветки части.
    func рамки(_ часть: ЧастьКомпьютераМоего) -> [CGRect] {
        switch часть {
        case .корпус: return [корпус]
        case .процессор: return [процессор]
        case .память: return [память]
        case .видеокарта: return [карта]
        case .бп: return [бп]
        case .накопители: return [накопителиПлаты, отсекиГруппа]
        }
    }
}

// MARK: - Разметка ноутбука

/// Места частей ноутбука снизу в точках холста 100 × 64 единицы.
private struct РазметкаНоутбукаМоего {
    let корпус: CGRect
    let батарея: CGRect
    let вентиляторЛ: CGRect
    let вентиляторП: CGRect
    let процессор: CGRect
    let карта: CGRect
    let память: CGRect
    let слоты: [CGRect]
    let чипы: [CGRect]
    let подписьПамяти: CGRect
    let m2: [CGRect]
    let m2Группа: CGRect
    let отсек: CGRect
    let трубки: [(CGPoint, CGPoint)]

    init(_ д: ДанныеСхемыКомпьютераМоего, u: CGFloat) {
        func р(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * u, y: y * u, width: max(0, w) * u, height: max(0, h) * u)
        }
        func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u, y: y * u) }
        корпус = р(2, 2, 96, 60)
        батарея = р(8, 37, 84, 21)
        вентиляторЛ = р(6, 7, 15, 15)
        вентиляторП = р(79, 7, 15, 15)
        процессор = р(28, 8, 11, 11)
        карта = р(42, 8.5, 10, 10)
        память = р(55, 4, 27, 30)
        let слотов = д.всяРаспаяна ? 0 : min(3, max(1, д.слотов))
        слоты = (0..<слотов).map { i in р(57, 6 + CGFloat(i) * 6.2, 22, 4.6) }
        var места: [CGRect] = []
        if д.всяРаспаяна {
            for ряд in 0..<2 {
                for j in 0..<4 { места.append(р(57 + CGFloat(j) * 5.7, 7 + CGFloat(ряд) * 6.4, 4.4, 4.4)) }
            }
        } else if (д.распаяно ?? 0) > 0 {
            for j in 0..<4 { места.append(р(57 + CGFloat(j) * 5.7, 6 + CGFloat(слотов) * 6.2 + 0.6, 4.4, 4.4)) }
        }
        чипы = места
        подписьПамяти = р(56, 29, 25, 3.6)
        let рядов = min(2, д.m2.count)
        m2 = (0..<рядов).map { i in р(24, 24 + CGFloat(i) * 5.2, д.m2[i].длина / 80 * 20, 3.6) }
        m2Группа = р(22, 22.5, 26, 12)
        отсек = р(84, 23.5, 11, 11)
        трубки = [(т(20, 14.5), т(28, 13.5)), (т(52, 13.5), т(79.5, 14.5))]
    }

    func рамки(_ часть: ЧастьКомпьютераМоего) -> [CGRect] {
        switch часть {
        case .процессор: return [процессор]
        case .память: return [память]
        case .видеокарта: return [карта]
        case .накопители: return [m2Группа, отсек]
        case .бп, .корпус: return []
        }
    }
}

// MARK: - Размещение

fileprivate extension View {
    /// Элемент части на своё место: рамка — в точках холста, начало — левый верх части.
    func элементСхемыКомпьютераМоего(_ рамка: CGRect, от начало: CGPoint) -> some View {
        frame(width: max(0, рамка.width), height: max(0, рамка.height))
            .offset(x: рамка.minX - начало.x, y: рамка.minY - начало.y)
    }

    /// Вид во всю рамку холста.
    func местоСхемыКомпьютераМоего(_ рамка: CGRect) -> some View {
        frame(width: max(0, рамка.width), height: max(0, рамка.height))
            .position(x: рамка.midX, y: рамка.midY)
    }
}

// MARK: - Живая схема

/// Компьютер сбоку или ноутбук снизу; части — кнопки, выбор — в панели под схемой.
@MainActor
struct ЖиваяСхемаКомпьютераМоего: View {
    let компьютер: КомпьютерМоего
    let выбрана: ЧастьКомпьютераМоего
    let вспышка: Set<ЧастьКомпьютераМоего>
    let выбрать: (ЧастьКомпьютераМоего) -> Void
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var собрано: Bool

    init(компьютер: КомпьютерМоего, выбрана: ЧастьКомпьютераМоего, вспышка: Set<ЧастьКомпьютераМоего>,
         выбрать: @escaping (ЧастьКомпьютераМоего) -> Void) {
        self.компьютер = компьютер
        self.выбрана = выбрана
        self.вспышка = вспышка
        self.выбрать = выбрать
        _собрано = State(initialValue: ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий)
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    /// Смена значений: пружина, в лёгком режиме — коротко, при «Уменьшении движения» — сразу.
    private var анимация: Animation? {
        ДвижениеСайта.мягко(режим.лёгкий ? .easeOut(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.8))
    }

    var body: some View {
        let д = ДанныеСхемыКомпьютераМоего(компьютер)
        let высота: CGFloat = д.ноутбук ? 64 : 80
        return GeometryReader { место in
            let u = место.size.width / 100
            холст(д, u)
                .frame(width: место.size.width, height: место.size.height, alignment: .topLeading)
        }
        .aspectRatio(100 / высота, contentMode: .fit)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .animation(анимация, value: д)
        .animation(ДвижениеСайта.выбор, value: выбрана)
        .animation(ДвижениеСайта.мягко(.easeInOut(duration: 0.6)), value: вспышка)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard !собрано else { return }
            if тихо {
                собрано = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { собрано = true }
            }
        }
    }

    @ViewBuilder
    private func холст(_ д: ДанныеСхемыКомпьютераМоего, _ u: CGFloat) -> some View {
        if д.ноутбук {
            ноутбук(д, РазметкаНоутбукаМоего(д, u: u), u)
        } else {
            корпус(д, РазметкаКорпусаМоего(д, u: u), u)
        }
    }

    // MARK: Общее

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    /// Часть — кнопка на своём месте: имя и значение для VoiceOver, «выбрана» — признаком; при первом показе —
    /// каскадом по номеру.
    private func кнопка<Рисунок: View>(_ часть: ЧастьКомпьютераМоего, _ рамка: CGRect, номер: Int,
                                       @ViewBuilder рисунок: () -> Рисунок) -> some View {
        Button {
            выбрать(часть)
        } label: {
            рисунок()
                .frame(width: max(1, рамка.width), height: max(1, рамка.height), alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        .accessibilityLabel(часть.название)
        .accessibilityValue(часть.значение(компьютер) ?? т("mpc_unset"))
        .accessibilityHint(т("mpc_a11y_part"))
        .accessibilityAddTraits(выбрана == часть ? .isSelected : [])
        .accessibilitySortPriority(Double(10 - номер))
        .opacity(собрано ? 1 : 0)
        .scaleEffect(собрано ? 1 : 0.92)
        .animation(ДвижениеСайта.мягко(.spring(response: 0.5, dampingFraction: 0.86).delay(0.06 * Double(номер))),
                   value: собрано)
        .position(x: рамка.midX, y: рамка.midY)
    }

    /// Мелкая надпись рисунка: цифры и латиница, не меньше 6 pt.
    private func надпись(_ текст: String, _ u: CGFloat, кегль: CGFloat = 2.3, светлая: Bool = true) -> some View {
        Text(текст)
            .font(.system(size: max(6, кегль * u), weight: .heavy, design: .rounded))
            .foregroundStyle(светлая ? КраскаКомпьютераМоего.надпись : КраскаКомпьютераМоего.надписьТёмная)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// Обводка выбранной части и вспышка заполненных по снимку. Касаний не ловит.
    private func подсветка(_ пары: [(часть: ЧастьКомпьютераМоего, рамка: CGRect)], _ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(пары.enumerated()), id: \.offset) { _, пара in
                let место = пара.рамка.insetBy(dx: -0.8 * u, dy: -0.8 * u)
                let форма = RoundedRectangle(cornerRadius: 1.6 * u, style: .continuous)
                форма
                    .fill(Theme.акцент.opacity(0.24))
                    .opacity(вспышка.contains(пара.часть) ? 1 : 0)
                    .местоСхемыКомпьютераМоего(место)
                форма
                    .stroke(Theme.акцент, lineWidth: 2.5)
                    .shadow(color: режим.лёгкий ? .clear : Theme.акцент.opacity(0.5), radius: 5)
                    .opacity(пара.часть == выбрана || вспышка.contains(пара.часть) ? 1 : 0)
                    .местоСхемыКомпьютераМоего(место)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Пары «часть — рамка» для подсветки.
    private static func пары(_ части: [ЧастьКомпьютераМоего],
                             _ рамки: (ЧастьКомпьютераМоего) -> [CGRect]) -> [(часть: ЧастьКомпьютераМоего, рамка: CGRect)] {
        var итог: [(часть: ЧастьКомпьютераМоего, рамка: CGRect)] = []
        for часть in части {
            for рамка in рамки(часть) { итог.append((часть: часть, рамка: рамка)) }
        }
        return итог
    }

    // MARK: Настольный

    private func корпус(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            частьКорпуса(д, р, u)
            декорКорпуса(д, р, u)
            частьПроцессора(д, р.процессор, u)
            частьПамяти(д, р, u)
            частьM2(д, р, u)
            частьКарты(д, р, u)
            частьБП(д, р, u)
            частьОтсеков(д, р, u)
            подсветка(Self.пары(ЧастьКомпьютераМоего.части(.настольный)) { р.рамки($0) }, u)
        }
        .frame(width: 100 * u, height: 80 * u, alignment: .topLeading)
    }

    private func частьКорпуса(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        let г = р.корпус
        return кнопка(.корпус, г, номер: 0) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 3 * u, style: .continuous)
                    .fill(КраскаКомпьютераМоего.корпус)
                RoundedRectangle(cornerRadius: 3 * u, style: .continuous)
                    .strokeBorder(КраскаКомпьютераМоего.кромка, lineWidth: max(1.5, 0.6 * u))
                // Перегородка над блоком питания.
                Rectangle()
                    .fill(КраскаКомпьютераМоего.кромка.opacity(0.7))
                    .frame(height: max(1, 0.5 * u))
                    .padding(.bottom, 16.5 * u)
                    .padding(.horizontal, 2 * u)
                if компьютер.корпус.плата != nil || компьютер.корпус.длинаКарты != nil {
                    надпись(компьютер.корпус.плата ?? "PC", u, кегль: 2.1, светлая: false)
                        .padding(.trailing, 2.4 * u)
                        .padding(.bottom, 18 * u)
                }
            }
        }
    }

    /// Задний вентилятор, плата с портами — без касаний.
    private func декорКорпуса(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ВентиляторКомпьютераМоего(крутится: !тихо)
                .местоСхемыКомпьютераМоего(р.вентилятор)
            RoundedRectangle(cornerRadius: 1.2 * u, style: .continuous)
                .fill(КраскаКомпьютераМоего.плата)
                .overlay {
                    RoundedRectangle(cornerRadius: 1.2 * u, style: .continuous)
                        .strokeBorder(КраскаКомпьютераМоего.платаКромка, lineWidth: max(1, 0.4 * u))
                }
                .opacity(д.платаИзвестна ? 1 : 0.55)
                .местоСхемыКомпьютераМоего(р.плата)
            // Порты на задней кромке платы.
            RoundedRectangle(cornerRadius: 0.4 * u)
                .fill(КраскаКомпьютераМоего.металл)
                .местоСхемыКомпьютераМоего(CGRect(x: р.плата.minX - 1.6 * u, y: р.плата.minY + 1.5 * u,
                                                  width: 2.2 * u, height: min(14 * u, р.плата.height * 0.3)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func частьПроцессора(_ д: ДанныеСхемыКомпьютераМоего, _ г: CGRect, _ u: CGFloat) -> some View {
        кнопка(.процессор, г, номер: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous)
                    .fill(КраскаКомпьютераМоего.металл)
                RoundedRectangle(cornerRadius: 0.6 * u, style: .continuous)
                    .fill(КраскаКомпьютераМоего.чип)
                    .padding(max(1.5, г.width * 0.12))
                надпись(д.сокет ?? "CPU", u, кегль: 2.2)
                    .padding(.horizontal, 1.2 * u)
            }
            .opacity(д.сокет == nil && компьютер.процессор.isEmpty ? 0.55 : 1)
        }
    }

    private func частьПамяти(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        let г = р.память
        return кнопка(.память, г, номер: 2) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(р.слоты.enumerated()), id: \.offset) { i, слот in
                    слотПамяти(i < д.планки.count, u)
                        .opacity(д.слотыИзвестны || i < д.планки.count ? 1 : 0.55)
                        .элементСхемыКомпьютераМоего(слот, от: г.origin)
                }
                надпись(д.всего.map { ФорматКомпьютераМоего.гб($0) } ?? "RAM", u, кегль: 2.2, светлая: false)
                    .frame(maxWidth: .infinity)
                    .элементСхемыКомпьютераМоего(р.подписьПамяти, от: г.origin)
            }
        }
    }

    /// Паз слота и планка в нём: зелёная плата с золотыми контактами снизу; пустой — только паз.
    private func слотПамяти(_ есть: Bool, _ u: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 0.5 * u)
                .fill(КраскаКомпьютераМоего.паз)
            RoundedRectangle(cornerRadius: 0.5 * u)
                .fill(КраскаКомпьютераМоего.планка)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(КраскаКомпьютераМоего.контакты)
                        .frame(height: max(1, 1.2 * u))
                }
                .opacity(есть ? 1 : 0)
                .scaleEffect(x: 1, y: есть ? 1 : 0.35, anchor: .bottom)
        }
    }

    private func частьM2(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        let г = р.накопителиПлаты
        return кнопка(.накопители, г, номер: 3) {
            ZStack(alignment: .topLeading) {
                if р.m2.isEmpty {
                    RoundedRectangle(cornerRadius: 0.5 * u)
                        .strokeBorder(КраскаКомпьютераМоего.надпись.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .overlay { надпись("M.2", u, кегль: 1.8) }
                        .элементСхемыКомпьютераМоего(CGRect(x: г.minX + 0.6 * u, y: г.minY + 0.6 * u,
                                                            width: min(г.width - 1.2 * u, 14 * u),
                                                            height: max(2.6 * u, г.height - 1.2 * u)), от: г.origin)
                }
                ForEach(Array(р.m2.enumerated()), id: \.offset) { i, рамка in
                    слотM2(д.m2[i], u)
                        .элементСхемыКомпьютераМоего(рамка, от: г.origin)
                }
            }
        }
    }

    private func слотM2(_ слот: ДанныеСхемыКомпьютераМоего.Слот, _ u: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0.4 * u)
                .fill(КраскаКомпьютераМоего.паз)
            RoundedRectangle(cornerRadius: 0.4 * u)
                .fill(КраскаКомпьютераМоего.ssd)
                .overlay {
                    if let подпись = слот.подпись {
                        надпись(подпись, u, кегль: 1.6)
                    }
                }
                .opacity(слот.занят ? 1 : 0)
                .scaleEffect(x: слот.занят ? 1 : 0.5, y: 1, anchor: .leading)
        }
    }

    private func частьКарты(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        let г = р.картаГруппа
        return кнопка(.видеокарта, г, номер: 4) {
            ZStack(alignment: .topLeading) {
                рисунокКарты(д, u)
                    .элементСхемыКомпьютераМоего(р.карта, от: г.origin)
                if let x = р.пределX {
                    let линия = CGRect(x: x - 0.5, y: р.карта.minY - 2.4 * u, width: 1, height: р.карта.height + 4.8 * u)
                    Rectangle()
                        .stroke(Theme.акцент, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .элементСхемыКомпьютераМоего(линия, от: г.origin)
                    if let предел = компьютер.корпус.длинаКарты {
                        надпись("≤" + String(предел), u, кегль: 1.8, светлая: false)
                            .fixedSize()
                            .элементСхемыКомпьютераМоего(CGRect(x: x - 9 * u, y: р.карта.minY - 4.4 * u,
                                                                width: 8.4 * u, height: 2.4 * u), от: г.origin)
                    }
                }
            }
        }
    }

    /// Видеокарта: кожух с вентиляторами и подпись чипа; встроенная — пунктир «iGPU»; неизвестная — бледная.
    @ViewBuilder
    private func рисунокКарты(_ д: ДанныеСхемыКомпьютераМоего, _ u: CGFloat) -> some View {
        if д.встроенная {
            RoundedRectangle(cornerRadius: 0.8 * u)
                .strokeBorder(КраскаКомпьютераМоего.надписьТёмная.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .overlay { надпись("iGPU", u, кегль: 2, светлая: false) }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous)
                    .fill(КраскаКомпьютераМоего.кожух)
                HStack(spacing: 1.2 * u) {
                    ForEach(0..<2, id: \.self) { _ in
                        Circle()
                            .fill(КраскаКомпьютераМоего.карта)
                            .overlay { Circle().stroke(КраскаКомпьютераМоего.вентилятор, lineWidth: 1) }
                            .aspectRatio(1, contentMode: .fit)
                    }
                    Spacer(minLength: 0)
                }
                .padding(0.7 * u)
                надпись(д.картаПодпись ?? "GPU", u, кегль: 2)
                    .padding(.leading, 12 * u)
                    .padding(.trailing, 1 * u)
            }
            .overlay(alignment: .leading) {
                // Планка крепления у задней стенки.
                Rectangle()
                    .fill(КраскаКомпьютераМоего.металл)
                    .frame(width: max(1.5, 0.6 * u))
            }
            .opacity(д.картаЕсть ? 1 : 0.5)
        }
    }

    private func частьБП(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        кнопка(.бп, р.бп, номер: 5) {
            HStack(spacing: 1.6 * u) {
                Circle()
                    .stroke(КраскаКомпьютераМоего.вентилятор, lineWidth: max(1, 0.4 * u))
                    .overlay { ЛопастиКомпьютераМоего().fill(КраскаКомпьютераМоего.вентилятор.opacity(0.7)) }
                    .padding(1.4 * u)
                    .aspectRatio(1, contentMode: .fit)
                VStack(alignment: .leading, spacing: 0.4 * u) {
                    надпись(д.бпВатт.map { String($0) + " W" } ?? "PSU", u, кегль: 2.6)
                        .contentTransition(.numericText())
                    if let с = компьютер.бп.сертификат {
                        надпись(с.replacingOccurrences(of: "80+ ", with: "80+"), u, кегль: 1.6)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 1 * u)
            .background(КраскаКомпьютераМоего.бп, in: RoundedRectangle(cornerRadius: 1 * u, style: .continuous))
            .opacity(д.бпВатт == nil ? 0.55 : 1)
        }
    }

    private func частьОтсеков(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаКорпусаМоего, _ u: CGFloat) -> some View {
        let г = р.отсекиГруппа
        return кнопка(.накопители, г, номер: 6) {
            ZStack(alignment: .topLeading) {
                if р.отсеки.isEmpty {
                    RoundedRectangle(cornerRadius: 0.5 * u)
                        .strokeBorder(КраскаКомпьютераМоего.надписьТёмная.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .overlay { надпись("2.5″", u, кегль: 1.8, светлая: false) }
                        .элементСхемыКомпьютераМоего(CGRect(x: г.minX + 3 * u, y: г.minY + 2 * u, width: 34 * u,
                                                            height: 11 * u), от: г.origin)
                }
                ForEach(Array(р.отсеки.enumerated()), id: \.offset) { i, рамка in
                    отсек(i < д.диски.count ? д.диски[i] : nil, u)
                        .элементСхемыКомпьютераМоего(рамка, от: г.origin)
                }
            }
        }
    }

    private func отсек(_ диск: String?, _ u: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 0.4 * u)
            .fill(диск == nil ? КраскаКомпьютераМоего.кромка.opacity(0.5) : КраскаКомпьютераМоего.ssd)
            .overlay {
                if let диск {
                    надпись(диск, u, кегль: 1.7)
                }
            }
    }

    // MARK: Ноутбук

    private func ноутбук(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего, _ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            декорНоутбука(р, u)
            частьПроцессораНоутбука(д, р, u)
            частьКартыНоутбука(д, р, u)
            частьПамятиНоутбука(д, р, u)
            частьM2Ноутбука(д, р, u)
            частьОтсекаНоутбука(д, р, u)
            подсветка(Self.пары(ЧастьКомпьютераМоего.части(.ноутбук)) { р.рамки($0) }, u)
        }
        .frame(width: 100 * u, height: 64 * u, alignment: .topLeading)
    }

    /// Корпус снизу, батарея, вентиляторы и тепловые трубки — без касаний.
    private func декорНоутбука(_ р: РазметкаНоутбукаМоего, _ u: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4 * u, style: .continuous)
                .fill(КраскаКомпьютераМоего.корпус)
                .overlay {
                    RoundedRectangle(cornerRadius: 4 * u, style: .continuous)
                        .strokeBorder(КраскаКомпьютераМоего.кромка, lineWidth: max(1.5, 0.6 * u))
                }
                .местоСхемыКомпьютераМоего(р.корпус)
            RoundedRectangle(cornerRadius: 1.6 * u, style: .continuous)
                .fill(КраскаКомпьютераМоего.батарея)
                .overlay {
                    Image(systemName: "battery.100")
                        .font(.system(size: max(10, 5 * u), weight: .regular))
                        .foregroundStyle(КраскаКомпьютераМоего.надписьТёмная.opacity(0.6))
                }
                .местоСхемыКомпьютераМоего(р.батарея)
            Path { путь in
                for (от, до) in р.трубки {
                    путь.move(to: от)
                    путь.addLine(to: до)
                }
            }
            .stroke(КраскаКомпьютераМоего.трубка, style: StrokeStyle(lineWidth: max(2, 1.2 * u), lineCap: .round))
            ВентиляторКомпьютераМоего(крутится: !тихо)
                .местоСхемыКомпьютераМоего(р.вентиляторЛ)
            ВентиляторКомпьютераМоего(крутится: !тихо)
                .местоСхемыКомпьютераМоего(р.вентиляторП)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func частьПроцессораНоутбука(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего,
                                         _ u: CGFloat) -> some View {
        кнопка(.процессор, р.процессор, номер: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous)
                    .fill(КраскаКомпьютераМоего.чип)
                RoundedRectangle(cornerRadius: 0.5 * u, style: .continuous)
                    .stroke(КраскаКомпьютераМоего.металл, lineWidth: 1)
                    .padding(1.6 * u)
                надпись("CPU", u, кегль: 2)
            }
            .opacity(компьютер.процессор.isEmpty ? 0.6 : 1)
        }
    }

    private func частьКартыНоутбука(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего,
                                    _ u: CGFloat) -> some View {
        кнопка(.видеокарта, р.карта, номер: 2) {
            ZStack {
                if д.картаЕсть {
                    RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous)
                        .fill(КраскаКомпьютераМоего.чип)
                    надпись(д.картаПодпись.map { Self.коротко($0) } ?? "GPU", u, кегль: 1.8)
                        .padding(.horizontal, 0.8 * u)
                } else {
                    RoundedRectangle(cornerRadius: 0.8 * u, style: .continuous)
                        .strokeBorder(КраскаКомпьютераМоего.надписьТёмная.opacity(0.5),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    надпись(д.встроенная ? "iGPU" : "GPU", u, кегль: 1.8, светлая: false)
                }
            }
        }
    }

    /// «RTX 4060» → «4060» на маленьком чипе.
    static func коротко(_ чип: String) -> String {
        let части = чип.split(separator: " ")
        guard части.count >= 2 else { return чип }
        return части.dropFirst().joined(separator: " ")
    }

    private func частьПамятиНоутбука(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего,
                                     _ u: CGFloat) -> some View {
        let г = р.память
        return кнопка(.память, г, номер: 3) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(р.слоты.enumerated()), id: \.offset) { i, слот in
                    планкаНоутбука(i < д.планки.count, u)
                        .opacity(д.слотыИзвестны || i < д.планки.count ? 1 : 0.55)
                        .элементСхемыКомпьютераМоего(слот, от: г.origin)
                }
                ForEach(Array(р.чипы.enumerated()), id: \.offset) { _, чип in
                    RoundedRectangle(cornerRadius: 0.4 * u)
                        .fill(КраскаКомпьютераМоего.чип)
                        .элементСхемыКомпьютераМоего(чип, от: г.origin)
                }
                HStack(spacing: 0.6 * u) {
                    if д.всяРаспаяна {
                        Image(systemName: "lock.fill")
                            .font(.system(size: max(6, 1.8 * u), weight: .bold))
                            .foregroundStyle(КраскаКомпьютераМоего.надписьТёмная)
                    }
                    надпись(д.всего.map { ФорматКомпьютераМоего.гб($0) } ?? "RAM", u, кегль: 2, светлая: false)
                }
                .frame(maxWidth: .infinity)
                .элементСхемыКомпьютераМоего(р.подписьПамяти, от: г.origin)
            }
        }
    }

    /// SO-DIMM лёжа: паз и планка с контактами слева.
    private func планкаНоутбука(_ есть: Bool, _ u: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 0.4 * u)
                .fill(КраскаКомпьютераМоего.паз)
            RoundedRectangle(cornerRadius: 0.4 * u)
                .fill(КраскаКомпьютераМоего.планка)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(КраскаКомпьютераМоего.контакты)
                        .frame(width: max(1, 1.2 * u))
                }
                .opacity(есть ? 1 : 0)
                .scaleEffect(x: есть ? 1 : 0.35, y: 1, anchor: .leading)
        }
    }

    private func частьM2Ноутбука(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего,
                                 _ u: CGFloat) -> some View {
        let г = р.m2Группа
        return кнопка(.накопители, г, номер: 4) {
            ZStack(alignment: .topLeading) {
                if р.m2.isEmpty {
                    RoundedRectangle(cornerRadius: 0.5 * u)
                        .strokeBorder(КраскаКомпьютераМоего.надписьТёмная.opacity(0.45),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .overlay { надпись("M.2", u, кегль: 1.8, светлая: false) }
                        .элементСхемыКомпьютераМоего(CGRect(x: г.minX + 2 * u, y: г.minY + 1.5 * u, width: 20 * u,
                                                            height: 4 * u), от: г.origin)
                }
                ForEach(Array(р.m2.enumerated()), id: \.offset) { i, рамка in
                    слотM2(д.m2[i], u)
                        .элементСхемыКомпьютераМоего(рамка, от: г.origin)
                }
            }
        }
    }

    private func частьОтсекаНоутбука(_ д: ДанныеСхемыКомпьютераМоего, _ р: РазметкаНоутбукаМоего,
                                     _ u: CGFloat) -> some View {
        let есть = д.отсеков > 0 || !д.диски.isEmpty
        return кнопка(.накопители, р.отсек, номер: 5) {
            ZStack {
                if let диск = д.диски.first {
                    RoundedRectangle(cornerRadius: 0.6 * u)
                        .fill(КраскаКомпьютераМоего.ssd)
                    надпись(диск, u, кегль: 1.5)
                        .padding(.horizontal, 0.6 * u)
                } else {
                    RoundedRectangle(cornerRadius: 0.6 * u)
                        .strokeBorder(КраскаКомпьютераМоего.надписьТёмная.opacity(есть ? 0.6 : 0.3),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    надпись("2.5″", u, кегль: 1.7, светлая: false)
                        .opacity(есть ? 1 : 0.6)
                }
            }
        }
    }
}

// MARK: - Вентилятор

/// Лопасти вентилятора: семь эллипсов вокруг ступицы.
struct ЛопастиКомпьютераМоего: Shape {
    func path(in rect: CGRect) -> Path {
        let ц = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var путь = Path()
        for номер in 0..<7 {
            let угол = CGFloat(номер) / 7 * 2 * CGFloat.pi
            let лопасть = Path(ellipseIn: CGRect(x: -r * 0.18, y: -r * 0.92, width: r * 0.36, height: r * 0.62))
            let поворот = CGAffineTransform(rotationAngle: угол).concatenating(CGAffineTransform(translationX: ц.x, y: ц.y))
            путь.addPath(лопасть.applying(поворот))
        }
        путь.addEllipse(in: CGRect(x: ц.x - r * 0.26, y: ц.y - r * 0.26, width: r * 0.52, height: r * 0.52))
        return путь
    }
}

/// Вентилятор рисунка: медленно крутится (не при «Уменьшении движения» и не в лёгком режиме).
private struct ВентиляторКомпьютераМоего: View {
    let крутится: Bool
    @State private var угол: Double = 0

    init(крутится: Bool) {
        self.крутится = крутится
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(КраскаКомпьютераМоего.паз)
            ЛопастиКомпьютераМоего()
                .fill(КраскаКомпьютераМоего.вентилятор)
                .rotationEffect(.degrees(угол))
                .padding(1)
        }
        .onAppear {
            guard крутится, угол == 0 else { return }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { угол = 360 }
        }
    }
}
