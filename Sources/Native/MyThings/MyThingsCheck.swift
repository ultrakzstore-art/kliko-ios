import SwiftUI
import UIKit

/**
 «МОЁ» — ПРОВЕРКА СНИМКА И РИСУНКИ ПОВЕРХ ФОТО.

   · ПроверкаСнимкаМоего — шаг после затвора или галереи: снимок «проявляется» (1,04 → 1 и прозрачность), у машины —
     два кольца колёс (белый пунктир с зелёным свечением) появляются пружиной 0,6 → 1 и дважды пульсируют, тащатся
     пальцем, размер — общим ползунком; Vision увидел людей — оранжевая отметка. У тела — точки позы по очереди сверху
     вниз и кости, дорисовывающиеся за 0,5 с; отметка «В полный рост», «Видно не всё» или «Человека не видно». Внизу —
     «Сохранить на телефоне» и «Переснять», мелко — «Фото останется только на этом телефоне».
   · КолёсаНаФотоМоего — фото и кольца колёс (доли снимка) — и в проверке, и в редакторе машины.
   · ПозаНаФотоМоего — фото и точки позы.
 Рисунки поверх фото всегда слева направо (координаты снимка), даже в арабском. «Уменьшение движения» — всё сразу.
 */
struct ПроверкаСнимкаМоего: View {
    let исходный: СнимокМоего
    let шаблон: ШаблонСъёмкиМоего
    let тихо: Bool
    let сохранить: @MainActor (СнимокМоего) async -> Bool
    let переснять: () -> Void
    let закрыть: () -> Void
    @State private var колёса: [КругМоего]
    @State private var появилось = false
    @State private var сохраняем = false
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init(снимок: СнимокМоего, шаблон: ШаблонСъёмкиМоего, тихо: Bool,
         сохранить: @escaping @MainActor (СнимокМоего) async -> Bool, переснять: @escaping () -> Void,
         закрыть: @escaping () -> Void) {
        self.исходный = снимок
        self.шаблон = шаблон
        self.тихо = тихо
        self.сохранить = сохранить
        self.переснять = переснять
        self.закрыть = закрыть
        _колёса = State(initialValue: снимок.колёса.isEmpty ? ОбработкаФотоМоего.колёсаПоУмолчанию : снимок.колёса)
    }

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаПримерочной(заголовок: шаблон.заголовок, закрыть: закрыть)
            ScrollView {
                VStack(spacing: 14) {
                    фото
                        .scaleEffect(появилось ? 1 : 1.04)
                        .opacity(появилось ? 1 : 0)
                    отметка
                    if !шаблон.тело {
                        Text(т("my_wheels_hint"))
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        ПолзунокКолёсМоего(колёса: $колёса, наТёмном: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            низ
        }
        .overlay(alignment: .bottom) {
            if let весть {
                ВестьПримерочной(текст: весть)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 150)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if тихо {
                появилось = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { появилось = true }
            }
        }
    }

    @ViewBuilder
    private var фото: some View {
        if шаблон.тело {
            ПозаНаФотоМоего(картинка: исходный.картинка, точки: исходный.поза, тихо: тихо)
                .frame(maxHeight: 520)
        } else {
            КолёсаНаФотоМоего(картинка: исходный.картинка, колёса: $колёса, правка: true, тихо: тихо)
                .frame(maxHeight: 520)
        }
    }

    /// Что увидел Vision — только подсказка, сохранить можно всё равно.
    @ViewBuilder
    private var отметка: some View {
        if шаблон.тело {
            switch исходный.полныйРост {
            case .some(true):
                значок(т("my_check_full"), "checkmark.circle.fill", Theme.зелёныйЯркий)
            case .some(false):
                значок(т("my_check_part"), "exclamationmark.triangle.fill", Theme.оранжевый)
            case .none:
                значок(т("my_check_nobody"), "person.fill.questionmark", Theme.оранжевый)
            }
        } else if исходный.люди == true {
            значок(т("my_check_people"), "person.2.fill", Theme.оранжевый)
        }
    }

    private func значок(_ текст: String, _ значок: String, _ цвет: Color) -> some View {
        Label {
            Text(текст)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: значок)
                .foregroundStyle(цвет)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay { Capsule().strokeBorder(цвет.opacity(0.6), lineWidth: 1) }
    }

    private var низ: some View {
        VStack(spacing: 10) {
            ЗелёнаяКнопкаФото(заголовок: т(сохраняем ? "my_cam_preparing" : "my_photo_save"), значок: "checkmark") {
                сохранитьСнимок()
            }
            .disabled(сохраняем)
            ЗелёнаяКнопкаФото(заголовок: т("my_car_retake"), значок: "camera.viewfinder", контурная: true,
                              наТёмном: true) {
                ОткликСайта.выбор()
                переснять()
            }
            .disabled(сохраняем)
            Label(т("my_photo_local"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.55)], startPoint: .top,
                           endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private func сохранитьСнимок() {
        guard !сохраняем else { return }
        сохраняем = true
        var готовый = исходный
        готовый.колёса = шаблон.тело ? [] : колёса
        Task { @MainActor in
            let удачно = await сохранить(готовый)
            сохраняем = false
            if удачно {
                ОткликСайта.успех()
                закрыть()
            } else {
                ОткликСайта.предупреждение()
                показатьВесть(т("my_photo_save_fail"))
            }
        }
    }

    /// Весть внизу уходит сама, как у камеры (КамераШаблонаМоего.показатьВесть).
    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}

// MARK: - Кольца колёс

/// Фото машины и кольца колёс поверх. правка — кольца тащатся пальцем (готово — когда отпустили).
struct КолёсаНаФотоМоего: View {
    let картинка: UIImage
    @Binding var колёса: [КругМоего]
    let правка: Bool
    let тихо: Bool
    var готово: (() -> Void)?
    @State private var начало: [Int: CGPoint] = [:]
    @State private var появились = false
    @State private var пульс = 0

    init(картинка: UIImage, колёса: Binding<[КругМоего]>, правка: Bool, тихо: Bool, готово: (() -> Void)? = nil) {
        self.картинка = картинка
        _колёса = колёса
        self.правка = правка
        self.тихо = тихо
        self.готово = готово
    }

    var body: some View {
        Image(uiImage: картинка)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { место in
                    ForEach(колёса.indices, id: \.self) { номер in
                        кольцо(номер, место.size)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(МоёText.т("my_wheels_t"))
            .onAppear {
                guard !появились else { return }
                if тихо {
                    появились = true
                    return
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.2)) { появились = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    пульс += 1
                }
            }
    }

    @ViewBuilder
    private func кольцо(_ номер: Int, _ размер: CGSize) -> some View {
        if колёса.indices.contains(номер) {
            let круг = колёса[номер]
            let диаметр = max(16, CGFloat(круг.r) * размер.width * 2)
            ZStack {
                Circle()
                    .stroke(Theme.зелёныйЯркий.opacity(0.55), lineWidth: 8)
                    .blur(radius: 5)
                Circle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 5]))
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            .frame(width: диаметр, height: диаметр)
            .contentShape(Circle().inset(by: -12))
            .scaleEffect(появились ? 1 : 0.6)
            .opacity(появились ? 1 : 0)
            .phaseAnimator(тихо ? [1.0] : [1.0, 1.12, 1.0, 1.12, 1.0], trigger: пульс) { вид, масштаб in
                вид.scaleEffect(масштаб)
            } animation: { _ in
                .easeInOut(duration: 0.22)
            }
            .position(x: CGFloat(круг.x) * размер.width, y: CGFloat(круг.y) * размер.height)
            .gesture(перетаскивание(номер, размер), including: правка ? .all : .none)
        }
    }

    private func перетаскивание(_ номер: Int, _ размер: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { жест in
                guard колёса.indices.contains(номер), размер.width > 0, размер.height > 0 else { return }
                let старт = начало[номер] ?? CGPoint(x: колёса[номер].x, y: колёса[номер].y)
                if начало[номер] == nil {
                    начало[номер] = старт
                    ОткликСайта.выбор()
                }
                колёса[номер].x = КругМоего.доля(Double(старт.x + жест.translation.width / размер.width))
                колёса[номер].y = КругМоего.доля(Double(старт.y + жест.translation.height / размер.height))
            }
            .onEnded { _ in
                начало[номер] = nil
                готово?()
            }
    }
}

/// Общий размер колец: ползунок, одинаково у обоих колёс.
struct ПолзунокКолёсМоего: View {
    @Binding var колёса: [КругМоего]
    var наТёмном: Bool
    var готово: (() -> Void)?

    init(колёса: Binding<[КругМоего]>, наТёмном: Bool = false, готово: (() -> Void)? = nil) {
        _колёса = колёса
        self.наТёмном = наТёмном
        self.готово = готово
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.caption)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { колёса.first?.r ?? 0.08 }, set: { новый in
                for номер in колёса.indices { колёса[номер].r = новый }
            }), in: 0.03...0.2, onEditingChanged: { идёт in
                if !идёт { готово?() }
            })
            .tint(Theme.зелёныйЯркий)
            .accessibilityLabel(МоёText.т("my_wheels_size"))
            Image(systemName: "circle")
                .font(.title3)
                .accessibilityHidden(true)
        }
        .foregroundStyle(наТёмном ? Color.white.opacity(0.8) : Theme.текстВторой)
    }
}

/// Фото машины из гаража с кольцами: картинка читается из файла, кольца тащатся и сохраняются, когда отпустили.
struct ФотоСКолёсамиМоего: View {
    let фото: ФотоМоего
    let сохранить: ([КругМоего]) -> Void
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var картинка: UIImage?
    @State private var колёса: [КругМоего]

    init(фото: ФотоМоего, сохранить: @escaping ([КругМоего]) -> Void) {
        self.фото = фото
        self.сохранить = сохранить
        _картинка = State(initialValue: КэшФотоМоего.готовая(фото.файл))
        _колёса = State(initialValue: фото.колёса.isEmpty ? ОбработкаФотоМоего.колёсаПоУмолчанию : фото.колёса)
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий }

    var body: some View {
        VStack(spacing: 10) {
            if let картинка {
                КолёсаНаФотоМоего(картинка: картинка, колёса: $колёса, правка: true, тихо: тихо) {
                    сохранить(колёса)
                }
                .transition(.opacity)
                ПолзунокКолёсМоего(колёса: $колёса) { сохранить(колёса) }
            } else {
                Theme.поверхность2
                    .aspectRatio(фото.пропорция, contentMode: .fit)
                    .overlay { SiteSpinner.мелкий }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            }
        }
        .task(id: фото.файл) {
            if картинка == nil {
                let прочитанная = await КэшФотоМоего.загрузить(фото.файл)
                withAnimation(ДвижениеСайта.появление) { картинка = прочитанная }
            }
        }
        .onChange(of: фото.колёса) { _, новые in
            if !новые.isEmpty && новые != колёса { колёса = новые }
        }
    }
}

// MARK: - Поза

/// Фото в полный рост и точки позы: точки появляются по очереди сверху вниз, кости дорисовываются за 0,5 с.
struct ПозаНаФотоМоего: View {
    let картинка: UIImage
    let точки: [String: ТочкаМоего]
    let тихо: Bool
    @State private var видны = false
    @State private var кости = false

    init(картинка: UIImage, точки: [String: ТочкаМоего], тихо: Bool) {
        self.картинка = картинка
        self.точки = точки
        self.тихо = тихо
    }

    var body: some View {
        Image(uiImage: картинка)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { место in
                    ZStack {
                        ForEach(Array(ОбработкаФотоМоего.кости.enumerated()), id: \.offset) { пара in
                            кость(пара.element.0, пара.element.1, место.size)
                        }
                        ForEach(Array(ОбработкаФотоМоего.порядокТочек.enumerated()), id: \.offset) { пара in
                            точка(пара.element, номер: пара.offset, место.size)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
            .onAppear {
                guard !видны else { return }
                видны = true
                if тихо {
                    кости = true
                } else {
                    withAnimation(.easeOut(duration: 0.5).delay(0.35)) { кости = true }
                }
            }
    }

    private func место(_ т: ТочкаМоего, _ размер: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(т.x) * размер.width, y: CGFloat(т.y) * размер.height)
    }

    @ViewBuilder
    private func кость(_ а: String, _ б: String, _ размер: CGSize) -> some View {
        if let начало = точки[а], let конец = точки[б] {
            Path { путь in
                путь.move(to: место(начало, размер))
                путь.addLine(to: место(конец, размер))
            }
            .trim(from: 0, to: кости ? 1 : 0)
            .stroke(Theme.зелёныйЯркий, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .shadow(color: Theme.зелёныйЯркий.opacity(0.7), radius: 4)
        }
    }

    @ViewBuilder
    private func точка(_ ключ: String, номер: Int, _ размер: CGSize) -> some View {
        if let т = точки[ключ] {
            Circle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .overlay { Circle().strokeBorder(Theme.зелёныйЯркий, lineWidth: 2) }
                .shadow(color: Theme.зелёныйЯркий.opacity(0.8), radius: 5)
                .scaleEffect(видны ? 1 : 0.2)
                .opacity(видны ? 1 : 0)
                .animation(тихо ? nil : .spring(response: 0.4, dampingFraction: 0.7).delay(0.03 * Double(номер)),
                           value: видны)
                .position(место(т, размер))
        }
    }
}

// MARK: - Шаблон съёмки

/// Шаблон камеры «Моего»: машина сбоку (только задняя камера) или полный рост (обе камеры, таймер).
enum ШаблонСъёмкиМоего: Equatable {
    case машинаСбоку
    case полныйРост

    var тело: Bool { self == .полныйРост }

    /// Контур примерочной.
    var вид: ВидИИПримерки { тело ? .человек : .машина }

    var заголовок: String { МоёText.т(тело ? "my_cam_body" : "my_cam_car") }

    var подсказка: String { МоёText.т(тело ? "my_cam_body_hint" : "my_cam_car_hint") }

    var значок: String { тело ? "figure.stand" : "car.side" }

    var советы: [(значок: String, текст: String)] {
        if тело {
            return [("figure.stand", МоёText.т("my_tip_full")), ("figure.arms.open", МоёText.т("my_tip_fit")),
                    ("square.fill", МоёText.т("my_tip_bg"))]
        }
        return [("car.side", МоёText.т("my_tip_side")), ("circle.circle", МоёText.т("my_tip_wheels")),
                ("sun.max.fill", МоёText.т("my_tip_light"))]
    }
}
