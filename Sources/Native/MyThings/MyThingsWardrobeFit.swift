import SwiftUI
import UIKit

/**
 «МОЙ ГАРДЕРОБ» — КАК СИДЯТ БРЕНДЫ (владелец: «Zara M — мала в плечах»; docs/SERVER_CIRCLE.md §11.3 — те же три ключа,
 что «Подошло?» сервера: small, ok, large).

 Заметка посадки — бренд, размер как на бирке, «мала / впору / велика» и где («в плечах», «по длине»). Пишется из листа
 вещи (бренд и размер уже есть — остаётся одно касание) или отдельно. Сводка по бренду: чего больше — «маломерит —
 берите на размер больше», «в размер», «большемерит»; поровну — «по-разному»; что впору — «беру M». Одна заметка на
 бренд, вид размера и размер: новая заменяет прежнюю. Только на телефоне (МоёХранилище.обновитьГардероб).
 */

/// Сводка посадки одного бренда: заметки (новые — первыми) и что из них следует.
struct СводкаБрендаГардероба: Identifiable {
    let бренд: String
    let заметки: [ЗаметкаПосадкиМоего]

    var id: String { бренд.lowercased() }

    /// Чего больше; поровну между разными — nil.
    var итог: ПосадкаВещиМоего? {
        let счёт = Dictionary(grouping: заметки, by: \.посадка).mapValues(\.count)
        guard let наибольший = счёт.values.max() else { return nil }
        let лидеры = счёт.filter { $0.value == наибольший }.map(\.key)
        return лидеры.count == 1 ? лидеры[0] : nil
    }

    /// «Маломерит — берите на размер больше», «Сидит в размер», «Большемерит», «По-разному».
    var совет: String {
        switch итог {
        case .мала: return МойГардеробText.т("mw_fit_verdict_small")
        case .впору: return МойГардеробText.т("mw_fit_verdict_ok")
        case .велика: return МойГардеробText.т("mw_fit_verdict_large")
        case nil: return МойГардеробText.т("mw_fit_verdict_mixed")
        }
    }

    /// Размер, который впору (последний), — «беру M».
    var беру: String? { заметки.first { $0.посадка == .впору }?.размер }

    var краска: Color {
        switch итог {
        case .впору: return Theme.акцент
        case .мала, .велика: return Theme.оранжевый
        case nil: return Theme.текстВторой
        }
    }
}

enum ПосадкаГардероба {
    /// Где мала или велика — ключи подписей (в заметку уходит подпись на языке приложения).
    static let где: [String] = ["mw_where_shoulders", "mw_where_chest", "mw_where_waist", "mw_where_hips",
                                "mw_where_length", "mw_where_sleeves", "mw_where_foot"]

    /// Частые бренды одежды и обуви в Казахстане — подсказки поля бренда.
    static let частыеБренды: [String] = [
        "Zara", "H&M", "Mango", "Bershka", "Pull&Bear", "Stradivarius", "Massimo Dutti", "Uniqlo", "LC Waikiki",
        "DeFacto", "Koton", "Reserved", "Colin's", "Gloria Jeans", "Befree", "O'stin", "Nike", "Adidas", "Puma",
        "New Balance", "Reebok", "Asics", "Levi's", "Tommy Hilfiger", "Calvin Klein", "Lacoste", "Guess", "Michael Kors",
        "Skechers", "Ecco", "Converse", "Vans", "The North Face", "Columbia"
    ]

    /// Сводки брендов: свежие — первыми.
    static func бренды(_ г: ГардеробМоего) -> [СводкаБрендаГардероба] {
        var порядок: [String] = []
        var группы: [String: [ЗаметкаПосадкиМоего]] = [:]
        var имена: [String: String] = [:]
        for заметка in г.посадка.sorted(by: { $0.когда > $1.когда }) {
            let ключ = заметка.бренд.trimmingCharacters(in: .whitespaces).lowercased()
            guard !ключ.isEmpty else { continue }
            if группы[ключ] == nil {
                порядок.append(ключ)
                имена[ключ] = заметка.бренд.trimmingCharacters(in: .whitespaces)
            }
            группы[ключ, default: []].append(заметка)
        }
        return порядок.map { СводкаБрендаГардероба(бренд: имена[$0] ?? $0, заметки: группы[$0] ?? []) }
    }

    /// Сводка одного бренда или nil.
    static func сводка(бренда бренд: String, _ г: ГардеробМоего) -> СводкаБрендаГардероба? {
        let заметки = г.заметки(бренда: бренд).sorted { $0.когда > $1.когда }
        guard !заметки.isEmpty else { return nil }
        return СводкаБрендаГардероба(бренд: заметки[0].бренд, заметки: заметки)
    }

    /// Новая заметка заменяет прежнюю того же бренда, вида размера и размера; сверх предела уходят самые старые.
    static func записать(_ заметка: ЗаметкаПосадкиМоего, в г: inout ГардеробМоего) {
        let бренд = заметка.бренд.trimmingCharacters(in: .whitespaces).lowercased()
        let размер = ПравилаРазмераОдежды.ключ(заметка.размер)
        г.посадка.removeAll {
            $0.бренд.trimmingCharacters(in: .whitespaces).lowercased() == бренд
                && ПравилаРазмераОдежды.ключ($0.размер) == размер && $0.вид == заметка.вид
        }
        г.посадка.append(заметка)
        if г.посадка.count > ГардеробМоего.пределЗаметок {
            г.посадка.removeFirst(г.посадка.count - ГардеробМоего.пределЗаметок)
        }
    }

    /// Бренды для подсказок: свои (по частоте), потом частые, начинающиеся с набранного; не больше предела.
    static func подсказки(_ набрано: String, г: ГардеробМоего, предел: Int = 8) -> [String] {
        let н = набрано.trimmingCharacters(in: .whitespaces).lowercased()
        /* Шаги с явными типами: кортеж с ?? и сортировка тернарником по кортежам с метками — риск проверки типов в CI. */
        var счёт: [String: (имя: String, раз: Int)] = [:]
        let всеБренды: [String] = г.вещи.map(\.бренд) + г.посадка.map(\.бренд)
        for имя in всеБренды {
            let чистое = имя.trimmingCharacters(in: .whitespaces)
            guard !чистое.isEmpty else { continue }
            let ключ = чистое.lowercased()
            if let было = счёт[ключ] {
                счёт[ключ] = (имя: было.имя, раз: было.раз + 1)
            } else {
                счёт[ключ] = (имя: чистое, раз: 1)
            }
        }
        let пары: [(имя: String, раз: Int)] = Array(счёт.values)
        let поЧастоте: [(имя: String, раз: Int)] = пары.sorted {
            (а: (имя: String, раз: Int), б: (имя: String, раз: Int)) -> Bool in
            if а.раз != б.раз { return а.раз > б.раз }
            return а.имя < б.имя
        }
        let свои: [String] = поЧастоте.map { (п: (имя: String, раз: Int)) -> String in п.имя }
        var итог: [String] = []
        for имя in свои + частыеБренды where !итог.contains(where: { $0.lowercased() == имя.lowercased() }) {
            if н.isEmpty || имя.lowercased().hasPrefix(н) { итог.append(имя) }
            if итог.count >= предел { break }
        }
        return итог.filter { $0.lowercased() != н }
    }
}

// MARK: - Выбор посадки

/// «Как сидит?» — три чипа и, если мала или велика, где именно (чипами, одно касание).
struct ВыборПосадкиГардероба: View {
    @Binding var посадка: ПосадкаВещиМоего?
    @Binding var где: String

    init(посадка: Binding<ПосадкаВещиМоего?>, где: Binding<String>) {
        _посадка = посадка
        _где = где
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(ПосадкаВещиМоего.allCases, id: \.self) { п in
                    ЧипМоего(т("mw_fit_" + п.rawValue), выбран: посадка == п) {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) {
                            посадка = посадка == п ? nil : п
                            if посадка == .впору || посадка == nil { где = "" }
                        }
                    }
                }
            }
            if посадка == .мала || посадка == .велика {
                ПотокЧипов(зазор: 6) {
                    ForEach(ПосадкаГардероба.где, id: \.self) { ключ in
                        let подпись = т(ключ)
                        ЧипМоего(подпись, выбран: где == подпись) {
                            ОткликСайта.выбор()
                            где = где == подпись ? "" : подпись
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(ДвижениеСайта.смена, value: посадка)
    }
}

// MARK: - Карточка на экране

/// «Как сидят бренды»: до шести брендов строками (бренд, совет, последняя заметка) и «Добавить заметку». Экран ставит
/// карточку, только когда она видна (у вещи есть бренд или есть заметка) или гардероб полон; иначе «Добавить заметку» —
/// в листе «Шаблоном».
struct КарточкаПосадкиГардероба: View {
    let гардероб: ГардеробМоего
    let открыть: (String?) -> Void

    init(гардероб: ГардеробМоего, открыть: @escaping (String?) -> Void) {
        self.гардероб = гардероб
        self.открыть = открыть
    }

    /// Карточка на экране: есть заметка посадки или хотя бы у одной вещи записан бренд.
    static func видна(_ г: ГардеробМоего) -> Bool {
        guard г.посадка.isEmpty else { return true }
        return г.вещи.contains { (в: ВещьГардеробаМоего) -> Bool in
            !в.бренд.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    var body: some View {
        let сводки = ПосадкаГардероба.бренды(гардероб)
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mw_fit_title"), значок: "ruler")
            if сводки.isEmpty {
                Text(т("mw_fit_empty"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(сводки.prefix(6))) { сводка in
                        строка(сводка)
                        if сводка.id != сводки.prefix(6).last?.id {
                            Divider().overlay(Theme.линия)
                        }
                    }
                }
            }
            МалаяКнопкаАвтоподбора(заголовок: т("mw_fit_add"), значок: "plus") {
                ОткликСайта.выбор()
                открыть(nil)
            }
        }
        .карточкаМоего()
    }

    private func строка(_ сводка: СводкаБрендаГардероба) -> some View {
        Button {
            ОткликСайта.выбор()
            открыть(сводка.бренд)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(сводка.бренд)
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(1)
                        if let беру = сводка.беру {
                            Text(String(format: т("mw_fit_take"), беру))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.акцент)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Theme.оттенокАкцента, in: Capsule())
                                .lineLimit(1)
                        }
                    }
                    Text(сводка.совет)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(сводка.краска)
                        .fixedSize(horizontal: false, vertical: true)
                    if let последняя = сводка.заметки.first {
                        Text(последняя.подпись)
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(сводка.заметки.count))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint(т("mw_fit_open_hint"))
    }
}

// MARK: - Лист заметок бренда

/// Заметки посадки: бренд (подсказки), размер как на бирке (чипы своих размеров), как сидит и где; ниже — заметки этого
/// бренда с удалением.
struct ЛистПосадкиГардероба: View {
    let начальный: String?
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @State private var бренд: String
    @State private var размер = ""
    @State private var вид: ВидРазмераМоего? = nil
    @State private var посадка: ПосадкаВещиМоего? = nil
    @State private var где = ""

    init(бренд: String?) {
        начальный = бренд
        _бренд = State(initialValue: бренд ?? "")
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var можно: Bool {
        !бренд.trimmingCharacters(in: .whitespaces).isEmpty && !размер.trimmingCharacters(in: .whitespaces).isEmpty
            && посадка != nil
    }

    var body: some View {
        let г = хранилище.запись.гардероб
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    поляБренда(г)
                    поляРазмера(г)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(т("mw_fit_how"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.текст)
                        ВыборПосадкиГардероба(посадка: $посадка, где: $где)
                    }
                    .карточкаМоего()
                    заметкиБренда(г)
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("mw_fit_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(МоёText.т("my_save")) { сохранить() }
                        .disabled(!можно)
                }
            }
            .клавиатураМоего()
        }
        .tint(Theme.акцент)
    }

    private func поляБренда(_ г: ГардеробМоего) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mw_brand"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПолеТекстаГардероба(подсказка: т("mw_brand_ph"), текст: $бренд, предел: ВещьГардеробаМоего.пределБренда)
            let подсказки = ПосадкаГардероба.подсказки(бренд, г: г, предел: 6)
            if !подсказки.isEmpty {
                ПотокЧипов(зазор: 6) {
                    ForEach(подсказки, id: \.self) { имя in
                        ЧипМоего(имя, выбран: false) {
                            ОткликСайта.выбор()
                            бренд = имя
                        }
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// Размер как на бирке: свои размеры из «Моих мерок» и размеры вещей этого бренда — чипами; можно набрать.
    private func поляРазмера(_ г: ГардеробМоего) -> some View {
        let свои = хранилище.запись.тело.размеры.map { ЧипРазмераБренда(текст: $0.коротко, вид: $0.вид) }
        let ключБренда = бренд.trimmingCharacters(in: .whitespaces).lowercased()
        let вещей = г.вещи.filter { $0.бренд.lowercased() == ключБренда }
            .compactMap { в in в.размер.map { ЧипРазмераБренда(текст: $0.коротко, вид: $0.вид) } }
        var видели = Set<String>()
        let чипы = Array((вещей + свои).filter { видели.insert($0.текст).inserted }.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            Text(т("mw_fit_size"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПолеТекстаГардероба(подсказка: т("mw_fit_size_ph"), текст: $размер, предел: 16)
            if !чипы.isEmpty {
                ПотокЧипов(зазор: 6) {
                    ForEach(чипы) { чип in
                        ЧипМоего(чип.текст, выбран: размер == чип.текст) {
                            ОткликСайта.выбор()
                            размер = чип.текст
                            вид = чип.вид
                        }
                    }
                }
            }
        }
        .карточкаМоего()
    }

    /// «Удалить: Zara M — мала» для VoiceOver — строка заранее, с явным типом (склейка в accessibilityLabel на хвосте
    /// Button — риск проверки типов).
    private func подписьУдаления(_ заметка: ЗаметкаПосадкиМоего) -> String {
        МоёText.т("my_delete") + ": " + заметка.подпись
    }

    @ViewBuilder
    private func заметкиБренда(_ г: ГардеробМоего) -> some View {
        let заметки = г.заметки(бренда: бренд).sorted { $0.когда > $1.когда }
        if !заметки.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let сводка = ПосадкаГардероба.сводка(бренда: бренд, г) {
                    Text(сводка.совет)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(сводка.краска)
                }
                ForEach(заметки) { заметка in
                    HStack(spacing: 10) {
                        Text(заметка.подпись)
                            .font(.subheadline)
                            .foregroundStyle(Theme.текст)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            ОткликСайта.выбор()
                            хранилище.обновитьГардероб { г in г.посадка.removeAll { $0.id == заметка.id } }
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.скидкаТекст)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
                        .accessibilityLabel(подписьУдаления(заметка))
                    }
                    .transition(.opacity)
                }
            }
            .карточкаМоего()
            .animation(ДвижениеСайта.вставкаСписка, value: заметки.map(\.id))
        }
    }

    private func сохранить() {
        guard можно, let посадка else { return }
        let заметка = ЗаметкаПосадкиМоего(бренд: String(бренд.trimmingCharacters(in: .whitespaces).prefix(30)), вид: вид,
                                          размер: String(размер.trimmingCharacters(in: .whitespaces).prefix(16)),
                                          посадка: посадка, текст: String(где.prefix(60)))
        хранилище.обновитьГардероб { г in ПосадкаГардероба.записать(заметка, в: &г) }
        ОткликСайта.успех()
        закрыть()
    }
}

/// Чип размера в листе заметок: подпись как на бирке и вид размера.
struct ЧипРазмераБренда: Identifiable {
    let текст: String
    let вид: ВидРазмераМоего?

    var id: String { текст }
}

// MARK: - Поле текста

/// Поле текста «Моего гардероба»: подложка второго уровня, рамка акцентом в фокусе, предел знаков.
struct ПолеТекстаГардероба: View {
    let подсказка: String
    @Binding var текст: String
    let предел: Int
    var строк: Int
    @FocusState private var фокус: Bool

    init(подсказка: String, текст: Binding<String>, предел: Int, строк: Int = 1) {
        self.подсказка = подсказка
        _текст = текст
        self.предел = предел
        self.строк = строк
    }

    var body: some View {
        Group {
            if строк > 1 {
                TextField(подсказка, text: $текст, axis: .vertical)
                    .lineLimit(строк, reservesSpace: false)
            } else {
                TextField(подсказка, text: $текст)
            }
        }
        .focused($фокус)
        .font(.body)
        .foregroundStyle(Theme.текст)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(фокус ? Theme.акцент : Theme.линия, lineWidth: фокус ? 2 : 1)
        }
        .animation(ДвижениеСайта.выбор, value: фокус)
        .onChange(of: текст) { _, новый in
            if новый.count > предел { текст = String(новый.prefix(предел)) }
        }
    }
}
