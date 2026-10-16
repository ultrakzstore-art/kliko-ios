import SwiftUI
import UIKit

/**
 «ПОДОЙДУТ ЛИ?» — ВЫБОР МАШИНЫ И ВВОД ПАРАМЕТРОВ (владелец 13.10.2026: «нужнее охват всего»).

 Страницы навигации окна (ШагАвтоподбора, AutoFitScreen.swift):
   · марка — группами, как у мастера авто подачи (Япония, Корея, Германия…), с поиском; нет в списке — «Другая марка»;
   · модель — модели марки с годами выпуска (поколения справочника), с поиском; нет — «Другая модель»;
   · год — от новых к старым, рядом имя поколения; «Не помню год» — без него. Выбрали — спрашиваем справочник посадки
     (ГаражАвтоподбора.выбрать): нашёлся — назад к итогу, нет — страница своих параметров;
   · свои параметры машины — штатный размер шин, PCD, DIA, ET с подсказкой, где их найти (наклейка в проёме двери
     водителя, инструкция, маркировка на штатном диске); под полем сразу видно, понято ли набранное;
   · параметры товара — если из объявления не поняли (или поняли не так): шины, диски или колёса в сборе и их числа.
 Всё на телефоне; набранное — только в памяти окна и в главной машине «Моего гаража» (MyThings/MyThingsStore.swift).
 Марка и модель отсюда же служат редактору машины гаража (ВыборМаркиАвтоподбора, ВыборМоделиАвтоподбора).
 */
struct ЭкранШагаАвтоподбора: View {
    let шаг: ШагАвтоподбора
    @ObservedObject var модель: МодельАвтоподбора
    @ObservedObject var гараж: ГаражАвтоподбора

    init(шаг: ШагАвтоподбора, модель: МодельАвтоподбора, гараж: ГаражАвтоподбора) {
        self.шаг = шаг
        self.модель = модель
        self.гараж = гараж
    }

    var body: some View {
        switch шаг {
        case .марка:
            ВыборМаркиАвтоподбора()
        case .модель(let марка):
            ВыборМоделиАвтоподбора(марка: марка)
        case .год(let марка, let имя):
            ВыборГодаАвтоподбора(модель: модель, гараж: гараж, марка: марка, имяМодели: имя)
        case .параметрыМашины:
            ПараметрыМашиныАвтоподбора(модель: модель, гараж: гараж)
        case .параметрыТовара:
            ПараметрыТовараАвтоподбора(модель: модель)
        case .калькулятор:
            калькулятор
        }
    }

    /// Калькулятор начинается со штатного размера машины («было») и шины из объявления («стало»).
    private var калькулятор: some View {
        let начало = модель.размерыКалькулятора(гараж.посадка)
        return КалькуляторАвтоподбора(было: начало.было, стало: начало.стало)
    }
}

// MARK: - Марка

struct ВыборМаркиАвтоподбора: View {
    @State private var группы: [ГруппаМарок] = []
    @State private var поиск = ""

    init() {}

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var запрос: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var найденные: [ГруппаМарок] {
        let искомое = запрос.lowercased()
        guard !искомое.isEmpty else { return группы }
        return группы.compactMap { группа in
            let свои = группа.марки.filter { $0.lowercased().contains(искомое) }
            return свои.isEmpty ? nil : ГруппаМарок(регион: группа.регион, марки: свои)
        }
    }

    /// Набранное не совпало ни с одной маркой целиком — можно взять как есть.
    private var своя: String? {
        guard !запрос.isEmpty else { return nil }
        let есть = группы.contains { $0.марки.contains { $0.lowercased() == запрос.lowercased() } }
        return есть ? nil : запрос
    }

    var body: some View {
        List {
            if let своя {
                Section {
                    NavigationLink(value: ШагАвтоподбора.модель(своя)) {
                        Label(String(format: т("af_brand_custom"), своя), systemImage: "pencil")
                    }
                }
            }
            ForEach(найденные) { группа in
                Section(группа.регион) {
                    ForEach(группа.марки, id: \.self) { марка in
                        NavigationLink(value: ШагАвтоподбора.модель(марка)) {
                            Text(марка)
                                .foregroundStyle(Theme.текст)
                        }
                    }
                }
            }
            Section {
                NavigationLink(value: ШагАвтоподбора.параметрыМашины) {
                    Label(т("af_car_manual"), systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text(т("af_manual_footer"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always), prompt: т("af_search_brand"))
        .autocorrectionDisabled()
        .navigationTitle(т("af_brand"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if группы.isEmpty { группы = СправочникАвтоподбора.стартовыеМарки() }
            let свежие = await СправочникАвтоподбора.свежиеМарки()
            if !свежие.isEmpty { группы = свежие }
        }
    }
}

// MARK: - Модель

struct ВыборМоделиАвтоподбора: View {
    let марка: String
    @State private var модели: [МодельАвто] = []
    @State private var грузим = true
    @State private var поиск = ""

    init(марка: String) {
        self.марка = марка
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var запрос: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var найденные: [МодельАвто] {
        let искомое = запрос.lowercased()
        guard !искомое.isEmpty else { return модели }
        return модели.filter { $0.имя.lowercased().contains(искомое) }
    }

    private var своя: String? {
        guard !запрос.isEmpty else { return nil }
        return модели.contains { $0.имя.lowercased() == запрос.lowercased() } ? nil : запрос
    }

    /// Годы выпуска по поколениям: «2006–2024», «с 2018».
    private func годы(_ м: МодельАвто) -> String? {
        let с = м.поколения.map(\.с).filter { $0 > 1900 }
        guard let начало = с.min() else { return nil }
        let выпускается = м.поколения.contains { $0.по <= 0 }
        let конец = м.поколения.map(\.по).filter { $0 > 1900 }.max()
        if выпускается || конец == nil { return String(format: т("af_years_from"), String(начало)) }
        return String(начало) + "–" + String(конец ?? начало)
    }

    var body: some View {
        List {
            if let своя {
                Section {
                    NavigationLink(value: ШагАвтоподбора.год(марка, своя)) {
                        Label(String(format: т("af_model_custom"), своя), systemImage: "pencil")
                    }
                }
            }
            if грузим && модели.isEmpty {
                HStack(spacing: 10) {
                    SiteSpinner(размер: 18, толщина: 2, стоит: ДвижениеСайта.тихо)
                    Text(т("af_loading"))
                        .foregroundStyle(Theme.текстВторой)
                }
                .accessibilityElement(children: .combine)
            } else if модели.isEmpty {
                Text(т("af_models_empty"))
                    .foregroundStyle(Theme.текстВторой)
            }
            Section {
                ForEach(найденные) { м in
                    NavigationLink(value: ШагАвтоподбора.год(марка, м.имя)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(м.имя)
                                .foregroundStyle(Theme.текст)
                            if let годы = годы(м) {
                                Text(годы)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.текстВторой)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always), prompt: т("af_search_model"))
        .autocorrectionDisabled()
        .navigationTitle(марка)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard модели.isEmpty else { return }
            модели = await СправочникАвтоподбора.моделиМарки(марка)
            грузим = false
        }
    }
}

// MARK: - Год

struct ВыборГодаАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @ObservedObject var гараж: ГаражАвтоподбора
    let марка: String
    let имяМодели: String
    @State private var поколения: [ПоколениеАвто] = []

    init(модель: МодельАвтоподбора, гараж: ГаражАвтоподбора, марка: String, имяМодели: String) {
        self.модель = модель
        self.гараж = гараж
        self.марка = марка
        self.имяМодели = имяМодели
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    /// Годы от новых к старым: по поколениям модели, а без них — с 1980 по следующий год.
    private var годы: [Int] {
        let следующий = Calendar.current.component(.year, from: Date()) + 1
        var низ = 1980
        var верх = следующий
        let начала = поколения.map(\.с).filter { $0 > 1900 }
        if let первое = начала.min() {
            низ = первое
            let выпускается = поколения.contains { $0.по <= 0 }
            if !выпускается, let последнее = поколения.map(\.по).filter({ $0 > 1900 }).max() {
                верх = min(следующий, max(последнее, низ))
            }
        }
        guard низ <= верх else { return [] }
        return Array((низ...верх).reversed())
    }

    private func поколение(_ год: Int) -> String? {
        поколения.first { $0.с > 1900 && $0.с <= год && ($0.по <= 0 || год <= $0.по) }?.имя
    }

    var body: some View {
        List {
            Section {
                Button { выбрать(nil) } label: {
                    Label(т("af_year_skip"), systemImage: "calendar")
                }
            }
            Section(т("af_year_list")) {
                ForEach(годы, id: \.self) { год in
                    Button { выбрать(год) } label: {
                        HStack(spacing: 8) {
                            Text(String(год))
                                .foregroundStyle(Theme.текст)
                            Spacer(minLength: 8)
                            if let имя = поколение(год) {
                                Text(имя)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.текстВторой)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .disabled(гараж.ищем)
        .overlay {
            if гараж.ищем {
                ищем
            }
        }
        .navigationTitle(марка + " " + имяМодели)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let модели = await СправочникАвтоподбора.моделиМарки(марка)
            поколения = модели.first { $0.имя == имяМодели }?.поколения ?? []
        }
    }

    private var ищем: some View {
        VStack(spacing: 12) {
            SiteSpinner(размер: 28, толщина: 3, стоит: ДвижениеСайта.тихо)
                .accessibilityHidden(true)
            Text(т("af_car_searching"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func выбрать(_ год: Int?) {
        ОткликСайта.выбор()
        let машина = МашинаАвтоподбора(марка: марка, модель: имяМодели, год: год)
        Task { @MainActor in
            let нашли = await гараж.выбрать(машина)
            guard гараж.машина == машина else { return }
            модель.путь = нашли ? [] : [.параметрыМашины]
        }
    }
}

// MARK: - Поле ввода

/// Какое поле в фокусе (параметры машины и товара).
enum ПолеВводаАвтоподбора: Hashable {
    case шины
    case pcd
    case dia
    case et
    case диаметр
    case ширина
}

/// Что поняли из набранного.
enum ИтогВводаАвтоподбора: Equatable {
    case пусто
    case понято(String)
    case непонятно
}

/// Поле с заголовком, примером и строкой «понято: …» или «не похоже — пример: …» под ним.
struct ПолеАвтоподбора: View {
    let заголовок: String
    let пример: String
    @Binding var текст: String
    let итог: ИтогВводаАвтоподбора
    let клавиатура: UIKeyboardType
    let фокус: FocusState<ПолеВводаАвтоподбора?>.Binding
    let ключ: ПолеВводаАвтоподбора

    init(заголовок: String, пример: String, текст: Binding<String>, итог: ИтогВводаАвтоподбора,
         клавиатура: UIKeyboardType, фокус: FocusState<ПолеВводаАвтоподбора?>.Binding, ключ: ПолеВводаАвтоподбора) {
        self.заголовок = заголовок
        self.пример = пример
        _текст = текст
        self.итог = итог
        self.клавиатура = клавиатура
        self.фокус = фокус
        self.ключ = ключ
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var вФокусе: Bool { фокус.wrappedValue == ключ }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityHidden(true)
            TextField(пример, text: $текст)
                .keyboardType(клавиатура)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(фокус, equals: ключ)
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 48)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(вФокусе ? Theme.акцент : Theme.линия, lineWidth: вФокусе ? 2 : 1)
                }
                .accessibilityLabel(заголовок)
                .accessibilityHint(String(format: т("af_f_example"), пример))
            строкаИтога
        }
    }

    @ViewBuilder
    private var строкаИтога: some View {
        switch итог {
        case .пусто:
            EmptyView()
        case .понято(let что):
            Label(что, systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(УровеньАвтоподбора.подходит.краска)
        case .непонятно:
            Label(String(format: т("af_f_bad"), пример), systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(УровеньАвтоподбора.проверить.краска)
        }
    }
}

/// Разбор полей ввода — общий для параметров машины и товара.
enum ВводАвтоподбора {
    static func шины(_ строка: String) -> (размер: РазмерШиныАвтоподбора?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let размер = РазмерШиныАвтоподбора.изВвода(строка) else { return (nil, .непонятно) }
        let что = String(format: АвтоподборText.т("af_f_tire_ok"), размер.подпись,
                         ЧислаАвтоподбора.ч(размер.внешний, знаков: 0))
        return (размер, .понято(что))
    }

    static func pcd(_ строка: String) -> (разболтовка: РазболтовкаАвтоподбора?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let р = РазболтовкаАвтоподбора.изВвода(строка) else { return (nil, .непонятно) }
        return (р, .понято(р.подпись))
    }

    static func dia(_ строка: String) -> (dia: Double?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let ч = ПарсерАвтоподбора.числоВвода(строка), (50...175).contains(ч) else { return (nil, .непонятно) }
        return (ч, .понято(String(format: АвтоподборText.т("af_mm"), ЧислаАвтоподбора.ч(ч, знаков: 2))))
    }

    static func et(_ строка: String) -> (вылет: ClosedRange<Double>?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let в = ПарсерАвтоподбора.вылетВвода(строка) else { return (nil, .непонятно) }
        let что = в.lowerBound == в.upperBound ? "ET" + ЧислаАвтоподбора.ч(в.lowerBound)
            : "ET" + ЧислаАвтоподбора.ч(в.lowerBound) + "…" + ЧислаАвтоподбора.ч(в.upperBound)
        return (в, .понято(что))
    }

    static func диаметр(_ строка: String) -> (диаметр: Double?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let ч = ПарсерАвтоподбора.числоВвода(строка), РазмерШиныАвтоподбора.диаметры.contains(ч) else {
            return (nil, .непонятно)
        }
        return (ч, .понято("R" + ЧислаАвтоподбора.ч(ч)))
    }

    static func ширина(_ строка: String) -> (ширина: Double?, итог: ИтогВводаАвтоподбора) {
        guard !пусто(строка) else { return (nil, .пусто) }
        guard let ч = ПарсерАвтоподбора.числоВвода(строка), (3.5...13).contains(ч) else { return (nil, .непонятно) }
        return (ч, .понято(ЧислаАвтоподбора.ч(ч) + "J"))
    }

    private static func пусто(_ строка: String) -> Bool {
        строка.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Свои параметры машины

struct ПараметрыМашиныАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @ObservedObject var гараж: ГаражАвтоподбора
    @State private var шины = ""
    @State private var pcd = ""
    @State private var dia = ""
    @State private var et = ""
    @State private var заполнено = false
    @State private var спроситьЗабыть = false
    @FocusState private var поле: ПолеВводаАвтоподбора?

    init(модель: МодельАвтоподбора, гараж: ГаражАвтоподбора) {
        self.модель = модель
        self.гараж = гараж
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var итоги: [ИтогВводаАвтоподбора] {
        [ВводАвтоподбора.шины(шины).итог, ВводАвтоподбора.pcd(pcd).итог, ВводАвтоподбора.dia(dia).итог,
         ВводАвтоподбора.et(et).итог]
    }

    /// Сохранить можно, когда хоть одно поле понято и ни одно набранное не осталось непонятым.
    private var годится: Bool {
        !итоги.contains(.непонятно) && итоги.contains { if case .понято = $0 { return true } else { return false } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                подсказка
                ПолеАвтоподбора(заголовок: т("af_f_tire"), пример: "205/55 R16", текст: $шины,
                                итог: ВводАвтоподбора.шины(шины).итог, клавиатура: .asciiCapable, фокус: $поле,
                                ключ: .шины)
                ПолеАвтоподбора(заголовок: т("af_f_pcd"), пример: "5x114.3", текст: $pcd,
                                итог: ВводАвтоподбора.pcd(pcd).итог, клавиатура: .asciiCapable, фокус: $поле, ключ: .pcd)
                ПолеАвтоподбора(заголовок: т("af_f_dia"), пример: "67.1", текст: $dia,
                                итог: ВводАвтоподбора.dia(dia).итог, клавиатура: .decimalPad, фокус: $поле, ключ: .dia)
                ПолеАвтоподбора(заголовок: т("af_f_et"), пример: "45", текст: $et,
                                итог: ВводАвтоподбора.et(et).итог, клавиатура: .numbersAndPunctuation, фокус: $поле,
                                ключ: .et)
                ЗелёнаяКнопкаФото(заголовок: т("af_save"), значок: "checkmark") {
                    сохранить()
                }
                .disabled(!годится)
                .opacity(годится ? 1 : 0.5)
                if гараж.машина != nil || гараж.посадка != nil {
                    МалаяКнопкаАвтоподбора(заголовок: т("af_car_forget"), значок: "trash", опасная: true) {
                        спроситьЗабыть = true
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("af_car_params_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(т("af_done")) { поле = nil }
            }
        }
        .onAppear { заполнить() }
        .confirmationDialog(т("af_car_forget_q"), isPresented: $спроситьЗабыть, titleVisibility: .visible) {
            Button(т("af_car_forget"), role: .destructive) {
                гараж.забыть()
                модель.путь = []
            }
            Button(т("af_cancel"), role: .cancel) {}
        }
    }

    /// Где взять параметры; если справочник машину не нашёл — сказать об этом.
    private var подсказка: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let машина = гараж.машина, гараж.посадка == nil || гараж.посадка?.свои == true {
                Text(машина.подпись)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                if гараж.посадка == nil {
                    Text(т(гараж.молчание == .сеть ? "af_car_no_net" : "af_car_not_found"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label {
                Text(т("af_where"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.текст)
        }
        .карточкаАвтоподбора()
    }

    private func заполнить() {
        guard !заполнено else { return }
        заполнено = true
        guard let п = гараж.посадка else { return }
        шины = п.шины.first?.подпись ?? ""
        pcd = п.разболтовка.map { String($0.отверстий) + "x" + ЧислаАвтоподбора.ч($0.pcd, знаков: 2) } ?? ""
        dia = п.dia.map { ЧислаАвтоподбора.ч($0, знаков: 2) } ?? ""
        if let низ = п.etMin ?? п.etMax, let верх = п.etMax ?? п.etMin {
            et = низ == верх ? ЧислаАвтоподбора.ч(низ) : ЧислаАвтоподбора.ч(низ) + "-" + ЧислаАвтоподбора.ч(верх)
        }
    }

    private func сохранить() {
        поле = nil
        var п = гараж.посадка ?? ПосадкаАвтоподбора()
        let размер = ВводАвтоподбора.шины(шины).размер
        if let размер {
            п.шины = [размер] + п.шины.filter { $0 != размер }
        } else {
            п.шины = []
        }
        п.разболтовка = ВводАвтоподбора.pcd(pcd).разболтовка
        п.dia = ВводАвтоподбора.dia(dia).dia
        let вылет = ВводАвтоподбора.et(et).вылет
        п.etMin = вылет?.lowerBound
        п.etMax = вылет?.upperBound
        гараж.сохранитьСвои(п)
        ОткликСайта.успех()
        модель.путь = []
    }
}

// MARK: - Параметры товара

struct ПараметрыТовараАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var вид: ВидТовараАвтоподбора = .шины
    @State private var шины = ""
    @State private var диаметр = ""
    @State private var ширина = ""
    @State private var pcd = ""
    @State private var et = ""
    @State private var dia = ""
    @State private var заполнено = false
    @FocusState private var поле: ПолеВводаАвтоподбора?

    init(модель: МодельАвтоподбора) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var итоги: [ИтогВводаАвтоподбора] {
        var список: [ИтогВводаАвтоподбора] = []
        if вид != .диски { список.append(ВводАвтоподбора.шины(шины).итог) }
        if вид != .шины || ВводАвтоподбора.шины(шины).размер == nil {
            список.append(ВводАвтоподбора.диаметр(диаметр).итог)
        }
        if вид != .шины {
            список += [ВводАвтоподбора.ширина(ширина).итог, ВводАвтоподбора.pcd(pcd).итог, ВводАвтоподбора.et(et).итог,
                       ВводАвтоподбора.dia(dia).итог]
        }
        return список
    }

    private var годится: Bool {
        !итоги.contains(.непонятно) && итоги.contains { if case .понято = $0 { return true } else { return false } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                выборВида
                Text(т("af_item_hint"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                if вид != .диски {
                    ПолеАвтоподбора(заголовок: т("af_f_item_tire"), пример: "225/45 R17", текст: $шины,
                                    итог: ВводАвтоподбора.шины(шины).итог, клавиатура: .asciiCapable, фокус: $поле,
                                    ключ: .шины)
                }
                if вид != .шины || ВводАвтоподбора.шины(шины).размер == nil {
                    ПолеАвтоподбора(заголовок: т("af_f_diam"), пример: "17", текст: $диаметр,
                                    итог: ВводАвтоподбора.диаметр(диаметр).итог, клавиатура: .decimalPad,
                                    фокус: $поле, ключ: .диаметр)
                }
                if вид != .шины {
                    поляДиска
                }
                ЗелёнаяКнопкаФото(заголовок: т("af_apply"), значок: "checkmark") {
                    применить()
                }
                .disabled(!годится)
                .opacity(годится ? 1 : 0.5)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.смена, value: вид)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("af_item_params_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(т("af_done")) { поле = nil }
            }
        }
        .onAppear { заполнить() }
    }

    /// Шины, диски или колёса: сегменты, а при крупном тексте — меню (в сегментах слова не помещаются).
    @ViewBuilder
    private var выборВида: some View {
        if размерТекста.isAccessibilitySize {
            Picker(т("af_kind"), selection: $вид) {
                ForEach(ВидТовараАвтоподбора.allCases, id: \.self) { вид in
                    Text(вид.название).tag(вид)
                }
            }
            .pickerStyle(.menu)
        } else {
            Picker(т("af_kind"), selection: $вид) {
                ForEach(ВидТовараАвтоподбора.allCases, id: \.self) { вид in
                    Text(вид.название).tag(вид)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var поляДиска: some View {
        VStack(alignment: .leading, spacing: 16) {
            ПолеАвтоподбора(заголовок: т("af_f_width"), пример: "7.5", текст: $ширина,
                            итог: ВводАвтоподбора.ширина(ширина).итог, клавиатура: .decimalPad, фокус: $поле,
                            ключ: .ширина)
            ПолеАвтоподбора(заголовок: т("af_f_pcd"), пример: "5x114.3", текст: $pcd,
                            итог: ВводАвтоподбора.pcd(pcd).итог, клавиатура: .asciiCapable, фокус: $поле, ключ: .pcd)
            ПолеАвтоподбора(заголовок: т("af_f_item_et"), пример: "45", текст: $et,
                            итог: ВводАвтоподбора.et(et).итог, клавиатура: .numbersAndPunctuation, фокус: $поле,
                            ключ: .et)
            ПолеАвтоподбора(заголовок: т("af_f_dia"), пример: "67.1", текст: $dia,
                            итог: ВводАвтоподбора.dia(dia).итог, клавиатура: .decimalPad, фокус: $поле, ключ: .dia)
        }
    }

    private func заполнить() {
        guard !заполнено else { return }
        заполнено = true
        let р = модель.разбор
        вид = р.вид ?? (ПризнакиДисков.диски(модель.товар) == true ? .диски : .шины)
        шины = (модель.размерТовара ?? р.шины.first)?.подпись ?? ""
        let д = р.диск.диаметр ?? р.диаметрШины
        диаметр = д.map { ЧислаАвтоподбора.ч($0) } ?? ""
        ширина = р.диск.ширина.map { ЧислаАвтоподбора.ч($0) } ?? ""
        pcd = р.диск.разболтовки.first.map { String($0.отверстий) + "x" + ЧислаАвтоподбора.ч($0.pcd, знаков: 2) } ?? ""
        et = р.диск.et.map { ЧислаАвтоподбора.ч($0) } ?? ""
        dia = р.диск.dia.map { ЧислаАвтоподбора.ч($0, знаков: 2) } ?? ""
    }

    private func применить() {
        поле = nil
        var р = модель.разбор
        р.вид = вид
        let размер = вид != .диски ? ВводАвтоподбора.шины(шины).размер : nil
        if let размер {
            р.шины = [размер] + Array(р.шины.filter { $0 != размер }.prefix(1))
        } else {
            р.шины = []
        }
        let своейДиаметр = ВводАвтоподбора.диаметр(диаметр).диаметр
        switch вид {
        case .шины:
            р.диаметрШины = размер?.диаметр ?? своейДиаметр
            р.диск = ДискАвтоподбора()
        case .диски, .колёса:
            р.диаметрШины = nil
            var д = ДискАвтоподбора()
            д.диаметр = своейДиаметр ?? (вид == .колёса ? размер?.диаметр : nil)
            д.ширина = ВводАвтоподбора.ширина(ширина).ширина
            /* Вторая разболтовка мультиразболтовки из объявления остаётся, если первую не меняли. */
            if let своя = ВводАвтоподбора.pcd(pcd).разболтовка {
                д.разболтовки = [своя] + Array(модель.разбор.диск.разболтовки.filter { !$0.совпадает(своя) }.prefix(1))
            }
            let вылет = ВводАвтоподбора.et(et).вылет
            д.et = вылет.map { ($0.lowerBound + $0.upperBound) / 2 }
            д.dia = ВводАвтоподбора.dia(dia).dia
            р.диск = д
        }
        модель.применить(р)
        ОткликСайта.успех()
        if !модель.путь.isEmpty { модель.путь.removeLast() }
    }
}
