import SwiftUI
import UIKit

/**
 «МОЙ ГАРДЕРОБ» — «С ЧЕМ НОСИТЬ» (пачка 16.10.2026; владелец: «это нужно для рекомендаций — по этим параметрам новинки и
 прочее»; docs/SERVER_CIRCLE.md §11.1–11.2).

 К своей вещи — два ряда:
   · из своего гардероба — ГардеробМоего.сЧемНосить (другой слой, цвета сочетаются);
   · с Kliko — 3–6 объявлений дополняющего слоя (к верху — низ, к низу — верх, к платью — обувь, к верхней одежде и
     обуви — низ, к аксессуару — верхняя одежда) моего размера и подходящего цвета.
 Правила цвета (ЦветСтандарта.сочетается): тон в тон, нейтральный + акцент, две нейтральных, известная пара; не
 сочетается — не показываем. Размер — та же сверка, что плашка «Подходит моему» (СовместимостьМоего.оценить: строка
 «Размер: EU 42 · RU 41 · …» описания), иначе — поле размера продавца (буквы INT и значение моей системы); чужой размер —
 не показываем, не указан — карточка честно говорит «размер уточните».

 Сеть — один запрос по нажатию «Подобрать» (раздел ленты по новизне, только с фото; GET — раздел публичный, как если бы
 человек открыл его сам): цвета и размер из «Моего» в адрес не уходят (договор: только телом POST, пока сервер не
 принимает — отбор на телефоне). Ответ — в памяти на 10 минут по разделу: соседняя вещь того же слоя берёт его без
 сети. «Удалить всё «Моё»» память не трогает — в ней нет ничего моего, только публичная лента раздела.
 */

/// Пол одежды по виду размера «Моего» (данные детей не собираем).
enum ПолГардеробаМоего: Sendable {
    case женский
    case мужской
}

/// Почему цвета идут вместе.
enum ПравилоЦветаГардероба: Sendable {
    case тонВТон
    case нейтральИАкцент
    case нейтральные
    case пара
    case нет

    /// Ключ подписи в МойГардеробText.
    var ключ: String {
        switch self {
        case .тонВТон: return "mw_rule_tone"
        case .нейтральИАкцент: return "mw_rule_accent"
        case .нейтральные: return "mw_rule_neutral"
        case .пара: return "mw_rule_pair"
        case .нет: return "mw_rule_no"
        }
    }

    var балл: Int {
        switch self {
        case .тонВТон, .нейтральИАкцент: return 3
        case .нейтральные, .пара: return 2
        case .нет: return 0
        }
    }
}

/// Как сверили размер предложения с моим.
enum РазмерПредложенияГардероба: Sendable {
    case ваш
    case близко
    case неУказан
}

/// Предложение «с чем носить»: объявление, правило цвета (nil — цвет в объявлении не указан), размер.
struct ПредложениеГардероба: Identifiable {
    let товар: Listing
    let правило: ПравилоЦветаГардероба?
    let цвета: [ЦветСтандарта]
    let размер: РазмерПредложенияГардероба

    var id: String { товар.id }
}

enum СочетаниеГардероба {
    /// Слой, который дополняет вещь в образе.
    static func дополнение(_ слой: СлойГардеробаМоего) -> СлойГардеробаМоего {
        switch слой {
        case .верх: return .низ
        case .низ: return .верх
        case .целиком: return .обувь
        case .верхняя: return .низ
        case .обувь: return .низ
        case .аксессуар: return .верхняя
        }
    }

    static func пол(_ вид: ВидРазмераМоего) -> ПолГардеробаМоего? {
        switch вид {
        case .одеждаЖ, .джинсыЖ, .обувьЖ, .бельё: return .женский
        case .одеждаМ, .джинсыМ, .обувьМ: return .мужской
        case .кольцо, .шапка, .перчатки: return nil
        }
    }

    /// Пол — по размеру вещи, по платью и юбке, иначе по первому размеру «Моих мерок»; не знаем — nil.
    static func пол(_ вещь: ВещьГардеробаМоего, тело: ТелоМоего) -> ПолГардеробаМоего? {
        if let в = вещь.размер?.вид, let п = пол(в) { return п }
        if вещь.вид == .платье || вещь.вид == .юбка { return .женский }
        for р in тело.размеры {
            if let п = пол(р.вид) { return п }
        }
        return nil
    }

    /// Раздел ленты слоя; пол не знаем — общий раздел (отбор — по названию и подразделу).
    static func раздел(_ слой: СлойГардеробаМоего, пол: ПолГардеробаМоего?) -> String {
        let ж = пол == .женский
        let м = пол == .мужской
        switch слой {
        case .верх: return ж ? "womens-tops" : (м ? "mens-tops" : "clothing")
        case .низ: return ж ? "womens-bottoms" : (м ? "mens-bottoms" : "clothing")
        case .целиком: return ж ? "womens-dresses" : (м ? "mens-suits" : "clothing")
        case .верхняя: return ж ? "womens-outerwear" : (м ? "mens-outerwear" : "clothing")
        case .обувь: return ж ? "womens-shoes" : (м ? "mens-shoes" : "shoes")
        case .аксессуар: return "bags-accessories"
        }
    }

    /// Подразделы слоя обоих полов — отбор, когда название вида не подсказывает.
    static func подразделы(_ слой: СлойГардеробаМоего) -> Set<String> {
        switch слой {
        case .верх: return ["womens-tops", "mens-tops"]
        case .низ: return ["womens-bottoms", "mens-bottoms"]
        case .целиком: return ["womens-dresses", "mens-suits"]
        case .верхняя: return ["womens-outerwear", "mens-outerwear"]
        case .обувь: return ["shoes"]
        case .аксессуар: return ["bags-accessories"]
        }
    }

    /// Мой размер для слоя предложений: те виды размера, которыми меряют слой, своего пола.
    static func мойРазмер(_ слой: СлойГардеробаМоего, пол: ПолГардеробаМоего?, тело: ТелоМоего) -> РазмерМоего? {
        let виды: [ВидРазмераМоего]
        switch слой {
        case .верх, .целиком, .верхняя: виды = [.одеждаЖ, .одеждаМ]
        case .низ: виды = [.джинсыЖ, .одеждаЖ, .джинсыМ, .одеждаМ]
        case .обувь: виды = [.обувьЖ, .обувьМ]
        case .аксессуар: виды = []
        }
        let свои = виды.filter { пол == nil || self.пол($0) == пол }
        return свои.lazy.compactMap { тело.размер($0) }.first
    }

    /// Правило цвета: моя вещь ↔ предложение. Цвета нет у одной из сторон — nil.
    static func правило(мои: [ЦветСтандарта], его: [ЦветСтандарта]) -> ПравилоЦветаГардероба? {
        guard let мой = мои.first, let он = его.first else { return nil }
        guard мой.сочетается(с: он) else { return .нет }
        if мой == он { return .тонВТон }
        if мой.нейтральный && он.нейтральный { return .нейтральные }
        if мой.нейтральный != он.нейтральный { return .нейтральИАкцент }
        return .пара
    }

    /// Цвета объявления: пункт «Цвет», название, поле цвета продавца (у одежды — колонка cpu ленты).
    static func цвета(_ товар: Listing) -> [ЦветСтандарта] {
        let найдено = РазборСтандартов.разобрать(товар).цвета
        if !найдено.isEmpty { return найдено }
        return РазборСтандартов.цвета(товар.cpuСтрокой ?? "")
    }

    /**
     Размер по полю продавца (у одежды и обуви — колонка storage ленты): буквы INT однозначны — совпало или нет; число —
     только в моей системе: совпало — мой, нет — «не знаем» (у числа бывает чужая система). nil — поля нет.
     */
    static func размерПоПолю(_ товар: Listing, мой: РазмерМоего) -> Bool? {
        guard let сырое = товар.storageСтрокой?.trimmingCharacters(in: .whitespacesAndNewlines), !сырое.isEmpty,
              сырое.count <= 24, let выбор = мой.выбор() else { return nil }
        let вкладка = мой.вид.вкладка
        let буквы = Set(вкладка.части(выбор).filter { $0.код.hasPrefix("INT") }
            .map { ПравилаРазмераОдежды.ключ($0.значение) })
        let своё = ПравилаРазмераОдежды.ключ(мой.значение)
        let куски = ПравилаРазмераОдежды.ключ(сырое).split { " /,;|-".contains($0) }.map(String.init)
        guard !куски.isEmpty else { return nil }
        if куски.contains(where: { буквы.contains($0) || $0 == своё }) { return true }
        let этоБуквы = куски.allSatisfy { к in к.allSatisfy { $0.isLetter } && к.count <= 4 }
        return этоБуквы && !буквы.isEmpty ? false : nil
    }

    /// Вид объявления по названию к слою: тот же слой — да, другой — нет; не узнали — по подразделу.
    private static func тотСлой(_ товар: Listing, _ слой: СлойГардеробаМоего) -> Bool {
        if let вид = ВидВещиГардеробаМоего.поНазванию(товар.title) { return вид.слой == слой }
        return РазделыСайта.внутри(товар.категория, подразделы(слой))
    }

    /**
     3–6 предложений к вещи из ленты раздела: дополняющий слой, без детского, цвет сочетается (или не указан), размер
     мой или не указан (чужой — прочь). Порядок — сумма баллов цвета (×2) и размера, при равных — как в ленте (свежие
     выше). С известным цветом — первыми; с неизвестным — только добивают до трёх.
     */
    static func подобрать(к вещь: ВещьГардеробаМоего, из товары: [Listing], запись: ЗаписьМоего,
                          предел: Int = 6) -> [ПредложениеГардероба] {
        let слой = дополнение(вещь.вид.слой)
        let мой = мойРазмер(слой, пол: пол(вещь, тело: запись.тело), тело: запись.тело)
        var сЦветом: [(Int, Int, ПредложениеГардероба)] = []
        var безЦвета: [(Int, Int, ПредложениеГардероба)] = []
        for (номер, товар) in товары.enumerated() {
            guard товар.активно, !товар.вРезерве, тотСлой(товар, слой),
                  !РазделыСайта.внутри(товар.категория, СовместимостьМоего.разделыДетские) else { continue }
            let его = цвета(товар)
            let какЦвет = правило(мои: вещь.цвета, его: его)
            if какЦвет == .нет { continue }
            guard let какРазмер = размерПредложения(товар, мой: мой, запись: запись) else { continue }
            let баллРазмера = какРазмер == .ваш ? 3 : (какРазмер == .близко ? 1 : 0)
            let предложение = ПредложениеГардероба(товар: товар, правило: какЦвет, цвета: его, размер: какРазмер)
            if let какЦвет {
                сЦветом.append((какЦвет.балл * 2 + баллРазмера, номер, предложение))
            } else if вещь.цвета.isEmpty && его.first?.нейтральный == true {
                сЦветом.append((2 + баллРазмера, номер, предложение))
            } else {
                безЦвета.append((баллРазмера, номер, предложение))
            }
        }
        let порядок: ((Int, Int, ПредложениеГардероба), (Int, Int, ПредложениеГардероба)) -> Bool = { а, б in
            а.0 == б.0 ? а.1 < б.1 : а.0 > б.0
        }
        var итог = сЦветом.sorted(by: порядок).prefix(предел).map(\.2)
        if итог.count < 3 {
            итог += безЦвета.sorted(by: порядок).prefix(3 - итог.count).map(\.2)
        }
        return итог
    }

    /// Размер предложения; nil — размер в объявлении чужой (не показываем). Моего размера нет — «не указан».
    private static func размерПредложения(_ товар: Listing, мой: РазмерМоего?,
                                          запись: ЗаписьМоего) -> РазмерПредложенияГардероба? {
        guard let мой else { return .неУказан }
        if let итог = СовместимостьМоего.оценить(товар, моё: запись), итог.профиль == .размер, let уровень = итог.уровень {
            switch уровень {
            case .подходит, .доработка: return .ваш
            case .проверить: return .близко
            case .неПодходит: return nil
            default: break
            }
        }
        switch размерПоПолю(товар, мой: мой) {
        case .some(true): return .ваш
        case .some(false): return nil
        case .none: return .неУказан
        }
    }
}

// MARK: - Память ленты раздела

/// Лента раздела для «с чем носить»: один запрос на раздел, ответ — в памяти 10 минут. Только главная нить.
@MainActor
final class ПодборГардеробаМодель: ObservableObject {
    static let shared = ПодборГардеробаМодель()

    enum Состояние: Equatable {
        case грузим
        case ошибка
    }

    /// Разделы, которые сейчас грузятся или не загрузились.
    @Published private(set) var состояние: [String: Состояние] = [:]
    /// Растёт с каждым пришедшим ответом: по нему блок пересчитывает предложения (не в каждом body).
    @Published private(set) var версия = 0
    private var память: [String: (когда: Date, товары: [Listing])] = [:]

    static let свежесть: TimeInterval = 600

    private init() {}

    /// Свежий ответ раздела из памяти или nil.
    func готовые(_ раздел: String) -> [Listing]? {
        guard let запись = память[раздел], Date().timeIntervalSince(запись.когда) < Self.свежесть else { return nil }
        return запись.товары
    }

    /// Раздел по новизне, только с фото, 48 штук. Уже в памяти или грузится — без второго запроса.
    func загрузить(_ раздел: String) async {
        guard готовые(раздел) == nil, состояние[раздел] != .грузим else { return }
        состояние[раздел] = .грузим
        var запрос = ListingsAPI.Запрос()
        запрос.per = 48
        запрос.cat = раздел
        запрос.фильтры.сФото = true
        do {
            let ответ = try await ListingsAPI.загрузить(запрос)
            память[раздел] = (Date(), ответ.страница.items)
            состояние[раздел] = nil
            версия += 1
        } catch {
            состояние[раздел] = .ошибка
        }
    }
}

// MARK: - Блок «С чем носить»

/// «С чем носить» в листе вещи: свои вещи рядом и подбор на Kliko по нажатию.
struct СЧемНоситьГардероба: View {
    let вещь: ВещьГардеробаМоего
    let запись: ЗаписьМоего
    let открытьСвою: (UUID) -> Void
    @ObservedObject private var подбор = ПодборГардеробаМодель.shared
    @Environment(\.dismiss) private var закрыть
    /// Подобранное к ответу раздела: считается в task по версии ответа, не в body.
    @State private var предложения: [ПредложениеГардероба]? = nil

    init(вещь: ВещьГардеробаМоего, запись: ЗаписьМоего, открытьСвою: @escaping (UUID) -> Void) {
        self.вещь = вещь
        self.запись = запись
        self.открытьСвою = открытьСвою
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var слой: СлойГардеробаМоего { СочетаниеГардероба.дополнение(вещь.вид.слой) }

    private var раздел: String {
        СочетаниеГардероба.раздел(слой, пол: СочетаниеГардероба.пол(вещь, тело: запись.тело))
    }

    var body: some View {
        let свои = запись.гардероб.сЧемНосить(вещь)
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mw_wear_with"), значок: "sparkles")
            if !свои.isEmpty {
                Text(т("mw_wear_own"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                рядСвоих(Array(свои.prefix(12)))
            }
            Text(String(format: т("mw_wear_kliko"), МойГардеробText.слой(слой)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            клико
        }
        .карточкаМоего()
        .task(id: ключПодбора) { пересчитать() }
    }

    /// Ответ раздела, цвета и размер вещи, мои мерки — сменилось что-то из них, подбор считается заново.
    private var ключПодбора: String {
        [раздел, String(подбор.версия), вещь.цвета.map(\.rawValue).joined(separator: ","), вещь.вид.rawValue,
         вещь.размер?.коротко ?? "", запись.тело.размеры.map(\.коротко).joined(separator: ",")].joined(separator: "|")
    }

    private func пересчитать() {
        guard let товары = подбор.готовые(раздел) else {
            предложения = nil
            return
        }
        let новые = СочетаниеГардероба.подобрать(к: вещь, из: товары, запись: запись)
        withAnimation(ДвижениеСайта.появление) { предложения = новые }
    }

    private func всеВРазделе() {
        закрыть()
        ПереходыГардероба.найти(раздел: раздел)
    }

    private func рядСвоих(_ вещи: [ВещьГардеробаМоего]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(вещи) { своя in
                    Button {
                        ОткликСайта.выбор()
                        открытьСвою(своя.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            КартинкаВещиГардероба(вещь: своя, поля: 6)
                                .frame(width: 84, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                            Text(своя.заголовок)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.текст)
                                .lineLimit(1)
                                .frame(width: 84, alignment: .leading)
                        }
                    }
                    .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
                    .accessibilityLabel(своя.заголовок)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var клико: some View {
        if let предложения {
            if предложения.isEmpty {
                пусто
            } else {
                ПредложенияГардероба(предложения: предложения, все: всеВРазделе)
            }
        } else if подбор.состояние[раздел] == .грузим {
            HStack(spacing: 10) {
                SiteSpinner(размер: 18, толщина: 2, стоит: ДвижениеСайта.тихо)
                Text(т("mw_wear_loading"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if подбор.состояние[раздел] == .ошибка {
                    Text(т("mw_wear_error"))
                        .font(.footnote)
                        .foregroundStyle(Theme.оранжевый)
                }
                Text(т("mw_wear_how"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                МалаяКнопкаАвтоподбора(заголовок: т("mw_wear_find"), значок: "wand.and.stars") {
                    ОткликСайта.выбор()
                    Task { await подбор.загрузить(раздел) }
                }
            }
        }
    }

    private var пусто: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mw_wear_none"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            МалаяКнопкаАвтоподбора(заголовок: т("mw_wear_all"), значок: "square.grid.2x2", действие: всеВРазделе)
        }
    }
}

/// Ряд предложений: карточки 140 pt, «Подобрали по цвету и размеру», «Весь раздел».
struct ПредложенияГардероба: View {
    let предложения: [ПредложениеГардероба]
    let все: () -> Void

    init(предложения: [ПредложениеГардероба], все: @escaping () -> Void) {
        self.предложения = предложения
        self.все = все
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(предложения.enumerated()), id: \.element.id) { номер, п in
                        Button {
                            ОткликСайта.выбор()
                            ПереходыГардероба.открыть(п.товар)
                        } label: {
                            КарточкаПредложенияГардероба(предложение: п)
                        }
                        .buttonStyle(НажатиеСайта())
                        .появлениеМоего(номер)
                    }
                }
                .padding(.vertical, 2)
            }
            Label(т("mw_wear_honest"), systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            МалаяКнопкаАвтоподбора(заголовок: т("mw_wear_all"), значок: "square.grid.2x2", действие: все)
        }
    }
}

/// Карточка предложения: фото 1:1, цена, название в две строки, правило цвета и размер чипами.
struct КарточкаПредложенияГардероба: View {
    let предложение: ПредложениеГардероба

    init(предложение: ПредложениеГардероба) {
        self.предложение = предложение
    }

    static let ширина: CGFloat = 140

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var размерТекст: String {
        switch предложение.размер {
        case .ваш: return т("mw_size_yours")
        case .близко: return т("mw_size_close")
        case .неУказан: return т("mw_size_unknown")
        }
    }

    var body: some View {
        let товар = предложение.товар
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Theme.поверхность2
                .frame(width: Self.ширина, height: Self.ширина)
                .overlay {
                    КартинкаЛенты(товар.обложка, пунктов: Self.ширина) {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(ListingCard.цена(товар))
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(товар.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if let цвет = предложение.цвета.first { КружокЦветаГардероба(цвет, размер: 10) }
                    Text(предложение.правило.map { т($0.ключ) } ?? т("mw_rule_unknown"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.акцент)
                Text(размерТекст)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(предложение.размер == .ваш ? Theme.акцент : Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
        }
        .frame(width: Self.ширина, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        .clipShape(форма)
        .contentShape(форма)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(товар.голос + ". " + (предложение.правило.map { т($0.ключ) } ?? т("mw_rule_unknown"))
                            + ". " + размерТекст)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Переходы

/// Переходы из гардероба: объявление окном поверх (поверх листа тоже), лента раздела, подача.
@MainActor
enum ПереходыГардероба {
    /**
     Свой лист вызывающий уже закрыл (dismiss SwiftUI) — пауза, пока он уезжает; «Моё» открыто окном поверх (ОкноМоего)
     — закрыть и его, иначе лента и мастер встанут под окном; в стеке кабинета — сразу после паузы.
     */
    static func послеОкон(_ действие: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if let верх = ПоверхВсего.верхний(), верх.presentingViewController != nil {
                верх.dismiss(animated: true)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            действие()
        }
    }

    /// Объявление окном поверх того, что на экране (лист вещи тоже остаётся под ним).
    static func открыть(_ товар: Listing) {
        ПоверхВсего.показать(большой: true) { закрыть in
            ОкноОбъявленияГардероба(товар: товар, закрыть: закрыть)
        }
    }

    /// Весь раздел — лента приложения (без цветов и размера в адресе).
    static func найти(раздел: String) {
        let искомое = ИскомоеЛенты(текст: "", раздел: раздел)
        послеОкон {
            WebBridge.shared.открытьЭкран(.найти(искомое), запасной: nil)
        }
    }

    /**
     «Продать своё»: мастер подачи. Заготовки названия, раздела и размера у мастера пока нет (ЦельПодачи — только новое
     и правка) — готовое название с размером кладётся в буфер обмена, экран говорит об этом вестью; раздел и размер
     человек выбирает в мастере сам.
     */
    static func продать(название: String) {
        // Только этот телефон (без Универсального буфера на другие устройства) и на 10 минут — как «Копировать» пароль.
        if !название.isEmpty {
            UIPasteboard.general.setItems([["public.utf8-plain-text": название]],
                                          options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(600)])
        }
        послеОкон {
            _ = ПодачаОкно.shared.открыть(.новое)
        }
    }
}

/// Объявление окном поверх «Моего гардероба»: свой стек (похожие и чат ложатся в него) и «Закрыть».
private struct ОкноОбъявленияГардероба: View {
    let товар: Listing
    let закрыть: () -> Void
    @State private var путь = NavigationPath()

    init(товар: Listing, закрыть: @escaping () -> Void) {
        self.товар = товар
        self.закрыть = закрыть
    }

    var body: some View {
        NavigationStack(path: $путь) {
            ListingDetailView(товар: товар, открыть: { адрес in открытьАдрес(адрес) })
                .navigationDestination(for: Listing.self) { другой in
                    ListingDetailView(товар: другой, открыть: { адрес in открытьАдрес(адрес) })
                }
                .чатМаршруты(открыть: { адрес in открытьАдрес(адрес) })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(МоёText.т("my_close")) { закрыть() }
                    }
                }
        }
        .environment(\.открытьОбъявлениеВСтеке, { другой in путь.append(другой) })
        .tint(Theme.акцент)
    }

    /// Ссылка изнутри карточки: окно закрывается, адрес — путём корня приложения.
    @MainActor
    private func открытьАдрес(_ адрес: URL) {
        закрыть()
        ПоверхВсего.открытьАдрес(адрес)
    }
}
