import SwiftUI

/**
 Блок «Размеры — по желанию» на шаге «Характеристики» подачи (и в раскрытых «Характеристиках» короткого пути с камеры),
 правила — PostingDims.swift. Под заголовком — одна строка «зачем» под вид товара (каталог, PostingSizeTemplates.swift),
 потом образцы (БлокОбразцовРазмеров, PostingSizeView.swift: «Что это?» и ряд типичных размеров или диагоналей), рисунок
 коробки со стрелками Ш/В/Г (стрелка поля в фокусе — акцентом, рядом — введённое число), три поля с цифровой клавиатурой
 (при крупном шрифте — столбиком), строка ошибки (только если размеры потребовал сервер), пометка «типичный размер»,
 «предложил Kliko AI» или «нашли в объявлении», «не хватает — без всех трёх не уйдут», кнопка «Это миллиметры —
 перевести в см», «где взять» и «Измерить в AR» (линейка «Поместится ли?» в режиме замера вещи: три отрезка — Ш, В, Г —
 сразу в поля; есть, если на устройстве AR, ЛинейкаПодачи). Метка прокрутки блока — ключ ошибки (sp_dims).
 */
struct БлокГабаритовПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ГабаритыПодачиText.т(ключ) }

    /// Поле в фокусе — если это одно из трёх.
    private var выделено: String? {
        guard let ключ = фокус.wrappedValue, ПравилаГабаритовПодачи.ключиФокуса.contains(ключ) else { return nil }
        return ключ
    }

    /// Заголовок и строка под ним: обязательные (потребовал сервер) — как раньше; по желанию — «зачем» вида товара или
    /// общий текст (у настольных вещей — «поставит на стол»).
    private var шапка: (заголовок: String, подпись: String) {
        if модель.обязательныГабариты { return (т("dm_title"), т("dm_sub")) }
        if let зачем = модель.зачемРазмеры { return (т("dm_opt_title"), зачем) }
        return (т("dm_opt_title"), т(ГабаритыВещи.наСтоле(модель.форма.раздел) ? "dm_opt_sub_desk" : "dm_opt_sub"))
    }

    var body: some View {
        let г = модель.габаритыФормы
        let ошибка = модель.ошибка(ПравилаГабаритовПодачи.ключОшибки)
        let ш = шапка
        return КарточкаПодачи(ш.заголовок, подпись: ш.подпись, значок: "cube") {
            БлокОбразцовРазмеров(модель: модель, фокус: фокус)
            РисунокКоробкиГабаритов(габариты: г, выделено: выделено)
            VStack(alignment: .leading, spacing: 8) {
                ПодписьПоля(т("dm_sizes"), обязательно: модель.обязательныГабариты, мелкая: true)
                поля(г, ошибка: ошибка != nil)
                СтрокаОшибки(ошибка)
            }
            пометки(г)
            подсказки
            if ЛинейкаПодачи.есть {
                кнопкаЛинейки
            }
        }
        .id(ПравилаГабаритовПодачи.ключОшибки)
        .onAppear { модель.подсказатьГабаритыИзОписания() }
    }

    // MARK: Поля

    private func поля(_ г: ГабаритыПодачи, ошибка: Bool) -> some View {
        let раскладка = размерТекста.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        let наибольший = модель.рамкиГабаритов.наибольший
        func плохо(_ текст: String) -> Bool {
            if текст.isEmpty { return ошибка }
            guard let число = ПравилаГабаритовПодачи.целое(текст) else { return true }
            return число > наибольший
        }
        return раскладка {
            ПолеГабаритаПодачи(подпись: т("dm_w"), пример: "60", текст: связь(\.ширина), фокус: фокус,
                               ключ: ПравилаГабаритовПодачи.ключиФокуса[0], ошибка: плохо(г.ширина))
            ПолеГабаритаПодачи(подпись: т("dm_h"), пример: "85", текст: связь(\.высота), фокус: фокус,
                               ключ: ПравилаГабаритовПодачи.ключиФокуса[1], ошибка: плохо(г.высота))
            ПолеГабаритаПодачи(подпись: т("dm_d"), пример: "55", текст: связь(\.глубина), фокус: фокус,
                               ключ: ПравилаГабаритовПодачи.ключиФокуса[2], ошибка: плохо(г.глубина))
        }
    }

    /// Только цифры (арабские и прочие — по значению), до 4 знаков; правка руками снимает пометку «предложение».
    private func связь(_ путь: WritableKeyPath<ГабаритыПодачи, String>) -> Binding<String> {
        let м = модель
        return Binding(get: { м.форма.габариты?[keyPath: путь] ?? "" }, set: { новое in
            let чистое = ПодачаМодель.цифры(новое, предел: 4)
            /* Пустое в нетронутый блок — не правка: подсказка из описания ещё может прийти. */
            if м.форма.габариты == nil && чистое.isEmpty { return }
            var г = м.форма.габариты ?? ГабаритыПодачи()
            if г[keyPath: путь] != чистое { г.источник = "" }
            г[keyPath: путь] = чистое
            м.форма.габариты = г
        })
    }

    // MARK: Пометки и подсказки

    @ViewBuilder
    private func пометки(_ г: ГабаритыПодачи) -> some View {
        if !г.пусто && г.источник == "tpl" {
            ЗаметкаПодачи(т("dm_tpl_note"), тон: .внимание, значок: "ruler")
        } else if !г.пусто && г.источник == "ai" {
            ЗаметкаПодачи(т("dm_ai"), тон: .внимание, значок: "sparkles")
        } else if !г.пусто && г.источник == "desc" {
            ЗаметкаПодачи(т("dm_found"), тон: .внимание, значок: "text.magnifyingglass")
        }
        /* По желанию — не ошибка, но неполные размеры в объявление не уйдут: скажем, чего не хватает. */
        if !модель.обязательныГабариты && !г.пусто && г.полные == nil && !модель.габаритыКрупнее {
            let нет = недостающие(г)
            ЗаметкаПодачи(нет.isEmpty ? т("dm_bad") : String(format: т("dm_opt_partial"), нет), тон: .серый,
                          значок: "info.circle")
        }
        if модель.габаритыКрупнее {
            Button {
                фокус.wrappedValue = nil
                модель.габаритыВСантиметры()
            } label: {
                Label(т("dm_mm_fix"), systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(КраскаПодачи.вниманиеТекст)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(КраскаПодачи.вниманиеФон,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(КраскаПодачи.вниманиеКромка, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if модель.габаритыМельче {
            ЗаметкаПодачи(т("dm_small"), тон: .внимание, значок: "exclamationmark.triangle")
        }
    }

    /// Пустые поля строчными через запятую («высота, глубина»); пустых нет — пусто.
    private func недостающие(_ г: ГабаритыПодачи) -> String {
        [("dm_w", г.ширина), ("dm_h", г.высота), ("dm_d", г.глубина)]
            .filter { $0.1.isEmpty }
            .map { т($0.0).lowercased() }
            .joined(separator: ", ")
    }

    private var подсказки: some View {
        let раздел = модель.форма.раздел
        func внутри(_ ключи: Set<String>) -> Bool {
            модель.справочники.внутри(раздел, ключи) || РазделыСайта.внутри(раздел, ключи)
        }
        return VStack(alignment: .leading, spacing: 6) {
            if внутри(["carpets"]) { строкаПодсказки(т("dm_carpet"), значок: "square.split.diagonal") }
            if внутри(["tv", "monitors"]) { строкаПодсказки(т("dm_screen"), значок: "tv") }
            строкаПодсказки(т("dm_where"), значок: "info.circle")
        }
    }

    private func строкаПодсказки(_ текст: String, значок: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: значок)
                .font(.footnote)
                .accessibilityHidden(true)
            Text(текст)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.текстВторой)
    }

    /// «Измерить в AR»: линейка в режиме замера вещи; «Готово» там — значения в поля (что не мерили — как было).
    private var кнопкаЛинейки: some View {
        Button {
            фокус.wrappedValue = nil
            let м = модель
            ЛинейкаПодачи.открыть(название: м.форма.название) { ширина, высота, глубина in
                Task { @MainActor in м.принятьЗамерГабаритов(ширина: ширина, высота: высота, глубина: глубина) }
            }
        } label: {
            Label(т("dm_measure"), systemImage: "ruler")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Поле

/// Одно поле габарита: подпись сверху (в фокусе — акцентом), число цифровой клавиатурой и «см» справа.
struct ПолеГабаритаПодачи: View {
    let подпись: String
    let пример: String
    @Binding var текст: String
    let фокус: FocusState<String?>.Binding
    let ключ: String
    let ошибка: Bool

    init(подпись: String, пример: String, текст: Binding<String>, фокус: FocusState<String?>.Binding, ключ: String,
         ошибка: Bool) {
        self.подпись = подпись
        self.пример = пример
        self._текст = текст
        self.фокус = фокус
        self.ключ = ключ
        self.ошибка = ошибка
    }

    var body: some View {
        let выбрано = фокус.wrappedValue == ключ
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return VStack(alignment: .leading, spacing: 4) {
            Text(подпись)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(выбрано ? Theme.акцент : Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityHidden(true)
            HStack(spacing: 4) {
                TextField(пример, text: $текст)
                    .keyboardType(.numberPad)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(КраскаПодачи.текст)
                    .modifier(ФокусПоля(фокус: фокус, ключ: ключ))
                    .accessibilityLabel(подпись + ", " + ГабаритыПодачиText.т("dm_in_cm"))
                Text(ГабаритыПодачиText.т("dm_cm"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(КраскаПодачи.поле, in: форма)
            .overlay {
                форма.strokeBorder(ошибка ? Theme.ценаСкидка : (выбрано ? Theme.акцент : КраскаПодачи.линия),
                                   lineWidth: ошибка || выбрано ? 2 : 1)
            }
            .contentShape(форма)
            .onTapGesture { фокус.wrappedValue = ключ }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Рисунок

/**
 Коробка в лёгкой перспективе и три стрелки: ширина — под лицевой стороной, высота — слева, глубина — вдоль нижнего
 правого ребра. Подпись стрелки — буква и введённое число. Стрелка поля в фокусе — акцентом и толще. Рисунок, не текст:
 в RTL не зеркалится, для VoiceOver скрыт (подписи есть у полей).
 */
struct РисунокКоробкиГабаритов: View {
    let габариты: ГабаритыПодачи
    let выделено: String?

    init(габариты: ГабаритыПодачи, выделено: String?) {
        self.габариты = габариты
        self.выделено = выделено
    }

    var body: some View {
        let т = ГабаритыПодачиText.т
        let подписи = (ш: подпись(т("dm_w_s"), габариты.ширина),
                       в: подпись(т("dm_h_s"), габариты.высота),
                       г: подпись(т("dm_d_s"), габариты.глубина))
        let ключи = ПравилаГабаритовПодачи.ключиФокуса
        return Canvas { холст, место in
            /* Поля под подписи стрелок: слева — высота, справа — глубина (арабские слова длиннее букв). */
            let слева: CGFloat = 74
            let справа: CGFloat = 78
            let сверху: CGFloat = 6
            let снизу: CGFloat = 28
            let ширинаПоля = max(40, место.width - слева - справа)
            let высотаПоля = max(40, место.height - сверху - снизу)
            let вбок = ширинаПоля * 0.3
            let вверх = высотаПоля * 0.26
            let лицо = CGRect(x: слева, y: сверху + вверх, width: ширинаПоля - вбок, height: высотаПоля - вверх)

            var верх = Path()
            верх.move(to: CGPoint(x: лицо.minX, y: лицо.minY))
            верх.addLine(to: CGPoint(x: лицо.minX + вбок, y: лицо.minY - вверх))
            верх.addLine(to: CGPoint(x: лицо.maxX + вбок, y: лицо.minY - вверх))
            верх.addLine(to: CGPoint(x: лицо.maxX, y: лицо.minY))
            верх.closeSubpath()
            var бок = Path()
            бок.move(to: CGPoint(x: лицо.maxX, y: лицо.minY))
            бок.addLine(to: CGPoint(x: лицо.maxX + вбок, y: лицо.minY - вверх))
            бок.addLine(to: CGPoint(x: лицо.maxX + вбок, y: лицо.maxY - вверх))
            бок.addLine(to: CGPoint(x: лицо.maxX, y: лицо.maxY))
            бок.closeSubpath()
            let перед = Path(лицо)
            холст.fill(верх, with: .color(КраскаПодачи.поле))
            холст.fill(бок, with: .color(КраскаПодачи.хорошоФон.opacity(0.6)))
            холст.fill(перед, with: .color(КраскаПодачи.хорошоФон))
            let кромка = GraphicsContext.Shading.color(КраскаПодачи.хорошоТекст.opacity(0.55))
            for путь in [верх, бок, перед] {
                холст.stroke(путь, with: кромка, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }

            /* Копия контекста рисует туда же: вложенной функции не нужно держать inout-параметр. */
            let кисть = холст
            func стрелка(_ откуда: CGPoint, _ куда: CGPoint, ключ: String, подпись: String, у точка: CGPoint,
                         якорь: UnitPoint) {
                let своя = выделено == ключ
                let цвет = своя ? Theme.акцент : Theme.текстВторой
                let угол = atan2(куда.y - откуда.y, куда.x - откуда.x)
                let длина: CGFloat = 6
                var линия = Path()
                линия.move(to: откуда)
                линия.addLine(to: куда)
                for (конец, поворот) in [(куда, угол), (откуда, угол + CGFloat.pi)] {
                    линия.move(to: CGPoint(x: конец.x - длина * cos(поворот - 0.45),
                                           y: конец.y - длина * sin(поворот - 0.45)))
                    линия.addLine(to: конец)
                    линия.addLine(to: CGPoint(x: конец.x - длина * cos(поворот + 0.45),
                                              y: конец.y - длина * sin(поворот + 0.45)))
                }
                кисть.stroke(линия, with: .color(цвет),
                             style: StrokeStyle(lineWidth: своя ? 2.4 : 1.4, lineCap: .round, lineJoin: .round))
                кисть.draw(Text(подпись)
                            .font(.caption.weight(своя ? .heavy : .semibold).monospacedDigit())
                            .foregroundStyle(цвет),
                           at: точка, anchor: якорь)
            }

            let низ = лицо.maxY + 9
            стрелка(CGPoint(x: лицо.minX, y: низ), CGPoint(x: лицо.maxX, y: низ), ключ: ключи[0], подпись: подписи.ш,
                    у: CGPoint(x: лицо.midX, y: низ + 4), якорь: .top)
            let левее = лицо.minX - 9
            стрелка(CGPoint(x: левее, y: лицо.minY), CGPoint(x: левее, y: лицо.maxY), ключ: ключи[1],
                    подпись: подписи.в, у: CGPoint(x: левее - 5, y: лицо.midY), якорь: .trailing)
            let начало = CGPoint(x: лицо.maxX + 8, y: лицо.maxY + 3)
            let конец = CGPoint(x: лицо.maxX + вбок + 8, y: лицо.maxY - вверх + 3)
            стрелка(начало, конец, ключ: ключи[2], подпись: подписи.г,
                    у: CGPoint(x: (начало.x + конец.x) / 2 + 9, y: (начало.y + конец.y) / 2 + 4), якорь: .leading)
        }
        .frame(maxWidth: 320)
        .frame(height: 132)
        .frame(maxWidth: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// «Ш 60» — буква и число; числа нет — одна буква.
    private func подпись(_ буква: String, _ число: String) -> String {
        число.isEmpty ? буква : буква + " " + число
    }
}
