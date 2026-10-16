import SwiftUI

/**
 ВЫБОР ПОД ЖИВЫМ ДИСКОМ (владелец 16.10.2026: «по-любому есть стандарты колёс = выбор по ним»).

 Лента частей (ЛентаЧастейКолеса) — части пилюлями со значениями, как подпись к рисунку. Панель выбранной части
 (ПанельКолеса) — чипы стандартов (WheelStandards.swift): частые первыми, «Ещё ›» раскрывает все:
   · шина — «Популярные для R16» и три ряда «ширина / профиль / R»; пока выбрано не всё — подсказка, чего не хватает;
   · обод — диаметр R (грузовые R17.5, R19.5, R22.5 — в «Ещё») и ширина J с подсказкой, какой обод обычно под шину; у
     машины другой R подбирает шину того же внешнего диаметра (СтандартыКолёс.шинаПодДиаметр) — с плашкой, что сменилось;
   · болты — разболтовки PCD, раскрытые — по числу болтов;
   · центр — DIA: сначала обычные для выбранной PCD, потом все;
   · вылет — регулятор с шагом 1 и чипы частых (35…50); у машины — ещё и пределы «от / до».
 Внизу — «Ввести вручную»: прежнее поле экрана, запасной путь для любого числа. Редкое значение — «проверьте», но не
 запрет. Каждый выбор — щелчок ОткликСайта.выбор.
 */

// MARK: - Лента частей

/// Части колеса пилюлями со значениями. Касание — как по части на рисунке; VoiceOver их не читает (те же кнопки — на
/// самом диске).
struct ЛентаЧастейКолеса: View {
    let части: [ЧастьКолеса]
    let значения: ЗначенияКолеса
    let черновик: ЧерновикШины
    let выбрана: ЧастьКолеса
    let выбрать: (ЧастьКолеса) -> Void

    init(части: [ЧастьКолеса], значения: ЗначенияКолеса, черновик: ЧерновикШины, выбрана: ЧастьКолеса,
         выбрать: @escaping (ЧастьКолеса) -> Void) {
        self.части = части
        self.значения = значения
        self.черновик = черновик
        self.выбрана = выбрана
        self.выбрать = выбрать
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(части) { часть in
                    пилюля(часть)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
        }
        .accessibilityHidden(true)
    }

    private func пилюля(_ часть: ЧастьКолеса) -> some View {
        let выбрано = часть == выбрана
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            выбрать(часть)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(часть.коротко)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .opacity(0.75)
                Text(часть.значение(значения, черновик: черновик) ?? "—")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .foregroundStyle(выбрано ? Color.white : Theme.текст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(выбрано ? Theme.зелёный : Theme.поверхность2, in: форма)
            .overlay { форма.strokeBorder(выбрано ? Theme.зелёный : Theme.линия, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
    }
}

// MARK: - Чип и ряд

/// Чип значения стандарта: выбранный — зелёный с белым, «Ещё ›» — акцентом без рамки.
struct ЧипЗначенияКолеса: View {
    let текст: String
    let выбран: Bool
    var ссылка = false
    let действие: () -> Void

    init(_ текст: String, выбран: Bool, ссылка: Bool = false, действие: @escaping () -> Void) {
        self.текст = текст
        self.выбран = выбран
        self.ссылка = ссылка
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(выбран ? Color.white : (ссылка ? Theme.акцент : Theme.текст))
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background(выбран ? Theme.зелёный : (ссылка ? Theme.оттенокАкцента : Theme.поверхность2), in: Capsule())
                .overlay { Capsule().strokeBorder(выбран ? Theme.зелёный : (ссылка ? .clear : Theme.линия), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.94))
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Ряд чисел стандарта одной строкой с прокруткой: частые (и выбранное, если оно не из них), «Ещё ›» — все. Выбранное
/// при появлении прокручивается к середине.
struct РядЗначенийКолеса: View {
    let заголовок: String
    let все: [Double]
    let частые: [Double]
    let выбрано: Double?
    let формат: (Double) -> String
    @Binding var раскрыт: Bool
    let выбрать: (Double) -> Void

    init(заголовок: String, все: [Double], частые: [Double], выбрано: Double?, раскрыт: Binding<Bool>,
         формат: @escaping (Double) -> String, выбрать: @escaping (Double) -> Void) {
        self.заголовок = заголовок
        self.все = все
        self.частые = частые
        self.выбрано = выбрано
        _раскрыт = раскрыт
        self.формат = формат
        self.выбрать = выбрать
    }

    private func то(_ x: Double) -> Bool {
        guard let выбрано else { return false }
        return abs(x - выбрано) < 0.001
    }

    /// Что видно: частые или все, и выбранное — всегда (даже набранное вручную вне стандарта).
    private var видимые: [Double] {
        var список = раскрыт ? все : частые
        if let выбрано, !список.contains(where: { abs($0 - выбрано) < 0.001 }) {
            список.append(выбрано)
            список.sort()
        }
        return список
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { прокрутка in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(видимые, id: \.self) { x in
                            ЧипЗначенияКолеса(формат(x), выбран: то(x)) { выбрать(x) }
                                .id(x)
                        }
                        ЧипЗначенияКолеса(КолёсаText.т(раскрыт ? "wh_less" : "wh_more"), выбран: false, ссылка: true) {
                            ОткликСайта.выбор()
                            раскрыт.toggle()
                        }
                    }
                    .padding(.vertical, 1)
                    .padding(.horizontal, 1)
                }
                .onAppear { кВыбранному(прокрутка) }
                .onChange(of: раскрыт) { _, _ in кВыбранному(прокрутка) }
            }
        }
    }

    private func кВыбранному(_ прокрутка: ScrollViewProxy) {
        guard let выбрано, let x = видимые.first(where: { abs($0 - выбрано) < 0.001 }) else { return }
        прокрутка.scrollTo(x, anchor: .center)
    }
}

/// Вылет: «−», крупное число, «+» — шаг 1 мм; для VoiceOver — регулируемый элемент. Пусто — первое касание ставит 40.
struct РегуляторВылетаКолеса: View {
    let подпись: String
    let значение: Double?
    let задать: (Double) -> Void

    init(подпись: String, значение: Double?, задать: @escaping (Double) -> Void) {
        self.подпись = подпись
        self.значение = значение
        self.задать = задать
    }

    /// Пределы шага: стандарт −20…+60, а набранное вручную за ними (до −65…+80) — не обрезается.
    private var пределы: ClosedRange<Double> {
        let низ = max(-65, min(СтандартыКолёс.вылеты.lowerBound, значение ?? 0))
        let верх = min(80, max(СтандартыКолёс.вылеты.upperBound, значение ?? 0))
        return низ...верх
    }

    private func шаг(_ на: Double) {
        guard let значение else {
            задать(40)
            return
        }
        let новое = min(пределы.upperBound, max(пределы.lowerBound, значение.rounded() + на))
        if новое != значение { задать(новое) }
    }

    var body: some View {
        HStack(spacing: 14) {
            кнопка("minus") { шаг(-1) }
            VStack(spacing: 0) {
                Text(подпись)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                Text(значение.map { ЧислаАвтоподбора.ч($0) } ?? "—")
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(значение == nil ? Theme.текстВторой : Theme.текст)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(minWidth: 84)
            кнопка("plus") { шаг(1) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись)
        .accessibilityValue(значение.map { "ET" + ЧислаАвтоподбора.ч($0) } ?? КолёсаText.т("wh_unset"))
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: шаг(1)
            case .decrement: шаг(-1)
            @unknown default: break
            }
        }
    }

    private func кнопка(_ значок: String, _ действие: @escaping () -> Void) -> some View {
        Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            Image(systemName: значок)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 52, height: 52)
                .background(Theme.оттенокАкцента, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
    }
}

// MARK: - Панель части

/// Выбор выбранной части: шапка со значением и «Стереть», подсказка, чипы стандартов, замечания и «Ввести вручную».
struct ПанельКолеса<Ручной: View>: View {
    let часть: ЧастьКолеса
    /// Снимок значений на этот кадр: экран разбирает свои строки один раз, а не на каждый чип.
    let значения: ЗначенияКолеса
    @Binding var черновик: ЧерновикШины
    let состав: СоставКолеса
    let задать: (ЗначенияКолеса) -> Void
    let ручной: Ручной
    @State private var раскрыто: Set<String> = []
    @State private var вручную = false
    @State private var подбор: ПодборШиныКолеса? = nil

    init(часть: ЧастьКолеса, значения: ЗначенияКолеса, черновик: Binding<ЧерновикШины>, состав: СоставКолеса,
         задать: @escaping (ЗначенияКолеса) -> Void, @ViewBuilder ручной: () -> Ручной) {
        self.часть = часть
        self.значения = значения
        _черновик = черновик
        self.состав = состав
        self.задать = задать
        self.ручной = ручной()
    }

    private func т(_ ключ: String) -> String { КолёсаText.т(ключ) }
    private func ч(_ x: Double) -> String { ЧислаАвтоподбора.ч(x, знаков: 2) }

    private var трио: ЧерновикШины { значения.трио(черновик) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            шапка
            Text(т(подсказкаКлюч))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            содержимое
            замечания
            ручнойВвод
        }
        .карточкаАвтоподбора()
    }

    private var подсказкаКлюч: String {
        switch часть {
        case .шина: return "wh_hint_tire"
        case .обод: return состав.ширинаJ ? "wh_hint_rim" : "wh_hint_rim_r"
        case .болты: return "wh_hint_pcd"
        case .центр: return "wh_hint_dia"
        case .вылет: return "wh_hint_et"
        }
    }

    private var шапка: some View {
        let значение = часть.значение(значения, черновик: черновик)
        return HStack(alignment: .center, spacing: 10) {
            Image(systemName: часть.значок)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(часть.название)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                Text(значение ?? т("wh_unset"))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(значение == nil ? Theme.текстВторой : Theme.акцент)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if можноСтереть(значение) {
                Button {
                    стереть()
                } label: {
                    Label(т("wh_clear"), systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("wh_clear") + ": " + часть.название)
            }
        }
    }

    /// «Стереть» — когда есть что стирать у самой части (R обода у машины без своего диаметра — это R шины).
    private func можноСтереть(_ значение: String?) -> Bool {
        guard значение != nil else { return false }
        if часть == .обод { return значения.диаметр != nil || значения.ширинаJ != nil }
        return true
    }

    @ViewBuilder
    private var содержимое: some View {
        switch часть {
        case .шина: панельШины
        case .обод: панельОбода
        case .болты: панельPCD
        case .центр: панельDIA
        case .вылет: панельET
        }
    }

    private func раскрыт(_ ключ: String) -> Binding<Bool> {
        Binding(get: { раскрыто.contains(ключ) }, set: { да in
            if да { раскрыто.insert(ключ) } else { раскрыто.remove(ключ) }
        })
    }

    // MARK: Шина

    private var панельШины: some View {
        let т3 = трио
        return VStack(alignment: .leading, spacing: 12) {
            if let r = т3.r {
                популярныеШины(r)
            }
            РядЗначенийКолеса(заголовок: т("wh_width"), все: СтандартыКолёс.ширины, частые: СтандартыКолёс.частыеШирины,
                              выбрано: т3.ширина, раскрыт: раскрыт("w"), формат: { ЧислаАвтоподбора.ч($0) }) {
                выбратьШину(ширина: $0)
            }
            РядЗначенийКолеса(заголовок: т("wh_profile"), все: СтандартыКолёс.профили,
                              частые: СтандартыКолёс.частыеПрофили, выбрано: т3.профиль, раскрыт: раскрыт("p"),
                              формат: { ЧислаАвтоподбора.ч($0) }) {
                выбратьШину(профиль: $0)
            }
            РядЗначенийКолеса(заголовок: т("wh_r"), все: (СтандартыКолёс.диаметры + СтандартыКолёс.грузовые).sorted(),
                              частые: СтандартыКолёс.частыеДиаметры, выбрано: т3.r, раскрыт: раскрыт("r"),
                              формат: { "R" + ЧислаАвтоподбора.ч($0) }) {
                выбратьШину(r: $0)
            }
            if let подбор {
                ПлашкаКолеса(текст: текстПодбора(подбор),
                             хорошо: abs(подбор.процент) <= СравнениеШинАвтоподбора.норма + 0.005)
            }
            if т3.полный == nil && !т3.пустой {
                Label(т("wh_tire_more"), systemImage: "hand.point.up.left.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
            }
        }
    }

    private func популярныеШины(_ r: Double) -> some View {
        let список = СтандартыКолёс.популярныеШины(r: r)
        let выбрана = значения.шина
        return VStack(alignment: .leading, spacing: 6) {
            Text(String(format: т("wh_popular_r"), ЧислаАвтоподбора.ч(r)))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityAddTraits(.isHeader)
            ПотокЧипов(зазор: 6) {
                ForEach(список, id: \.self) { размер in
                    ЧипЗначенияКолеса(размер.подпись, выбран: размер == выбрана) {
                        выбратьШину(ширина: размер.ширина, профиль: размер.профиль, r: размер.диаметр)
                    }
                }
            }
        }
    }

    /// Шина по частям: что выбрано — в значения (у экранов со строкой полная шина ляжет в строку, неполная — в
    /// черновик). R шины — это и R диска: у машины другой R для полной шины — как R на ободе (шина того же внешнего
    /// диаметра, с плашкой), а не та же шина на +4 % без слова.
    private func выбратьШину(ширина: Double? = nil, профиль: Double? = nil, r: Double? = nil) {
        if let r, ширина == nil, профиль == nil, состав.подборШины, трио.полный != nil {
            выбратьДиаметр(r)
            return
        }
        подбор = nil
        var новое = трио
        if let ширина { новое.ширина = ширина }
        if let профиль { новое.профиль = профиль }
        if let r { новое.r = r }
        черновик = новое
        изменить { з in
            з.ширинаШины = новое.ширина
            з.профиль = новое.профиль
            з.диаметрШины = новое.r
            if let r, состав.диаметр { з.диаметр = r }
        }
    }

    // MARK: Обод

    private var панельОбода: some View {
        VStack(alignment: .leading, spacing: 12) {
            РядЗначенийКолеса(заголовок: т("wh_r"), все: (СтандартыКолёс.диаметры + СтандартыКолёс.грузовые).sorted(),
                              частые: СтандартыКолёс.частыеДиаметры, выбрано: значения.r ?? черновик.r,
                              раскрыт: раскрыт("rr"), формат: { "R" + ЧислаАвтоподбора.ч($0) }) {
                выбратьДиаметр($0)
            }
            if let подбор {
                ПлашкаКолеса(текст: текстПодбора(подбор),
                             хорошо: abs(подбор.процент) <= СравнениеШинАвтоподбора.норма + 0.005)
            }
            if состав.ширинаJ {
                РядЗначенийКолеса(заголовок: т("wh_j"), все: СтандартыКолёс.шириныОбода,
                                  частые: СтандартыКолёс.частыеШириныОбода, выбрано: значения.ширинаJ,
                                  раскрыт: раскрыт("j"), формат: { ЧислаАвтоподбора.ч($0) + "J" }) { j in
                    изменить { $0.ширинаJ = j }
                }
                if состав.шина, let шина = значения.шина {
                    Label(текстОбодаПодШину(шина), systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(СтандартыКолёс.ободНеДляШины(значения) ? УровеньАвтоподбора.проверить.краска
                                         : Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// «Шина под R17: 225/45 R17 — внешний диаметр +0.4% к прежней».
    private func текстПодбора(_ п: ПодборШиныКолеса) -> String {
        let процент = ЧислаАвтоподбора.соЗнаком(п.процент) + "%"
        return String(format: т("wh_plus_size"), ЧислаАвтоподбора.ч(п.стало.диаметр), п.стало.подпись, процент)
    }

    /// «Под шину 205/55 R16 обычно ставят обод 5.5–7.5J».
    private func текстОбодаПодШину(_ шина: РазмерШиныАвтоподбора) -> String {
        let обычно = СтандартыКолёс.ободДляШины(шина)
        let пределы = ЧислаАвтоподбора.ч(обычно.lowerBound) + "–" + ЧислаАвтоподбора.ч(обычно.upperBound) + "J"
        return String(format: т("wh_rim_for_tire"), шина.подпись, пределы)
    }

    private func выбратьДиаметр(_ r: Double) {
        var з = значения
        var черн = черновик
        let новый = з.сменитьДиаметр(r, состав: состав, черновик: &черн)
        черновик = черн
        подбор = новый
        guard з != значения else { return }
        ОткликСайта.выбор()
        задать(з)
    }

    // MARK: Болты

    private var панельPCD: some View {
        let всё = раскрыто.contains("pcd")
        let частые = Array(СтандартыКолёс.разболтовки.prefix(СтандартыКолёс.частыхРазболтовок))
        return VStack(alignment: .leading, spacing: 10) {
            if всё {
                ForEach(группыPCD, id: \.self) { болтов in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(болтов) + " ×")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.текстВторой)
                        чипыPCD(СтандартыКолёс.разболтовки.filter { $0.отверстий == болтов }
                            .sorted { $0.pcd < $1.pcd }, болтов: болтов)
                    }
                }
            } else {
                чипыPCD(частые)
            }
            ЧипЗначенияКолеса(т(всё ? "wh_less" : "wh_more"), выбран: false, ссылка: true) {
                ОткликСайта.выбор()
                раскрыт("pcd").wrappedValue = !всё
            }
        }
    }

    /// Группы по числу болтов; своя разболтовка с редким числом болтов (7 ×) — своей группой.
    private var группыPCD: [Int] {
        var болтов = Set(СтандартыКолёс.разболтовки.map(\.отверстий))
        if let своя = значения.pcd { болтов.insert(своя.отверстий) }
        return Array(болтов).sorted()
    }

    /// Чипы разболтовок; выбранная не из стандарта — тоже здесь, первой (раскрытые — только в группе своего числа
    /// болтов, а не в каждой).
    private func чипыPCD(_ список: [РазболтовкаАвтоподбора], болтов: Int? = nil) -> some View {
        var видимые = список
        if let своя = значения.pcd, болтов == nil || своя.отверстий == болтов,
           !СтандартыКолёс.разболтовки.contains(where: { $0.совпадает(своя) }) {
            видимые.insert(своя, at: 0)
        }
        return ПотокЧипов(зазор: 6) {
            ForEach(видимые, id: \.self) { р in
                ЧипЗначенияКолеса(р.подпись, выбран: значения.pcd?.совпадает(р) == true) {
                    изменить { $0.pcd = р }
                }
            }
        }
    }

    // MARK: Центр

    private var панельDIA: some View {
        let всё = раскрыто.contains("dia")
        let обычные = значения.pcd.map { СтандартыКолёс.ступицыДля($0) } ?? []
        return VStack(alignment: .leading, spacing: 10) {
            if let pcd = значения.pcd, !обычные.isEmpty {
                Text(String(format: т("wh_dia_for"), pcd.подпись))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                чипыDIA(обычные)
                Text(т("wh_dia_all"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
            }
            чипыDIA(всё ? СтандартыКолёс.ступицы : СтандартыКолёс.частыеСтупицы)
            ЧипЗначенияКолеса(т(всё ? "wh_less" : "wh_more"), выбран: false, ссылка: true) {
                ОткликСайта.выбор()
                раскрыт("dia").wrappedValue = !всё
            }
            Text(т("wh_dia_rings"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func чипыDIA(_ список: [Double]) -> some View {
        var видимые = список
        if let своё = значения.dia, !видимые.contains(where: { abs($0 - своё) < 0.06 }) {
            видимые.append(своё)
            видимые.sort()
        }
        return ПотокЧипов(зазор: 6) {
            ForEach(видимые, id: \.self) { d in
                ЧипЗначенияКолеса(ч(d), выбран: значения.dia.map { abs($0 - d) < 0.06 } == true) {
                    изменить { $0.dia = d }
                }
            }
        }
    }

    // MARK: Вылет

    private var пределыВылета: Bool {
        guard let et = значения.et else { return false }
        return et.upperBound - et.lowerBound > 0.01
    }

    private var панельET: some View {
        let низ = значения.et?.lowerBound
        let верх = значения.et?.upperBound
        return VStack(alignment: .leading, spacing: 12) {
            if пределыВылета {
                HStack(spacing: 8) {
                    РегуляторВылетаКолеса(подпись: т("wh_et_from"), значение: низ) { x in
                        изменить { $0.et = x...max(x, верх ?? x) }
                    }
                    РегуляторВылетаКолеса(подпись: т("wh_et_to"), значение: верх) { x in
                        изменить { $0.et = min(x, низ ?? x)...x }
                    }
                }
            } else {
                РегуляторВылетаКолеса(подпись: "ET", значение: низ) { x in
                    изменить { $0.et = x...x }
                }
            }
            РядЗначенийКолеса(заголовок: т("wh_et_popular"), все: СтандартыКолёс.всеВылеты,
                              частые: СтандартыКолёс.частыеВылеты, выбрано: пределыВылета ? nil : низ,
                              раскрыт: раскрыт("et"), формат: { ЧислаАвтоподбора.ч($0) }) { x in
                изменить { $0.et = x...x }
            }
            if состав.диапазонET {
                ЧипЗначенияКолеса(т(пределыВылета ? "wh_et_single" : "wh_et_range"), выбран: false, ссылка: true) {
                    переключитьПределы()
                }
            }
        }
    }

    /// Пределы «от / до» (штатный вылет машины бывает таким) ↔ одно число — середина.
    private func переключитьПределы() {
        guard let et = значения.et else {
            изменить { $0.et = 35...45 }
            return
        }
        if пределыВылета {
            let середина = ((et.lowerBound + et.upperBound) / 2).rounded()
            изменить { $0.et = середина...середина }
        } else {
            let верх = min(80, et.lowerBound + 10)
            изменить { $0.et = et.lowerBound...верх }
        }
    }

    // MARK: Общее

    @ViewBuilder
    private var замечания: some View {
        if СтандартыКолёс.редкое(часть, значения) {
            ПлашкаКолеса(текст: т("wh_rare"), хорошо: false)
        }
        if (часть == .шина || часть == .обод) && состав.шина && состав.диаметр
            && СтандартыКолёс.разныйДиаметр(значения) {
            ПлашкаКолеса(текст: т("wh_r_mismatch"), хорошо: false)
        }
    }

    private var ручнойВвод: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                ОткликСайта.выбор()
                withAnimation(ДвижениеСайта.смена) { вручную.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: вручную ? "chevron.up" : "keyboard")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(т(вручную ? "wh_manual_hide" : "wh_manual"))
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Theme.акцент)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if вручную {
                ручной
                    .transition(.opacity)
            }
        }
    }

    /// Правка значений: одна запись, щелчок — только если что-то поменялось.
    private func изменить(_ правка: (inout ЗначенияКолеса) -> Void) {
        var з = значения
        правка(&з)
        guard з != значения else { return }
        ОткликСайта.выбор()
        задать(з)
    }

    private func стереть() {
        if часть == .шина || часть == .обод { подбор = nil }
        if часть == .шина { черновик = ЧерновикШины() }
        изменить { з in
            switch часть {
            case .шина:
                з.задатьШину(nil)
            case .обод:
                з.диаметр = nil
                з.ширинаJ = nil
            case .болты:
                з.pcd = nil
            case .центр:
                з.dia = nil
            case .вылет:
                з.et = nil
            }
        }
    }
}

// MARK: - Плашка

/// Плашка-замечание: «хорошо» — зелёная с галочкой, иначе — янтарная с треугольником.
struct ПлашкаКолеса: View {
    let текст: String
    let хорошо: Bool

    init(текст: String, хорошо: Bool) {
        self.текст = текст
        self.хорошо = хорошо
    }

    var body: some View {
        let краска = (хорошо ? УровеньАвтоподбора.подходит : УровеньАвтоподбора.проверить).краска
        return Label {
            Text(текст)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: хорошо ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(краска)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(краска.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

/// Над «Сохранить» / «Применить»: набранное вручную не понято, а само поле спрятано под «Ввести вручную» своей части —
/// какая часть и где исправить (иначе кнопка просто серая). Всё понято — ничего.
struct ПлашкаНепонятогоКолеса: View {
    let части: [ЧастьКолеса]

    /// Поля экрана с частью, под которой каждое лежит.
    init(_ поля: [(ЧастьКолеса, ИтогВводаАвтоподбора)]) {
        var итог: [ЧастьКолеса] = []
        for (часть, итогПоля) in поля where итогПоля == .непонятно && !итог.contains(часть) {
            итог.append(часть)
        }
        части = итог
    }

    var body: some View {
        if !части.isEmpty {
            ПлашкаКолеса(текст: String(format: КолёсаText.т("wh_manual_bad"),
                                       части.map { $0.коротко }.joined(separator: ", ")),
                         хорошо: false)
        }
    }
}
