import SwiftUI
import UIKit

/**
 3D-ОБЗОР В ПОДАЧЕ — ЧАСТИ ЭКРАНОВ: подсказка ракурса со схемой обхода, полоска пяти ракурсов, поворот пальцем
 (360°-обзор — так его увидит покупатель) и кольцо сборки.

 Схема и поворот рисуются слева направо при любом языке (геометрия обхода, а не текст): «влево» на схеме совпадает со
 словами подсказки. «Уменьшение движения» — ничего не пульсирует и не кружит; лёгкий режим — кольцо стоит, поворот сам не
 листается.
 */

// MARK: - Подсказка ракурса

/// Над камерой: схема обхода сверху и «Обойдите вещь — шаг 2 из 5: под углом 45° спереди-слева».
struct ПодсказкаРакурсаОбзора3D: View {
    let вид: ВидОбзора3DПодачи
    let ракурс: РакурсОбзора3DПодачи
    let снятые: Set<Int>
    let тихо: Bool

    init(вид: ВидОбзора3DПодачи, ракурс: РакурсОбзора3DПодачи, снятые: Set<Int>, тихо: Bool) {
        self.вид = вид
        self.ракурс = ракурс
        self.снятые = снятые
        self.тихо = тихо
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    private var указание: String {
        String(format: т(вид == .машина ? "m3_go_car" : "m3_go_item"), ракурс.номер, РакурсОбзора3DПодачи.всего,
               т("m3_how_" + ракурс.ключ))
    }

    var body: some View {
        HStack(spacing: 12) {
            СхемаРакурсаОбзора3D(вид: вид, ракурс: ракурс, снятые: снятые, тихо: тихо)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 3) {
                Text(т(ракурс.ключТекста))
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(указание)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т(ракурс.ключТекста))
        .accessibilityValue(указание)
    }
}

/**
 Схема обхода сверху: вещь (или машина) в центре, передом вниз; пунктирный круг обхода и пять мест камеры — спереди
 (снизу), 45° спереди-слева, слева, 45° сзади-слева, сзади (сверху). Снятые — зелёные с галочкой, текущее — белое с
 камерой и пульсом, стрелка ведёт к нему от прошлого места.
 */
struct СхемаРакурсаОбзора3D: View {
    let вид: ВидОбзора3DПодачи
    let ракурс: РакурсОбзора3DПодачи
    let снятые: Set<Int>
    let тихо: Bool

    init(вид: ВидОбзора3DПодачи, ракурс: РакурсОбзора3DПодачи, снятые: Set<Int>, тихо: Bool) {
        self.вид = вид
        self.ракурс = ракурс
        self.снятые = снятые
        self.тихо = тихо
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: тихо)) { шкала in
            let t = тихо ? 0 : шкала.date.timeIntervalSinceReferenceDate
            Canvas { холст, размер in
                нарисовать(&холст, размер: размер, t: t)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// Точка места камеры: угол обхода a (0 — спереди, снизу; 90 — слева; 180 — сзади, сверху).
    private static func точка(_ a: Double, центр: CGPoint, радиус: CGFloat) -> CGPoint {
        let р = a * .pi / 180
        return CGPoint(x: центр.x - радиус * CGFloat(sin(р)), y: центр.y + радиус * CGFloat(cos(р)))
    }

    private func нарисовать(_ холст: inout GraphicsContext, размер: CGSize, t: Double) {
        let сторона = min(размер.width, размер.height)
        let центр = CGPoint(x: размер.width / 2, y: размер.height / 2)
        let радиус = сторона * 0.38
        let белый = Color.white
        let зелёный = Theme.зелёныйЯркий
        /* Круг обхода. */
        let круг = Path(ellipseIn: CGRect(x: центр.x - радиус, y: центр.y - радиус, width: радиус * 2, height: радиус * 2))
        холст.stroke(круг, with: .color(белый.opacity(0.28)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        /* Вещь в центре: машина — вытянутая, передом вниз; вещь — квадрат. Перед — светлая черта. */
        let ширинаТела = сторона * (вид == .машина ? 0.18 : 0.24)
        let высотаТела = сторона * (вид == .машина ? 0.34 : 0.24)
        let тело = CGRect(x: центр.x - ширинаТела / 2, y: центр.y - высотаТела / 2, width: ширинаТела, height: высотаТела)
        let скругление = вид == .машина ? сторона * 0.06 : сторона * 0.04
        холст.fill(Path(roundedRect: тело, cornerRadius: скругление), with: .color(белый.opacity(0.22)))
        холст.stroke(Path(roundedRect: тело, cornerRadius: скругление), with: .color(белый.opacity(0.6)), lineWidth: 1.2)
        var перед = Path()
        перед.move(to: CGPoint(x: тело.minX + тело.width * 0.25, y: тело.maxY - сторона * 0.03))
        перед.addLine(to: CGPoint(x: тело.maxX - тело.width * 0.25, y: тело.maxY - сторона * 0.03))
        холст.stroke(перед, with: .color(зелёный), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        /* Стрелка от прошлого места к текущему — по кругу. */
        if ракурс.rawValue > 0 {
            let начало = (ракурс.угол - 45) + 90
            let конец = ракурс.угол + 90 - 9
            var дуга = Path()
            дуга.addArc(center: центр, radius: радиус, startAngle: .degrees(начало + 9), endAngle: .degrees(конец),
                        clockwise: false)
            холст.stroke(дуга, with: .color(зелёный), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            let уголКонца = конец * .pi / 180
            let кончик = CGPoint(x: центр.x + радиус * CGFloat(cos(уголКонца)),
                                 y: центр.y + радиус * CGFloat(sin(уголКонца)))
            let вдоль = CGVector(dx: -CGFloat(sin(уголКонца)), dy: CGFloat(cos(уголКонца)))
            let поперёк = CGVector(dx: -вдоль.dy, dy: вдоль.dx)
            let д = сторона * 0.06
            var наконечник = Path()
            наконечник.move(to: CGPoint(x: кончик.x + вдоль.dx * д, y: кончик.y + вдоль.dy * д))
            наконечник.addLine(to: CGPoint(x: кончик.x - вдоль.dx * д * 0.2 + поперёк.dx * д * 0.7,
                                           y: кончик.y - вдоль.dy * д * 0.2 + поперёк.dy * д * 0.7))
            наконечник.addLine(to: CGPoint(x: кончик.x - вдоль.dx * д * 0.2 - поперёк.dx * д * 0.7,
                                           y: кончик.y - вдоль.dy * д * 0.2 - поперёк.dy * д * 0.7))
            наконечник.closeSubpath()
            холст.fill(наконечник, with: .color(зелёный))
        }
        /* Места камеры. */
        let малый = сторона * 0.065
        for р in РакурсОбзора3DПодачи.allCases {
            let т = Self.точка(р.угол, центр: центр, радиус: радиус)
            if р == ракурс {
                let пульс = тихо ? 0 : CGFloat((sin(t * 3.2) + 1) / 2)
                let волна = малый * (1.9 + 0.7 * пульс)
                холст.fill(Path(ellipseIn: CGRect(x: т.x - волна, y: т.y - волна, width: волна * 2, height: волна * 2)),
                           with: .color(зелёный.opacity(0.18 + 0.12 * Double(1 - пульс))))
                let r = малый * 1.6
                холст.fill(Path(ellipseIn: CGRect(x: т.x - r, y: т.y - r, width: r * 2, height: r * 2)),
                           with: .color(белый))
                var значок = холст.resolve(Image(systemName: "camera.fill"))
                значок.shading = .color(Color.black)
                холст.draw(значок, in: CGRect(x: т.x - r * 0.62, y: т.y - r * 0.5, width: r * 1.24, height: r))
            } else if снятые.contains(р.rawValue) {
                let r = малый * 1.15
                холст.fill(Path(ellipseIn: CGRect(x: т.x - r, y: т.y - r, width: r * 2, height: r * 2)),
                           with: .color(зелёный))
                var галочка = Path()
                галочка.move(to: CGPoint(x: т.x - r * 0.45, y: т.y + r * 0.02))
                галочка.addLine(to: CGPoint(x: т.x - r * 0.1, y: т.y + r * 0.38))
                галочка.addLine(to: CGPoint(x: т.x + r * 0.5, y: т.y - r * 0.35))
                холст.stroke(галочка, with: .color(Color.black), style: StrokeStyle(lineWidth: 1.6, lineCap: .round,
                                                                                    lineJoin: .round))
            } else {
                let r = малый
                холст.stroke(Path(ellipseIn: CGRect(x: т.x - r, y: т.y - r, width: r * 2, height: r * 2)),
                             with: .color(белый.opacity(0.55)), lineWidth: 1.4)
            }
        }
    }
}

// MARK: - Картинка ракурса

/// Ракурс: миниатюра из файла на телефоне, иначе — адрес на сервере (файл стёрла система), иначе — заглушка.
struct КартинкаРакурсаОбзора3D: View {
    let картинка: UIImage?
    let адрес: URL?

    init(картинка: UIImage?, адрес: URL?) {
        self.картинка = картинка
        self.адрес = адрес
    }

    var body: some View {
        if let картинка {
            Image(uiImage: картинка)
                .resizable()
                .scaledToFit()
        } else if let адрес {
            AsyncImage(url: адрес) { фаза in
                if let изображение = фаза.image {
                    изображение.resizable().scaledToFit()
                } else {
                    Color.white.opacity(0.05)
                }
            }
        } else {
            Image(systemName: "photo")
                .font(.title3)
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }

    /// Адрес ракурса записи на сервере (только https на kliko.kz).
    static func адресРакурса(_ запись: ЗаписьОбзора3DПодачи?, _ номер: Int) -> URL? {
        guard let запись, запись.ракурсы.indices.contains(номер) else { return nil }
        return ХодПримерочной.адрес(запись.ракурсы[номер].адрес)
    }
}

// MARK: - Полоска ракурсов

/// Пять клеток по порядку обхода: снятые — миниатюра с галочкой, текущий — в зелёной рамке, отвергнутый сервером —
/// с красным знаком. нажать — съёмка этого ракурса (пересъёмка снятого или недостающий); nil — клетки не нажимаются.
struct ПолоскаРакурсовОбзора3D: View {
    let кадры: [Int: UIImage]
    let запись: ЗаписьОбзора3DПодачи?
    let текущий: Int?
    let плохой: Int?
    let малая: Bool
    let нажать: ((РакурсОбзора3DПодачи) -> Void)?

    init(кадры: [Int: UIImage], запись: ЗаписьОбзора3DПодачи?, текущий: Int?, плохой: Int?, малая: Bool,
         нажать: ((РакурсОбзора3DПодачи) -> Void)?) {
        self.кадры = кадры
        self.запись = запись
        self.текущий = текущий
        self.плохой = плохой
        self.малая = малая
        self.нажать = нажать
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    var body: some View {
        HStack(spacing: малая ? 8 : 10) {
            ForEach(РакурсОбзора3DПодачи.allCases) { р in
                клетка(р)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func клетка(_ р: РакурсОбзора3DПодачи) -> some View {
        let есть = запись?.ракурс(р).есть == true
        if let нажать {
            Button {
                ОткликСайта.выбор()
                нажать(р)
            } label: {
                содержимое(р, есть: есть)
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
            .accessibilityLabel(подпись(р, есть: есть))
            .accessibilityHint(есть ? т("m3_tap_retake") : т("m3_shoot"))
        } else {
            содержимое(р, есть: есть)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(подпись(р, есть: есть))
        }
    }

    private func подпись(_ р: РакурсОбзора3DПодачи, есть: Bool) -> String {
        String(format: т("m3_cell_a11y"), р.номер, т(р.ключТекста)) + " — " + т(есть ? "m3_cell_done" : "m3_cell_todo")
    }

    private func содержимое(_ р: РакурсОбзора3DПодачи, есть: Bool) -> some View {
        let размер: CGFloat = малая ? 46 : 58
        let текущая = текущий == р.rawValue
        let отвергнут = плохой == р.rawValue
        let форма = RoundedRectangle(cornerRadius: малая ? 10 : 12, style: .continuous)
        return ZStack {
            форма.fill(Color.white.opacity(есть ? 0.1 : 0.05))
            if есть {
                КартинкаРакурсаОбзора3D(картинка: кадры[р.rawValue],
                                        адрес: КартинкаРакурсаОбзора3D.адресРакурса(запись, р.rawValue))
                    .padding(3)
            } else {
                Text(String(р.номер))
                    .font(.system(size: малая ? 15 : 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(текущая ? 0.95 : 0.45))
            }
        }
        .frame(width: размер, height: размер)
        .clipShape(форма)
        .overlay {
            форма.strokeBorder(отвергнут ? Theme.малиновый : (текущая ? Theme.зелёныйЯркий : Color.white.opacity(0.16)),
                               lineWidth: текущая || отвергнут ? 2.5 : 1)
        }
        .overlay(alignment: .topTrailing) {
            if отвергнут {
                знак("exclamationmark", фон: Theme.малиновый)
            } else if есть {
                знак("checkmark", фон: Theme.зелёныйЯркий)
            }
        }
    }

    private func знак(_ значок: String, фон: Color) -> some View {
        Image(systemName: значок)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.black)
            .frame(width: 18, height: 18)
            .background(фон, in: Circle())
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 1.5) }
            .offset(x: 5, y: -5)
            .accessibilityHidden(true)
    }
}

// MARK: - Поворот пальцем (360°-обзор)

/**
 Ракурсы по кругу: ведёте пальцем — вещь «поворачивается» (смена ракурса каждые 36 pt), с лёгким щелчком на каждом шаге.
 Пока не трогали — сама медленно поворачивается туда и обратно (не при «Уменьшении движения» и не в лёгком режиме).
 VoiceOver — смахивание вверх и вниз меняет ракурс.
 */
struct ПоворотРакурсовОбзора3D: View {
    let кадры: [Int: UIImage]
    let запись: ЗаписьОбзора3DПодачи?
    let тихо: Bool
    let лёгкий: Bool
    @State private var номер = 0
    @State private var началоЖеста: Int? = nil
    @State private var трогали = false
    @State private var вперёд = true

    init(кадры: [Int: UIImage], запись: ЗаписьОбзора3DПодачи?, тихо: Bool, лёгкий: Bool) {
        self.кадры = кадры
        self.запись = запись
        self.тихо = тихо
        self.лёгкий = лёгкий
    }

    private func т(_ ключ: String) -> String { Обзор3DПодачиText.т(ключ) }

    /// Номера снятых ракурсов по порядку обхода.
    private var снятые: [Int] {
        guard let запись else { return [] }
        return РакурсОбзора3DПодачи.allCases.filter { запись.ракурс($0).есть }.map { $0.rawValue }
    }

    private var текущий: Int {
        let список = снятые
        return список.contains(номер) ? номер : (список.first ?? 0)
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                КартинкаРакурсаОбзора3D(картинка: кадры[текущий],
                                        адрес: КартинкаРакурсаОбзора3D.адресРакурса(запись, текущий))
                    .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 12)
                    .id(текущий)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background {
                RadialGradient(colors: [Theme.зелёныйЯркий.opacity(0.22), Color.clear], center: .center,
                               startRadius: 4, endRadius: 220)
            }
            .contentShape(Rectangle())
            .gesture(жест)
            точки
        }
        .environment(\.layoutDirection, .leftToRight)
        .task(id: трогали) { await листатьСам() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("m3_rotate_a11y"))
        .accessibilityValue(РакурсОбзора3DПодачи(rawValue: текущий).map { т($0.ключТекста) } ?? "")
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: сдвинуть(на: 1)
            case .decrement: сдвинуть(на: -1)
            @unknown default: break
            }
        }
    }

    /// Точки ракурсов и «ведите пальцем».
    private var точки: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.шапкаМята)
            ForEach(снятые, id: \.self) { н in
                Capsule()
                    .fill(н == текущий ? Theme.зелёныйЯркий : Color.white.opacity(0.3))
                    .frame(width: н == текущий ? 18 : 6, height: 6)
            }
            Text(т("m3_rotate_hint"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .animation(ДвижениеСайта.выбор, value: текущий)
        .accessibilityHidden(true)
    }

    private var жест: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { жест in
                let список = снятые
                guard список.count > 1 else { return }
                if началоЖеста == nil {
                    началоЖеста = список.firstIndex(of: текущий) ?? 0
                    трогали = true
                }
                /* Палец вправо — следующий ракурс, как у покупателя (360° и 3D на странице объявления). */
                let шаг = Int((жест.translation.width / 36).rounded())
                let место = min(max(0, (началоЖеста ?? 0) + шаг), список.count - 1)
                if список[место] != номер {
                    номер = список[место]
                    ОткликСайта.выбор()
                }
            }
            .onEnded { _ in началоЖеста = nil }
    }

    private func сдвинуть(на сдвиг: Int) {
        let список = снятые
        guard !список.isEmpty else { return }
        трогали = true
        let место = min(max(0, (список.firstIndex(of: текущий) ?? 0) + сдвиг), список.count - 1)
        номер = список[место]
    }

    /// Сам поворачивается туда и обратно, пока не трогали.
    private func листатьСам() async {
        guard !тихо, !лёгкий, !трогали else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, !трогали else { return }
            let список = снятые
            guard список.count > 1 else { continue }
            var место = список.firstIndex(of: текущий) ?? 0
            if вперёд && место >= список.count - 1 { вперёд = false }
            if !вперёд && место <= 0 { вперёд = true }
            место += вперёд ? 1 : -1
            withAnimation(.easeInOut(duration: 0.35)) { номер = список[место] }
        }
    }
}

// MARK: - Кольцо сборки

/**
 «Собираем 3D»: ракурсы из ряда сходятся в кольцо и кружат вокруг светящегося куба — как будто ИИ обходит вещь. Ближние
 крупнее и ярче, дальние — меньше и тусклее. «Уменьшение движения» и лёгкий режим — кольцо стоит.
 */
struct КольцоСборкиОбзора3D: View {
    let кадры: [Int: UIImage]
    let запись: ЗаписьОбзора3DПодачи?
    let тихо: Bool
    @State private var начало = Date()

    init(кадры: [Int: UIImage], запись: ЗаписьОбзора3DПодачи?, тихо: Bool) {
        self.кадры = кадры
        self.запись = запись
        self.тихо = тихо
    }

    var body: some View {
        /* 30 кадров в секунду, а не частота дисплея (120 Гц на ProMotion): кольцо кружит всю сборку, до 10 минут. Кольцо
           рисуется одним проходом Metal (drawingGroup) — тени пяти карточек не считаются каждая вне экрана. */
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: тихо)) { шкала in
            let t = тихо ? 12 : шкала.date.timeIntervalSince(начало)
            GeometryReader { место in
                кадр(t: t, размер: место.size)
                    .drawingGroup()
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear { начало = Date() }
        .accessibilityHidden(true)
    }

    /// Кубическое замедление: быстро в начале, мягко у цели.
    private static func плавно(_ x: Double) -> Double {
        let ч = min(1, max(0, x))
        return 1 - pow(1 - ч, 3)
    }

    private func кадр(t: Double, размер: CGSize) -> some View {
        let ширина = min(размер.width, 420)
        let радиус = Double(ширина) * 0.36
        let c = Self.плавно((t - 0.1) / 1.3)
        let пульс = sin(t * 2.1)
        let сторонаКарточки = ширина * 0.27
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Theme.зелёныйЯркий.opacity(0.45), Color.clear], center: .center,
                                     startRadius: 4, endRadius: ширина * 0.45))
                .frame(width: ширина, height: ширина)
                .scaleEffect(1 + 0.04 * пульс)
                .opacity(0.35 + 0.5 * c)
            Ellipse()
                .stroke(Theme.шапкаМята.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
                .frame(width: CGFloat(радиус * 2), height: CGFloat(радиус * 0.42))
                .offset(y: сторонаКарточки * 0.42)
                .opacity(c)
            ForEach(РакурсОбзора3DПодачи.allCases) { р in
                let фаза = t * 0.55 + Double(р.rawValue) * 2 * .pi / 5
                let глубина = cos(фаза)
                let хКольца = sin(фаза) * радиус
                let уКольца = глубина * радиус * 0.2
                let хРяда = (Double(р.rawValue) - 2) * Double(ширина) * 0.19
                let масштаб = (1 - c) * 0.72 + c * (0.55 + 0.45 * (глубина + 1) / 2)
                карточка(р, сторона: сторонаКарточки)
                    .scaleEffect(CGFloat(масштаб))
                    .opacity(0.45 + 0.55 * ((1 - c) + c * (глубина + 1) / 2))
                    .offset(x: CGFloat(хРяда * (1 - c) + хКольца * c), y: CGFloat(уКольца * c))
                    .zIndex(глубина)
            }
            Image(systemName: "cube.transparent")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(Theme.шапкаМята)
                .shadow(color: Theme.зелёныйЯркий, radius: 12)
                .scaleEffect(CGFloat(0.9 + 0.12 * пульс))
                .opacity(c)
                .zIndex(-0.2)
        }
        .frame(width: размер.width, height: размер.height)
    }

    private func карточка(_ р: РакурсОбзора3DПодачи, сторона: CGFloat) -> some View {
        КартинкаРакурсаОбзора3D(картинка: кадры[р.rawValue],
                                адрес: КартинкаРакурсаОбзора3D.адресРакурса(запись, р.rawValue))
            .padding(4)
            .frame(width: сторона, height: сторона)
            .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 6)
    }
}
