import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ РОСТ И МЕРКИ» (владелец 14.10.2026: «одежда — полный рост сфоткал по шаблону, всё готово, чел может так
 одеться и сразу заказать вещи»).

   · Фото в полный рост по шаблону (камера с контуром человека, таймер 3 / 10 с) или из галереи — карточка 3:4 с
     точками позы (Vision на телефоне). Лицо не распознаётся; фото остаётся только на телефоне.
   · Рост — линейка: деления 100…230 см листаются пальцем и прилипают к сантиметру (scrollTargetBehavior .viewAligned),
     щелчок под пальцем на каждом делении, число крупно перекатом.
   · «Мои размеры» — по одному на вид (обувь, одежда, джинсы, бельё, кольцо, шапка, перчатки) в своей системе; бирка
     всех систем — из таблиц размеров (ClothingSizes, только вызовы). Детских размеров здесь нет.
   · «Мерки» — обхваты и длины тела в сантиметрах, сеткой по два поля; что продавцы указывают у вещей (rules.fit в
     схеме подачи) — первым и с пометкой.
 */
struct ЭкранТелаМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var съёмка = false
    @State private var изГалереи = false
    @State private var спроситьФото = false
    @State private var размер: ЦельРазмераМоего? = nil
    @State private var ключиСхемы: Set<String> = []

    init() {}

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }
    private func м(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        let тело = хранилище.запись.тело
        ScrollView {
            VStack(spacing: 14) {
                карточкаФото(тело.фото)
                карточкаРоста(тело.рост)
                карточкаРазмеров(тело)
                карточкаМерок(тело)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: тело.размеры)
            .animation(ДвижениеСайта.смена, value: тело.фото)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(м("my_body"))
        .клавиатураМоего()
        .fullScreenCover(isPresented: $съёмка) {
            КамераШаблонаМоего(шаблон: .полныйРост, начатьСГалереи: изГалереи) { снимок in
                await МоёХранилище.shared.сохранитьФотоТела(снимок.готовое, поза: снимок.поза,
                                                            полныйРост: снимок.полныйРост, шаблон: снимок.шаблон)
            }
        }
        .sheet(item: $размер) { цель in
            РедакторРазмераМоего(вид: цель.вид)
        }
        .confirmationDialog(м("my_car_photo_del"), isPresented: $спроситьФото, titleVisibility: .visible) {
            Button(м("my_delete"), role: .destructive) {
                withAnimation(ДвижениеСайта.смена) { хранилище.удалитьФотоТела() }
            }
            Button(м("my_cancel"), role: .cancel) {}
        }
        .onAppear { хранилище.подготовить() }
        .task {
            /* Ключи замеров вещи из схемы подачи (rules.fit): что продавцы указывают — первым. Только кэш, без сети. */
            let правила = await ЗагрузкаСхемыПодачи.изКэша()?.замеры
            ключиСхемы = Set((правила?.ключи.values.flatMap { $0 }) ?? [])
        }
    }

    // MARK: Фото

    private func карточкаФото(_ фото: ФотоМоего?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mb_photo"), значок: "figure.stand")
            if let фото {
                ФотоПозыМоего(фото: фото)
                отметка(фото)
                ПотокЧипов(зазор: 8) {
                    МалаяКнопкаАвтоподбора(заголовок: м("my_car_retake"), значок: "camera.viewfinder") { снять(false) }
                    МалаяКнопкаАвтоподбора(заголовок: м("my_car_gallery"), значок: "photo.on.rectangle") { снять(true) }
                    МалаяКнопкаАвтоподбора(заголовок: м("my_car_photo_del"), значок: "trash", опасная: true) {
                        спроситьФото = true
                    }
                }
            } else {
                пустоеФото
                ЗелёнаяКнопкаФото(заголовок: м("my_car_shoot"), значок: "camera.viewfinder") { снять(false) }
                ЗелёнаяКнопкаФото(заголовок: м("my_car_gallery"), значок: "photo.on.rectangle", контурная: true) {
                    снять(true)
                }
            }
            Label {
                Text(т("mb_photo_hint"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(Theme.текстВторой)
        }
        .карточкаМоего()
    }

    private var пустоеФото: some View {
        Theme.поверхность2
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxHeight: 260)
            .overlay {
                СилуэтПримерочной()
                    .stroke(Theme.акцент.opacity(0.6),
                            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [6, 5]))
                    .aspectRatio(СилуэтПримерочной.пропорция, contentMode: .fit)
                    .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func отметка(_ фото: ФотоМоего) -> some View {
        switch фото.полныйРост {
        case .some(true):
            Label(м("my_check_full"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.акцент)
        case .some(false):
            Label(м("my_check_part"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.оранжевый)
        case .none:
            Label(м("my_check_nobody"), systemImage: "person.fill.questionmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.оранжевый)
        }
    }

    private func снять(_ галерея: Bool) {
        ОткликСайта.выбор()
        изГалереи = галерея
        съёмка = true
    }

    // MARK: Рост

    private func карточкаРоста(_ рост: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mb_height"), значок: "ruler")
            ЛинейкаРостаМоего(рост: рост) { новый in хранилище.задатьРост(новый) }
        }
        .карточкаМоего()
    }

    // MARK: Размеры

    private func карточкаРазмеров(_ тело: ТелоМоего) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mb_sizes"), значок: "tag")
            Text(т("mb_sizes_hint"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(тело.размеры, id: \.вид) { р in
                строкаРазмера(р)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if тело.размеры.count < ВидРазмераМоего.allCases.count {
                ЗелёнаяКнопкаФото(заголовок: т("mb_add_size"), значок: "plus", контурная: true) {
                    ОткликСайта.выбор()
                    размер = ЦельРазмераМоего(вид: nil)
                }
            }
        }
        .карточкаМоего()
    }

    private func строкаРазмера(_ р: РазмерМоего) -> some View {
        Button {
            ОткликСайта.выбор()
            размер = ЦельРазмераМоего(вид: р.вид)
        } label: {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: р.вид.значок, цвет: ПрофильМоего.тело.цвет, размер: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(р.вид.подпись + " — " + р.коротко)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let бирка = р.бирка() {
                        Text(бирка.части.map { РазмерыОдеждыText.показ($0) }.joined(separator: " | "))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                СтрелкаСтрокиКабинета()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
    }

    // MARK: Мерки

    private var мерки: [МеркаМоего] {
        let все = МеркаМоего.allCases
        return все.filter { ключиСхемы.contains($0.ключСхемы) } + все.filter { !ключиСхемы.contains($0.ключСхемы) }
    }

    private func карточкаМерок(_ тело: ТелоМоего) -> some View {
        let колонки = размерТекста.isAccessibilitySize ? 1 : 2
        return VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mb_measures"), значок: "ruler")
            Text(т("mb_measures_hint"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: колонки),
                      alignment: .leading, spacing: 14) {
                ForEach(мерки, id: \.self) { мерка in
                    ПолеМеркиМоего(мерка: мерка, продавцы: ключиСхемы.contains(мерка.ключСхемы),
                                   значение: Binding(get: { тело.мерка(мерка) },
                                                     set: { хранилище.задатьМерку(мерка, $0) }))
                }
            }
        }
        .карточкаМоего()
    }
}

/// Цель листа размера: вид или nil — «Добавить размер».
struct ЦельРазмераМоего: Identifiable {
    let id = UUID()
    let вид: ВидРазмераМоего?
}

// MARK: - Фото с позой

/// Фото в полный рост из файла и точки позы — в карточке 3:4.
struct ФотоПозыМоего: View {
    let фото: ФотоМоего
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var картинка: UIImage?

    init(фото: ФотоМоего) {
        self.фото = фото
        _картинка = State(initialValue: КэшФотоМоего.готовая(фото.файл))
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий }

    var body: some View {
        Theme.поверхность2
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxHeight: 420)
            .overlay {
                if let картинка {
                    ПозаНаФотоМоего(картинка: картинка, точки: фото.поза, тихо: тихо)
                        .transition(.opacity)
                } else {
                    SiteSpinner.мелкий
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .frame(maxWidth: .infinity)
            .task(id: фото.файл) {
                if картинка == nil {
                    let прочитанная = await КэшФотоМоего.загрузить(фото.файл)
                    withAnimation(ДвижениеСайта.появление) { картинка = прочитанная }
                }
            }
    }
}

// MARK: - Линейка роста

/// Рост линейкой: деления 100…230, прилипают к сантиметру; число крупно; щелчок на каждом делении. Сохраняется,
/// когда палец остановился. VoiceOver — «Рост, 176 см», жест вверх или вниз меняет на сантиметр.
struct ЛинейкаРостаМоего: View {
    let рост: Int?
    let задать: (Int) -> Void
    @State private var позиция: Int? = nil
    @State private var готов = false
    @State private var задача: Task<Void, Never>? = nil

    private static let шаг: CGFloat = 10
    private static let пределы = ТелоМоего.пределыРоста

    init(рост: Int?, задать: @escaping (Int) -> Void) {
        self.рост = рост
        self.задать = задать
    }

    private var показ: Int { позиция ?? рост ?? 170 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(показ))
                    .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(рост == nil ? Theme.текстВторой : Theme.текст)
                    .contentTransition(.numericText(value: Double(показ)))
                Text(МоёТелоText.т("mb_cm"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.выбор, value: показ)
            линейка
                .frame(height: 64)
                .environment(\.layoutDirection, .leftToRight)
        }
        // Щелчок только на сдвиге: первая установка позиции при появлении (nil → число) молчит.
        .sensoryFeedback(.selection, trigger: позиция) { старое, новое in старое != nil && новое != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(МоёТелоText.т("mb_height"))
        .accessibilityValue(рост.map { String($0) + " " + МоёТелоText.т("mb_cm") } ?? "—")
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: сдвинуть(1)
            case .decrement: сдвинуть(-1)
            @unknown default: break
            }
        }
        .onAppear {
            позиция = рост ?? 170
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 450_000_000)
                готов = true
            }
        }
        .onChange(of: позиция) { _, новая in
            guard готов else { return }
            // Вернули палец к прежнему росту — ждущий сдвиг уже не нужен.
            задача?.cancel()
            задача = nil
            guard let новая, Self.пределы.contains(новая), новая != рост else { return }
            задача = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                задача = nil
                задать(новая)
            }
        }
        .onDisappear {
            // Записать только сдвиг пальцем, который пауза ещё не записала: открыть и уйти — не рост 170.
            guard let ждёт = задача else { return }
            ждёт.cancel()
            задача = nil
            if let позиция, позиция != рост, Self.пределы.contains(позиция) { задать(позиция) }
        }
    }

    private var линейка: some View {
        GeometryReader { место in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(Self.пределы), id: \.self) { см in
                        деление(см)
                            .frame(width: Self.шаг, height: 64, alignment: .top)
                            .id(см)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, место.size.width / 2 - Self.шаг / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $позиция, anchor: .center)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Theme.акцент)
                    .frame(width: 3, height: 40)
                    .allowsHitTesting(false)
            }
            .mask {
                LinearGradient(colors: [Color.clear, Color.black, Color.black, Color.clear], startPoint: .leading,
                               endPoint: .trailing)
            }
        }
    }

    private func деление(_ см: Int) -> some View {
        let десяток = см % 10 == 0
        let пять = см % 5 == 0
        return VStack(spacing: 4) {
            Rectangle()
                .fill(десяток ? Theme.текст : Theme.текстВторой.opacity(пять ? 0.8 : 0.45))
                .frame(width: десяток ? 2 : 1, height: десяток ? 30 : (пять ? 22 : 14))
            if десяток {
                Text(String(см))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize()
            }
        }
    }

    private func сдвинуть(_ на: Int) {
        let новый = min(Self.пределы.upperBound, max(Self.пределы.lowerBound, показ + на))
        готов = true
        позиция = новый
        задать(новый)
    }
}

// MARK: - Поле мерки

/// Мерка: название, «как мерить» по кнопке «?», пометка «Продавцы указывают это», поле в сантиметрах и «Обычно 80–120 см».
struct ПолеМеркиМоего: View {
    let мерка: МеркаМоего
    let продавцы: Bool
    @Binding var значение: Double?
    @State private var как = false

    init(мерка: МеркаМоего, продавцы: Bool, значение: Binding<Double?>) {
        self.мерка = мерка
        self.продавцы = продавцы
        _значение = значение
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(мерка.название)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
                Button {
                    как = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.акцент)
                        .frame(minWidth: 28, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(т("mb_how") + ": " + мерка.название)
                .popover(isPresented: $как) {
                    Text(мерка.как)
                        .font(.subheadline)
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: 280)
                        .presentationCompactAdaptation(.popover)
                }
            }
            if продавцы {
                Label(т("mb_seller_keys"), systemImage: "tag.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
            }
            ПолеЧислаМоего(заголовок: мерка.название, единица: т("mb_cm"), значение: $значение, пределы: мерка.пределы,
                           знаков: 1,
                           подсказка: String(format: т("mb_m_range"), String(мерка.обычно.0), String(мерка.обычно.1)),
                           показатьЗаголовок: false)
        }
    }
}
