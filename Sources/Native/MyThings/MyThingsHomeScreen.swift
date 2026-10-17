import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ ДОМ» (пачка 16.10.2026 «мой дом, компьютер, гардероб и для вас»; владелец: «мой дом — что можно по
 дому?»; «стандарты: по ним изи точечно подбирать, что почём; шаблоны»; «удобно для глаз, ровная схема везде, мощная
 анимированная подача, летает на всех девайсах»; TestFlight 81: «вот эти моменты упростить + чтобы отсюда поиск и сюда
 вставить то, что подходит»).

 Экран сверху вниз — короткий и ровный (каскад ПоявлениеМоего, как у хаба):
   · шапка — кольцо прогресса дома (прогрессДома), сводка («160×200 · E27 ×6 · дверь 74 см») и следующий шаг;
   · «Пройдёт ли в дверь и лифт?» — вещь шаблоном одним рядом или «Свои размеры» против пути в дом
     (MyThingsHomePass.swift); путь не указан — одна кнопка «Указать двери и лифт» (лист проёмов);
   · разделы — по строке-карточке (КарточкаРазделаДома): значок, название, что сохранено одной строкой («Кровать
     160×200», «130×140, 145×150», «Не заполнено»), справа «Изменить ›» или «Добавить». Шаблоны чипами — не здесь, а в
     листах: «Изменить» открывает лист раздела (ЛистРазделаДома — строки, шаблоны, этаж и «Лифта нет», цоколи, стиль),
     «Добавить» у пустого — сразу лист новой вещи с шаблонами внутри (у проёмов, света и стиля — лист раздела);
   · под заполненным разделом — ряд «Подходит вам» (РядПодходитМоего, MyThingsFitRow.swift): кровать — матрасы и бельё
     этого размера, окна — шторы и жалюзи, ТВ — кронштейны по VESA, свет — лампы по цоколю; ничего не подошло — ряда
     нет, есть «Найти подходящее» (лента раздела с «Для моего»); у проёмов и техники — только «Найти подходящее»;
   · купленное на Kliko для дома и «Добавить из моих покупок».
 Разделы — ленивым столбцом: ряд «Подходит вам» идёт в сеть, только когда доехал до экрана. Листы правки —
 MyThingsHomeSheets.swift. Всё — только на телефоне (МоёХранилище.обновитьДом), на сервер ничего не уходит; камера и
 фото — только по нажатию; цвета фото и текст наклейки читаются на телефоне.

 Ширина — до 680 pt (iPad), на iPhone SE — те же карточки столбиком. «Уменьшение движения» и лёгкий режим — без полёта
 (ДвижениеСайта, РежимУстройства), VoiceOver — строки одним элементом, регуляторы — регулируемые.
 Экран не регистрирует ЦельМоего сам: это делают хаб и окно «Моего» (MyThingsHub.swift).
 */
struct ЭкранМоегоДома: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var лист: ЛистДомаМоего? = nil

    init() {}

    var body: some View {
        let запись = хранилище.запись
        ScrollView {
            LazyVStack(spacing: 14) {
                верх(запись)
                разделы(запись)
                низ(запись)
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: запись.дом)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(МоёText.т("my_home"))
        .клавиатураМоего()
        .sheet(item: $лист) { цель in
            ЛистДомаВид(лист: цель)
        }
        .onAppear { хранилище.подготовить() }
    }

    private func открыть(_ цель: ЛистДомаМоего) {
        лист = цель
    }

    @ViewBuilder
    private func верх(_ запись: ЗаписьМоего) -> some View {
        ШапкаДомаМоего(прогресс: запись.прогрессДома, сводка: запись.сводкаДома)
            .появлениеМоего(0)
        КарточкаПроходаДома(дом: запись.дом, открыть: открыть)
            .появлениеМоего(1)
    }

    /// Разделы строками; у заполненного — ряд «Подходит вам» в той же карточке.
    private func разделы(_ запись: ЗаписьМоего) -> some View {
        ForEach(РазделДомаМоего.allCases, id: \.self) { раздел in
            карточкаРаздела(раздел, запись)
                .появлениеМоего(2 + раздел.порядок)
        }
    }

    private func карточкаРаздела(_ раздел: РазделДомаМоего, _ запись: ЗаписьМоего) -> some View {
        let дом: ДомМоего = запись.дом
        let сводка: String? = КарточкаРазделаДома.сохранено(раздел, дом)
        let цвета: [ЦветСтандарта] = раздел == .стиль ? дом.палитра : []
        let ищу: ЗапросИщуМоего? = сводка == nil ? nil : ИщуМоего.дом(раздел, дом)
        return КарточкаРазделаДома(раздел: раздел, сводка: сводка, цвета: цвета, ищу: ищу) {
            if сводка == nil {
                добавить(раздел, дом)
            } else {
                открыть(.раздел(раздел))
            }
        }
    }

    /// «Добавить» у пустого раздела: лист новой вещи — шаблоны в нём; комната кладётся сразу (пустая при закрытии
    /// уходит сама); проёмы, свет и стиль — лист раздела (этаж, «Лифта нет», цоколи, цвета).
    private func добавить(_ раздел: РазделДомаМоего, _ дом: ДомМоего) {
        switch раздел {
        case .комнаты:
            guard дом.комнаты.count < ДомМоего.пределКомнат else { return }
            let новая = КомнатаМоего(вид: .другая)
            МоёХранилище.shared.обновитьДом { д in д.комнаты.append(новая) }
            открыть(.комната(новая.id, новая: true))
        case .кровати:
            открыть(.кровать(КроватьМоего(), новая: true))
        case .окна:
            открыть(.окно(ОкноДомаМоего(), новое: true))
        case .экраны:
            открыть(.экран(ЭкранНаСтенеМоего(), новый: true))
        case .техника:
            открыть(.техника(ТехникаМоего(вид: .другая), новая: true))
        case .проёмы, .свет, .стиль:
            открыть(.раздел(раздел))
        }
    }

    @ViewBuilder
    private func низ(_ запись: ЗаписьМоего) -> some View {
        let купленное = запись.вещиВ(.дом)
        let после: Int = 2 + РазделДомаМоего.allCases.count
        if !купленное.isEmpty || Config.покупкиВМоё {
            КарточкаКупленногоДома(вещи: купленное, дом: запись.дом)
                .появлениеМоего(после)
        }
        приватность
            .появлениеМоего(после + 1)
    }

    private var приватность: some View {
        Label {
            Text(МойДомText.т("mh_local"))
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
}

// MARK: - Разделы

/// Разделы «Моего дома» на главном экране — по строке на каждый, в этом порядке.
enum РазделДомаМоего: String, CaseIterable, Hashable {
    case комнаты = "rooms"
    case проёмы = "openings"
    case кровати = "beds"
    case окна = "windows"
    case экраны = "tvs"
    case свет = "light"
    case техника = "appliances"
    case стиль = "style"

    var название: String {
        switch self {
        case .комнаты: return МойДомText.т("mh_rooms")
        case .проёмы: return МойДомText.т("mh_openings")
        case .кровати: return МойДомText.т("mh_beds")
        case .окна: return МойДомText.т("mh_windows")
        case .экраны: return МойДомText.т("mh_tvs")
        case .свет: return МойДомText.т("mh_light")
        case .техника: return МойДомText.т("mh_appliances")
        case .стиль: return МойДомText.т("mh_style")
        }
    }

    var значок: String {
        switch self {
        case .комнаты: return "square.split.2x2"
        case .проёмы: return "door.left.hand.open"
        case .кровати: return "bed.double"
        case .окна: return "window.casement"
        case .экраны: return "tv"
        case .свет: return "lightbulb"
        case .техника: return "powerplug"
        case .стиль: return "paintpalette"
        }
    }

    /// Место в каскаде появления (после шапки и «Пройдёт ли?»).
    var порядок: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Ряд «Подходит вам» под строкой раздела; у комнат и стиля его нет.
    var подбор: ПодборРазделаМоего? {
        switch self {
        case .проёмы: return .проёмы
        case .кровати: return .кровати
        case .окна: return .окна
        case .экраны: return .экраны
        case .свет: return .свет
        case .техника: return .техника
        case .комнаты, .стиль: return nil
        }
    }

    func заполнен(_ дом: ДомМоего) -> Bool {
        switch self {
        case .комнаты: return !дом.комнаты.isEmpty
        case .проёмы: return !дом.проёмы.isEmpty || дом.этаж != nil || дом.лифтаНет
        case .кровати: return !дом.кровати.isEmpty
        case .окна: return !дом.окна.isEmpty
        case .экраны: return !дом.экраны.isEmpty
        case .свет: return !дом.лампы.isEmpty
        case .техника: return !дом.техника.isEmpty
        case .стиль: return !дом.стиль.isEmpty || !дом.палитра.isEmpty
        }
    }
}

/**
 Раздел на главном экране дома: строка 48 pt — значок, название, что сохранено одной строкой (у стиля — и круги цвета),
 справа «Изменить ›» или «Добавить» капсулой; касание всей строки — то же. Под строкой в той же карточке — ряд «Подходит
 вам» (он сам решает, показаться ли: пусто — места не занимает; заполнено, а ряда нет — «Найти подходящее»), а под
 ним у кровати, света и ТВ — «Ищу матрас 160×200» (пачка 83: сохранённый поиск со стандартом, MyThingsWanted.swift).
 */
struct КарточкаРазделаДома: View {
    let раздел: РазделДомаМоего
    /// nil — раздел не заполнен.
    let сводка: String?
    let цвета: [ЦветСтандарта]
    /// «Ищу матрас 160×200» под рядом (пачка 83, MyThingsWanted.swift); nil — кнопки нет.
    let ищу: ЗапросИщуМоего?
    let действие: () -> Void
    @Environment(\.dynamicTypeSize) private var размерТекста

    init(раздел: РазделДомаМоего, сводка: String?, цвета: [ЦветСтандарта] = [], ищу: ЗапросИщуМоего? = nil,
         действие: @escaping () -> Void) {
        self.раздел = раздел
        self.сводка = сводка
        self.цвета = цвета
        self.ищу = ищу
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    private var текстСводки: String { сводка ?? т("mh_not_filled") }
    private var текстДействия: String { сводка == nil ? МоёText.т("my_add") : т("mh_edit") }

    // MARK: Что сохранено

    /**
     Что сохранено — одной строкой: «Кровать 160×200», «130×140, 145×150», «E27 ×4 · GU10 ×6»; пусто — nil. Здесь, а
     не у РазделДомаМоего: берёт заголовки у карточек разделов (КарточкаКроватейДома.заголовок…), а они — виды.
     */
    static func сохранено(_ раздел: РазделДомаМоего, _ дом: ДомМоего) -> String? {
        guard раздел.заполнен(дом) else { return nil }
        switch раздел {
        case .комнаты: return Self.сводкаКомнат(дом)
        case .проёмы: return Self.сводкаПроёмов(дом)
        case .кровати: return Self.сводкаКроватей(дом)
        case .окна: return Self.сводкаОкон(дом)
        case .экраны: return Self.сводкаЭкранов(дом)
        case .свет: return Self.сводкаСвета(дом)
        case .техника: return Self.список(дом.техника.map(\.заголовок))
        case .стиль: return Self.сводкаСтиля(дом)
        }
    }

    /// Первые несколько через запятую и «+N» за остальные.
    private static func список(_ части: [String], предел: Int = 3, через: String = ", ") -> String {
        let видно: [String] = Array(части.prefix(предел))
        var текст: String = видно.joined(separator: через)
        let ещё: Int = части.count - видно.count
        if ещё > 0 { текст += " +" + String(ещё) }
        return текст
    }

    /// Одна комната — «Спальня · ≈ 3×4 м · 12 м²»; несколько — названия.
    private static func сводкаКомнат(_ дом: ДомМоего) -> String {
        if дом.комнаты.count == 1, let к = дом.комнаты.first {
            guard let размеры = МойДомЧисла.комната(к) else { return к.заголовок }
            return к.заголовок + " · " + размеры
        }
        let имена: [String] = дом.комнаты.map(\.заголовок)
        return список(имена)
    }

    /// «Входная дверь 74 см · Лифт 80 см · 5 этаж»; «Лифта нет».
    private static func сводкаПроёмов(_ дом: ДомМоего) -> String {
        let см: String = МойДомText.т("mh_cm")
        var названия: [String] = []
        for п in дом.проёмы {
            var проём: String = КарточкаПроёмовДома.заголовок(п)
            if let ш = п.ширина { проём += " " + String(ш) + " " + см }
            названия.append(проём)
        }
        var части: [String] = []
        if !названия.isEmpty { части.append(список(названия, предел: 2, через: " · ")) }
        if let этаж = дом.этаж {
            let ярус: String = этаж <= 1
                ? МойДомText.т("mh_s_floor_ground")
                : String(format: МойДомText.т("mh_s_floor"), String(этаж))
            части.append(ярус)
        }
        let естьЛифт: Bool = дом.проёмы.contains { $0.вид == .лифт }
        if дом.лифтаНет && !естьЛифт { части.append(МойДомText.т("mh_no_lift")) }
        return части.joined(separator: " · ")
    }

    /// Одна — «Кровать 160×200»; несколько — «160×200, 90×200».
    private static func сводкаКроватей(_ дом: ДомМоего) -> String {
        if дом.кровати.count == 1, let к = дом.кровати.first { return КарточкаКроватейДома.заголовок(к) }
        let места: [String] = дом.кровати.compactMap(\.место)
        let размеры: [String] = места.map { (м: String) -> String in КаталогСтандартов.показ(м) }
        guard !размеры.isEmpty else { return МойДомText.т("mh_bed") }
        return список(размеры)
    }

    /// Одно — «Окно 130×140 см»; несколько — «130×140, 145×150».
    private static func сводкаОкон(_ дом: ДомМоего) -> String {
        if дом.окна.count == 1, let о = дом.окна.first { return КарточкаОконДома.заголовок(о) }
        var размеры: [String] = []
        for о in дом.окна {
            guard let ш = о.ширина, let в = о.высота else { continue }
            размеры.append(String(ш) + "×" + String(в))
        }
        guard !размеры.isEmpty else { return МойДомText.т("mh_window") }
        return список(размеры)
    }

    /// Один — «ТВ 55″ · VESA 300×300»; несколько — «ТВ 55″, 43″».
    private static func сводкаЭкранов(_ дом: ДомМоего) -> String {
        if дом.экраны.count == 1, let э = дом.экраны.first { return КарточкаЭкрановДома.заголовок(э) }
        var диагонали: [String] = []
        for э in дом.экраны {
            if let д = э.диагональ { диагонали.append(ЧислоМоего.дюймы(д)) }
        }
        let начало: String = МойДомText.т("mh_tv_short")
        guard !диагонали.isEmpty else { return начало }
        return начало + " " + список(диагонали)
    }

    /// «E27 ×4 · GU10 ×6» — сначала цоколи, где ламп больше.
    private static func сводкаСвета(_ дом: ДомМоего) -> String {
        let счёт: [String: Int] = дом.цоколи
        let коды: [String] = счёт.keys.sorted { (а: String, б: String) -> Bool in
            let на: Int = счёт[а] ?? 0
            let нб: Int = счёт[б] ?? 0
            if на != нб { return на > нб }
            return а < б
        }
        var части: [String] = []
        for код in коды {
            let сколько: Int = счёт[код] ?? 0
            части.append(код + " ×" + String(сколько))
        }
        return список(части, через: " · ")
    }

    /// «Сканди, Лофт»; стиля нет, а цвета есть — «Цвета дома» (круги цвета — рядом).
    private static func сводкаСтиля(_ дом: ДомМоего) -> String {
        let стили: [String] = дом.стиль.map(\.название)
        guard !стили.isEmpty else { return МойДомText.т("mh_colors") }
        return список(стили)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            строка
            if let подбор = раздел.подбор {
                РядПодходитМоего(подбор)
            }
            if let ищу {
                КнопкаИщуМоего(ищу)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .карточкаМоего(поля: 14)
    }

    private var строка: some View {
        Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: раздел.значок, цвет: РазделМоего.дом.цвет, размер: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(раздел.название)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                    подпись
                }
                Spacer(minLength: 8)
                метка
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(раздел.название + ", " + текстСводки)
        .accessibilityHint(текстДействия)
        .accessibilityAddTraits(.isButton)
    }

    private var подпись: some View {
        HStack(spacing: 6) {
            Text(текстСводки)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(размерТекста.isAccessibilitySize ? 3 : 1)
                .multilineTextAlignment(.leading)
                .contentTransition(.opacity)
            if !цвета.isEmpty {
                HStack(spacing: -3) {
                    ForEach(цвета) { цвет in
                        КраскаЦветаДома(цвет: цвет, размер: 12)
                    }
                }
            }
        }
    }

    /// «Изменить ›» у заполненного, «+ Добавить» капсулой у пустого; при крупном шрифте — только значок.
    @ViewBuilder
    private var метка: some View {
        let коротко: Bool = размерТекста.isAccessibilitySize
        if сводка == nil {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.caption.weight(.heavy))
                if !коротко {
                    Text(МоёText.т("my_add"))
                        .lineLimit(1)
                }
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Theme.оттенокАкцента, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
        } else {
            HStack(spacing: 3) {
                if !коротко {
                    Text(т("mh_edit"))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.акцент)
        }
    }
}

// MARK: - Шапка

/// Шапка дома: градиент шапки «Моего», кольцо прогресса дома, «Мой дом», сводка и следующий шаг капсулой.
struct ШапкаДомаМоего: View {
    let прогресс: ПрогрессМоего
    let сводка: String

    init(прогресс: ПрогрессМоего, сводка: String) {
        self.прогресс = прогресс
        self.сводка = сводка
    }

    private var текстШага: String {
        прогресс.шаг.map { МоёText.т($0) } ?? МоёText.т("my_all_set")
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.шапка, style: .continuous)
        HStack(alignment: .center, spacing: 16) {
            КольцоМоего(доля: прогресс.доля, размер: 68, толщина: 6, цвет: Theme.шапкаМята,
                        дорожка: Color.white.opacity(0.15), цветТекста: Color.white, шрифт: 15)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.шапкаМята)
                        .accessibilityHidden(true)
                    Text(МоёText.т("my_home"))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(сводка)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                шаг
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .clipShape(форма)
        }
        .animation(ДвижениеСайта.смена, value: прогресс)
        .animation(ДвижениеСайта.смена, value: сводка)
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(format: МоёText.т("my_ready"), ПроцентМоего.текст(прогресс.доля)))
    }

    private var шаг: some View {
        HStack(spacing: 5) {
            Image(systemName: прогресс.шаг == nil ? "checkmark" : "plus")
                .font(.system(size: 10, weight: .heavy))
                .accessibilityHidden(true)
            Text(текстШага)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.шапкаМятаТекст)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.шапкаМята, in: Capsule())
        .id(прогресс.шаг ?? "done")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - Стиль и цвета

/// Стиль дома и общая палитра — только порядок подборки «Для вас», никогда не отсекают.
struct КарточкаСтиляДома: View {
    let дом: ДомМоего

    init(дом: ДомМоего) {
        self.дом = дом
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    /// Частые цвета комнат — до пяти, по числу комнат.
    private var цветаКомнат: [ЦветСтандарта] {
        var счёт: [ЦветСтандарта: Int] = [:]
        for к in дом.комнаты {
            for (место, ц) in к.палитра.enumerated() { счёт[ц, default: 0] += 10 - место }
        }
        return Array(счёт.sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
            .prefix(5)).map { $0.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_style"), значок: "paintpalette")
            Text(т("mh_style_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ПотокЧипов(зазор: 8) {
                ForEach(СтильДомаМоего.allCases, id: \.self) { стиль in
                    ЧипМоего(стиль.название, выбран: дом.стиль.contains(стиль)) { переключить(стиль) }
                }
            }
            Text(т("mh_colors"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 0) {
                ForEach(ЦветСтандарта.allCases) { цвет in
                    КругЦветаДома(цвет: цвет, выбран: дом.палитра.contains(цвет)) { переключить(цвет) }
                }
            }
            if !цветаКомнат.isEmpty && цветаКомнат != дом.палитра {
                МалаяКнопкаАвтоподбора(заголовок: т("mh_colors_from_rooms"), значок: "square.stack.3d.up") {
                    let собранные = цветаКомнат
                    ОткликСайта.успех()
                    МоёХранилище.shared.обновитьДом { д in д.палитра = собранные }
                }
            }
        }
        .карточкаМоего()
    }

    private func переключить(_ стиль: СтильДомаМоего) {
        ОткликСайта.выбор()
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.стиль.firstIndex(of: стиль) {
                д.стиль.remove(at: i)
            } else {
                д.стиль.append(стиль)
                д.стиль.sort { $0.rawValue < $1.rawValue }
            }
        }
    }

    private func переключить(_ цвет: ЦветСтандарта) {
        guard дом.палитра.contains(цвет) || дом.палитра.count < 5 else {
            ОткликСайта.предупреждение()
            return
        }
        ОткликСайта.выбор()
        МоёХранилище.shared.обновитьДом { д in
            if let i = д.палитра.firstIndex(of: цвет) {
                д.палитра.remove(at: i)
            } else if д.палитра.count < 5 {
                д.палитра.append(цвет)
            }
        }
    }
}

// MARK: - Куплено на Kliko

/// Купленное на Kliko для дома (ВещьМоего с местом «дом») и «Добавить из моих покупок».
struct КарточкаКупленногоДома: View {
    let вещи: [ВещьМоего]
    let дом: ДомМоего

    init(вещи: [ВещьМоего], дом: ДомМоего) {
        self.вещи = вещи
        self.дом = дом
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_bought"), значок: "bag")
            ForEach(вещи) { вещь in
                строка(вещь)
            }
            if Config.покупкиВМоё {
                NavigationLink(value: ЦельМоего.изПокупок) {
                    HStack(spacing: 12) {
                        ЗначокПрофиляМоего(значок: "bag.badge.plus", цвет: Theme.золото, размер: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(МоёText.т("my_deals_title"))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.текст)
                            Text(т("mh_bought_sub"))
                                .font(.caption)
                                .foregroundStyle(Theme.текстВторой)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        СтрелкаСтрокиКабинета()
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеСайта())
            }
        }
        .карточкаМоего()
    }

    private func строка(_ вещь: ВещьМоего) -> some View {
        let комната = вещь.место.раздел == .дом ? дом.имяКомнаты(вещь.место.id) : nil
        let подпись = [вещь.покупка?.подпись, комната].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            ЗначокПрофиляМоего(значок: "shippingbox", цвет: РазделМоего.дом.цвет, размер: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(вещь.название)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                if !подпись.isEmpty {
                    Text(подпись)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 8)
            Menu {
                /* «Продать» купленное (владелец 17.10.2026): название сделки, раздел, стандарты; чужого фото — нет. */
                Button {
                    продать(вещь)
                } label: {
                    Label(ПродатьМоёText.т("msl_sell"), systemImage: "tag")
                }
                Button(role: .destructive) {
                    убрать(вещь.id)
                } label: {
                    Label(т("mh_bought_remove"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(МоёText.т("my_more_actions"))
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: ПродатьМоёText.т("msl_sell")) { продать(вещь) }
        .accessibilityAction(named: т("mh_bought_remove")) { убрать(вещь.id) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func убрать(_ id: UUID) {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.вставкаСписка) { МоёХранилище.shared.удалитьВещь(id) }
    }

    /// Мастер подачи уже заполненным (MyThingsSellHome.swift).
    private func продать(_ вещь: ВещьМоего) {
        ОткликСайта.выбор()
        ПереходыГардероба.продать(ПродатьСвоёМоего.купленное(вещь))
    }
}
