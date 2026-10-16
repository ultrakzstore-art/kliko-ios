import SwiftUI
import UIKit

/**
 «ПОМЕСТИТСЯ ЛИ?» — ГОТОВЫЕ РАЗМЕРЫ (владелец 16.10.2026, скрин TestFlight 1.12 (77): лист «Укажите размеры» с нулями в
 полях и пустотой под ними — «вот тут нужен тот самый шаблон — ноутбук или другая вещь; если это ноутбук, то снизу как
 раз пусто — там выбрать размер, или так же другой вещи — когда не указаны размеры»).

 Размеров в объявлении нет, нашлись не все три или они — прикидка по диагонали (РазборГабаритов, FitBoxSize.swift) — под
 полями листа размеров (ЛистРазмеровГабаритов, FitBoxSheets.swift) блок «Готовые размеры» из каталога шаблонов подачи
 (КаталогРазмеров, Posting/PostingSizeTemplates.swift; схему сайта подача держит только в своей модели — здесь
 встроенный каталог):
   · вид вещи — сам, по разделу и словам названия (КаталогРазмеров.вид); раздел не из каталога — по словам названия
     среди всех видов; не поняли — «Не поняли, что это за вещь» и виды раздела кнопками;
   · ровная сетка образцов вида: «15,6″» и под ней мелко «36 × 2 × 24 см» (колонки одной ширины, чипы одной высоты,
     появляются лесенкой); касание — Ш×В×Г в поля (числа перекатываются), клавиатура убирается, под полями — честное
     «Типичные размеры для «Ноутбук 15,6″» — у конкретной модели бывает на 1–2 см иначе»; ручная правка поля снимает
     выбор;
   · диагональ или размер образца в названии («15.6», «27"», «55 дюймов», «160х200») — этот образец выбран сразу (только
     когда полей нечем было заполнить или там прикидка по диагонали: найденное в объявлении не подменяем);
   · «Другая вещь ›» — список видов каталога с поиском (ВыборВидаГабаритов), выбор вида показывает его образцы.
 Выбранный образец уходит в окно пометкой «примерно» (МодельГабаритов.примерно): под затвором — «Размер примерный —
 типичный для …». Шины и диски — не здесь: у них не Ш×В×Г. VoiceOver: чип — «15,6 дюйма, 36 на 2 на 24 сантиметра».
 Тексты — ГотовыеРазмерыText (FitBoxTemplatesText.swift), имена видов и образцов — РазмерыОбразцовText подачи.
 */
enum ГотовыеРазмеры {
    /// Виды, которые меряются Ш×В×Г — коробкой или через диагональ (у шин и дисков свои числа); шаблоны выключены
    /// (Config.шаблоныРазмеров) — пусто.
    static var виды: [ВидРазмеров] {
        guard Config.шаблоныРазмеров else { return [] }
        return КаталогРазмеров.все(nil).filter { $0.мера == .коробка || $0.мера == .диагональ }
    }

    /// Блок нужен: размеров в объявлении нет или не все три, или они — прикидка по диагонали.
    static func нужны(_ найдено: НайденныеГабариты) -> Bool {
        guard Config.шаблоныРазмеров else { return false }
        return найдено.полные == nil || прикидка(найдено)
    }

    /// Размеры — прикидка по диагонали экрана (FitBoxSize.swift), а не из объявления.
    static func прикидка(_ найдено: НайденныеГабариты) -> Bool {
        if case .диагональ = найдено.источник { return true }
        return false
    }

    /// Раздел или его предок — один из ключей (снимок дерева сайта).
    private static func внутри(_ раздел: String, _ ключи: Set<String>) -> Bool {
        РазделыСайта.внутри(раздел, ключи)
    }

    /**
     Вид вещи: по разделу и названию (КаталогРазмеров.вид). У раздела видов нет вовсе (раздел не из каталога) — по
     словам названия среди всех видов: больше совпавших слов, при равенстве — слово раньше в названии, потом порядок
     каталога. nil — не понять (тогда виды раздела кнопками и «Другая вещь»).
     */
    static func вид(раздел: String?, название: String, виды: [ВидРазмеров]) -> ВидРазмеров? {
        guard !виды.isEmpty else { return nil }
        if let раздел, !раздел.isEmpty {
            if let свой = КаталогРазмеров.вид(раздел: раздел, название: название, виды: виды, внутри: внутри) {
                return свой
            }
            let к = КаталогРазмеров.кандидаты(раздел: раздел, виды: виды, внутри: внутри)
            if !к.прямые.isEmpty || !к.через.isEmpty { return nil }
        }
        let текст = КаталогРазмеров.нормально(название)
        guard !текст.isEmpty else { return nil }
        var лучший: (вид: ВидРазмеров, сколько: Int, первое: Int)? = nil
        for вид in виды {
            let с = КаталогРазмеров.совпадения(вид, в: текст)
            guard с.сколько > 0 else { continue }
            if let л = лучший, с.сколько < л.сколько || (с.сколько == л.сколько && с.первое >= л.первое) { continue }
            лучший = (вид: вид, сколько: с.сколько, первое: с.первое)
        }
        return лучший?.вид
    }

    /// Виды раздела — кнопками, когда вид не поняли: прямые (раздел назван у вида), иначе через предков; не больше 8.
    static func кандидаты(раздел: String?, виды: [ВидРазмеров]) -> [ВидРазмеров] {
        guard let раздел, !раздел.isEmpty else { return [] }
        let к = КаталогРазмеров.кандидаты(раздел: раздел, виды: виды, внутри: внутри)
        return Array((к.прямые.isEmpty ? к.через : к.прямые).prefix(8))
    }

    /**
     Образец, который выбрать сразу: у диагонального вида — ближайший к диагонали прикидки (допуск 0,35″, как у
     образецПоНазванию); иначе — по названию («15,6"», «55 дюймов», «160х200», «100 л»), у диагонального — и дробное
     число без знака дюйма, ровно как у образца («Ноутбук IdeaPad 3 15.6 i5»). nil — не нашли.
     */
    static func образец(_ вид: ВидРазмеров, название: String, найдено: НайденныеГабариты) -> ОбразецРазмеров? {
        if вид.мера == .диагональ, case .диагональ(let дюймы) = найдено.источник {
            var лучший: (образец: ОбразецРазмеров, разница: Double)? = nil
            for о in вид.образцы {
                guard let д = о.дюймы else { continue }
                let разница = abs(д - дюймы)
                if разница <= 0.35 && разница < (лучший?.разница ?? .infinity) {
                    лучший = (образец: о, разница: разница)
                }
            }
            if let лучший { return лучший.образец }
        }
        if let свой = КаталогРазмеров.образецПоНазванию(вид, название: название) { return свой }
        guard вид.мера == .диагональ else { return nil }
        /* Диагональ без знака дюйма: только дробное число, ровно как у образца (13,3 · 15,6 · 17,3 · 10,5 · 12,9 ·
           6,1…) — целое («16 ГБ», «IdeaPad 3») за диагональ не принимаем. */
        let текст = название.replacingOccurrences(of: ",", with: ".")
        var откуда = текст.startIndex
        while let место = текст.range(of: #"(?<![\d.])\d{1,2}\.\d(?![\d.])"#, options: .regularExpression,
                                      range: откуда..<текст.endIndex) {
            if let д = Double(текст[место]),
               let свой = вид.образцы.first(where: { о in о.дюймы.map { abs($0 - д) < 0.05 } ?? false }) {
                return свой
            }
            откуда = место.upperBound
        }
        return nil
    }

    /// Образец вида, с которым совпадают все три размера; nil — ни один (или поля не заполнены).
    static func совпавший(_ вид: ВидРазмеров?, ширина: Double?, высота: Double?,
                          глубина: Double?) -> ОбразецРазмеров? {
        guard let вид, let ш = ширина, let в = высота, let г = глубина else { return nil }
        return вид.образцы.first { о in
            Double(о.ширина) == ш && Double(о.высота) == в && Double(о.глубина) == г
        }
    }

    /// «15,6″» — диагональ образца с запятой у ru и kk; не диагональ — nil.
    private static func диагональ(_ о: ОбразецРазмеров, вида вид: ВидРазмеров) -> String? {
        guard вид.мера == .диагональ, let д = о.дюймы else { return nil }
        return ГабаритыВещи.число(д) + "″"
    }

    /// Две строки чипа: сверху — «15,6″» (с именем, если есть: «8,3″ · как iPad mini») или имя образца, снизу —
    /// «36 × 2 × 24 см». Ни имени, ни диагонали — сверху размеры, снизу пусто.
    static func подписи(_ о: ОбразецРазмеров, вида вид: ВидРазмеров) -> (верх: String, низ: String) {
        let размеры = о.размеры + " " + ГабаритыText.т("fb_cm")
        let имя = о.имя
        if let экран = диагональ(о, вида: вид) {
            return (имя.isEmpty ? экран : экран + " · " + имя, размеры)
        }
        if !имя.isEmpty { return (имя, размеры) }
        if !о.доп.isEmpty { return (о.доп.replacingOccurrences(of: "\"", with: "″"), размеры) }
        return (размеры, "")
    }

    /// Имя образца для пометки «примерно»: «Ноутбук 15,6″», «Диван, 3-местный»; без имени — вид.
    static func подпись(_ о: ОбразецРазмеров, вида вид: ВидРазмеров) -> String {
        if let экран = диагональ(о, вида: вид) { return вид.заголовок + " " + экран }
        let имя = о.имя
        return имя.isEmpty ? вид.заголовок : вид.заголовок + ", " + имя
    }

    /// Чип для VoiceOver: «15,6 дюйма, 36 на 2 на 24 сантиметра»; с именем — «2-местный, 160 на 85 на 90 сантиметров».
    static func озвучка(_ о: ОбразецРазмеров, вида вид: ВидРазмеров) -> String {
        let размеры = String(format: ГотовыеРазмерыText.т("fbt_a11y_dims"), String(о.ширина), String(о.высота),
                             String(о.глубина), ГотовыеРазмерыText.единица(Double(о.глубина), "fbt_cm"))
        var части: [String] = []
        if вид.мера == .диагональ, let д = о.дюймы {
            части.append(ГабаритыВещи.число(д) + " " + ГотовыеРазмерыText.единица(д, "fbt_in"))
        }
        let имя = о.имя
        if !имя.isEmpty { части.append(имя) }
        части.append(размеры)
        return части.joined(separator: ", ")
    }

    /// Строка под видом в списке «Другая вещь»: первые образцы через точку — «13,3″ · 14″ · 15,6″ · 16″…».
    static func кратко(_ вид: ВидРазмеров) -> String {
        let верхи = вид.образцы.prefix(4).map { подписи($0, вида: вид).верх }
        return верхи.joined(separator: " · ") + (вид.образцы.count > 4 ? "…" : "")
    }

    /// Поиск вида: запрос (уже нормальный) — в заголовке, начало слова вида или имя образца («ipad» → планшет).
    static func подходит(_ вид: ВидРазмеров, запрос: String) -> Bool {
        guard !запрос.isEmpty else { return true }
        if КаталогРазмеров.нормально(вид.заголовок).contains(запрос) { return true }
        let поСловам = вид.слова.contains { исходное in
            let слово = КаталогРазмеров.нормально(исходное)
            return слово == запрос || (слово.count >= 3 && (слово.hasPrefix(запрос) || запрос.hasPrefix(слово)))
        }
        if поСловам { return true }
        return вид.образцы.contains { КаталогРазмеров.нормально($0.имя).contains(запрос) }
    }

    /// Значок вида (SF Symbols iOS 16 и раньше); незнакомый вид сайта — коробка или экран.
    static func значок(_ вид: ВидРазмеров) -> String {
        switch вид.ключ {
        case "sofa", "sofa_corner": return "sofa"
        case "armchair": return "chair.lounge"
        case "bed", "mattress", "crib", "kids_bed": return "bed.double"
        case "wardrobe", "dresser", "kitchen_set": return "cabinet"
        case "wall_unit": return "books.vertical"
        case "tv_stand": return "tv.and.mediabox"
        case "table_dining", "table_desk", "table_coffee": return "table.furniture"
        case "chair", "office_chair": return "chair"
        case "carpet": return "square.grid.3x3"
        case "fridge": return "refrigerator"
        case "washer": return "washer"
        case "dishwasher": return "dishwasher"
        case "stove": return "stove"
        case "oven": return "oven"
        case "microwave": return "microwave"
        case "air_conditioner": return "air.conditioner.horizontal"
        case "water_heater": return "heater.vertical"
        case "tv": return "tv"
        case "monitor": return "display"
        case "laptop": return "laptopcomputer"
        case "tablet": return "ipad"
        case "phone": return "iphone"
        case "desktop": return "desktopcomputer"
        case "console": return "gamecontroller"
        case "soundbar", "speaker": return "hifispeaker"
        case "treadmill": return "figure.run"
        case "exercise_bike": return "figure.indoor.cycle"
        case "bicycle", "bicycle_kids": return "bicycle"
        case "e_scooter": return "scooter"
        case "stroller": return "figure.and.child.holdinghands"
        case "aquarium": return "fish"
        default: return вид.мера == .диагональ ? "tv" : "shippingbox"
        }
    }
}

// MARK: - Блок

/// «Готовые размеры» под полями листа размеров: какая вещь и «Другая вещь ›», сетка образцов вида; вид не поняли —
/// «Не поняли, что это за вещь» и виды раздела кнопками.
struct БлокГотовыхРазмеров: View {
    let вид: ВидРазмеров?
    /// Виды раздела — кнопками, когда вид не поняли.
    let кандидаты: [ВидРазмеров]
    /// Ключ выбранного образца; nil — ни один (поля пусты или введены руками).
    let выбранный: String?
    let выбрать: (ОбразецРазмеров) -> Void
    let выбратьВид: (ВидРазмеров) -> Void
    let другаяВещь: () -> Void
    @Environment(\.dynamicTypeSize) private var размерТекста
    @ScaledMetric(relativeTo: .subheadline) private var ширинаВида: CGFloat = 140

    init(вид: ВидРазмеров?, кандидаты: [ВидРазмеров], выбранный: String?,
         выбрать: @escaping (ОбразецРазмеров) -> Void, выбратьВид: @escaping (ВидРазмеров) -> Void,
         другаяВещь: @escaping () -> Void) {
        self.вид = вид
        self.кандидаты = кандидаты
        self.выбранный = выбранный
        self.выбрать = выбрать
        self.выбратьВид = выбратьВид
        self.другаяВещь = другаяВещь
    }

    private func т(_ ключ: String) -> String { ГотовыеРазмерыText.т(ключ) }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            шапка
            if let вид {
                строкаВида(вид)
                СеткаГотовыхРазмеров(вид: вид, выбранный: выбранный, выбрать: выбрать)
                    .id(вид.ключ)
                    .transition(.opacity)
            } else {
                неПоняли
                if !кандидаты.isEmpty {
                    быстрыеВиды
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        .animation(ДвижениеСайта.смена, value: вид?.ключ)
    }

    private var шапка: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 32, height: 32)
                .background(Theme.оттенокАкцента,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("fbt_title"))
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                /* Вид понят — «Похоже, это — Ноутбук» с образцами объясняют сами; так на iPhone SE образцы видны
                   сразу. */
                if вид == nil {
                    Text(т("fbt_sub"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// «Похоже, это — Ноутбук» и «Другая вещь ›»; крупный текст — одно под другим.
    private func строкаВида(_ вид: ВидРазмеров) -> some View {
        let раскладка = размерТекста.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return раскладка {
            HStack(spacing: 10) {
                ЗначокВидаГабаритов(вид: вид)
                VStack(alignment: .leading, spacing: 1) {
                    Text(т("fbt_kind"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                    Text(вид.заголовок)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            кнопкаДругой
        }
    }

    private var кнопкаДругой: some View {
        Button {
            ОткликСайта.выбор()
            другаяВещь()
        } label: {
            HStack(spacing: 4) {
                Text(т("fbt_other"))
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.оттенокАкцента, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityHint(т("fbt_other_hint"))
    }

    /// Вид не поняли: строка-кнопка к списку видов.
    private var неПоняли: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button {
            ОткликСайта.выбор()
            другаяВещь()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "questionmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 36, height: 36)
                    .background(Theme.оттенокАкцента,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("fbt_unknown"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                    Text(т("fbt_pick"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .background(Theme.фонСтраницы, in: форма)
            .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityHint(т("fbt_other_hint"))
    }

    /// Виды раздела кнопками (их несколько, а по названию не понять).
    private var быстрыеВиды: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: ширинаВида), spacing: 8)], alignment: .leading,
                         spacing: 8) {
            ForEach(кандидаты) { вид in
                Button {
                    ОткликСайта.выбор()
                    выбратьВид(вид)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: ГотовыеРазмеры.значок(вид))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.акцент)
                            .accessibilityHidden(true)
                        Text(вид.заголовок)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.фонСтраницы, in: форма)
                    .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
                    .contentShape(форма)
                }
                .buttonStyle(НажатиеСайта())
            }
        }
    }
}

// MARK: - Сетка образцов

/// Ровная сетка образцов вида: колонки одной ширины, чипы одной высоты; при появлении — лесенкой снизу (при «Уменьшении
/// движения» — сразу). Короткие обе строки («15,6″» и «36 × 2 × 24 см») — по три в ряд на iPhone SE; длинная хоть одна
/// («Кресло-кровать, сложено» или «168 × 103 × 35 см» у телевизора) — по две, иначе размеры обрезались бы; iPad —
/// сколько войдёт.
struct СеткаГотовыхРазмеров: View {
    let вид: ВидРазмеров
    let выбранный: String?
    let выбрать: (ОбразецРазмеров) -> Void
    @State private var видны = false
    @ScaledMetric(relativeTo: .subheadline) private var узкая: CGFloat = 92
    @ScaledMetric(relativeTo: .subheadline) private var широкая: CGFloat = 146

    init(вид: ВидРазмеров, выбранный: String?, выбрать: @escaping (ОбразецРазмеров) -> Void) {
        self.вид = вид
        self.выбранный = выбранный
        self.выбрать = выбрать
    }

    var body: some View {
        let образцы = вид.образцы
        let подписи = образцы.map { ГотовыеРазмеры.подписи($0, вида: вид) }
        let короткие = подписи.allSatisfy { $0.верх.count <= 8 && $0.низ.count <= 14 }
        let колонки = [GridItem(.adaptive(minimum: короткие ? узкая : широкая), spacing: 8, alignment: .top)]
        return LazyVGrid(columns: колонки, alignment: .leading, spacing: 8) {
            ForEach(Array(образцы.enumerated()), id: \.element.id) { номер, образец in
                ЧипГотовогоРазмера(верх: подписи[номер].верх, низ: подписи[номер].низ,
                                   выбран: выбранный == образец.ключ,
                                   озвучка: ГотовыеРазмеры.озвучка(образец, вида: вид)) {
                    выбрать(образец)
                }
                .opacity(видны ? 1 : 0)
                .offset(y: видны ? 0 : 10)
                .animation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.82)
                    .delay(Double(min(номер, 10)) * 0.035)), value: видны)
            }
        }
        .onAppear { видны = true }
    }
}

/// Чип образца: сверху — «15,6″» или имя, под ней мелко — «36 × 2 × 24 см». Выбранный — зелёный с галочкой (как
/// ЧипОбразцаРазмеров подачи); нажатие — лёгкое сжатие сайта.
struct ЧипГотовогоРазмера: View {
    let верх: String
    let низ: String
    let выбран: Bool
    let озвучка: String
    let действие: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var высота: CGFloat = 56

    init(верх: String, низ: String, выбран: Bool, озвучка: String, действие: @escaping () -> Void) {
        self.верх = верх
        self.низ = низ
        self.выбран = выбран
        self.озвучка = озвучка
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button(action: действие) {
            VStack(alignment: .leading, spacing: 2) {
                Text(верх)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(низ.isEmpty ? " " : низ)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .opacity(выбран ? 0.92 : 0.7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(выбран ? Color.white : Theme.текст)
            .padding(.leading, 12)
            .padding(.trailing, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: высота, alignment: .leading)
            .background(выбран ? Theme.зелёный : Theme.фонСтраницы, in: форма)
            .overlay { форма.strokeBorder(выбран ? Theme.зелёный : Theme.линия, lineWidth: 1) }
            .overlay(alignment: .topTrailing) {
                if выбран {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white)
                        .padding(6)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(форма)
            .animation(ДвижениеСайта.выбор, value: выбран)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityLabel(озвучка)
        .accessibilityHint(ГотовыеРазмерыText.т("fbt_chip_hint"))
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// Значок вида в мятном квадрате (строка вида в блоке и список «Другая вещь»).
struct ЗначокВидаГабаритов: View {
    let вид: ВидРазмеров
    @ScaledMetric(relativeTo: .body) private var сторона: CGFloat = 36

    init(вид: ВидРазмеров) {
        self.вид = вид
    }

    var body: some View {
        Image(systemName: ГотовыеРазмеры.значок(вид))
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.акцент)
            .frame(width: сторона, height: сторона)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Другая вещь

/// «Другая вещь ›»: виды каталога с поиском по названию вида, его словам и именам образцов; выбор — назад к листу,
/// там — образцы этого вида.
struct ВыборВидаГабаритов: View {
    let виды: [ВидРазмеров]
    let выбран: String?
    let выбрать: (ВидРазмеров) -> Void
    @State private var поиск = ""

    init(виды: [ВидРазмеров], выбран: String?, выбрать: @escaping (ВидРазмеров) -> Void) {
        self.виды = виды
        self.выбран = выбран
        self.выбрать = выбрать
    }

    private func т(_ ключ: String) -> String { ГотовыеРазмерыText.т(ключ) }

    private var найденные: [ВидРазмеров] {
        let запрос = КаталогРазмеров.нормально(поиск.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !запрос.isEmpty else { return виды }
        return виды.filter { ГотовыеРазмеры.подходит($0, запрос: запрос) }
    }

    var body: some View {
        let список = найденные
        return List {
            if список.isEmpty {
                Text(т("fbt_nothing"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .listRowBackground(Theme.поверхность)
            }
            ForEach(список) { вид in
                Button {
                    ОткликСайта.выбор()
                    выбрать(вид)
                } label: {
                    строка(вид)
                }
                .listRowBackground(Theme.поверхность)
                .accessibilityAddTraits(вид.ключ == выбран ? .isSelected : [])
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always), prompt: т("fbt_search"))
        .autocorrectionDisabled()
        .navigationTitle(т("fbt_picker_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func строка(_ вид: ВидРазмеров) -> some View {
        let кратко = ГотовыеРазмеры.кратко(вид)
        return HStack(spacing: 12) {
            ЗначокВидаГабаритов(вид: вид)
            VStack(alignment: .leading, spacing: 2) {
                Text(вид.заголовок)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                if !кратко.isEmpty {
                    Text(кратко)
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if вид.ключ == выбран {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
