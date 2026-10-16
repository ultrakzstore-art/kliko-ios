import SwiftUI
import UIKit

/**
 «МОЁ» — ПАНЕЛЬ МЕРКИ ПОД СИЛУЭТОМ (владелец 16.10.2026: «стандарты ≠ удобства»).

 Касание зоны на фигуре (MyThingsBodyFigure.swift) открывает здесь её мерку:
   · шапка — «‹ Обхват груди ›» (листать мерки по кругу) и «Обычно 80–120 см»;
   · регулятор — крупное число перекатом, «−» и «+» на шаг и линейка-колесо в пределах мерки: деления прилипают к шагу
     (сантиметр, у стопы — полсантиметра), щелчок под пальцем; записывается, когда палец остановился. Правка руками
     снимает «≈». Старая мерка с дробью (прежнее поле, «92,5») показывается как есть, «+» и «−» — к соседнему делению;
   · «≈ примерно» — «Так и есть» снимает пометку, «Стереть» — мерку; «Продавцы указывают это», если мерка есть в схеме;
   · чипы стандартных значений — до шести ближайших из таблиц (ТиповыеМеркиМоего.стандарты), ставятся с «≈»; у
     обхватов и плеч без пола — «Выберите фигуру выше»;
   · «Как мерить» — строкой, «лентой, не туго» (кроме стопы) и маленькой фигурой с линией этой мерки.
 VoiceOver: регулятор — «Обхват груди, 96 см», жест вверх или вниз меняет на шаг.
 */
struct ПанельМеркиМоего: View {
    let мерка: МеркаМоего
    let тело: ТелоМоего
    let пол: ПолТелаМоего?
    let продавцы: Bool
    let листать: (Int) -> Void

    init(мерка: МеркаМоего, тело: ТелоМоего, пол: ПолТелаМоего?, продавцы: Bool, листать: @escaping (Int) -> Void) {
        self.мерка = мерка
        self.тело = тело
        self.пол = пол
        self.продавцы = продавцы
        self.листать = листать
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    var body: some View {
        let значение = тело.мерка(мерка)
        let примерно = тело.примерная(мерка)
        VStack(alignment: .leading, spacing: 14) {
            шапка
            ЛинейкаМеркиМоего(мерка: мерка, значение: значение, примерно: примерно) { x in
                ЗаписьМерокМоего.задать(мерка, x)
            }
            .id(мерка)
            отметка(значение, примерно)
            стандарты(значение)
            какМерить
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .animation(ДвижениеСайта.смена, value: примерно)
        .animation(ДвижениеСайта.смена, value: значение == nil)
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(spacing: 8) {
            стрелка(-1)
            VStack(spacing: 2) {
                Text(мерка.название)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(String(format: т("mb_m_range"), String(мерка.обычно.0), String(мерка.обычно.1)))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .id(мерка)
            .transition(.opacity)
            стрелка(1)
        }
    }

    private func стрелка(_ на: Int) -> some View {
        Button {
            ОткликСайта.выбор()
            листать(на)
        } label: {
            Image(systemName: на < 0 ? "chevron.backward" : "chevron.forward")
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 44, height: 44)
                .background(Theme.оттенокАкцента, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .accessibilityLabel(т(на < 0 ? "mb_prev" : "mb_next"))
    }

    // MARK: Пометки

    @ViewBuilder
    private func отметка(_ значение: Double?, _ примерно: Bool) -> some View {
        if примерно || продавцы || значение != nil {
            VStack(alignment: .leading, spacing: 8) {
                if примерно {
                    Label {
                        Text(т("mb_approx_hint"))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Text("≈")
                            .font(.subheadline.weight(.heavy))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.оранжевый)
                }
                if продавцы {
                    Label(т("mb_seller_keys"), systemImage: "tag.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
                if значение != nil {
                    ПотокЧипов(зазор: 8) {
                        if примерно {
                            МалаяКнопкаАвтоподбора(заголовок: т("mb_confirm"), значок: "checkmark") {
                                ОткликСайта.успех()
                                ЗаписьМерокМоего.подтвердить(мерка)
                            }
                        }
                        МалаяКнопкаАвтоподбора(заголовок: т("mb_clear"), значок: "eraser") {
                            ОткликСайта.выбор()
                            ЗаписьМерокМоего.задать(мерка, nil)
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: Стандарты

    @ViewBuilder
    private func стандарты(_ значение: Double?) -> some View {
        let все = ТиповыеМеркиМоего.стандарты(мерка, пол: пол, рост: тело.рост)
        if все.isEmpty, пол == nil, [МеркаМоего.грудь, .талия, .бёдра, .плечи].contains(мерка) {
            // Обхваты и плечи по таблицам — только своего пола: сказать, откуда они появятся.
            Text(т("mb_std_need_fig"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        } else if !все.isEmpty {
            let около = значение ?? Double(мерка.обычно.0 + мерка.обычно.1) / 2
            VStack(alignment: .leading, spacing: 8) {
                Text(т("mb_std"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                ПотокЧипов(зазор: 8) {
                    ForEach(ТиповыеМеркиМоего.ближайшие(все, к: около, сколько: 6)) { с in
                        ЧипМоего(с.подпись + " · " + ЧислоМоего.ч(с.значение), выбран: значение == с.значение) {
                            ОткликСайта.выбор()
                            ЗаписьМерокМоего.задатьПримерно(мерка, с.значение)
                        }
                    }
                }
            }
        }
    }

    // MARK: Как мерить

    private var какМерить: some View {
        HStack(alignment: .top, spacing: 12) {
            МалыйСилуэтМеркиМоего(мерка: мерка, пол: пол)
                .frame(width: 36, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(т("mb_how"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                Text(мерка.как)
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                // «Лентой, не туго» — у всех, кроме стопы: её меряют по листу бумаги.
                if мерка != .стопа {
                    Text(т("mb_measures_hint"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Регулятор

/**
 Число и линейка мерки: деления в пределах мерки прилипают к шагу (scrollTargetBehavior .viewAligned), щелчок на
 каждом делении, «−» и «+» — на шаг сразу. Пустая мерка стоит на середине «обычно» серым и не записывается, пока её не
 сдвинули. Записывается, когда палец остановился (0,35 с); ушли с экрана раньше — записывается сразу.
 */
struct ЛинейкаМеркиМоего: View {
    let мерка: МеркаМоего
    let значение: Double?
    let примерно: Bool
    let задать: (Double) -> Void
    @State private var позиция: Int? = nil
    @State private var готов = false
    @State private var задача: Task<Void, Never>? = nil

    private static let шаг: CGFloat = 10

    init(мерка: МеркаМоего, значение: Double?, примерно: Bool, задать: @escaping (Double) -> Void) {
        self.мерка = мерка
        self.значение = значение
        self.примерно = примерно
        self.задать = задать
    }

    /// Делений после нулевого.
    private var последний: Int {
        Int(((мерка.пределы.upperBound - мерка.пределы.lowerBound) / мерка.приращение).rounded())
    }

    private func индекс(_ x: Double) -> Int {
        min(последний, max(0, Int(((x - мерка.пределы.lowerBound) / мерка.приращение).rounded())))
    }

    private func величина(_ н: Int) -> Double { мерка.пределы.lowerBound + Double(н) * мерка.приращение }

    private var начальное: Double { значение ?? Double(мерка.обычно.0 + мерка.обычно.1) / 2 }

    /// Пока линейка стоит у самой мерки — сама мерка: старая запись с дробью (прежнее поле, «92,5», «24,3») не
    /// округляется на глазах; сдвинули — значение деления.
    private var показ: Double {
        if let значение, позиция == nil || позиция == индекс(значение) { return значение }
        return величина(позиция ?? индекс(начальное))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                кнопкаШага(-1)
                число
                кнопкаШага(1)
            }
            линейка
                .frame(height: 56)
        }
        .environment(\.layoutDirection, .leftToRight)
        // Щелчок только на сдвиге: первая установка позиции при появлении (nil → число) молчит.
        .sensoryFeedback(.selection, trigger: позиция) { старое, новое in старое != nil && новое != nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(мерка.название)
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
            // Значение поставили снаружи (чип, подстановка) — линейка доезжает до него; палец двигает — не мешаем.
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
        guard let значение else { return МоёТелоText.т("mb_a11y_empty") }
        let текст = ЧислоМоего.ч(значение) + " " + МоёТелоText.т("mb_cm")
        return примерно ? текст + ", " + МоёТелоText.т("mb_a11y_approx") : текст
    }

    private var число: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if примерно && значение == показ {
                Text("≈")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.текстВторой)
                    .transition(.opacity)
            }
            Text(ЧислоМоего.ч(показ))
                .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(значение == nil ? Theme.текстВторой : Theme.текст)
                .contentTransition(.numericText(value: показ))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(МоёТелоText.т("mb_cm"))
                .font(.title3.weight(.semibold))
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
                HStack(spacing: 0) {
                    ForEach(Array(0...последний), id: \.self) { н in
                        деление(н)
                            .frame(width: Self.шаг, height: 56, alignment: .top)
                            .id(н)
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
                    .frame(width: 3, height: 36)
                    .allowsHitTesting(false)
            }
            .mask {
                LinearGradient(colors: [Color.clear, Color.black, Color.black, Color.clear], startPoint: .leading,
                               endPoint: .trailing)
            }
        }
    }

    /// Деление: крупное с числом — каждые 10 см (у стопы — 5), среднее — 5 см (у стопы — 1).
    private func деление(_ н: Int) -> some View {
        let x = величина(н)
        let крупное: Double = мерка == .стопа ? 5 : 10
        let среднее: Double = мерка == .стопа ? 1 : 5
        let большое = x.truncatingRemainder(dividingBy: крупное) == 0
        let малое = x.truncatingRemainder(dividingBy: среднее) == 0
        return VStack(spacing: 4) {
            Rectangle()
                .fill(большое ? Theme.текст : Theme.текстВторой.opacity(малое ? 0.8 : 0.45))
                .frame(width: большое ? 2 : 1, height: большое ? 28 : (малое ? 20 : 12))
            if большое {
                Text(ЧислоМоего.ч(x))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize()
            }
        }
    }

    private func сдвинуть(_ на: Int) {
        var база = позиция ?? индекс(начальное)
        // Мерка с дробью мимо делений (92,5) и линейка у неё: «+» — на ближайшее деление выше (93), «−» — ниже (92).
        if let значение, значение != величина(индекс(значение)), позиция == nil || позиция == индекс(значение) {
            let доля = (значение - мерка.пределы.lowerBound) / мерка.приращение
            база = Int(доля.rounded(на > 0 ? .down : .up))
        }
        let новый = min(последний, max(0, база + на))
        готов = true
        задача?.cancel()
        задача = nil
        позиция = новый
        let x = величина(новый)
        if x != значение { задать(x) }
    }
}
