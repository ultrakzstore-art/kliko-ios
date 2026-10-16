import SwiftUI
import UIKit

/**
 «МОЁ» — «МОИ УСТРОЙСТВА» (владелец 14.10.2026: «так же с чехлами для смартфонов, сумками для ноутбуков и на всё, что
 возможно»).

 Телефон — определяется сам по железу («Ваш телефон — iPhone 15 Pro», «Определили сами», габариты и диагональ);
 «Другая модель» — поиск по каталогу (все iPhone, частые Android), своя модель «Нет в списке» с диагональю. Ноутбук —
 чипы диагонали из шаблонов габаритов (КаталогРазмеров, как у подачи объявлений): касание подставляет Ш×В×Г с пометкой
 «примерно»; три поля и модель по желанию; «Ноутбука нет». Мониторы и телевизоры — списком, «Добавить экран» (лист:
 Монитор / Телевизор, диагональ, габариты), «Экрана нет». По этим размерам позже подбираются чехлы, сумки и место на
 столе. Всё — только на телефоне.
 */
struct ЭкранУстройствМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var ноутбук = УстройствоМоего(вид: .ноутбук)
    @State private var выборТелефона = false
    @State private var экран: УстройствоМоего? = nil

    init() {}

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    var body: some View {
        let запись = хранилище.запись
        ScrollView {
            VStack(spacing: 14) {
                карточкаТелефона(запись.телефон)
                карточкаНоутбука(запись)
                карточкаЭкранов(запись)
                Label {
                    Text(т("md_why"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Theme.акцент)
                }
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: запись.устройства)
            .animation(ДвижениеСайта.смена, value: запись.нет)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(МоёText.т("my_devices"))
        .клавиатураМоего()
        .sheet(isPresented: $выборТелефона) {
            ВыборТелефонаМоего()
        }
        .sheet(item: $экран) { устройство in
            РедакторУстройстваМоего(устройство: устройство,
                                    новое: !хранилище.запись.устройства.contains(where: { $0.id == устройство.id }))
        }
        .onAppear {
            хранилище.подготовить()
            if let свой = хранилище.запись.ноутбуки.first { ноутбук = свой }
            if хранилище.запись.телефон == nil, let определён = КаталогТелефоновМоего.определить() {
                хранилище.задатьТелефон(определён)
            }
        }
        .onChange(of: ноутбук) { _, новый in сохранить(новый) }
    }

    /// Заполненное — в запись; опустевшее — прочь из записи.
    private func сохранить(_ устройство: УстройствоМоего) {
        if устройство.заполнено {
            хранилище.обновитьУстройство(устройство)
        } else if хранилище.запись.устройства.contains(where: { $0.id == устройство.id }) {
            хранилище.удалитьУстройство(устройство.id)
        }
    }

    // MARK: Телефон

    private func карточкаТелефона(_ телефон: ТелефонМоего?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("md_phone"), значок: "iphone.gen3")
            if let телефон {
                Text(телефон.сам ? String(format: т("md_phone_auto"), телефон.модель) : телефон.модель)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if телефон.сам {
                    Label(т("md_phone_auto_sub"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
                if let строка = Self.габариты(телефон) {
                    Text(строка)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                }
                МалаяКнопкаАвтоподбора(заголовок: т("md_phone_change"), значок: "arrow.triangle.2.circlepath") {
                    выборТелефона = true
                }
            } else {
                Text(т("md_phone_none"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ЗелёнаяКнопкаФото(заголовок: т("md_phone_pick"), значок: "iphone.gen3") {
                    выборТелефона = true
                }
            }
        }
        .карточкаМоего()
    }

    /// «70,6 × 146,6 × 8,25 мм · 6,1″».
    static func габариты(_ телефон: ТелефонМоего) -> String? {
        var части: [String] = []
        if let мм = телефон.мм, мм.count == 3 {
            части.append(мм.map { ЧислоМоего.ч($0, знаков: 2) }.joined(separator: " × ") + " " + МоёТелоText.т("md_mm"))
        }
        if let д = телефон.диагональ { части.append(ЧислоМоего.ч(д, знаков: 2) + "″") }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    // MARK: Ноутбук

    private func карточкаНоутбука(_ запись: ЗаписьМоего) -> some View {
        let нет = запись.нет.contains(ЗаписьМоего.нетНоутбука) && !ноутбук.заполнено
        return VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("md_laptop"), значок: ВидУстройстваМоего.ноутбук.значок)
            if нет {
                строкаНет(т("md_none_laptop")) { хранилище.отметитьНет(.ноутбук, false) }
            } else {
                ПоляУстройстваМоего(устройство: $ноутбук)
                    .id(ноутбук.id)
                if ноутбук.заполнено {
                    МалаяКнопкаАвтоподбора(заголовок: МоёText.т("my_delete"), значок: "trash", опасная: true) {
                        хранилище.удалитьУстройство(ноутбук.id)
                        ноутбук = УстройствоМоего(вид: .ноутбук)
                    }
                } else {
                    ЧипМоего(т("md_none_laptop"), выбран: false, значок: "xmark") {
                        ОткликСайта.выбор()
                        хранилище.отметитьНет(.ноутбук, true)
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// «Ноутбука нет ✓» и «Добавить» — снять отметку.
    private func строкаНет(_ текст: String, вернуть: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Label(текст, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.акцент)
            Spacer(minLength: 8)
            МалаяКнопкаАвтоподбора(заголовок: МоёText.т("my_add"), значок: "plus") {
                ОткликСайта.выбор()
                вернуть()
            }
        }
    }

    // MARK: Мониторы и ТВ

    private func карточкаЭкранов(_ запись: ЗаписьМоего) -> some View {
        let экраны = запись.экраны
        let нет = запись.нет.contains(ЗаписьМоего.нетЭкрана) && экраны.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("md_screen"), значок: ВидУстройстваМоего.монитор.значок)
            ForEach(экраны) { устройство in
                строкаЭкрана(устройство)
            }
            if нет {
                строкаНет(т("md_none_screen")) { хранилище.отметитьНет(.монитор, false) }
            } else {
                if запись.устройства.count < ЗаписьМоего.пределУстройств {
                    ЗелёнаяКнопкаФото(заголовок: т("md_add_screen"), значок: "plus", контурная: true) {
                        ОткликСайта.выбор()
                        экран = УстройствоМоего(вид: .монитор)
                    }
                }
                if экраны.isEmpty {
                    ЧипМоего(т("md_none_screen"), выбран: false, значок: "xmark") {
                        ОткликСайта.выбор()
                        хранилище.отметитьНет(.монитор, true)
                    }
                }
            }
        }
        .карточкаМоего()
    }

    private func строкаЭкрана(_ устройство: УстройствоМоего) -> some View {
        Button {
            ОткликСайта.выбор()
            экран = устройство
        } label: {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: устройство.вид.значок, цвет: ПрофильМоего.устройства.цвет, размер: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(устройство.заголовок)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                    if let габариты = устройство.строкаГабаритов {
                        Text(габариты)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                Spacer(minLength: 8)
                СтрелкаСтрокиКабинета()
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

extension УстройствоМоего {
    /// «Телевизор 55″» или своя модель.
    var заголовок: String {
        let своя = модель.trimmingCharacters(in: .whitespacesAndNewlines)
        if !своя.isEmpty { return своя }
        guard let д = диагональ else { return вид.название }
        return вид.название + " " + ЧислоМоего.дюймы(д)
    }

    /// «123 × 77 × 25 см · примерно».
    var строкаГабаритов: String? {
        guard let см, см.count == 3 else { return nil }
        let строка = см.map { String($0) }.joined(separator: " × ") + " " + МоёТелоText.т("mb_cm")
        return образец ? строка + " · " + МоёТелоText.т("md_approx") : строка
    }
}

// MARK: - Поля устройства

/// Диагональ чипами (шаблоны габаритов), Ш × В × Г в сантиметрах и модель по желанию.
struct ПоляУстройстваМоего: View {
    @Binding var устройство: УстройствоМоего
    @Environment(\.dynamicTypeSize) private var размерТекста
    @State private var части: [Double?] = [nil, nil, nil]
    @State private var заполнено = false

    init(устройство: Binding<УстройствоМоего>) {
        _устройство = устройство
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    private var образцы: [ОбразецРазмеров] {
        КаталогРазмеров.встроенные.first { $0.ключ == устройство.вид.rawValue }?.образцы ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(т("md_diag"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(образцы) { образец in
                    ЧипМоего(образец.подписьДиагонали, выбран: образец.дюймы != nil && образец.дюймы == устройство.диагональ) {
                        подставить(образец)
                    }
                }
            }
            HStack(spacing: 6) {
                Text(т("md_dims"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                if устройство.образец && устройство.см != nil {
                    Text(т("md_approx"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.оранжевый)
                        .transition(.opacity)
                }
            }
            поля
            модель
        }
        .animation(ДвижениеСайта.смена, value: устройство.образец)
        .onAppear {
            guard !заполнено else { return }
            заполнено = true
            части = Self.части(устройство.см)
        }
        .onChange(of: устройство.см) { _, новые in
            if новые != nil { части = Self.части(новые) }
        }
    }

    @ViewBuilder
    private var поля: some View {
        if размерТекста.isAccessibilitySize {
            VStack(spacing: 10) {
                поле(0, т("md_w"))
                поле(1, т("md_h"))
                поле(2, т("md_d"))
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                поле(0, т("md_w"))
                поле(1, т("md_h"))
                поле(2, т("md_d"))
            }
        }
    }

    private func поле(_ номер: Int, _ заголовок: String) -> some View {
        ПолеЧислаМоего(заголовок: заголовок, единица: т("mb_cm"), значение: Binding(get: { части[номер] }, set: { новое in
            части[номер] = новое
            применитьЧасти()
        }), пределы: 1...500, знаков: 0)
    }

    private var модель: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("md_model"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityHidden(true)
            TextField(т("md_model_ph"), text: Binding(get: { устройство.модель }, set: { новое in
                устройство.модель = String(новое.prefix(60))
            }))
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .foregroundStyle(Theme.текст)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .accessibilityLabel(т("md_model"))
        }
    }

    private static func части(_ см: [Int]?) -> [Double?] {
        guard let см, см.count == 3 else { return [nil, nil, nil] }
        return см.map { Double($0) }
    }

    /// Все три числа есть — габариты свои (не «примерно»); стёрли одно — габаритов нет.
    private func применитьЧасти() {
        let числа = части.compactMap { $0 }.map { Int($0.rounded()) }
        if числа.count == 3 && числа.allSatisfy({ $0 > 0 }) {
            устройство.см = числа
            устройство.образец = false
        } else if устройство.см != nil {
            устройство.см = nil
            устройство.образец = false
        }
    }

    /// Чип диагонали: диагональ и примерные Ш × В × Г шаблона.
    private func подставить(_ образец: ОбразецРазмеров) {
        ОткликСайта.выбор()
        устройство.диагональ = образец.дюймы
        устройство.см = [образец.ширина, образец.высота, образец.глубина]
        устройство.образец = true
        части = Self.части(устройство.см)
    }
}

// MARK: - Монитор или ТВ

/// Лист экрана: Монитор / Телевизор, диагональ, габариты, модель; «Сохранить» и «Удалить».
struct РедакторУстройстваМоего: View {
    let новое: Bool
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @State private var устройство: УстройствоМоего

    init(устройство: УстройствоМоего, новое: Bool) {
        self.новое = новое
        _устройство = State(initialValue: устройство)
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(т("md_screen"), selection: $устройство.вид) {
                        Text(т("md_monitor")).tag(ВидУстройстваМоего.монитор)
                        Text(т("md_tv")).tag(ВидУстройстваМоего.тв)
                    }
                    .pickerStyle(.segmented)
                    ПоляУстройстваМоего(устройство: $устройство)
                        .id(устройство.вид)
                        .карточкаМоего()
                    if !новое {
                        МалаяКнопкаАвтоподбора(заголовок: МоёText.т("my_delete"), значок: "trash", опасная: true) {
                            хранилище.удалитьУстройство(устройство.id)
                            закрыть()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("md_screen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(МоёText.т("my_save")) {
                        хранилище.обновитьУстройство(устройство)
                        ОткликСайта.успех()
                        закрыть()
                    }
                    .disabled(!устройство.заполнено)
                }
            }
            .клавиатураМоего()
            .onChange(of: устройство.вид) { _, _ in
                ОткликСайта.выбор()
                устройство.диагональ = nil
                устройство.см = nil
                устройство.образец = false
            }
        }
        .tint(Theme.акцент)
        .presentationDetents([.large])
    }
}
