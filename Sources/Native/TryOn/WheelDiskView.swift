import SwiftUI

/**
 ЖИВОЙ ДИСК «ПРЯМ ПО ДИСКУ» (владелец 16.10.2026, скрин «Параметры колёс»: «стандартизация должна быть необычной, а прям
 по диску»).

 Колесо спереди, как его видно на машине: шина, на боковине которой по дуге написан размер («205/55 R16»), обод с
 закраиной, спицы, болты по кругу разболтовки — ровно столько, сколько в PCD, сам круг разболтовки и центральное
 отверстие DIA; рядом — разрез колеса со схемой вылета ET: середина обода ↔ привалочная плоскость. Части — кнопки: шина —
 размер шины, обод — R и J, болты — PCD, центр — DIA, схема — ET (выбор под диском — ПанельКолеса, WheelPanel.swift).
 Выбранная часть обведена акцентом; смена значения — мягко: кольца меняют размер, болты и спицы переезжают по кругу.
 «Уменьшение движения» (ДвижениеСайта.тихо) — сразу, без полёта; лёгкий режим (РежимУстройства) — короче и без свечения.

 Пропорции — по настоящим миллиметрам: посадка R × 25,4 мм и две боковины шины; круг болтов и отверстие чуть крупнее,
 чтобы их было видно. Неизвестное рисуется обычным (R16, 5×114.3, DIA 64.1) и бледнее. Надписи по дуге — только цифры и
 латиница (по буквам: арабская вязь так не собирается), рисунок всегда слева направо.
 */

// MARK: - Части: имена и значения

extension ЧастьКолеса {
    /// «Шина», «Разболтовка PCD» — заголовок панели и имя для VoiceOver.
    var название: String {
        switch self {
        case .шина: return КолёсаText.т("wh_part_tire")
        case .обод: return КолёсаText.т("wh_part_rim")
        case .болты: return КолёсаText.т("wh_part_pcd")
        case .центр: return КолёсаText.т("wh_part_dia")
        case .вылет: return КолёсаText.т("wh_part_et")
        }
    }

    /// Коротко для ленты частей: «Шина», «Обод», «PCD», «DIA», «ET».
    var коротко: String {
        switch self {
        case .шина: return КолёсаText.т("wh_tab_tire")
        case .обод: return КолёсаText.т("wh_tab_rim")
        case .болты: return "PCD"
        case .центр: return "DIA"
        case .вылет: return "ET"
        }
    }

    var значок: String {
        switch self {
        case .шина: return "circle.circle"
        case .обод: return "smallcircle.filled.circle"
        case .болты: return "circle.grid.cross"
        case .центр: return "largecircle.fill.circle"
        case .вылет: return "arrow.left.and.right"
        }
    }

    /// Значение части для глаз: «205/55 R16», «R16 · 7J», «5×114.3», «67.1 мм», «ET45»; не выбрано — nil.
    func значение(_ з: ЗначенияКолеса, черновик: ЧерновикШины) -> String? {
        switch self {
        case .шина:
            if let размер = з.шина { return размер.подпись }
            let трио = з.трио(черновик)
            return трио.ширина == nil && трио.профиль == nil ? nil : трио.подпись
        case .обод:
            return СтандартыКолёс.подписьОбода(r: з.r ?? черновик.r, j: з.ширинаJ)
        case .болты:
            return з.pcd?.подпись
        case .центр:
            return з.dia.map { String(format: АвтоподборText.т("af_mm"), ЧислаАвтоподбора.ч($0, знаков: 2)) }
        case .вылет:
            return з.et.map { СтандартыКолёс.подписьВылета($0) }
        }
    }
}

// MARK: - Краска

/// Цвета рисунка: шина тёмная в обеих темах, металл в тёмной — глуше, чтобы не слепил.
enum КраскаКолеса {
    static let шина = Theme.цвет(0x2B302D, 0x0D100E)
    static let боковина = Theme.цвет(0x3A413D, 0x262D29)
    static let надпись = Color.white.opacity(0.88)
    static let металл = Theme.цвет(0xDDE4E0, 0x7A8580)
    static let металлТень = Theme.цвет(0xA6B1AB, 0x4B5550)
    static let просвет = Theme.цвет(0x39403C, 0x121614)
    static let ступица = Theme.цвет(0xC7D0CB, 0x5F6A64)
    static let болт = Theme.цвет(0x59635E, 0xB3BEB8)
    static let отверстие = Theme.цвет(0x1C2220, 0x060807)
}

// MARK: - Геометрия

/// Размеры рисунка — доли внешнего радиуса шины (1 — край протектора).
struct ГеометрияКолеса: Equatable {
    /// Край обода — где кончается боковина.
    var обод: CGFloat
    /// Внутренний край закраины обода.
    var полка: CGFloat
    /// Шайба ступицы — на ней болты.
    var ступица: CGFloat
    var разболтовка: CGFloat
    var болт: CGFloat
    var отверстие: CGFloat
    /// Зона касания центра (не меньше пальца).
    var центр: CGFloat
    var болтов: Int
    var спиц: Int

    init(_ з: ЗначенияКолеса, черновик: ЧерновикШины) {
        let трио = з.трио(черновик)
        let r = з.r ?? трио.r ?? 16
        let запас = трио.ширина == nil || трио.профиль == nil ? СтандартыКолёс.популярныеШины(r: r).first : nil
        let ширина = трио.ширина ?? запас?.ширина ?? 205
        let профиль = трио.профиль ?? запас?.профиль ?? 55
        let ободМм = max(r * 25.4, 1)
        let внешний = ободМм + 2 * ширина * профиль / 100
        обод = CGFloat(min(0.80, max(0.56, ободМм / внешний)))
        полка = обод * 0.9
        let pcd = з.pcd?.pcd ?? 114.3
        разболтовка = обод * CGFloat(min(0.46, max(0.26, pcd / ободМм * 1.25)))
        болт = обод * 0.05
        let dia = з.dia ?? 64.1
        отверстие = min(разболтовка * 0.6, обод * CGFloat(min(0.30, max(0.10, dia / ободМм * 1.25))))
        ступица = min(разболтовка + обод * 0.11, полка * 0.66)
        центр = min(max(отверстие * 1.3, 0.13), разболтовка - болт * 1.6)
        болтов = min(10, max(3, з.pcd?.отверстий ?? 5))
        спиц = болтов >= 5 ? болтов : болтов * 2
    }
}

// MARK: - Формы

private func кругВокруг(_ центр: CGPoint, _ радиус: CGFloat) -> CGRect {
    CGRect(x: центр.x - радиус, y: центр.y - радиус, width: 2 * радиус, height: 2 * радиус)
}

/// Кольцо между двумя долями радиуса (0…1 от половины меньшей стороны); внутр 0 — круг. Заливать с eoFill.
struct КольцоКолеса: Shape {
    var внутр: CGFloat
    var внешн: CGFloat

    init(внутр: CGFloat, внешн: CGFloat) {
        self.внутр = внутр
        self.внешн = внешн
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(внутр, внешн) }
        set {
            внутр = newValue.first
            внешн = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ц = CGPoint(x: rect.midX, y: rect.midY)
        let радиус = min(rect.width, rect.height) / 2
        var путь = Path()
        путь.addEllipse(in: кругВокруг(ц, радиус * max(0, внешн)))
        if внутр > 0 { путь.addEllipse(in: кругВокруг(ц, радиус * внутр)) }
        return путь
    }
}

/// Спица вверх от ступицы к ободу: трапеция, у ступицы шире. Поворачивается снаружи (rotationEffect).
struct СпицаКолеса: Shape {
    var от: CGFloat
    var до: CGFloat
    var ширина: CGFloat

    init(от: CGFloat, до: CGFloat, ширина: CGFloat) {
        self.от = от
        self.до = до
        self.ширина = ширина
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(от, до), ширина) }
        set {
            от = newValue.first.first
            до = newValue.first.second
            ширина = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ц = CGPoint(x: rect.midX, y: rect.midY)
        let радиус = min(rect.width, rect.height) / 2
        let низ = ц.y - радиус * от
        let верх = ц.y - радиус * до
        let уОси = радиус * ширина / 2
        let уОбода = уОси * 0.62
        var путь = Path()
        путь.move(to: CGPoint(x: ц.x - уОси, y: низ))
        путь.addLine(to: CGPoint(x: ц.x - уОбода, y: верх))
        путь.addLine(to: CGPoint(x: ц.x + уОбода, y: верх))
        путь.addLine(to: CGPoint(x: ц.x + уОси, y: низ))
        путь.closeSubpath()
        return путь
    }
}

/// Шашки протектора по краю шины — короткие черты по кругу.
struct ПротекторКолеса: Shape {
    var шашек = 48

    func path(in rect: CGRect) -> Path {
        let ц = CGPoint(x: rect.midX, y: rect.midY)
        let радиус = min(rect.width, rect.height) / 2
        var путь = Path()
        for номер in 0..<шашек {
            let угол = Double(номер) / Double(шашек) * 2 * Double.pi
            let x = CGFloat(cos(угол))
            let y = CGFloat(sin(угол))
            путь.move(to: CGPoint(x: ц.x + x * радиус * 0.93, y: ц.y + y * радиус * 0.93))
            путь.addLine(to: CGPoint(x: ц.x + x * радиус * 0.995, y: ц.y + y * радиус * 0.995))
        }
        return путь
    }
}

/// Надпись по дуге: сверху — по часовой, снизу — «улыбкой», буквы стоят прямо. Только цифры и латиница.
struct ТекстПоДуге: View {
    let текст: String
    let радиус: CGFloat
    let кегль: CGFloat
    let сверху: Bool

    init(текст: String, радиус: CGFloat, кегль: CGFloat, сверху: Bool) {
        self.текст = текст
        self.радиус = радиус
        self.кегль = кегль
        self.сверху = сверху
    }

    var body: some View {
        let буквы = Array(текст)
        let шаг = Double(кегль * 0.66 / max(радиус, 1)) * 180 / Double.pi
        let середина = Double(буквы.count - 1) / 2
        return ZStack {
            ForEach(Array(буквы.enumerated()), id: \.offset) { номер, буква in
                Text(String(буква))
                    .font(.system(size: кегль, weight: .heavy, design: .monospaced))
                    .foregroundStyle(КраскаКолеса.надпись)
                    .offset(y: сверху ? -радиус : радиус)
                    .rotationEffect(.degrees((сверху ? Double(номер) - середина : середина - Double(номер)) * шаг))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Разметка: диск и схема рядом

/// Диск квадратом 170…260 pt по ширине места и схема вылета 64 pt справа; без схемы — диск по центру.
struct РазметкаЖивогоДиска: Layout {
    var схема: CGFloat = 64
    var зазор: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? 340
        let сторона = self.сторона(ширина, subviews.count)
        let нужно = сторона + (subviews.count > 1 ? схема + зазор : 0)
        return CGSize(width: ширина.isFinite ? max(ширина, нужно) : нужно, height: сторона)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let диск = subviews.first else { return }
        let сторона = self.сторона(bounds.width, subviews.count)
        let естьСхема = subviews.count > 1
        let нужно = сторона + (естьСхема ? схема + зазор : 0)
        let x = bounds.midX - нужно / 2
        диск.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                   proposal: ProposedViewSize(width: сторона, height: сторона))
        if естьСхема {
            subviews[1].place(at: CGPoint(x: x + сторона + зазор, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: схема, height: сторона))
        }
    }

    private func сторона(_ ширина: CGFloat, _ сколько: Int) -> CGFloat {
        let место = (ширина.isFinite ? ширина : 340) - (сколько > 1 ? схема + зазор : 0)
        return max(170, min(260, место))
    }
}

// MARK: - Живой диск

/// Колесо спереди и схема вылета. Части — кнопки: касание выбирает часть, выбор — в панели под диском.
struct ЖивойДискКолеса: View {
    let значения: ЗначенияКолеса
    let черновик: ЧерновикШины
    let состав: СоставКолеса
    let выбрана: ЧастьКолеса
    let вспышка: Set<ЧастьКолеса>
    let выбрать: (ЧастьКолеса) -> Void
    @ObservedObject private var режим = РежимУстройства.shared

    init(значения: ЗначенияКолеса, черновик: ЧерновикШины, состав: СоставКолеса, выбрана: ЧастьКолеса,
         вспышка: Set<ЧастьКолеса>, выбрать: @escaping (ЧастьКолеса) -> Void) {
        self.значения = значения
        self.черновик = черновик
        self.состав = состав
        self.выбрана = выбрана
        self.вспышка = вспышка
        self.выбрать = выбрать
    }

    private func т(_ ключ: String) -> String { КолёсаText.т(ключ) }

    /// Смена размеров: пружина, в лёгком режиме — коротко, при «Уменьшении движения» — сразу.
    private var анимация: Animation? {
        ДвижениеСайта.мягко(режим.лёгкий ? .easeOut(duration: 0.18) : .spring(response: 0.5, dampingFraction: 0.8))
    }

    var body: some View {
        let г = ГеометрияКолеса(значения, черновик: черновик)
        return РазметкаЖивогоДиска() {
            колесо(г)
            if состав.et {
                СхемаВылетаКолеса(et: значения.et, ширинаJ: значения.ширинаJ, выбрана: выбрана == .вылет,
                                  вспышка: вспышка.contains(.вылет), лёгкий: режим.лёгкий) {
                    выбрать(.вылет)
                }
                .accessibilitySortPriority(1)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(анимация, value: г)
        .animation(анимация, value: значения.et)
        .animation(ДвижениеСайта.выбор, value: выбрана)
        .animation(ДвижениеСайта.мягко(.easeInOut(duration: 0.6)), value: вспышка)
    }

    private func колесо(_ г: ГеометрияКолеса) -> some View {
        GeometryReader { место in
            let сторона = min(место.size.width, место.size.height) * 0.96
            ZStack {
                шина(г, сторона / 2)
                обод(г)
                болты(г, сторона / 2)
                центр(г)
                подсветка(г)
            }
            .frame(width: сторона, height: сторона)
            .position(x: место.size.width / 2, y: место.size.height / 2)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Части

    /// Размер шины по боковине: полный, частями с прочерками, ничего — «—/— R—».
    private var надписьШины: String {
        if let размер = значения.шина { return размер.подпись }
        return значения.трио(черновик).подпись
    }

    @ViewBuilder
    private func шина(_ г: ГеометрияКолеса, _ радиус: CGFloat) -> some View {
        let форма = КольцоКолеса(внутр: г.обод, внешн: 1)
        let кегль = min(14, max(9, радиус * (1 - г.обод) * 0.36))
        let рисунок = ZStack {
            форма.fill(КраскаКолеса.шина, style: FillStyle(eoFill: true))
            КольцоКолеса(внутр: г.обод + (1 - г.обод) * 0.12, внешн: г.обод + (1 - г.обод) * 0.86)
                .stroke(КраскаКолеса.боковина, lineWidth: 1)
            ПротекторКолеса()
                .stroke(Color.white.opacity(0.09), lineWidth: 1.5)
            if состав.шина {
                ТекстПоДуге(текст: надписьШины, радиус: радиус * (1 + г.обод) / 2, кегль: кегль, сверху: true)
            }
            if let ободом = СтандартыКолёс.подписьОбода(r: значения.r ?? черновик.r, j: значения.ширинаJ) {
                ТекстПоДуге(текст: ободом, радиус: радиус * (1 + г.обод) / 2, кегль: кегль * 0.9, сверху: false)
                    .opacity(0.8)
            }
        }
        if состав.шина {
            кнопка(.шина, порядок: 5) {
                рисунок.contentShape(форма, eoFill: true)
            }
        } else {
            рисунок
                .opacity(0.4)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func обод(_ г: ГеометрияКолеса) -> some View {
        let форма = КольцоКолеса(внутр: г.ступица, внешн: г.обод)
        let металл = режим.лёгкий ? AnyShapeStyle(КраскаКолеса.металл)
            : AnyShapeStyle(LinearGradient(colors: [КраскаКолеса.металл, КраскаКолеса.металлТень],
                                           startPoint: .top, endPoint: .bottom))
        let ширинаСпицы = min(0.2, 0.9 / CGFloat(max(г.спиц, 1))) * г.обод * 1.6
        let рисунок = ZStack {
            КольцоКолеса(внутр: г.ступица * 0.96, внешн: г.полка)
                .fill(КраскаКолеса.просвет, style: FillStyle(eoFill: true))
            ForEach(0..<10, id: \.self) { номер in
                СпицаКолеса(от: г.ступица * 0.92, до: г.полка * 1.01, ширина: ширинаСпицы)
                    .fill(металл)
                    .rotationEffect(.degrees(360 / Double(г.спиц) * Double(номер)))
                    .opacity(номер < г.спиц ? 1 : 0)
            }
            КольцоКолеса(внутр: г.полка, внешн: г.обод)
                .fill(металл, style: FillStyle(eoFill: true))
            КольцоКолеса(внутр: г.полка, внешн: г.полка)
                .stroke(КраскаКолеса.металлТень, lineWidth: 1)
        }
        if состав.есть(.обод) {
            кнопка(.обод, порядок: 4) {
                рисунок.contentShape(форма, eoFill: true)
            }
        } else {
            рисунок
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func болты(_ г: ГеометрияКолеса, _ радиус: CGFloat) -> some View {
        let форма = КольцоКолеса(внутр: г.центр, внешн: г.ступица)
        let выбраны = выбрана == .болты
        /* PCD не задано — болты и круг бледные: пять болтов «для вида» не выдают себя за выбранную разболтовку. */
        let бледно: Double = значения.pcd == nil ? 0.45 : 1
        let рисунок = ZStack {
            КольцоКолеса(внутр: 0, внешн: г.ступица)
                .fill(КраскаКолеса.ступица)
            КольцоКолеса(внутр: г.разболтовка, внешн: г.разболтовка)
                .stroke(выбраны ? Theme.акцент : КраскаКолеса.металлТень,
                        style: StrokeStyle(lineWidth: выбраны ? 1.5 : 1, dash: [3, 3]))
                .opacity(бледно)
            ForEach(0..<10, id: \.self) { номер in
                Circle()
                    .fill(выбраны ? Theme.акцент : КраскаКолеса.болт)
                    .overlay {
                        Circle()
                            .fill(КраскаКолеса.отверстие.opacity(0.55))
                            .padding(радиус * г.болт * 0.55)
                    }
                    .frame(width: радиус * г.болт * 2, height: радиус * г.болт * 2)
                    .offset(y: -радиус * г.разболтовка)
                    .rotationEffect(.degrees(360 / Double(г.болтов) * Double(номер)))
                    .opacity(номер < г.болтов ? бледно : 0)
                    .scaleEffect(номер < г.болтов ? 1 : 0.4)
            }
        }
        if состав.pcd {
            кнопка(.болты, порядок: 3) {
                рисунок.contentShape(форма, eoFill: true)
            }
        } else {
            рисунок
                .opacity(0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func центр(_ г: ГеометрияКолеса) -> some View {
        let рисунок = ZStack {
            КольцоКолеса(внутр: 0, внешн: г.отверстие)
                .fill(КраскаКолеса.отверстие)
            КольцоКолеса(внутр: г.отверстие, внешн: г.отверстие)
                .stroke(КраскаКолеса.металлТень, lineWidth: 1.5)
        }
        .opacity(значения.dia == nil ? 0.5 : 1)
        if состав.dia {
            кнопка(.центр, порядок: 2) {
                рисунок.contentShape(КольцоКолеса(внутр: 0, внешн: г.центр))
            }
        } else {
            рисунок
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Обводка выбранной части и вспышка считанных сканером. Касаний не ловит.
    private func подсветка(_ г: ГеометрияКолеса) -> some View {
        ZStack {
            ForEach([ЧастьКолеса.шина, .обод, .болты, .центр], id: \.self) { часть in
                let кольцо = кольцоПодсветки(часть, г)
                let видна = часть == выбрана && состав.есть(часть)
                кольцо
                    .fill(Theme.акцент.opacity(0.22), style: FillStyle(eoFill: true))
                    .opacity(вспышка.contains(часть) ? 1 : 0)
                кольцо
                    .stroke(Theme.акцент, lineWidth: 3)
                    .shadow(color: режим.лёгкий ? .clear : Theme.акцент.opacity(0.55), radius: 6)
                    .opacity(видна || вспышка.contains(часть) ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func кольцоПодсветки(_ часть: ЧастьКолеса, _ г: ГеометрияКолеса) -> КольцоКолеса {
        switch часть {
        case .шина: return КольцоКолеса(внутр: г.обод, внешн: 1)
        case .обод: return КольцоКолеса(внутр: г.ступица, внешн: г.обод)
        case .болты: return КольцоКолеса(внутр: г.центр, внешн: г.ступица)
        case .центр, .вылет: return КольцоКолеса(внутр: 0, внешн: г.отверстие)
        }
    }

    /// Часть — кнопка: имя и значение для VoiceOver, «выбрана» — признаком.
    private func кнопка<Метка: View>(_ часть: ЧастьКолеса, порядок: Double,
                                     @ViewBuilder метка: () -> Метка) -> some View {
        Button {
            выбрать(часть)
        } label: {
            метка()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(часть.название)
        .accessibilityValue(часть.значение(значения, черновик: черновик) ?? т("wh_unset"))
        .accessibilityHint(т("wh_a11y_hint"))
        .accessibilityAddTraits(выбрана == часть ? .isSelected : [])
        .accessibilitySortPriority(порядок)
    }
}

// MARK: - Схема вылета

/**
 Разрез колеса сбоку: шина, обод шириной J, пунктир — середина обода, акцентная планка — привалочная плоскость (где
 диск прижимается к ступице). Вылет ET — расстояние между ними: больше — планка наружу (колесо глубже в арке), меньше
 или минус — внутрь. Масштаб вылета чуть крупнее настоящего, чтобы было видно.
 */
struct СхемаВылетаКолеса: View {
    let et: ClosedRange<Double>?
    let ширинаJ: Double?
    let выбрана: Bool
    let вспышка: Bool
    let лёгкий: Bool
    let действие: () -> Void

    init(et: ClosedRange<Double>?, ширинаJ: Double?, выбрана: Bool, вспышка: Bool, лёгкий: Bool,
         действие: @escaping () -> Void) {
        self.et = et
        self.ширинаJ = ширинаJ
        self.выбрана = выбрана
        self.вспышка = вспышка
        self.лёгкий = лёгкий
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { КолёсаText.т(ключ) }

    private var значение: String {
        guard let et else { return "—" }
        return СтандартыКолёс.подписьВылета(et).replacingOccurrences(of: "ET", with: "")
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button(action: действие) {
            VStack(spacing: 4) {
                Text("ET")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Theme.текстВторой)
                Text(значение)
                    .font(.system(size: 15, weight: .bold).monospacedDigit())
                    .foregroundStyle(et == nil ? Theme.текстВторой : Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                GeometryReader { место in
                    разрез(место.size)
                }
                HStack(spacing: 2) {
                    Text(т("wh_out"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(выбрана || вспышка ? Theme.оттенокАкцента : Theme.поверхность2, in: форма)
            .overlay {
                форма.strokeBorder(выбрана ? Theme.акцент : Theme.линия, lineWidth: выбрана ? 2 : 1)
            }
            .shadow(color: выбрана && !лёгкий ? Theme.акцент.opacity(0.35) : .clear, radius: 6)
            .contentShape(форма)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ЧастьКолеса.вылет.название)
        .accessibilityValue(et.map { СтандартыКолёс.подписьВылета($0) } ?? т("wh_unset"))
        .accessibilityHint(т("wh_a11y_hint"))
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    /// Шина и обод в разрезе, середина обода и привалочная плоскость со стрелкой между ними.
    private func разрез(_ размер: CGSize) -> some View {
        let ш = размер.width
        let в = размер.height
        let масштаб = max(ш - 22, 20) / (12 * 25.4)
        let обод = max(16, CGFloat((ширинаJ ?? 7) * 25.4) * масштаб)
        let вылет = et.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 40
        let предел = обод / 2 + 4
        let сдвиг = min(предел, max(-предел, CGFloat(вылет) * масштаб * 1.8))
        let акцент = выбрана || вспышка
        return ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(КраскаКолеса.шина)
                .frame(width: обод + 12, height: в)
            Rectangle()
                .fill(КраскаКолеса.металл)
                .frame(width: обод, height: в * 0.62)
            Path { путь in
                путь.move(to: CGPoint(x: ш / 2, y: в * 0.08))
                путь.addLine(to: CGPoint(x: ш / 2, y: в * 0.92))
            }
            .stroke(Theme.текстВторой, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Capsule()
                .fill(акцент ? Theme.акцент : КраскаКолеса.металлТень)
                .frame(width: 4, height: в * 0.36)
                .offset(x: сдвиг)
            Rectangle()
                .fill(акцент ? Theme.акцент : Theme.текстВторой)
                .frame(width: abs(сдвиг), height: 1.5)
                .offset(x: сдвиг / 2, y: -в * 0.24)
        }
        .frame(width: ш, height: в)
        .opacity(et == nil ? 0.55 : 1)
    }
}
