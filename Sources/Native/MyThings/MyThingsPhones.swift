import SwiftUI

/**
 «МОЁ» — КАТАЛОГ ТЕЛЕФОНОВ: модель так, как её пишут в объявлениях чехлов и стёкол («iPhone 15 Pro»), диагональ и
 габариты Ш × В × Т, мм. По ним позже сверяются чехлы (строго: «15 Pro» ≠ «15 Pro Max») и сумки.

 Свой телефон определяется сам — по коду железа (ЖелезоУстройства.модель, utsname: «iPhone16,1»), без сети и без
 запросов. Таблица — все iPhone, на которых работает iOS 17 и новее (с XR и XS). Незнакомый код (новая модель, iPad,
 симулятор) — модель не угадываем: человек выберет её сам. Android — частые модели Казахстана для ручного выбора.
 Размеры — по страницам производителей (у iPhone 17, Air, 17 Pro и Pro Max сверено 16.10.2026); у iPhone 17e — только
 диагональ, габариты появятся с проверкой.
 */
struct МодельТелефонаМоего: Identifiable, Equatable, Sendable {
    let имя: String
    let коды: [String]
    let диагональ: Double
    /// Ширина, высота, толщина, мм; nil — не сверены.
    let мм: [Double]?

    var id: String { имя }

    init(_ имя: String, _ коды: [String], _ диагональ: Double, _ мм: [Double]?) {
        self.имя = имя
        self.коды = коды
        self.диагональ = диагональ
        self.мм = мм
    }

    /// Свой телефон с этой моделью.
    func телефон(код: String = "", сам: Bool = false) -> ТелефонМоего {
        ТелефонМоего(модель: имя, код: код, диагональ: диагональ, мм: мм, сам: сам)
    }
}

enum КаталогТелефоновМоего {
    /// iPhone от новых к старым.
    static let iphone: [МодельТелефонаМоего] = [
        МодельТелефонаМоего("iPhone 17 Pro Max", ["iPhone18,2"], 6.9, [78.0, 163.4, 8.75]),
        МодельТелефонаМоего("iPhone 17 Pro", ["iPhone18,1"], 6.3, [71.9, 150.0, 8.75]),
        МодельТелефонаМоего("iPhone Air", ["iPhone18,4"], 6.5, [74.7, 156.2, 5.64]),
        МодельТелефонаМоего("iPhone 17", ["iPhone18,3"], 6.3, [71.5, 149.6, 7.95]),
        МодельТелефонаМоего("iPhone 17e", ["iPhone18,5"], 6.1, nil),
        МодельТелефонаМоего("iPhone 16 Pro Max", ["iPhone17,2"], 6.9, [77.6, 163.0, 8.25]),
        МодельТелефонаМоего("iPhone 16 Pro", ["iPhone17,1"], 6.3, [71.5, 149.6, 8.25]),
        МодельТелефонаМоего("iPhone 16 Plus", ["iPhone17,4"], 6.7, [77.8, 160.9, 7.8]),
        МодельТелефонаМоего("iPhone 16", ["iPhone17,3"], 6.1, [71.6, 147.6, 7.8]),
        МодельТелефонаМоего("iPhone 16e", ["iPhone17,5"], 6.1, [71.5, 146.7, 7.8]),
        МодельТелефонаМоего("iPhone 15 Pro Max", ["iPhone16,2"], 6.7, [76.7, 159.9, 8.25]),
        МодельТелефонаМоего("iPhone 15 Pro", ["iPhone16,1"], 6.1, [70.6, 146.6, 8.25]),
        МодельТелефонаМоего("iPhone 15 Plus", ["iPhone15,5"], 6.7, [77.8, 160.9, 7.8]),
        МодельТелефонаМоего("iPhone 15", ["iPhone15,4"], 6.1, [71.6, 147.6, 7.8]),
        МодельТелефонаМоего("iPhone 14 Pro Max", ["iPhone15,3"], 6.7, [77.6, 160.7, 7.85]),
        МодельТелефонаМоего("iPhone 14 Pro", ["iPhone15,2"], 6.1, [71.5, 147.5, 7.85]),
        МодельТелефонаМоего("iPhone 14 Plus", ["iPhone14,8"], 6.7, [78.1, 160.8, 7.8]),
        МодельТелефонаМоего("iPhone 14", ["iPhone14,7"], 6.1, [71.5, 146.7, 7.8]),
        МодельТелефонаМоего("iPhone SE (3)", ["iPhone14,6"], 4.7, [67.3, 138.4, 7.3]),
        МодельТелефонаМоего("iPhone 13 Pro Max", ["iPhone14,3"], 6.7, [78.1, 160.8, 7.65]),
        МодельТелефонаМоего("iPhone 13 Pro", ["iPhone14,2"], 6.1, [71.5, 146.7, 7.65]),
        МодельТелефонаМоего("iPhone 13", ["iPhone14,5"], 6.1, [71.5, 146.7, 7.65]),
        МодельТелефонаМоего("iPhone 13 mini", ["iPhone14,4"], 5.4, [64.2, 131.5, 7.65]),
        МодельТелефонаМоего("iPhone 12 Pro Max", ["iPhone13,4"], 6.7, [78.1, 160.8, 7.4]),
        МодельТелефонаМоего("iPhone 12 Pro", ["iPhone13,3"], 6.1, [71.5, 146.7, 7.4]),
        МодельТелефонаМоего("iPhone 12", ["iPhone13,2"], 6.1, [71.5, 146.7, 7.4]),
        МодельТелефонаМоего("iPhone 12 mini", ["iPhone13,1"], 5.4, [64.2, 131.5, 7.4]),
        МодельТелефонаМоего("iPhone SE (2)", ["iPhone12,8"], 4.7, [67.3, 138.4, 7.3]),
        МодельТелефонаМоего("iPhone 11 Pro Max", ["iPhone12,5"], 6.5, [77.8, 158.0, 8.1]),
        МодельТелефонаМоего("iPhone 11 Pro", ["iPhone12,3"], 5.8, [71.4, 144.0, 8.1]),
        МодельТелефонаМоего("iPhone 11", ["iPhone12,1"], 6.1, [75.7, 150.9, 8.3]),
        МодельТелефонаМоего("iPhone XS Max", ["iPhone11,4", "iPhone11,6"], 6.5, [77.4, 157.5, 7.7]),
        МодельТелефонаМоего("iPhone XS", ["iPhone11,2"], 5.8, [70.9, 143.6, 7.7]),
        МодельТелефонаМоего("iPhone XR", ["iPhone11,8"], 6.1, [75.7, 150.9, 8.3])
    ]

    /// Частые Android — для ручного выбора.
    static let android: [МодельТелефонаМоего] = [
        МодельТелефонаМоего("Samsung Galaxy S25 Ultra", [], 6.9, [77.6, 162.8, 8.2]),
        МодельТелефонаМоего("Samsung Galaxy S25+", [], 6.7, [75.8, 158.4, 7.3]),
        МодельТелефонаМоего("Samsung Galaxy S25", [], 6.2, [70.5, 146.9, 7.2]),
        МодельТелефонаМоего("Samsung Galaxy S24 Ultra", [], 6.8, [79.0, 162.3, 8.6]),
        МодельТелефонаМоего("Samsung Galaxy S24+", [], 6.7, [75.9, 158.5, 7.7]),
        МодельТелефонаМоего("Samsung Galaxy S24", [], 6.2, [70.6, 147.0, 7.6]),
        МодельТелефонаМоего("Samsung Galaxy S23 Ultra", [], 6.8, [78.1, 163.4, 8.9]),
        МодельТелефонаМоего("Samsung Galaxy S23+", [], 6.6, [76.2, 157.8, 7.6]),
        МодельТелефонаМоего("Samsung Galaxy S23", [], 6.1, [70.9, 146.3, 7.6]),
        МодельТелефонаМоего("Samsung Galaxy A56", [], 6.7, [77.5, 162.2, 7.4]),
        МодельТелефонаМоего("Samsung Galaxy A55", [], 6.6, [77.4, 161.1, 8.2]),
        МодельТелефонаМоего("Samsung Galaxy A54", [], 6.4, [76.7, 158.2, 8.2]),
        МодельТелефонаМоего("Samsung Galaxy A36", [], 6.7, [78.2, 162.9, 7.4]),
        МодельТелефонаМоего("Samsung Galaxy A35", [], 6.6, [78.0, 161.7, 8.2]),
        МодельТелефонаМоего("Samsung Galaxy A34", [], 6.6, [78.1, 161.3, 8.2]),
        МодельТелефонаМоего("Samsung Galaxy A26", [], 6.7, [77.5, 164.0, 7.7]),
        МодельТелефонаМоего("Samsung Galaxy A25", [], 6.5, [76.5, 161.0, 8.3]),
        МодельТелефонаМоего("Samsung Galaxy A16", [], 6.7, [77.9, 164.4, 7.9]),
        МодельТелефонаМоего("Samsung Galaxy A15", [], 6.5, [76.8, 160.1, 8.4]),
        МодельТелефонаМоего("Xiaomi Redmi Note 14 Pro+", [], 6.67, [74.7, 162.5, 8.8]),
        МодельТелефонаМоего("Xiaomi Redmi Note 14 Pro", [], 6.67, [74.4, 162.3, 8.2]),
        МодельТелефонаМоего("Xiaomi Redmi Note 14", [], 6.67, [75.7, 163.3, 8.2]),
        МодельТелефонаМоего("Xiaomi Redmi Note 13 Pro+", [], 6.67, [74.7, 161.4, 8.9]),
        МодельТелефонаМоего("Xiaomi Redmi Note 13 Pro", [], 6.67, [74.2, 161.2, 8.0]),
        МодельТелефонаМоего("Xiaomi Redmi Note 13", [], 6.67, [75.8, 162.3, 8.0]),
        МодельТелефонаМоего("Xiaomi Redmi Note 12 Pro", [], 6.67, [76.0, 163.0, 8.0]),
        МодельТелефонаМоего("Xiaomi Redmi Note 12", [], 6.67, [76.2, 165.9, 8.0]),
        МодельТелефонаМоего("Xiaomi Redmi 13C", [], 6.74, [78.0, 168.0, 8.1]),
        МодельТелефонаМоего("Xiaomi Poco X6 Pro", [], 6.67, [74.3, 160.5, 8.3]),
        МодельТелефонаМоего("Xiaomi Poco X6", [], 6.67, [74.3, 161.2, 8.0]),
        МодельТелефонаМоего("Honor X8b", [], 6.7, [74.6, 161.0, 6.8]),
        МодельТелефонаМоего("Honor X8a", [], 6.7, [76.6, 166.0, 7.5]),
        МодельТелефонаМоего("Honor X8", [], 6.7, [76.6, 165.2, 7.5]),
        МодельТелефонаМоего("Google Pixel 9", [], 6.3, [72.0, 152.8, 8.5]),
        МодельТелефонаМоего("Google Pixel 8", [], 6.2, [70.8, 150.5, 8.9])
    ]

    static var все: [МодельТелефонаМоего] { iphone + android }

    /// Диагонали для своей модели, которой нет в списке.
    static let диагонали: [Double] = [5.4, 6.1, 6.3, 6.5, 6.7, 6.9]

    static func поКоду(_ код: String) -> МодельТелефонаМоего? {
        iphone.first { $0.коды.contains(код) }
    }

    static func поИмени(_ имя: String) -> МодельТелефонаМоего? {
        let нужное = нормально(имя)
        return все.first { нормально($0.имя) == нужное }
    }

    /// Этот телефон: «iPhone…» из таблицы — модель; iPad, симулятор, незнакомый код — nil (человек выберет сам).
    static func определить() -> ТелефонМоего? {
        let код = ЖелезоУстройства.модель
        guard код.hasPrefix("iPhone"), let модель = поКоду(код) else { return nil }
        return модель.телефон(код: код, сам: true)
    }

    /// Поиск по словам: «15 pro» находит «iPhone 15 Pro» и «iPhone 15 Pro Max», «s24» — «Galaxy S24…».
    static func найти(_ запрос: String) -> [МодельТелефонаМоего] {
        let слова = нормально(запрос).split(separator: " ").map(String.init)
        guard !слова.isEmpty else { return все }
        return все.filter { модель in
            let имя = нормально(модель.имя)
            return слова.allSatisfy { имя.contains($0) }
        }
    }

    /// Строчные, без лишних пробелов; «айфон» — «iphone».
    static func нормально(_ текст: String) -> String {
        var s = текст.lowercased().replacingOccurrences(of: "айфон", with: "iphone")
        s = s.replacingOccurrences(of: "самсунг", with: "samsung").replacingOccurrences(of: "редми", with: "redmi")
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Выбор телефона

/// Поиск модели: этот телефон (если определён), все iPhone, частые Android; «Нет в списке: «…»» — своя модель с
/// диагональю.
struct ВыборТелефонаМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""
    @State private var диагональ: Double? = nil

    init() {}

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    private var запрос: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var найденные: [МодельТелефонаМоего] { КаталогТелефоновМоего.найти(запрос) }

    /// Набранное не совпало с моделью из списка целиком — можно взять как есть.
    private var своя: String? {
        guard запрос.count >= 2 else { return nil }
        return КаталогТелефоновМоего.поИмени(запрос) == nil ? String(запрос.prefix(60)) : nil
    }

    var body: some View {
        NavigationStack {
            List {
                if let своя {
                    разделСвоей(своя)
                }
                if запрос.isEmpty, let этот = КаталогТелефоновМоего.определить() {
                    Section {
                        строка(имя: String(format: т("md_phone_auto"), этот.модель), диагональ: этот.диагональ,
                               выбран: хранилище.запись.телефон?.модель == этот.модель) {
                            выбрать(этот)
                        }
                    }
                }
                раздел("iPhone", найденные.filter { !$0.коды.isEmpty })
                раздел("Android", найденные.filter { $0.коды.isEmpty })
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .searchable(text: $поиск, placement: .navigationBarDrawer(displayMode: .always), prompt: т("md_phone_search"))
            .autocorrectionDisabled()
            .navigationTitle(т("md_phone"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    @ViewBuilder
    private func раздел(_ заголовок: String, _ модели: [МодельТелефонаМоего]) -> some View {
        if !модели.isEmpty {
            Section(заголовок) {
                ForEach(модели) { модель in
                    строка(имя: модель.имя, диагональ: модель.диагональ,
                           выбран: хранилище.запись.телефон?.модель == модель.имя) {
                        let этот = КаталогТелефоновМоего.определить()
                        выбрать(этот?.модель == модель.имя ? (этот ?? модель.телефон()) : модель.телефон())
                    }
                }
            }
        }
    }

    private func разделСвоей(_ своя: String) -> some View {
        Section {
            Button {
                выбрать(ТелефонМоего(модель: своя, диагональ: диагональ))
            } label: {
                Label(String(format: т("md_phone_other"), своя), systemImage: "pencil")
            }
            ПотокЧипов(зазор: 8) {
                ForEach(КаталогТелефоновМоего.диагонали, id: \.self) { д in
                    ЧипМоего(ЧислоМоего.ч(д) + "″", выбран: диагональ == д) {
                        ОткликСайта.выбор()
                        диагональ = диагональ == д ? nil : д
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(т("md_diag"))
        }
    }

    private func строка(имя: String, диагональ: Double?, выбран: Bool, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Text(имя)
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                if let диагональ {
                    Text(ЧислоМоего.ч(диагональ, знаков: 2) + "″")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                }
                if выбран {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    private func выбрать(_ телефон: ТелефонМоего) {
        хранилище.задатьТелефон(телефон)
        ОткликСайта.успех()
        закрыть()
    }
}
