import SwiftUI

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР»: ЧАСТИ И ПАНЕЛЬ ЧАСТИ (владелец 16.10.2026: «мой компьютер — видюха или ОЗУ»; «стандарты =
 удобство: не пустые поля, а выбор по стандартам, шаблоны, камера»).

 Часть — кнопка живой схемы (MyThingsPCScheme.swift) и вкладка ленты частей под ней: процессор и сокет, память со
 слотами, видеокарта, блок питания, накопители (слоты M.2 и отсеки 2.5″), корпус; у ноутбука — процессор, память
 («распаяна? да · нет · не знаю»), накопители и видеокарта (не меняется). Панель под схемой — выбор чипами из каталога
 (КаталогСтандартов): поколения, формы и частоты памяти, ряды ватт, длины M.2, форм-факторы плат; шаблоны каталога —
 одним касанием; свои числа — полем (длина карты, пределы корпуса). Повторное касание выбранного чипа — «не знаю»
 (nil, а не ноль). Правка — сразу в МоёХранилище через привязку экрана; история «поставили · заменили» пишется при
 уходе с экрана (ИсторияКомпьютераМоего, MyThingsPCHistory.swift), а не на каждое касание.
 */

// MARK: - Части

enum ЧастьКомпьютераМоего: String, CaseIterable, Identifiable, Hashable, Sendable {
    case процессор = "cpu"
    case память = "ram"
    case видеокарта = "gpu"
    case бп = "psu"
    case накопители = "drives"
    case корпус = "case"

    var id: String { rawValue }

    /// Части вида: у ноутбука нет своего блока питания и корпуса.
    static func части(_ вид: ВидКомпьютераМоего) -> [ЧастьКомпьютераМоего] {
        вид == .ноутбук ? [.процессор, .память, .накопители, .видеокарта] : allCases
    }

    var название: String { МойКомпьютерText.т("mpc_part_" + rawValue) }

    var значок: String {
        switch self {
        case .процессор: return "cpu"
        case .память: return "memorychip"
        case .видеокарта: return "rectangle.3.group"
        case .бп: return "bolt"
        case .накопители: return "internaldrive"
        case .корпус: return "pc"
        }
    }

    /// Заполнена ли часть — точка на вкладке.
    func заполнена(_ к: КомпьютерМоего) -> Bool {
        switch self {
        case .процессор: return к.естьПроцессор
        case .память: return к.естьПамять
        case .видеокарта: return !к.видеокарта.пусто
        case .бп: return к.бп.ватт != nil
        case .накопители: return к.естьНакопитель
        case .корпус: return к.корпус.длинаКарты != nil || к.корпус.плата != nil
        }
    }

    /// Значение части для глаз и VoiceOver: «Ryzen 5 5600 · AM4», «16 ГБ · DDR4 · SO-DIMM · 2 из 2»; ничего — nil.
    func значение(_ к: КомпьютерМоего) -> String? {
        let части: [String]
        switch self {
        case .процессор: части = Self.поПроцессору(к)
        case .память: части = Self.поПамяти(к.память)
        case .видеокарта: части = Self.поКарте(к.видеокарта)
        case .бп: части = Self.поБП(к.бп)
        case .накопители: части = Self.поНакопителям(к)
        case .корпус: части = Self.поКорпусу(к.корпус)
        }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    private static func поПроцессору(_ к: КомпьютерМоего) -> [String] {
        var итог: [String] = []
        let цп = к.процессор.trimmingCharacters(in: .whitespaces)
        if !цп.isEmpty { итог.append(цп) }
        if let с = к.сокетДляСверки { итог.append(с == "BGA" ? МойКомпьютерText.т("mpc_bga") : с) }
        if к.вид == .настольный, let ч = к.чипсет { итог.append(ч) }
        return итог
    }

    private static func поПамяти(_ м: ПамятьКомпьютераМоего) -> [String] {
        var итог: [String] = []
        if let всего = м.всего { итог.append(ФорматКомпьютераМоего.гб(всего)) }
        if let п = м.поколение { итог.append(п) }
        if м.всяРаспаяна {
            итог.append(СтандартыText.т("ram_soldered_short"))
        } else {
            if let ф = м.форма { итог.append(ф) }
            if let слотов = м.слотов, слотов > 0 {
                итог.append(String(format: МойКомпьютерText.т("mpc_slots_of"), String(м.планки.count), String(слотов)))
            }
        }
        return итог
    }

    private static func поКарте(_ в: ВидеокартаМоего) -> [String] {
        if в.встроенная && в.чип == nil { return [МойКомпьютерText.т("mpc_gpu_igpu")] }
        var итог: [String] = []
        if let чип = в.чип { итог.append(чип) }
        if let г = в.памятьГБ { итог.append(ФорматКомпьютераМоего.гб(г)) }
        if let д = в.длина { итог.append(ФорматКомпьютераМоего.мм(д)) }
        return итог
    }

    private static func поБП(_ б: БлокПитанияМоего) -> [String] {
        var итог: [String] = []
        if let в = б.ватт { итог.append(ФорматКомпьютераМоего.ватт(в)) }
        if let с = б.сертификат { итог.append(с) }
        if let ф = б.форма, ф != "ATX" { итог.append(ф) }
        return итог
    }

    private static func поНакопителям(_ к: КомпьютерМоего) -> [String] {
        var итог = к.накопители.prefix(2).map { ФорматКомпьютераМоего.диск($0) }
        if к.накопители.count > 2 { итог.append("+" + String(к.накопители.count - 2)) }
        if !к.слотыM2.isEmpty {
            let свободно = к.слотыM2.filter { !$0.занят }.count
            итог.append(String(format: МойКомпьютерText.т("mpc_m2_free_of"), String(свободно), String(к.слотыM2.count)))
        }
        return итог
    }

    private static func поКорпусу(_ к: КорпусМоего) -> [String] {
        var итог: [String] = []
        if let п = к.плата { итог.append(п) }
        if let д = к.длинаКарты { итог.append(String(format: СтандартыText.т("u_gpu_upto"), String(д))) }
        return итог
    }
}

// MARK: - Формат

/// Подписи чисел «Моего компьютера»: «16 ГБ», «512 ГБ», «1 ТБ», «650 Вт», «240 мм», «16 окт 2026».
enum ФорматКомпьютераМоего {
    static func гб(_ x: Int) -> String { String(x) + " " + СтандартыText.т("u_gb") }

    static func объём(_ тб: Double) -> String {
        if тб < 1 { return ЧислоМоего.ч(тб * 1000, знаков: 0) + " " + СтандартыText.т("u_gb") }
        return ЧислоМоего.ч(тб) + " " + СтандартыText.т("u_tb")
    }

    static func ватт(_ x: Int) -> String { String(x) + " " + СтандартыText.т("u_w") }

    static func мм(_ x: Int) -> String { String(x) + " " + СтандартыText.т("u_mm") }

    /// «SSD 1 ТБ», «HDD 2 ТБ».
    static func диск(_ н: НакопительМоего) -> String {
        var итог = н.hdd ? "HDD" : "SSD"
        if let тб = н.тб { итог += " " + объём(тб) }
        return итог
    }

    /// «M.2 2280», «2.5″».
    static func форма(_ код: String) -> String {
        код.hasPrefix("22") ? "M.2 " + код : код + "″"
    }

    /// «NVMe», «SATA», «NVMe и SATA».
    static func протокол(_ код: String?) -> String {
        switch код {
        case "nvme": return "NVMe"
        case "sata": return "SATA"
        case "both": return МойКомпьютерText.т("mpc_proto_both")
        default: return МойКомпьютерText.т("mpc_dont_know")
        }
    }

    /// Разъём питания видеокарты для чипа: «8-pin», «без доп. питания».
    static func разъём(_ код: String) -> String {
        switch код {
        case "none": return МойКомпьютерText.т("mpc_power_none")
        case "6pin": return "6-pin"
        case "8pin": return "8-pin"
        case "2x8pin": return "2×8-pin"
        case "3x8pin": return "3×8-pin"
        default: return код
        }
    }

    /// Форматтеры даты на четыре языка — один раз.
    private static let форматтеры: [String: DateFormatter] = {
        var итог: [String: DateFormatter] = [:]
        for (язык, место) in [("ru", "ru_RU"), ("kk", "kk_KZ"), ("en", "en_US"), ("ar", "ar")] {
            let ф = DateFormatter()
            ф.locale = Locale(identifier: место)
            ф.dateFormat = "d MMM yyyy"
            итог[язык] = ф
        }
        return итог
    }()

    /// «16 окт 2026» на языке приложения.
    static func дата(_ д: Date) -> String {
        let ф = форматтеры[ПримерочнаяText.язык] ?? форматтеры["ru"]
        return (ф?.string(from: д) ?? "").replacingOccurrences(of: ".", with: "")
    }
}

// MARK: - Общие части панели

/// Группа чипов панели: подпись, поток чипов, пояснение под ними.
struct ГруппаЧиповКомпьютераМоего<Чипы: View>: View {
    let заголовок: String
    let подсказка: String?
    let чипы: Чипы

    init(_ заголовок: String, подсказка: String? = nil, @ViewBuilder чипы: () -> Чипы) {
        self.заголовок = заголовок
        self.подсказка = подсказка
        self.чипы = чипы()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(заголовок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ПотокЧипов(зазор: 8) {
                чипы
            }
            if let подсказка {
                Text(подсказка)
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Выбор меню в виде чипа: «2280 ▾», «NVMe ▾», «Слот 1 · 8 ГБ ▾». Невыбранное — серым.
struct МенюЧипКомпьютераМоего<Пункты: View>: View {
    let текст: String
    let выбран: Bool
    let подпись: String
    let пункты: Пункты

    init(_ текст: String, выбран: Bool = true, подпись: String, @ViewBuilder пункты: () -> Пункты) {
        self.текст = текст
        self.выбран = выбран
        self.подпись = подпись
        self.пункты = пункты()
    }

    var body: some View {
        Menu {
            пункты
        } label: {
            HStack(spacing: 4) {
                Text(текст)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(выбран ? Theme.акцент : Theme.текстВторой)
            .padding(.horizontal, 11)
            .frame(minHeight: 36)
            .background(Theme.оттенокАкцента, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .accessibilityLabel(подпись)
        .accessibilityValue(текст)
    }
}

/// Строка-пояснение на подложке: «Процессор ноутбука распаян — не меняется».
struct ЗаметкаКомпьютераМоего: View {
    let текст: String
    let значок: String

    init(_ текст: String, значок: String) {
        self.текст = текст
        self.значок = значок
    }

    var body: some View {
        Label {
            Text(текст)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: значок)
                .foregroundStyle(Theme.акцент)
        }
        .font(.footnote)
        .foregroundStyle(Theme.текстВторой)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

/// Текстовое поле: набранное принимается по «Готово» и когда поле теряет фокус (не на каждую букву).
struct ПолеТекстаКомпьютераМоего: View {
    let заголовок: String
    let подсказка: String
    let значение: String
    let предел: Int
    let принять: (String) -> Void
    @State private var текст = ""
    @FocusState private var фокус: Bool

    init(заголовок: String, подсказка: String, значение: String, предел: Int, принять: @escaping (String) -> Void) {
        self.заголовок = заголовок
        self.подсказка = подсказка
        self.значение = значение
        self.предел = предел
        self.принять = принять
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityHidden(true)
            TextField(подсказка, text: $текст)
                .focused($фокус)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { сдать() }
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(фокус ? Theme.акцент : Theme.линия, lineWidth: фокус ? 2 : 1)
                }
                .accessibilityLabel(заголовок)
        }
        .animation(ДвижениеСайта.выбор, value: фокус)
        .onAppear { текст = значение }
        .onChange(of: значение) { _, новое in
            if !фокус { текст = новое }
        }
        .onChange(of: фокус) { _, стало in
            if !стало { сдать() }
        }
        .onDisappear {
            if фокус { сдать() }
        }
    }

    private func сдать() {
        let чистый = String(текст.trimmingCharacters(in: .whitespacesAndNewlines).prefix(предел))
        текст = чистый
        if чистый != значение { принять(чистый) }
    }
}

/// Заголовок подгруппы панели (без чипов): «Слоты M.2», «Накопители».
private struct ПодписьГруппыКомпьютераМоего: View {
    let текст: String

    init(_ текст: String) {
        self.текст = текст
    }

    var body: some View {
        Text(текст)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.текст)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Панель части

/// Панель выбранной части под схемой: заголовок с текущим значением и выбор чипами.
struct ПанельЧастиКомпьютераМоего: View {
    let часть: ЧастьКомпьютераМоего
    @Binding var компьютер: КомпьютерМоего

    init(часть: ЧастьКомпьютераМоего, компьютер: Binding<КомпьютерМоего>) {
        self.часть = часть
        _компьютер = компьютер
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            заголовок
            редактор
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var заголовок: some View {
        HStack(spacing: 10) {
            ЗначокПрофиляМоего(значок: часть.значок, цвет: РазделМоего.компьютер.цвет, размер: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(часть.название)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                Text(часть.значение(компьютер) ?? МойКомпьютерText.т("mpc_unset"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(ДвижениеСайта.смена, value: часть.значение(компьютер))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var редактор: some View {
        switch часть {
        case .процессор:
            РедакторПроцессораМоего(компьютер: $компьютер)
        case .память:
            РедакторПамятиМоего(компьютер: $компьютер)
        case .видеокарта:
            РедакторВидеокартыМоего(компьютер: $компьютер)
        case .бп:
            РедакторБлокаПитанияМоего(компьютер: $компьютер)
        case .накопители:
            РедакторНакопителейМоего(компьютер: $компьютер)
        case .корпус:
            РедакторКорпусаМоего(компьютер: $компьютер)
        }
    }
}

// MARK: - Процессор

private struct РедакторПроцессораМоего: View {
    @Binding var компьютер: КомпьютерМоего
    @State private var найдено: String? = nil

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ПолеТекстаКомпьютераМоего(заголовок: т("mpc_cpu_model"), подсказка: т("mpc_cpu_ph"),
                                          значение: компьютер.процессор, предел: 60) { новый in
                    принять(новый)
                }
                if let найдено {
                    Label(найдено, systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                        .transition(.opacity)
                }
            }
            .animation(ДвижениеСайта.смена, value: найдено)
            if компьютер.вид == .ноутбук {
                ЗаметкаКомпьютераМоего(т("mpc_cpu_laptop"), значок: "lock")
            } else {
                сокеты
                чипсеты
                тепло
            }
        }
    }

    /// Модель процессора: по ней — сокет («Ryzen 5 5600» → AM4), у ноутбука и Apple — BGA.
    private func принять(_ новый: String) {
        var к = компьютер
        к.процессор = новый
        найдено = nil
        let нормальный = " " + РазборСтандартов.нормально(новый) + " "
        if let цп = РазборСтандартов.процессор(нормальный) {
            if цп.сокет == "BGA" {
                if к.вид == .ноутбук { к.сокет = "BGA" }
            } else if к.вид == .настольный {
                к.сокет = цп.сокет
                if let ч = к.чипсет, КаталогСтандартов.сокет(чипсета: ч) != цп.сокет { к.чипсет = nil }
                найдено = String(format: т("mpc_socket_found"), цп.сокет)
            }
        } else if нормальный.contains("apple m") {
            к.сокет = "BGA"
        }
        компьютер = к
    }

    private var подсказкаСокета: String {
        guard let с = КаталогСтандартов.сокет(компьютер.сокетДляСверки), с.код != "BGA" else { return т("mpc_socket_hint") }
        return с.процессоры + " · " + с.память.joined(separator: " / ")
    }

    private var сокеты: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_socket"), подсказка: подсказкаСокета) {
            ForEach(КаталогСтандартов.сокеты.filter { $0.код != "BGA" }, id: \.код) { с in
                ЧипМоего(с.код, выбран: компьютер.сокетДляСверки == с.код) {
                    выбратьСокет(с.код)
                }
            }
        }
    }

    private func выбратьСокет(_ код: String) {
        ОткликСайта.выбор()
        var к = компьютер
        if к.сокетДляСверки == код {
            к.сокет = nil
            к.чипсет = nil
        } else {
            к.сокет = код
            if let ч = к.чипсет, КаталогСтандартов.сокет(чипсета: ч) != код { к.чипсет = nil }
        }
        компьютер = к
    }

    @ViewBuilder
    private var чипсеты: some View {
        if let с = КаталогСтандартов.сокет(компьютер.сокетДляСверки), !с.чипсеты.isEmpty {
            ГруппаЧиповКомпьютераМоего(т("mpc_chipset"), подсказка: т("mpc_chipset_hint")) {
                ForEach(с.чипсеты, id: \.self) { ч in
                    ЧипМоего(ч, выбран: компьютер.чипсет == ч) {
                        ОткликСайта.выбор()
                        var к = компьютер
                        к.чипсет = к.чипсет == ч ? nil : ч
                        if к.сокет == nil { к.сокет = с.код }
                        компьютер = к
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private var тепло: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_tdp"), подсказка: т("mpc_tdp_hint")) {
            ForEach([35, 65, 105, 125, 170], id: \.self) { вт in
                ЧипМоего(ФорматКомпьютераМоего.ватт(вт), выбран: компьютер.tdp == вт) {
                    ОткликСайта.выбор()
                    var к = компьютер
                    к.tdp = к.tdp == вт ? nil : вт
                    компьютер = к
                }
            }
        }
    }
}

// MARK: - Память

private struct РедакторПамятиМоего: View {
    @Binding var компьютер: КомпьютерМоего

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var м: ПамятьКомпьютераМоего { компьютер.память }
    private var ноутбук: Bool { компьютер.вид == .ноутбук }

    private enum Распайка {
        case да
        case нет
        case неЗнаю
    }

    private var распайка: Распайка {
        if м.всяРаспаяна || (м.распаяно ?? 0) > 0 { return .да }
        if let с = м.слотов, с > 0 { return .нет }
        return .неЗнаю
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ноутбук { распаяна }
            if !м.всяРаспаяна { шаблоны }
            поколения
            if !м.всяРаспаяна {
                формы
                частоты
                слоты
                планки
                максимум
            }
        }
        .animation(ДвижениеСайта.смена, value: м.всяРаспаяна)
    }

    private func изменить(_ правка: (inout ПамятьКомпьютераМоего) -> Void) {
        ОткликСайта.выбор()
        var к = компьютер
        правка(&к.память)
        к.память.нормализовать()
        компьютер = к
    }

    // MARK: Распаяна ли

    private var распаяна: some View {
        VStack(alignment: .leading, spacing: 12) {
            ГруппаЧиповКомпьютераМоего(т("mpc_ram_soldered_q"), подсказка: т("mpc_ram_soldered_hint")) {
                ЧипМоего(т("mpc_yes"), выбран: распайка == .да) { задатьРаспайку(.да) }
                ЧипМоего(т("mpc_no"), выбран: распайка == .нет) { задатьРаспайку(.нет) }
                ЧипМоего(т("mpc_dont_know"), выбран: распайка == .неЗнаю) { задатьРаспайку(.неЗнаю) }
            }
            if распайка == .да {
                ГруппаЧиповКомпьютераМоего(т("mpc_ram_soldered_gb")) {
                    ForEach([4, 8, 16, 24, 32], id: \.self) { гб in
                        ЧипМоего(ФорматКомпьютераМоего.гб(гб), выбран: м.распаяно == гб) {
                            изменить { $0.распаяно = гб }
                        }
                    }
                }
                .transition(.opacity)
                ГруппаЧиповКомпьютераМоего(т("mpc_ram_extra_slot")) {
                    ЧипМоего(т("mpc_no"), выбран: м.всяРаспаяна) { одинСлот(false) }
                    ЧипМоего(т("mpc_ram_one_slot"), выбран: !м.всяРаспаяна) { одинСлот(true) }
                }
                .transition(.opacity)
            }
        }
    }

    private func задатьРаспайку(_ новая: Распайка) {
        изменить { п in
            switch новая {
            case .да:
                п.распаяно = п.распаяно ?? п.всего ?? 8
                п.планки = []
                п.слотов = 0
                п.форма = "soldered"
            case .нет:
                п.распаяно = nil
                if п.форма == "soldered" { п.форма = nil }
                if let г = п.поколение, КаталогСтандартов.распаянныеПоколения.contains(г) { п.поколение = nil }
                if (п.слотов ?? 0) == 0 { п.слотов = 2 }
                if п.форма == nil { п.форма = "SO-DIMM" }
            case .неЗнаю:
                п.распаяно = nil
                if п.форма == "soldered" { п.форма = nil }
                if let г = п.поколение, КаталогСтандартов.распаянныеПоколения.contains(г) { п.поколение = nil }
                if п.слотов == 0 { п.слотов = nil }
            }
        }
    }

    /// Распаяно и ещё один слот (часть ноутбуков: 8 ГБ на плате + SO-DIMM).
    private func одинСлот(_ есть: Bool) {
        изменить { п in
            if есть {
                п.слотов = 1
                if п.форма == nil || п.форма == "soldered" { п.форма = "SO-DIMM" }
                if let г = п.поколение, КаталогСтандартов.распаянныеПоколения.contains(г) { п.поколение = nil }
                п.планки = Array(п.планки.prefix(1))
            } else {
                п.слотов = 0
                п.планки = []
                п.форма = "soldered"
            }
        }
    }

    // MARK: Шаблоны и поколение

    private var шаблоны: some View {
        let ключ = ноутбук ? "pr_ram_laptop" : "pr_ram_pc"
        let список = КаталогСтандартов.шаблоны(.память).filter { $0.пояснение == ключ }
        return ГруппаЧиповКомпьютераМоего(т("mpc_templates"), подсказка: т("mpc_ram_tpl_hint")) {
            ForEach(список) { ш in
                ЧипМоего(ш.подпись, выбран: подходит(ш), значок: "square.grid.2x2") {
                    применить(ш)
                }
            }
        }
    }

    private func подходит(_ ш: КаталогСтандартов.ШаблонСтандарта) -> Bool {
        м.поколение == ш.поля[КлючСтандарта.поколение] && м.форма == ш.поля[КлючСтандарта.форма]
            && м.частота.map { String($0) } == ш.поля[КлючСтандарта.частота]
    }

    /// Шаблон ставит поколение, форму и частоту; планки и слоты — свои.
    private func применить(_ ш: КаталогСтандартов.ШаблонСтандарта) {
        let слотовОбычно = ноутбук ? 2 : 4
        изменить { п in
            п.поколение = ш.поля[КлючСтандарта.поколение]
            п.форма = ш.поля[КлючСтандарта.форма]
            п.частота = ш.поля[КлючСтандарта.частота].flatMap { Int($0) }
            п.распаяно = nil
            if (п.слотов ?? 0) == 0 { п.слотов = слотовОбычно }
        }
    }

    private var списокПоколений: [String] {
        ноутбук ? ["DDR3", "DDR3L", "DDR4", "DDR5", "LPDDR4X", "LPDDR5", "LPDDR5X"] : ["DDR3", "DDR4", "DDR5"]
    }

    private var поколения: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_ram_gen"), подсказка: м.всяРаспаяна ? т("mpc_ram_lp_hint") : nil) {
            ForEach(списокПоколений, id: \.self) { п in
                ЧипМоего(п, выбран: м.поколение == п) {
                    выбратьПоколение(п)
                }
            }
        }
    }

    private func выбратьПоколение(_ п: String) {
        изменить { память in
            if память.поколение == п {
                память.поколение = nil
                return
            }
            память.поколение = п
            if КаталогСтандартов.распаянныеПоколения.contains(п) {
                память.распаяно = память.распаяно ?? память.всего ?? 8
                память.планки = []
                память.слотов = 0
                память.форма = "soldered"
                память.частота = nil
            } else if let ч = память.частота, !РедакторПамятиМоего.рядЧастот(п).contains(ч) {
                память.частота = nil
            }
        }
    }

    // MARK: Форма, частота, слоты

    private var формы: some View {
        let список = ноутбук ? ["SO-DIMM", "CAMM2"] : ["DIMM", "SO-DIMM"]
        let подсказка = т(ноутбук ? "mpc_ram_form_laptop" : "mpc_ram_form_pc")
        return ГруппаЧиповКомпьютераМоего(т("mpc_ram_form"), подсказка: подсказка) {
            ForEach(список, id: \.self) { ф in
                ЧипМоего(ф, выбран: м.форма == ф) {
                    изменить { $0.форма = $0.форма == ф ? nil : ф }
                }
            }
        }
    }

    /// Частоты поколения: DDR3 — до 2133, DDR4 — 2133…3600, DDR5 — от 4800; распаянная LPDDR — без выбора.
    static func рядЧастот(_ поколение: String?) -> [Int] {
        let все = КаталогСтандартов.частотыПамяти
        guard let поколение else { return все }
        if КаталогСтандартов.распаянныеПоколения.contains(поколение) { return [] }
        switch КаталогСтандартов.основа(поколения: поколение) {
        case "DDR3": return все.filter { $0 <= 2133 }
        case "DDR4": return все.filter { (2133...3600).contains($0) }
        case "DDR5": return все.filter { $0 >= 4800 }
        default: return все
        }
    }

    @ViewBuilder
    private var частоты: some View {
        let список = Self.рядЧастот(м.поколение)
        if !список.isEmpty {
            ГруппаЧиповКомпьютераМоего(т("mpc_ram_mts"), подсказка: т("mpc_ram_mts_hint")) {
                ForEach(список, id: \.self) { ч in
                    ЧипМоего(String(ч), выбран: м.частота == ч) {
                        изменить { $0.частота = $0.частота == ч ? nil : ч }
                    }
                }
            }
        }
    }

    private var слоты: some View {
        let список = ноутбук ? [1, 2] : [2, 4]
        return ГруппаЧиповКомпьютераМоего(т("mpc_ram_slots"), подсказка: т("mpc_ram_slots_hint")) {
            ForEach(список, id: \.self) { n in
                ЧипМоего(String(n), выбран: м.слотов == n) {
                    изменить { п in
                        if п.слотов == n {
                            п.слотов = nil
                        } else {
                            п.слотов = n
                            п.планки = Array(п.планки.prefix(n))
                        }
                    }
                }
            }
        }
    }

    private var планки: some View {
        let слотов = м.слотов ?? min(4, max(1, м.планки.count + 1))
        return VStack(alignment: .leading, spacing: 8) {
            ПодписьГруппыКомпьютераМоего(т("mpc_ram_sticks"))
            ПотокЧипов(зазор: 8) {
                ForEach(0..<max(1, слотов), id: \.self) { номер in
                    планка(номер)
                }
            }
        }
    }

    private func планка(_ номер: Int) -> some View {
        let есть = номер < м.планки.count
        let слот = String(format: т("mpc_ram_slot_n"), String(номер + 1))
        let объём = есть ? ФорматКомпьютераМоего.гб(м.планки[номер]) : т("mpc_slot_empty")
        return МенюЧипКомпьютераМоего(слот + " · " + объём, выбран: есть, подпись: слот) {
            ForEach(КаталогСтандартов.объёмыМодуля, id: \.self) { гб in
                Button(ФорматКомпьютераМоего.гб(гб)) {
                    поставитьПланку(номер, гб)
                }
            }
            if есть {
                Button(т("mpc_slot_empty"), role: .destructive) {
                    поставитьПланку(номер, nil)
                }
            }
        }
    }

    private func поставитьПланку(_ номер: Int, _ гб: Int?) {
        изменить { п in
            if let гб {
                if номер < п.планки.count {
                    п.планки[номер] = гб
                } else {
                    п.планки.append(гб)
                }
            } else if номер < п.планки.count {
                п.планки.remove(at: номер)
            }
        }
    }

    private var максимум: some View {
        let список = ноутбук ? [16, 32, 64] : [32, 64, 128, 192]
        return ГруппаЧиповКомпьютераМоего(т("mpc_ram_max"), подсказка: т("mpc_ram_max_hint")) {
            ForEach(список, id: \.self) { гб in
                ЧипМоего(ФорматКомпьютераМоего.гб(гб), выбран: м.максимум == гб) {
                    изменить { $0.максимум = $0.максимум == гб ? nil : гб }
                }
            }
            ЧипМоего(т("mpc_dont_know"), выбран: м.максимум == nil) {
                изменить { $0.максимум = nil }
            }
        }
    }
}

// MARK: - Видеокарта

private struct РедакторВидеокартыМоего: View {
    @Binding var компьютер: КомпьютерМоего

    /// Частые чипы — чипами; прочее — полем.
    private static let частые = ["GTX 1650", "RTX 3050", "RTX 3060", "RTX 4060", "RTX 4060 Ti", "RTX 4070",
                                 "RTX 4070 Super", "RTX 5070", "RX 6600", "RX 7600", "RX 7800 XT"]

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var в: ВидеокартаМоего { компьютер.видеокарта }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if компьютер.вид == .ноутбук {
                ЗаметкаКомпьютераМоего(т("mpc_gpu_laptop"), значок: "lock")
            }
            ПолеТекстаКомпьютераМоего(заголовок: т("mpc_gpu_model"), подсказка: т("mpc_gpu_ph"), значение: в.чип ?? "",
                                      предел: 40) { текст in
                принятьМодель(текст)
            }
            чипы
            if компьютер.вид == .настольный && !(в.встроенная && в.чип == nil) {
                памятьКарты
                длина
                питание
            }
        }
        .animation(ДвижениеСайта.смена, value: в.встроенная)
    }

    private func изменить(_ правка: (inout ВидеокартаМоего) -> Void) {
        ОткликСайта.выбор()
        var к = компьютер
        правка(&к.видеокарта)
        компьютер = к
    }

    /// «MSI RTX 4060 Ventus 8GB» → RTX 4060, 8 ГБ; «Intel UHD Graphics» — встроенная; иначе — как набрано.
    private func принятьМодель(_ текст: String) {
        var к = компьютер
        if текст.isEmpty {
            к.видеокарта.чип = nil
        } else {
            let набор = РазборСтандартов.разобрать(текст: текст, семьи: [.видеокарта], источник: .продавец).набор
            if let найденный = набор[.видеокарта, КлючСтандарта.чип] {
                к.видеокарта.чип = найденный
                к.видеокарта.встроенная = false
                if к.видеокарта.памятьГБ == nil {
                    к.видеокарта.памятьГБ = набор.целое(.видеокарта, КлючСтандарта.памятьКарты)
                }
            } else if Self.встроенная(текст) {
                к.видеокарта.чип = nil
                к.видеокарта.встроенная = true
            } else {
                к.видеокарта.чип = String(текст.prefix(40))
                к.видеокарта.встроенная = false
            }
        }
        компьютер = к
    }

    /// Встроенная графика по названию: Intel UHD / Iris, Radeon Graphics, Vega, Apple.
    static func встроенная(_ текст: String) -> Bool {
        let н = текст.lowercased()
        return ["uhd", "iris", "radeon graphics", "radeon(tm) graphics", "vega", "intel graphics", "apple"]
            .contains { н.contains($0) }
    }

    private var чипы: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_gpu_pick")) {
            ЧипМоего(т("mpc_gpu_igpu"), выбран: в.встроенная && в.чип == nil) {
                изменить { карта in
                    if карта.встроенная && карта.чип == nil {
                        карта.встроенная = false
                    } else {
                        карта.встроенная = true
                        карта.чип = nil
                        карта.длина = nil
                        карта.питание = nil
                        карта.памятьГБ = nil
                    }
                }
            }
            if компьютер.вид == .настольный {
                ForEach(Self.частые, id: \.self) { чип in
                    ЧипМоего(чип, выбран: в.чип == чип) {
                        изменить { карта in
                            карта.чип = карта.чип == чип ? nil : чип
                            карта.встроенная = false
                        }
                    }
                }
            }
        }
    }

    private var памятьКарты: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_gpu_vram")) {
            ForEach([4, 6, 8, 12, 16, 24], id: \.self) { гб in
                ЧипМоего(ФорматКомпьютераМоего.гб(гб), выбран: в.памятьГБ == гб) {
                    изменить { $0.памятьГБ = $0.памятьГБ == гб ? nil : гб }
                }
            }
        }
    }

    private var длина: some View {
        ПолеЧислаМоего(заголовок: т("mpc_gpu_len"), единица: СтандартыText.т("u_mm"),
                       значение: Binding(get: { компьютер.видеокарта.длина.map { Double($0) } },
                                         set: { новое in
                                             var к = компьютер
                                             к.видеокарта.длина = новое.map { Int($0.rounded()) }
                                             компьютер = к
                                         }),
                       пределы: 60...450, знаков: 0, подсказка: т("mpc_gpu_len_hint"))
    }

    private var питание: some View {
        ГруппаЧиповКомпьютераМоего(т("mpc_gpu_power")) {
            ForEach(КаталогСтандартов.разъёмыПитанияКарт, id: \.self) { код in
                ЧипМоего(ФорматКомпьютераМоего.разъём(код), выбран: в.питание == код) {
                    изменить { $0.питание = $0.питание == код ? nil : код }
                }
            }
        }
    }
}

// MARK: - Блок питания

private struct РедакторБлокаПитанияМоего: View {
    @Binding var компьютер: КомпьютерМоего

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var б: БлокПитанияМоего { компьютер.бп }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            нужно
            ГруппаЧиповКомпьютераМоего(т("mpc_psu_w"), подсказка: т("mpc_psu_w_hint")) {
                ForEach(КаталогСтандартов.ваттыБП, id: \.self) { вт in
                    ЧипМоего(ФорматКомпьютераМоего.ватт(вт), выбран: б.ватт == вт) {
                        изменить { $0.ватт = $0.ватт == вт ? nil : вт }
                    }
                }
            }
            ГруппаЧиповКомпьютераМоего(т("mpc_psu_form")) {
                ForEach(КаталогСтандартов.формыБП, id: \.self) { ф in
                    ЧипМоего(ф, выбран: б.форма == ф) {
                        изменить { $0.форма = $0.форма == ф ? nil : ф }
                    }
                }
            }
            ГруппаЧиповКомпьютераМоего(т("mpc_psu_cert")) {
                ForEach(КаталогСтандартов.сертификатыБП, id: \.self) { с in
                    ЧипМоего(с, выбран: б.сертификат == с) {
                        изменить { $0.сертификат = $0.сертификат == с ? nil : с }
                    }
                }
            }
        }
    }

    private func изменить(_ правка: (inout БлокПитанияМоего) -> Void) {
        ОткликСайта.выбор()
        var к = компьютер
        правка(&к.бп)
        компьютер = к
    }

    /// «Для RTX 3060 нужно от 550 Вт» — эвристика Kliko (КаталогСтандартов.нужноБП), со знаком уровня.
    @ViewBuilder
    private var нужно: some View {
        if let чип = компьютер.видеокарта.чип,
           let нужноВатт = КаталогСтандартов.нужноБП(чип: чип, tdpПроцессора: компьютер.tdp) {
            let знак = Self.уровень(есть: б.ватт, нужно: нужноВатт)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: т("mpc_psu_need"), чип, String(нужноВатт)))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                    Text(т("mpc_psu_need_sub"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: знак.значок)
                    .foregroundStyle(знак.краска)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// Свой БП против нужного: не меньше — подходит, на ступень ниже — проверьте, иначе — нет; не знаем — неизвестно.
    static func уровень(есть: Int?, нужно: Int) -> УровеньСтандарта {
        guard let есть else { return .неизвестно }
        if есть >= нужно { return .подходит }
        if let ниже = КаталогСтандартов.ступеньНиже(нужно), есть >= ниже { return .проверить }
        return .неПодходит
    }
}

// MARK: - Накопители

private struct РедакторНакопителейМоего: View {
    @Binding var компьютер: КомпьютерМоего

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            слотыM2
            отсеки
            диски
        }
        .animation(ДвижениеСайта.вставкаСписка, value: компьютер.слотыM2)
        .animation(ДвижениеСайта.вставкаСписка, value: компьютер.накопители)
    }

    private func изменить(_ правка: (inout КомпьютерМоего) -> Void) {
        ОткликСайта.выбор()
        var к = компьютер
        правка(&к)
        компьютер = к
    }

    // MARK: Слоты M.2

    private var слотыM2: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьГруппыКомпьютераМоего(т("mpc_m2_slots"))
            if компьютер.слотыM2.isEmpty {
                Text(т("mpc_m2_none"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(компьютер.слотыM2.enumerated()), id: \.element.id) { номер, слот in
                строкаСлота(номер, слот)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if компьютер.слотыM2.count < 6 {
                МалаяКнопкаАвтоподбора(заголовок: т("mpc_m2_add"), значок: "plus") {
                    изменить { к in к.слотыM2.append(СлотM2Моего(pcie: к.слотыM2.last?.pcie)) }
                }
            }
        }
    }

    private func изменитьСлот(_ id: UUID, _ правка: (inout СлотM2Моего) -> Void) {
        изменить { к in
            guard let i = к.слотыM2.firstIndex(where: { $0.id == id }) else { return }
            правка(&к.слотыM2[i])
        }
    }

    /// «PCIe 4.0»; поколение не задано — «PCIe ?». Отдельной функцией: склейка с map и ?? в аргументе чипа — риск
    /// проверки типов.
    private func подписьPCIe(_ поколение: Int?) -> String {
        guard let g = поколение else { return "PCIe ?" }
        return "PCIe " + String(g) + ".0"
    }

    private func строкаСлота(_ номер: Int, _ слот: СлотM2Моего) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(format: т("mpc_m2_n"), String(номер + 1)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 8)
                кнопкаУбрать {
                    изменить { к in к.слотыM2.removeAll { $0.id == слот.id } }
                }
            }
            ПотокЧипов(зазор: 6) {
                МенюЧипКомпьютераМоего(слот.длина, подпись: т("mpc_m2_len")) {
                    ForEach(КаталогСтандартов.формыM2, id: \.self) { ф in
                        Button(ф) { изменитьСлот(слот.id) { $0.длина = ф } }
                    }
                }
                МенюЧипКомпьютераМоего(ФорматКомпьютераМоего.протокол(слот.протокол), подпись: т("mpc_m2_proto")) {
                    ForEach(["nvme", "sata", "both"], id: \.self) { п in
                        Button(ФорматКомпьютераМоего.протокол(п)) { изменитьСлот(слот.id) { $0.протокол = п } }
                    }
                }
                МенюЧипКомпьютераМоего(подписьPCIe(слот.pcie), выбран: слот.pcie != nil, подпись: "PCIe") {
                    ForEach(КаталогСтандартов.поколенияPCIe, id: \.self) { g in
                        Button(подписьPCIe(g)) { изменитьСлот(слот.id) { $0.pcie = g } }
                    }
                    Button(т("mpc_dont_know")) { изменитьСлот(слот.id) { $0.pcie = nil } }
                }
                ЧипМоего(слот.занят ? т("mpc_m2_busy") : т("mpc_m2_free"), выбран: слот.занят) {
                    изменитьСлот(слот.id) { $0.занят.toggle() }
                }
            }
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private func кнопкаУбрать(_ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .accessibilityLabel(т("mpc_remove"))
    }

    // MARK: Отсеки 2.5″

    private var отсеки: some View {
        let список = компьютер.вид == .ноутбук ? [0, 1] : [0, 1, 2, 4]
        return ГруппаЧиповКомпьютераМоего(т("mpc_bays"), подсказка: т("mpc_bays_hint")) {
            ForEach(список, id: \.self) { n in
                ЧипМоего(String(n), выбран: компьютер.отсеков25 == n) {
                    изменить { к in к.отсеков25 = к.отсеков25 == n ? nil : n }
                }
            }
        }
    }

    // MARK: Накопители

    private var диски: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьГруппыКомпьютераМоего(т("mpc_drives"))
            if компьютер.накопители.isEmpty {
                Text(т("mpc_drives_none"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(компьютер.накопители) { диск in
                строкаДиска(диск)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if компьютер.накопители.count < 12 {
                добавитьДиск
            }
        }
    }

    private var добавитьДиск: some View {
        Menu {
            ForEach(КаталогСтандартов.шаблоны(.накопитель)) { ш in
                Button(ш.подпись) { добавить(ш.поля) }
            }
            Button("HDD 3.5″ SATA") {
                добавить([КлючСтандарта.форма: "3.5", КлючСтандарта.протокол: "sata"], hdd: true)
            }
        } label: {
            Label(т("mpc_drive_add"), systemImage: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    /// Новый накопитель из шаблона каталога; M.2 занимает свободный слот (нет слотов — появляется занятый).
    private func добавить(_ поля: [String: String], hdd: Bool = false) {
        изменить { к in
            let диск = НакопительМоего(форма: поля[КлючСтандарта.форма] ?? "2280", протокол: поля[КлючСтандарта.протокол],
                                       pcie: поля[КлючСтандарта.pcie].flatMap { Int($0) }, тб: nil, hdd: hdd)
            if КаталогСтандартов.длинаM2(диск.форма) != nil { Self.занятьСлот(&к, под: диск) }
            к.накопители.append(диск)
        }
    }

    static func занятьСлот(_ к: inout КомпьютерМоего, под диск: НакопительМоего) {
        if let i = к.слотыM2.firstIndex(where: { !$0.занят }) {
            к.слотыM2[i].занят = true
        } else if к.слотыM2.count < 6 {
            let протокол = диск.протокол == "sata" ? "sata" : "nvme"
            к.слотыM2.append(СлотM2Моего(длина: диск.форма, протокол: протокол, pcie: диск.pcie, занят: true))
        }
    }

    private func изменитьДиск(_ id: UUID, _ правка: (inout НакопительМоего) -> Void) {
        изменить { к in
            guard let i = к.накопители.firstIndex(where: { $0.id == id }) else { return }
            правка(&к.накопители[i])
        }
    }

    private func строкаДиска(_ диск: НакопительМоего) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(ФорматКомпьютераМоего.диск(диск) + " · " + ФорматКомпьютераМоего.форма(диск.форма))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Spacer(minLength: 8)
                кнопкаУбрать { убрать(диск) }
            }
            ПотокЧипов(зазор: 6) {
                МенюЧипКомпьютераМоего(диск.hdd ? "HDD" : "SSD", подпись: т("mpc_drive_kind")) {
                    Button("SSD") { изменитьДиск(диск.id) { $0.hdd = false } }
                    Button("HDD") {
                        изменитьДиск(диск.id) { д in
                            д.hdd = true
                            д.протокол = "sata"
                            if КаталогСтандартов.длинаM2(д.форма) != nil { д.форма = "3.5" }
                        }
                    }
                }
                МенюЧипКомпьютераМоего(ФорматКомпьютераМоего.форма(диск.форма), подпись: т("mpc_drive_form")) {
                    ForEach(КаталогСтандартов.формыM2 + КаталогСтандартов.формыДисков, id: \.self) { ф in
                        Button(ФорматКомпьютераМоего.форма(ф)) { изменитьДиск(диск.id) { $0.форма = ф } }
                    }
                }
                МенюЧипКомпьютераМоего(диск.тб.map { ФорматКомпьютераМоего.объём($0) } ?? т("mpc_drive_size"),
                                       выбран: диск.тб != nil, подпись: т("mpc_drive_size")) {
                    ForEach(КаталогСтандартов.объёмыНакопителя, id: \.self) { тб in
                        Button(ФорматКомпьютераМоего.объём(тб)) { изменитьДиск(диск.id) { $0.тб = тб } }
                    }
                }
                if !диск.hdd {
                    МенюЧипКомпьютераМоего(ФорматКомпьютераМоего.протокол(диск.протокол), выбран: диск.протокол != nil,
                                           подпись: т("mpc_m2_proto")) {
                        Button("NVMe") { изменитьДиск(диск.id) { $0.протокол = "nvme" } }
                        Button("SATA") { изменитьДиск(диск.id) { $0.протокол = "sata" } }
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// Убрать накопитель; M.2 освобождает занятый слот.
    private func убрать(_ диск: НакопительМоего) {
        изменить { к in
            к.накопители.removeAll { $0.id == диск.id }
            if КаталогСтандартов.длинаM2(диск.форма) != nil, let i = к.слотыM2.lastIndex(where: { $0.занят }) {
                к.слотыM2[i].занят = false
            }
        }
    }
}

// MARK: - Корпус

private struct РедакторКорпусаМоего: View {
    @Binding var компьютер: КомпьютерМоего

    init(компьютер: Binding<КомпьютерМоего>) {
        _компьютер = компьютер
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var к: КорпусМоего { компьютер.корпус }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ГруппаЧиповКомпьютераМоего(т("mpc_case_board"), подсказка: т("mpc_case_board_hint")) {
                ForEach(КаталогСтандартов.формыПлат, id: \.код) { ф in
                    ЧипМоего(ф.код, выбран: к.плата == ф.код) {
                        изменить { $0.плата = $0.плата == ф.код ? nil : ф.код }
                    }
                }
            }
            предел(т("mpc_case_gpu"), т("mpc_case_gpu_hint"), [300, 320, 340, 360, 400], \.длинаКарты, 100...600)
            предел(т("mpc_case_cooler"), т("mpc_case_cooler_hint"), [155, 160, 165, 170], \.высотаКулера, 20...250)
        }
    }

    private func изменить(_ правка: (inout КорпусМоего) -> Void) {
        ОткликСайта.выбор()
        var новый = компьютер
        правка(&новый.корпус)
        компьютер = новый
    }

    /// Предел корпуса: частые значения чипами и своё число полем.
    private func предел(_ заголовок: String, _ подсказка: String, _ частые: [Int],
                        _ путь: WritableKeyPath<КорпусМоего, Int?>, _ пределы: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ПолеЧислаМоего(заголовок: заголовок, единица: СтандартыText.т("u_mm"),
                           значение: Binding(get: { компьютер.корпус[keyPath: путь].map { Double($0) } },
                                             set: { новое in
                                                 var новый = компьютер
                                                 новый.корпус[keyPath: путь] = новое.map { Int($0.rounded()) }
                                                 компьютер = новый
                                             }),
                           пределы: пределы, знаков: 0, подсказка: подсказка)
            ПотокЧипов(зазор: 8) {
                ForEach(частые, id: \.self) { мм in
                    ЧипМоего(String(мм), выбран: компьютер.корпус[keyPath: путь] == мм) {
                        изменить { $0[keyPath: путь] = $0[keyPath: путь] == мм ? nil : мм }
                    }
                }
            }
        }
    }
}
