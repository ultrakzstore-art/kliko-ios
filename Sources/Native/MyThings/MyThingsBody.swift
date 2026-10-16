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
     всех систем — из таблиц размеров (ClothingSizes, только вызовы). Детских размеров здесь нет. «Добавить размер» —
     сразу здесь: чипы вида и сетка размеров (БыстрыйРазмерМоего, MyThingsBodyQuickSize.swift).
   · Владелец 16.10.2026: «стандарты ≠ удобства». Вместо восьми пустых полей «— см»:
       — шаблоны (КарточкаШаблоновМоего): по своему размеру — типичные мерки «Подставить» (в пустые, с «≈»; сменился
         размер — «Обновить по размеру»), по фото в полный рост — плечи, рука, шаг. Предложить нечего — карточки нет;
         появилась — стоит до конца захода;
       — живой силуэт (СилуэтМерокМоего): мерки линиями на фигуре, касание — панель мерки ниже (ПанельМеркиМоего):
         линейка-колесо, стандартные значения, «как мерить». Что продавцы указывают у вещей (rules.fit) — с пометкой.
 */
struct ЭкранТелаМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var съёмка = false
    @State private var изГалереи = false
    @State private var спроситьФото = false
    @State private var размер: ЦельРазмераМоего? = nil
    @State private var ключиСхемы: Set<String> = []
    /// «Добавить размер» раскрыт прямо в карточке.
    @State private var быстро = false
    /// Пол фигуры, выбранный чипом; nil — по видам размеров (ТиповыеМеркиМоего.полИз).
    @State private var выбранныйПол: ПолТелаМоего? = nil
    /// Мерка панели под силуэтом.
    @State private var мерка: МеркаМоего = .грудь
    @State private var начато = false
    /// Карточка шаблонов на этом заходе: предложить нечего (КарточкаШаблоновМоего.нужна) — её нет; появилась — стоит до
    /// ухода с экрана, чтобы панель мерки ниже не прыгала, когда мерки заполнились или стёрлись.
    @State private var шаблоныВидны = false

    /// Якорь прокрутки к панели мерки.
    private static let якорьПанели = "body-measure-panel"

    init() {}

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }
    private func м(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        let тело = хранилище.запись.тело
        ScrollViewReader { прокрутка in
            ScrollView {
                VStack(spacing: 14) {
                    карточкаФото(тело.фото)
                    карточкаРоста(тело.рост)
                    карточкаРазмеров(тело)
                    if шаблоныВидны {
                        КарточкаШаблоновМоего(тело: тело, пол: привязкаПола(тело))
                            .transition(.opacity)
                    }
                    карточкаМерок(тело, прокрутка)
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.вставкаСписка, value: тело.размеры)
                .animation(ДвижениеСайта.смена, value: тело.фото)
            }
            .scrollDismissesKeyboard(.interactively)
        }
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
        .onAppear {
            хранилище.подготовить()
            обновитьШаблоны(плавно: false)
        }
        // Шаблоны — по тому, что меняют карточки выше (рост, размеры, фото); мерки панели ниже их не прячут и не зовут.
        .onChange(of: тело.размеры) { _, _ in обновитьШаблоны() }
        .onChange(of: тело.рост) { _, _ in обновитьШаблоны() }
        .onChange(of: тело.фото) { _, _ in обновитьШаблоны() }
        .task {
            /* Ключи замеров вещи из схемы подачи (rules.fit): что продавцы указывают — первым. Только кэш, без сети. */
            let правила = await ЗагрузкаСхемыПодачи.изКэша()?.замеры
            ключиСхемы = Set((правила?.ключи.values.flatMap { $0 }) ?? [])
            // Первая мерка панели — когда ключи схемы уже есть (до них правило «продавцы — раньше» не сработает).
            начать()
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
            if быстро {
                БыстрыйРазмерМоего(тело: тело, пол: привязкаПола(тело), другаяСистема: { вид in
                    размер = ЦельРазмераМоего(вид: вид)
                }, закрыть: {
                    withAnimation(ДвижениеСайта.смена) { быстро = false }
                })
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if тело.размеры.count < ВидРазмераМоего.allCases.count {
                ЗелёнаяКнопкаФото(заголовок: т("mb_add_size"), значок: "plus", контурная: true) {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.смена) { быстро = true }
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

    // MARK: Мерки — силуэт и панель

    /// Пол фигуры: выбранный чипом, иначе по видам размеров; nil — средняя фигура.
    private func полФигуры(_ тело: ТелоМоего) -> ПолТелаМоего? {
        выбранныйПол ?? ТиповыеМеркиМоего.полИз(тело.размеры)
    }

    private func привязкаПола(_ тело: ТелоМоего) -> Binding<ПолТелаМоего?> {
        Binding(get: { выбранныйПол ?? ТиповыеМеркиМоего.полИз(тело.размеры) },
                set: { выбранныйПол = $0 })
    }

    private func карточкаМерок(_ тело: ТелоМоего, _ прокрутка: ScrollViewProxy) -> some View {
        let пол = полФигуры(тело)
        return VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mb_measures"), значок: "ruler")
            Text(т("mb_fig_hint"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text(т("mb_figure"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ЧипМоего(т("mb_women"), выбран: пол == .женский) { сменитьПол(.женский) }
                ЧипМоего(т("mb_men"), выбран: пол == .мужской) { сменитьПол(.мужской) }
                Spacer(minLength: 0)
            }
            СилуэтМерокМоего(тело: тело, пол: пол, выбрана: мерка) { м in
                выбрать(м, прокрутка)
            }
            ПанельМеркиМоего(мерка: мерка, тело: тело, пол: пол, продавцы: ключиСхемы.contains(мерка.ключСхемы)) { шаг in
                листать(шаг)
            }
            .id(Self.якорьПанели)
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: мерка)
    }

    /// Показать шаблоны, если им есть что предложить; убирает их только новый заход на экран. При входе — без анимации.
    private func обновитьШаблоны(плавно: Bool = true) {
        guard !шаблоныВидны else { return }
        let сейчас = хранилище.запись.тело
        guard КарточкаШаблоновМоего.нужна(сейчас, пол: полФигуры(сейчас)) else { return }
        if плавно {
            withAnimation(ДвижениеСайта.смена) { шаблоныВидны = true }
        } else {
            шаблоныВидны = true
        }
    }

    private func сменитьПол(_ новый: ПолТелаМоего) {
        guard выбранныйПол != новый else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) { выбранныйПол = новый }
    }

    /// Касание зоны силуэта: мерка в панель, панель — в видимую часть (на маленьком экране она ниже фигуры).
    private func выбрать(_ новая: МеркаМоего, _ прокрутка: ScrollViewProxy) {
        начато = true
        if новая != мерка {
            ОткликСайта.выбор()
            withAnimation(ДвижениеСайта.смена) { мерка = новая }
        }
        withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(Self.якорьПанели, anchor: nil) }
    }

    /// «‹ ›» панели — по кругу в порядке фигуры.
    private func листать(_ шаг: Int) {
        let порядок = ГеометрияТелаМоего.порядок
        let н = порядок.firstIndex(of: мерка) ?? 0
        let следующая = порядок[((н + шаг) % порядок.count + порядок.count) % порядок.count]
        начато = true
        withAnimation(ДвижениеСайта.смена) { мерка = следующая }
    }

    /**
     Первый показ (после ключей схемы): панель — на первой пустой мерке по важности для одежды (грудь, талия, бёдра, …,
     голова — порядок МеркаМоего), что продавцы указывают — раньше; всё заполнено — грудь. Человек уже выбрал мерку
     касанием или «‹ ›» — не перебиваем (начато).
     */
    private func начать() {
        guard !начато else { return }
        начато = true
        let тело = хранилище.запись.тело
        let пустые = МеркаМоего.allCases.filter { тело.мерка($0) == nil }
        мерка = пустые.first { ключиСхемы.contains($0.ключСхемы) } ?? пустые.first ?? .грудь
    }
}

/// Цель листа размера: свой вид (правка, «Другая система» быстрого выбора) или nil — лист с выбором вида.
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
