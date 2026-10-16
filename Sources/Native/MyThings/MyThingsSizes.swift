import SwiftUI
import UIKit

/**
 «МОЁ» — РАЗМЕР В СВОЕЙ СИСТЕМЕ (владелец 14.10.2026: размеры «как на бирке магазина» во всех системах).

 Лист: что это (обувь, одежда, джинсы, бельё, кольцо, шапка, перчатки) → система, к которой человек привык (EU, US,
 RU, W…) → ровная сетка значений этой системы (колонок 5, 4, 3 или 2 по самой длинной подписи; выбранный — зелёная
 заливка, она перелетает к новому чипу) → у джинсов длина L, у белья чашка. Снизу — живая бирка всех систем (таблицы
 ClothingSizes — только вызовы; при смене бирка вздрагивает). Есть мерки — «По меркам подойдёт: RU 48 · M» и
 «Подставить». Хранится значение своей системы, а не номер ряда: таблицы сайта могут сдвинуть ряды.
 */
struct РедакторРазмераМоего: View {
    let начальный: ВидРазмераМоего?
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @Namespace private var пространство
    @State private var вид: ВидРазмераМоего
    @State private var система: String
    @State private var ряд: Int? = nil
    @State private var ряд2: Int? = nil
    @State private var толчок = 0
    @State private var начато = false

    init(вид: ВидРазмераМоего?) {
        начальный = вид
        let в = вид ?? .обувьЖ
        _вид = State(initialValue: в)
        _система = State(initialValue: в.вкладка.системаСайта)
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    private var вкладка: ВкладкаРазмеровОдежды { вид.вкладка }

    private var текущая: СистемаРазмераОдежды? { вкладка.система(система) ?? вкладка.системы.first }

    private var выбор: ВыборРазмераОдежды? {
        guard let ряд else { return nil }
        return ВыборРазмераОдежды(вкладка: вкладка.ключ, ряд: ряд, ряд2: ряд2)
    }

    /// Значение своей системы у выбранного ряда (пусто — в этой системе такого размера нет).
    private var значение: String {
        guard let ряд, let с = текущая else { return "" }
        return вкладка.основная.значение(ряд, с.первый)
    }

    private var был: Bool { хранилище.запись.тело.размер(вид) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    выборВида
                    выборСистемы
                    сеткаОсновная
                    сеткаВторая
                    подсказкаПоМеркам
                    бирка
                    if был {
                        МалаяКнопкаАвтоподбора(заголовок: т("mb_size_remove"), значок: "trash", опасная: true) {
                            хранилище.удалитьРазмер(вид)
                            ОткликСайта.успех()
                            закрыть()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("mb_sizes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(МоёText.т("my_save")) { сохранить() }
                        .disabled(значение.isEmpty)
                }
            }
        }
        .tint(Theme.акцент)
        .presentationDetents([.large])
        .onAppear { начать() }
    }

    // MARK: Что и в какой системе

    private var выборВида: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mb_kind"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(ВидРазмераМоего.allCases, id: \.self) { в in
                    ЧипМоего(в.подпись, выбран: в == вид, значок: в.значок) { сменитьВид(в) }
                }
            }
        }
    }

    private var выборСистемы: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mb_system"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(вкладка.системы, id: \.код) { с in
                    ЧипМоего(РазмерыОдеждыText.система(с.код), выбран: с.код == текущая?.код) {
                        guard с.код != система else { return }
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { система = с.код }
                        толчок += 1
                    }
                }
            }
        }
    }

    // MARK: Сетки

    @ViewBuilder
    private var сеткаОсновная: some View {
        if let с = текущая {
            СеткаРазмеровМоего(чипы: вкладка.основная.чипы(с.первый), выбранный: ряд, код: с.код,
                               пространство: пространство, метка: "main") { чип in
                ОткликСайта.выбор()
                withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) { ряд = чип.id }
                толчок += 1
            }
            .id(вид.rawValue + "|" + с.код)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var сеткаВторая: some View {
        if let с = текущая, let второй = с.второй, let т2 = вкладка.вторая {
            VStack(alignment: .leading, spacing: 8) {
                Text(т(вид == .бельё ? "mb_cup" : "mb_length"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                СеткаРазмеровМоего(чипы: т2.чипы(второй), выбранный: ряд2, код: "", пространство: пространство,
                                   метка: "second") { чип in
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) {
                        ряд2 = ряд2 == чип.id ? nil : чип.id
                    }
                    толчок += 1
                }
            }
            .id(вид.rawValue + "|2|" + с.код)
            .transition(.opacity)
        }
    }

    // MARK: По меркам

    @ViewBuilder
    private var подсказкаПоМеркам: some View {
        if let совет = ПодсказкаРазмераМоего.выбор(вид, хранилище.запись.тело), совет.ряд != ряд || совет.ряд2 != ряд2 {
            HStack(spacing: 10) {
                Image(systemName: "ruler")
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(String(format: т("mb_suggest"), ПодсказкаРазмераМоего.подпись(вкладка, совет, система: система)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                МалаяКнопкаАвтоподбора(заголовок: т("mb_suggest_apply"), значок: "wand.and.stars") {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) {
                        ряд = совет.ряд
                        ряд2 = совет.ряд2
                    }
                    толчок += 1
                }
            }
            .padding(12)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var бирка: some View {
        if let выбор, !значение.isEmpty {
            БиркаРазмера(вкладка.бирка(выбор, система: текущая?.код ?? система), толчок: толчок, сброс: nil) {
                EmptyView()
            }
            .transition(.opacity)
        } else {
            Label(РазмерыОдеждыText.т("empty"), systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
        }
    }

    // MARK: Действия

    /// Открыли «Добавить размер» — первым вид, которого ещё нет; открыли свой — его система и значение.
    private func начать() {
        guard !начато else { return }
        начато = true
        if начальный == nil {
            let есть = Set(хранилище.запись.тело.размеры.map(\.вид))
            if let первый = ВидРазмераМоего.allCases.first(where: { !есть.contains($0) }) { вид = первый }
        }
        загрузить(вид)
    }

    private func сменитьВид(_ новый: ВидРазмераМоего) {
        guard новый != вид else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) {
            вид = новый
            загрузить(новый)
        }
    }

    /// Свой размер вида — его система и ряды; нет — система сайта у таблицы, без выбора.
    private func загрузить(_ в: ВидРазмераМоего) {
        if let свой = хранилище.запись.тело.размер(в), let выбор = свой.выбор() {
            система = свой.система
            ряд = выбор.ряд
            ряд2 = выбор.ряд2
        } else {
            система = в.вкладка.системаСайта
            ряд = nil
            ряд2 = nil
        }
    }

    private func сохранить() {
        guard let ряд, let с = текущая else { return }
        let своё = вкладка.основная.значение(ряд, с.первый)
        guard !своё.isEmpty else { return }
        var второе = ""
        if let второй = с.второй, let т2 = вкладка.вторая, let ряд2 {
            второе = т2.значение(ряд2, второй)
        }
        хранилище.задатьРазмер(РазмерМоего(вид: вид, система: с.код, значение: своё, значение2: второе))
        ОткликСайта.успех()
        закрыть()
    }
}

// MARK: - Сетка

/// Ровная сетка чипов: колонок 5, 4, 3 или 2 по самой длинной подписи, все чипы одной высоты (44), неполный ряд добит
/// пустыми местами. Выбранный — зелёная заливка, одна на сетку: она перелетает к новому чипу.
struct СеткаРазмеровМоего: View {
    let чипы: [ЧипРазмераОдежды]
    let выбранный: Int?
    /// Код системы — возраст и единицы показываются на языке телефона; пусто — без подписи для VoiceOver.
    let код: String
    let пространство: Namespace.ID
    let метка: String
    let нажато: (ЧипРазмераОдежды) -> Void

    init(чипы: [ЧипРазмераОдежды], выбранный: Int?, код: String, пространство: Namespace.ID, метка: String,
         нажато: @escaping (ЧипРазмераОдежды) -> Void) {
        self.чипы = чипы
        self.выбранный = выбранный
        self.код = код
        self.пространство = пространство
        self.метка = метка
        self.нажато = нажато
    }

    static func колонки(_ подписи: [String]) -> Int {
        let длина = подписи.map { $0.count }.max() ?? 0
        if длина <= 4 { return 5 }
        if длина <= 6 { return 4 }
        if длина <= 11 { return 3 }
        return 2
    }

    var body: some View {
        let колонки = Self.колонки(чипы.map { РазмерыОдеждыText.чип($0.значение, код: код) })
        let ряды = stride(from: 0, to: чипы.count, by: колонки).map { Array(чипы[$0..<min($0 + колонки, чипы.count)]) }
        VStack(spacing: 8) {
            ForEach(ряды.indices, id: \.self) { н in
                HStack(spacing: 8) {
                    ForEach(ряды[н]) { чип in
                        кнопка(чип)
                    }
                    ForEach(0..<(колонки - ряды[н].count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func кнопка(_ чип: ЧипРазмераОдежды) -> some View {
        let выбран = выбранный.map { чип.ряды.contains($0) } ?? false
        let подпись = РазмерыОдеждыText.чип(чип.значение, код: код)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            нажато(чип)
        } label: {
            Text(подпись)
                .font(.system(size: 15, weight: выбран ? Font.Weight.heavy : Font.Weight.semibold).monospacedDigit())
                .foregroundStyle(выбран ? Color.white : Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background {
                    if выбран {
                        форма
                            .fill(Theme.зелёный2)
                            .matchedGeometryEffect(id: метка, in: пространство)
                    } else {
                        форма.fill(Theme.поверхность)
                    }
                }
                .overlay { форма.strokeBorder(выбран ? Color.clear : Theme.линия, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.94))
        .accessibilityLabel(код.isEmpty ? подпись : РазмерыОдеждыText.система(код) + " " + подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Подсказка по меркам

/**
 Размер по меркам тела — ближайший ряд таблицы: одежда женская — по груди и бёдрам, мужская — по груди, джинсы — по
 талии (и длина L — по длине ноги по шагу), обувь — первый ряд, где стелька не короче стопы, шапка — по обхвату
 головы. Мерок нет или вид другой — nil. Мерки «≈» (подставлены по размеру, росту, фото) не в счёт: иначе грудь,
 взятая из M, тянула бы обратно на M «по вашим меркам» — только введённые руками или подтверждённые «Так и есть».
 */
enum ПодсказкаРазмераМоего {
    static func выбор(_ вид: ВидРазмераМоего, _ тело: ТелоМоего) -> ВыборРазмераОдежды? {
        let вкладка = вид.вкладка
        let т = вкладка.основная
        func мерка(_ м: МеркаМоего) -> Double? { тело.примерная(м) ? nil : тело.мерка(м) }
        let ряд: Int?
        var ряд2: Int? = nil
        switch вид {
        case .одеждаЖ:
            ряд = ближайший(т, [("Грудь, см", мерка(.грудь)), ("Бёдра, см", мерка(.бёдра))])
        case .одеждаМ:
            ряд = ближайший(т, [("Грудь, см", мерка(.грудь))])
        case .джинсыЖ, .джинсыМ:
            ряд = ближайший(т, [("Талия, см", мерка(.талия))])
            if let т2 = вкладка.вторая {
                ряд2 = ближайший(т2, [("По внутреннему шву, см", мерка(.шаг))])
            }
        case .обувьЖ, .обувьМ:
            guard let стопа = мерка(.стопа), let столбец = т.столбец("CM") else { return nil }
            ряд = т.ряды.indices.first { (ПравилаРазмераОдежды.число(т.значение($0, столбец)) ?? 0) >= стопа }
        case .шапка:
            ряд = ближайший(т, [("RU", мерка(.голова))])
        case .бельё, .кольцо, .перчатки:
            ряд = nil
        }
        guard let ряд else { return nil }
        return ВыборРазмераОдежды(вкладка: вкладка.ключ, ряд: ряд, ряд2: ряд2)
    }

    /// Ряд с наименьшей суммой расхождений по известным меркам; ни одной мерки — nil.
    private static func ближайший(_ т: ТаблицаРазмеровОдежды, _ мерки: [(String, Double?)]) -> Int? {
        var лучший: (ряд: Int, разница: Double)? = nil
        for ряд in т.ряды.indices {
            var сумма = 0.0
            var есть = 0
            for (код, тело) in мерки {
                guard let тело, let столбец = т.столбец(код),
                      let x = ПравилаРазмераОдежды.число(т.значение(ряд, столбец)) else { continue }
                сумма += abs(x - тело)
                есть += 1
            }
            guard есть > 0 else { continue }
            if лучший.map({ сумма < $0.разница }) ?? true { лучший = (ряд, сумма) }
        }
        return лучший?.ряд
    }

    /// «RU 48 · M»: своя система и буква INT, если она есть и это не та же система.
    static func подпись(_ вкладка: ВкладкаРазмеровОдежды, _ выбор: ВыборРазмераОдежды, система: String) -> String {
        let части = вкладка.части(выбор)
        var итог: [String] = []
        if let своя = части.first(where: { $0.код == система }) ?? части.first {
            итог.append(РазмерыОдеждыText.показ(своя))
        }
        if система != "INT", let буква = части.first(where: { $0.код == "INT" }) {
            итог.append(буква.значение)
        }
        return итог.joined(separator: " · ")
    }
}
