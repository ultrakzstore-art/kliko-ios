import SwiftUI
import UIKit

/**
 «МОЁ» — «ДОБАВИТЬ ИЗ МОИХ ПОКУПОК»: ЦИФРОВИЗАЦИЯ КУПЛЕННОГО (владелец 16.10.2026: «показывать, что был куплен там —
 цифровизация реальности»; docs/STANDARDS.md §8.8, docs/SERVER_CIRCLE.md §2).

 Список завершённых покупок в безопасной сделке — тот же ответ my_deals&role=buyer, что у «Моих сделок» (СделкиAPI,
 только чтение, по открытию экрана и потягиванию; в памяти 10 минут, на диск не пишется). Завершённой считается сделка
 с итогом «продано» (outcome sold), до него — статусы released, confirmed, done, completed; возврат, отмена, услуги и
 аренда — не покупки вещи. По разделу объявления экран предлагает, куда положить (гараж, устройства, дом, компьютер,
 гардероб, мерки), человек может выбрать другое; «В «Моё»» — касанием (это и есть согласие): вещь ложится с названием,
 обложкой объявления, ценой, месяцем покупки — «Куплено на Kliko · окт 2026 · 25 000 ₸» — и стандартами из названия и
 снимка сделки. Одежда — вещью гардероба, ноутбук и ПК — компьютером, техника — в «Мой дом», детское — без места
 (данные детей не собираем). «Убрать из «Моего»» — тем же касанием. Цена и дата — только на этом телефоне.
 */

// MARK: - Покупка из сделки

/// Завершённая покупка из ответа my_deals: что, где, почём и когда; стандарты — из снимка сделки и названия.
struct ПокупкаИзСделкиМоего: Identifiable, Equatable, Sendable {
    /// Номер сделки.
    let id: String
    let товар: String
    let название: String
    /// Раздел объявления (category).
    let раздел: String
    /// Обложка объявления (адрес сайта).
    let фото: String
    let цена: Int?
    let когда: Date?
    let бренд: String
    let стандарты: НаборСтандартов
    let цвета: [ЦветСтандарта]

    /// Сделка покупателя завершилась покупкой: итог sold или (без итога) один из этих статусов.
    static let завершённые: Set<String> = ["released", "confirmed", "done", "completed"]

    init?(_ j: [String: Any]) {
        typealias A = СделкиAPI
        let номер = A.строка(j["id"])
        guard A.годныйНомер(номер), A.строка(j["my_role"]) != "seller" else { return nil }
        let вид = A.строка(j["kind"])
        /* Цифровой код (mode digital, Ц4) — не вещь: в «Моё» не предлагается. */
        let режим = A.строка(j["mode"])
        guard вид != "service", вид != "rent", режим != "rent", режим != ЦифровыеТовары.сделка else { return nil }
        let итог = A.строка(j["outcome"]).lowercased()
        if итог.isEmpty {
            guard Self.завершённые.contains(A.строка(j["status"]).lowercased()), !A.да(j["return_hold"]) else { return nil }
        } else {
            guard итог == "sold" else { return nil }
        }
        let снимок = (j["listing_snapshot"] as? [String: Any]) ?? [:]
        id = номер
        var объявление = A.строка(j["product_id"])
        if объявление.isEmpty || объявление == "0" { объявление = A.строка(снимок["listing_id"]) }
        товар = объявление
        let бренд = A.строка(снимок["brand"]).isEmpty ? A.строка(j["product_brand"]) : A.строка(снимок["brand"])
        self.бренд = String(бренд.prefix(30))
        let заголовок = A.строка(j["product_title"]).isEmpty ? A.строка(снимок["title"]) : A.строка(j["product_title"])
        название = НазваниеСделки.чистое(заголовок, бренд: бренд)
        раздел = A.строка(j["category"]).isEmpty ? A.строка(снимок["category"]) : A.строка(j["category"])
        let обложка = A.строка(снимок["img"]).trimmingCharacters(in: .whitespaces)
        фото = обложка.isEmpty ? A.строка(j["product_img"]).trimmingCharacters(in: .whitespaces) : обложка
        let сумма = A.целое(j["amount"]) - max(0, A.целое(j["refund_part"]))
        цена = сумма > 0 ? сумма : nil
        let дата = [A.строка(j["outcome_at"]), A.строка(j["confirmed_at"]), A.строка(j["created_at"])]
            .lazy.compactMap { СделкиФормат.дата($0) }.first
        когда = дата
        var набор = Self.стандартыСнимка(снимок["std"])
        let нужные = РазборСтандартов.семьи(раздел: раздел, название: название)
        if !нужные.isEmpty {
            набор.дополнить(РазборСтандартов.разобрать(текст: название, семьи: нужные, источник: .сделка).набор)
        }
        набор.источник = .сделка
        let штук = A.целое(снимок["qty"])
        if штук > 1 { набор.сколько = min(999, штук) }
        стандарты = набор
        let цвет = A.строка(снимок["color"])
        цвета = цвет.isEmpty ? РазборСтандартов.цвета(название) : ЦветСтандарта.из(цвет.split(separator: ",").map(String.init))
    }

    /// std снимка: {семья: {поле: значение}} или краткая форма {семья: "E14"} — первое главное поле.
    private static func стандартыСнимка(_ сырое: Any?) -> НаборСтандартов {
        var набор = НаборСтандартов(источник: .сделка)
        guard let std = сырое as? [String: Any] else { return набор }
        for (ключ, значение) in std {
            guard let семья = СемьяСтандарта(rawValue: ключ) else { continue }
            if let поля = значение as? [String: Any] {
                for (поле, з) in поля { набор[семья, поле] = строка(з) }
            } else if let главное = семья.главные.first {
                набор[семья, главное] = строка(значение)
            }
        }
        return набор
    }

    /// Значение поля строкой: число — без лишних нулей, массив — через запятую.
    private static func строка(_ з: Any) -> String? {
        if let s = з as? String { return s }
        if let n = з as? NSNumber { return ЧислаАвтоподбора.ч(n.doubleValue, знаков: 3) }
        if let a = з as? [Any] { return a.compactMap { строка($0) }.joined(separator: ",") }
        return nil
    }

    /// Покупка для записи «Моего».
    var покупка: ПокупкаМоего {
        ПокупкаМоего(сделка: id, объявление: товар, цена: цена, когда: когда, бренд: бренд.isEmpty ? nil : бренд)
    }

    /// Куда положить — по разделу объявления.
    var предложение: РазделВещиМоего { ПокупкиМоего.раздел(раздела: раздел, название: название) }

    /// Ноутбук, ПК или моноблок целиком — ложится компьютером.
    var целыйКомпьютер: Bool { РазделыСайта.внутри(раздел, ["laptops", "desktops", "all-in-one"]) }

    var адресФото: String? { фото.isEmpty ? nil : String(фото.prefix(500)) }
}

// MARK: - Куда и как положить

enum ПокупкиМоего {
    /// Раздел «Моего» по разделу объявления; детское — без места: данные детей не собираем.
    static func раздел(раздела раздел: String, название: String) -> РазделВещиМоего {
        let внутри: (Set<String>) -> Bool = { РазделыСайта.внутри(раздел, $0) }
        if внутри(["kids", "kids-clothing", "kids-shoes"]) { return .безМеста }
        if внутри(["clothing"]) { return .гардероб }
        if внутри(["printers"]) { return .дом }
        if внутри(["laptops", "desktops", "all-in-one", "pc-components"]) { return .компьютер }
        if внутри(["electronics"]) { return .устройства }
        if внутри(["transport"]) { return .гараж }
        if внутри(["home-garden"]) { return .дом }
        if раздел.isEmpty, ВидВещиГардеробаМоего.поНазванию(название) != nil { return .гардероб }
        return .безМеста
    }

    /// Вид техники дома по разделу объявления; не техника — nil.
    static func видТехники(раздела раздел: String, название: String) -> ВидТехникиМоего? {
        let пары: [(String, ВидТехникиМоего)] = [
            ("fridges", .холодильник), ("washing-machines", .стиральная), ("dishwashers", .посудомойка),
            ("vacuum-cleaners", .пылесос), ("air-conditioners", .кондиционер), ("stoves", .плита),
            ("microwaves", .микроволновка), ("water-heaters", .водонагреватель), ("printers", .принтер)
        ]
        if let пара = пары.first(where: { РазделыСайта.внутри(раздел, [$0.0]) }) { return пара.1 }
        if РазделыСайта.внутри(раздел, ["kettles-coffee"]) {
            return название.lowercased().contains("кофе") || название.lowercased().contains("coffee") ? .кофемашина : .другая
        }
        if РазделыСайта.внутри(раздел, ["small-appliances", "appliances"]) { return .другая }
        return nil
    }

    /**
     Положить покупку в «Моё» (внутри правки хранилища): одежда — вещью гардероба; ноутбук и ПК целиком — компьютером
     (стандарты названия — в его поля); техника — в «Мой дом»; остальное — ВещьМоего с местом (машина, компьютер —
     главные) и событием в историю компьютера. false — уже добавлена или нет места.
     */
    static func положить(_ п: ПокупкаИзСделкиМоего, в раздел: РазделВещиМоего, запись з: inout ЗаписьМоего) -> Bool {
        guard з.изСделок[п.id] == nil else { return false }
        let покупка = п.покупка
        switch раздел {
        case .гардероб:
            guard з.гардероб.вещи.count < ГардеробМоего.пределВещей else { return false }
            let вещь = ВещьГардеробаМоего(вид: ВидВещиГардеробаМоего.поНазванию(п.название) ?? .другое,
                                          имя: String(п.название.prefix(ВещьГардеробаМоего.пределИмени)),
                                          цвета: п.цвета, бренд: п.бренд, адресФото: п.адресФото, покупка: покупка)
            з.гардероб.вещи.insert(вещь, at: 0)
            з.изСделок[п.id] = вещь.id
            return true
        case .компьютер where п.целыйКомпьютер && з.компьютеры.count < ЗаписьМоего.пределКомпьютеров:
            var к = компьютер(из: п)
            к.записать("bought", п.название + " · " + покупка.подписьСЦеной, когда: п.когда ?? Date())
            з.компьютеры.append(к)
            з.изСделок[п.id] = к.id
            return true
        case .дом:
            if let вид = видТехники(раздела: п.раздел, название: п.название),
               з.дом.техника.count < ДомМоего.пределТехники {
                let т = ТехникаМоего(вид: вид, бренд: п.бренд, модель: String(п.название.prefix(60)), покупка: покупка,
                                     адресФото: п.адресФото)
                з.дом.техника.append(т)
                з.изСделок[п.id] = т.id
                return true
            }
        default:
            break
        }
        guard з.вещи.count < ЗаписьМоего.пределВещей else { return false }
        var место = МестоВещиМоего(раздел)
        switch раздел {
        case .гараж: место.id = з.главнаяМашина?.id
        case .компьютер: место.id = з.главныйКомпьютер?.id
        default: break
        }
        let вещь = ВещьМоего(название: п.название, раздел: п.раздел, место: место, стандарты: п.стандарты,
                             покупка: покупка, адресФото: п.адресФото)
        з.вещи.insert(вещь, at: 0)
        з.изСделок[п.id] = вещь.id
        if раздел == .компьютер, let i = з.компьютеры.firstIndex(where: { $0.id == место.id }) {
            з.компьютеры[i].записать("bought", п.название + " · " + покупка.подписьСЦеной, когда: п.когда ?? Date())
        }
        return true
    }

    /// Ноутбук или ПК из покупки: вид, модель, покупка; сокет, процессор, память и накопитель — из названия.
    private static func компьютер(из п: ПокупкаИзСделкиМоего) -> КомпьютерМоего {
        let ноутбук = РазделыСайта.внутри(п.раздел, ["laptops"])
        var к = КомпьютерМоего(вид: ноутбук ? .ноутбук : .настольный, модель: String(п.название.prefix(80)),
                               покупка: п.покупка)
        let н = РазборСтандартов.нормально(п.название)
        if let цп = РазборСтандартов.процессор(" " + н + " ") {
            к.процессор = цп.имя
            к.сокет = цп.сокет
        }
        // Память и накопитель целого компьютера: «16GB DDR4», «SSD 512GB» — поколение и объём, примерно.
        let память = РазборСтандартов.разобрать(текст: п.название, семьи: [.память], источник: .сделка).набор
        if let поколение = память[.память, КлючСтандарта.поколение] {
            к.память.поколение = поколение
            if КаталогСтандартов.распаянныеПоколения.contains(поколение) { к.память.форма = "soldered" }
        }
        let диск = РазборСтандартов.разобрать(текст: п.название, семьи: [.накопитель], источник: .сделка).набор
        if let тб = диск.число(.накопитель, КлючСтандарта.тб) {
            к.накопители = [НакопительМоего(форма: диск[.накопитель, КлючСтандарта.форма] ?? "2280",
                                            протокол: диск[.накопитель, КлючСтандарта.протокол], тб: тб)]
        }
        return к
    }

    /// Убрать то, что добавлено из сделки (если оно всё ещё из этой сделки).
    static func убрать(сделка: String, запись з: inout ЗаписьМоего) {
        guard let id = з.изСделок[сделка] else { return }
        з.вещи.removeAll { $0.id == id && $0.покупка?.сделка == сделка }
        з.гардероб.вещи.removeAll { $0.id == id && $0.покупка?.сделка == сделка }
        з.компьютеры.removeAll { $0.id == id && $0.покупка?.сделка == сделка }
        з.дом.техника.removeAll { $0.id == id && $0.покупка?.сделка == сделка }
        з.изСделок[сделка] = nil
    }
}

// MARK: - Модель списка

/// Покупки покупателя из my_deals — в памяти на 10 минут; на диск не пишется. «Удалить всё «Моё»» и выход забывают.
@MainActor
final class ПокупкиМоегоМодель: ObservableObject {
    static let shared = ПокупкиМоегоМодель()

    enum Загрузка: Equatable {
        case нет
        case идёт
        case готово
        case нуженВход
        case ошибка
    }

    @Published private(set) var покупки: [ПокупкаИзСделкиМоего] = []
    @Published private(set) var загрузка: Загрузка = .нет

    /// Сколько помнить список без нового запроса.
    static let память: TimeInterval = 600

    private var когда: Date? = nil
    private var uid = ""
    private var поколение = 0
    private var грузим = false

    private init() {}

    /// Список с памятью: свежий (моложе 10 минут) не запрашивается; сила — потянули вниз.
    func загрузить(сила: Bool = false) async {
        guard Config.покупкиВМоё, !грузим else { return }
        if СессияПриложения.shared.вошёл == false {
            сбросить()
            загрузка = .нуженВход
            return
        }
        if !сила, загрузка == .готово, let когда, Date().timeIntervalSince(когда) < Self.память { return }
        грузим = true
        defer { грузим = false }
        let моё = поколение
        if покупки.isEmpty { загрузка = .идёт }
        do {
            let страница = try await КабинетСайта.состояние()
            guard моё == поколение else { return }
            if страница.вошёл == false {
                сбросить()
                загрузка = .нуженВход
                return
            }
            if !uid.isEmpty, !страница.uid.isEmpty, страница.uid != uid { покупки = [] }
            uid = страница.uid
            МоиОбъявленияAPI.запомнитьТокен(страница.csrf)
            guard let j = try await СделкиAPI.получить("escrow.php?action=my_deals&role=buyer") else {
                throw КабинетСайта.Сбой.приложение
            }
            guard моё == поколение else { return }
            guard СделкиAPI.да(j["ok"]) else {
                if МоиОбъявленияAPI.нетСессии(j) {
                    сбросить()
                    загрузка = .нуженВход
                } else {
                    загрузка = покупки.isEmpty ? .ошибка : .готово
                }
                return
            }
            let сырые = (j["deals"] as? [Any]) ?? []
            покупки = сырые.compactMap { з -> ПокупкаИзСделкиМоего? in
                guard let d = з as? [String: Any] else { return nil }
                return ПокупкаИзСделкиМоего(d)
            }
            когда = Date()
            загрузка = .готово
        } catch {
            guard моё == поколение else { return }
            загрузка = покупки.isEmpty ? .ошибка : .готово
        }
    }

    private func сбросить() {
        покупки = []
        когда = nil
        uid = ""
    }

    /// «Удалить всё «Моё»» и выход из аккаунта: список уходит из памяти, запрос в пути не вернёт его.
    func забыть() {
        поколение += 1
        сбросить()
        загрузка = .нет
    }
}

// MARK: - Экран

/// «Добавить из моих покупок»: пояснение, список завершённых покупок с выбором места и «В «Моё»», честный конец списка.
struct ЭкранПокупокМоего: View {
    @ObservedObject private var модель = ПокупкиМоегоМодель.shared
    @ObservedObject private var хранилище = МоёХранилище.shared
    /// Выбранное место у покупки (номер сделки → раздел); нет — предложение по разделу объявления.
    @State private var выбор: [String: РазделВещиМоего] = [:]
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init() {}

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                пояснение
                    .появлениеМоего(0)
                содержимое
                    .появлениеМоего(1)
                Label {
                    Text(т("my_deals_note"))
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
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: модель.покупки)
            .animation(ДвижениеСайта.смена, value: модель.загрузка)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(т("my_deals_title"))
        .refreshable { await модель.загрузить(сила: true) }
        .overlay(alignment: .bottom) {
            if let весть {
                ТостКабинета(текст: весть)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityHidden(true)
            }
        }
        .task {
            хранилище.подготовить()
            await модель.загрузить()
        }
    }

    private var пояснение: some View {
        HStack(alignment: .top, spacing: 12) {
            ЗначокПрофиляМоего(значок: "bag", цвет: Theme.золото)
            Text(т("my_deals_intro"))
                .font(.subheadline)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .карточкаМоего(поля: 14)
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.загрузка {
        case .нет, .идёт:
            VStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .fill(Theme.поверхность)
                        .frame(height: 88)
                        .overlay { ProgressView().opacity(0.4) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(т("my_deals_loading"))
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: т("my_deals_login_t"), подпись: т("my_deals_login_s"))
        case .ошибка:
            ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("my_deals_err_t"), подпись: nil,
                       кнопка: т("my_deals_retry"), действие: {
                           Task { await модель.загрузить(сила: true) }
                       })
        case .готово:
            if модель.покупки.isEmpty {
                ПустоСайта(значок: "bag", заголовок: т("my_deals_empty_t"), подпись: т("my_deals_empty_s"))
            } else {
                список
            }
        }
    }

    private var список: some View {
        LazyVStack(spacing: 10) {
            ForEach(модель.покупки) { покупка in
                СтрокаПокупкиМоего(покупка: покупка, добавлена: хранилище.вМоём(сделка: покупка.id),
                                   раздел: выбор[покупка.id] ?? покупка.предложение,
                                   выбрать: { раздел in
                                       withAnimation(ДвижениеСайта.выбор) { выбор[покупка.id] = раздел }
                                   },
                                   добавить: { добавить(покупка) },
                                   убрать: { убрать(покупка) })
            }
            Text(т("my_deals_end"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private func добавить(_ покупка: ПокупкаИзСделкиМоего) {
        let раздел = выбор[покупка.id] ?? покупка.предложение
        if хранилище.добавитьПокупку(покупка, в: раздел) {
            ОткликСайта.успех()
            показатьВесть(String(format: т("my_deals_added"), раздел.название))
        } else {
            ОткликСайта.предупреждение()
            показатьВесть(т("my_deals_fail"))
        }
    }

    private func убрать(_ покупка: ПокупкаИзСделкиМоего) {
        хранилище.убратьПокупку(сделка: покупка.id)
        ОткликСайта.выбор()
        показатьВесть(т("my_deals_removed"))
    }

    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}

/// Строка покупки: обложка, название, «Куплено на Kliko · окт 2026 · 25 000 ₸», чип «Куда положить» и «В «Моё»» —
/// добавленная: «В «Моём» ✓» и «Убрать». Для VoiceOver — один элемент с действиями.
private struct СтрокаПокупкиМоего: View {
    let покупка: ПокупкаИзСделкиМоего
    let добавлена: Bool
    let раздел: РазделВещиМоего
    let выбрать: (РазделВещиМоего) -> Void
    let добавить: () -> Void
    let убрать: () -> Void

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            обложка
            VStack(alignment: .leading, spacing: 6) {
                Text(покупка.название)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(покупка.покупка.подписьСЦеной)
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    куда
                    Spacer(minLength: 4)
                    кнопка
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .карточкаМоего(поля: 12)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: добавлена ? т("my_deals_remove") : т("my_deals_add")) {
            добавлена ? убрать() : добавить()
        }
    }

    private var обложка: some View {
        КартинкаЛенты(Config.url(покупка.фото), пунктов: 56) {
            ZStack {
                Theme.поверхность2
                Image(systemName: раздел.значок)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .accessibilityHidden(true)
    }

    /// «Куда положить»: меню разделов; добавленная — только подпись места.
    @ViewBuilder
    private var куда: some View {
        if добавлена {
            Label(раздел.название, systemImage: раздел.значок)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
        } else {
            Menu {
                ForEach(РазделВещиМоего.allCases, id: \.self) { вариант in
                    Button {
                        выбрать(вариант)
                    } label: {
                        Label(вариант.название, systemImage: вариант == раздел ? "checkmark" : вариант.значок)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: раздел.значок)
                        .font(.caption.weight(.bold))
                    Text(раздел.название)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(Theme.оттенокАкцента, in: Capsule())
                .contentTransition(.opacity)
            }
            .accessibilityLabel(т("my_deals_where") + ": " + раздел.название)
        }
    }

    @ViewBuilder
    private var кнопка: some View {
        if добавлена {
            Menu {
                Button(role: .destructive, action: убрать) {
                    Label(т("my_deals_remove"), systemImage: "minus.circle")
                }
            } label: {
                Label(т("my_deals_in"), systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(minHeight: 30)
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else {
            Button(action: добавить) {
                Label(т("my_deals_add"), systemImage: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(Theme.зелёный2, in: Capsule())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }
}
