import SwiftUI
import UIKit

/**
 «МОЁ» — ЖИВОЙ СИЛУЭТ МЕРОК (владелец 16.10.2026: «стандарты ≠ удобства» — мерки на фигуре, а не восемь пустых полей).

 Фигура человека в поле 150 × 248: сама фигура — 100 по ширине в середине, по бокам — место подписей. Женская, мужская
 или средняя (пол не выбран) — одна кривая с долей 0…1, поэтому смена пола перетекает (animatableData). На фигуре восемь
 мерок: обхваты груди, талии, бёдер и головы — кольцами; плечи, рука, нога по шагу и стопа — линиями с засечками.
 Заполненная мерка — сплошная зелёная линия (дорисовывается при появлении) и число рядом перекатом; «примерно» — светлее
 и с «≈»; пустая — пунктир. Выбранная — с мягкой подсветкой. Значение сменилось — линия «вздыхает» (phaseAnimator по
 толчку). Касание зоны выбирает мерку — панель ниже (MyThingsBodyPanel.swift). VoiceOver: каждая зона — кнопка
 «Обхват груди, 96 сантиметров». «Уменьшение движения» и лёгкий режим — без дорисовки, вздоха и перетекания.
 На арабском фигура не отражается (layoutDirection слева направо, как у позы на фото): рука слева — зона руки слева.
 */

// MARK: - Геометрия

enum ГеометрияТелаМоего {
    /// Поле рисунка: 150 × 248; фигура — в своих 0…100 по ширине, сдвинута на 25.
    static let ширина: CGFloat = 150
    static let высота: CGFloat = 248
    static let сдвиг: CGFloat = 25
    static let пропорция: CGFloat = 150.0 / 248.0

    /// Мерки в порядке чтения — сверху вниз.
    static let порядок: [МеркаМоего] = [.голова, .плечи, .грудь, .рукав, .талия, .бёдра, .шаг, .стопа]

    /// Доля фигуры: 0 — женская, 1 — мужская, пол не выбран — средняя.
    static func доля(_ пол: ПолТелаМоего?) -> CGFloat {
        guard let пол else { return 0.5 }
        return пол == .мужской ? 1 : 0
    }

    static func смесь(_ а: CGFloat, _ б: CGFloat, _ t: CGFloat) -> CGFloat { а + (б - а) * t }

    /// Точка «женская → мужская» в долях фигуры.
    struct Пара {
        let ж: CGPoint
        let м: CGPoint

        init(_ жx: CGFloat, _ жy: CGFloat, _ мx: CGFloat, _ мy: CGFloat) {
            ж = CGPoint(x: жx, y: жy)
            м = CGPoint(x: мx, y: мy)
        }

        func при(_ t: CGFloat) -> CGPoint {
            CGPoint(x: ГеометрияТелаМоего.смесь(ж.x, м.x, t), y: ГеометрияТелаМоего.смесь(ж.y, м.y, t))
        }
    }

    /// Кусок контура: линия или кривая (через опорную точку).
    enum Кусок {
        case линия(Пара)
        case кривая(Пара, через: Пара)
    }

    /// Голова: центр и полуоси (женская, мужская).
    private static let центрГоловы = Пара(50, 21, 50, 21)
    private static let полуосиГоловы = Пара(10.5, 13, 11.2, 13.6)

    /// Правая половина от шеи до шага: плечо, рука и кисть, подмышка, бок, бедро, нога и стопа, внутренняя сторона ноги.
    private static let начало = Пара(53.5, 33, 54.5, 33)
    private static let куски: [Кусок] = [
        .линия(Пара(54.5, 42, 55.5, 42)),
        .кривая(Пара(69.5, 50, 74, 50), через: Пара(61, 43, 64, 43)),
        .кривая(Пара(76, 86, 80, 86), через: Пара(74.5, 56, 79.5, 56)),
        .линия(Пара(78.5, 118, 83, 121)),
        .кривая(Пара(75, 130, 79, 134), через: Пара(80, 129, 84.5, 133)),
        .линия(Пара(73, 119, 76.5, 122)),
        .линия(Пара(70.5, 94, 74, 96)),
        .кривая(Пара(65.5, 62, 69, 62), через: Пара(69, 72, 73, 72)),
        .кривая(Пара(61.5, 98, 66, 101), через: Пара(70.5, 79, 70.5, 82)),
        .кривая(Пара(71, 121, 68, 120), через: Пара(69.5, 106, 67, 112)),
        .кривая(Пара(63, 176, 64, 176), через: Пара(71, 146, 69, 146)),
        .кривая(Пара(59, 225, 61, 225), через: Пара(62.5, 205, 63.5, 205)),
        .линия(Пара(62, 233, 64.5, 233)),
        .кривая(Пара(58, 237.5, 60, 237.5), через: Пара(63.5, 237.5, 66, 237.5)),
        .линия(Пара(52, 237.5, 52, 237.5)),
        .линия(Пара(52.5, 226, 52.5, 226)),
        .кривая(Пара(53.5, 176, 53.5, 176), через: Пара(51.5, 205, 51.5, 205)),
        .кривая(Пара(50, 133, 50, 131), через: Пара(54.5, 150, 54, 150))
    ]

    /// Опорные точки мерок.
    private static let плечо = Пара(69.5, 50, 74, 50)
    private static let локоть = Пара(76, 86, 80, 86)
    private static let запястье = Пара(78.5, 118, 83, 121)

    /// Контур фигуры: голова и тело (правая половина, потом зеркально обратно).
    static func контур(_ м: МасштабТелаМоего, _ t: CGFloat) -> Path {
        var путь = Path()
        let ц = центрГоловы.при(t)
        let о = полуосиГоловы.при(t)
        путь.addEllipse(in: м.рамка(ц.x - о.x, ц.y - о.y, ц.x + о.x, ц.y + о.y))
        var точки: [CGPoint] = [начало.при(t)]
        var опоры: [CGPoint?] = [nil]
        for кусок in куски {
            switch кусок {
            case .линия(let до):
                точки.append(до.при(t))
                опоры.append(nil)
            case .кривая(let до, let через):
                точки.append(до.при(t))
                опоры.append(через.при(t))
            }
        }
        путь.move(to: м.т(точки[0]))
        for н in 1..<точки.count {
            if let опора = опоры[н] {
                путь.addQuadCurve(to: м.т(точки[н]), control: м.т(опора))
            } else {
                путь.addLine(to: м.т(точки[н]))
            }
        }
        // Левая половина — зеркально и в обратном порядке: кусок «н−1 → н» идёт «н → н−1» с той же опорой.
        for н in stride(from: точки.count - 1, through: 1, by: -1) {
            let до = зеркало(точки[н - 1])
            if let опора = опоры[н] {
                путь.addQuadCurve(to: м.т(до), control: м.т(зеркало(опора)))
            } else {
                путь.addLine(to: м.т(до))
            }
        }
        путь.closeSubpath()
        return путь
    }

    private static func зеркало(_ p: CGPoint) -> CGPoint { CGPoint(x: 100 - p.x, y: p.y) }

    /// Линия мерки: кольцо обхвата или отрезки с засечками на концах.
    static func линия(_ мерка: МеркаМоего, _ м: МасштабТелаМоего, _ t: CGFloat) -> Path {
        var путь = Path()
        func кольцо(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) {
            путь.addEllipse(in: м.рамка(cx - rx, cy - ry, cx + rx, cy + ry))
        }
        func ломаная(_ точки: [CGPoint]) {
            guard let первая = точки.first else { return }
            путь.move(to: м.т(первая))
            for p in точки.dropFirst() { путь.addLine(to: м.т(p)) }
        }
        func засечка(_ p: CGPoint, _ длина: CGFloat, вертикальная: Bool) {
            let d = длина / 2
            путь.move(to: м.т(вертикальная ? CGPoint(x: p.x, y: p.y - d) : CGPoint(x: p.x - d, y: p.y)))
            путь.addLine(to: м.т(вертикальная ? CGPoint(x: p.x, y: p.y + d) : CGPoint(x: p.x + d, y: p.y)))
        }
        let к = смесь
        switch мерка {
        case .голова:
            кольцо(50, 16.5, к(12, 12.8, t), 2.6)
        case .плечи:
            let x = плечо.при(t).x
            ломаная([CGPoint(x: 100 - x, y: 46), CGPoint(x: x, y: 46)])
            засечка(CGPoint(x: 100 - x, y: 46), 5, вертикальная: true)
            засечка(CGPoint(x: x, y: 46), 5, вертикальная: true)
        case .грудь:
            кольцо(50, к(72, 70, t), к(18.5, 20.5, t), 3.2)
        case .талия:
            кольцо(50, к(98, 101, t), к(12.5, 17, t), 3)
        case .бёдра:
            кольцо(50, к(121, 120, t), к(22, 19, t), 3.2)
        case .рукав:
            let п = плечо.при(t)
            let л = локоть.при(t)
            let з = запястье.при(t)
            ломаная([CGPoint(x: 100 - п.x - 3, y: п.y + 1), CGPoint(x: 100 - л.x - 3.5, y: л.y),
                      CGPoint(x: 100 - з.x - 3.5, y: з.y)])
            засечка(CGPoint(x: 100 - з.x - 3.5, y: з.y), 4, вертикальная: false)
        case .шаг:
            ломаная([CGPoint(x: 52.5, y: к(136, 134, t)), CGPoint(x: 55.5, y: 176), CGPoint(x: 54.5, y: 236)])
            засечка(CGPoint(x: 54.5, y: 236), 4, вертикальная: false)
        case .стопа:
            let конец = к(62.5, 65, t)
            ломаная([CGPoint(x: 52, y: 242), CGPoint(x: конец, y: 242)])
            засечка(CGPoint(x: 52, y: 242), 4, вертикальная: true)
            засечка(CGPoint(x: конец, y: 242), 4, вертикальная: true)
        }
        return путь
    }

    /// Где число мерки: точка и сторона (слева — число прижато к точке правым краем).
    static func подпись(_ мерка: МеркаМоего, _ t: CGFloat) -> (точка: CGPoint, слева: Bool) {
        let к = смесь
        let бок = к(83, 88, t)
        switch мерка {
        case .голова: return (CGPoint(x: 66.5, y: 16.5), false)
        case .плечи: return (CGPoint(x: плечо.при(t).x + 4, y: 43), false)
        case .грудь: return (CGPoint(x: бок, y: к(72, 70, t)), false)
        case .талия: return (CGPoint(x: бок, y: к(98, 101, t)), false)
        case .бёдра: return (CGPoint(x: бок, y: к(121, 120, t)), false)
        case .рукав: return (CGPoint(x: к(17, 13, t), y: 90), true)
        case .шаг: return (CGPoint(x: к(65, 67, t), y: 182), false)
        case .стопа: return (CGPoint(x: к(66, 68.5, t), y: 240.5), false)
        }
    }

    /// Середина линии мерки — опора «вздоха».
    static func центр(_ мерка: МеркаМоего, _ t: CGFloat) -> CGPoint {
        let к = смесь
        switch мерка {
        case .голова: return CGPoint(x: 50, y: 16.5)
        case .плечи: return CGPoint(x: 50, y: 46)
        case .грудь: return CGPoint(x: 50, y: к(72, 70, t))
        case .талия: return CGPoint(x: 50, y: к(98, 101, t))
        case .бёдра: return CGPoint(x: 50, y: к(121, 120, t))
        case .рукав: return CGPoint(x: 100 - локоть.при(t).x - 3.5, y: локоть.при(t).y)
        case .шаг: return CGPoint(x: 55, y: 186)
        case .стопа: return CGPoint(x: 58, y: 242)
        }
    }

    /// Зона касания мерки в долях фигуры (x от −25 до 125 — всё поле); зоны не пересекаются.
    static func зона(_ мерка: МеркаМоего) -> CGRect {
        func р(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGRect {
            CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        }
        switch мерка {
        case .голова: return р(36, 2, 125, 33)
        case .плечи: return р(22, 33, 125, 57)
        case .грудь: return р(27, 57, 125, 86)
        case .талия: return р(27, 86, 125, 110)
        case .бёдра: return р(27, 110, 125, 134)
        case .рукав: return р(-25, 46, 27, 140)
        case .шаг: return р(50, 134, 125, 230)
        case .стопа: return р(44, 230, 125, 248)
        }
    }
}

/// Перевод долей фигуры в точки вида: поле 150 × 248 вписано в рамку по центру.
struct МасштабТелаМоего {
    let k: CGFloat
    let x0: CGFloat
    let y0: CGFloat

    init(_ рамка: CGRect) {
        let г = ГеометрияТелаМоего.self
        k = max(0.01, min(рамка.width / г.ширина, рамка.height / г.высота))
        x0 = рамка.midX - г.ширина * k / 2 + г.сдвиг * k
        y0 = рамка.midY - г.высота * k / 2
    }

    func т(_ p: CGPoint) -> CGPoint { CGPoint(x: x0 + p.x * k, y: y0 + p.y * k) }

    func т(_ x: CGFloat, _ y: CGFloat) -> CGPoint { т(CGPoint(x: x, y: y)) }

    func рамка(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> CGRect {
        let a = т(x1, y1)
        let b = т(x2, y2)
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}

// MARK: - Формы

/// Контур фигуры; доля 0…1 перетекает анимацией.
struct ФигураТелаМоего: Shape {
    var доля: CGFloat

    var animatableData: CGFloat {
        get { доля }
        set { доля = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ГеометрияТелаМоего.контур(МасштабТелаМоего(rect), доля)
    }
}

/// Линия одной мерки на фигуре.
struct ЛинияМеркиТелаМоего: Shape {
    let мерка: МеркаМоего
    var доля: CGFloat

    var animatableData: CGFloat {
        get { доля }
        set { доля = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ГеометрияТелаМоего.линия(мерка, МасштабТелаМоего(rect), доля)
    }
}

// MARK: - Силуэт

struct СилуэтМерокМоего: View {
    let тело: ТелоМоего
    let пол: ПолТелаМоего?
    let выбрана: МеркаМоего
    let выбрать: (МеркаМоего) -> Void
    @ObservedObject private var режим = РежимУстройства.shared
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @Environment(\.horizontalSizeClass) private var классШирины
    @State private var нарисовано: CGFloat = 0
    @State private var толчки: [МеркаМоего: Int] = [:]

    init(тело: ТелоМоего, пол: ПолТелаМоего?, выбрана: МеркаМоего, выбрать: @escaping (МеркаМоего) -> Void) {
        self.тело = тело
        self.пол = пол
        self.выбрана = выбрана
        self.выбрать = выбрать
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    /// 300 pt на телефоне, 320 — на широком экране; ширина — по пропорции поля.
    private var высота: CGFloat { классШирины == .regular ? 320 : 300 }

    var body: some View {
        let доля = ГеометрияТелаМоего.доля(пол)
        GeometryReader { место in
            let м = МасштабТелаМоего(CGRect(origin: .zero, size: место.size))
            ZStack(alignment: .topLeading) {
                фигура(доля)
                ForEach(ГеометрияТелаМоего.порядок, id: \.self) { мерка in
                    линия(мерка, доля, м)
                }
                ForEach(ГеометрияТелаМоего.порядок, id: \.self) { мерка in
                    подпись(мерка, доля, м)
                }
                ForEach(ГеометрияТелаМоего.порядок, id: \.self) { мерка in
                    зона(мерка, м)
                }
            }
            .frame(width: место.size.width, height: место.size.height, alignment: .topLeading)
        }
        .frame(width: высота * ГеометрияТелаМоего.пропорция, height: высота)
        // Линии — Shape (не отражаются), подписи и зоны — .position (в RTL отражается): фигура всегда слева направо.
        .environment(\.layoutDirection, .leftToRight)
        .frame(maxWidth: .infinity)
        .animation(тихо ? nil : Animation.spring(response: 0.55, dampingFraction: 0.82), value: доля)
        .accessibilityElement(children: .contain)
        .onAppear {
            guard нарисовано < 1 else { return }
            if тихо {
                нарисовано = 1
            } else {
                withAnimation(.easeOut(duration: 0.9)) { нарисовано = 1 }
            }
        }
        .onChange(of: тело.мерки) { старые, новые in
            guard !тихо else { return }
            for м in МеркаМоего.allCases where новые[м.rawValue] != nil && старые[м.rawValue] != новые[м.rawValue] {
                толчки[м, default: 0] += 1
            }
        }
    }

    // MARK: Части

    private func фигура(_ доля: CGFloat) -> some View {
        ZStack {
            ФигураТелаМоего(доля: доля)
                .fill(Theme.оттенокАкцента)
                .opacity(нарисовано)
            ФигураТелаМоего(доля: доля)
                .trim(from: 0, to: нарисовано)
                .stroke(Theme.акцент.opacity(0.45), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func линия(_ мерка: МеркаМоего, _ доля: CGFloat, _ м: МасштабТелаМоего) -> some View {
        let есть = тело.мерка(мерка) != nil
        let примерно = тело.примерная(мерка)
        let эта = мерка == выбрана
        let форма = ЛинияМеркиТелаМоего(мерка: мерка, доля: доля)
        let центр = м.т(ГеометрияТелаМоего.центр(мерка, доля))
        let ширинаПоля = max(1, ГеометрияТелаМоего.ширина * м.k)
        let высотаПоля = max(1, ГеометрияТелаМоего.высота * м.k)
        let якорь = UnitPoint(x: min(1, max(0, центр.x / ширинаПоля)), y: min(1, max(0, центр.y / высотаПоля)))
        return ZStack {
            форма
                .stroke(Theme.акцент.opacity(эта ? 0.18 : 0), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            форма
                .stroke(Theme.текстВторой.opacity(есть ? 0 : (эта ? 0.9 : 0.55)),
                        style: StrokeStyle(lineWidth: эта ? 1.8 : 1.4, lineCap: .round, dash: [3, 3]))
            форма
                .trim(from: 0, to: есть ? 1 : 0)
                .stroke(примерно ? Theme.акцент.opacity(0.6) : Theme.акцент,
                        style: StrokeStyle(lineWidth: эта ? 3 : 2.2, lineCap: .round, lineJoin: .round))
        }
        .phaseAnimator(тихо ? [0.0] : [0.0, 1.0, 0.0], trigger: толчки[мерка] ?? 0) { содержимое, фаза in
            содержимое.scaleEffect(1 + 0.06 * CGFloat(фаза), anchor: якорь)
        } animation: { _ in
            .spring(response: 0.28, dampingFraction: 0.55)
        }
        .animation(тихо ? nil : Animation.easeOut(duration: 0.45), value: есть)
        .animation(ДвижениеСайта.выбор, value: эта)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func подпись(_ мерка: МеркаМоего, _ доля: CGFloat, _ м: МасштабТелаМоего) -> some View {
        let место = ГеометрияТелаМоего.подпись(мерка, доля)
        let точка = м.т(место.точка)
        let эта = мерка == выбрана
        if let x = тело.мерка(мерка) {
            HStack(spacing: 1) {
                if тело.примерная(мерка) {
                    Text("≈")
                }
                Text(ЧислоМоего.ч(x))
                    .contentTransition(.numericText(value: x))
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(эта ? Theme.акцент : (тело.примерная(мерка) ? Theme.текстВторой : Theme.текст))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(эта ? Theme.оттенокАкцента : Color.clear, in: Capsule())
            .fixedSize()
            .frame(width: 72, alignment: место.слева ? .trailing : .leading)
            .position(x: место.слева ? точка.x - 36 : точка.x + 36, y: точка.y)
            .animation(тихо ? nil : Animation.spring(response: 0.35, dampingFraction: 0.8), value: x)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else if эта {
            Text("?")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Theme.оттенокАкцента, in: Capsule())
                .frame(width: 72, alignment: место.слева ? .trailing : .leading)
                .position(x: место.слева ? точка.x - 36 : точка.x + 36, y: точка.y)
                .transition(.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func зона(_ мерка: МеркаМоего, _ м: МасштабТелаМоего) -> some View {
        let р = ГеометрияТелаМоего.зона(мерка)
        let рамка = м.рамка(р.minX, р.minY, р.maxX, р.maxY)
        return Button {
            выбрать(мерка)
        } label: {
            Color.clear
                .frame(width: max(1, рамка.width), height: max(1, рамка.height))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: рамка.midX, y: рамка.midY)
        .accessibilityLabel(Self.подписьДоступности(мерка, тело))
        .accessibilityAddTraits(мерка == выбрана ? .isSelected : [])
    }

    /// «Обхват груди, 96 сантиметров», «…, примерно» или «…, не указано».
    static func подписьДоступности(_ мерка: МеркаМоего, _ тело: ТелоМоего) -> String {
        guard let x = тело.мерка(мерка) else { return мерка.название + ", " + МоёТелоText.т("mb_a11y_empty") }
        let число = мерка.название + ", " + ЧислоМеркиМоего.словами(x)
        return тело.примерная(мерка) ? число + ", " + МоёТелоText.т("mb_a11y_approx") : число
    }
}

// MARK: - Малая фигура «как мерить»

/// Маленькая фигура с одной линией мерки — картинка к «Как мерить» в панели.
struct МалыйСилуэтМеркиМоего: View {
    let мерка: МеркаМоего
    let пол: ПолТелаМоего?

    init(мерка: МеркаМоего, пол: ПолТелаМоего?) {
        self.мерка = мерка
        self.пол = пол
    }

    var body: some View {
        let доля = ГеометрияТелаМоего.доля(пол)
        ZStack {
            ФигураТелаМоего(доля: доля)
                .fill(Theme.оттенокАкцента)
            ФигураТелаМоего(доля: доля)
                .stroke(Theme.акцент.opacity(0.4), lineWidth: 0.8)
            ЛинияМеркиТелаМоего(мерка: мерка, доля: доля)
                .stroke(Theme.акцент, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
