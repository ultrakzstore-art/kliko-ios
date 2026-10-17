import SwiftUI
import UIKit

/**
 «МОЁ» — ХАБ (владелец 16.10.2026: «по всем моментам разом»; «мощная анимированная подача»).

 Вход — карточка «Моё» в кабинете (гостю тоже) и «Мой гараж» в «Подойдут ли?». Экран — шапка с общим прогрессом,
 карточки профилей ровной высоты 96 pt: гараж, устройства, рост и мерки, а с пачки 16.10.2026 «мой дом, компьютер,
 гардероб и для вас» — «Мой дом», «Мой компьютер», «Мой гардероб» (на iPad — две строки по три колонки) и строка
 «Добавить из моих покупок». Подача — каскад ПоявлениеМоего (шапка 0, карточки 1–6, покупки 7) и кольца, дорастающие
 пружиной; «Удалить всё» — кольца уходят проявлением, сводки сменяются, внизу весть «Удалено с телефона».

 Пачка 83 (аудит упрощений, «Моё» главный): «Удалить всё «Моё»» — только в меню «…» шапки (и в общей очистке
 кабинета), красной кнопки внизу нет; «Только на этом телефоне» — одной капсулой в шапке (ШапкаМоего), строки с замком
 внизу нет; пустая карточка — название, одна строка пользы и чип действия, без кольца 0 % (КарточкаХабаМоего).

 В стеке кабинета переходы к первым трём — через переходКабинета (КабинетЦель: .моё, .мойГараж, .моиУстройства,
 .моиМерки); к новым разделам — значением ЦельМоего (стек кабинета — NavigationPath, цель регистрирует сам хаб). В окне
 поверх любого экрана (ОкноМоего) — свой стек с той же регистрацией; ОкноМоего.открыть(раздел:) открывает новый раздел
 сразу (из «Для вас», плашки «Подходит моему», чипа ленты).
 */
struct ЭкранМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.horizontalSizeClass) private var класс
    @State private var спросить = false
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init() {}

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        let запись = хранилище.запись
        ScrollView {
            VStack(spacing: 16) {
                ШапкаМоего(доля: запись.готовность, всё: запись.всёГотово)
                    .появлениеМоего(0)
                карточки(запись)
                разделы(запись)
                if Config.покупкиВМоё {
                    ПереходРазделаМоего(цель: .изПокупок) {
                        КарточкаПокупокМоего(добавлено: запись.изСделок.count)
                    }
                    .появлениеМоего(7)
                }
            }
            .padding(16)
            .frame(maxWidth: класс == .regular ? 960 : 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(т("my_title"))
        .navigationDestination(for: ЦельМоего.self) { цель in
            ЭкранЦелиМоего(цель: цель)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        спросить = true
                    } label: {
                        Label(т("my_delete_all"), systemImage: "trash")
                    }
                    .disabled(запись.пусто)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(т("my_more_actions"))
                }
            }
        }
        .confirmationDialog(т("my_delete_all_q"), isPresented: $спросить, titleVisibility: .visible) {
            Button(т("my_delete"), role: .destructive) { стереть() }
            Button(т("my_cancel"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let весть {
                ТостКабинета(текст: весть)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityHidden(true)
            }
        }
        .onAppear { хранилище.подготовить() }
    }

    /// Три профиля: на iPhone — столбиком, на iPad — в три колонки.
    @ViewBuilder
    private func карточки(_ запись: ЗаписьМоего) -> some View {
        if класс == .regular {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ПрофильМоего.allCases) { профиль in
                    карточка(профиль, запись)
                }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(ПрофильМоего.allCases) { профиль in
                    карточка(профиль, запись)
                }
            }
        }
    }

    private func карточка(_ профиль: ПрофильМоего, _ запись: ЗаписьМоего) -> some View {
        ПереходМоего(цель: профиль.цель) {
            КарточкаПрофиляМоего(профиль: профиль, сводка: запись.сводка(профиль), прогресс: профиль.прогресс(запись),
                                 номер: профиль.rawValue)
        }
        .появлениеМоего(профиль.rawValue + 1)
    }

    /// Дом, компьютер, гардероб (включённые рубильниками): на iPhone — столбиком, на iPad — второй строкой в три колонки.
    @ViewBuilder
    private func разделы(_ запись: ЗаписьМоего) -> some View {
        let включённые = РазделМоего.включённые
        if !включённые.isEmpty {
            if класс == .regular {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(включённые) { раздел in
                        карточкаРаздела(раздел, запись)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(включённые) { раздел in
                        карточкаРаздела(раздел, запись)
                    }
                }
            }
        }
    }

    private func карточкаРаздела(_ раздел: РазделМоего, _ запись: ЗаписьМоего) -> some View {
        ПереходРазделаМоего(цель: раздел.цель) {
            КарточкаРазделаМоего(раздел: раздел, сводка: раздел.сводка(запись), прогресс: раздел.прогресс(запись),
                                 номер: раздел.rawValue + ПрофильМоего.allCases.count)
        }
        .появлениеМоего(раздел.rawValue + ПрофильМоего.allCases.count + 1)
    }

    private func стереть() {
        хранилище.стереть()
        ОткликСайта.успех()
        показатьВесть(т("my_deleted"))
    }

    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}

// MARK: - Цели стека

/// Экран «Моего» по цели стека (кабинет и окно поверх). Прочие цели сюда не приходят.
struct ЭкранРазделаМоего: View {
    let цель: КабинетЦель

    init(цель: КабинетЦель) {
        self.цель = цель
    }

    var body: some View {
        switch цель {
        case .моё:
            ЭкранМоего()
        case .мойГараж:
            ЭкранГаражаМоего()
        case .моиУстройства:
            ЭкранУстройствМоего()
        case .моиМерки:
            ЭкранТелаМоего()
        default:
            EmptyView()
        }
    }
}

/**
 Новые разделы «Моего» (пачка 16.10.2026) — своя цель стека: КабинетЦель — общий файл кабинета, его не трогаем. Стек
 кабинета — NavigationPath, поэтому NavigationLink(value: ЦельМоего) кладёт её туда же; экран находит хаб, который
 регистрирует navigationDestination(for: ЦельМоего.self), а в окне поверх — само окно.
 */
enum ЦельМоего: Hashable, Sendable {
    case дом
    case компьютер
    case гардероб
    /// «Добавить из моих покупок» (MyThingsFromDeals.swift).
    case изПокупок
}

/// Экран нового раздела «Моего» по цели. Экраны дома, компьютера и гардероба — init() без параметров.
struct ЭкранЦелиМоего: View {
    let цель: ЦельМоего

    init(цель: ЦельМоего) {
        self.цель = цель
    }

    var body: some View {
        switch цель {
        case .дом:
            ЭкранМоегоДома()
        case .компьютер:
            ЭкранМоегоКомпьютера()
        case .гардероб:
            ЭкранМоегоГардероба()
        case .изПокупок:
            ЭкранПокупокМоего()
        }
    }
}

/// Переход к новому разделу «Моего» — NavigationLink(value:) с нажатием сайта; своей стрелки нет — её рисует метка.
struct ПереходРазделаМоего<Метка: View>: View {
    let цель: ЦельМоего
    @ViewBuilder let метка: () -> Метка

    init(цель: ЦельМоего, @ViewBuilder метка: @escaping () -> Метка) {
        self.цель = цель
        self.метка = метка
    }

    var body: some View {
        NavigationLink(value: цель) {
            метка()
        }
        .buttonStyle(НажатиеСайта())
    }
}

// MARK: - Окно поверх любого экрана

/// «Моё» поверх любого экрана (из «Подойдут ли?», с плашки «Подходит моему», чипа ленты и «Для вас»): свой стек и
/// «Закрыть».
@MainActor
enum ОкноМоего {
    static func открыть(_ цель: КабинетЦель = .моё) {
        guard Config.моё else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ОкноМоегоВид(корень: .кабинет(цель), закрыть: закрыть)
        }
    }

    /// Новый раздел сразу: «Мой дом», «Мой компьютер», «Мой гардероб», «Добавить из моих покупок».
    static func открыть(раздел цель: ЦельМоего) {
        guard Config.моё else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ОкноМоегоВид(корень: .раздел(цель), закрыть: закрыть)
        }
    }
}

private struct ОкноМоегоВид: View {
    enum Корень {
        case кабинет(КабинетЦель)
        case раздел(ЦельМоего)
    }

    let корень: Корень
    let закрыть: () -> Void

    var body: some View {
        NavigationStack {
            корневой
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(МоёText.т("my_close"), action: закрыть)
                    }
                }
                .navigationDestination(for: КабинетЦель.self) { следующая in
                    ЭкранРазделаМоего(цель: следующая)
                }
        }
        .tint(Theme.акцент)
    }

    /// Корень окна. Хаб регистрирует ЦельМоего сам; у раздела — окно (иначе «Добавить из моих покупок» из раздела
    /// некуда положить).
    @ViewBuilder
    private var корневой: some View {
        switch корень {
        case .кабинет(let цель):
            ЭкранРазделаМоего(цель: цель)
        case .раздел(let цель):
            ЭкранЦелиМоего(цель: цель)
                .navigationDestination(for: ЦельМоего.self) { следующая in
                    ЭкранЦелиМоего(цель: следующая)
                }
        }
    }
}

// MARK: - Сводки карточек

extension ЗаписьМоего {
    func сводка(_ профиль: ПрофильМоего) -> String {
        switch профиль {
        case .гараж: return сводкаГаража
        case .устройства: return сводкаУстройств
        case .тело: return сводкаТела
        }
    }

    /// «Toyota Camry, 2018 · 5×114.3 · R17 · + ещё 1». Машины нет — польза одной строкой (чип «＋ Добавьте машину»
    /// стоит рядом, повторять его не нужно).
    var сводкаГаража: String {
        guard let м = главнаяМашина else { return МоёText.т("my_garage_use") }
        var части = [м.заголовок]
        if let р = м.посадка?.разболтовка { части.append(р.подпись) }
        if let r = м.посадка?.штатныеДиаметры.first { части.append("R" + ЧислаАвтоподбора.ч(r)) }
        if машины.count > 1 { части.append(String(format: МоёText.т("my_more"), String(машины.count - 1))) }
        return части.joined(separator: " · ")
    }

    /// «iPhone 15 Pro · ноутбук 15.6″ · ТВ 55″».
    var сводкаУстройств: String {
        var части: [String] = []
        if let т = телефон { части.append(т.модель) }
        for у in устройства where у.заполнено {
            части.append(у.короткоВСводке)
        }
        guard !части.isEmpty else { return МоёText.т("my_devices_empty") }
        return части.prefix(3).joined(separator: " · ")
    }

    /// «176 см · EU 42 · RU 48».
    var сводкаТела: String {
        var части: [String] = []
        if let рост = тело.рост { части.append(String(рост) + " " + МоёТелоText.т("mb_cm")) }
        for размер in тело.размеры.prefix(3) { части.append(размер.коротко) }
        if части.isEmpty && !тело.мерки.isEmpty {
            части.append(МоёТелоText.т("mb_measures") + ": " + String(тело.мерки.count))
        }
        guard !части.isEmpty else { return МоёText.т("my_body_empty") }
        return части.joined(separator: " · ")
    }
}

extension УстройствоМоего {
    /// «ноутбук 15.6″», «ТВ 55″»; без диагонали — модель или вид.
    var короткоВСводке: String {
        let ключ: String
        switch вид {
        case .ноутбук: ключ = "md_s_laptop"
        case .монитор: ключ = "md_s_monitor"
        case .тв: ключ = "md_s_tv"
        }
        if let д = диагональ { return String(format: МоёТелоText.т(ключ), ЧислоМоего.дюймы(д)) }
        let своя = модель.trimmingCharacters(in: .whitespacesAndNewlines)
        return своя.isEmpty ? вид.название : своя
    }
}

// MARK: - Новые разделы: дом, компьютер, гардероб

/// Разделы пачки 16.10.2026 — карточки хаба после трёх профилей; rawValue — порядок.
enum РазделМоего: Int, CaseIterable, Identifiable {
    case дом
    case компьютер
    case гардероб

    var id: Int { rawValue }

    /// Включённые рубильниками (Config.мойДом, мойКомпьютер, мойГардероб).
    static var включённые: [РазделМоего] {
        allCases.filter { раздел in
            switch раздел {
            case .дом: return Config.мойДом
            case .компьютер: return Config.мойКомпьютер
            case .гардероб: return Config.мойГардероб
            }
        }
    }

    var значок: String {
        switch self {
        case .дом: return "house"
        case .компьютер: return "desktopcomputer"
        case .гардероб: return "hanger"
        }
    }

    var цвет: Color {
        switch self {
        case .дом: return Theme.цвет(0x0F766E, 0x2DD4BF)
        case .компьютер: return Theme.цвет(0x4F46E5, 0x8B9CF8)
        case .гардероб: return Theme.цвет(0xBE185D, 0xF472B6)
        }
    }

    var название: String {
        switch self {
        case .дом: return МоёText.т("my_home")
        case .компьютер: return МоёText.т("my_pc")
        case .гардероб: return МоёText.т("my_wardrobe")
        }
    }

    var цель: ЦельМоего {
        switch self {
        case .дом: return .дом
        case .компьютер: return .компьютер
        case .гардероб: return .гардероб
        }
    }

    func прогресс(_ запись: ЗаписьМоего) -> ПрогрессМоего {
        switch self {
        case .дом: return запись.прогрессДома
        case .компьютер: return запись.прогрессКомпьютера
        case .гардероб: return запись.прогрессГардероба
        }
    }

    func сводка(_ запись: ЗаписьМоего) -> String {
        switch self {
        case .дом: return запись.сводкаДома
        case .компьютер: return запись.сводкаКомпьютера
        case .гардероб: return запись.сводкаГардероба
        }
    }
}

extension ЗаписьМоего {
    /// «160×200 · E27 ×6 · дверь 80 см» — до трёх частей.
    var сводкаДома: String {
        var части: [String] = []
        if let место = дом.кровати.compactMap(\.место).first { части.append(КаталогСтандартов.показ(место)) }
        let цоколи = дом.цоколи.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        if let первый = цоколи.first { части.append(первый.key + " ×" + String(первый.value)) }
        if let узкий = дом.самыйУзкий, let ширина = узкий.ширина {
            части.append(String(format: МоёText.т("my_home_door_cm"), String(ширина)))
        } else if !дом.комнаты.isEmpty {
            части.append(String(format: МоёText.т("my_home_rooms_n"), String(дом.комнаты.count)))
        }
        guard !части.isEmpty else { return МоёText.т("my_home_empty") }
        return части.prefix(3).joined(separator: " · ")
    }

    /// «Ryzen 5 5600 · 16 ГБ DDR4 · RTX 3060 · + ещё 1».
    var сводкаКомпьютера: String {
        guard let к = главныйКомпьютер else { return МоёText.т("my_pc_empty") }
        var текст = к.сводка
        if текст.isEmpty { текст = к.заголовок }
        if компьютеры.count > 1 {
            текст += " · " + String(format: МоёText.т("my_more"), String(компьютеры.count - 1))
        }
        return текст
    }

    /// «Вещей: 12 · Образов: 3 · Zara M — мала в плечах».
    var сводкаГардероба: String {
        var части: [String] = []
        if !гардероб.вещи.isEmpty {
            части.append(String(format: МоёText.т("my_wear_items_n"), String(гардероб.вещи.count)))
        }
        if !гардероб.образы.isEmpty {
            части.append(String(format: МоёText.т("my_wear_outfits_n"), String(гардероб.образы.count)))
        }
        if let заметка = гардероб.посадка.last { части.append(заметка.подпись) }
        guard !части.isEmpty else { return МоёText.т("my_wardrobe_empty") }
        return части.joined(separator: " · ")
    }
}

/// Карточка нового раздела хаба — та же карточка хаба (КарточкаХабаМоего), что у профилей: ровно 96 pt, значок,
/// название, сводка, чип следующего шага, кольцо (у пустой — без кольца).
struct КарточкаРазделаМоего: View {
    let раздел: РазделМоего
    let сводка: String
    let прогресс: ПрогрессМоего
    let номер: Int

    init(раздел: РазделМоего, сводка: String, прогресс: ПрогрессМоего, номер: Int) {
        self.раздел = раздел
        self.сводка = сводка
        self.прогресс = прогресс
        self.номер = номер
    }

    var body: some View {
        КарточкаХабаМоего(значок: раздел.значок, цвет: раздел.цвет, название: раздел.название, сводка: сводка,
                          прогресс: прогресс, номер: номер)
    }
}

/// «Добавить из моих покупок» — карточка 72 pt под разделами: значок пакета, подпись, сколько уже добавлено.
struct КарточкаПокупокМоего: View {
    let добавлено: Int

    init(добавлено: Int) {
        self.добавлено = добавлено
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        let подпись = добавлено > 0 ? String(format: МоёText.т("my_deals_added_n"), String(добавлено))
            : МоёText.т("my_deals_sub")
        HStack(spacing: 12) {
            ЗначокПрофиляМоего(значок: "bag", цвет: Theme.золото)
            VStack(alignment: .leading, spacing: 2) {
                Text(МоёText.т("my_deals_title"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            СтрелкаСтрокиКабинета()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72, alignment: .leading)
        .background(Theme.поверхность, in: форма)
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        .contentShape(форма)
        .animation(ДвижениеСайта.смена, value: добавлено)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(МоёText.т("my_deals_title") + ". " + подпись)
        .accessibilityAddTraits(.isButton)
    }
}

/// Заглушка раздела, пока его экран не готов: шапка раздела и «готовим этот раздел» (экраны заменяют её целиком).
struct ЗаглушкаРазделаМоего: View {
    let раздел: РазделМоего

    init(раздел: РазделМоего) {
        self.раздел = раздел
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ЗначокПрофиляМоего(значок: раздел.значок, цвет: раздел.цвет, размер: 56)
                Text(раздел.название)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(МоёText.т("my_soon"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .карточкаМоего()
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(раздел.название)
    }
}
