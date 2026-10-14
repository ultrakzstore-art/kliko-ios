import SwiftUI

/**
 Образцы размеров в блоке «Размеры — по желанию» (PostingDimsView.swift) и блок «Размер шин или дисков» на шаге
 «Характеристики» в разделе шин и дисков (PostingSteps.swift, режим запчастей). Каталог и правила —
 PostingSizeTemplates.swift и PostingSizeWheels.swift; тексты — PostingSizeText.swift (sz_*, tw_*) и PostingDimsText.swift
 (dm_tpl_*).
 */

// MARK: - Образцы Ш×В×Г

/// «Что это?» (видов у раздела несколько) и ряд образцов вида: касание — Ш×В×Г в поля с пометкой «типичный размер».
struct БлокОбразцовРазмеров: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { ГабаритыПодачиText.т(ключ) }

    var body: some View {
        let кандидаты = модель.кандидатыРазмеров.filter { Self.коробкой($0) }
        let вид = Self.годный(модель.видРазмеров)
        if кандидаты.count > 1 || вид != nil {
            VStack(alignment: .leading, spacing: 12) {
                if кандидаты.count > 1 {
                    выборВида(кандидаты, выбран: вид)
                }
                if let вид, !вид.образцы.isEmpty {
                    образцы(вид)
                }
            }
        }
    }

    /// Вид меряется Ш×В×Г (коробкой или через диагональ) — у шин и дисков свой блок.
    private static func коробкой(_ вид: ВидРазмеров) -> Bool {
        вид.мера == .коробка || вид.мера == .диагональ
    }

    private static func годный(_ вид: ВидРазмеров?) -> ВидРазмеров? {
        guard let вид, коробкой(вид) else { return nil }
        return вид
    }

    private func выборВида(_ кандидаты: [ВидРазмеров], выбран: ВидРазмеров?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("dm_tpl_kind"), мелкая: true)
            ПотокЧипов(зазор: 8) {
                ForEach(кандидаты) { вид in
                    ЧипПодачи(вид.заголовок, выбран: выбран?.ключ == вид.ключ) {
                        фокус.wrappedValue = nil
                        ОткликСайта.выбор()
                        модель.выбратьВидРазмеров(вид.ключ)
                    }
                }
            }
        }
    }

    /// Чипы образцов: у диагонали — «55″» и размеры, у коробки — имя и размеры.
    private func образцы(_ вид: ВидРазмеров) -> some View {
        let выбранный = модель.выбранныйОбразец(вид)
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т(вид.мера == .диагональ ? "dm_tpl_diag" : "dm_tpl_box"), мелкая: true)
            ПотокЧипов(зазор: 8) {
                ForEach(вид.образцы) { образец in
                    let подписи = вид.подписи(образец)
                    ЧипОбразцаРазмеров(верх: подписи.верх, низ: подписи.низ, выбран: выбранный?.id == образец.id,
                                       озвучка: String(format: т("dm_tpl_a11y"), Self.озвучка(подписи))) {
                        фокус.wrappedValue = nil
                        ОткликСайта.выбор()
                        модель.применитьОбразецРазмеров(образец, вида: вид)
                    }
                }
            }
        }
    }

    static func озвучка(_ подписи: (верх: String, низ: String)) -> String {
        подписи.низ.isEmpty ? подписи.верх : подписи.верх + ", " + подписи.низ
    }
}

// MARK: - Чип образца

/// Чип в две строки: сверху — имя («3-местный», «55″», «205/55 R16»), снизу мелко — размеры или машины. Выбранный —
/// зелёный, как ЧипПодачи.
struct ЧипОбразцаРазмеров: View {
    let верх: String
    let низ: String
    let выбран: Bool
    let озвучка: String
    let действие: () -> Void

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
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !низ.isEmpty {
                    Text(низ)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .opacity(выбран ? 0.92 : 0.72)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(выбран ? Color.white : КраскаПодачи.текст)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(выбран ? Theme.зелёный : КраскаПодачи.карточка, in: форма)
            .overlay { форма.strokeBorder(выбран ? Theme.зелёный : КраскаПодачи.линия, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(озвучка)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Шины и диски

/**
 «Размер шин или дисков» в разделе tires-wheels — над мастером запчастей (ПоляЗапчасти): «Шины | Диски» (выбор меняет
 поля мастера: диски — вид «wheel»), популярные размеры из каталога, ввод одной строкой («205/55 R16», «R17 5x114.3 ET45
 DIA 67.1 7.5J») и только те поля, которых у мастера нет. Значения — в форма.запчасть (PostingSizeWheels.swift).
 */
struct БлокШинДисковПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding
    @State private var строка = ""
    @State private var итогСтроки: String? = nil
    @State private var строкаПонята = false

    private let колонки = [GridItem(.flexible(), spacing: 10, alignment: .top),
                           GridItem(.flexible(), spacing: 10, alignment: .top)]

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { РазмерыОбразцовText.т(ключ) }

    var body: some View {
        let диски = модель.дискиВыбраны
        let вид = модель.видКолёс
        let зачем = вид?.зачем ?? ""
        return КарточкаПодачи(т("tw_title"), подпись: зачем.isEmpty ? т("tw_sub") : зачем, значок: "circle.circle") {
            выбор(диски)
            if let вид, !вид.образцы.isEmpty {
                образцы(вид)
            }
            ввод(диски)
            своиПоля(диски)
            if let вид, вид.мера == .диск, модель.выбранныйОбразецКолёс(вид) != nil {
                ЗаметкаПодачи(т("tw_rim_note"), тон: .внимание, значок: "exclamationmark.triangle")
            }
        }
        .id("tw_size")
    }

    /// «Шины | Диски»; не поняли по названию — подсказка выбрать.
    private func выбор(_ диски: Bool?) -> some View {
        let м = модель
        let варианты = [ВариантПоля(ключ: "tyre", подпись: м.заголовокКолёс(диски: false)),
                        ВариантПоля(ключ: "rim", подпись: м.заголовокКолёс(диски: true))]
        let значение = Binding<String>(get: {
            switch м.дискиВыбраны {
            case .some(true): return "rim"
            case .some(false): return "tyre"
            case .none: return ""
            }
        }, set: { новое in
            guard !новое.isEmpty else { return }
            фокус.wrappedValue = nil
            ОткликСайта.выбор()
            м.выбратьКолёса(диски: новое == "rim")
        })
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("tw_kind"), мелкая: true)
            ВыборСегментом(варианты, значение: значение)
            if диски == nil {
                ПодсказкаПоля(т("tw_ask"))
            }
        }
    }

    /// Популярные размеры: шины — «205/55 R16» и машины, диски — «R16 · 5×114.3» и машины.
    private func образцы(_ вид: ВидРазмеров) -> some View {
        let выбранный = модель.выбранныйОбразецКолёс(вид)
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("tw_popular"), мелкая: true)
            ПотокЧипов(зазор: 8) {
                ForEach(вид.образцы) { образец in
                    let подписи = вид.подписи(образец)
                    ЧипОбразцаРазмеров(верх: подписи.верх, низ: подписи.низ, выбран: выбранный?.id == образец.id,
                                       озвучка: т("tw_fill_a11y", БлокОбразцовРазмеров.озвучка(подписи))) {
                        фокус.wrappedValue = nil
                        ОткликСайта.выбор()
                        модель.применитьОбразецКолёс(образец, вида: вид)
                    }
                }
            }
        }
    }

    private func т(_ ключ: String, _ значение: String) -> String { РазмерыОбразцовText.т(ключ, значение) }

    /// Пример строки для подсказки и для ответа «не поняли».
    private func пример(_ диски: Bool?) -> String {
        диски == true ? "R16 6.5J ET45 5x114.3 DIA 67.1" : "205/55 R16"
    }

    /// Размер одной строкой и «Разложить».
    private func ввод(_ диски: Bool?) -> some View {
        let пусто = строка.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            ПодписьПоля(т("tw_line"), мелкая: true)
            HStack(spacing: 8) {
                ПолеПодачи(пример(диски), текст: $строка, заглавные: .characters, фокус: фокус, ключ: "tw_line",
                           предел: 60)
                    .onSubmit { разложить(диски) }
                Button {
                    разложить(диски)
                } label: {
                    Text(т("tw_line_btn"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(КраскаПодачи.хорошоФон,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(пусто)
                .opacity(пусто ? 0.5 : 1)
            }
            if let итог = итогСтроки {
                ЗаметкаПодачи(итог, тон: строкаПонята ? .хорошо : .внимание,
                              значок: строкаПонята ? "checkmark.circle" : "exclamationmark.triangle")
            }
        }
    }

    private func разложить(_ диски: Bool?) {
        let текст = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !текст.isEmpty else { return }
        фокус.wrappedValue = nil
        if модель.разложитьСтрокуКолёс(текст) {
            строкаПонята = true
            итогСтроки = т("tw_line_ok")
            строка = ""
        } else {
            строкаПонята = false
            итогСтроки = т("tw_line_bad", пример(диски))
        }
    }

    /// Поля шин или дисков, которых нет у мастера запчастей (старый справочник, диски без вида «wheel»), по два в ряд.
    @ViewBuilder
    private func своиПоля(_ диски: Bool?) -> some View {
        let есть = Set(модель.поляЗапчасти.map { $0.id })
        let нужны = (диски == true ? СтрокиКолёсПодачи.ключиДисков : СтрокиКолёсПодачи.ключиШин)
            .filter { !есть.contains($0) }
        if !нужны.isEmpty {
            LazyVGrid(columns: колонки, alignment: .leading, spacing: 12) {
                ForEach(нужны, id: \.self) { ключ in
                    VStack(alignment: .leading, spacing: 6) {
                        ПодписьПоля(подпись(ключ), мелкая: true)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        ПолеПодачи(подсказка(ключ), текст: значение(ключ),
                                   клавиатура: ключ == "pcd" || ключ == "et" ? .numbersAndPunctuation : .decimalPad,
                                   фокус: фокус, ключ: "tw_" + ключ)
                    }
                }
            }
        }
    }

    private func подпись(_ ключ: String) -> String {
        switch ключ {
        case "width": return т("tw_w")
        case "profile": return т("tw_h")
        case "width_j": return т("tw_j")
        case "et": return т("tw_et")
        case "pcd": return т("tw_pcd")
        case "dia": return т("tw_dia")
        default: return т("tw_r")
        }
    }

    /// Пример в пустом поле — числа без слов, на всех языках одинаковые.
    private func подсказка(_ ключ: String) -> String {
        switch ключ {
        case "width": return "205"
        case "profile": return "55"
        case "width_j": return "6.5"
        case "et": return "45"
        case "pcd": return "5x114.3"
        case "dia": return "67.1"
        default: return "16"
        }
    }

    /// Значение поля: числа — цифры и одна дробная часть (вылет — со знаком), PCD — как ввели (до 12 знаков).
    private func значение(_ ключ: String) -> Binding<String> {
        let м = модель
        return Binding(get: { м.форма.запчасть[ключ] ?? "" }, set: { новое in
            let чистое: String
            switch ключ {
            case "pcd":
                чистое = String(новое.trimmingCharacters(in: .whitespaces).prefix(12))
            case "et":
                let знак = новое.trimmingCharacters(in: .whitespaces).hasPrefix("-") ? "-" : ""
                чистое = знак + ПодачаМодель.дробное(новое, предел: 5)
            default:
                чистое = ПодачаМодель.дробное(новое, предел: 6)
            }
            if (м.форма.запчасть[ключ] ?? "") != чистое { м.форма.запчасть[ключ] = чистое }
        })
    }
}
