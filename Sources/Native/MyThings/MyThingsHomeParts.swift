import SwiftUI
import UIKit
import PhotosUI
import Vision

/**
 «МОЙ ДОМ» — ОБЩИЕ ЧАСТИ ЭКРАНОВ (владелец 16.10.2026: «стандарты = удобство: не пустые поля, а выбор по стандартам,
 шаблоны, камера»; «удобно для глаз, ровная схема везде, мощная анимированная подача, летает на всех девайсах»).

   · РегуляторДома — число и линейка сантиметров, как у мерок (ЛинейкаМеркиМоего): деления прилипают к шагу, щелчок
     на каждом, «−» и «+»; пустое значение стоит на «обычно» серым и не пишется, пока его не сдвинули; пишется, когда
     палец остановился (0,35 с). Для VoiceOver — регулируемый элемент;
   · ВыборКомнатыДома — «Весь дом» и комнаты чипами; СтрокаДома — строка раздела 48 pt со стрелкой;
     ПолеТекстаДома — текст в рамке, как поле модели у устройств; КругЦветаДома — чип цвета палитры;
   · РисунокЦоколяДома — цоколь картинкой (резьба, штыри, «таблетка», капсула, трубка), чтобы узнать свой без слов;
   · КнопкаЗамераДома — «Измерить в AR»: линейка «Поместится ли?» в режиме замера (ЛинейкаПодачи), если AR есть;
   · ВыборСнимкаДома — снимок только по нажатию: системная камера (КамераПодачи) или системный выбор фото (доступа
     к фото не нужно);
   · ПалитраФотоДома — до пяти цветов фото комнаты, ближайших из 16 цветов каталога, — на телефоне, вне главной нити;
   · НаклейкаТехникиДома — текст наклейки техники (Vision на телефоне) → кандидаты модели и бренда; снимок не
     хранится и никуда не уходит.
 */

// MARK: - Регулятор

struct РегуляторДома: View {
    let заголовок: String
    let значение: Int?
    let пределы: ClosedRange<Int>
    let шаг: Int
    let обычно: Int
    let примерно: Bool
    let единица: String
    let задать: (Int) -> Void
    @State private var позиция: Int? = nil
    @State private var готов = false
    @State private var задача: Task<Void, Never>? = nil

    private static let ширинаДеления: CGFloat = 10

    init(заголовок: String, значение: Int?, пределы: ClosedRange<Int>, шаг: Int = 1, обычно: Int,
         примерно: Bool = false, единица: String = МойДомText.т("mh_cm"), задать: @escaping (Int) -> Void) {
        self.заголовок = заголовок
        self.значение = значение
        self.пределы = пределы
        self.шаг = max(1, шаг)
        self.обычно = обычно
        self.примерно = примерно
        self.единица = единица
        self.задать = задать
    }

    /// Делений после нулевого.
    private var последний: Int { max(0, (пределы.upperBound - пределы.lowerBound) / шаг) }

    private func индекс(_ x: Int) -> Int {
        min(последний, max(0, Int((Double(x - пределы.lowerBound) / Double(шаг)).rounded())))
    }

    private func величина(_ н: Int) -> Int { пределы.lowerBound + н * шаг }

    private var начальное: Int { значение ?? обычно }

    /// Пока линейка стоит у самого значения — само значение (вне шага не округляется на глазах); сдвинули — деление.
    private var показ: Int {
        if let значение, позиция == nil || позиция == индекс(значение) { return значение }
        return величина(позиция ?? индекс(начальное))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                if примерно && значение != nil {
                    Text(МойДомText.т("mh_approx"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.оранжевый)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                кнопкаШага(-1)
                число
                кнопкаШага(1)
            }
            линейка
                .frame(height: 50)
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(ДвижениеСайта.смена, value: примерно)
        .sensoryFeedback(.selection, trigger: позиция) { старое, новое in старое != nil && новое != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(заголовок)
        .accessibilityValue(подписьЗначения)
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: сдвинуть(1)
            case .decrement: сдвинуть(-1)
            @unknown default: break
            }
        }
        .onAppear {
            позиция = индекс(начальное)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                готов = true
            }
        }
        .onChange(of: позиция) { _, новая in
            guard готов else { return }
            задача?.cancel()
            задача = nil
            guard let новая else { return }
            let x = величина(новая)
            guard x != значение else { return }
            задача = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                задача = nil
                задать(x)
            }
        }
        .onChange(of: значение) { _, новое in
            // Значение поставили снаружи (шаблон, замер AR) — линейка доезжает; палец двигает — не мешаем.
            guard let новое, задача == nil else { return }
            let н = индекс(новое)
            guard позиция != н else { return }
            withAnimation(ДвижениеСайта.прокрутка) { позиция = н }
        }
        .onDisappear {
            guard let ждёт = задача else { return }
            ждёт.cancel()
            задача = nil
            if let позиция, величина(позиция) != значение { задать(величина(позиция)) }
        }
    }

    private var подписьЗначения: String {
        guard let значение else { return МойДомText.т("mh_a11y_empty") }
        let текст = String(значение) + " " + единица
        return примерно ? текст + ", " + МойДомText.т("mh_approx") : текст
    }

    private var число: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if примерно && значение == показ {
                Text("≈")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.текстВторой)
                    .transition(.opacity)
            }
            Text(String(показ))
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(значение == nil ? Theme.текстВторой : Theme.текст)
                .contentTransition(.numericText(value: Double(показ)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(единица)
                .font(.headline)
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity)
        .animation(ДвижениеСайта.выбор, value: показ)
    }

    private func кнопкаШага(_ на: Int) -> some View {
        Button {
            сдвинуть(на)
        } label: {
            Image(systemName: на < 0 ? "minus" : "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 44, height: 44)
                .background(Theme.оттенокАкцента, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
    }

    private var линейка: some View {
        GeometryReader { место in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0...последний, id: \.self) { н in
                        деление(н)
                            .frame(width: Self.ширинаДеления, height: 50, alignment: .top)
                            .id(н)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, место.size.width / 2 - Self.ширинаДеления / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $позиция, anchor: .center)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(РазделМоего.дом.цвет)
                    .frame(width: 3, height: 32)
                    .allowsHitTesting(false)
            }
            .mask {
                LinearGradient(colors: [Color.clear, Color.black, Color.black, Color.clear], startPoint: .leading,
                               endPoint: .trailing)
            }
        }
    }

    /// Деление: крупное с числом — каждые 10 шагов, среднее — 5.
    private func деление(_ н: Int) -> some View {
        let x = величина(н)
        let большое = (x - пределы.lowerBound) % (шаг * 10) == 0
        let малое = (x - пределы.lowerBound) % (шаг * 5) == 0
        return VStack(spacing: 3) {
            Rectangle()
                .fill(большое ? Theme.текст : Theme.текстВторой.opacity(малое ? 0.8 : 0.45))
                .frame(width: большое ? 2 : 1, height: большое ? 24 : (малое ? 17 : 10))
            if большое {
                Text(String(x))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize()
            }
        }
    }

    private func сдвинуть(_ на: Int) {
        let база = позиция ?? индекс(начальное)
        let новый = min(последний, max(0, база + на))
        готов = true
        задача?.cancel()
        задача = nil
        позиция = новый
        let x = величина(новый)
        if x != значение { задать(x) }
    }
}

// MARK: - Комната вещи

/// «Где»: «Весь дом» и комнаты чипами. Комнат нет — ничего.
struct ВыборКомнатыДома: View {
    let комнаты: [КомнатаМоего]
    @Binding var комната: UUID?

    init(комнаты: [КомнатаМоего], комната: Binding<UUID?>) {
        self.комнаты = комнаты
        _комната = комната
    }

    var body: some View {
        if !комнаты.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(МойДомText.т("mh_where"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                ПотокЧипов(зазор: 8) {
                    ЧипМоего(МойДомText.т("mh_room_any"), выбран: комната == nil, значок: "house") {
                        ОткликСайта.выбор()
                        комната = nil
                    }
                    ForEach(комнаты) { к in
                        ЧипМоего(к.заголовок, выбран: комната == к.id, значок: к.вид.значок) {
                            ОткликСайта.выбор()
                            комната = к.id
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Строка

/// Строка раздела дома: значок 36 в цветном квадрате, заголовок, подпись цифрами, «≈» у примерного, стрелка.
struct СтрокаДома: View {
    let значок: String
    let заголовок: String
    let подпись: String?
    let примерно: Bool
    let действие: () -> Void

    init(значок: String, заголовок: String, подпись: String? = nil, примерно: Bool = false,
         действие: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.подпись = подпись
        self.примерно = примерно
        self.действие = действие
    }

    var body: some View {
        Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: значок, цвет: РазделМоего.дом.цвет, размер: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                    if let подпись, !подпись.isEmpty {
                        Text(подпись)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.текстВторой)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if примерно {
                    Text("≈")
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Theme.оранжевый)
                }
                СтрелкаСтрокиКабинета()
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(озвучка)
        .accessibilityAddTraits(.isButton)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

extension СтрокаДома {
    /// «Окно 130×140 см, 2 створки, примерно».
    fileprivate var озвучка: String {
        var части = [заголовок]
        if let подпись, !подпись.isEmpty { части.append(подпись) }
        if примерно { части.append(МойДомText.т("mh_approx")) }
        return части.joined(separator: ", ")
    }
}

// MARK: - Поле текста

/// Текст в рамке 44 pt: заголовок сверху, предел длины.
struct ПолеТекстаДома: View {
    let заголовок: String
    let подсказка: String
    @Binding var текст: String
    let предел: Int

    init(заголовок: String, подсказка: String, текст: Binding<String>, предел: Int = 30) {
        self.заголовок = заголовок
        self.подсказка = подсказка
        _текст = текст
        self.предел = предел
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityHidden(true)
            TextField(подсказка, text: Binding(get: { текст }, set: { новое in
                текст = String(новое.prefix(предел))
            }))
            .autocorrectionDisabled()
            .foregroundStyle(Theme.текст)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .accessibilityLabel(заголовок)
        }
    }
}

// MARK: - Цвет

/// Чип цвета палитры: круг краски (у «разноцветного» — радуга), выбранный — галочка и кольцо акцента. Цель — 44 pt.
struct КругЦветаДома: View {
    let цвет: ЦветСтандарта
    let выбран: Bool
    let размер: CGFloat
    let действие: () -> Void

    init(цвет: ЦветСтандарта, выбран: Bool, размер: CGFloat = 30, действие: @escaping () -> Void) {
        self.цвет = цвет
        self.выбран = выбран
        self.размер = размер
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            КраскаЦветаДома(цвет: цвет, размер: размер)
                .overlay {
                    if выбран {
                        Image(systemName: "checkmark")
                            .font(.system(size: размер * 0.42, weight: .heavy))
                            .foregroundStyle(цвет.светлый ? Color.black.opacity(0.75) : Color.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(Theme.акцент, lineWidth: выбран ? 2.5 : 0)
                        .padding(-4)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .animation(ДвижениеСайта.выбор, value: выбран)
        .accessibilityLabel(цвет.название)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Круг краски цвета (без нажатия): у светлых — тонкая рамка, у «разноцветного» — радуга.
struct КраскаЦветаДома: View {
    let цвет: ЦветСтандарта
    let размер: CGFloat

    init(цвет: ЦветСтандарта, размер: CGFloat = 22) {
        self.цвет = цвет
        self.размер = размер
    }

    var body: some View {
        ZStack {
            if цвет == .разноцветный {
                Circle()
                    .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                          center: .center))
            } else {
                Circle()
                    .fill(цвет.краска)
            }
            Circle()
                .strokeBorder(цвет.светлый ? Theme.линия : Color.clear, lineWidth: 1)
        }
        .frame(width: размер, height: размер)
        .accessibilityHidden(true)
    }
}

// MARK: - Цоколь картинкой

/**
 Цоколь картинкой: резьба (E27, E14, E40, E10), штыковой (B22d, B15d), спот (GU10 — толстые штыри с «шляпками»,
 GU5.3 и GU4 — тонкие), капсула (G9 — петли, G4 и GY6.35 — штырьки), «таблетка» (GX53, GX70), трубка (G13, G5, R7s),
 компактная (2G11, G23, G24). Рисуется Canvas одним проходом, без картинок в сборке.
 */
struct РисунокЦоколяДома: View {
    let код: String
    let размер: CGFloat

    init(код: String, размер: CGFloat = 30) {
        self.код = код
        self.размер = размер
    }

    private enum Форма {
        case резьба(CGFloat)
        case штыковой(CGFloat)
        case спот(толстые: Bool)
        case капсула(петли: Bool)
        case таблетка
        case трубка
        case компакт
    }

    private var форма: Форма {
        switch код {
        case "E27": return .резьба(0.40)
        case "E14": return .резьба(0.26)
        case "E40": return .резьба(0.52)
        case "E10": return .резьба(0.18)
        case "B22d": return .штыковой(0.40)
        case "B15d": return .штыковой(0.26)
        case "GU10": return .спот(толстые: true)
        case "GU5.3", "GU4": return .спот(толстые: false)
        case "G9": return .капсула(петли: true)
        case "G4", "GY6.35": return .капсула(петли: false)
        case "GX53", "GX70": return .таблетка
        case "G13", "G5", "R7s": return .трубка
        default: return .компакт
        }
    }

    var body: some View {
        let стекло = Theme.золото.opacity(0.28)
        let линия = Theme.текстВторой
        let металл = Theme.текстВторой.opacity(0.7)
        let вид = форма
        Canvas { к, р in
            let w = р.width
            let h = р.height
            switch вид {
            case .резьба(let доля), .штыковой(let доля):
                let колба = Path(ellipseIn: CGRect(x: w * 0.18, y: h * 0.02, width: w * 0.64, height: h * 0.58))
                к.fill(колба, with: .color(стекло))
                к.stroke(колба, with: .color(линия), lineWidth: 1.2)
                let шц = w * доля
                let x0 = (w - шц) / 2
                let цоколь = Path(roundedRect: CGRect(x: x0, y: h * 0.56, width: шц, height: h * 0.30), cornerRadius: 1.5)
                к.fill(цоколь, with: .color(металл))
                if case .резьба = вид {
                    var нарезка = Path()
                    for i in 1...3 {
                        let y = h * 0.56 + h * 0.075 * CGFloat(i)
                        нарезка.move(to: CGPoint(x: x0, y: y))
                        нарезка.addLine(to: CGPoint(x: x0 + шц, y: y))
                    }
                    к.stroke(нарезка, with: .color(Color.white.opacity(0.75)), lineWidth: 0.8)
                } else {
                    let штырь = Path(roundedRect: CGRect(x: x0 - w * 0.08, y: h * 0.66, width: шц + w * 0.16,
                                                         height: h * 0.06), cornerRadius: 1)
                    к.fill(штырь, with: .color(линия))
                }
                let контакт = Path(ellipseIn: CGRect(x: w / 2 - шц * 0.18, y: h * 0.86, width: шц * 0.36, height: h * 0.08))
                к.fill(контакт, with: .color(линия))
            case .спот(let толстые):
                var отражатель = Path()
                отражатель.move(to: CGPoint(x: w * 0.08, y: h * 0.08))
                отражатель.addLine(to: CGPoint(x: w * 0.92, y: h * 0.08))
                отражатель.addLine(to: CGPoint(x: w * 0.64, y: h * 0.62))
                отражатель.addLine(to: CGPoint(x: w * 0.36, y: h * 0.62))
                отражатель.closeSubpath()
                к.fill(отражатель, with: .color(стекло))
                к.stroke(отражатель, with: .color(линия), lineWidth: 1.2)
                let толщина: CGFloat = толстые ? w * 0.09 : w * 0.04
                for x in [w * 0.40, w * 0.60] {
                    let штырь = Path(roundedRect: CGRect(x: x - толщина / 2, y: h * 0.62, width: толщина,
                                                         height: h * 0.30), cornerRadius: толщина / 2)
                    к.fill(штырь, with: .color(металл))
                    if толстые {
                        let шляпка = Path(ellipseIn: CGRect(x: x - толщина, y: h * 0.84, width: толщина * 2,
                                                             height: h * 0.10))
                        к.fill(шляпка, with: .color(линия))
                    }
                }
            case .капсула(let петли):
                let капсула = Path(roundedRect: CGRect(x: w * 0.30, y: h * 0.04, width: w * 0.40, height: h * 0.56),
                                   cornerRadius: w * 0.2)
                к.fill(капсула, with: .color(стекло))
                к.stroke(капсула, with: .color(линия), lineWidth: 1.2)
                for x in [w * 0.42, w * 0.58] {
                    var штырь = Path()
                    штырь.move(to: CGPoint(x: x, y: h * 0.60))
                    if петли {
                        штырь.addQuadCurve(to: CGPoint(x: x, y: h * 0.92),
                                           control: CGPoint(x: x + (x < w / 2 ? -w * 0.16 : w * 0.16), y: h * 0.76))
                    } else {
                        штырь.addLine(to: CGPoint(x: x, y: h * 0.94))
                    }
                    к.stroke(штырь, with: .color(металл), lineWidth: 1.6)
                }
            case .таблетка:
                let таблетка = Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.34, width: w * 0.88, height: h * 0.30),
                                    cornerRadius: h * 0.12)
                к.fill(таблетка, with: .color(стекло))
                к.stroke(таблетка, with: .color(линия), lineWidth: 1.2)
                for x in [w * 0.30, w * 0.70] {
                    let штырь = Path(roundedRect: CGRect(x: x - w * 0.04, y: h * 0.64, width: w * 0.08, height: h * 0.14),
                                     cornerRadius: 1)
                    к.fill(штырь, with: .color(металл))
                }
            case .трубка:
                let трубка = Path(roundedRect: CGRect(x: w * 0.12, y: h * 0.40, width: w * 0.76, height: h * 0.20),
                                  cornerRadius: h * 0.10)
                к.fill(трубка, with: .color(стекло))
                к.stroke(трубка, with: .color(линия), lineWidth: 1.2)
                for x in [w * 0.04, w * 0.88] {
                    let торец = Path(roundedRect: CGRect(x: x, y: h * 0.38, width: w * 0.08, height: h * 0.24), cornerRadius: 1)
                    к.fill(торец, with: .color(металл))
                }
            case .компакт:
                for x in [w * 0.30, w * 0.52] {
                    let трубка = Path(roundedRect: CGRect(x: x, y: h * 0.04, width: w * 0.18, height: h * 0.56),
                                      cornerRadius: w * 0.09)
                    к.fill(трубка, with: .color(стекло))
                    к.stroke(трубка, with: .color(линия), lineWidth: 1.1)
                }
                let цоколь = Path(roundedRect: CGRect(x: w * 0.24, y: h * 0.60, width: w * 0.52, height: h * 0.28),
                                  cornerRadius: 2)
                к.fill(цоколь, with: .color(металл))
            }
        }
        .frame(width: размер, height: размер)
        .accessibilityHidden(true)
    }
}

// MARK: - Замер AR

/// «Измерить в AR»: линейка «Поместится ли?» в режиме замера; отрезки по порядку — ширина, высота, глубина (см).
/// Нет AR на устройстве или выключено рубильником — кнопки нет.
struct КнопкаЗамераДома: View {
    let название: String
    let готово: (Double?, Double?, Double?) -> Void

    init(название: String, готово: @escaping (Double?, Double?, Double?) -> Void) {
        self.название = название
        self.готово = готово
    }

    var body: some View {
        if ЛинейкаПодачи.есть {
            МалаяКнопкаАвтоподбора(заголовок: МойДомText.т("mh_ar"), значок: "ruler") {
                ОткликСайта.выбор()
                ЛинейкаПодачи.открыть(название: название, готово: готово)
            }
        }
    }
}

// MARK: - Снимок по нажатию

/// Камера (системная, КамераПодачи) и системный выбор фото по флагам; снимок отдаётся на главной нити.
struct ВыборСнимкаДома: ViewModifier {
    @Binding var камера: Bool
    @Binding var галерея: Bool
    let получено: (ИсточникСнимкаМоего) -> Void
    @State private var выбор: PhotosPickerItem? = nil

    init(камера: Binding<Bool>, галерея: Binding<Bool>, получено: @escaping (ИсточникСнимкаМоего) -> Void) {
        _камера = камера
        _галерея = галерея
        self.получено = получено
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $камера) {
                КамераПодачи(снято: { снимок in получено(.кадр(снимок)) }, закрыть: { камера = false })
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $галерея, selection: $выбор, matching: .images)
            .onChange(of: выбор) { _, новый in
                guard let новый else { return }
                выбор = nil
                Task { @MainActor in
                    guard let данные = try? await новый.loadTransferable(type: Data.self) else {
                        ОткликСайта.предупреждение()
                        return
                    }
                    получено(.файл(данные))
                }
            }
    }
}

extension View {
    /// Снимок по нажатию для «Моего дома»: камера или системный выбор фото.
    func выборСнимкаДома(камера: Binding<Bool>, галерея: Binding<Bool>,
                         получено: @escaping (ИсточникСнимкаМоего) -> Void) -> some View {
        modifier(ВыборСнимкаДома(камера: камера, галерея: галерея, получено: получено))
    }
}

// MARK: - Палитра с фото

/// Цвета фото комнаты на телефоне: снимок 48×48, каждый пиксель — к ближайшему из 16 цветов каталога, доля меньше
/// 4 % отбрасывается; самые заметные — первыми. Не на главной нити.
enum ПалитраФотоДома {
    static func цвета(_ данные: Data, предел: Int = КомнатаМоего.пределПалитры) -> [ЦветСтандарта] {
        guard let картинка = UIImage(data: данные)?.cgImage else { return [] }
        let сторона = 48
        guard let пространство = CGColorSpace(name: CGColorSpace.sRGB),
              let холст = CGContext(data: nil, width: сторона, height: сторона, bitsPerComponent: 8,
                                    bytesPerRow: сторона * 4, space: пространство,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        холст.interpolationQuality = .medium
        холст.draw(картинка, in: CGRect(x: 0, y: 0, width: сторона, height: сторона))
        guard let сырые = холст.data else { return [] }
        let байты = сырые.bindMemory(to: UInt8.self, capacity: сторона * сторона * 4)
        var веса: [ЦветСтандарта: Int] = [:]
        var всего = 0
        for i in stride(from: 0, to: сторона * сторона * 4, by: 4) {
            let альфа = Double(байты[i + 3]) / 255
            guard альфа > 0.5 else { continue }
            let цвет = ЦветСтандарта.ближайший(красный: Double(байты[i]) / 255 / альфа,
                                               зелёный: Double(байты[i + 1]) / 255 / альфа,
                                               синий: Double(байты[i + 2]) / 255 / альфа)
            веса[цвет, default: 0] += 1
            всего += 1
        }
        guard всего > 0 else { return [] }
        let порог = max(1, всего * 4 / 100)
        let порядок = веса.filter { $0.value >= порог }.sorted { $0.value > $1.value }
        return Array(порядок.prefix(предел)).map { $0.key }
    }
}

// MARK: - Наклейка техники

/// Текст наклейки техники (Vision на телефоне) → кандидаты модели и бренда. Снимок не хранится.
enum НаклейкаТехникиДома {
    /// Частые бренды техники в КЗ — ищутся словом целиком.
    static let бренды: [String] = [
        "Samsung", "LG", "Bosch", "Siemens", "Beko", "Indesit", "Hotpoint", "Ariston", "Haier", "Electrolux", "AEG",
        "Whirlpool", "Candy", "Atlant", "Gorenje", "Hisense", "Midea", "Philips", "Xiaomi", "Dyson", "Tefal",
        "Redmond", "Panasonic", "Sharp", "Toshiba", "Hitachi", "Liebherr", "Miele", "Zanussi", "Artel", "Shivaki",
        "Brita", "Aquaphor", "Gree", "Kitfort", "Polaris", "Scarlett", "Vitek", "DeLonghi", "Krups", "Nespresso",
        "Thermex", "Canon", "HP", "Epson", "Brother", "Roborock", "iRobot", "Dreame", "Karcher", "Thomas", "Vestel"
    ]

    /// Слова-метки модели на наклейках (латиница, кириллица, казахский).
    private static let метки: [String] = ["model no", "model name", "model", "mod.", "m/n", "type", "модель", "мод.",
                                          "тип", "үлгі"]

    /// Строки снимка (по два варианта каждой надписи); не на главной нити.
    static func строки(_ источник: ИсточникСнимкаМоего) -> [String] {
        let готовое: ГотовоеФотоМоего?
        switch источник {
        case .кадр(let кадр): готовое = ОбработкаФотоМоего.подготовить(кадр)
        case .файл(let данные): готовое = ОбработкаФотоМоего.подготовить(данные)
        }
        guard let готовое, let кадр = UIImage(data: готовое.jpeg)?.cgImage else { return [] }
        let запрос = VNRecognizeTextRequest()
        запрос.recognitionLevel = .accurate
        запрос.usesLanguageCorrection = false
        let поддержка = (try? запрос.supportedRecognitionLanguages()) ?? []
        let языки = ["en-US", "ru-RU"].filter { поддержка.contains($0) }
        if !языки.isEmpty { запрос.recognitionLanguages = языки }
        let обработчик = VNImageRequestHandler(cgImage: кадр, orientation: .up, options: [:])
        do {
            try обработчик.perform([запрос])
        } catch {
            return []
        }
        var итог: [String] = []
        for наблюдение in запрос.results ?? [] {
            for кандидат in наблюдение.topCandidates(2) { итог.append(кандидат.string) }
        }
        return итог
    }

    /// Похоже на код модели: 4–24 знака, есть и буква, и цифра; не напряжение, мощность, частота, вес, серийный.
    static func похожеНаМодель(_ слово: String) -> Bool {
        let с = слово.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]\"'"))
        guard (4...24).contains(с.count), с.contains(where: \.isLetter), с.contains(where: \.isNumber) else { return false }
        let верх = с.uppercased()
        let хвосты = ["V", "W", "HZ", "KG", "КГ", "MM", "ММ", "BAR", "MPA", "КВТ", "KW", "Л", "L", "A", "А"]
        if let цифры = верх.firstIndex(where: { !$0.isNumber && $0 != "-" && $0 != "." && $0 != "/" && $0 != "~" }),
           верх[верх.startIndex..<цифры].contains(where: \.isNumber), хвосты.contains(String(верх[цифры...])) {
            return false
        }
        let запрет = ["IPX", "S/N", "SN:", "SER", "EAN", "WWW", "HTTP", "CE", "ГОСТ", "ТР ТС"]
        return !запрет.contains { верх.hasPrefix($0) }
    }

    /// Кандидаты модели (с меткой — первыми, до четырёх) и бренды (до двух) из строк наклейки.
    static func разобрать(_ строки: [String]) -> (модели: [String], бренды: [String]) {
        var модели: [String] = []
        func добавить(_ слово: String) {
            let чистое = слово.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]\"' "))
            guard похожеНаМодель(чистое), !модели.contains(where: { $0.uppercased() == чистое.uppercased() }) else { return }
            модели.append(чистое)
        }
        for строка in строки {
            let нижняя = строка.lowercased()
            guard let метка = метки.first(where: { нижняя.contains($0) }),
                  let место = строка.range(of: метка, options: .caseInsensitive) else { continue }
            let хвост = строка[место.upperBound...]
            for слово in хвост.split(whereSeparator: { $0 == " " || $0 == ":" }).prefix(2) { добавить(String(слово)) }
        }
        for строка in строки {
            for слово in строка.split(separator: " ") { добавить(String(слово)) }
        }
        var найденные: [String] = []
        for строка in строки {
            let слова = Set(строка.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            for бренд in бренды where слова.contains(бренд.uppercased()) && !найденные.contains(бренд) {
                найденные.append(бренд)
            }
        }
        return (Array(модели.prefix(4)), Array(найденные.prefix(2)))
    }
}
